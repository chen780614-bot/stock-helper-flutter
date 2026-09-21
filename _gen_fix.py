# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"C:\Users\user\Documents\stock-helper-flutter\lib\screens\holdings_screen.dart")
t = p.read_text(encoding="utf-8")
old = '''                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: working.length,
                        itemBuilder: (ctx, i) {'''
new = '''                    SizedBox(
                      height: MediaQuery.of(ctx).size.height * 0.5,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: working.length,
                        itemBuilder: (ctx, i) {'''
if old not in t:
    raise SystemExit('Flexible block not found')
p.write_text(t.replace(old, new, 1), encoding="utf-8")
print('dialog layout fixed')

# unit test for parser
test = Path(r"C:\Users\user\Documents\stock-helper-flutter\test\holdings_ocr_test.dart")
test.write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:stock_helper/services/holdings_ocr.dart';

void main() {
  test('parses labeled broker-style multi-row OCR', () {
    const text = '''
庫存明細
2330 台積電
庫存股數 1,000
成本均價 580.50
現價 920
0050 元大台灣50
持有股數 2000
平均成本 140.25
00878 國泰永續高股息
股數 3,000
成本 22.8
''';
    final rows = parseHoldingsFromOcrText(text);
    expect(rows.length, greaterThanOrEqualTo(3));
    final tsmc = rows.firstWhere((e) => e.code == '2330');
    expect(tsmc.name.contains('台積'), isTrue);
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
    const text = '2330 台積電 1000 580.5 920.0\n2317 鴻海 500 105';
    final rows = parseHoldingsFromOcrText(text);
    expect(rows.any((e) => e.code == '2330'), isTrue);
    final t = rows.firstWhere((e) => e.code == '2330');
    expect(t.shares, isNotNull);
    expect(t.avgCost, isNotNull);
  });
}
''', encoding='utf-8')
print('test written')
