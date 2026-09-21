from pathlib import Path
text = r"""import 'package:flutter_test/flutter_test.dart';
import 'package:stock_helper/services/holdings_ocr.dart';
import 'package:stock_helper/services/names.dart';
import 'package:stock_helper/services/storage.dart';

void main() {
  test('parses name-first broker table like user sample', () {
    const text = '''
股名 種類 股數 成本均價
元大高股息 現股 400 51.49
國泰永續高股息 現股 400 32.87
群益台灣精選高息 現股 200 32.35
''';
    final rows = parseHoldingsFromOcrText(text);
    expect(rows.length, 3);
    expect(rows[0].name, '元大高股息');
    expect(rows[0].shares, 400);
    expect(rows[0].avgCost, closeTo(51.49, 0.001));
    expect(rows[1].name, '國泰永續高股息');
    expect(rows[1].shares, 400);
    expect(rows[1].avgCost, closeTo(32.87, 0.001));
    expect(rows[2].name, '群益台灣精選高息');
    expect(rows[2].shares, 200);
    expect(rows[2].avgCost, closeTo(32.35, 0.001));
  });

  test('enriches name-first rows to ETF codes via NamesService', () {
    final names = NamesService(AppStorage());
    names.debugReplaceMemory({
      '0056': '元大高股息',
      '00878': '國泰永續高股息',
      '00919': '群益台灣精選高息',
      '2330': '台積電',
    });
    final rows = parseHoldingsFromOcrText('''
股名 種類 股數 成本均價
元大高股息 現股 400 51.49
國泰永續高股息 現股 400 32.87
群益台灣精選高息 現股 200 32.35
''');
    enrichDraftsWithNames(rows, names);
    expect(rows[0].code, '0056');
    expect(rows[1].code, '00878');
    expect(rows[2].code, '00919');
    expect(rows.every((e) => e.isComplete), isTrue);
  });

  test('parses labeled code-first multi-row OCR', () {
    const text = '''
庫存明細
2330 台積電
庫存股數 1,000
成本均價 580.50
現價 920
0050 元大台灣50
持有股數 2000
平均成本 140.25
''';
    final rows = parseHoldingsFromOcrText(text);
    expect(rows.any((e) => e.code == '2330'), isTrue);
    final tsmc = rows.firstWhere((e) => e.code == '2330');
    expect(tsmc.shares, 1000);
    expect(tsmc.avgCost, closeTo(580.5, 0.01));
  });

  test('ignores 種類 column token 現股', () {
    final rows = parseHoldingsFromOcrText('元大高股息 現股 400 51.49');
    expect(rows.length, 1);
    expect(rows.first.name.contains('現股'), isFalse);
    expect(rows.first.shares, 400);
  });
}
"""
Path(r'C:\Users\user\Documents\stock-helper-flutter\test\holdings_ocr_test.dart').write_text(text, encoding='utf-8')
print('test rewritten', len(text))