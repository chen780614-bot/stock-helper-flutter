import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'names.dart';
import 'ticker.dart';

class QuotesService {
  QuotesService(this._names);
  final NamesService _names;

  Map<String, Map<String, dynamic>>? _twseDayAll;
  Map<String, Map<String, dynamic>>? _tpexDayAll;
  Map<String, Map<String, dynamic>>? _esmDayAll;
  DateTime? _officialLoadedAt;

  /// Taipei cash-market quote window: weekdays 08:30–14:30 inclusive (Asia/Taipei).
  /// Inside: Yahoo / live poll. Outside: official TWSE / TPEx / 興櫃 daily last.
  static bool isTwRegularSession([DateTime? now]) {
    final n = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    if (n.weekday > 5) return false;
    final mins = n.hour * 60 + n.minute;
    const start = 8 * 60 + 30;
    const end = 14 * 60 + 30;
    return mins >= start && mins <= end;
  }

  Future<void> _ensureOfficialDayAll({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _officialLoadedAt != null &&
        now.difference(_officialLoadedAt!).inSeconds < 60 &&
        (_twseDayAll != null || _tpexDayAll != null || _esmDayAll != null)) {
      return;
    }
    await Future.wait([
      _loadTwseDayAll(),
      _loadTpexDayAll(),
      _loadEsmDayAll(),
    ]);
    if (_twseDayAll != null || _tpexDayAll != null || _esmDayAll != null) {
      _officialLoadedAt = now;
    }
  }

