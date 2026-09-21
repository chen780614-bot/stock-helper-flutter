from pathlib import Path
text = """import 'package:flutter_test/flutter_test.dart';
import 'package:stock_helper/services/holdings_ocr.dart';

void main() {
  test('parses labeled broker-style multi-row OCR', () {
    const text = '''
\u5eab\u5b58\u660e\u7d30
2330 \u53f0\u7a4d\u96fb
\u5eab\u5b58\u80a1\u6578 1,000
\u6210\u672c\u5747\u50f9 580.50
\u73fe\u50f9 920
0050 \u5143\u5927\u53f0\u706350
\u6301\u6709\u80a1\u6578 2000
\u5e73\u5747\u6210\u672c 140.25
00878 \u570b\u6cf0\u6c38\u7e8c\u9ad8\u80a1\u606f
\u80a1\u6578 3,000
\u6210\u672c 22.8
''';
    final rows = parseHoldingsFromOcrText(text);
    expect(rows.length, greaterThanOrEqualTo(3));
    final tsmc = rows.firstWhere((e) => e.code == '2330');
    expect(tsmc.name.contains('\u53f0\u7a4d'), isTrue);
    expect(tsmc.shares, 1000);
    expect(tsmc.avgCost, closeTo(580.5, 0.01));
    final etf = rows.firstWhere((e) => e.code == '0050');
    expect(etf.shares, 2000);
    expect(etf.avgCost, closeTo(140.25, 0.01));
    final div = rows.firstWhere((e) => e.code == '00878');
    expect(div.shares, 3000);
    expect(div.avgCost, closeTo(22.8, 0.01));
  });

  test('parses compact table-like line', () {
    const text = '2330 \u53f0\u7a4d\u96fb 1000 580.5 920.0\\n2317 \u9d3b\u6d77 500 105';
    final rows = parseHoldingsFromOcrText(text);
    expect(rows.any((e) => e.code == '2330'), isTrue);
    final t = rows.firstWhere((e) => e.code == '2330');
    expect(t.shares, isNotNull);
    expect(t.avgCost, isNotNull);
  });
}
"""
Path(r'C:\Users\user\Documents\stock-helper-flutter\test\holdings_ocr_test.dart').write_text(text, encoding='utf-8')
print('test ok', len(text))