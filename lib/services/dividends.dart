import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ticker.dart';

const _cacheKey = 'exdiv_cache_v2';
const _cacheTtl = Duration(hours: 6);

/// One row from TWSE TWT48U_ALL or TPEx tpex_exright_prepost.
class ExDividendEvent {
  ExDividendEvent({
    required this.code,
    required this.name,
    required this.exDate,
    required this.kind,
    required this.market,
    this.cashDividend,
    this.stockDividendRatio,
    this.paymentDate,
  });

  final String code;
  final String name;

  /// Gregorian calendar date (Taipei calendar day).
  final DateTime exDate;

  /// 除息 / 除權 / 除權息 / 權 / 息 …
  final String kind;

  /// `twse` (上市) or `tpex` (上櫃).
  final String market;

  /// 現金股利（元／股）；null if not disclosed on the table.
  final double? cashDividend;

  /// 每股無償配股率；預估可配股數 = 持股股數 × 此值。
  final double? stockDividendRatio;

  /// 發放日：公開預告表通常未列；保留欄位供未來擴充。
  final DateTime? paymentDate;

  String get marketLabel => market == 'tpex' ? '上櫃' : '上市';

  /// 預估可領現金 = 持股股數 × 每股現金股利（四捨五入至整元）。
  double? estimatedCash(double shares) {
    final d = cashDividend;
    if (d == null || d <= 0 || shares <= 0) return null;
    return (d * shares).roundToDouble();
  }

  /// Exact product before rounding (for formula display).
  double? estimatedCashExact(double shares) {
    final d = cashDividend;
    if (d == null || d <= 0 || shares <= 0) return null;
    return d * shares;
  }

  /// 預估可配股數 = 持股股數 × 每股無償配股率。
  double? estimatedStockShares(double shares) {
    final r = stockDividendRatio;
    if (r == null || r <= 0 || shares <= 0) return null;
    return shares * r;
  }

  /// Upcoming event used for countdown: payment date if future, else ex-date.
  DateTime get countdownDate {
    final today = _dateOnly(DateTime.now());
    final pay = paymentDate == null ? null : _dateOnly(paymentDate!);
    if (pay != null && !pay.isBefore(today)) return pay;
    return _dateOnly(exDate);
  }

  String get countdownLabel {
    final today = _dateOnly(DateTime.now());
    final ex = _dateOnly(exDate);
    if (ex.isBefore(today)) return '除權息日已過';
    final pay = paymentDate == null ? null : _dateOnly(paymentDate!);
    if (pay != null && !pay.isBefore(today)) return '距發放日';
    return '距除權息日';
  }

  int get daysUntilCountdown {
    final today = _dateOnly(DateTime.now());
    final ex = _dateOnly(exDate);
    if (ex.isBefore(today)) {
      // Negative days = how many days past ex-date.
      return ex.difference(today).inDays;
    }
    final target = countdownDate;
    return target.difference(today).inDays;
  }

