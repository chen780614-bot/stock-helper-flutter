# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:\Users\user\Documents\stock-helper-flutter")

# --- holdings_ocr.dart ---
(root / "lib" / "services" / "holdings_ocr.dart").write_text(r'''import 'dart:io';

import 'package:google_mlkit_text_recognition' as mlkit;
import 'package:image_picker/image_picker.dart';

import 'ticker.dart';

/// One row parsed from a broker holdings screenshot (editable in UI).
class OcrHoldingDraft {
  OcrHoldingDraft({
    required this.code,
    this.name = '',
    this.shares,
    this.avgCost,
    this.selected = true,
    this.rawHint = '',
  });

  /// Bare TW code e.g. 2330 / 0050 (no .TW suffix yet).
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

/// On-device OCR + Taiwan broker holdings heuristics.
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

  /// Runs ML Kit text recognition on [imagePath] (on-device only).
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

  Future<List<OcrHoldingDraft>> pickAndParse(ImageSource source) async {
    final file = await pickImage(source);
    if (file == null) return [];
    final text = await recognizeText(file.path);
    // Best-effort: delete nothing; picker temp files are OS-managed.
    if (text.trim().isEmpty) {
      throw StateError('無法從圖片辨識文字，請換更清晰的持倉截圖');
    }
    final drafts = parseHoldingsFromOcrText(text);
    if (drafts.isEmpty) {
      throw StateError(
        '未辨識到台股代號／股數／均價。請確認截圖含「代號、股數、成本均價」欄位',
      );
    }
    return drafts;
  }

  /// Convenience when the caller already has a file path.
  Future<List<OcrHoldingDraft>> parseFile(String path) async {
    if (!File(path).existsSync()) {
      throw ArgumentError('找不到圖片：$path');
    }
    final text = await recognizeText(path);
    return parseHoldingsFromOcrText(text);
  }
}

// ---------------------------------------------------------------------------
// Pure parser (testable without ML Kit)
// ---------------------------------------------------------------------------

final _codeRe = RegExp(r'(?<!\d)(\d{4,6})(?!\d)');
final _numRe = RegExp(
  r'(?<![\d.])(\d{1,3}(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)(?![\d.])',
);
final _chineseRe = RegExp(r'[\u4e00-\u9fffＡ-Ｚａ-ｚA-Za-z0-9]+');

const _noiseWords = {
  '代號',
  '名稱',
  '股票',
  '商品',
  '股數',
  '持有',
  '庫存',
  '成本',
  '均價',
  '平均',
  '現價',
  '市價',
  '參考',
  '漲跌',
  '損益',
  '報酬',
  '市值',
  '合計',
  '小計',
  '總計',
  '幣別',
  '台幣',
  'TWD',
  '庫存股數',
  '持有股數',
  '成本均價',
  '平均成本',
  '參考成本',
  '買進均價',
  '成本價',
  '成交',
  '未實現',
  '已實現',
  '張數',
  '可用',
  '可出',
  '今日',
  '昨日',
  '證券',
  '帳號',
  '客戶',
  '明細',
  '持股',
  '部位',
};

bool _looksLikeTwCode(String code) {
  if (!RegExp(r'^\d{4,6}$').hasMatch(code)) return false;
  // Reject obvious years / times fragments loosely; keep ETFs 00xx / 008xxx.
  if (code.length == 4) {
    final n = int.parse(code);
    // Common TWSE/TPEx range + ETFs; exclude 0000-0999 except 00xx ETFs.
    if (n < 1000) return code.startsWith('00');
    return n <= 9999;
  }
  // 5–6 digit: mostly ETFs / beneficiary certificates (0050 is 4-digit though).
  return code.startsWith('00') || code.startsWith('006') || code.startsWith('008');
}

double? _parseNum(String raw) {
  final s = raw.replaceAll(',', '').replaceAll('，', '').trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

String _normalizeOcr(String text) {
  const full = '０１２３４５６７８９．，　';
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
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('：', ':')
      .replaceAll('／', '/')
      .replaceAll(RegExp(r'[ \t]+'), ' ');
}

String? _extractNameNear(String line, String code) {
  var s = line;
  s = s.replaceFirst(code, ' ');
  // Strip labeled noise and numbers.
  s = s.replaceAll(RegExp(r'(股數|庫存|成本|均價|現價|市價|損益|報酬|市值)[:：]?'), ' ');
  s = s.replaceAll(_numRe, ' ');
  s = s.replaceAll(RegExp(r'[|｜/／\-–—:：()（）\[\]【】]'), ' ');
  final parts = _chineseRe.allMatches(s).map((m) => m.group(0)!.trim()).where((p) {
    if (p.isEmpty) return false;
    if (_noiseWords.contains(p)) return false;
    if (RegExp(r'^\d+$').hasMatch(p)) return false;
    // Prefer tokens with Chinese characters (TW stock names).
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(p);
  }).toList();
  if (parts.isEmpty) return null;
  // Longest Chinese-ish token usually is the name.
  parts.sort((a, b) => b.length.compareTo(a.length));
  final name = parts.first;
  if (name.length > 20) return name.substring(0, 20);
  return name;
}

bool _lineHasSharesHint(String line) =>
    RegExp(r'股數|持股|庫存|持有|張數|股$').hasMatch(line);

bool _lineHasCostHint(String line) =>
    RegExp(r'成本|均價|平均|買進均價|參考成本').hasMatch(line);

bool _lineHasPriceNoise(String line) =>
    RegExp(r'現價|市價|成交價|漲跌|報酬率|損益|市值').hasMatch(line) &&
    !_lineHasCostHint(line);

/// Parse messy OCR text into candidate holdings rows.
List<OcrHoldingDraft> parseHoldingsFromOcrText(String rawText) {
  final text = _normalizeOcr(rawText);
  final lines = text
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  // Flatten for keyword-distance fallback.
  final draftsByCode = <String, OcrHoldingDraft>{};
  final order = <String>[];

  void ensure(String code, {String? name, String? hint}) {
    if (!draftsByCode.containsKey(code)) {
      draftsByCode[code] = OcrHoldingDraft(
        code: code,
        name: name ?? '',
        rawHint: hint ?? '',
      );
      order.add(code);
    } else {
      final d = draftsByCode[code]!;
      if ((d.name.isEmpty) && name != null && name.isNotEmpty) {
        d.name = name;
      }
      if (hint != null && hint.isNotEmpty) {
        d.rawHint = '${d.rawHint} $hint'.trim();
      }
    }
  }

  // Pass 1: locate codes + nearby names.
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final m in _codeRe.allMatches(line)) {
      final code = m.group(1)!;
      if (!_looksLikeTwCode(code)) continue;
      // Skip if this "code" is clearly part of a large money amount context only
      // and line has no stock-ish tokens — still allow; later filters incomplete.
      var name = _extractNameNear(line, code);
      if (name == null || name.isEmpty) {
        // Peek previous/next line for Chinese name-only lines.
        for (final j in [i - 1, i + 1]) {
          if (j < 0 || j >= lines.length) continue;
          final cand = _extractNameNear(lines[j], '');
          if (cand != null &&
              cand.isNotEmpty &&
              !_codeRe.hasMatch(lines[j])) {
            name = cand;
            break;
          }
        }
      }
      final window = [
        if (i > 0) lines[i - 1],
        line,
        if (i + 1 < lines.length) lines[i + 1],
        if (i + 2 < lines.length) lines[i + 2],
      ].join(' | ');
      ensure(code, name: name, hint: window);
    }
  }

  if (order.isEmpty) return [];

  // Pass 2: assign shares / avg cost from local windows.
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final codesOnLine =
        _codeRe.allMatches(line).map((m) => m.group(1)!).where(_looksLikeTwCode).toList();

    // Build a search window around this line.
    final start = (i - 1).clamp(0, lines.length);
    final end = (i + 3).clamp(0, lines.length);
    final windowLines = lines.sublist(start, end);
    final window = windowLines.join('\n');

    // Determine target code(s) for this window.
    final targets = <String>[];
    if (codesOnLine.isNotEmpty) {
      targets.addAll(codesOnLine);
    } else {
      // Orphan numeric line: attach to nearest prior code within 2 lines.
      for (var j = i; j >= 0 && j >= i - 2; j--) {
        final prevCodes = _codeRe
            .allMatches(lines[j])
            .map((m) => m.group(1)!)
            .where(_looksLikeTwCode)
            .toList();
        if (prevCodes.isNotEmpty) {
          targets.add(prevCodes.last);
          break;
        }
      }
    }
    if (targets.isEmpty) continue;

    // Explicit keyword captures in window.
    double? kwShares;
    double? kwCost;
    final sharesKw = RegExp(
      r'(?:庫存股數|持有股數|股數|持股|張數)\s*[:：]?\s*([\d,]+(?:\.\d+)?)',
    ).firstMatch(window);
    if (sharesKw != null) {
      kwShares = _parseNum(sharesKw.group(1)!);
      // 張 → 股 if labeled 張數 and value looks small.
      if (window.contains('張') && kwShares != null && kwShares < 500) {
        // Only scale when clearly 張; many UIs show 股 already.
        if (RegExp(r'張數').hasMatch(window)) {
          kwShares = kwShares * 1000;
        }
      }
    }
    final lotKw = RegExp(r'([\d,]+(?:\.\d+)?)\s*張').firstMatch(window);
    if (lotKw != null && kwShares == null) {
      final lots = _parseNum(lotKw.group(1)!);
      if (lots != null) kwShares = lots * 1000;
    }
    final costKw = RegExp(
      r'(?:成本均價|平均成本|參考成本|買進均價|成本價|均價|成本)\s*[:：]?\s*([\d,]+(?:\.\d+)?)',
    ).firstMatch(window);
    if (costKw != null) {
      kwCost = _parseNum(costKw.group(1)!);
    }

    // Unlabeled numbers on the code line / next lines (table layout).
    // Typical: CODE NAME SHARES AVG MARKET PnL
    final nums = <({double v, bool hasDot, String src})>[];
    for (final wl in windowLines) {
      if (_lineHasPriceNoise(wl) && !_lineHasCostHint(wl) && !_lineHasSharesHint(wl)) {
        // Skip pure quote/PnL lines for unlabeled harvest, but keep keyword hits.
        continue;
      }
      for (final nm in _numRe.allMatches(wl)) {
        final token = nm.group(1)!;
        // Skip the ticker itself.
        if (_looksLikeTwCode(token.replaceAll(',', '')) &&
            !token.contains('.') &&
            targets.contains(token.replaceAll(',', ''))) {
          continue;
        }
        final v = _parseNum(token);
        if (v == null) continue;
        // Skip percentages / tiny noise.
        if (v == 0) continue;
        nums.add((v: v, hasDot: token.contains('.'), src: wl));
      }
    }

    for (final code in targets) {
      if (!draftsByCode.containsKey(code)) continue;
      final d = draftsByCode[code]!;

      if (kwShares != null && kwShares > 0 && (d.shares == null)) {
        d.shares = kwShares;
      }
      if (kwCost != null && kwCost > 0 && (d.avgCost == null)) {
        d.avgCost = kwCost;
      }

      if (d.shares != null && d.avgCost != null) continue;

      // Classify unlabeled numbers.
      // Prefer: integer-ish large → shares; decimal mid-range → avg cost.
      final shareCands = <double>[];
      final costCands = <double>[];
      for (final n in nums) {
        final v = n.v;
        final intish = !n.hasDot || (v - v.round()).abs() < 1e-9;
        if (intish && v >= 1 && v <= 1e9) {
          // Heuristic: share counts often >= 1; prices can also be integers.
          if (v >= 100 || (v >= 1 && _lineHasSharesHint(n.src))) {
            shareCands.add(v);
          } else if (v < 100 && v > 0) {
            // Ambiguous small integer: could be price (e.g. 88) or shares.
            costCands.add(v);
            if (v >= 10) shareCands.add(v);
          }
        }
        if (n.hasDot && v > 0 && v < 1e6) {
          costCands.add(v);
        } else if (!n.hasDot && v > 0 && v < 100000 && !shareCands.contains(v)) {
          // Integer prices common for high-priced stocks (e.g. 920).
          costCands.add(v);
        }
      }

      if (d.shares == null && shareCands.isNotEmpty) {
        // Prefer the first large integer in reading order.
        shareCands.sort(); // ascending — pick typical lot size carefully
        // Prefer values that look like share counts (multiples of 1000 or >= 100).
        final preferred = shareCands.where((s) => s >= 100 || s % 1000 == 0).toList();
        d.shares = preferred.isNotEmpty ? preferred.first : shareCands.last;
      }
      if (d.avgCost == null && costCands.isNotEmpty) {
        // Prefer dotted numbers; else first mid-range.
        final dotted = nums.where((n) => n.hasDot && costCands.contains(n.v)).map((n) => n.v).toList();
        if (dotted.isNotEmpty) {
          d.avgCost = dotted.first;
        } else {
          // Avoid picking the same value as shares.
          final rest = costCands.where((c) => c != d.shares).toList();
          if (rest.isNotEmpty) d.avgCost = rest.first;
        }
      }
    }
  }

  // Pass 3: cleanup — try normalize ticker validity & drop empties without code.
  final out = <OcrHoldingDraft>[];
  for (final code in order) {
    final d = draftsByCode[code]!;
    // Validate code via normalizeTicker path.
    try {
      normalizeTicker(code);
    } catch (_) {
      continue;
    }
    // Default-select only complete rows; incomplete stay editable & unchecked.
    d.selected = d.isComplete;
    out.add(d);
  }
  return out;
}
''', encoding='utf-8')
print('wrote holdings_ocr.dart', (root / "lib" / "services" / "holdings_ocr.dart").stat().st_size)
