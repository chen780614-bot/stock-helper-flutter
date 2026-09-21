# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:\Users\user\Documents\stock-helper-flutter")

# --- names.dart with reverse lookup ---
(root / "lib" / "services" / "names.dart").write_text(r'''import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'storage.dart';
import 'ticker.dart';

class NamesService {
  NamesService(this._storage);
  final AppStorage _storage;

  Map<String, String> _memory = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final bundled =
        await rootBundle.loadString('assets/tw_names_subset.json');
    _memory = Map<String, String>.from(jsonDecode(bundled) as Map);
    final cached = await _storage.loadNamesCache();
    if (cached != null) {
      _memory.addAll(cached);
    }
    _loaded = true;
  }

  Future<void> refreshFromTwse() async {
    await ensureLoaded();
    try {
      final uri = Uri.parse(
          'https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL');
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'stock-helper-flutter/1.0',
      }).timeout(const Duration(seconds: 45));
      if (resp.statusCode != 200) return;
      final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      final map = <String, String>{};
      for (final row in list) {
        if (row is! Map) continue;
        final code = '${row['Code'] ?? ''}'.trim();
        final name = '${row['Name'] ?? ''}'.trim();
        if (code.isNotEmpty && name.isNotEmpty) map[code] = name;
      }
      if (map.isNotEmpty) {
        _memory.addAll(map);
        await _storage.saveNamesCache(map);
      }
    } catch (_) {
      // keep bundled / cache
    }
  }

  String? lookup(String ticker) {
    final code = extractTwCode(ticker);
    if (code == null) return null;
    return _memory[code];
  }

  String resolveName(String ticker, {String? fallback}) {
    return lookup(ticker) ?? fallback ?? '';
  }

  /// Resolve bare TW code from a Chinese (or mixed) stock name.
  /// Exact match first; then unique containment (OCR may truncate/extend).
  String? resolveCodeByName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return null;

    String? exact;
    for (final e in _memory.entries) {
      if (e.value == name) {
        // Prefer shorter/common ETF codes if duplicate names ever appear.
        if (exact == null || e.key.length < exact.length) exact = e.key;
      }
    }
    if (exact != null) return exact;

    final hits = <MapEntry<String, String>>[];
    for (final e in _memory.entries) {
      final v = e.value;
      if (v.isEmpty) continue;
      if (name.contains(v) || v.contains(name)) {
        hits.add(e);
      }
    }
    if (hits.isEmpty) return null;
    if (hits.length == 1) return hits.first.key;

    // Prefer the longest known name match (more specific), then shorter code.
    hits.sort((a, b) {
      final byLen = b.value.length.compareTo(a.value.length);
      if (byLen != 0) return byLen;
      return a.key.length.compareTo(b.key.length);
    });
    // If top two share same name length and different codes, ambiguous.
    if (hits.length >= 2 &&
        hits[0].value.length == hits[1].value.length &&
        hits[0].key != hits[1].key &&
        !(name.contains(hits[0].value) && !name.contains(hits[1].value))) {
      // Still return best guess when OCR name equals/contains top uniquely.
      final top = hits[0];
      final equallySpecific = hits
          .where((h) => h.value.length == top.value.length)
          .toList();
      if (equallySpecific.length > 1) {
        final exactish = equallySpecific
            .where((h) => name == h.value || name.contains(h.value))
            .toList();
        if (exactish.length == 1) return exactish.first.key;
      }
    }
    return hits.first.key;
  }

  /// Exposed for OCR unit tests without Flutter binding when map is injected.
  void debugReplaceMemory(Map<String, String> map) {
    _memory = Map<String, String>.from(map);
    _loaded = true;
  }
}
''', encoding='utf-8')
print('names.dart written')