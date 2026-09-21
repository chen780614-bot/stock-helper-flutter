import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:http/http.dart' as http;

import 'securities_db.dart';
import 'securities_models.dart';
import 'securities_validator.dart';

typedef MarketFetcher = Future<FetchPayload> Function(TwMarket market, String now);

class FetchPayload {
  const FetchPayload({
    required this.httpOk,
    required this.rows,
    required this.source,
    this.errorMessage = '',
  });

  final bool httpOk;
  final List<Map<String, Object?>> rows;
  final String source;
  final String errorMessage;
}

/// Syncs official TW securities masters into SQLite — per market, staged,
/// validated, transactional. Quotes APIs are NEVER existence authority.
class SecuritiesSync {
  SecuritiesSync(
    this.db, {
    http.Client? client,
    SecuritiesValidator? validator,
    MarketFetcher? fetcherOverride,
  })  : _client = client ?? http.Client(),
        _validator = validator ?? const SecuritiesValidator(),
        _fetcherOverride = fetcherOverride,
        _ownsClient = client == null;

  final SecuritiesSyncStore db;
  final http.Client _client;
  final SecuritiesValidator _validator;
  final MarketFetcher? _fetcherOverride;
  final bool _ownsClient;

  static const _ua = 'stock-helper-flutter/1.4';

  void close() {
    if (_ownsClient) _client.close();
  }

  /// Sync each market independently. One failure does not undo others.
  Future<OverallSyncResult> sync({bool force = false}) async {
    final now = DateTime.now().toIso8601String();
    final outcomes = <MarketSyncOutcome>[];
    for (final market in TwMarket.values) {
      outcomes.add(await syncMarket(market, force: force, nowIso: now));
    }
    await db.ensureBuiltinAliases();
    await db.refreshAggregateMeta();
    return OverallSyncResult(markets: outcomes, completedAt: now);
  }

  Future<MarketSyncOutcome> syncMarket(
    TwMarket market, {
    bool force = false,
    String? nowIso,
  }) async {
    final now = nowIso ?? DateTime.now().toIso8601String();
    await db.writeMarketMeta(market, lastAttemptAt: now);

    try {
      final payload = _fetcherOverride != null
          ? await _fetcherOverride(market, now)
          : await _fetchMarket(market, now);

      if (!payload.httpOk) {
        final msg = payload.errorMessage.isNotEmpty
            ? payload.errorMessage
            : 'HTTP 失敗，已保留舊資料';
        await db.writeMarketMeta(
          market,
          lastAttemptAt: now,
          errorMessage: msg,
        );
        final meta = await db.readMarketMeta(market);
        return MarketSyncOutcome(
          market: market,
          success: false,
          recordCount: meta.recordCount,
          source: meta.source,
          errorMessage: msg,
          skipped: false,
        );
      }

      final prior = await db.readMarketMeta(market);
      final lastCount = prior.recordCount > 0
          ? prior.recordCount
          : await db.countForMarket(market, activeOnly: true);

      final staged = List<Map<String, Object?>>.from(payload.rows);
      final validated = _validator.validate(
        market: market,
        httpOk: true,
        staged: staged,
        lastSuccessfulCount: lastCount,
      );

      if (!validated.ok) {
        await db.writeMarketMeta(
          market,
          lastAttemptAt: now,
          errorMessage: validated.errorMessage,
          // Do NOT touch record_count / last_success_at / is_active.
        );
        return MarketSyncOutcome(
          market: market,
          success: false,
          recordCount: prior.recordCount,
          source: prior.source,
          errorMessage: validated.errorMessage,
          skipped: false,
        );
      }

      await db.commitMarketUpdate(
        market: market,
        rows: validated.rows,
        nowIso: now,
        source: payload.source,
      );

      final after = await db.readMarketMeta(market);
      return MarketSyncOutcome(
        market: market,
        success: true,
        recordCount: after.recordCount,
        source: after.source,
        errorMessage: '',
        skipped: false,
      );
    } catch (e) {
      final msg = e.toString();
      await db.writeMarketMeta(
        market,
        lastAttemptAt: now,
        errorMessage: msg,
      );
      final meta = await db.readMarketMeta(market);
      return MarketSyncOutcome(
        market: market,
        success: false,
        recordCount: meta.recordCount,
        source: meta.source,
        errorMessage: msg,
        skipped: false,
      );
    }
  }

