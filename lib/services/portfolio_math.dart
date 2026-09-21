import '../models/models.dart';

/// Shared portfolio aggregates so 首頁 and 成本損益 never diverge.
class PortfolioTotals {
  const PortfolioTotals({
    required this.totalCost,
    required this.totalMarketValue,
    required this.hasMarketValue,
    required this.unrealizedPnl,
    required this.unrealizedPnlPct,
    required this.dayPnl,
    required this.hasDayPnl,
    required this.quotedCount,
    required this.holdingCount,
  });

  /// Sum of cost basis for every holding (quoted or not).
  final double totalCost;

  /// Sum of price × shares for holdings with a successful quote.
  final double totalMarketValue;

  final bool hasMarketValue;

  /// Unrealized P&L using only holdings that have quotes:
  /// Σ(mv − cost) for quoted rows. Avoids subtracting cost of unquoted
  /// names from a partial market-value sum.
  final double? unrealizedPnl;

  final double? unrealizedPnlPct;

  /// Σ(price − previousClose) × shares when previousClose is known.
  final double? dayPnl;

  final bool hasDayPnl;

  final int quotedCount;
  final int holdingCount;
}

/// Position weight by market value (quoted holdings only).
class PortfolioWeight {
  const PortfolioWeight({
    required this.holding,
    required this.marketValue,
    required this.weight,
  });

  final Holding holding;
  final double marketValue;

  /// Fraction of [PortfolioTotals.totalMarketValue]; 0 if no MV.
  final double weight;
}

/// Compute cost / market value / unrealized / day P&L from one holdings list
/// and one quotes map. Both UI tabs must call this.
PortfolioTotals computePortfolioTotals({
  required List<Holding> holdings,
  required Map<String, Quote> quotes,
}) {
  var totalCost = 0.0;
  var totalMv = 0.0;
  var quotedCost = 0.0;
  var hasMv = false;
  var quotedCount = 0;
  double? dayPnl;
  var hasDay = false;

  for (final h in holdings) {
    totalCost += h.cost;
    final q = quotes[h.ticker];
    if (q == null || !q.ok) continue;
    final mv = q.price * h.shares;
    totalMv += mv;
    quotedCost += h.cost;
    hasMv = true;
    quotedCount++;
    final prev = q.previousClose;
    if (prev != null && prev > 0) {
      dayPnl = (dayPnl ?? 0) + (q.price - prev) * h.shares;
      hasDay = true;
    }
  }

  final unrealized = hasMv ? totalMv - quotedCost : null;
  final unrealizedPct =
      (unrealized != null && quotedCost > 0) ? unrealized / quotedCost : null;

  return PortfolioTotals(
    totalCost: totalCost,
    totalMarketValue: totalMv,
    hasMarketValue: hasMv,
    unrealizedPnl: unrealized,
    unrealizedPnlPct: unrealizedPct,
    dayPnl: dayPnl,
    hasDayPnl: hasDay,
    quotedCount: quotedCount,
    holdingCount: holdings.length,
  );
}

/// Market-value weights for the same holdings/quotes pair (quoted only).
List<PortfolioWeight> computePortfolioWeights({
  required List<Holding> holdings,
  required Map<String, Quote> quotes,
}) {
  final rows = <({Holding h, double mv})>[];
  var totalMv = 0.0;
  for (final h in holdings) {
    final q = quotes[h.ticker];
    if (q == null || !q.ok) continue;
    final mv = q.price * h.shares;
    totalMv += mv;
    rows.add((h: h, mv: mv));
  }
  if (totalMv <= 0) return const [];
  final out = [
    for (final r in rows)
      PortfolioWeight(
        holding: r.h,
        marketValue: r.mv,
        weight: r.mv / totalMv,
      ),
  ];
  out.sort((a, b) => b.weight.compareTo(a.weight));
  return out;
}

/// Flatten every group's items then consolidate by ticker (portfolio-wide).
List<Holding> flattenAndConsolidateGroups(List<HoldingGroup> groups) {
  final flat = <Holding>[
    for (final g in groups) ...g.items,
  ];
  return consolidateHoldings(flat);
}

/// Active group items (already consolidated per group on load), or empty.
List<Holding> holdingsInActiveGroup(
  List<HoldingGroup> groups,
  String? activeGroupId,
) {
  if (groups.isEmpty) return const [];
  HoldingGroup g = groups.first;
  if (activeGroupId != null) {
    for (final x in groups) {
      if (x.id == activeGroupId) {
        g = x;
        break;
      }
    }
  }
  return List<Holding>.from(g.items);
}
