class AllocationRow {
  AllocationRow({
    required this.ticker,
    required this.name,
    required this.price,
    required this.shares,
    required this.cost,
  });
  final String ticker;
  final String name;
  final double price;
  final int shares;
  final double cost;
}

class AllocationResult {
  AllocationResult({
    required this.mode,
    required this.lotSize,
    required this.capital,
    required this.rows,
    required this.leftover,
    this.nSharesEach,
  });
  final String mode; // equal_n | equal_dollar
  final int lotSize;
  final double capital;
  final List<AllocationRow> rows;
  final double leftover;
  final int? nSharesEach;
}

int _floorToLot(int shares, int lotSize) {
  if (lotSize <= 1) return shares < 0 ? 0 : shares;
  if (shares <= 0) return 0;
  return (shares ~/ lotSize) * lotSize;
}

AllocationResult allocateEqualN({
  required double capital,
  required List<double> prices,
  required List<String> tickers,
  List<String>? names,
  int lotSize = 1,
}) {
  if (capital < 0) throw ArgumentError('資本不可為負數');
  if (lotSize < 1) throw ArgumentError('整股單位必須 >= 1');
  if (prices.length != tickers.length) {
    throw ArgumentError('prices 與 tickers 長度不一致');
  }
  final nm = names ?? List<String>.from(tickers);
  if (prices.isEmpty) {
    return AllocationResult(
      mode: 'equal_n',
      lotSize: lotSize,
      capital: capital,
      rows: [],
      leftover: capital,
      nSharesEach: 0,
    );
  }
  if (prices.any((p) => p <= 0)) throw ArgumentError('價格必須為正數');
  final unitCost = prices.fold<double>(0, (a, b) => a + b) * lotSize;
  final n = unitCost > 0 ? (capital / unitCost).floor() : 0;
  final sharesEach = n * lotSize;
  final rows = <AllocationRow>[];
  var total = 0.0;
  for (var i = 0; i < tickers.length; i++) {
    final cost = sharesEach * prices[i];
    total += cost;
    rows.add(AllocationRow(
      ticker: tickers[i],
      name: nm[i],
      price: prices[i],
      shares: sharesEach,
      cost: cost,
    ));
  }
  return AllocationResult(
    mode: 'equal_n',
    lotSize: lotSize,
    capital: capital,
    rows: rows,
    leftover: capital - total,
    nSharesEach: sharesEach,
  );
}

AllocationResult allocateEqualDollar({
  required double capital,
  required List<double> prices,
  required List<String> tickers,
  List<String>? names,
  int lotSize = 1,
}) {
  if (capital < 0) throw ArgumentError('資本不可為負數');
  if (lotSize < 1) throw ArgumentError('整股單位必須 >= 1');
  if (prices.length != tickers.length) {
    throw ArgumentError('prices 與 tickers 長度不一致');
  }
  final nm = names ?? List<String>.from(tickers);
  if (prices.isEmpty) {
    return AllocationResult(
      mode: 'equal_dollar',
      lotSize: lotSize,
      capital: capital,
      rows: [],
      leftover: capital,
    );
  }
  if (prices.any((p) => p <= 0)) throw ArgumentError('價格必須為正數');
  final budget = capital / prices.length;
  final rows = <AllocationRow>[];
  var total = 0.0;
  for (var i = 0; i < tickers.length; i++) {
    final rawShares = (budget / prices[i]).floor();
    final shares = _floorToLot(rawShares, lotSize);
    final cost = shares * prices[i];
    total += cost;
    rows.add(AllocationRow(
      ticker: tickers[i],
      name: nm[i],
      price: prices[i],
      shares: shares,
      cost: cost,
    ));
  }
  return AllocationResult(
    mode: 'equal_dollar',
    lotSize: lotSize,
    capital: capital,
    rows: rows,
    leftover: capital - total,
  );
}
