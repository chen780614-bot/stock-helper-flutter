# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:\Users\user\Documents\stock-helper-flutter")
content = r'''import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/holdings_ocr.dart';
import '../services/names.dart';
import '../services/quotes.dart';
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
  });

  final AppStorage storage;
  final NamesService names;
  final QuotesService quotes;
  final bool active;

  @override
  State<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends State<HoldingsScreen> {
  List<Holding> _items = [];
  Map<String, Quote> _quotes = {};
  bool _loading = true;
  bool _refreshing = false;
  bool _ocrBusy = false;
  final _tickerCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _sharesCtrl = TextEditingController();
  final _money = NumberFormat('#,##0.##');
  final _pct = NumberFormat('+0.00%;-0.00%');
  final _ocr = HoldingsOcrService();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
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

  Future<void> _bootstrap() async {
    await widget.names.ensureLoaded();
    final raw = await widget.storage.loadHoldings();
    final items = consolidateHoldings(raw);
    if (items.length != raw.length) {
      await widget.storage.saveHoldings(items);
    }
    setState(() {
      _items = items;
      _loading = false;
    });
    await _refreshQuotes(force: true);
  }

  Future<void> _reloadHoldings() async {
    final raw = await widget.storage.loadHoldings();
    final items = consolidateHoldings(raw);
    if (items.length != raw.length) {
      await widget.storage.saveHoldings(items);
    }
    if (!mounted) return;
    setState(() {
      _items = items;
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
      final ticker = normalizeTicker(_tickerCtrl.text);
      final buy = double.tryParse(_priceCtrl.text.trim());
      final shares = double.tryParse(_sharesCtrl.text.trim());
      if (buy == null || buy <= 0) throw ArgumentError('請輸入有效買入價');
      if (shares == null || shares <= 0) throw ArgumentError('請輸入有效股數');
      await widget.names.ensureLoaded();
      final name = widget.names.resolveName(ticker);
      final existed = _items.any((e) => e.ticker == ticker);
      final purchase = Holding(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        ticker: ticker,
        name: name,
        buyPrice: buy,
        shares: shares,
      );
      final next = addOrMergeHolding(_items, purchase);
      setState(() => _items = next);
      await widget.storage.saveHoldings(_items);
      _tickerCtrl.clear();
      _priceCtrl.clear();
      _sharesCtrl.clear();
      final merged = next.firstWhere((e) => e.ticker == ticker);
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

  Future<void> _importFromImage() async {
    if (_ocrBusy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('圖片匯入持倉', style: Theme.of(ctx).textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '選擇券商持倉截圖。文字辨識在本機完成，不會上傳圖片。',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('從相簿選擇'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('拍照'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('取消'),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (source == null || !mounted) return;

    setState(() => _ocrBusy = true);
    try {
      final drafts = await _ocr.pickAndParse(source);
      if (!mounted) return;
      if (drafts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未辨識到可匯入的持倉列')),
        );
        return;
      }
      await widget.names.ensureLoaded();
      for (final d in drafts) {
        if (d.name.trim().isEmpty) {
          try {
            final t = normalizeTicker(d.code);
            d.name = widget.names.resolveName(t);
          } catch (_) {}
        }
      }
      final confirmed = await _showOcrConfirmDialog(drafts);
      if (confirmed == null || confirmed.isEmpty || !mounted) return;
      await _commitOcrDrafts(confirmed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('圖片匯入失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  Future<List<OcrHoldingDraft>?> _showOcrConfirmDialog(
    List<OcrHoldingDraft> drafts,
  ) async {
    final working = drafts
        .map(
          (d) => OcrHoldingDraft(
            code: d.code,
            name: d.name,
            shares: d.shares,
            avgCost: d.avgCost,
            selected: d.selected,
            rawHint: d.rawHint,
          ),
        )
        .toList();
    final codeCtrls = [
      for (final d in working) TextEditingController(text: d.code),
    ];
    final nameCtrls = [
      for (final d in working) TextEditingController(text: d.name),
    ];
    final sharesCtrls = [
      for (final d in working)
        TextEditingController(
          text: d.shares == null ? '' : _money.format(d.shares).replaceAll(',', ''),
        ),
    ];
    final costCtrls = [
      for (final d in working)
        TextEditingController(
          text: d.avgCost == null ? '' : _money.format(d.avgCost).replaceAll(',', ''),
        ),
    ];

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final selectedCount =
                working.where((e) => e.selected).length;
            return AlertDialog(
              title: const Text('確認 OCR 匯入'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '請勾選要匯入的列，並修正辨識錯誤的欄位。匯入後會依代號合併／加權平均成本。',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: working.length,
                        itemBuilder: (ctx, i) {
                          final d = working[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                              child: Column(
                                children: [
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    value: d.selected,
                                    title: Text('第 ${i + 1} 列'),
                                    subtitle: d.isComplete
                                        ? null
                                        : const Text(
                                            '欄位不完整，請補齊後再勾選',
                                            style: TextStyle(color: Colors.orange),
                                          ),
                                    onChanged: (v) => setLocal(() {
                                      d.selected = v ?? false;
                                    }),
                                  ),
                                  TextField(
                                    controller: codeCtrls[i],
                                    decoration: const InputDecoration(
                                      labelText: '代號',
                                      isDense: true,
                                    ),
                                    onChanged: (v) => d.code = v.trim(),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: nameCtrls[i],
                                    decoration: const InputDecoration(
                                      labelText: '名稱（可空白）',
                                      isDense: true,
                                    ),
                                    onChanged: (v) => d.name = v.trim(),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: sharesCtrls[i],
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                          decoration: const InputDecoration(
                                            labelText: '所持股數',
                                            isDense: true,
                                          ),
                                          onChanged: (v) {
                                            d.shares = double.tryParse(
                                              v.trim().replaceAll(',', ''),
                                            );
                                            setLocal(() {});
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: costCtrls[i],
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                          decoration: const InputDecoration(
                                            labelText: '購入均價',
                                            isDense: true,
                                          ),
                                          onChanged: (v) {
                                            d.avgCost = double.tryParse(
                                              v.trim().replaceAll(',', ''),
                                            );
                                            setLocal(() {});
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Text('已勾選 $selectedCount / ${working.length} 列'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: selectedCount == 0
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: const Text('確認匯入'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final c in [...codeCtrls, ...nameCtrls, ...sharesCtrls, ...costCtrls]) {
      c.dispose();
    }
    if (ok != true) return null;
    return working.where((e) => e.selected).toList();
  }

  Future<void> _commitOcrDrafts(List<OcrHoldingDraft> drafts) async {
    var added = 0;
    var merged = 0;
    var next = List<Holding>.from(_items);
    await widget.names.ensureLoaded();

    for (final d in drafts) {
      try {
        final ticker = normalizeTicker(d.code);
        final shares = d.shares;
        final buy = d.avgCost;
        if (shares == null || shares <= 0) {
          throw ArgumentError('股數無效（${d.code}）');
        }
        if (buy == null || buy <= 0) {
          throw ArgumentError('均價無效（${d.code}）');
        }
        final name = d.name.trim().isNotEmpty
            ? d.name.trim()
            : widget.names.resolveName(ticker);
        final existed = next.any((e) => e.ticker == ticker);
        final purchase = Holding(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          ticker: ticker,
          name: name,
          buyPrice: buy,
          shares: shares,
          note: 'OCR匯入',
        );
        next = addOrMergeHolding(next, purchase);
        if (existed) {
          merged++;
        } else {
          added++;
        }
        // Tiny delay so ids stay unique if loop is fast.
        await Future<void>.delayed(const Duration(microseconds: 2));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('略過一列：$e')),
          );
        }
      }
    }

    setState(() => _items = next);
    await widget.storage.saveHoldings(_items);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('圖片匯入完成：新增 $added、合併 $merged'),
        ),
      );
    }
    await _refreshQuotes(force: true);
  }

  Future<void> _remove(Holding h) async {
    setState(() => _items = _items.where((e) => e.id != h.id).toList());
    await widget.storage.saveHoldings(_items);
    await _refreshQuotes(force: true);
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
      final result = applySell(
        holdings: _items,
        holding: h,
        sellShares: shares,
        sellPrice: price,
      );
      setState(() => _items = result.holdings);
      await widget.storage.saveHoldings(_items);
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
    _tickerCtrl.dispose();
    _priceCtrl.dispose();
    _sharesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    double totalCost = 0;
    double totalMv = 0;
    var hasMv = false;
    for (final h in _items) {
      totalCost += h.cost;
      final q = _quotes[h.ticker];
      if (q != null && q.ok) {
        totalMv += q.price * h.shares;
        hasMv = true;
      }
    }
    final totalPnl = hasMv ? totalMv - totalCost : null;
    final totalPnlPct =
        (totalPnl != null && totalCost > 0) ? totalPnl / totalCost : null;

    return RefreshIndicator(
      onRefresh: _reloadHoldings,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          sectionHeader(
            context,
            '成本與損益',
            subtitle: '未開市顯示收盤價；開市後每 10 秒更新。點持倉可賣出；刪除總收益紀錄會還原股數。可用「圖片匯入」辨識券商截圖。',
          ),
          const SizedBox(height: 12),
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
          OutlinedButton.icon(
            onPressed: _ocrBusy ? null : _importFromImage,
            icon: _ocrBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image_search_outlined),
            label: Text(_ocrBusy ? '辨識中…' : '圖片匯入'),
          ),
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
              hint: '手動輸入，或按「圖片匯入」辨識券商持倉截圖',
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
                        Text(line2, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '點擊賣出',
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
                        tooltip: '刪除持倉',
                        icon: const Icon(Icons.delete_outline),
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
'''
(root / "lib" / "screens" / "holdings_screen.dart").write_text(content, encoding="utf-8")
print("holdings_screen written", len(content))
