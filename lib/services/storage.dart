import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'ids.dart';

class NamesCacheData {
  NamesCacheData({
    required this.names,
    required this.otcCodes,
    this.esmCodes = const {},
  });
  final Map<String, String> names;
  final Set<String> otcCodes;
  final Set<String> esmCodes;
}

class AppStorage {
  static const _watchKey = 'watchlist_v1';
  static const _holdKey = 'holdings_v1';
  static const _sellKey = 'sells_v1';
  static const _incomeKey = 'incomes_v1';
  static const _namesKey = 'tw_names_cache_v1';
  static const _themeKey = 'theme_mode_v1';

  Future<List<WatchItem>> loadWatchlist() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_watchKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final items = list
        .map((e) => WatchItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    var dirty = false;
    final fixed = <WatchItem>[];
    for (final w in items) {
      if (w.id.isEmpty) {
        dirty = true;
        fixed.add(w.copyWith(id: newEntityId()));
      } else {
        fixed.add(w);
      }
    }
    if (dirty) {
      await p.setString(
          _watchKey, jsonEncode(fixed.map((e) => e.toJson()).toList()));
    }
    return fixed;
  }

  Future<void> saveWatchlist(List<WatchItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _watchKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<List<Holding>> loadHoldings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_holdKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final items = list
        .map((e) => Holding.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    var dirty = false;
    final fixed = <Holding>[];
    for (final h in items) {
      if (h.id.isEmpty) {
        dirty = true;
        fixed.add(h.copyWith(id: newEntityId()));
      } else {
        fixed.add(h);
      }
    }
    if (dirty) {
      await p.setString(
          _holdKey, jsonEncode(fixed.map((e) => e.toJson()).toList()));
    }
    return fixed;
  }

  Future<void> saveHoldings(List<Holding> items) async {
    final consolidated = consolidateHoldings(items);
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _holdKey, jsonEncode(consolidated.map((e) => e.toJson()).toList()));
  }

  /// Holdings for portfolio math: groups are canonical (成本損益);
  /// [activeGroupOnly] matches the group currently shown there.
  Future<List<Holding>> loadPortfolioHoldings({bool activeGroupOnly = true}) async {
    final groups = await loadHoldingGroups();
    if (groups.isEmpty) {
      return consolidateHoldings(await loadHoldings());
    }
    if (!activeGroupOnly) {
      final flat = <Holding>[for (final g in groups) ...g.items];
      return consolidateHoldings(flat);
    }
    final activeId = await loadActiveHoldingGroupId();
    HoldingGroup g = groups.first;
    if (activeId != null) {
      for (final x in groups) {
        if (x.id == activeId) {
          g = x;
          break;
        }
      }
    }
    return List<Holding>.from(g.items);
  }

  /// Restore shares from an undone sell into the active holding group (canonical).
  Future<void> restoreSellIntoActiveGroup(SellRecord record) async {
    final groups = await loadHoldingGroups();
    final activeId = await loadActiveHoldingGroupId();
    if (groups.isEmpty) {
      final restored = restoreHoldingFromSell(await loadHoldings(), record);
      await saveHoldings(consolidateHoldings(restored));
      return;
    }
    var idx = 0;
    if (activeId != null) {
      final i = groups.indexWhere((g) => g.id == activeId);
      if (i >= 0) idx = i;
    }
    final nextItems = restoreHoldingFromSell(groups[idx].items, record);
    final next = [...groups];
    next[idx] = groups[idx].copyWith(items: nextItems);
    await saveHoldingGroups(next);
  }

  Future<List<SellRecord>> loadSells() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_sellKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final sells = list
        .map((e) => SellRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    sells.sort((a, b) => b.soldAt.compareTo(a.soldAt));
    return sells;
  }