  Future<FetchPayload> _fetchMarket(TwMarket market, String now) async {
    switch (market) {
      case TwMarket.twse:
        return _fetchTwse(now);
      case TwMarket.tpex:
        return _fetchTpex(now);
      case TwMarket.emerging:
        return _fetchEmerging(now);
    }
  }

  Future<FetchPayload> _fetchTwse(String now) async {
    final uri =
        Uri.parse('https://openapi.twse.com.tw/v1/opendata/t187ap03_L');
    final resp = await _client
        .get(uri, headers: {'Accept': 'application/json', 'User-Agent': _ua})
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      return FetchPayload(
        httpOk: false,
        rows: const [],
        source: 'TWSE:t187ap03_L',
        errorMessage: 'HTTP ${resp.statusCode}',
      );
    }
    final list = jsonDecode(utf8.decode(resp.bodyBytes));
    if (list is! List) {
      return const FetchPayload(
        httpOk: true,
        rows: [],
        source: 'TWSE:t187ap03_L',
        errorMessage: 'JSON 非陣列',
      );
    }
    final out = <Map<String, Object?>>[];
    for (final row in list) {
      if (row is! Map) continue;
      final code = '${row['公司代號'] ?? ''}'.trim().toUpperCase();
      final name = '${row['公司簡稱'] ?? row['公司名稱'] ?? ''}'.trim();
      final full = '${row['公司名稱'] ?? ''}'.trim();
      if (!_looksLikeCode(code) || name.isEmpty) continue;
      out.add(_row(
        code: code,
        name: name,
        fullName: full,
        market: TwMarket.twse,
        type: _inferType(code, name, ''),
        industry: '${row['產業別'] ?? ''}'.trim(),
        source: 'TWSE:t187ap03_L',
        now: now,
      ));
    }
    return FetchPayload(httpOk: true, rows: out, source: 'TWSE:t187ap03_L');
  }

  Future<FetchPayload> _fetchTpex(String now) async {
    final uri = Uri.parse(
        'https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap03_O');
    final resp = await _client
        .get(uri, headers: {'Accept': 'application/json', 'User-Agent': _ua})
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      return FetchPayload(
        httpOk: false,
        rows: const [],
        source: 'TPEX:mopsfin_t187ap03_O',
        errorMessage: 'HTTP ${resp.statusCode}',
      );
    }
    final list = jsonDecode(utf8.decode(resp.bodyBytes));
    if (list is! List) {
      return const FetchPayload(
        httpOk: true,
        rows: [],
        source: 'TPEX:mopsfin_t187ap03_O',
        errorMessage: 'JSON 非陣列',
      );
    }
    final out = <Map<String, Object?>>[];
    for (final row in list) {
      if (row is! Map) continue;
      final code =
          '${row['SecuritiesCompanyCode'] ?? row['公司代號'] ?? ''}'
              .trim()
              .toUpperCase();
      final name =
          '${row['CompanyAbbreviation'] ?? row['CompanyName'] ?? row['公司簡稱'] ?? ''}'
              .trim();
      final full = '${row['CompanyName'] ?? row['公司名稱'] ?? ''}'.trim();
      if (!_looksLikeCode(code) || (name.isEmpty && full.isEmpty)) continue;
      out.add(_row(
        code: code,
        name: name.isNotEmpty ? name : full,
        fullName: full,
        market: TwMarket.tpex,
        type: _inferType(code, name, ''),
        industry: '${row['SecuritiesIndustryCode'] ?? ''}'.trim(),
        source: 'TPEX:mopsfin_t187ap03_O',
        now: now,
      ));
    }
    return FetchPayload(
      httpOk: true,
      rows: out,
      source: 'TPEX:mopsfin_t187ap03_O',
    );
  }

  Future<FetchPayload> _fetchEmerging(String now) async {
    try {
      final rows = await _fetchIsinMode(5, TwMarket.emerging, now);
      return FetchPayload(
        httpOk: true,
        rows: rows,
        source: 'ISIN:mode5',
      );
    } catch (e) {
      return FetchPayload(
        httpOk: false,
        rows: const [],
        source: 'ISIN:mode5',
        errorMessage: e.toString(),
      );
    }
  }

  Future<List<Map<String, Object?>>> _fetchIsinMode(
    int mode,
    TwMarket market,
    String now,
  ) async {
    final uri = Uri.parse(
        'https://isin.twse.com.tw/isin/C_public.jsp?strMode=$mode');
    final resp = await _client
        .get(uri, headers: {'User-Agent': _ua, 'Accept': 'text/html'})
        .timeout(const Duration(seconds: 90));
    if (resp.statusCode != 200) {
      throw StateError('HTTP ${resp.statusCode}');
    }
    final decoded = await _decodeBig5(resp.bodyBytes);
    final re = RegExp(
      r'>(\d{4,6}[A-Z]{0,2})\u3000([^<]+)</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>',
      caseSensitive: false,
    );
    final out = <Map<String, Object?>>[];
    for (final m in re.allMatches(decoded)) {
      final code = m.group(1)!.toUpperCase();
      final name = m.group(2)!.trim();
      final isin = m.group(3)!.trim();
      final listing = m.group(4)!.trim();
      final industry = m.group(6)!.trim();
      if (!_looksLikeCode(code) || name.isEmpty) continue;
      out.add(_row(
        code: code,
        name: name,
        fullName: name,
        market: market,
        type: _inferType(code, name, industry),
        industry: industry,
        isin: isin,
        listingDate: listing,
        source: 'ISIN:mode$mode',
        now: now,
      ));
    }
    return out;
  }

  Map<String, Object?> _row({
    required String code,
    required String name,
    required String fullName,
    required TwMarket market,
    required SecurityType type,
    required String source,
    required String now,
    String industry = '',
    String isin = '',
    String listingDate = '',
  }) {
    return {
      'code': code,
      'name': name,
      'full_name': fullName,
      'english_name': '',
      'market': market.code,
      'security_type': type.code,
      'industry': industry,
      'isin': isin,
      'currency': 'TWD',
      'yahoo_symbol': yahooSymbolFor(code, market),
      'is_active': 1,
      'listing_date': listingDate,
      'delisting_date': '',
      'source': source,
      'last_updated': now,
      'normalized_name': normalizeSearchKey(name),
    };
  }

  bool _looksLikeCode(String code) =>
      SecuritiesValidator.codePattern.hasMatch(code);

  SecurityType _inferType(String code, String name, String industry) {
    final blob = '$name $industry';
    if (blob.contains('認購') ||
        blob.contains('認售') ||
        blob.contains('權證') ||
        blob.contains('牛證') ||
        blob.contains('熊證')) {
      return SecurityType.warrant;
    }
    if (blob.contains('ETN') || name.endsWith('ETN')) {
      return SecurityType.etn;
    }
    if (blob.contains('ETF') ||
        (code.startsWith('00') && code.length >= 4) ||
        name.contains('基金')) {
      if (blob.contains('ETF') || code.startsWith('00')) {
        return SecurityType.etf;
      }
    }
    if (blob.contains('特別股') ||
        (RegExp(r'[A-Z]$').hasMatch(code) && blob.contains('特'))) {
      return SecurityType.preferred;
    }
    if (blob.contains('TDR') || blob.contains('存託憑證')) {
      return SecurityType.tdr;
    }
    return SecurityType.stock;
  }

  Future<String> _decodeBig5(List<int> bytes) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      return await CharsetConverter.decode('big5', data);
    } catch (_) {}
    try {
      return await CharsetConverter.decode('CP950', data);
    } catch (_) {}
    try {
      return utf8.decode(data);
    } catch (_) {}
    return latin1.decode(data, allowInvalid: true);
  }
}
