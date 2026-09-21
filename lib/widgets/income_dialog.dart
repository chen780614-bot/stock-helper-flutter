import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/ids.dart';
import '../services/storage.dart';
import '../services/ticker.dart';

/// Dialog to manually record 股利／息 into 總收益. Prefills optional estimate.
Future<IncomeRecord?> showRecordIncomeDialog(
  BuildContext context, {
  required AppStorage storage,
  String? initialTicker,
  String? initialName,
  double? initialAmount,
  DateTime? initialDate,
  String initialKind = 'dividend',
}) async {
  final tickerCtrl = TextEditingController(text: initialTicker ?? '');
  final nameCtrl = TextEditingController(text: initialName ?? '');
  final amountCtrl = TextEditingController(
    text: initialAmount == null || initialAmount <= 0
        ? ''
        : NumberFormat('0.##').format(initialAmount),
  );
  final noteCtrl = TextEditingController();
  var kind = initialKind == 'interest' ? 'interest' : 'dividend';
  var date = initialDate ?? DateTime.now();
  final dayFmt = DateFormat('yyyy/MM/dd');

  final result = await showDialog<IncomeRecord>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('記入股利／息到總收益'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '不會自動入帳；確認後才寫入「總收益」。刪除時不會還原持股。',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'dividend', label: Text('股利')),
                      ButtonSegment(value: 'interest', label: Text('息')),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => setLocal(() => kind = s.first),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tickerCtrl,
                    decoration: const InputDecoration(
                      labelText: '代號',
                      hintText: '2330 或 2330.TW',
                    ),
                  ),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '名稱（可空）'),
                  ),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '金額（TWD）',
                      hintText: '預估可領現金可先帶入，請再確認',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('入帳日期：${dayFmt.format(date)}'),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 366)),
                      );
                      if (picked != null) setLocal(() => date = picked);
                    },
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: '備註（可空）',
                      hintText: '例如：除息預估／實際入帳',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final rawTicker = tickerCtrl.text.trim();
                  if (rawTicker.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('請填代號')),
                    );
                    return;
                  }
                  String ticker;
                  try {
                    ticker = normalizeTicker(rawTicker);
                  } catch (e) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                    return;
                  }
                  final amount = double.tryParse(
                    amountCtrl.text.trim().replaceAll(',', ''),
                  );
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('請填正確金額（大於 0）')),
                    );
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    IncomeRecord(
                      id: newEntityId(),
                      ticker: ticker,
                      name: nameCtrl.text.trim(),
                      amount: amount,
                      receivedAt: DateTime(date.year, date.month, date.day),
                      note: noteCtrl.text.trim(),
                      kind: kind,
                    ),
                  );
                },
                child: const Text('確認記入'),
              ),
            ],
          );
        },
      );
    },
  );

  tickerCtrl.dispose();
  nameCtrl.dispose();
  amountCtrl.dispose();
  noteCtrl.dispose();

  if (result == null) return null;
  await storage.addIncome(result);
  return result;
}
