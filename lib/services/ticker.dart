/// Taiwan listed codes: 4–6 digits, optional letter suffix (ETF/特別股等), e.g. 2330, 00407A, 00679B, 2883B.
final RegExp kTwBareCode = RegExp(r'^\d{4,6}[A-Z]{0,2}$');
final RegExp kTwSuffixedCode = RegExp(r'^(\d{4,6}[A-Z]{0,2})\.(TW|TWO)$');
final RegExp kTwAliasCode = RegExp(r'^(\d{4,6}[A-Z]{0,2})[\s\-_]+(TW|TWO)$');

String normalizeTicker(String raw) {
  final s = raw.trim().toUpperCase();
  if (s.isEmpty) {
    throw ArgumentError('股票代號不可為空');
  }
  final m1 = kTwSuffixedCode.firstMatch(s);
  if (m1 != null) return s;

  if (kTwBareCode.hasMatch(s)) return '$s.TW';

  final m2 = kTwAliasCode.firstMatch(s);
  if (m2 != null) return '${m2.group(1)}.${m2.group(2)}';

  final us = RegExp(r'^[A-Z][A-Z0-9.\-]{0,9}$');
  if (us.hasMatch(s)) return s;

  throw ArgumentError('無法辨識的股票代號：$raw');
}

bool isTaiwanTicker(String ticker) {
  return RegExp(r'\.(TW|TWO)$').hasMatch(ticker.toUpperCase());
}

String? extractTwCode(String ticker) {
  final s = ticker.trim().toUpperCase();
  final m = kTwSuffixedCode.firstMatch(s);
  if (m != null) return m.group(1);
  if (kTwBareCode.hasMatch(s)) return s;
  return null;
}

/// True when [raw] looks like a TW code (bare or with .TW/.TWO), before full normalize.
bool looksLikeTwCode(String raw) {
  final s = raw.trim().toUpperCase();
  if (s.isEmpty) return false;
  return kTwBareCode.hasMatch(s) ||
      kTwSuffixedCode.hasMatch(s) ||
      kTwAliasCode.hasMatch(s);
}

String formatLabel(String name, String ticker) {
  final n = name.trim();
  if (n.isEmpty) return ticker;
  return '$n（$ticker）';
}