  Future<void> _loadTwseDayAll() async {
    try {
      final uri = Uri.parse(
          'https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL');
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'stock-helper-flutter/1.0',
      }).timeout(const Duration(seconds: 45));
      if (resp.statusCode != 200) return;
      final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      final map = <String, Map<String, dynamic>>{};
      for (final row in list) {
        if (row is! Map) continue;
        final code = '${row['Code'] ?? ''}'.trim();
        if (code.isEmpty) continue;
        map[code] = Map<String, dynamic>.from(row);
      }
      if (map.isNotEmpty) _twseDayAll = map;
    } catch (_) {}
  }

  Future<void> _loadTpexDayAll() async {
    try {
      final uri = Uri.parse(
          'https://www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes');
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'stock-helper-flutter/1.0',
      }).timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) return;
      final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      final map = <String, Map<String, dynamic>>{};
      for (final row in list) {
        if (row is! Map) continue;
        final code = '${row['SecuritiesCompanyCode'] ?? ''}'.trim();
        if (code.isEmpty) continue;
        map[code] = Map<String, dynamic>.from(row);
      }
      if (map.isNotEmpty) _tpexDayAll = map;
    } catch (_) {}
  }

  /// Official 興櫃 snapshot: TPEx OpenAPI tpex_esb_latest_statistics.
  Future<void> _loadEsmDayAll() async {
    try {
      final uri = Uri.parse(
          'https://www.tpex.org.tw/openapi/v1/tpex_esb_latest_statistics');
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'stock-helper-flutter/1.0',
      }).timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) return;
      final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      final map = <String, Map<String, dynamic>>{};
      for (final row in list) {
        if (row is! Map) continue;
        final code = '${row['SecuritiesCompanyCode'] ?? ''}'.trim();
        if (code.isEmpty) continue;
        map[code] = Map<String, dynamic>.from(row);
      }
      if (map.isNotEmpty) _esmDayAll = map;
    } catch (_) {}
  }

  Future<Quote> fetchQuote(String ticker, {bool force = false}) async {
    try {
      if (isTaiwanTicker(ticker)) {
        // Correct .TW/.TWO using OTC + 興櫃 maps (legacy rows may have wrong suffix).
        ticker = _names.normalizeTickerForMarket(ticker);
        // Outside 08:30–14:30 Taipei prefer official daily last / close.
        if (!isTwRegularSession()) {
          final q = await _fetchOfficialTw(ticker, force: force);
          if (q != null && q.ok) return q;
        }
        // In session: Yahoo first for fresher last; fall back official.
        final y = await _fetchYahoo(ticker);
        if (y.ok) return y;
        final q = await _fetchOfficialTw(ticker, force: force);
        if (q != null && q.ok) return q;
        return y;
      }
      return await _fetchYahoo(ticker);
    } catch (e) {
      return Quote(
        ticker: ticker,
        shortName: _names.resolveName(ticker, fallback: ticker),
        price: 0,
        currency: '',
        error: '取得報價失敗（$ticker）：$e',
      );
    }
  }

  Future<Map<String, Quote>> fetchQuotes(List<String> tickers,
      {bool force = false}) async {
    final out = <String, Quote>{};
    for (final t in tickers) {
      out[t] = await fetchQuote(t, force: force);
    }
    return out;
  }

  Future<Quote?> _fetchOfficialTw(String ticker, {bool force = false}) async {
    await _ensureOfficialDayAll(force: force);
    final code = extractTwCode(ticker);
    if (code == null) return null;

    final twse = _twseDayAll?[code];
    if (twse != null) {
      return _quoteFromTwseRow(ticker, twse);
    }
    final tpex = _tpexDayAll?[code];
    if (tpex != null) {
      return _quoteFromTpexRow(ticker, tpex);
    }
    final esm = _esmDayAll?[code];
    if (esm != null) {
      return _quoteFromEsmRow(ticker, esm);
    }
    return null;
  }

  Quote _quoteFromTwseRow(String ticker, Map<String, dynamic> row) {
    final priceStr = '${row['ClosingPrice'] ?? ''}'.replaceAll(',', '');
    final price = double.tryParse(priceStr) ?? 0;
    final name = '${row['Name'] ?? ''}'.trim();
    if (price <= 0) {
      return Quote(
        ticker: ticker,
        shortName: name.isNotEmpty ? name : _names.resolveName(ticker),
        price: 0,
        currency: 'TWD',
        error: '查無報價：$ticker',
      );
    }
    final changeStr =
        '${row['Change'] ?? ''}'.replaceAll(',', '').replaceAll('+', '');
    final change = double.tryParse(changeStr);
    double? prevClose;
    if (change != null) {
      prevClose = price - change;
      if (prevClose <= 0) prevClose = null;
    }
    final outside = !isTwRegularSession();
    return Quote(
      ticker: ticker,
      shortName: name.isNotEmpty
          ? name
          : _names.resolveName(ticker, fallback: ticker),
      price: price,
      currency: 'TWD',
      asOf: DateTime.now(),
      priorClose: outside,
      previousClose: outside && prevClose != null
          ? prevClose
          : (outside ? price : prevClose),
    );
  }

  Quote _quoteFromTpexRow(String ticker, Map<String, dynamic> row) {
    final priceStr = '${row['Close'] ?? ''}'.replaceAll(',', '').trim();
    final price = double.tryParse(priceStr) ?? 0;
    final name = '${row['CompanyName'] ?? ''}'.trim();
    if (price <= 0) {
      return Quote(
        ticker: ticker,
        shortName: name.isNotEmpty ? name : _names.resolveName(ticker),
        price: 0,
        currency: 'TWD',
        error: '查無報價：$ticker',
      );
    }
    final changeStr =
        '${row['Change'] ?? ''}'.replaceAll(',', '').replaceAll('+', '').trim();
    final change = double.tryParse(changeStr);
    double? prevClose;
    if (change != null) {
      prevClose = price - change;
      if (prevClose <= 0) prevClose = null;
    }
    final outside = !isTwRegularSession();
    return Quote(
      ticker: ticker,
      shortName: name.isNotEmpty
          ? name
          : _names.resolveName(ticker, fallback: ticker),
      price: price,
      currency: 'TWD',
      asOf: DateTime.now(),
      priorClose: outside,
      previousClose: outside && prevClose != null
          ? prevClose
          : (outside ? price : prevClose),
    );
  }

  Quote _quoteFromEsmRow(String ticker, Map<String, dynamic> row) {
    // 興櫃 official last = LatestPrice; fall back to 日均價 Average.
    final lastStr = '${row['LatestPrice'] ?? ''}'.replaceAll(',', '').trim();
    final avgStr = '${row['Average'] ?? ''}'.replaceAll(',', '').trim();
    var price = double.tryParse(lastStr) ?? 0;
    if (price <= 0) {
      price = double.tryParse(avgStr) ?? 0;
    }
    final name = '${row['CompanyName'] ?? ''}'.trim();
    if (price <= 0) {
      return Quote(
        ticker: ticker,
        shortName: name.isNotEmpty ? name : _names.resolveName(ticker),
        price: 0,
        currency: 'TWD',
        error: '查無報價：$ticker',
      );
    }
    final prevStr =
        '${row['PreviousAveragePrice'] ?? ''}'.replaceAll(',', '').trim();
    final prevClose = double.tryParse(prevStr);
    final outside = !isTwRegularSession();
    final usablePrev = prevClose != null && prevClose > 0 ? prevClose : null;
    return Quote(
      ticker: ticker,
      shortName: name.isNotEmpty
          ? name
          : _names.resolveName(ticker, fallback: ticker),
      price: price,
      currency: 'TWD',
      asOf: DateTime.now(),
      priorClose: outside,
      previousClose: outside
          ? (usablePrev ?? price)
          : usablePrev,
    );
  }

  Future<Quote> _fetchYahoo(String ticker) async {
    final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=1d&range=5d');
    final resp = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      return Quote(
        ticker: ticker,
        shortName: _names.resolveName(ticker, fallback: ticker),
        price: 0,
        currency: isTaiwanTicker(ticker) ? 'TWD' : 'USD',
        error: '查無報價：$ticker',
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final chart = data['chart'] as Map<String, dynamic>?;
    final result = (chart?['result'] as List?)?.cast<dynamic>();
    if (result == null || result.isEmpty) {
      return Quote(
        ticker: ticker,
        shortName: _names.resolveName(ticker, fallback: ticker),
        price: 0,
        currency: isTaiwanTicker(ticker) ? 'TWD' : 'USD',
        error: '查無報價：$ticker',
      );
    }
    final r0 = result.first as Map<String, dynamic>;
    final meta = Map<String, dynamic>.from(r0['meta'] as Map);
    final regular = (meta['regularMarketPrice'] as num?)?.toDouble();
    final prev = (meta['previousClose'] as num?)?.toDouble() ??
        (meta['chartPreviousClose'] as num?)?.toDouble();
    final state = '${meta['marketState'] ?? ''}';
    final inRegular = state == 'REGULAR';
    final priorClose = !inRegular && prev != null && prev > 0;
    final price = inRegular
        ? (regular ?? prev ?? 0)
        : (prev ?? regular ?? 0);
    final currency =
        '${meta['currency'] ?? (isTaiwanTicker(ticker) ? 'TWD' : 'USD')}';
    final name = _names.resolveName(ticker,
        fallback: '${meta['symbol'] ?? ticker}');
    final ts = meta['regularMarketTime'];
    DateTime? asOf;
    if (ts is num) {
      asOf = DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000, isUtc: true)
          .toLocal();
    }
    if (price <= 0) {
      return Quote(
        ticker: ticker,
        shortName: name,
        price: 0,
        currency: currency,
        error: '無效價格：$ticker',
      );
    }
    // When we display prior close as price, day P&L vs that close is ~0.
    final prevCloseVal = (prev != null && prev > 0) ? prev : null;
    final effectivePrev = priorClose ? price : prevCloseVal;
    return Quote(
      ticker: ticker,
      shortName: name,
      price: price,
      currency: currency,
      asOf: asOf ?? DateTime.now(),
      priorClose: priorClose,
      previousClose: effectivePrev,
    );
  }
}
