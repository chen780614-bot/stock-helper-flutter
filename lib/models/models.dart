import 'package:uuid/uuid.dart';

class Holding {
  Holding({
    required this.id,
    required this.ticker,
    required this.name,
    required this.buyPrice,
    required this.shares,
    this.note = '',
  });

  final String id;
  final String ticker;
  final String name;
  /// Weighted average buy price when merged from multiple lots.
  final double buyPrice;
  final double shares;
  final String note;

  /// Actual invested amount (= per-share actual cost × shares).
  double get cost => buyPrice * shares;

  /// Per-share actual cost (alias of [buyPrice], which already stores the
  /// weighted average including fees when the user entered an invested amount).
  double get costPerShare => buyPrice;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticker': ticker,
        'name': name,
        'buyPrice': buyPrice,
        'shares': shares,
        'note': note,
      };

  factory Holding.fromJson(Map<String, dynamic> j) {
    num? price = j['buyPrice'] as num?;
    price ??= j['avgCost'] as num?;
    price ??= j['price'] as num?;
    price ??= j['cost'] as num?;
    final sharesRaw = j['shares'] as num? ?? j['qty'] as num? ?? 0;
    return Holding(
      id: (j['id'] as String?)?.trim().isNotEmpty == true
          ? j['id'] as String
          : '',
      ticker: (j['ticker'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      buyPrice: (price ?? 0).toDouble(),
      shares: sharesRaw.toDouble(),
      note: (j['note'] as String?) ?? '',
    );
  }

  Holding copyWith({
    String? id,
    String? ticker,
    String? name,
    double? buyPrice,
    double? shares,
    String? note,
  }) =>
      Holding(
        id: id ?? this.id,
        ticker: ticker ?? this.ticker,
        name: name ?? this.name,
        buyPrice: buyPrice ?? this.buyPrice,
        shares: shares ?? this.shares,
        note: note ?? this.note,
      );
}

/// Realized P&L from a sell against average cost.
class SellRecord {
  SellRecord({
    required this.id,
    required this.ticker,
    required this.name,
    required this.avgCost,
    required this.sellPrice,
    required this.shares,
    required this.soldAt,
    this.note = '',
  });

  final String id;
  final String ticker;
  final String name;
  final double avgCost;
  final double sellPrice;
  final double shares;
  final DateTime soldAt;
  final String note;

  double get proceeds => sellPrice * shares;
  double get costBasis => avgCost * shares;
  double get pnl => proceeds - costBasis;
  double? get pnlPct => costBasis == 0 ? null : pnl / costBasis;

  int get year => soldAt.year;
  int get month => soldAt.month;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticker': ticker,
        'name': name,
        'avgCost': avgCost,
        'sellPrice': sellPrice,
        'shares': shares,
        'soldAt': soldAt.toIso8601String(),
        'note': note,
      };

  factory SellRecord.fromJson(Map<String, dynamic> j) => SellRecord(
        id: (j['id'] as String?)?.trim().isNotEmpty == true
            ? j['id'] as String
            : '',
        ticker: j['ticker'] as String,
        name: (j['name'] as String?) ?? '',
        avgCost: (j['avgCost'] as num).toDouble(),
        sellPrice: (j['sellPrice'] as num).toDouble(),
        shares: (j['shares'] as num).toDouble(),
        soldAt: DateTime.parse(j['soldAt'] as String),
        note: (j['note'] as String?) ?? '',
      );
}


/// Cash dividend / interest-like income recorded into 總收益 (not a sell).
class IncomeRecord {
  IncomeRecord({
    required this.id,
    required this.ticker,
    required this.name,
    required this.amount,
    required this.receivedAt,
    this.note = '',
    this.kind = 'dividend',
  });

  final String id;
  final String ticker;
  final String name;
  /// Amount received in TWD (positive).
  final double amount;
  final DateTime receivedAt;
  final String note;
  /// `dividend` (股利) or `interest` (息／配息類).
  final String kind;

  String get kindLabel => kind == 'interest' ? '息' : '股利';

  /// Treat as realized P&L contribution.
  double get pnl => amount;

