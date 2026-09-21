import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/ids.dart';
import '../services/names.dart';
import '../services/quotes.dart';
import '../services/portfolio_math.dart';
import '../services/storage.dart';
import '../services/ticker.dart';
import '../theme.dart';

class HoldingsScreen extends StatefulWidget {
  const HoldingsScreen({
    super.key,
    required this.storage,
    required this.names,
    required this.quotes,
    this.active = true,
    this.onThemeModeChanged,
    this.onDataImported,
  });

  final AppStorage storage;
  final NamesService names;
  final QuotesService quotes;
  final bool active;
  final Future<void> Function(ThemeMode mode)? onThemeModeChanged;
  final VoidCallback? onDataImported;

  @override
  State<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends State<HoldingsScreen> {
  static const int _groupsSoftCap = 50;

  List<HoldingGroup> _groups = [];
  String? _activeGroupId;
  Map<String, Quote> _quotes = {};
  bool _loading = true;
  bool _refreshing = false;
  final _tickerCtrl = TextEditingController();
  String _inputMirror = '';
  String _resolvedPreview = '';
  bool _previewLookupPending = false;
  int _previewSeq = 0;
  final _priceCtrl = TextEditingController();
  final _sharesCtrl = TextEditingController();
  final _money = NumberFormat('#,##0.##');
  final _pct = NumberFormat('+0.00%;-0.00%');
  Timer? _timer;

  HoldingGroup? get _activeGroup {
    if (_groups.isEmpty) return null;
    final id = _activeGroupId;
    if (id != null) {
      for (final g in _groups) {
        if (g.id == id) return g;
      }
    }
    return _groups.first;
  }

  List<Holding> get _items => _activeGroup?.items ?? const [];

  @override
  void initState() {
    super.initState();
    _tickerCtrl.addListener(_onTickerInputChanged);
    _bootstrap();
    if (widget.active) _armTimer();
  }

  @override
  void didUpdateWidget(covariant HoldingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _reloadHoldings();
      _armTimer();
    } else if (!widget.active && oldWidget.active) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !widget.active || _refreshing) return;
      _refreshQuotes(force: true);
    });
  }

  void _onTickerInputChanged() {
    final v = _tickerCtrl.text.trim();
    if (v == _inputMirror) return;
    setState(() {
      _inputMirror = v;
      _resolvedPreview = _computePreviewSync(v);
    });
    _schedulePreviewLookup(v);
  }

  String _computePreviewSync(String raw) {
    if (raw.isEmpty) return '';
    try {
      return widget.names.previewLabelForInput(raw);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _schedulePreviewLookup(String raw) async {
    final seq = ++_previewSeq;
    if (raw.isEmpty) {
      if (mounted && seq == _previewSeq) {
        setState(() {
          _previewLookupPending = false;
          _resolvedPreview = '';
        });
      }
      return;
    }
    final code = extractTwCode(raw);
    final needsFetch = code != null && widget.names.lookup(code) == null;
    if (!needsFetch) {
      if (mounted && seq == _previewSeq) {
        setState(() {
          _previewLookupPending = false;
          _resolvedPreview = _computePreviewSync(raw);
        });
      }
      return;
    }
    if (mounted && seq == _previewSeq) {
      setState(() => _previewLookupPending = true);
    }
    try {
      await widget.names.ensureLoaded();
      if (widget.names.lookup(code!) == null) {
        await widget.names.refreshFromMarkets();
      }
    } catch (_) {}
    if (!mounted || seq != _previewSeq) return;
    setState(() {
      _previewLookupPending = false;
      _resolvedPreview = _computePreviewSync(raw);
    });
  }

  Future<void> _bootstrap() async {
    await widget.names.ensureLoaded();
    await widget.names.refreshFromMarkets();
    final groups = await widget.storage.loadHoldingGroups();
    final activeId = await widget.storage.loadActiveHoldingGroupId();
    setState(() {
      _groups = groups;
      _activeGroupId = activeId ?? (groups.isEmpty ? null : groups.first.id);
      _loading = false;
    });
    await _refreshQuotes(force: true);
  }

  Future<void> _persistGroups() async {
    await widget.storage.saveHoldingGroups(_groups);
    final id = _activeGroupId;
    if (id != null) await widget.storage.saveActiveHoldingGroupId(id);
  }

  Future<void> _reloadHoldings() async {
    final groups = await widget.storage.loadHoldingGroups();
    final activeId = await widget.storage.loadActiveHoldingGroupId();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _activeGroupId = activeId ?? (groups.isEmpty ? null : groups.first.id);
      _loading = false;
    });
    await _refreshQuotes(force: true);
  }

  Future<void> _refreshQuotes({bool force = false}) async {
    if (_items.isEmpty) {
      setState(() => _quotes = {});
      return;
    }
    setState(() => _refreshing = true);
    final tickers = _items.map((e) => e.ticker).toSet().toList();
    final q = await widget.quotes.fetchQuotes(tickers, force: force);
    if (!mounted) return;
    setState(() {
      _quotes = q;
      _refreshing = false;
    });
  }

  Future<void> _add() async {
    try {
      await widget.names.ensureLoaded();
      final g = _activeGroup;
      if (g == null) return;
      final raw = _tickerCtrl.text.trim();
      final probe = extractTwCode(raw) ?? raw.toUpperCase();
      if (looksLikeTwCode(probe) &&
          widget.names.lookup(probe) == null) {
        await widget.names.refreshFromMarkets();
      }
      final ticker = widget.names.normalizeTickerForMarket(raw);
      final buy = double.tryParse(_priceCtrl.text.trim());
      final shares = double.tryParse(_sharesCtrl.text.trim());
      if (buy == null || buy <= 0) throw ArgumentError('請輸入有效買入價');
      if (shares == null || shares <= 0) throw ArgumentError('請輸入有效股數');
      final name = widget.names.resolveName(ticker);
      final existed = g.items.any((e) => e.ticker == ticker);
      final purchase = Holding(
        id: newEntityId(),
        ticker: ticker,
        name: name,
        buyPrice: buy,
        shares: shares,
      );
      final nextItems = addOrMergeHolding(g.items, purchase);
      setState(() {
        _groups = _groups
            .map((x) => x.id == g.id ? x.copyWith(items: nextItems) : x)
            .toList();
      });
      await _persistGroups();
      _tickerCtrl.clear();
      _priceCtrl.clear();
      _sharesCtrl.clear();
      final merged = nextItems.firstWhere((e) => e.ticker == ticker);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existed
                  ? '已合併 ${formatLabel(merged.name, ticker)}｜均價 ${_money.format(merged.buyPrice)} × ${_money.format(merged.shares)}'
                  : '已登錄 ${formatLabel(name, ticker)}',
            ),
          ),
        );
      }
      await _refreshQuotes(force: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _remove(Holding h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除持倉'),
        content: Text(
          '僅移除「${formatLabel(h.name, h.ticker)}」紀錄，不計入賣出損益。\n'
          '若要計算已實現損益，請改用「賣出」。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('僅移除紀錄'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final g = _activeGroup;
    if (g == null) return;
    final nextItems = g.items.where((e) => e.id != h.id).toList();
    setState(() {
      _groups = _groups
          .map((x) => x.id == g.id ? x.copyWith(items: nextItems) : x)
          .toList();
    });
    await _persistGroups();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已移除持倉（未計入賣出損益）')),
      );
    }
    await _refreshQuotes(force: true);
  }

  Future<void> _addGroup() async {
    if (_groups.length >= _groupsSoftCap) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('群組數量已達建議上限（$_groupsSoftCap）')),
      );
      return;
    }
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增持倉群組'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '群組名稱'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: '備註（選填）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('建立'),
          ),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    final note = noteCtrl.text.trim();
    nameCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true || name.isEmpty) return;
    final g = HoldingGroup(
      id: newEntityId(),
      name: name,
      note: note,
      items: [],
    );
    setState(() {
      _groups = [..._groups, g];
      _activeGroupId = g.id;
    });
    await _persistGroups();
  }

  Future<void> _deleteGroup() async {
    final g = _activeGroup;
    if (g == null) return;
    if (_groups.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需保留一個持倉群組')),
      );
      return;
    }
    final count = g.items.length;
    final msg = count == 0
        ? '確定刪除群組「${g.name}」？'
        : '群組「${g.name}」尚有 $count 筆持倉。\n刪除後會一併移出此群組（不計入賣出損益）。確定刪除？';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除持倉群組'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除群組'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final next = _groups.where((x) => x.id != g.id).toList();
    final newActive = next.first.id;
    setState(() {
      _groups = next;
      _activeGroupId = newActive;
    });
    await _persistGroups();
    await widget.storage.saveActiveHoldingGroupId(newActive);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已刪除群組「${g.name}」')),
      );
    }
    await _refreshQuotes(force: true);
  }

  Future<void> _editGroupNote() async {
    final g = _activeGroup;
    if (g == null) return;
    final ctrl = TextEditingController(text: g.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('群組備註｜${g.name}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '備註'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    final note = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    setState(() {
      _groups = _groups
          .map((x) => x.id == g.id ? x.copyWith(note: note) : x)
          .toList();
    });
    await _persistGroups();
  }

  Future<void> _openSell(Holding h) async {
    final q = _quotes[h.ticker];
    final sellSharesCtrl = TextEditingController();
    final sellPriceCtrl = TextEditingController(
      text: (q != null && q.ok) ? q.price.toString() : '',
    );
    double previewShares = 0;
    double previewPrice = 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final canPreview = previewShares > 0 && previewPrice >= 0;
            final pnl = canPreview
                ? (previewPrice - h.buyPrice) * previewShares
                : null;
            final remain = h.shares - previewShares;
            return AlertDialog(
              title: Text('賣出 ${formatLabel(h.name, h.ticker)}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '目前持有 ${_money.format(h.shares)} 股｜平均成本 ${_money.format(h.buyPrice)}',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sellSharesCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '賣出股數',
                      ),
                      onChanged: (v) => setLocal(() {
                        previewShares = double.tryParse(v.trim()) ?? 0;
                      }),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: sellPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '賣出價格',
                      ),
                      onChanged: (v) => setLocal(() {
                        previewPrice = double.tryParse(v.trim()) ?? 0;
                      }),
                    ),
                    if (canPreview && previewShares <= h.shares) ...[
                      const SizedBox(height: 12),
                      Text(
                        '賣後剩餘：${_money.format(remain < 0 ? 0 : remain)} 股',
                      ),
                      Text(
                        '預估損益：${_money.format(pnl!)}'
                        '${h.buyPrice == 0 || previewShares == 0 ? '' : '（${_pct.format(pnl / (h.buyPrice * previewShares))}）'}',
                        style: TextStyle(
                          color: pnlColor(ctx, pnl),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('確認賣出'),
                ),
              ],
            );
          },
        );
      },
    );

    final shares = double.tryParse(sellSharesCtrl.text.trim());
    final price = double.tryParse(sellPriceCtrl.text.trim());
    sellSharesCtrl.dispose();
    sellPriceCtrl.dispose();
    if (ok != true) return;

    try {
      if (shares == null || price == null) {
        throw ArgumentError('請輸入有效股數與價格');
      }
      final g = _activeGroup;
      if (g == null) return;
      final result = applySell(
        holdings: g.items,
        holding: h,
        sellShares: shares,
        sellPrice: price,
      );
      setState(() {
        _groups = _groups
            .map((x) =>
                x.id == g.id ? x.copyWith(items: result.holdings) : x)
            .toList();
      });
      await _persistGroups();
      await widget.storage.addSell(result.record);
      if (mounted) {
        final r = result.record;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已賣出 ${formatLabel(r.name, r.ticker)} ${_money.format(r.shares)} 股｜'
              '損益 ${_money.format(r.pnl)}（見「總收益」）',
            ),
          ),
        );
      }
      await _refreshQuotes(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tickerCtrl.removeListener(_onTickerInputChanged);
    _tickerCtrl.dispose();
    _priceCtrl.dispose();
    _sharesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final cs = Theme.of(context).colorScheme;
    final g = _activeGroup;

    // Same shared math as 首頁 (active group holdings + quotes).
    final totals = computePortfolioTotals(holdings: _items, quotes: _quotes);
    final totalCost = totals.totalCost;
    final totalMv = totals.totalMarketValue;
    final hasMv = totals.hasMarketValue;
    final totalPnl = totals.unrealizedPnl;
    final totalPnlPct = totals.unrealizedPnlPct;

    return RefreshIndicator(
      onRefresh: _reloadHoldings,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          sectionHeader(
            context,
            '成本與損益',
            subtitle: '未開市顯示收盤價；開市後每 10 秒更新。點持倉可賣出；「移除」僅刪紀錄不計損益。'
                '可至「設置 → 備份／還原」匯出或匯入 JSON。',
          ),

          if (_inputMirror.isNotEmpty) ...[
            const SizedBox(height: 8),
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  _previewLookupPending &&
                          (_resolvedPreview.isEmpty || !_resolvedPreview.contains('　'))
                      ? '目前輸入：$_inputMirror　查詢名稱中…'
                      : '目前輸入：${_resolvedPreview.isNotEmpty ? _resolvedPreview : _inputMirror}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '群組',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: g?.id,
                      items: [
                        for (final x in _groups)
                          DropdownMenuItem(
                            value: x.id,
                            child: Text(
                              '${x.name}（${x.items.length}）',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) async {
                        if (id == null) return;
                        setState(() => _activeGroupId = id);
                        await widget.storage.saveActiveHoldingGroupId(id);
                        await _refreshQuotes(force: true);
                      },
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '新增群組',
                onPressed: _addGroup,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                tooltip: '群組備註',
                onPressed: _editGroupNote,
                icon: const Icon(Icons.sticky_note_2_outlined),
              ),
              IconButton(
                tooltip: '刪除群組',
                onPressed: _deleteGroup,
                icon: const Icon(Icons.folder_delete_outlined),
              ),
            ],
          ),
          if (g != null && g.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                g.note,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _tickerCtrl,
            decoration: const InputDecoration(labelText: '代號'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '買入價'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _sharesCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '股數'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _add, child: const Text('新增／合併持倉')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _refreshing ? null : _reloadHoldings,
              icon: const Icon(Icons.refresh),
              label: const Text('重新整理（含持倉）'),
            ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 4),
            summaryCard(
              context,
              children: [
                Text('總成本：${_money.format(totalCost)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(hasMv ? '總市值：${_money.format(totalMv)}' : '總市值：—'),
                Text(
                  totalPnl == null
                      ? '未實現損益：—'
                      : '未實現損益：${_money.format(totalPnl)}'
                          '${totalPnlPct == null ? '' : '（${_pct.format(totalPnlPct)}）'}',
                  style: totalPnl == null
                      ? null
                      : TextStyle(
                          fontWeight: FontWeight.w700,
                          color: pnlColor(context, totalPnl),
                        ),
                ),
              ],
            ),
          ],
          const Divider(),
          if (_items.isEmpty)
            emptyState(
              context,
              icon: Icons.account_balance_wallet_outlined,
              message: '尚未登錄持倉',
              hint: '手動輸入代號／價格／股數，或按「備份／還原」匯入 JSON',
            )
          else
            ..._items.map((h) {
              final q = _quotes[h.ticker];
              final name = h.name.isNotEmpty
                  ? h.name
                  : widget.names.resolveName(h.ticker);
              String line2;
              Color? color;
              if (q == null) {
                line2 = '現價載入中…';
              } else if (!q.ok) {
                line2 = '無法取得報價｜成本 ${_money.format(h.cost)}';
              } else {
                final mv = q.price * h.shares;
                final pnl = mv - h.cost;
                final pct = h.cost == 0 ? null : pnl / h.cost;
                color = pnlColor(context, pnl);
                final tag = q.priorClose ? '收盤' : '即時';
                line2 =
                    '$tag ${_money.format(q.price)}｜市值 ${_money.format(mv)}｜未實現 ${_money.format(pnl)}'
                    '${pct == null ? '' : '（${_pct.format(pct)}）'}';
              }
              return Card(
                child: ListTile(
                  onTap: () => _openSell(h),
                  title: Text(
                    formatLabel(name, h.ticker),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '平均成本 ${_money.format(h.buyPrice)} × ${_money.format(h.shares)} 股｜成本 ${_money.format(h.cost)}',
                        ),
                        const SizedBox(height: 2),
                        Text(line2,
                            style: TextStyle(
                                color: color, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '點擊賣出；或右側「移除」僅刪紀錄',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '賣出',
                        icon: const Icon(Icons.sell_outlined),
                        onPressed: () => _openSell(h),
                      ),
                      IconButton(
                        tooltip: '移除（不計損益）',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _remove(h),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
