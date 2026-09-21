import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup.dart';
import '../services/storage.dart';
import '../theme.dart';

/// JSON 備份匯出／匯入（業務資料：觀察名單、持倉、賣出紀錄、主題）。
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.storage,
    this.onThemeModeChanged,
    this.onImported,
  });

  final AppStorage storage;
  final Future<void> Function(ThemeMode mode)? onThemeModeChanged;
  final VoidCallback? onImported;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupService _backup = BackupService(widget.storage);
  bool _busy = false;
  BackupConflictStrategy _strategy = BackupConflictStrategy.replaceAll;

  String _strategyLabel(BackupConflictStrategy s) => switch (s) {
        BackupConflictStrategy.replaceAll => '完整還原（取代本機資料）',
        BackupConflictStrategy.skip => '跳過（保留本機）',
        BackupConflictStrategy.overwrite => '覆蓋（以備份為準）',
        BackupConflictStrategy.saveAsCopy => '另存（新 UUID）',
      };

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final info = await PackageInfo.fromPlatform();
      final env = await _backup.buildExportEnvelope(
        appPackage: info.packageName,
        appVersion: '${info.version}+${info.buildNumber}',
      );
      final json = _backup.encodeEnvelopePretty(env);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toLocal()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/股市助手備份_$stamp.json');
      await file.writeAsString(json, flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: '股市助手備份',
        text: '股市助手 JSON 備份（schema ${env.schemaVersion}）',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已匯出：觀察 ${env.payload.watchlist.length}、'
            '持倉 ${env.payload.holdings.length}、'
            '賣出 ${env.payload.sells.length}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      String raw;
      if (f.bytes != null && f.bytes!.isNotEmpty) {
        raw = utf8.decode(f.bytes!);
      } else if (f.path != null) {
        raw = await File(f.path!).readAsString();
      } else {
        throw BackupException('無法讀取所選檔案');
      }

      final envelope = parseAndValidateBackupJson(raw);
      final local = await _backup.loadLocal();
      final preview = previewImport(
        local: local,
        incoming: envelope.payload,
        strategy: _strategy,
      );
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('確認還原／匯入'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '備份時間：${envelope.exportedAt.isEmpty ? '（未知）' : envelope.exportedAt}',
                  ),
                  Text('App：${envelope.appPackage} ${envelope.appVersion}'),
                  Text('Schema：${envelope.schemaVersion}'),
                  const SizedBox(height: 8),
                  Text('衝突策略：${_strategyLabel(_strategy)}'),
                  const Divider(),
                  Text('觀察名單：新增 ${preview.watchAdded}／變更 ${preview.watchChanged}／跳過 ${preview.watchSkipped}'),
                  Text('持倉：新增 ${preview.holdingsAdded}／變更 ${preview.holdingsChanged}／跳過 ${preview.holdingsSkipped}'),
                  Text('賣出紀錄：新增 ${preview.sellsAdded}／變更 ${preview.sellsChanged}／跳過 ${preview.sellsSkipped}'),
          Text('股利／息：新增 ${preview.incomesAdded}／變更 ${preview.incomesChanged}／跳過 ${preview.incomesSkipped}'),
                  Text(
                    preview.themeWillChange
                        ? '主題：將變更為 ${envelope.payload.themeMode}'
                        : '主題：不變',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '合計：新增 ${preview.totalAdded}、變更 ${preview.totalChanged}、跳過 ${preview.totalSkipped}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '匯入僅含業務資料（不含名稱快取等）。確定後會寫入本機。',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
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
                child: const Text('確認匯入'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;

      final merged = await _backup.applyImportAtomic(
        incoming: envelope.payload,
        strategy: _strategy,
      );
      if (widget.onThemeModeChanged != null) {
        await widget.onThemeModeChanged!(merged.themeMode);
      }
      widget.onImported?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '匯入完成：觀察 ${merged.watchlist.length}、'
            '持倉 ${merged.holdings.length}、'
            '賣出 ${merged.sells.length}',
          ),
        ),
      );
    } on BackupException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯入失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('備份／還原')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'JSON 備份',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '匯出／匯入觀察名單、持倉分組、賣出／股利與主題。預設「完整還原」會以備份取代本機業務資料。不含名稱快取。檔案僅透過系統分享／選檔。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: appPrimaryButtonStyle(Theme.of(context).colorScheme),
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: const Text('匯出備份（JSON）'),
          ),
          const SizedBox(height: 12),
          Text('匯入衝突策略', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SegmentedButton<BackupConflictStrategy>(
            segments: const [
              ButtonSegment(
                value: BackupConflictStrategy.replaceAll,
                label: Text('完整還原'),
                icon: Icon(Icons.restore_outlined),
              ),
              ButtonSegment(
                value: BackupConflictStrategy.overwrite,
                label: Text('覆蓋'),
                icon: Icon(Icons.find_replace_outlined),
              ),
              ButtonSegment(
                value: BackupConflictStrategy.skip,
                label: Text('跳過'),
                icon: Icon(Icons.skip_next_outlined),
              ),
            ],
            selected: {_strategy},
            onSelectionChanged: _busy
                ? null
                : (s) => setState(() => _strategy = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            _strategyLabel(_strategy),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: appOutlineButtonStyle(Theme.of(context).colorScheme),
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.download_outlined),
            label: const Text('匯入／還原（選擇 JSON）'),
          ),

          const SizedBox(height: 24),
          const Divider(),
          Text(
            '雲端同步',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('雲端同步'),
            subtitle: const Text('即將開放（目前請用本機 JSON 備份）'),
            trailing: const Icon(Icons.hourglass_empty),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('雲端同步即將開放，請先使用本機 JSON 備份')),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            '說明',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '• 格式標記：stock_helper_backup\n'
            '• 含 schemaVersion、exportedAt、payload、checksum（SHA-256）\n'
            '• 持倉／賣出／觀察項使用字串 UUID；另存策略會產生新 UUID\n'
            '• 拒絕較新的 schemaVersion，並顯示清楚錯誤\n'
            '• 匯入前會顯示預覽摘要，確認後才寫入',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
