import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/storage.dart';
import '../services/ticker.dart';
import '../theme.dart';
import '../widgets/income_dialog.dart';

class RealizedScreen extends StatefulWidget {
  const RealizedScreen({super.key, required this.storage});

  final AppStorage storage;

  @override
  State<RealizedScreen> createState() => _RealizedScreenState();
}

class _RealizedScreenState extends State<RealizedScreen> {
  List<SellRecord> _sells = [];
  List<IncomeRecord> _incomes = [];
  bool _loading = true;
  final _money = NumberFormat('#,##0.##');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sells = await widget.storage.loadSells();
    final incomes = await widget.storage.loadIncomes();
    if (!mounted) return;
    setState(() {
      _sells = sells;
      _incomes = incomes;
      _loading = false;
    });
  }

  Future<void> _addIncome() async {
    final rec = await showRecordIncomeDialog(
      context,
      storage: widget.storage,
    );
    if (rec != null) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已記入${rec.kindLabel} ${formatLabel(rec.name, rec.ticker)} '
            'NT\$ ${_money.format(rec.amount)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final groupedSells = groupSellsByYearMonth(_sells);
    final groupedIncomes = groupIncomesByYearMonth(_incomes);
    final years = {...groupedSells.keys, ...groupedIncomes.keys}.toList()
      ..sort((a, b) => b.compareTo(a));
    final allPnl = sumPnl(_sells) + sumIncome(_incomes);
    final totalCount = _sells.length + _incomes.length;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
            sectionHeader(
              context,
              '總收益',
              subtitle:
                  '已實現賣出損益與手動記入的股利／息。刪除賣出會還原持股；刪除股利／息不會動到持股。',
            ),
            const SizedBox(height: 12),
            summaryCard(
              context,
              children: [
                Text(
                  totalCount == 0
                      ? '尚無已實現收益'
                      : '累計已實現：${_money.format(allPnl)}'
                          '（賣出 ${_sells.length}＋股利／息 ${_incomes.length}）',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: totalCount == 0 ? null : pnlColor(context, allPnl),
                  ),
                ),
                if (_incomes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '其中股利／息合計：${_money.format(sumIncome(_incomes))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            const Divider(),
            if (years.isEmpty)
              emptyState(
                context,
                icon: Icons.trending_up,
                message: '尚無已實現收益',
                hint: '在「成本損益」賣出，或從首頁除權息／此頁「記入股利／息」新增',
              )
            else
              ...years.map((year) {
                final monthsMap = groupedSells[year] ?? {};
                final incomeMonths = groupedIncomes[year] ?? {};
                final monthKeys = {...monthsMap.keys, ...incomeMonths.keys}
                    .toList()
                  ..sort((a, b) => b.compareTo(a));
                final yearSells = monthsMap.values.expand((e) => e);
                final yearIncomes = incomeMonths.values.expand((e) => e);
                final yearPnl = sumPnl(yearSells) + sumIncome(yearIncomes);
                final yearCount = yearSells.length + yearIncomes.length;
                return Card(
                  child: ExpansionTile(
                    initiallyExpanded: year == DateTime.now().year,
                    shape: const Border(),
                    title: Text(
                      '$year 年',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '全年 ${_money.format(yearPnl)}｜$yearCount 筆',
                      style: TextStyle(color: pnlColor(context, yearPnl)),
                    ),
                    children: [
                      for (final month in monthKeys)
                        ListTile(
                          title: Text('$month 月'),
                          subtitle: Text(
                            '當月 ${_money.format(sumPnl(monthsMap[month] ?? const []) + sumIncome(incomeMonths[month] ?? const []))}｜'
                            '${(monthsMap[month]?.length ?? 0) + (incomeMonths[month]?.length ?? 0)} 筆',
                            style: TextStyle(
                              color: pnlColor(
                                context,
                                sumPnl(monthsMap[month] ?? const []) +
                                    sumIncome(incomeMonths[month] ?? const []),
                              ),
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _MonthDetailPage(
                                  year: year,
                                  month: month,
                                  storage: widget.storage,
                                  onChanged: _load,
                                ),
                              ),
                            );
                            await _load();
                          },
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addIncome,
        icon: const Icon(Icons.add),
        label: const Text('記入股利／息'),
      ),
    );
  }
}

class _MonthDetailPage extends StatefulWidget {
  const _MonthDetailPage({
    required this.year,
    required this.month,
    required this.storage,
    required this.onChanged,
  });

  final int year;
  final int month;
  final AppStorage storage;
  final Future<void> Function() onChanged;

  @override
  State<_MonthDetailPage> createState() => _MonthDetailPageState();
}

class _MonthDetailPageState extends State<_MonthDetailPage> {
  List<SellRecord> _sells = [];
  List<IncomeRecord> _incomes = [];
  bool _loading = true;
  final _money = NumberFormat('#,##0.##');
  final _pct = NumberFormat('+0.00%;-0.00%');
  final _day = DateFormat('yyyy-MM-dd HH:mm');
  final _dayOnly = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sells = await widget.storage.loadSells();
    final incomes = await widget.storage.loadIncomes();
    if (!mounted) return;
    setState(() {
      _sells = sells
          .where((r) => r.year == widget.year && r.month == widget.month)
          .toList();
      _incomes = incomes
          .where((r) => r.year == widget.year && r.month == widget.month)
          .toList();
      _loading = false;
    });
  }

  Future<void> _deleteSell(SellRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除這筆賣出紀錄？'),
        content: Text(
          '刪除後不可修改。\n'
          '${formatLabel(r.name, r.ticker)} ${_money.format(r.shares)} 股會加回「成本損益」。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: appPrimaryButtonStyle(Theme.of(ctx).colorScheme, danger: true),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除並還原股數'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.storage.restoreSellIntoActiveGroup(r);
    await widget.storage.deleteSell(r.id);
    await widget.onChanged();
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已刪除，${formatLabel(r.name, r.ticker)} ${_money.format(r.shares)} 股已還原',
          ),
        ),
      );
      if (_sells.isEmpty && _incomes.isEmpty) Navigator.of(context).pop();
    }
  }

  Future<void> _deleteIncome(IncomeRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除這筆股利／息？'),
        content: Text(
          '僅從總收益移除，不會變更持股。\n'
          '${formatLabel(r.name, r.ticker)} ${r.kindLabel} ${_money.format(r.amount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: appPrimaryButtonStyle(Theme.of(ctx).colorScheme, danger: true),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.storage.deleteIncome(r.id);
    await widget.onChanged();
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已刪除股利／息紀錄')),
      );
      if (_sells.isEmpty && _incomes.isEmpty) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.year} 年 ${widget.month} 月')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final monthPnl = sumPnl(_sells) + sumIncome(_incomes);

    return Scaffold(
      appBar: AppBar(title: Text('${widget.year} 年 ${widget.month} 月')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          summaryCard(
            context,
            children: [
              Text(
                '當月已實現：${_money.format(monthPnl)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: pnlColor(context, monthPnl),
                ),
              ),
              Text(
                '賣出 ${_sells.length} 筆｜股利／息 ${_incomes.length} 筆（僅可刪除）',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_sells.isEmpty && _incomes.isEmpty)
            emptyState(
              context,
              icon: Icons.inbox_outlined,
              message: '本月已無紀錄',
            )
          else ...[
            if (_incomes.isNotEmpty) ...[
              Text(
                '股利／息',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ..._incomes.map((r) {
                return Card(
                  child: ListTile(
                    title: Text(
                      '${r.kindLabel}｜${formatLabel(r.name, r.ticker)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_dayOnly.format(r.receivedAt)),
                          Text(
                            '金額 ${_money.format(r.amount)}',
                            style: TextStyle(
                              color: pnlColor(context, r.amount),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (r.note.isNotEmpty) Text('備註：${r.note}'),
                        ],
                      ),
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: '刪除（不還原持股）',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteIncome(r),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
            if (_sells.isNotEmpty) ...[
              Text(
                '賣出',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ..._sells.map((r) {
                return Card(
                  child: ListTile(
                    title: Text(
                      formatLabel(r.name, r.ticker),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_day.format(r.soldAt)),
                          Text(
                            '均價 ${_money.format(r.avgCost)} → 賣價 ${_money.format(r.sellPrice)}'
                            ' × ${_money.format(r.shares)}',
                          ),
                          Text(
                            '損益 ${_money.format(r.pnl)}'
                            '${r.pnlPct == null ? '' : '（${_pct.format(r.pnlPct)}）'}',
                            style: TextStyle(
                              color: pnlColor(context, r.pnl),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: '刪除並還原股數',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteSell(r),
                    ),
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}