  /// True while still shown in the 2-day post-ex window.
  bool get isPastExDate {
    final today = _dateOnly(DateTime.now());
    return _dateOnly(exDate).isBefore(today);
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Parse ROC YYYYMMDD (e.g. 1150914) or Gregorian YYYYMMDD.
DateTime? parseTwDate(String raw) {
  final s = raw.trim().replaceAll('/', '').replaceAll('-', '');
  if (s.length != 7 && s.length != 8) return null;
  try {
    if (s.length == 7) {
      // ROC: YYYMMDD
      final y = int.parse(s.substring(0, 3)) + 1911;
      final m = int.parse(s.substring(3, 5));
      final d = int.parse(s.substring(5, 7));
      return DateTime(y, m, d);
    }
    final y = int.parse(s.substring(0, 4));
    final m = int.parse(s.substring(4, 6));
    final d = int.parse(s.substring(6, 8));
    return DateTime(y, m, d);
  } catch (_) {
    return null;
  }
}

double? _parsePositiveNum(dynamic raw) {
  final s = '$raw'.trim().replaceAll(',', '');
  if (s.isEmpty || s == '尚未公告') return null;
  final v = double.tryParse(s);
  if (v == null || v <= 0) return null;
  return v;
}

class DividendsService {
  List<ExDividendEvent>? _memory;
  DateTime? _loadedAt;
  bool _lastFetchFailed = false;

  bool get lastFetchFailed => _lastFetchFailed;

  Future<List<ExDividendEvent>> loadEvents({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _memory != null &&
        _loadedAt != null &&
        now.difference(_loadedAt!) < _cacheTtl) {
      return _memory!;
    }

    if (!force) {
      final cached = await _readPrefsCache();
      if (cached != null) {
        _memory = cached;
        _loadedAt = now;
        _lastFetchFailed = false;
        return cached;
      }
    }

    try {
      final results = await Future.wait([
        _fetchTwse(),
        _fetchTpex(),
      ]);
      final twse = results[0];
      final tpex = results[1];
      if (twse == null && tpex == null) {
        _lastFetchFailed = true;
        return _memory ?? await _readPrefsCache() ?? const [];
      }

      final merged = _mergeEvents([
        ...?twse,
        ...?tpex,
      ]);
      merged.sort((a, b) => a.exDate.compareTo(b.exDate));
      _memory = merged;
      _loadedAt = now;
      _lastFetchFailed = false;
      await _writePrefsCache(merged);
      return merged;
    } catch (_) {
      _lastFetchFailed = true;
      final cached = await _readPrefsCache();
      if (cached != null) {
        _memory = cached;
        _loadedAt = now;
        return cached;
      }
      return _memory ?? const [];
    }
  }

  /// Deduplicate by code + exDate; prefer TWSE when both markets report same.
  List<ExDividendEvent> _mergeEvents(List<ExDividendEvent> all) {
    final map = <String, ExDividendEvent>{};
    for (final e in all) {
      final key =
          '${e.code}|${e.exDate.year}${e.exDate.month.toString().padLeft(2, '0')}${e.exDate.day.toString().padLeft(2, '0')}';
      final prev = map[key];
      if (prev == null) {
        map[key] = e;
        continue;
      }
      if (prev.market == 'tpex' && e.market == 'twse') {
        map[key] = e;
      }
    }
    return map.values.toList();
  }

  Future<List<ExDividendEvent>?> _fetchTwse() async {
    try {
      final uri = Uri.parse(
        'https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL',
      );
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'stock-helper-flutter/1.0',
      }).timeout(const Duration(seconds: 45));
      if (resp.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      final events = <ExDividendEvent>[];
      for (final row in list) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final code = '${m['Code'] ?? ''}'.trim();
        if (code.isEmpty) continue;
        final ex = parseTwDate('${m['Date'] ?? ''}');
        if (ex == null) continue;
        final kindRaw = '${m['Exdividend'] ?? ''}'.trim();
        events.add(ExDividendEvent(
          code: code,
          name: '${m['Name'] ?? ''}'.trim(),
          exDate: ex,
          kind: kindRaw.isEmpty ? '除權息' : kindRaw,
          market: 'twse',
          cashDividend: _parsePositiveNum(m['CashDividend']),
          stockDividendRatio: _parsePositiveNum(m['StockDividendRatio']),
          paymentDate: null,
        ));
      }
      return events;
    } catch (_) {
      return null;
    }
  }