  int get year => receivedAt.year;
  int get month => receivedAt.month;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticker': ticker,
        'name': name,
        'amount': amount,
        'receivedAt': receivedAt.toIso8601String(),
        'note': note,
        'kind': kind,
      };

  factory IncomeRecord.fromJson(Map<String, dynamic> j) => IncomeRecord(
        id: (j['id'] as String?)?.trim().isNotEmpty == true
            ? j['id'] as String
            : '',
        ticker: j['ticker'] as String,
        name: (j['name'] as String?) ?? '',
        amount: (j['amount'] as num).toDouble(),
        receivedAt: DateTime.parse(j['receivedAt'] as String),
        note: (j['note'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? 'dividend',
      );

  IncomeRecord copyWith({
    String? id,
    String? ticker,
    String? name,
    double? amount,
    DateTime? receivedAt,
    String? note,
    String? kind,
  }) =>
      IncomeRecord(
        id: id ?? this.id,
        ticker: ticker ?? this.ticker,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        receivedAt: receivedAt ?? this.receivedAt,
        note: note ?? this.note,
        kind: kind ?? this.kind,
      );
}

Map<int, Map<int, List<IncomeRecord>>> groupIncomesByYearMonth(
  List<IncomeRecord> records,
) {
  final out = <int, Map<int, List<IncomeRecord>>>{};
  for (final r in records) {
    out.putIfAbsent(r.year, () => {});
    out[r.year]!.putIfAbsent(r.month, () => []);
    out[r.year]![r.month]!.add(r);
  }
  for (final y in out.keys) {
    for (final m in out[y]!.keys) {
      out[y]![m]!.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    }
  }
  return out;
}

double sumIncome(Iterable<IncomeRecord> records) =>
    records.fold(0.0, (a, r) => a + r.amount);

/// Per-share actual cost from an actual invested amount (incl. fees).
double costPerShareFromInvested(double invested, double shares) {
  if (shares <= 0) throw ArgumentError('股數必須大於 0');
  if (invested <= 0) throw ArgumentError('實際投入金額必須大於 0');
  return invested / shares;
}

/// Build a purchase lot. If [invested] is given it wins over [buyPrice]:
/// buyPrice (per-share actual cost) = invested / shares.
Holding buildPurchaseLot({
  required String id,
  required String ticker,
  required String name,
  required double shares,
  double? buyPrice,
  double? invested,
  String note = '',
}) {
  if (shares <= 0) throw ArgumentError('請輸入有效股數');
  final double price;
  if (invested != null) {
    price = costPerShareFromInvested(invested, shares);
  } else {
    if (buyPrice == null || buyPrice <= 0) {
      throw ArgumentError('請輸入有效買入價');
    }
    price = buyPrice;
  }
  return Holding(
    id: id,
    ticker: ticker,
    name: name,
    buyPrice: price,
    shares: shares,
    note: note,
  );
}

/// Apply a sell to holdings using average-cost; returns updated list + record.
({List<Holding> holdings, SellRecord record}) applySell({
  required List<Holding> holdings,
  required Holding holding,
  required double sellShares,
  required double sellPrice,
  DateTime? soldAt,
}) {
  if (sellShares <= 0) throw ArgumentError('賣出股數必須大於 0');
  if (sellPrice < 0) throw ArgumentError('賣出價格不可為負數');
  if (sellShares > holding.shares + 1e-9) {
    throw ArgumentError('賣出股數不可超過目前持有股數');
  }
  final when = soldAt ?? DateTime.now();
  final record = SellRecord(
    id: const Uuid().v4(),
    ticker: holding.ticker,
    name: holding.name,
    avgCost: holding.buyPrice,
    sellPrice: sellPrice,
    shares: sellShares,
    soldAt: when,
  );
  final remain = holding.shares - sellShares;
  final next = List<Holding>.from(holdings);
  final idx = next.indexWhere((e) => e.id == holding.id);
  if (idx < 0) throw ArgumentError('找不到該持倉');
  if (remain <= 1e-9) {
    next.removeAt(idx);
  } else {
    next[idx] = holding.copyWith(shares: remain);
  }
  return (holdings: next, record: record);
}


/// Group sell records: year → month → list (newest year/month first).
Map<int, Map<int, List<SellRecord>>> groupSellsByYearMonth(
  List<SellRecord> records,
) {
  final out = <int, Map<int, List<SellRecord>>>{};
  for (final r in records) {
    out.putIfAbsent(r.year, () => {});
    out[r.year]!.putIfAbsent(r.month, () => []);
    out[r.year]![r.month]!.add(r);
  }
  for (final y in out.keys) {
    for (final m in out[y]!.keys) {
      out[y]![m]!.sort((a, b) => b.soldAt.compareTo(a.soldAt));
    }
  }
  return out;
}

double sumPnl(Iterable<SellRecord> records) =>
    records.fold(0.0, (a, r) => a + r.pnl);

/// Merge lots of the same ticker into one weighted-average-cost holding.
Holding mergeLots(List<Holding> lots, {String? preferId}) {
  if (lots.isEmpty) {
    throw ArgumentError('lots 不可為空');
  }
  if (lots.length == 1) return lots.first;
  final ticker = lots.first.ticker;
  final name = lots
      .map((e) => e.name)
      .firstWhere((n) => n.isNotEmpty, orElse: () => lots.first.name);
  var totalShares = 0.0;
  var totalCost = 0.0;
  final notes = <String>[];
  for (final h in lots) {
    if (h.ticker != ticker) {
      throw ArgumentError('只能合併同一代號');
    }
    totalShares += h.shares;
    totalCost += h.cost;
    if (h.note.trim().isNotEmpty) notes.add(h.note.trim());
  }
  final avg = totalShares == 0 ? 0.0 : totalCost / totalShares;
  return Holding(
    id: preferId ?? lots.first.id,
    ticker: ticker,
    name: name,
    buyPrice: avg,
    shares: totalShares,
    note: notes.isEmpty ? '' : notes.join('；'),
  );
}

List<Holding> consolidateHoldings(List<Holding> items) {
  if (items.isEmpty) return [];
  final order = <String>[];
  final groups = <String, List<Holding>>{};
  for (final h in items) {
    if (!groups.containsKey(h.ticker)) {
      order.add(h.ticker);
      groups[h.ticker] = [];
    }
    groups[h.ticker]!.add(h);
  }
  return [for (final t in order) mergeLots(groups[t]!)];
}

List<Holding> addOrMergeHolding(List<Holding> items, Holding purchase) {
  final idx = items.indexWhere((e) => e.ticker == purchase.ticker);
  if (idx < 0) return [...items, purchase];
  final merged = mergeLots([items[idx], purchase], preferId: items[idx].id);
  final next = List<Holding>.from(items);
  next[idx] = merged;
  return next;
}

/// Undo a sell: put shares back into holdings at the recorded average cost.
List<Holding> restoreHoldingFromSell(List<Holding> holdings, SellRecord record) {
  final lot = Holding(
    id: const Uuid().v4(),
    ticker: record.ticker,
    name: record.name,
    buyPrice: record.avgCost,
    shares: record.shares,
  );
  return addOrMergeHolding(holdings, lot);
}


class Quote {
  Quote({
    required this.ticker,
    required this.shortName,
    required this.price,
    required this.currency,
    this.asOf,
    this.error,
    this.priorClose = false,
    this.previousClose,
  });

  final String ticker;
  final String shortName;
  final double price;
  final String currency;
  final DateTime? asOf;
  final String? error;
  /// True when price is previous/session close (market not in regular session).
  final bool priorClose;
  /// Prior session close when known (for day P&L vs 昨收).
  final double? previousClose;

  bool get ok => error == null && price > 0;
}

class WatchItem {
  WatchItem({required this.id, required this.ticker, required this.name});
  final String id;
  final String ticker;
  final String name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticker': ticker,
        'name': name,
      };

  factory WatchItem.fromJson(Map<String, dynamic> j) => WatchItem(
        id: (j['id'] as String?)?.trim().isNotEmpty == true
            ? j['id'] as String
            : '',
        ticker: j['ticker'] as String,
        name: (j['name'] as String?) ?? '',
      );

  WatchItem copyWith({String? id, String? ticker, String? name}) => WatchItem(
        id: id ?? this.id,
        ticker: ticker ?? this.ticker,
        name: name ?? this.name,
      );
}

