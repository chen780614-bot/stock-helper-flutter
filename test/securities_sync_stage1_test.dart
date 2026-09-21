import 'package:flutter_test/flutter_test.dart';
import 'package:stock_helper/services/securities/securities_db.dart';
import 'package:stock_helper/services/securities/securities_models.dart';
import 'package:stock_helper/services/securities/securities_sync.dart';
import 'package:stock_helper/services/securities/securities_validator.dart';

Map<String, Object?> _row(TwMarket m, String code, String name) => {
      'code': code,
      'name': name,
      'full_name': name,
      'english_name': '',
      'market': m.code,
      'security_type': 'STOCK',
      'industry': '',
      'isin': '',
      'currency': 'TWD',
      'yahoo_symbol': yahooSymbolFor(code, m),
      'is_active': 1,
      'listing_date': '',
      'delisting_date': '',
      'source': 'test',
      'last_updated': '2026-09-21T00:00:00.000',
      'normalized_name': normalizeSearchKey(name),
    };

class MemoryStore implements SecuritiesSyncStore {
  final Map<TwMarket, MarketSyncMeta> meta = {
    for (final m in TwMarket.values)
      m: MarketSyncMeta(
        market: m,
        lastSuccessAt: '',
        lastAttemptAt: '',
        recordCount: 0,
        source: '',
        errorMessage: '',
      ),
  };

  /// code|market → row
  final Map<String, Map<String, Object?>> rows = {};

  String _key(TwMarket m, String code) => '${code.toUpperCase()}|${m.code}';

  @override
  Future<MarketSyncMeta> readMarketMeta(TwMarket market) async => meta[market]!;

  @override
  Future<void> writeMarketMeta(
    TwMarket market, {
    String? lastSuccessAt,
    String? lastAttemptAt,
    int? recordCount,
    String? source,
    String? errorMessage,
  }) async {
    final cur = meta[market]!;
    meta[market] = MarketSyncMeta(
      market: market,
      lastSuccessAt: lastSuccessAt ?? cur.lastSuccessAt,
      lastAttemptAt: lastAttemptAt ?? cur.lastAttemptAt,
      recordCount: recordCount ?? cur.recordCount,
      source: source ?? cur.source,
      errorMessage: errorMessage ?? cur.errorMessage,
    );
  }

  @override
  Future<int> countForMarket(TwMarket market, {bool activeOnly = true}) async {
    var n = 0;
    for (final e in rows.entries) {
      if (!e.key.endsWith('|${market.code}')) continue;
      final active = (e.value['is_active'] as int?) ?? 0;
      final type = '${e.value['security_type']}';
      if (activeOnly && (active != 1 || type == 'WARRANT')) continue;
      n++;
    }
    return n;
  }

  @override
  Future<void> commitMarketUpdate({
    required TwMarket market,
    required List<Map<String, Object?>> rows,
    required String nowIso,
    required String source,
  }) async {
    final present = <String>{};
    for (final r in rows) {
      final code = '${r['code']}'.toUpperCase();
      present.add(code);
      this.rows[_key(market, code)] = Map<String, Object?>.from(r)
        ..['is_active'] = 1
        ..['market'] = market.code;
    }
    // Deactivate vanished — never delete.
    for (final e in this.rows.entries.toList()) {
      if (!e.key.endsWith('|${market.code}')) continue;
      final code = e.key.split('|').first;
      if (!present.contains(code) && ((e.value['is_active'] as int?) ?? 0) == 1) {
        e.value['is_active'] = 0;
        e.value['delisting_date'] = nowIso.substring(0, 10);
      }
    }
    final count = await countForMarket(market, activeOnly: true);
    meta[market] = MarketSyncMeta(
      market: market,
      lastSuccessAt: nowIso,
      lastAttemptAt: nowIso,
      recordCount: count,
      source: source,
      errorMessage: '',
    );
  }

  @override
  Future<void> ensureBuiltinAliases() async {}

  @override
  Future<void> refreshAggregateMeta() async {}

  int activeCount(TwMarket market) {
    var n = 0;
    for (final e in rows.entries) {
      if (e.key.endsWith('|${market.code}') &&
          ((e.value['is_active'] as int?) ?? 0) == 1) {
        n++;
      }
    }
    return n;
  }

  bool exists(TwMarket market, String code) =>
      rows.containsKey(_key(market, code));

  bool isActive(TwMarket market, String code) =>
      ((rows[_key(market, code)]?['is_active'] as int?) ?? 0) == 1;
}

List<Map<String, Object?>> _nRows(TwMarket m, int n, {int start = 1000}) {
  return [
    for (var i = 0; i < n; i++)
      _row(m, '${start + i}', '公司$i'),
  ];
}

