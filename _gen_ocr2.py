# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"C:\Users\user\Documents\stock-helper-flutter\lib\services\holdings_ocr.dart")
p.write_text("""import 'dart:io';

import 'package:google_mlkit_text_recognition' as mlkit;
import 'package:image_picker/image_picker.dart';

import 'names.dart';
import 'ticker.dart';

/// One row parsed from a broker holdings screenshot (editable in UI).
class OcrHoldingDraft {
  OcrHoldingDraft({
    this.code = '',
    this.name = '',
    this.shares,
    this.avgCost,
    this.selected = true,
    this.rawHint = '',
  });

  /// Bare TW code e.g. 2330 / 0056 (no .TW suffix yet). May be empty until resolved.
  String code;
  String name;
  double? shares;
  double? avgCost;
  bool selected;
  String rawHint;

  bool get isComplete =>
      code.trim().isNotEmpty &&
      shares != null &&
      shares! > 0 &&
      avgCost != null &&
      avgCost! > 0;
}

/// On-device OCR + Taiwan broker holdings heuristics (code-first OR name-first).
class HoldingsOcrService {
  HoldingsOcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<XFile?> pickImage(ImageSource source) {
    return _picker.pickImage(
      source: source,
      imageQuality: 95,
      maxWidth: 4096,
      maxHeight: 4096,
    );
  }

  Future<String> recognizeText(String imagePath) async {
    final input = mlkit.InputImage.fromFilePath(imagePath);
    final recognizer = mlkit.TextRecognizer(
      script: mlkit.TextRecognitionScript.chinese,
    );
    try {
      final result = await recognizer.processImage(input);
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  Future<List<OcrHoldingDraft>> pickAndParse(
    ImageSource source, {
    NamesService? names,
  }) async {
    final file = await pickImage(source);
    if (file == null) return [];
    final text = await recognizeText(file.path);
    if (text.trim().isEmpty) {
      throw StateError('\\u7121\\u6cd5\\u5f9e\\u5716\\u7247\\u8fa8\\u8b58\\u6587\\u5b57\\uff0c\\u8acb\\u63db\\u66f4\\u6e05\\u6670\\u7684\\u6301\\u5009\\u622a\\u5716');
    }
    var drafts = parseHoldingsFromOcrText(text);
    if (names != null) {
      drafts = enrichDraftsWithNames(drafts, names);
    }
    if (drafts.isEmpty) {
      throw StateError(
        '\\u672a\\u8fa8\\u8b58\\u5230\\u53ef\\u532f\\u5165\\u7684\\u6301\\u5009\\u5217\\u3002\\u8acb\\u78ba\\u8a8d\\u622a\\u5716\\u542b\\u300c\\u80a1\\u540d\\uff0f\\u4ee3\\u865f\\u3001\\u80a1\\u6578\\u3001\\u6210\\u672c\\u5747\\u50f9\\u300d',
      );
    }
    return drafts;
  }
}

/// Fill missing codes from names (and vice versa) using [NamesService].
List<OcrHoldingDraft> enrichDraftsWithNames(
  List<OcrHoldingDraft> drafts,
  NamesService names,
) {
  for (final d in drafts) {
    if (d.code.trim().isEmpty && d.name.trim().isNotEmpty) {
      final code = names.resolveCodeByName(d.name);
      if (code != null) d.code = code;
    }
    if (d.name.trim().isEmpty && d.code.trim().isNotEmpty) {
      try {
        final t = normalizeTicker(d.code);
        final n = names.resolveName(t);
        if (n.isNotEmpty) d.name = n;
      } catch (_) {}
    }
    d.selected = d.isComplete;
  }
  return drafts;
}

// ---------------------------------------------------------------------------
// Pure parser
// ---------------------------------------------------------------------------

final _codeRe = RegExp(r'(?<!\\d)(\\d{4,6})(?!\\d)');
final _numRe = RegExp(
  r'(?<![\\d.])(\\d{1,3}(?:,\\d{3})*(?:\\.\\d+)?|\\d+(?:\\.\\d+)?)(?![\\d.])',
);
final _chineseChunkRe = RegExp(r'[\\u4e00-\\u9fff]{2,}');

const _typeNoise = {
  '\\u73fe\\u80a1',
  '\\u878d\\u8cc7',
  '\\u878d\\u5238',
  '\\u501f\\u5238',
  '\\u96f6\\u80a1',
  '\\u914d\\u80a1',
  '\\u7a2e\\u985e',
  '\\u73fe\\u91d1',
};

const _headerNoise = {
  '\\u80a1\\u540d',
  '\\u540d\\u7a31',
  '\\u5546\\u54c1',
  '\\u80a1\\u7968',
  '\\u4ee3\\u865f',
  '\\u7a2e\\u985e',
  '\\u80a1\\u6578',
  '\\u6301\\u6709',
  '\\u5eab\\u5b58',
  '\\u6210\\u672c',
  '\\u5747\\u50f9',
  '\\u5e73\\u5747',
  '\\u73fe\\u50f9',
  '\\u5e02\\u50f9',
  '\\u6f32\\u8dcc',
  '\\u640d\\u76ca',
  '\\u5831\\u916c',
  '\\u5e02\\u503c',
  '\\u5408\\u8a08',
  '\\u5c0f\\u8a08',
  '\\u7e3d\\u8a08',
  '\\u660e\\u7d30',
  '\\u5eab\\u5b58\\u80a1\\u6578',
  '\\u6301\\u6709\\u80a1\\u6578',
  '\\u6210\\u672c\\u5747\\u50f9',
  '\\u5e73\\u5747\\u6210\\u672c',
  '\\u53c3\\u8003\\u6210\\u672c',
  '\\u8cb7\\u9032\\u5747\\u50f9',
};

bool _looksLikeTwCode(String code) {
  if (!RegExp(r'^\\d{4,6}$').hasMatch(code)) return false;
  if (code.length == 4) {
    final n = int.parse(code);
    if (n < 1000) return code.startsWith('00');
    return n <= 9999;
  }
  return code.startsWith('00') ||
      code.startsWith('006') ||
      code.startsWith('008') ||
      code.startsWith('009');
}

double? _parseNum(String raw) {
  final s = raw.replaceAll(',', '').replaceAll('\\uFF0C', '').trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

String _normalizeOcr(String text) {
  const full = '\\uFF10\\uFF11\\uFF12\\uFF13\\uFF14\\uFF15\\uFF16\\uFF17\\uFF18\\uFF19\\uFF0E\\uFF0C\\u3000';
  const half = '0123456789., ';
  final buf = StringBuffer();
  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    final i = full.indexOf(ch);
    if (i >= 0) {
      buf.write(half[i]);
    } else {
      buf.write(ch);
    }
  }
  return buf
      .toString()
      .replaceAll('\\r\\n', '\\n')
      .replaceAll('\\r', '\\n')
      .replaceAll('\\uFF1A', ':')
      .replaceAll('\\uFF0F', '/')
      .replaceAll(RegExp(r'[ \\t]+'), ' ');
}

bool _isHeaderLine(String line) {
  final hasName = line.contains('\\u80a1\\u540d') ||
      line.contains('\\u540d\\u7a31') ||
      line.contains('\\u5546\\u54c1');
  final hasShares = line.contains('\\u80a1\\u6578') ||
      line.contains('\\u5eab\\u5b58') ||
      line.contains('\\u6301\\u80a1');
  final hasCost = line.contains('\\u5747\\u50f9') ||
      line.contains('\\u6210\\u672c');
  return (hasName || line.contains('\\u4ee3\\u865f')) && (hasShares || hasCost);
}

String? _extractChineseName(String line) {
  var s = line;
  for (final t in _typeNoise) {
    s = s.replaceAll(t, ' ');
  }
  for (final t in _headerNoise) {
    s = s.replaceAll(t, ' ');
  }
  s = s.replaceAll(_codeRe, ' ');
  s = s.replaceAll(_numRe, ' ');
  s = s.replaceAll(RegExp(r'[|\\uFF5C/\\uFF0F\\-\\u2013\\u2014:()\\uFF08\\uFF09\\[\\]\\u3010\\u3011]'), ' ');
  final parts = _chineseChunkRe
      .allMatches(s)
      .map((m) => m.group(0)!.trim())
      .where((p) => p.length >= 2)
      .where((p) => !_typeNoise.contains(p) && !_headerNoise.contains(p))
      .toList();
  if (parts.isEmpty) return null;
  parts.sort((a, b) => b.length.compareTo(a.length));
  var name = parts.first;
  if (name.length > 24) name = name.substring(0, 24);
  return name;
}

({double? shares, double? cost}) _pickSharesAndCost(List<double> nums) {
  if (nums.isEmpty) return (shares: null, cost: null);
  double? shares;
  double? cost;
  // Prefer: integer-ish as shares, dotted / trailing as cost.
  final intish = <double>[];
  final dotted = <double>[];
  for (final v in nums) {
    if (v <= 0) continue;
    if ((v - v.roundToDouble()).abs() < 1e-9 && v == v.roundToDouble()) {
      intish.add(v);
    } else {
      dotted.add(v);
    }
  }
  if (intish.isNotEmpty) {
    // First integer is usually \\u80a1\\u6578 in L->R tables.
    shares = intish.first;
  }
  if (dotted.isNotEmpty) {
    cost = dotted.first;
  } else if (intish.length >= 2) {
    // e.g. 400 51 with OCR dropping decimal — treat 2nd as cost if plausible.
    final cand = intish[1];
    if (cand > 0 && cand < 100000 && cand != shares) cost = cand;
  } else if (nums.length >= 2 && shares != null) {
    final rest = nums.where((n) => n != shares).toList();
    if (rest.isNotEmpty) cost = rest.first;
  }
  // If only one number and it's dotted, it's cost not shares.
  if (shares == null && dotted.length == 1 && intish.isEmpty) {
    cost = dotted.first;
  }
  return (shares: shares, cost: cost);
}

List<double> _numsIn(String line, {Set<String> skipCodes = const {}}) {
  final out = <double>[];
  for (final m in _numRe.allMatches(line)) {
    final token = m.group(1)!;
    final bare = token.replaceAll(',', '');
    if (skipCodes.contains(bare)) continue;
    if (_looksLikeTwCode(bare) && !token.contains('.')) continue;
    final v = _parseNum(token);
    if (v != null && v > 0) out.add(v);
  }
  return out;
}

/// Parse messy OCR text into candidate holdings rows (code-first and/or name-first).
List<OcrHoldingDraft> parseHoldingsFromOcrText(String rawText) {
  final text = _normalizeOcr(rawText);
  final lines = text
      .split('\\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  final drafts = <OcrHoldingDraft>[];
  final seen = <String>{}; // code or name key

  void addDraft(OcrHoldingDraft d) {
    final key = d.code.isNotEmpty
        ? 'c:${d.code}'
        : 'n:${d.name}';
    if (key == 'c:' || key == 'n:') return;
    if (seen.contains(key)) {
      // Merge into existing.
      final i = drafts.indexWhere((e) =>
          (d.code.isNotEmpty && e.code == d.code) ||
          (d.code.isEmpty && e.name == d.name));
      if (i >= 0) {
        final ex = drafts[i];
        if (ex.name.isEmpty && d.name.isNotEmpty) ex.name = d.name;
        if (ex.code.isEmpty && d.code.isNotEmpty) ex.code = d.code;
        ex.shares ??= d.shares;
        ex.avgCost ??= d.avgCost;
        if (d.rawHint.isNotEmpty) {
          ex.rawHint = '${ex.rawHint} ${d.rawHint}'.trim();
        }
      }
      return;
    }
    seen.add(key);
    drafts.add(d);
  }

  // Detect header-driven table mode.
  var headerIdx = -1;
  for (var i = 0; i < lines.length; i++) {
    if (_isHeaderLine(lines[i])) {
      headerIdx = i;
      break;
    }
  }

  // ---- Name-first / table rows (works with or without explicit header) ----
  final start = headerIdx >= 0 ? headerIdx + 1 : 0;
  for (var i = start; i < lines.length; i++) {
    final line = lines[i];
    if (_isHeaderLine(line)) continue;

    // Skip pure noise / totals.
    if (RegExp(r'^(\\u5408\\u8a08|\\u5c0f\\u8a08|\\u7e3d\\u8a08)').hasMatch(line)) continue;

    final codes = _codeRe
        .allMatches(line)
        .map((m) => m.group(1)!)
        .where(_looksLikeTwCode)
        .toList();
    final name = _extractChineseName(line);
    final nums = _numsIn(line, skipCodes: codes.toSet());

    // Multi-line row: name on one line, numbers on next (common OCR split).
    var shares = _pickSharesAndCost(nums).shares;
    var cost = _pickSharesAndCost(nums).cost;
    var usedHint = line;

    if ((shares == null || cost == null) && i + 1 < lines.length) {
      final next = lines[i + 1];
      // Don't steal next row's name line.
      final nextName = _extractChineseName(next);
      final nextCodes = _codeRe
          .allMatches(next)
          .map((m) => m.group(1)!)
          .where(_looksLikeTwCode)
          .toList();
      final nextLooksLikeNewRow = (nextName != null &&
              nextName.length >= 2 &&
              _chineseChunkRe.hasMatch(next) &&
              _numsIn(next).length <= 1 &&
              nextCodes.isEmpty) ==
          false;
      if (nextLooksLikeNewRow ||
          RegExp(r'\\u73fe\\u80a1|\\u878d\\u8cc7').hasMatch(next) ||
          _numsIn(next).length >= 1) {
        final mergedNums = [...nums, ..._numsIn(next, skipCodes: nextCodes.toSet())];
        final picked = _pickSharesAndCost(mergedNums);
        shares ??= picked.shares;
        cost ??= picked.cost;
        usedHint = '$line | $next';
      }
    }

    // Strip type tokens that OCR glued: "\\u73fe\\u80a1 400"
    if (name == null && codes.isEmpty) continue;
    // Need at least name or code, plus some numeric signal ideally.
    if (name == null && codes.isEmpty) continue;

    if (codes.isNotEmpty) {
      for (final code in codes) {
        addDraft(OcrHoldingDraft(
          code: code,
          name: name ?? '',
          shares: shares,
          avgCost: cost,
          rawHint: usedHint,
        ));
      }
    } else if (name != null) {
      // Name-first row (user sample: \\u80a1\\u540d | \\u7a2e\\u985e | \\u80a1\\u6578 | \\u6210\\u672c\\u5747\\u50f9)
      if (shares == null && cost == null) continue;
      addDraft(OcrHoldingDraft(
        code: '',
        name: name,
        shares: shares,
        avgCost: cost,
        rawHint: usedHint,
      ));
    }
  }

  // ---- Fallback code-window pass if still empty ----
  if (drafts.isEmpty) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      for (final m in _codeRe.allMatches(line)) {
        final code = m.group(1)!;
        if (!_looksLikeTwCode(code)) continue;
        final window = [
          if (i > 0) lines[i - 1],
          line,
          if (i + 1 < lines.length) lines[i + 1],
          if (i + 2 < lines.length) lines[i + 2],
        ].join('\\n');
        final name = _extractChineseName(window) ?? _extractChineseName(line);
        final nums = _numsIn(window, skipCodes: {code});
        final picked = _pickSharesAndCost(nums);
        addDraft(OcrHoldingDraft(
          code: code,
          name: name ?? '',
          shares: picked.shares,
          avgCost: picked.cost,
          rawHint: window,
        ));
      }
    }
  }

  for (final d in drafts) {
    if (d.code.isNotEmpty) {
      try {
        normalizeTicker(d.code);
      } catch (_) {
        d.code = '';
      }
    }
    d.selected = d.isComplete;
  }

  // Drop rows with neither name nor code.
  return drafts
      .where((d) => d.code.isNotEmpty || d.name.isNotEmpty)
      .toList();
}
""", encoding="utf-8")
# Fix: the write used a Python string with unicode escapes like \\u which become \u in file - good for Dart.
# But error messages I used \\u which is wrong - I wanted Chinese. Let me patch error strings after.
print("wrote", p.stat().st_size)