/// Watchlist group (multi-group + optional note).
class WatchGroup {
  WatchGroup({
    required this.id,
    required this.name,
    this.note = '',
    List<WatchItem>? items,
  }) : items = items ?? [];

  final String id;
  final String name;
  final String note;
  final List<WatchItem> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory WatchGroup.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['items'] as List?) ?? const [];
    return WatchGroup(
      id: (j['id'] as String?)?.trim().isNotEmpty == true
          ? j['id'] as String
          : '',
      name: (j['name'] as String?)?.trim().isNotEmpty == true
          ? j['name'] as String
          : '預設清單',
      note: (j['note'] as String?) ?? '',
      items: rawItems
          .map((e) => WatchItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  WatchGroup copyWith({
    String? id,
    String? name,
    String? note,
    List<WatchItem>? items,
  }) =>
      WatchGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        note: note ?? this.note,
        items: items ?? this.items,
      );
}


/// Holdings group (multi-group, same UX as watchlist).
class HoldingGroup {
  HoldingGroup({
    required this.id,
    required this.name,
    this.note = '',
    List<Holding>? items,
  }) : items = items ?? [];

  final String id;
  final String name;
  final String note;
  final List<Holding> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory HoldingGroup.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['items'] as List?) ?? const [];
    return HoldingGroup(
      id: (j['id'] as String?)?.trim().isNotEmpty == true
          ? j['id'] as String
          : '',
      name: (j['name'] as String?)?.trim().isNotEmpty == true
          ? j['name'] as String
          : '預設持倉',
      note: (j['note'] as String?) ?? '',
      items: rawItems
          .map((e) => Holding.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  HoldingGroup copyWith({
    String? id,
    String? name,
    String? note,
    List<Holding>? items,
  }) =>
      HoldingGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        note: note ?? this.note,
        items: items ?? this.items,
      );
}


/// Resolve which holding group is active: the persisted [activeId] if it still
/// exists, otherwise the first group (same fallback as portfolio math).
/// Returns null when there are no groups.
String? resolveActiveHoldingGroupId(List<HoldingGroup> groups, String? activeId) {
  if (groups.isEmpty) return null;
  if (activeId != null && groups.any((g) => g.id == activeId)) return activeId;
  return groups.first.id;
}
