import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'securities_models.dart';


/// Minimal store surface used by [SecuritiesSync] (real SQLite or in-memory fake).
abstract class SecuritiesSyncStore {
  Future<MarketSyncMeta> readMarketMeta(TwMarket market);
  Future<void> writeMarketMeta(
    TwMarket market, {
    String? lastSuccessAt,
    String? lastAttemptAt,
    int? recordCount,
    String? source,
    String? errorMessage,
  });
  Future<int> countForMarket(TwMarket market, {bool activeOnly = true});
  Future<void> commitMarketUpdate({
    required TwMarket market,
    required List<Map<String, Object?>> rows,
    required String nowIso,
    required String source,
  });
  Future<void> ensureBuiltinAliases();
  Future<void> refreshAggregateMeta();
}

class SecuritiesDb implements SecuritiesSyncStore {
  SecuritiesDb._();
  static final SecuritiesDb instance = SecuritiesDb._();

  /// Test seam: inject an already-opened DB (e.g. in-memory).
  SecuritiesDb.forTest(this._db);

  Database? _db;

  static const schemaVersion = 2;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'tw_securities_master.db');
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        await _upgradeToV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _upgradeToV2(db);
        }
      },
    );
  }

  Future<void> _createV1(Database db) async {
    await db.execute('''
CREATE TABLE securities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  full_name TEXT NOT NULL DEFAULT '',
  english_name TEXT NOT NULL DEFAULT '',
  market TEXT NOT NULL,
  security_type TEXT NOT NULL,
  industry TEXT NOT NULL DEFAULT '',
  isin TEXT NOT NULL DEFAULT '',
  currency TEXT NOT NULL DEFAULT 'TWD',
  yahoo_symbol TEXT NOT NULL DEFAULT '',
  is_active INTEGER NOT NULL DEFAULT 1,
  listing_date TEXT NOT NULL DEFAULT '',
  delisting_date TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT '',
  last_updated TEXT NOT NULL DEFAULT '',
  normalized_name TEXT NOT NULL DEFAULT '',
  UNIQUE(code, market)
)''');
    await db.execute('CREATE INDEX idx_sec_code ON securities(code)');
    await db.execute('CREATE INDEX idx_sec_name ON securities(name)');
    await db.execute('CREATE INDEX idx_sec_full ON securities(full_name)');
    await db.execute(
        'CREATE INDEX idx_sec_norm ON securities(normalized_name)');
    await db.execute(
        'CREATE INDEX idx_sec_active_type ON securities(is_active, security_type)');
    await db.execute(
        'CREATE INDEX idx_sec_market ON securities(market, is_active)');
    await db.execute('''
CREATE TABLE security_aliases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  security_id INTEGER NOT NULL,
  alias TEXT NOT NULL,
  normalized_alias TEXT NOT NULL,
  alias_type TEXT NOT NULL DEFAULT 'common',
  source TEXT NOT NULL DEFAULT 'builtin',
  FOREIGN KEY(security_id) REFERENCES securities(id) ON DELETE CASCADE
)''');
    await db.execute(
        'CREATE INDEX idx_alias_norm ON security_aliases(normalized_alias)');
    await db.execute('''
CREATE TABLE sync_meta (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  last_success_at TEXT NOT NULL DEFAULT '',
  last_attempt_at TEXT NOT NULL DEFAULT '',
  row_count INTEGER NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT '',
  last_error TEXT NOT NULL DEFAULT ''
)''');
    await db.insert('sync_meta', {
      'id': 1,
      'last_success_at': '',
      'last_attempt_at': '',
      'row_count': 0,
      'source': '',
      'last_error': '',
    });
  }

  Future<void> _upgradeToV2(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS market_sync_meta (
  market TEXT PRIMARY KEY,
  last_success_at TEXT NOT NULL DEFAULT '',
  last_attempt_at TEXT NOT NULL DEFAULT '',
  record_count INTEGER NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT '',
  error_message TEXT NOT NULL DEFAULT ''
)''');
    for (final m in TwMarket.values) {
      await db.insert(
        'market_sync_meta',
        {
          'market': m.code,
          'last_success_at': '',
          'last_attempt_at': '',
          'record_count': 0,
          'source': '',
          'error_message': '',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    // Additive only — never deleteDatabase / wipe user tables.
  }

  Future<SyncMeta> readMeta() async {
    final db = await database;
    final rows = await db.query('sync_meta', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      return const SyncMeta(
        lastSuccessAt: '',
        lastAttemptAt: '',
        rowCount: 0,
        source: '',
        lastError: '',
      );
    }
    final r = rows.first;
    return SyncMeta(
      lastSuccessAt: '${r['last_success_at'] ?? ''}',
      lastAttemptAt: '${r['last_attempt_at'] ?? ''}',
      rowCount: (r['row_count'] as int?) ?? 0,
      source: '${r['source'] ?? ''}',
      lastError: '${r['last_error'] ?? ''}',
    );
  }

  Future<void> writeMeta({
    String? lastSuccessAt,
    String? lastAttemptAt,
    int? rowCount,
    String? source,
    String? lastError,
  }) async {
    final db = await database;
    final cur = await readMeta();
    await db.update(
      'sync_meta',
      {
        'last_success_at': lastSuccessAt ?? cur.lastSuccessAt,
        'last_attempt_at': lastAttemptAt ?? cur.lastAttemptAt,
        'row_count': rowCount ?? cur.rowCount,
        'source': source ?? cur.source,
        'last_error': lastError ?? cur.lastError,
      },
      where: 'id = 1',
    );
  }

  @override
  Future<MarketSyncMeta> readMarketMeta(TwMarket market) async {
    final db = await database;
    final rows = await db.query(
      'market_sync_meta',
      where: 'market = ?',
      whereArgs: [market.code],
      limit: 1,
    );
    if (rows.isEmpty) {
      return MarketSyncMeta(
        market: market,
        lastSuccessAt: '',
        lastAttemptAt: '',
        recordCount: 0,
        source: '',
        errorMessage: '',
      );
    }
    final r = rows.first;
    return MarketSyncMeta(
      market: market,
      lastSuccessAt: '${r['last_success_at'] ?? ''}',
      lastAttemptAt: '${r['last_attempt_at'] ?? ''}',
      recordCount: (r['record_count'] as int?) ?? 0,
      source: '${r['source'] ?? ''}',
      errorMessage: '${r['error_message'] ?? ''}',
    );
  }

  Future<List<MarketSyncMeta>> readAllMarketMeta() async {
    final out = <MarketSyncMeta>[];
    for (final m in TwMarket.values) {
      out.add(await readMarketMeta(m));
    }
    return out;
  }

  @override
  Future<void> writeMarketMeta(
    TwMarket market, {
    String? lastSuccessAt,
    String? lastAttemptAt,
    int? recordCount,
    String? source,
    String? errorMessage,
  }) async {
    final db = await database;
    final cur = await readMarketMeta(market);
    await db.insert(
      'market_sync_meta',
      {
        'market': market.code,
        'last_success_at': lastSuccessAt ?? cur.lastSuccessAt,
        'last_attempt_at': lastAttemptAt ?? cur.lastAttemptAt,
        'record_count': recordCount ?? cur.recordCount,
        'source': source ?? cur.source,
        'error_message': errorMessage ?? cur.errorMessage,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> countRows({bool activeOnly = false}) async {
    final db = await database;
    final sql = activeOnly
        ? "SELECT COUNT(*) AS c FROM securities WHERE is_active = 1 AND security_type != 'WARRANT'"
        : 'SELECT COUNT(*) AS c FROM securities';
    final r = await db.rawQuery(sql);
    return (r.first['c'] as int?) ?? 0;
  }

  @override
  Future<int> countForMarket(TwMarket market, {bool activeOnly = true}) async {
    final db = await database;
    final sql = activeOnly
        ? "SELECT COUNT(*) AS c FROM securities WHERE market = ? AND is_active = 1 AND security_type != 'WARRANT'"
        : 'SELECT COUNT(*) AS c FROM securities WHERE market = ?';
    final r = await db.rawQuery(sql, [market.code]);
    return (r.first['c'] as int?) ?? 0;
  }

  /// Upsert by UNIQUE(code, market). Preserves row id (no wipe / no REPLACE).
  Future<void> upsertBatch(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await _upsertInTxn(txn, rows);
    });
  }

  Future<void> _upsertInTxn(
    Transaction txn,
    List<Map<String, Object?>> rows,
  ) async {
    for (final row in rows) {
      final code = '${row['code']}';
      final market = '${row['market']}';
      final existing = await txn.query(
        'securities',
        columns: ['id'],
        where: 'code = ? AND market = ?',
        whereArgs: [code, market],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('securities', row);
      } else {
        final id = existing.first['id'];
        final update = Map<String, Object?>.from(row)..remove('id');
        await txn.update(
          'securities',
          update,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  /// Commit one market after validation: upsert + deactivate vanished codes
  /// for THAT market only. Never DELETE rows. Rollback on failure.
  @override
  Future<void> commitMarketUpdate({
    required TwMarket market,
    required List<Map<String, Object?>> rows,
    required String nowIso,
    required String source,
  }) async {
    final db = await database;
    final presentCodes = <String>{
      for (final r in rows) '${r['code']}'.toUpperCase(),
    };
    await db.transaction((txn) async {
      await _upsertInTxn(txn, rows);

      final existing = await txn.query(
        'securities',
        columns: ['id', 'code', 'is_active'],
        where: 'market = ?',
        whereArgs: [market.code],
      );
      for (final r in existing) {
        final code = '${r['code']}'.toUpperCase();
        final active = (r['is_active'] as int?) ?? 0;
        if (!presentCodes.contains(code) && active == 1) {
          await txn.update(
            'securities',
            {
              'is_active': 0,
              'delisting_date':
                  nowIso.length >= 10 ? nowIso.substring(0, 10) : nowIso,
              'last_updated': nowIso,
            },
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      }

      final countRow = await txn.rawQuery(
        "SELECT COUNT(*) AS c FROM securities WHERE market = ? AND is_active = 1 AND security_type != 'WARRANT'",
        [market.code],
      );
      final count = (countRow.first['c'] as int?) ?? rows.length;

      await txn.insert(
        'market_sync_meta',
        {
          'market': market.code,
          'last_success_at': nowIso,
          'last_attempt_at': nowIso,
          'record_count': count,
          'source': source,
          'error_message': '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @Deprecated('Use commitMarketUpdate — global markAbsent is unsafe across markets')
  Future<void> markAbsentInactive(
      Set<String> presentKeys, String nowIso) async {
    final db = await database;
    final all = await db.query(
      'securities',
      columns: ['id', 'code', 'market', 'is_active'],
    );
    final batch = db.batch();
    for (final r in all) {
      final key = '${r['code']}|${r['market']}';
      if (!presentKeys.contains(key) && (r['is_active'] as int? ?? 0) == 1) {
        batch.update(
          'securities',
          {
            'is_active': 0,
            'delisting_date':
                nowIso.length >= 10 ? nowIso.substring(0, 10) : nowIso,
            'last_updated': nowIso,
          },
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  SecurityRow mapRow(Map<String, Object?> r) {
    return SecurityRow(
      id: (r['id'] as int?) ?? 0,
      code: '${r['code'] ?? ''}',
      name: '${r['name'] ?? ''}',
      fullName: '${r['full_name'] ?? ''}',
      englishName: '${r['english_name'] ?? ''}',
      market: TwMarketX.tryParse('${r['market']}') ?? TwMarket.twse,
      securityType: SecurityTypeX.tryParse('${r['security_type']}'),
      industry: '${r['industry'] ?? ''}',
      isin: '${r['isin'] ?? ''}',
      currency: '${r['currency'] ?? 'TWD'}',
      yahooSymbol: '${r['yahoo_symbol'] ?? ''}',
      isActive: ((r['is_active'] as int?) ?? 1) == 1,
      listingDate: '${r['listing_date'] ?? ''}',
      delistingDate: '${r['delisting_date'] ?? ''}',
      source: '${r['source'] ?? ''}',
      lastUpdated: '${r['last_updated'] ?? ''}',
      normalizedName: '${r['normalized_name'] ?? ''}',
    );
  }

  Future<List<SecurityRow>> search(
    String query, {
    int limit = 40,
    bool includeWarrants = false,
    bool includeInactive = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final norm = normalizeSearchKey(q);
    final db = await database;
    final typeSql = includeWarrants ? '' : "AND s.security_type != 'WARRANT'";
    final activeSql = includeInactive ? '' : 'AND s.is_active = 1';
    final likeQ = '%$q%';
    final likeNorm = '%$norm%';
    final prefixQ = '$q%';
    final prefixNorm = '$norm%';

    final rows = await db.rawQuery('''
SELECT s.*,
  CASE
    WHEN upper(s.code) = upper(?) THEN 0
    WHEN s.name = ? THEN 1
    WHEN s.normalized_name = ? THEN 2
    WHEN upper(s.code) LIKE upper(?) THEN 3
    WHEN s.name LIKE ? THEN 4
    WHEN s.normalized_name LIKE ? THEN 5
    WHEN EXISTS (
      SELECT 1 FROM security_aliases a
      WHERE a.security_id = s.id AND (
        a.alias = ? OR a.normalized_alias = ? OR a.normalized_alias LIKE ?
      )
    ) THEN 6
    ELSE 7
  END AS rank
FROM securities s
WHERE 1 = 1
  $typeSql
  $activeSql
  AND (
    upper(s.code) LIKE upper(?)
    OR s.name LIKE ?
    OR s.normalized_name LIKE ?
    OR s.full_name LIKE ?
    OR EXISTS (
      SELECT 1 FROM security_aliases a
      WHERE a.security_id = s.id AND (
        a.alias LIKE ? OR a.normalized_alias LIKE ?
      )
    )
  )
ORDER BY rank ASC, s.is_active DESC, length(s.code) ASC, s.code ASC
LIMIT ?
''', [
      q,
      q,
      norm,
      prefixQ,
      prefixQ,
      prefixNorm,
      q,
      norm,
      prefixNorm,
      likeQ,
      likeQ,
      likeNorm,
      likeQ,
      likeQ,
      likeNorm,
      limit,
    ]);
    return rows.map(mapRow).toList();
  }

  Future<List<SecurityRow>> byCode(String code) async {
    final db = await database;
    final rows = await db.query(
      'securities',
      where: "upper(code) = upper(?) AND security_type != 'WARRANT'",
      whereArgs: [code.trim()],
      orderBy: 'is_active DESC, market ASC',
    );
    return rows.map(mapRow).toList();
  }

  Future<SecurityRow?> bestByCode(String code) async {
    final list = await byCode(code);
    if (list.isEmpty) return null;
    for (final s in list) {
      if (s.isActive) return s;
    }
    return list.first;
  }

  Future<SecurityRow?> byCodeAndMarket(String code, TwMarket market) async {
    final db = await database;
    final rows = await db.query(
      'securities',
      where: 'upper(code) = upper(?) AND market = ?',
      whereArgs: [code.trim(), market.code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return mapRow(rows.first);
  }

  @override
  Future<void> ensureBuiltinAliases() async {
    final db = await database;
    const seeds = <List<String>>[
      ['2330', 'TWSE', '台積', 'short'],
      ['2330', 'TWSE', '台灣積體電路', 'full'],
      ['2330', 'TWSE', '台灣積體電路製造', 'full'],
      ['2317', 'TWSE', '鴻海', 'short'],
      ['2412', 'TWSE', '中華電信', 'full'],
      ['2412', 'TWSE', '中華電', 'short'],
      ['0050', 'TWSE', '元大台灣50', 'common'],
      ['0050', 'TWSE', '台灣50', 'common'],
      ['0056', 'TWSE', '元大高股息', 'common'],
      ['2303', 'TWSE', '聯電', 'short'],
      ['2454', 'TWSE', '聯發科', 'short'],
    ];
    for (final s in seeds) {
      final sec = await db.query(
        'securities',
        where: 'code = ? AND market = ?',
        whereArgs: [s[0], s[1]],
        limit: 1,
      );
      if (sec.isEmpty) continue;
      final sid = sec.first['id'];
      final norm = normalizeSearchKey(s[2]);
      final exist = await db.query(
        'security_aliases',
        where: 'security_id = ? AND normalized_alias = ?',
        whereArgs: [sid, norm],
        limit: 1,
      );
      if (exist.isNotEmpty) continue;
      await db.insert('security_aliases', {
        'security_id': sid,
        'alias': s[2],
        'normalized_alias': norm,
        'alias_type': s[3],
        'source': 'builtin',
      });
    }
  }

  /// Refresh aggregate sync_meta from per-market rows (UI backward compat).
  @override
  Future<void> refreshAggregateMeta() async {
    final markets = await readAllMarketMeta();
    var latestSuccess = '';
    var latestAttempt = '';
    final sources = <String>[];
    final errors = <String>[];
    var total = 0;
    for (final m in markets) {
      total += m.recordCount;
      if (m.source.isNotEmpty) sources.add('${m.market.code}:${m.source}');
      if (m.errorMessage.isNotEmpty) {
        errors.add('${m.market.labelZh}:${m.errorMessage}');
      }
      if (m.lastSuccessAt.compareTo(latestSuccess) > 0) {
        latestSuccess = m.lastSuccessAt;
      }
      if (m.lastAttemptAt.compareTo(latestAttempt) > 0) {
        latestAttempt = m.lastAttemptAt;
      }
    }
    final live = await countRows(activeOnly: true);
    await writeMeta(
      lastSuccessAt: latestSuccess,
      lastAttemptAt: latestAttempt,
      rowCount: live > 0 ? live : total,
      source: sources.join('+'),
      lastError: errors.join('；'),
    );
  }
}
