import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import 'ids.dart';
import 'storage.dart';

const kBackupFormat = 'stock_helper_backup';
const kBackupSchemaVersion = 2;

/// Fields that must never be imported from a backup file.
const _privilegeKeys = {
  'token',
  'accessToken',
  'refreshToken',
  'apiKey',
  'password',
  'secret',
  'isAdmin',
  'role',
  'privileges',
  'admin',
  'adsConsent',
  'adMob',
  'adsSdk',
  'session',
  'auth',
  'credential',
  'privateKey',
};

enum BackupConflictStrategy {
  skip, // 跳過
  overwrite, // 覆蓋
  saveAsCopy, // 另存一份
}

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupPayload {
  BackupPayload({
    required this.watchlist,
    required this.holdings,
    required this.sells,
    required this.incomes,
    required this.themeMode,
    this.watchGroups = const [],
    this.holdingGroups = const [],
    this.activeWatchGroupId,
    this.activeHoldingGroupId,
  });

  final List<WatchItem> watchlist;
  final List<Holding> holdings;
  final List<SellRecord> sells;
  final List<IncomeRecord> incomes;
  final String themeMode; // light | dark | system
  final List<WatchGroup> watchGroups;
  final List<HoldingGroup> holdingGroups;
  final String? activeWatchGroupId;
  final String? activeHoldingGroupId;

  Map<String, dynamic> toJson() => {
        'watchlist': watchlist.map((e) => e.toJson()).toList(),
        'holdings': holdings.map((e) => e.toJson()).toList(),
        'sells': sells.map((e) => e.toJson()).toList(),
        'incomes': incomes.map((e) => e.toJson()).toList(),
        'themeMode': themeMode,
        'watchGroups': watchGroups.map((e) => e.toJson()).toList(),
        'holdingGroups': holdingGroups.map((e) => e.toJson()).toList(),
        if (activeWatchGroupId != null) 'activeWatchGroupId': activeWatchGroupId,
        if (activeHoldingGroupId != null)
          'activeHoldingGroupId': activeHoldingGroupId,
      };

  factory BackupPayload.fromJson(Map<String, dynamic> j) {
    final clean = stripPrivilegeFields(j);
    final watch = ((clean['watchlist'] as List?) ?? const [])
        .map((e) => WatchItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final holds = ((clean['holdings'] as List?) ?? const [])
        .map((e) => Holding.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final sells = ((clean['sells'] as List?) ?? const [])
        .map((e) => SellRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final incomes = ((clean['incomes'] as List?) ?? const [])
        .map((e) => IncomeRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final theme = (clean['themeMode'] as String?) ?? 'system';
    final wgs = ((clean['watchGroups'] as List?) ?? const [])
        .map((e) => WatchGroup.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final hgs = ((clean['holdingGroups'] as List?) ?? const [])
        .map((e) => HoldingGroup.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return BackupPayload(
      watchlist: watch,
      holdings: holds,
      sells: sells,
      incomes: incomes,
      themeMode: theme,
      watchGroups: wgs,
      holdingGroups: hgs,
      activeWatchGroupId: clean['activeWatchGroupId'] as String?,
      activeHoldingGroupId: clean['activeHoldingGroupId'] as String?,
    );
  }
}

class BackupEnvelope {
  BackupEnvelope({
    required this.format,
    required this.schemaVersion,
    required this.exportedAt,
    required this.appPackage,
    required this.appVersion,
    required this.payload,
    required this.checksum,
  });

  final String format;
  final int schemaVersion;
  final String exportedAt;
  final String appPackage;
  final String appVersion;
  final BackupPayload payload;
  final String checksum;

  Map<String, dynamic> toJson() => {
        'format': format,
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt,
        'appPackage': appPackage,
        'appVersion': appVersion,
        'payload': payload.toJson(),
        'checksum': checksum,
      };
}

class ImportPreview {
  ImportPreview({
    required this.watchAdded,
    required this.watchChanged,
    required this.watchSkipped,
    required this.holdingsAdded,
    required this.holdingsChanged,
    required this.holdingsSkipped,
    required this.sellsAdded,
    required this.sellsChanged,
    required this.sellsSkipped,
    required this.incomesAdded,
    required this.incomesChanged,
    required this.incomesSkipped,
    required this.themeWillChange,
  });

  final int watchAdded;
  final int watchChanged;
  final int watchSkipped;
  final int holdingsAdded;
  final int holdingsChanged;
  final int holdingsSkipped;
  final int sellsAdded;
  final int sellsChanged;
  final int sellsSkipped;
  final int incomesAdded;
  final int incomesChanged;
  final int incomesSkipped;
  final bool themeWillChange;

  int get totalAdded => watchAdded + holdingsAdded + sellsAdded + incomesAdded;
  int get totalChanged =>
      watchChanged + holdingsChanged + sellsChanged + incomesChanged;
  int get totalSkipped =>
      watchSkipped + holdingsSkipped + sellsSkipped + incomesSkipped;
}

class LocalBackupSnapshot {
  LocalBackupSnapshot({
    required this.watchlist,
    required this.holdings,
    required this.sells,
    required this.incomes,
    required this.themeMode,
    this.watchGroups = const [],
    this.holdingGroups = const [],
    this.activeWatchGroupId,
    this.activeHoldingGroupId,
  });

  final List<WatchItem> watchlist;
  final List<Holding> holdings;
  final List<SellRecord> sells;
  final List<IncomeRecord> incomes;
  final ThemeMode themeMode;
  final List<WatchGroup> watchGroups;
  final List<HoldingGroup> holdingGroups;
  final String? activeWatchGroupId;
  final String? activeHoldingGroupId;
}

/// Deterministic JSON for checksum: sorted object keys, no extra whitespace.
String canonicalJsonEncode(Object? value) {
  final buf = StringBuffer();
  _writeCanonical(buf, value);
  return buf.toString();
}

void _writeCanonical(StringBuffer buf, Object? value) {
  if (value == null) {
    buf.write('null');
    return;
  }
  if (value is bool) {
    buf.write(value ? 'true' : 'false');
    return;
  }
  if (value is num) {
    buf.write(jsonEncode(value));
    return;
  }
  if (value is String) {
    buf.write(jsonEncode(value));
    return;
  }
  if (value is List) {
    buf.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) buf.write(',');
      _writeCanonical(buf, value[i]);
    }
    buf.write(']');
    return;
  }
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    buf.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) buf.write(',');
      final k = keys[i];
      buf.write(jsonEncode(k));
      buf.write(':');
      _writeCanonical(buf, value[k]);
    }
    buf.write('}');
    return;
  }
  buf.write(jsonEncode(value.toString()));
}

String sha256HexOfCanonicalPayload(Map<String, dynamic> payload) {
  final canonical = canonicalJsonEncode(payload);
  return sha256.convert(utf8.encode(canonical)).toString();
}

Map<String, dynamic> stripPrivilegeFields(Map<String, dynamic> input) {
  final out = <String, dynamic>{};
  for (final e in input.entries) {
    if (_privilegeKeys.contains(e.key)) continue;
    final v = e.value;
    if (v is Map) {
      out[e.key] = stripPrivilegeFields(Map<String, dynamic>.from(v));
    } else if (v is List) {
      out[e.key] = v.map((item) {
        if (item is Map) {
          return stripPrivilegeFields(Map<String, dynamic>.from(item));
        }
        return item;
      }).toList();
    } else {
      out[e.key] = v;
    }
  }
  return out;
}

Map<String, dynamic> migratePayloadToV1(Map<String, dynamic> raw, int fromVersion) {
  var data = stripPrivilegeFields(raw);
  if (fromVersion > kBackupSchemaVersion) {
    throw BackupException('備份 schema 版本過新（$fromVersion），請更新 App 後再匯入');
  }
  // v0 / missing → v1: ensure entity ids; drop excluded caches if present.
  data.remove('namesCache');
  data.remove('tw_names_cache');
  data.remove('quoteCache');
  data.remove('quotes');
  data.remove('logs');
  data.remove('tokens');
  data.remove('ads');

  List<Map<String, dynamic>> asMaps(dynamic list) =>
      ((list as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  final watch = asMaps(data['watchlist']);
  for (final w in watch) {
    w['id'] = ensureEntityId(w['id'] as String?);
    w.removeWhere((k, _) => _privilegeKeys.contains(k));
  }
  data['watchlist'] = watch;

  final holds = asMaps(data['holdings']);
  for (final h in holds) {
    h['id'] = ensureEntityId(h['id'] as String?);
    h.removeWhere((k, _) => _privilegeKeys.contains(k));
  }
  data['holdings'] = holds;

  final sells = asMaps(data['sells']);
  for (final s in sells) {
    s['id'] = ensureEntityId(s['id'] as String?);
    s.removeWhere((k, _) => _privilegeKeys.contains(k));
  }
  data['sells'] = sells;

  final incomes = asMaps(data['incomes']);
  for (final r in incomes) {
    r['id'] = ensureEntityId(r['id'] as String?);
    r.removeWhere((k, _) => _privilegeKeys.contains(k));
  }
  data['incomes'] = incomes;

  final theme = data['themeMode'];
  if (theme is! String ||
      (theme != 'light' && theme != 'dark' && theme != 'system')) {
    data['themeMode'] = 'system';
  }
  return data;
}

BackupEnvelope parseAndValidateBackupJson(String rawJson) {
  late final dynamic decoded;
  try {
    decoded = jsonDecode(rawJson);
  } catch (_) {
    throw BackupException('備份檔不是有效的 JSON');
  }
  if (decoded is! Map) {
    throw BackupException('備份檔格式錯誤（根節點必須是物件）');
  }
  final root = Map<String, dynamic>.from(decoded);
  final format = root['format'] as String?;
  if (format != kBackupFormat) {
    throw BackupException('不是股市助手備份檔（format 不符）');
  }
  final schemaVersion = (root['schemaVersion'] as num?)?.toInt();
  if (schemaVersion == null) {
    throw BackupException('缺少 schemaVersion');
  }
  if (schemaVersion > kBackupSchemaVersion) {
    throw BackupException('備份 schema 版本過新（$schemaVersion），請更新 App 後再匯入');
  }
  final payloadRaw = root['payload'];
  if (payloadRaw is! Map) {
    throw BackupException('缺少或損毀的 payload');
  }
  final migrated =
      migratePayloadToV1(Map<String, dynamic>.from(payloadRaw), schemaVersion);
  final expected = root['checksum'] as String?;
  if (expected == null || expected.isEmpty) {
    throw BackupException('缺少 checksum');
  }
  final actual = sha256HexOfCanonicalPayload(migrated);
  if (actual.toLowerCase() != expected.toLowerCase()) {
    // Also accept checksum of original payload before migrate if schema==1
    // and identical structure — but after migrate ids may change if missing.
    // Recompute against pre-migrate stripped payload for schema==1 files that
    // already had ids.
    final stripped =
        stripPrivilegeFields(Map<String, dynamic>.from(payloadRaw));
    // Drop excluded keys that migrate removes, without rewriting ids.
    stripped.remove('namesCache');
    stripped.remove('tw_names_cache');
    stripped.remove('quoteCache');
    stripped.remove('quotes');
    stripped.remove('logs');
    stripped.remove('tokens');
    stripped.remove('ads');
    final alt = sha256HexOfCanonicalPayload(stripped);
    if (alt.toLowerCase() != expected.toLowerCase() &&
        actual.toLowerCase() != expected.toLowerCase()) {
      throw BackupException('checksum 驗證失敗（檔案可能已損毀或被竄改）');
    }
  }
  final payload = BackupPayload.fromJson(migrated);
  return BackupEnvelope(
    format: format!,
    schemaVersion: schemaVersion,
    exportedAt: (root['exportedAt'] as String?) ?? '',
    appPackage: (root['appPackage'] as String?) ?? '',
    appVersion: (root['appVersion'] as String?) ?? '',
    payload: payload,
    checksum: expected,
  );
}

String themeModeToBackup(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

ThemeMode themeModeFromBackup(String v) => switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

bool _watchEqual(WatchItem a, WatchItem b) =>
    a.ticker == b.ticker && a.name == b.name;

bool _holdingEqual(Holding a, Holding b) =>
    a.ticker == b.ticker &&
    a.name == b.name &&
    a.buyPrice == b.buyPrice &&
    a.shares == b.shares &&
    a.note == b.note;

bool _sellEqual(SellRecord a, SellRecord b) =>
    a.ticker == b.ticker &&
    a.name == b.name &&
    a.avgCost == b.avgCost &&
    a.sellPrice == b.sellPrice &&
    a.shares == b.shares &&
    a.soldAt.toIso8601String() == b.soldAt.toIso8601String() &&
    a.note == b.note;

bool _incomeEqual(IncomeRecord a, IncomeRecord b) =>
    a.ticker == b.ticker &&
    a.name == b.name &&
    a.amount == b.amount &&
    a.receivedAt.toIso8601String() == b.receivedAt.toIso8601String() &&
    a.note == b.note &&
    a.kind == b.kind;

ImportPreview previewImport({
  required LocalBackupSnapshot local,
  required BackupPayload incoming,
  required BackupConflictStrategy strategy,
}) {
  var wAdd = 0, wChg = 0, wSkip = 0;
  var hAdd = 0, hChg = 0, hSkip = 0;
  var sAdd = 0, sChg = 0, sSkip = 0;
  var iAdd = 0, iChg = 0, iSkip = 0;

  final localWatchById = {for (final e in local.watchlist) e.id: e};
  final localWatchByTicker = {for (final e in local.watchlist) e.ticker: e};
  for (final item in incoming.watchlist) {
    final exist = localWatchById[item.id] ?? localWatchByTicker[item.ticker];
    if (exist == null) {
      wAdd++;
    } else if (_watchEqual(exist, item.copyWith(id: exist.id))) {
      wSkip++;
    } else {
      switch (strategy) {
        case BackupConflictStrategy.skip:
          wSkip++;
        case BackupConflictStrategy.overwrite:
          wChg++;
        case BackupConflictStrategy.saveAsCopy:
          wAdd++;
      }
    }
  }

  final localHoldById = {for (final e in local.holdings) e.id: e};
  for (final item in incoming.holdings) {
    final exist = localHoldById[item.id];
    if (exist == null) {
      hAdd++;
    } else if (_holdingEqual(exist, item)) {
      hSkip++;
    } else {
      switch (strategy) {
        case BackupConflictStrategy.skip:
          hSkip++;
        case BackupConflictStrategy.overwrite:
          hChg++;
        case BackupConflictStrategy.saveAsCopy:
          hAdd++;
      }
    }
  }

  final localSellById = {for (final e in local.sells) e.id: e};
  for (final item in incoming.sells) {
    final exist = localSellById[item.id];
    if (exist == null) {
      sAdd++;
    } else if (_sellEqual(exist, item)) {
      sSkip++;
    } else {
      switch (strategy) {
        case BackupConflictStrategy.skip:
          sSkip++;
        case BackupConflictStrategy.overwrite:
          sChg++;
        case BackupConflictStrategy.saveAsCopy:
          sAdd++;
      }
    }
  }

  final localIncomeById = {for (final e in local.incomes) e.id: e};
  for (final item in incoming.incomes) {
    final exist = localIncomeById[item.id];
    if (exist == null) {
      iAdd++;
    } else if (_incomeEqual(exist, item)) {
      iSkip++;
    } else {
      switch (strategy) {
        case BackupConflictStrategy.skip:
          iSkip++;
        case BackupConflictStrategy.overwrite:
          iChg++;
        case BackupConflictStrategy.saveAsCopy:
          iAdd++;
      }
    }
  }

  final themeWillChange = strategy != BackupConflictStrategy.skip &&
      themeModeToBackup(local.themeMode) != incoming.themeMode;

  return ImportPreview(
    watchAdded: wAdd,
    watchChanged: wChg,
    watchSkipped: wSkip,
    holdingsAdded: hAdd,
    holdingsChanged: hChg,
    holdingsSkipped: hSkip,
    sellsAdded: sAdd,
    sellsChanged: sChg,
    sellsSkipped: sSkip,
    incomesAdded: iAdd,
    incomesChanged: iChg,
    incomesSkipped: iSkip,
    themeWillChange: themeWillChange ||
        (strategy == BackupConflictStrategy.skip && false),
  );
}

LocalBackupSnapshot mergeImport({
  required LocalBackupSnapshot local,
  required BackupPayload incoming,
  required BackupConflictStrategy strategy,
}) {
  // Watchlist
  final watchById = {for (final e in local.watchlist) e.id: e};
  final watchByTicker = {for (final e in local.watchlist) e.ticker: e};
  final watchOut = List<WatchItem>.from(local.watchlist);

  for (final item in incoming.watchlist) {
    final byId = watchById[item.id];
    final byTicker = watchByTicker[item.ticker];
    final exist = byId ?? byTicker;
    if (exist == null) {
      final add = item.id.isEmpty ? item.copyWith(id: newEntityId()) : item;
      watchOut.add(add);
      watchById[add.id] = add;
      watchByTicker[add.ticker] = add;
      continue;
    }
    switch (strategy) {
      case BackupConflictStrategy.skip:
        break;
      case BackupConflictStrategy.overwrite:
        final idx = watchOut.indexWhere((e) => e.id == exist.id);
        final replaced = item.copyWith(id: exist.id);
        if (idx >= 0) {
          watchOut[idx] = replaced;
        }
        watchById[exist.id] = replaced;
        watchByTicker[replaced.ticker] = replaced;
      case BackupConflictStrategy.saveAsCopy:
        // Same ticker already present: skip duplicate ticker for watchlist
        // (watchlist is unique by ticker). If only id conflicts, new id.
        if (byTicker != null && byTicker.ticker == item.ticker) {
          // already have this ticker — treat as skip for watch uniqueness
          break;
        }
        final copy = item.copyWith(id: newEntityId());
        watchOut.add(copy);
        watchById[copy.id] = copy;
        watchByTicker[copy.ticker] = copy;
    }
  }

  // Holdings
  final holdById = {for (final e in local.holdings) e.id: e};
  final holdOut = List<Holding>.from(local.holdings);
  for (final item in incoming.holdings) {
    final exist = holdById[item.id];
    if (exist == null) {
      holdOut.add(item);
      holdById[item.id] = item;
      continue;
    }
    switch (strategy) {
      case BackupConflictStrategy.skip:
        break;
      case BackupConflictStrategy.overwrite:
        final idx = holdOut.indexWhere((e) => e.id == exist.id);
        if (idx >= 0) holdOut[idx] = item;
        holdById[item.id] = item;
      case BackupConflictStrategy.saveAsCopy:
        final copy = item.copyWith(id: newEntityId());
        holdOut.add(copy);
        holdById[copy.id] = copy;
    }
  }

  // Sells
  final sellById = {for (final e in local.sells) e.id: e};
  final sellOut = List<SellRecord>.from(local.sells);
  for (final item in incoming.sells) {
    final exist = sellById[item.id];
    if (exist == null) {
      sellOut.add(item);
      sellById[item.id] = item;
      continue;
    }
    switch (strategy) {
      case BackupConflictStrategy.skip:
        break;
      case BackupConflictStrategy.overwrite:
        final idx = sellOut.indexWhere((e) => e.id == exist.id);
        if (idx >= 0) sellOut[idx] = item;
        sellById[item.id] = item;
      case BackupConflictStrategy.saveAsCopy:
        final copy = SellRecord(
          id: newEntityId(),
          ticker: item.ticker,
          name: item.name,
          avgCost: item.avgCost,
          sellPrice: item.sellPrice,
          shares: item.shares,
          soldAt: item.soldAt,
          note: item.note,
        );
        sellOut.add(copy);
        sellById[copy.id] = copy;
    }
  }

  // Incomes (股利／息)
  final incomeById = {for (final e in local.incomes) e.id: e};
  final incomeOut = List<IncomeRecord>.from(local.incomes);
  for (final item in incoming.incomes) {
    final exist = incomeById[item.id];
    if (exist == null) {
      incomeOut.add(item);
      incomeById[item.id] = item;
      continue;
    }
    switch (strategy) {
      case BackupConflictStrategy.skip:
        break;
      case BackupConflictStrategy.overwrite:
        final idx = incomeOut.indexWhere((e) => e.id == exist.id);
        if (idx >= 0) incomeOut[idx] = item;
        incomeById[item.id] = item;
      case BackupConflictStrategy.saveAsCopy:
        final copy = item.copyWith(id: newEntityId());
        incomeOut.add(copy);
        incomeById[copy.id] = copy;
    }
  }

  final theme = strategy == BackupConflictStrategy.skip
      ? local.themeMode
      : themeModeFromBackup(incoming.themeMode);

  // Groups: overwrite when incoming provides them; else keep local.
  final watchGroups = incoming.watchGroups.isNotEmpty
      ? incoming.watchGroups
      : local.watchGroups;
  final holdingGroups = incoming.holdingGroups.isNotEmpty
      ? incoming.holdingGroups
      : local.holdingGroups;
  final activeWatch = incoming.activeWatchGroupId ?? local.activeWatchGroupId;
  final activeHold =
      incoming.activeHoldingGroupId ?? local.activeHoldingGroupId;

  return LocalBackupSnapshot(
    watchlist: watchOut,
    holdings: holdOut,
    sells: sellOut,
    incomes: incomeOut,
    themeMode: theme,
    watchGroups: watchGroups,
    holdingGroups: holdingGroups,
    activeWatchGroupId: activeWatch,
    activeHoldingGroupId: activeHold,
  );
}

class BackupService {
  BackupService(this.storage);
  final AppStorage storage;

  Future<LocalBackupSnapshot> loadLocal() async {
    final watch = await storage.loadWatchlist();
    // Ensure watch items have ids (migrate in-memory).
    final watchFixed = <WatchItem>[];
    var dirty = false;
    for (final w in watch) {
      if (w.id.isEmpty) {
        dirty = true;
        watchFixed.add(w.copyWith(id: newEntityId()));
      } else {
        watchFixed.add(w);
      }
    }
    if (dirty) await storage.saveWatchlist(watchFixed);

    final watchGroups = await storage.loadWatchGroups();
    final holdingGroups = await storage.loadHoldingGroups();
    return LocalBackupSnapshot(
      watchlist: watchFixed,
      holdings: await storage.loadHoldings(),
      sells: await storage.loadSells(),
      incomes: await storage.loadIncomes(),
      themeMode: await storage.loadThemeMode(),
      watchGroups: watchGroups,
      holdingGroups: holdingGroups,
      activeWatchGroupId: await storage.loadActiveWatchGroupId(),
      activeHoldingGroupId: await storage.loadActiveHoldingGroupId(),
    );
  }

  Future<BackupEnvelope> buildExportEnvelope({
    required String appPackage,
    required String appVersion,
    DateTime? exportedAt,
  }) async {
    final local = await loadLocal();
    final payload = BackupPayload(
      watchlist: local.watchlist,
      holdings: local.holdings,
      sells: local.sells,
      incomes: local.incomes,
      themeMode: themeModeToBackup(local.themeMode),
      watchGroups: local.watchGroups,
      holdingGroups: local.holdingGroups,
      activeWatchGroupId: local.activeWatchGroupId,
      activeHoldingGroupId: local.activeHoldingGroupId,
    );
    final payloadMap = payload.toJson();
    final checksum = sha256HexOfCanonicalPayload(payloadMap);
    return BackupEnvelope(
      format: kBackupFormat,
      schemaVersion: kBackupSchemaVersion,
      exportedAt: (exportedAt ?? DateTime.now().toUtc()).toIso8601String(),
      appPackage: appPackage,
      appVersion: appVersion,
      payload: payload,
      checksum: checksum,
    );
  }

  String encodeEnvelopePretty(BackupEnvelope env) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(env.toJson());
  }

  /// Atomic apply with rollback snapshot on failure.
  Future<LocalBackupSnapshot> applyImportAtomic({
    required BackupPayload incoming,
    required BackupConflictStrategy strategy,
  }) async {
    final before = await loadLocal();
    final merged = mergeImport(
      local: before,
      incoming: incoming,
      strategy: strategy,
    );
    try {
      await storage.saveWatchlist(merged.watchlist);
      await storage.saveHoldings(merged.holdings);
      await storage.saveSells(merged.sells);
      await storage.saveIncomes(merged.incomes);
      await storage.saveThemeMode(merged.themeMode);
      if (merged.watchGroups.isNotEmpty) {
        await storage.saveWatchGroups(merged.watchGroups);
      }
      if (merged.holdingGroups.isNotEmpty) {
        await storage.saveHoldingGroups(merged.holdingGroups);
      }
      if (merged.activeWatchGroupId != null) {
        await storage.saveActiveWatchGroupId(merged.activeWatchGroupId!);
      }
      if (merged.activeHoldingGroupId != null) {
        await storage.saveActiveHoldingGroupId(merged.activeHoldingGroupId!);
      }
      return merged;
    } catch (e) {
      // Rollback
      try {
        await storage.saveWatchlist(before.watchlist);
        await storage.saveHoldings(before.holdings);
        await storage.saveSells(before.sells);
        await storage.saveIncomes(before.incomes);
        await storage.saveThemeMode(before.themeMode);
        if (before.watchGroups.isNotEmpty) {
          await storage.saveWatchGroups(before.watchGroups);
        }
        if (before.holdingGroups.isNotEmpty) {
          await storage.saveHoldingGroups(before.holdingGroups);
        }
      } catch (_) {}
      throw BackupException('匯入失敗，已還原先前資料：$e');
    }
  }
}
