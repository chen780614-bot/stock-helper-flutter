import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_helper/models/models.dart';
import 'package:stock_helper/services/storage.dart';

void main() {
  final groups = [
    HoldingGroup(id: 'g1', name: 'A'),
    HoldingGroup(id: 'g2', name: 'B'),
  ];

  test('resolveActiveHoldingGroupId falls back to first / null', () {
    expect(resolveActiveHoldingGroupId([], 'g1'), isNull);
    expect(resolveActiveHoldingGroupId(groups, null), 'g1');
    expect(resolveActiveHoldingGroupId(groups, 'zzz'), 'g1');
    expect(resolveActiveHoldingGroupId(groups, 'g2'), 'g2');
  });

  test('saving active id notifies listeners and persists (shared by tabs)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStorage();
    final seen = <String?>[];
    s.activeHoldingGroupNotifier.addListener(
        () => seen.add(s.activeHoldingGroupNotifier.value));
    await s.saveActiveHoldingGroupId('g2');
    await s.saveActiveHoldingGroupId('g2'); // unchanged → no extra notify
    await s.saveActiveHoldingGroupId('g1');
    expect(seen, ['g2', 'g1']);
    expect(await s.loadActiveHoldingGroupId(), 'g1');
  });

  test('portfolio holdings follow the active group', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStorage();
    Holding h(String id, String t, double p) =>
        Holding(id: id, ticker: t, name: t, buyPrice: p, shares: 10);
    await s.saveHoldingGroups([
      HoldingGroup(id: 'g1', name: 'A', items: [h('1', '2330.TW', 500)]),
      HoldingGroup(id: 'g2', name: 'B', items: [h('2', '0050.TW', 150)]),
    ]);
    await s.saveActiveHoldingGroupId('g2');
    var items = await s.loadPortfolioHoldings(activeGroupOnly: true);
    expect(items.single.ticker, '0050.TW');
    await s.saveActiveHoldingGroupId('g1');
    items = await s.loadPortfolioHoldings(activeGroupOnly: true);
    expect(items.single.ticker, '2330.TW');
  });
}
