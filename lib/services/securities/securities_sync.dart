import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:http/http.dart' as http;

import 'securities_db.dart';
import 'securities_models.dart';

/// Syncs official TW securities masters into SQLite.
/// Quotes APIs are NEVER used as existence authority.
class SecuritiesSync {
  SecuritiesSync(this.db);
  final SecuritiesDb db;

  static const _ua = 'stock-helper-flutter/1.4';

  Future<SyncMeta> sync({bool force = false}) async {
    final now = DateTime.now().toIso8601String();
    await db.writeMeta(lastAttemptAt: now);
    try {
      final rows = <Map<String, Object?>>[];
      final keys = <String>{};
      final sources = <String>[];

      final twse = await _fetchTwseCompanies(now);
      if (twse.isNotEmpty) {
        rows.addAll(twse);
        sources.add('TWSE:t187ap03_L');
      }

      final tpex = await _fetchTpexCompanies(now);
      if (tpex.isNotEmpty) {
        rows.addAll(tpex);
        sources.add('TPEX:mopsfin_t187ap03_O');
      }

      final isin = await _fetchIsinAll(now);
      if (isin.isNotEmpty) {
        final byKey = {
          for (final r in rows) '${r['code']}|${r['market']}': r
        };
        for (final r in isin) {
          final k = '${r['code']}|${r['market']}';
          final prev = byKey[k];
          if (prev == null) {
            byKey[k] = r;
          } else {
            final t = '${r['security_type']}';
            if (t != 'STOCK' && t != 'OTHER') {
              byKey[k] = {
                ...prev,
                ...r,
                'name': (prev['name'] != null && '${prev['name']}'.isNotEmpty)
                    ? prev['name']
                    : r['name'],
              };
            } else {
              byKey[k] = {
                ...prev,
                'isin': (prev['isin'] == null || '${prev['isin']}'.isEmpty)
                    ? r['isin']
                    : prev['isin'],
                'industry': (prev['industry'] == null ||
                        '${prev['industry']}'.isEmpty)
                    ? r['industry']
                    : prev['industry'],
                'listing_date': (prev['listing_date'] == null ||
                        '${prev['listing_date']}'.isEmpty)
                    ? r['listing_date']
                    : prev['listing_date'],
              };
            }
          }
        }
        rows
          ..clear()
          ..addAll(byKey.values);
        sources.add('ISIN:C_public');
      }

      if (rows.isEmpty) {
        await db.writeMeta(
          lastAttemptAt: now,
          lastError: '所有官方來源皆失敗，已保留舊資料',
        );
        return await db.readMeta();
      }

      for (final r in rows) {
        keys.add('${r['code']}|${r['market']}');
      }

      await db.upsertBatch(rows);
      await db.markAbsentInactive(keys, now);
      await db.ensureBuiltinAliases();
      final count = await db.countRows();
      await db.writeMeta(
        lastSuccessAt: now,
        lastAttemptAt: now,
        rowCount: count,
        source: sources.join('+'),
        lastError: '',
      );
      return await db.readMeta();
    } catch (e) {
      await db.writeMeta(
        lastAttemptAt: now,
        lastError: e.toString(),
      );
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> _fetchTwseCompanies(String now) async {
    final uri =
        Uri.parse('https://openapi.twse.com.tw/v1/opendata/t187ap03_L');
    final resp = await http
        .get(uri, headers: {'Accept': 'application/json', 'User-Agent': _ua})
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) return const [];
    final list = jsonDecode(utf8.decode(resp.bodyBytes));
    if (list is! List) return const [];
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
    return out;
  }

  Future<List<Map<String, Object?>>> _fetchTpexCompanies(String now) async {
    final uri = Uri.parse(
        'https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap03_O');
    final resp = await http
        .get(uri, headers: {'Accept': 'application/json', 'User-Agent': _ua})
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) return const [];
    final list = jsonDecode(utf8.decode(resp.bodyBytes));
    if (list is! List) return const [];
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
    return out;
  }

  /// ISIN public tables: mode 2 TWSE, 4 TPEx, 5 Emerging.
  Future<List<Map<String, Object?>>> _fetchIsinAll(String now) async {
    final out = <Map<String, Object?>>[];
    for (final mode in <(int, TwMarket)>[
      (2, TwMarket.twse),
      (4, TwMarket.tpex),
      (5, TwMarket.emerging),
    ]) {
      try {
        out.addAll(await _fetchIsinMode(mode.$1, mode.$2, now));
      } catch (_) {}
    }
    return out;
  }

  Future<List<Map<String, Object?>>> _fetchIsinMode(
    int mode,
    TwMarket market,
    String now,
  ) async {
    final uri = Uri.parse(
        'https://isin.twse.com.tw/isin/C_public.jsp?strMode=$mode');
    final resp = await http
        .get(uri, headers: {'User-Agent': _ua, 'Accept': 'text/html'})
        .timeout(const Duration(seconds: 90));
    if (resp.statusCode != 200) return const [];
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
      RegExp(r'^\d{4,6}[A-Z]{0,2}$').hasMatch(code);

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