  Future<void> saveSells(List<SellRecord> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _sellKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> addSell(SellRecord record) async {
    final all = await loadSells();
    all.insert(0, record);
    await saveSells(all);
  }

  Future<void> deleteSell(String id) async {
    final all = await loadSells();
    all.removeWhere((e) => e.id == id);
    await saveSells(all);
  }

  Future<List<IncomeRecord>> loadIncomes() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_incomeKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final items = list
        .map((e) => IncomeRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    var dirty = false;
    final fixed = <IncomeRecord>[];
    for (final r in items) {
      if (r.id.isEmpty) {
        dirty = true;
        fixed.add(r.copyWith(id: newEntityId()));
      } else {
        fixed.add(r);
      }
    }
    fixed.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    if (dirty) {
      await p.setString(
          _incomeKey, jsonEncode(fixed.map((e) => e.toJson()).toList()));
    }
    return fixed;
  }

  Future<void> saveIncomes(List<IncomeRecord> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _incomeKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> addIncome(IncomeRecord record) async {
    final all = await loadIncomes();
    all.insert(0, record);
    await saveIncomes(all);
  }

  Future<void> deleteIncome(String id) async {
    final all = await loadIncomes();
    all.removeWhere((e) => e.id == id);
    await saveIncomes(all);
  }

  Future<NamesCacheData?> loadNamesCache() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_namesKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAt = (data['fetchedAt'] as num?)?.toDouble() ?? 0;
      final ageMs = DateTime.now().millisecondsSinceEpoch - fetchedAt;
      if (ageMs > 24 * 60 * 60 * 1000) return null;
      final names = Map<String, dynamic>.from(data['names'] as Map);
      Set<String> parseCodes(dynamic rawList) {
        final out = <String>{};
        if (rawList is List) {
          for (final e in rawList) {
            final s = '$e'.trim();
            if (s.isNotEmpty) out.add(s);
          }
        }
        return out;
      }

      return NamesCacheData(
        names: names.map((k, v) => MapEntry(k, v.toString())),
        otcCodes: parseCodes(data['otcCodes']),
        esmCodes: parseCodes(data['esmCodes']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveNamesCache(
    Map<String, String> names, {
    Set<String> otcCodes = const {},
    Set<String> esmCodes = const {},
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _namesKey,
      jsonEncode({
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        'names': names,
        'otcCodes': otcCodes.toList(),
        'esmCodes': esmCodes.toList(),
      }),
    );
  }

  Future<ThemeMode> loadThemeMode() async {
    final p = await SharedPreferences.getInstance();
    switch (p.getString(_themeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final p = await SharedPreferences.getInstance();
    final v = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await p.setString(_themeKey, v);
  }

  static const _watchGroupsKey = 'watch_groups_v1';
  static const _activeWatchGroupKey = 'watch_active_group_v1';

  /// Load watch groups; migrates flat watchlist_v1 into one default group.
  Future<List<WatchGroup>> loadWatchGroups() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_watchGroupsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        final groups = <WatchGroup>[];
        var dirty = false;
        for (final e in list) {
          var g = WatchGroup.fromJson(Map<String, dynamic>.from(e as Map));
          if (g.id.isEmpty) {
            dirty = true;
            g = g.copyWith(id: newEntityId());
          }
          final fixedItems = <WatchItem>[];
          for (final w in g.items) {
            if (w.id.isEmpty) {
              dirty = true;
              fixedItems.add(w.copyWith(id: newEntityId()));
            } else {
              fixedItems.add(w);
            }
          }
          groups.add(g.copyWith(items: fixedItems));
        }
        if (groups.isEmpty) {
          final flat = await loadWatchlist();
          final g = WatchGroup(
            id: newEntityId(),
            name: '預設清單',
            items: flat,
          );
          await saveWatchGroups([g]);
          return [g];
        }
        if (dirty) await saveWatchGroups(groups);
        return groups;
      } catch (_) {
        // fall through to migrate
      }
    }
    final flat = await loadWatchlist();
    final g = WatchGroup(
      id: newEntityId(),
      name: '預設清單',
      items: flat,
    );
    await saveWatchGroups([g]);
    return [g];
  }

  Future<void> saveWatchGroups(List<WatchGroup> groups) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _watchGroupsKey,
      jsonEncode(groups.map((e) => e.toJson()).toList()),
    );
    // Keep legacy flat key in sync (all symbols, for backup compatibility).
    final flat = <WatchItem>[];
    final seen = <String>{};
    for (final g in groups) {
      for (final w in g.items) {
        if (seen.add(w.ticker)) flat.add(w);
      }
    }
    await p.setString(
      _watchKey,
      jsonEncode(flat.map((e) => e.toJson()).toList()),
    );
  }

  Future<String?> loadActiveWatchGroupId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_activeWatchGroupKey);
  }

  Future<void> saveActiveWatchGroupId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_activeWatchGroupKey, id);
  }


  static const _holdGroupsKey = 'hold_groups_v1';
  static const _activeHoldGroupKey = 'hold_active_group_v1';

  /// Load holding groups; migrates flat holdings_v1 into one default group.
  Future<List<HoldingGroup>> loadHoldingGroups() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_holdGroupsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        final groups = <HoldingGroup>[];
        var dirty = false;
        for (final e in list) {
          var g = HoldingGroup.fromJson(Map<String, dynamic>.from(e as Map));
          if (g.id.isEmpty) {
            dirty = true;
            g = g.copyWith(id: newEntityId());
          }
          final fixedItems = <Holding>[];
          for (final h in g.items) {
            if (h.id.isEmpty) {
              dirty = true;
              fixedItems.add(h.copyWith(id: newEntityId()));
            } else {
              fixedItems.add(h);
            }
          }
          final consolidated = consolidateHoldings(fixedItems);
          if (consolidated.length != fixedItems.length) dirty = true;
          groups.add(g.copyWith(items: consolidated));
        }
        if (groups.isEmpty) {
          final flat = await loadHoldings();
          final g = HoldingGroup(
            id: newEntityId(),
            name: '預設持倉',
            items: flat,
          );
          await saveHoldingGroups([g]);
          return [g];
        }
        if (dirty) await saveHoldingGroups(groups);
        return groups;
      } catch (_) {
        // fall through to migrate
      }
    }
    final flat = await loadHoldings();
    final g = HoldingGroup(
      id: newEntityId(),
      name: '預設持倉',
      items: flat,
    );
    await saveHoldingGroups([g]);
    return [g];
  }

  Future<void> saveHoldingGroups(List<HoldingGroup> groups) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _holdGroupsKey,
      jsonEncode(groups.map((e) => e.toJson()).toList()),
    );
    // Keep legacy flat key in sync (all holdings across groups).
    final flat = <Holding>[];
    for (final g in groups) {
      flat.addAll(g.items);
    }
    await p.setString(
      _holdKey,
      jsonEncode(flat.map((e) => e.toJson()).toList()),
    );
  }

  Future<String?> loadActiveHoldingGroupId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_activeHoldGroupKey);
  }

  Future<void> saveActiveHoldingGroupId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_activeHoldGroupKey, id);
  }

}