  Future<List<ExDividendEvent>?> _fetchTpex() async {
    try {
      final uri = Uri.parse(
        'https://www.tpex.org.tw/openapi/v1/tpex_exright_prepost',
      );
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'stock-helper-flutter/1.0',
      }).timeout(const Duration(seconds: 45));
      if (resp.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      final events = <ExDividendEvent>[];
      for (final row in list) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final code = '${m['SecuritiesCompanyCode'] ?? ''}'.trim();
        if (code.isEmpty) continue;
        final ex = parseTwDate('${m['ExRrightsExDividendDate'] ?? ''}');
        if (ex == null) continue;
        final kindRaw = '${m['ExRrightsExDividend'] ?? ''}'.trim();
        events.add(ExDividendEvent(
          code: code,
          name: '${m['CompanyName'] ?? ''}'.trim(),
          exDate: ex,
          kind: kindRaw.isEmpty ? '除權息' : kindRaw,
          market: 'tpex',
          cashDividend: _parsePositiveNum(m['CashDividend']),
          stockDividendRatio: _parsePositiveNum(m['StockDividendRatio']),
          paymentDate: null,
        ));
      }
      return events;
    } catch (_) {
      return null;
    }
  }

  /// Upcoming (or today) events for held TW codes only.
  Future<List<({ExDividendEvent event, double shares})>> forHoldings({
    required Map<String, double> codeToShares,
    bool force = false,
  }) async {
    if (codeToShares.isEmpty) return [];
    final all = await loadEvents(force: force);
    final today = _dateOnly(DateTime.now());
    final out = <({ExDividendEvent event, double shares})>[];
    for (final e in all) {
      final shares = codeToShares[e.code];
      if (shares == null || shares <= 0) continue;
      // Keep row for 2 calendar days after 除權／除息日 (Taipei day).
      final ex = _dateOnly(e.exDate);
      final daysAfterEx = today.difference(ex).inDays;
      if (daysAfterEx > 2) continue;
      out.add((event: e, shares: shares));
    }
    out.sort((a, b) => a.event.exDate.compareTo(b.event.exDate));
    return out;
  }

  Future<List<ExDividendEvent>?> _readPrefsCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAt = (data['fetchedAt'] as num?)?.toInt() ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - fetchedAt;
      if (age > _cacheTtl.inMilliseconds) return null;
      final list = (data['events'] as List?) ?? const [];
      return list
          .map((e) => _fromCacheMap(Map<String, dynamic>.from(e as Map)))
          .whereType<ExDividendEvent>()
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePrefsCache(List<ExDividendEvent> events) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _cacheKey,
        jsonEncode({
          'fetchedAt': DateTime.now().millisecondsSinceEpoch,
          'events': events.map(_toCacheMap).toList(),
        }),
      );
    } catch (_) {}
  }

  Map<String, dynamic> _toCacheMap(ExDividendEvent e) => {
        'code': e.code,
        'name': e.name,
        'exDate': e.exDate.toIso8601String(),
        'kind': e.kind,
        'market': e.market,
        'cashDividend': e.cashDividend,
        'stockDividendRatio': e.stockDividendRatio,
        'paymentDate': e.paymentDate?.toIso8601String(),
      };

  ExDividendEvent? _fromCacheMap(Map<String, dynamic> m) {
    final ex = DateTime.tryParse('${m['exDate'] ?? ''}');
    if (ex == null) return null;
    final payRaw = m['paymentDate'];
    final market = '${m['market'] ?? 'twse'}';
    return ExDividendEvent(
      code: '${m['code'] ?? ''}',
      name: '${m['name'] ?? ''}',
      exDate: ex,
      kind: '${m['kind'] ?? '除權息'}',
      market: market == 'tpex' ? 'tpex' : 'twse',
      cashDividend: (m['cashDividend'] as num?)?.toDouble(),
      stockDividendRatio: (m['stockDividendRatio'] as num?)?.toDouble(),
      paymentDate: payRaw is String ? DateTime.tryParse(payRaw) : null,
    );
  }
}

/// Build code→shares map from tickers like 2330.TW / 6488.TWO.
Map<String, double> holdingSharesByTwCode(
  Iterable<({String ticker, double shares})> holdings,
) {
  final map = <String, double>{};
  for (final h in holdings) {
    final code = extractTwCode(h.ticker);
    if (code == null) continue;
    map[code] = (map[code] ?? 0) + h.shares;
  }
  return map;
}