void main() {
  group('SecuritiesValidator', () {
    const v = SecuritiesValidator();

    test('normal payload passes', () {
      final r = v.validate(
        market: TwMarket.twse,
        httpOk: true,
        staged: _nRows(TwMarket.twse, 10),
        lastSuccessfulCount: 10,
      );
      expect(r.ok, isTrue);
      expect(r.rows.length, 10);
    });

    test('HTTP fail', () {
      final r = v.validate(
        market: TwMarket.twse,
        httpOk: false,
        staged: _nRows(TwMarket.twse, 10),
        lastSuccessfulCount: 10,
      );
      expect(r.ok, isFalse);
      expect(r.errorMessage, contains('HTTP'));
    });

    test('empty data', () {
      final r = v.validate(
        market: TwMarket.twse,
        httpOk: true,
        staged: const [],
        lastSuccessfulCount: 10,
      );
      expect(r.ok, isFalse);
      expect(r.errorMessage, contains('空'));
    });

    test('missing fields filtered / rejected when excessive', () {
      final staged = [
        ..._nRows(TwMarket.twse, 2),
        {'code': '', 'name': '', 'market': 'TWSE'},
        {'code': '', 'name': '', 'market': 'TWSE'},
        {'code': '', 'name': '', 'market': 'TWSE'},
      ];
      final r = v.validate(
        market: TwMarket.twse,
        httpOk: true,
        staged: staged,
        lastSuccessfulCount: 0,
      );
      expect(r.ok, isFalse);
    });

    test('count drop below 70% cancels', () {
      final r = v.validate(
        market: TwMarket.twse,
        httpOk: true,
        staged: _nRows(TwMarket.twse, 6),
        lastSuccessfulCount: 10,
      );
      expect(r.ok, isFalse);
      expect(r.errorMessage, contains('70%'));
    });

    test('duplicates excessive cancel', () {
      final staged = <Map<String, Object?>>[
        for (var i = 0; i < 20; i++) _row(TwMarket.twse, '2330', '台積電'),
      ];
      final r = v.validate(
        market: TwMarket.twse,
        httpOk: true,
        staged: staged,
        lastSuccessfulCount: 0,
      );
      expect(r.ok, isFalse);
      expect(r.errorMessage, contains('重複'));
    });
  });

  group('SecuritiesSync per-market isolation', () {
    late MemoryStore store;

    setUp(() {
      store = MemoryStore();
    });

    test('normal sync commits all markets', () async {
      final sync = SecuritiesSync(
        store,
        fetcherOverride: (m, now) async => FetchPayload(
          httpOk: true,
          rows: _nRows(m, 10, start: m == TwMarket.twse
              ? 1000
              : m == TwMarket.tpex
                  ? 2000
                  : 3000),
          source: 'fake:${m.code}',
        ),
      );
      final result = await sync.sync(force: true);
      expect(result.markets.every((o) => o.success), isTrue);
      expect(store.activeCount(TwMarket.twse), 10);
      expect(store.activeCount(TwMarket.tpex), 10);
      expect(store.activeCount(TwMarket.emerging), 10);
    });

    test('HTTP fail keeps last good data', () async {
      // Seed TWSE
      await store.commitMarketUpdate(
        market: TwMarket.twse,
        rows: _nRows(TwMarket.twse, 10),
        nowIso: '2026-09-20T00:00:00.000',
        source: 'seed',
      );
      final sync = SecuritiesSync(
        store,
        fetcherOverride: (m, now) async {
          if (m == TwMarket.twse) {
            return const FetchPayload(
              httpOk: false,
              rows: [],
              source: 'fake',
              errorMessage: 'HTTP 500',
            );
          }
          return FetchPayload(
            httpOk: true,
            rows: _nRows(m, 5, start: 4000),
            source: 'fake',
          );
        },
      );
      final result = await sync.sync(force: true);
      final twse = result.forMarket(TwMarket.twse)!;
      expect(twse.success, isFalse);
      expect(store.activeCount(TwMarket.twse), 10); // unchanged
      expect(store.meta[TwMarket.twse]!.errorMessage, contains('HTTP'));
      expect(result.forMarket(TwMarket.tpex)!.success, isTrue);
    });

    test('empty data cancels that market only', () async {
      await store.commitMarketUpdate(
        market: TwMarket.tpex,
        rows: _nRows(TwMarket.tpex, 8, start: 5000),
        nowIso: '2026-09-20T00:00:00.000',
        source: 'seed',
      );
      final sync = SecuritiesSync(
        store,
        fetcherOverride: (m, now) async {
          if (m == TwMarket.tpex) {
            return const FetchPayload(httpOk: true, rows: [], source: 'fake');
          }
          return FetchPayload(
            httpOk: true,
            rows: _nRows(m, 5, start: 6000),
            source: 'fake',
          );
        },
      );
      final result = await sync.sync(force: true);
      expect(result.forMarket(TwMarket.tpex)!.success, isFalse);
      expect(store.activeCount(TwMarket.tpex), 8);
      expect(result.forMarket(TwMarket.twse)!.success, isTrue);
    });

    test('single market fail others succeed', () async {
      final sync = SecuritiesSync(
        store,
        fetcherOverride: (m, now) async {
          if (m == TwMarket.emerging) {
            return const FetchPayload(
              httpOk: false,
              rows: [],
              source: 'fake',
              errorMessage: 'down',
            );
          }
          return FetchPayload(
            httpOk: true,
            rows: _nRows(m, 12, start: (m.index + 1) * 1000),
            source: 'fake',
          );
        },
      );
      final result = await sync.sync(force: true);
      expect(result.forMarket(TwMarket.twse)!.success, isTrue);
      expect(result.forMarket(TwMarket.tpex)!.success, isTrue);
      expect(result.forMarket(TwMarket.emerging)!.success, isFalse);
      expect(store.activeCount(TwMarket.emerging), 0);
    });

    test('<70% count drop cancels update', () async {
      await store.commitMarketUpdate(
        market: TwMarket.twse,
        rows: _nRows(TwMarket.twse, 100),
        nowIso: '2026-09-20T00:00:00.000',
        source: 'seed',
      );
      final sync = SecuritiesSync(
        store,
        fetcherOverride: (m, now) async {
          if (m != TwMarket.twse) {
            return FetchPayload(
              httpOk: true,
              rows: _nRows(m, 5, start: 7000),
              source: 'fake',
            );
          }
          return FetchPayload(
            httpOk: true,
            rows: _nRows(TwMarket.twse, 50), // 50% < 70%
            source: 'fake',
          );
        },
      );
      final result = await sync.sync(force: true);
      expect(result.forMarket(TwMarket.twse)!.success, isFalse);
      expect(store.activeCount(TwMarket.twse), 100);
      expect(result.forMarket(TwMarket.twse)!.errorMessage, contains('70%'));
    });

    test('new + delisted: inactive not delete', () async {
      await store.commitMarketUpdate(
        market: TwMarket.twse,
        rows: [
          _row(TwMarket.twse, '1101', '台泥'),
          _row(TwMarket.twse, '1102', '亞泥'),
        ],
        nowIso: '2026-09-20T00:00:00.000',
        source: 'seed',
      );
      final sync = SecuritiesSync(
        store,
        fetcherOverride: (m, now) async {
          if (m != TwMarket.twse) {
            return FetchPayload(
              httpOk: true,
              rows: _nRows(m, 3, start: 8000),
              source: 'fake',
            );
          }
          return FetchPayload(
            httpOk: true,
            rows: [
              _row(TwMarket.twse, '1101', '台泥'),
              _row(TwMarket.twse, '2330', '台積電'), // new
              // 1102 vanished
            ],
            source: 'fake',
          );
        },
      );
      await sync.sync(force: true);
      expect(store.exists(TwMarket.twse, '1102'), isTrue);
      expect(store.isActive(TwMarket.twse, '1102'), isFalse);
      expect(store.isActive(TwMarket.twse, '1101'), isTrue);
      expect(store.isActive(TwMarket.twse, '2330'), isTrue);
    });

    test('API failure does not mark market inactive', () async {
      await store.commitMarketUpdate(
        market: TwMarket.twse,
        rows: _nRows(TwMarket.twse, 5),
        nowIso: '2026-09-20T00:00:00.000',
        source: 'seed',
      );
      final before = store.activeCount(TwMarket.twse);
      final sync = SecuritiesSync(
        store,
        fetcherOverride: (m, now) async => const FetchPayload(
          httpOk: false,
          rows: [],
          source: 'fake',
          errorMessage: 'timeout',
        ),
      );
      await sync.syncMarket(TwMarket.twse, force: true);
      expect(store.activeCount(TwMarket.twse), before);
      for (var i = 0; i < 5; i++) {
        expect(store.isActive(TwMarket.twse, '${1000 + i}'), isTrue);
      }
    });
  });

  group('calendar day helper', () {
    test('same local day', () {
      final now = DateTime(2026, 9, 21, 16, 0);
      expect(
        isSameLocalCalendarDay('2026-09-21T01:00:00.000', now),
        isTrue,
      );
      expect(
        isSameLocalCalendarDay('2026-09-20T23:00:00.000', now),
        isFalse,
      );
      expect(isSameLocalCalendarDay('', now), isFalse);
    });
  });
}
