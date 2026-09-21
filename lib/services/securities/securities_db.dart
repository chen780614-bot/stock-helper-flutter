import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'securities_models.dart';

class SecuritiesDb {
  SecuritiesDb._();
  static final SecuritiesDb instance = SecuritiesDb._();
  Database? _db;

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
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
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
      },
    );
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

  Future<int> countRows({bool activeOnly = false}) async {
    final db = await database;
    final sql = activeOnly
        ? "SELECT COUNT(*) AS c FROM securities WHERE is_active = 1 AND security_type != 'WARRANT'"
        : 'SELECT COUNT(*) AS c FROM securities';
    final r = await db.rawQuery(sql);
    return (r.first['c'] as int?) ?? 0;
  }

  /// Upsert by UNIQUE(code, market). Preserves row id (no wipe / no REPLACE).
  Future<void> upsertBatch(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
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
    });
  }

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
}
