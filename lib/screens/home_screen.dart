import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/dividends.dart';
import '../services/names.dart';
import '../services/quotes.dart';
import '../services/portfolio_math.dart';
import '../services/storage.dart';
import '../services/ticker.dart';
import '../theme.dart';
import '../widgets/income_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.storage,
    required this.names,
    required this.quotes,
    required this.dividends,
    this.active = true,
  });

  final AppStorage storage;
  final NamesService names;
  final QuotesService quotes;
  final DividendsService dividends;
  final bool active;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Holding> _holdings = [];
  Map<String, Quote> _quotes = {};
  List<({ExDividendEvent event, double shares})> _exEvents = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _divFailed = false;
  Timer? _timer;
  final _money = NumberFormat('#,##0.##');
  final _cash = NumberFormat('#,##0');
  final _sharesFmt = NumberFormat('#,##0.####');
  final _pct = NumberFormat('0.0%;-0.0%');
  final _day = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _bootstrap();
    if (widget.active) _armTimer();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _reload();
      _armTimer();
    } else if (!widget.active && oldWidget.active) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || !widget.active || _refreshing) return;
      _refreshQuotes(force: true);
    });
  }

  Future<void> _bootstrap() async {
    await widget.names.ensureLoaded();
    // Fire-and-forget full TWSE+TPEx+興櫃 name map.
    widget.names.refreshFromMarkets();
    await _reload();
  }

  Future<void> _reload() async {
    setState(() => _refreshing = true);
    // Same universe as 成本損益 (active holding group).
    final items = await widget.storage.loadPortfolioHoldings(activeGroupOnly: true);
    if (!mounted) return;
    setState(() {
      _holdings = items;
      _loading = false;
    });
    await Future.wait([
      _refreshQuotes(force: true),
      _loadDividends(force: false),
    ]);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _refreshQuotes({bool force = false}) async {
    if (_holdings.isEmpty) {
      if (mounted) setState(() => _quotes = {});
      return;
    }
    final tickers = _holdings.map((e) => e.ticker).toSet().toList();
    final q = await widget.quotes.fetchQuotes(tickers, force: force);
    if (!mounted) return;
    setState(() => _quotes = q);
  }

  Future<void> _loadDividends({bool force = false}) async {
    final map = holdingSharesByTwCode(
      _holdings.map((h) => (ticker: h.ticker, shares: h.shares)),
    );
    final events = await widget.dividends.forHoldings(
      codeToShares: map,
      force: force,
    );
    if (!mounted) return;
    setState(() {
      _exEvents = events;
      _divFailed = widget.dividends.lastFetchFailed && events.isEmpty;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totals = computePortfolioTotals(holdings: _holdings, quotes: _quotes);
    final totalMv = totals.totalMarketValue;
    final hasMv = totals.hasMarketValue;
    final dayPnl = totals.dayPnl;
    final hasDay = totals.hasDayPnl;
    final unrealized = totals.unrealizedPnl;
    final weights = computePortfolioWeights(holdings: _holdings, quotes: _quotes);
    final top3 = weights.take(3).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await _reload();
        await _loadDividends(force: true);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          sectionHeader(
            context,
            '首頁總覽',
            subtitle: '與「成本損益」目前群組同一套計算；盤中即時、收盤後用收盤價。下拉可重新整理。',
          ),
          const SizedBox(height: 8),
          if (_holdings.isEmpty)
            emptyState(
              context,
              icon: Icons.home_outlined,
              message: '尚無持倉',
              hint: '到「成本損益」登錄持倉後，這裡會顯示市值與除權息',
            )
          else ...[
            summaryCard(
              context,
              children: [
                _metric(
                  context,
                  '總市值',
                  hasMv ? _money.format(totalMv) : '—',
                ),
                const SizedBox(height: 8),
                _metric(
                  context,
                  '未實現損益',
                  unrealized == null
                      ? '—'
                      : '${_money.format(unrealized)}'
                          '${totals.unrealizedPnlPct != null ? '（${NumberFormat('+0.00%;-0.00%').format(totals.unrealizedPnlPct)}）' : ''}',
                  color: unrealized == null
                      ? null
                      : pnlColor(context, unrealized),
                ),
                const SizedBox(height: 8),
                _metric(
                  context,
                  '今日估損益（相對昨收）',
                  !hasDay
                      ? '—'
                      : _money.format(dayPnl!),
                  color: !hasDay ? null : pnlColor(context, dayPnl!),
                ),
                const SizedBox(height: 4),
                Text(
                  '報價來源與其他分頁相同（Yahoo／證交所）；非盤中時「相對昨收」可能接近 0 或為當日漲跌。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '前三權重大小',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (top3.isEmpty)
              Text('尚無法計算權重（缺報價）',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ...top3.asMap().entries.map((e) {
                final i = e.key;
                final row = e.value;
                final h = row.holding;
                final name = h.name.isNotEmpty
                    ? h.name
                    : widget.names.resolveName(h.ticker);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(
                      formatLabel(name, h.ticker),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '市值 ${_money.format(row.marketValue)}｜權重 ${_pct.format(row.weight)}',
                    ),
                  ),
                );
              }),
          ],
          const SizedBox(height: 16),
          const Divider(),
          sectionHeader(
            context,
            '持倉除權息',
            subtitle:
                '依「成本損益」持股對應公開預告：上市（TWSE TWT48U_ALL）＋上櫃（TPEx tpex_exright_prepost）。興櫃目前無對應公開預告 API，故不併入。僅顯示你持有且尚未過期之預告；金額＝官方表欄位×持股，不另推估。發放日若表上未列則標「公開表未列」。',
          ),
          const SizedBox(height: 8),
          if (_holdings.isEmpty)
            emptyState(
              context,
              icon: Icons.inventory_2_outlined,
              message: '無持倉可對應除權息',
              hint: '到「成本損益」登錄持股後，這裡會依公開表計算預估可領金額',
            )
          else if (_divFailed)
            emptyState(
              context,
              icon: Icons.cloud_off_outlined,
              message: '暫無資料',
              hint: '無法取得證交所／櫃買除權息預告，請稍後下拉重試',
            )
          else if (_exEvents.isEmpty)
            emptyState(
              context,
              icon: Icons.event_busy_outlined,
              message: '暫無資料',
              hint: '目前持倉沒有即將到來的上市／上櫃除權息預告',
            )
          else ...[
            Builder(builder: (context) {
              var totalCash = 0.0;
              var hasCash = false;
              for (final row in _exEvents) {
                final c = row.event.estimatedCash(row.shares);
                if (c != null) {
                  totalCash += c;
                  hasCash = true;
                }
              }
              return summaryCard(
                context,
                children: [
                  _metric(
                    context,
                    '預估合計可領現金',
                    hasCash ? 'NT\$ ${_cash.format(totalCash)}' : '—',
                    color: hasCash
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasCash
                        ? '合計＝各檔「持股股數 × 每股現金股利」四捨五入至整元後加總（僅表上有現金股利者）。'
                        : '目前對應預告未列現金股利，或僅有配股。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            }),
            const SizedBox(height: 8),
            ..._exEvents.map((row) {
              final e = row.event;
              final cash = e.estimatedCash(row.shares);
              final stockSh = e.estimatedStockShares(row.shares);
              final days = e.daysUntilCountdown;
              final countdownText = days < 0
                  ? '已過 ${-days} 天'
                  : days == 0
                      ? '今天'
                      : '$days 天';
              final suffix = e.market == 'tpex' ? '.TWO' : '.TW';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatLabel(
                          e.name.isNotEmpty
                              ? e.name
                              : widget.names.resolveName('${e.code}$suffix'),
                          '${e.code}$suffix',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text('市場：${e.marketLabel}｜種類：${e.kind}'),
                      Text('除權／除息日：${_day.format(e.exDate)}'),
                      Text(
                        e.paymentDate == null
                            ? '發放日：公開表未列'
                            : '發放日：${_day.format(e.paymentDate!)}',
                      ),
                      Text('持股股數：${_sharesFmt.format(row.shares)}'),
                      Text(
                        e.cashDividend == null
                            ? '每股現金股利：公開表未列'
                            : '每股現金股利：${_money.format(e.cashDividend!)} 元',
                      ),
                      Text(
                        e.stockDividendRatio == null
                            ? '每股無償配股率：公開表未列／無'
                            : '每股無償配股率：${_money.format(e.stockDividendRatio!)}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        cash == null
                            ? '預估可領現金：—'
                            : '預估可領現金：NT\$ ${_cash.format(cash)}'
                                '（${_sharesFmt.format(row.shares)} × '
                                '${_money.format(e.cashDividend!)}）',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cash == null
                              ? null
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Text(
                        stockSh == null
                            ? '預估可配股數：—'
                            : '預估可配股數：${_sharesFmt.format(stockSh)}'
                                '（${_sharesFmt.format(row.shares)} × '
                                '${_money.format(e.stockDividendRatio!)}）',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: stockSh == null
                              ? null
                              : Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${e.countdownLabel}：$countdownText',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _recordIncomeFromEvent(e, row.shares),
                          icon: const Icon(Icons.savings_outlined, size: 18),
                          label: const Text('記入總收益'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _recordIncomeFromEvent(ExDividendEvent e, double shares) async {
    final cash = e.estimatedCash(shares);
    final suffix = e.market == 'tpex' ? '.TWO' : '.TW';
    final ticker = '${e.code}$suffix';
    final rec = await showRecordIncomeDialog(
      context,
      storage: widget.storage,
      initialTicker: ticker,
      initialName: e.name.isNotEmpty
          ? e.name
          : widget.names.resolveName(ticker),
      initialAmount: cash,
      initialDate: e.exDate,
      initialKind: 'dividend',
    );
    if (rec == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已記入${rec.kindLabel} ${formatLabel(rec.name, rec.ticker)}',
        ),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        ),
      ],
    );
  }
}
