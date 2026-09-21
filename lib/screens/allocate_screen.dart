import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/allocator.dart';
import '../services/names.dart';
import '../services/quotes.dart';
import '../services/storage.dart';
import '../services/ticker.dart';
import '../theme.dart';

class AllocateScreen extends StatefulWidget {
  const AllocateScreen({
    super.key,
    required this.storage,
    required this.names,
    required this.quotes,
  });

  final AppStorage storage;
  final NamesService names;
  final QuotesService quotes;

  @override
  State<AllocateScreen> createState() => _AllocateScreenState();
}

class _AllocateScreenState extends State<AllocateScreen> {
  final _capitalCtrl = TextEditingController(text: '100000');
  /// equal_n = 以股數（等股數 N）；equal_dollar = 以資金（等金額拆分）
  String _mode = 'equal_n';
  bool _lot1000 = false;
  bool _busy = false;
  AllocationResult? _result;
  String? _error;
  final _money = NumberFormat('#,##0.##');

  @override
  void dispose() {
    _capitalCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final capital = double.tryParse(_capitalCtrl.text.trim());
      if (capital == null || capital <= 0) {
        throw ArgumentError('請輸入有效資本');
      }
      final watch = await widget.storage.loadWatchlist();
      if (watch.isEmpty) {
        throw ArgumentError('請先在觀察清單加入股票');
      }
      final tickers = watch.map((e) => e.ticker).toList();
      final qmap = await widget.quotes.fetchQuotes(tickers);
      final prices = <double>[];
      final names = <String>[];
      final okTickers = <String>[];
      for (final t in tickers) {
        final q = qmap[t];
        if (q == null || !q.ok) continue;
        okTickers.add(t);
        prices.add(q.price);
        names.add(q.shortName.isNotEmpty
            ? q.shortName
            : widget.names.resolveName(t, fallback: t));
      }
      if (okTickers.isEmpty) {
        throw ArgumentError('沒有可用報價，無法配置');
      }
      final lot = _lot1000 ? 1000 : 1;
      final result = _mode == 'equal_dollar'
          ? allocateEqualDollar(
              capital: capital,
              prices: prices,
              tickers: okTickers,
              names: names,
              lotSize: lot,
            )
          : allocateEqualN(
              capital: capital,
              prices: prices,
              tickers: okTickers,
              names: names,
              lotSize: lot,
            );
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _modeHint {
    if (_mode == 'equal_dollar') {
      return '以資金分配：資本均分到每檔，各檔預算內盡量買，股數向下取整'
          '${_lot1000 ? '並對齊整股 1000' : ''}。';
    }
    return '以股數分配：求最大整數 N，使每檔買相同 N 股（或 N 張）且總成本 ≤ 資本。';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        sectionHeader(context, '資本配置', subtitle: _modeHint),
        const SizedBox(height: 12),
        Text('配置模式', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'equal_n',
              label: Text('以股數'),
              icon: Icon(Icons.tag),
            ),
            ButtonSegment(
              value: 'equal_dollar',
              label: Text('以資金'),
              icon: Icon(Icons.attach_money),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            setState(() {
              _mode = s.first;
              _result = null;
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _capitalCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '資本（金額）',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('台股整股（1000 股／張）'),
          value: _lot1000,
          onChanged: (v) => setState(() => _lot1000 = v),
        ),
        FilledButton(
          onPressed: _busy ? null : _run,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('計算'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (_result != null) ...[
          const Divider(),
          summaryCard(
            context,
            children: [
              Text(
                _resultSummary(_result!),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._result!.rows.map((r) => Card(
                child: ListTile(
                  title: Text(
                    formatLabel(r.name, r.ticker),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                      '價 ${_money.format(r.price)} × ${r.shares} = ${_money.format(r.cost)}'),
                ),
              )),
        ] else if (_error == null && !_busy) ...[
          const Divider(),
          emptyState(
            context,
            icon: Icons.pie_chart_outline,
            message: '尚未計算配置',
            hint: '選擇模式與資本後按「計算」；標的來自觀察清單',
          ),
        ],
      ],
    );
  }

  String _resultSummary(AllocationResult r) {
    final total = r.rows.fold<double>(0, (a, b) => a + b.cost);
    final usage =
        r.capital > 0 ? (total / r.capital * 100).toStringAsFixed(1) : '0';
    if (r.mode == 'equal_n') {
      return '等股數：每檔 ${r.nSharesEach} 股｜總成本 ${_money.format(total)}｜剩餘 ${_money.format(r.leftover)}｜使用率 $usage%';
    }
    return '等金額：總成本 ${_money.format(total)}｜剩餘 ${_money.format(r.leftover)}｜使用率 $usage%';
  }
}