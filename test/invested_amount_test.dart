import 'package:flutter_test/flutter_test.dart';
import 'package:stock_helper/models/models.dart';

void main() {
  Holding lot({
    String id = 'a',
    double shares = 1000,
    double? price,
    double? invested,
  }) =>
      buildPurchaseLot(
        id: id,
        ticker: '2330.TW',
        name: '台積電',
        shares: shares,
        buyPrice: price,
        invested: invested,
      );

  test('invested-only: per-share cost = invested / shares', () {
    final h = lot(shares: 3, invested: 1000);
    expect(h.buyPrice, closeTo(333.3333333, 1e-6));
    expect(h.costPerShare, h.buyPrice);
    expect(h.cost, closeTo(1000, 1e-9));
  });

  test('price x shares unchanged when invested empty', () {
    final h = lot(shares: 1000, price: 100.5);
    expect(h.buyPrice, 100.5);
    expect(h.cost, 100500);
  });

  test('invested wins when both given', () {
    final h = lot(shares: 1000, price: 100, invested: 100142);
    expect(h.buyPrice, closeTo(100.142, 1e-9));
    expect(h.cost, closeTo(100142, 1e-6));
  });

  test('validation', () {
    expect(() => lot(shares: 0, invested: 100), throwsArgumentError);
    expect(() => lot(shares: 10, invested: 0), throwsArgumentError);
    expect(() => lot(shares: 10), throwsArgumentError);
    expect(() => lot(shares: 10, price: 0), throwsArgumentError);
  });

  test('merge: avg = sum invested / sum shares', () {
    var items = <Holding>[];
    items = addOrMergeHolding(items, lot(id: 'a', shares: 1000, invested: 100142));
    items = addOrMergeHolding(items, lot(id: 'b', shares: 3, invested: 1000));
    items = addOrMergeHolding(items, lot(id: 'c', shares: 500, price: 98.5));
    expect(items.length, 1);
    final h = items.single;
    expect(h.id, 'a');
    expect(h.shares, 1503);
    final totalInvested = 100142 + 1000 + 500 * 98.5;
    expect(h.cost, closeTo(totalInvested, 1e-6));
    expect(h.buyPrice, closeTo(totalInvested / 1503, 1e-9));
  });

  test('old JSON (no new fields) still parses; toJson schema unchanged', () {
    final h = Holding.fromJson({
      'id': 'x',
      'ticker': '0050.TW',
      'name': '元大台灣50',
      'buyPrice': 150.25,
      'shares': 200,
      'note': '',
    });
    expect(h.cost, closeTo(30050, 1e-9));
    expect(h.toJson().keys.toSet(),
        {'id', 'ticker', 'name', 'buyPrice', 'shares', 'note'});
    final legacy = Holding.fromJson({'ticker': '2330.TW', 'avgCost': 500, 'qty': 10});
    expect(legacy.cost, 5000);
    final g = HoldingGroup.fromJson({
      'id': 'g',
      'name': 'G',
      'items': [h.toJson()],
    });
    expect(g.items.single.buyPrice, 150.25);
  });
}
