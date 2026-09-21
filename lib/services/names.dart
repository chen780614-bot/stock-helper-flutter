import 'securities/securities_db.dart';
import 'securities/securities_models.dart';
import 'securities/securities_sync.dart';
import 'storage.dart';
import 'ticker.dart';

/// Taiwan securities name / market lookup backed by SQLite master.
/// Public API kept compatible with the previous JSON+quote map service.
class NamesService {
  NamesService(this._storage);
  // ignore: unused_field
  final AppStorage _storage;

  final SecuritiesDb _db = SecuritiesDb.instance;
  late final SecuritiesSync _sync = SecuritiesSync(_db);

  bool _loaded = false;
  bool _refreshing = false;

  /// In-memory hot cache: code → display name (active, non-warrant preferred).
  final Map<String, String> _memory = {};
  final Set<String> _otcCodes = {};
  final Set<String> _esmCodes = {};

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _db.database;
    await _hydrateFromDb();
    _loaded = true;

    final meta = await _db.readMeta();
    final empty = meta.rowCount == 0;
    final stale = _isStale(meta.lastSuccessAt);
    if (empty) {
      // First load: block until we have something (best-effort).
      try {
        await refreshFromMarkets(force: true);
      } catch (_) {}
    } else if (stale) {
      // Background refresh if last success > 24h.
      // ignore: unawaited_futures
      refreshFromMarkets();
    }
  }

  bool _isStale(String lastSuccessAt) {
    if (lastSuccessAt.isEmpty) return true;
    try {
      final t = DateTime.parse(lastSuccessAt);
      return DateTime.now().difference(t) > const Duration(hours: 24);
    } catch (_) {
      return true;
    }
  }

  Future<void> _hydrateFromDb() async {
    final db = await _db.database;
    final rows = await db.query(
      'securities',
      columns: ['code', 'name', 'market', 'is_active', 'security_type'],
      where: "security_type != 'WARRANT'",
      orderBy: 'is_active DESC, market ASC',
    );
    _memory.clear();
    _otcCodes.clear();
    _esmCodes.clear();
    for (final r in rows) {
      final code = '${r['code'] ?? ''}'.trim().toUpperCase();
      final name = '${r['name'] ?? ''}'.trim();
      final market = '${r['market'] ?? ''}';
      final active = ((r['is_active'] as int?) ?? 1) == 1;
      if (code.isEmpty || name.isEmpty) continue;
      // Prefer first (active-first) name for code.
      _memory.putIfAbsent(code, () => name);
      if (!active) continue;
      if (market == 'TPEX') _otcCodes.add(code);
      if (market == 'EMERGING') _esmCodes.add(code);
    }
  }

  /// Refresh from official masters (NOT daily quotes).
  Future<void> refreshFromTwse() => refreshFromMarkets();

  Future<void> refreshFromMarkets({bool force = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await ensureLoaded();
      if (!force) {
        final meta = await _db.readMeta();
        if (meta.rowCount > 0 && !_isStale(meta.lastSuccessAt)) {
          return;
        }
      }
      await _sync.sync(force: force);
      await _hydrateFromDb();
    } finally {
      _refreshing = false;
    }
  }

  Future<SyncMeta> syncNow() async {
    await ensureLoaded();
    final meta = await _sync.sync(force: true);
    await _hydrateFromDb();
    return meta;
  }

  Future<SyncMeta> readSyncMeta() => _db.readMeta();

  Future<int> activeCount() => _db.countRows(activeOnly: true);

  bool isOtcCode(String code) => _otcCodes.contains(code.trim().toUpperCase());

  bool isEsmCode(String code) => _esmCodes.contains(code.trim().toUpperCase());

  bool _isTwoSuffixCode(String code) =>
      _otcCodes.contains(code) || _esmCodes.contains(code);

  /// Yahoo / internal suffix: .TWO for TPEx 上櫃 and 興櫃, .TW for TWSE.
  /// EMERGING also uses .TWO historically for Yahoo; master stores no guess
  /// for yahoo_symbol on EMERGING, but ticker suffix still .TWO for quotes.
  String marketSuffixForCode(String code) =>
      _isTwoSuffixCode(code) ? 'TWO' : 'TW';

  String normalizeTickerForMarket(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty) {
      throw ArgumentError('股票代號不可為空');
    }
    final m1 = kTwSuffixedCode.firstMatch(s);
    if (m1 != null) {
      final code = m1.group(1)!;
      if (_isTwoSuffixCode(code) && m1.group(2) == 'TW') {
        return '$code.TWO';
      }
      if (!_isTwoSuffixCode(code) &&
          m1.group(2) == 'TWO' &&
          _memory.containsKey(code)) {
        return '$code.TW';
      }
      return s;
    }

    if (kTwBareCode.hasMatch(s)) {
      return '$s.${marketSuffixForCode(s)}';
    }

    final m2 = kTwAliasCode.firstMatch(s);
    if (m2 != null) {
      final code = m2.group(1)!;
      return '$code.${marketSuffixForCode(code)}';
    }

    return normalizeTicker(raw);
  }

  String previewLabelForInput(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    try {
      final code = extractTwCode(s);
      if (code != null) {
        final name = _memory[code] ?? '';
        if (name.isNotEmpty) return '$code　$name';
        return code;
      }
      final byName = resolveCodeByName(s);
      if (byName != null) {
        final name = _memory[byName] ?? s;
        return '$byName　$name';
      }
    } catch (_) {}
    return s;
  }

  String? lookup(String ticker) {
    final code = extractTwCode(ticker);
    if (code == null) return null;
    return _memory[code];
  }

  String resolveName(String ticker, {String? fallback}) {
    return lookup(ticker) ?? fallback ?? '';
  }

  /// Resolve bare TW code from a Chinese (or mixed) stock name / alias.
  String? resolveCodeByName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return null;

    // Sync path uses in-memory map (already filtered warrants).
    String? exact;
    for (final e in _memory.entries) {
      if (e.value == name) {
        if (exact == null || e.key.length < exact.length) exact = e.key;
      }
    }
    if (exact != null) return exact;

    final norm = normalizeSearchKey(name);
    // Alias exact via memory scan of common short names already in DB hydrate
    // is incomplete; do a quick sync search if DB is ready.
    // Prefer contains ranking on memory for offline UX.
    final hits = <MapEntry<String, String>>[];
    for (final e in _memory.entries) {
      final v = e.value;
      if (v.isEmpty) continue;
      final vn = normalizeSearchKey(v);
      if (name.contains(v) ||
          v.contains(name) ||
          (norm.isNotEmpty && (vn.contains(norm) || norm.contains(vn)))) {
        hits.add(e);
      }
    }
    if (hits.isEmpty) return null;
    if (hits.length == 1) return hits.first.key;

    hits.sort((a, b) {
      final byLen = b.value.length.compareTo(a.value.length);
      if (byLen != 0) return byLen;
      return a.key.length.compareTo(b.key.length);
    });
    if (hits.length >= 2 && hits[0].value.length == hits[1].value.length) {
      final top = hits[0];
      final equallySpecific =
          hits.where((h) => h.value.length == top.value.length).toList();
      if (equallySpecific.length > 1) {
        final exactish = equallySpecific
            .where((h) => name == h.value || name.contains(h.value))
            .toList();
        if (exactish.length == 1) return exactish.first.key;
      }
    }
    return hits.first.key;
  }

  /// Ranked search (exact code, exact name, prefix, alias, contains).
  Future<List<SecurityRow>> search(String query, {int limit = 40}) async {
    await ensureLoaded();
    return _db.search(query, limit: limit, includeWarrants: false);
  }

  /// For unit tests without Flutter binding when map is injected.
  void debugReplaceMemory(
    Map<String, String> map, {
    Set<String>? otcCodes,
    Set<String>? esmCodes,
  }) {
    _memory
      ..clear()
      ..addAll(map);
    _otcCodes
      ..clear()
      ..addAll(otcCodes ?? {});
    _esmCodes
      ..clear()
      ..addAll(esmCodes ?? {});
    _loaded = true;
  }
}
