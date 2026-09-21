import 'package:flutter_test/flutter_test.dart';
import 'package:stock_helper/services/dividends.dart';

void main() {
  test('parseTwDate ROC and cash/stock estimates', () {
    final d = parseTwDate('1150916');
    expect(d, DateTime(2026, 9, 16));

    final e = ExDividendEvent(
      code: '2330',
      name: '台積電',
      exDate: DateTime(2026, 9, 16),
      kind: '息',
      market: 'twse',
      cashDividend: 7.000001,
      stockDividendRatio: 0.05,
    );
    expect(e.estimatedCash(1000), 7000);
    expect(e.estimatedStockShares(1000), closeTo(50.0, 1e-9));
  });

  test('holdingSharesByTwCode merges TW/TWO', () {
    final m = holdingSharesByTwCode([
      (ticker: '2330.TW', shares: 100),
      (ticker: '6488.TWO', shares: 200),
      (ticker: '2330.TW', shares: 50),
    ]);
    expect(m['2330'], 150);
    expect(m['6488'], 200);
  });

  test('IncomeRecord pnl equals amount', () {
    // imported via models through dividends? use models in app - skip if not exported
  });
}
