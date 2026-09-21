import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/feature_flags.dart';
import '../services/ad_free.dart';
import '../services/billing.dart';
import '../services/entitlement.dart';
import '../services/rewarded_ads.dart';
import '../services/names.dart';
import '../services/securities/securities_models.dart';
import '../services/storage.dart';
import 'backup_screen.dart';

/// 設置：外觀、訂閱（關廣告）、獎勵廣告 24h、備份。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.storage,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.adFree,
    required this.entitlement,
    required this.billing,
    required this.names,
    this.onImported,
  });

  final AppStorage storage;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;
  final AdFreeController adFree;
  final EntitlementService entitlement;
  final BillingService billing;
  final NamesService names;
  final VoidCallback? onImported;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  bool _dbBusy = false;
  bool _online = true;
  Timer? _countdown;
  Timer? _netPoll;
  String _versionLabel = '';
  int _versionLongPressTicks = 0;
  String _dbStatus = '讀取中…';

  @override
  void initState() {
    super.initState();
    widget.adFree.addListener(_onChanged);
    widget.entitlement.addListener(_onChanged);
    widget.billing.addListener(_onChanged);
    _countdown = Timer.periodic(const Duration(seconds: 30), (_) {
      widget.adFree.tick();
      if (mounted) setState(() {});
    });
    _refreshNetwork();
    _netPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      _refreshNetwork();
    });
    _loadVersion();
    _loadDbStatus();
  }

  @override
  void dispose() {
    widget.adFree.removeListener(_onChanged);
    widget.entitlement.removeListener(_onChanged);
    widget.billing.removeListener(_onChanged);
    _countdown?.cancel();
    _netPoll?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLabel = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {}
  }

  Future<void> _refreshNetwork() async {
    final ok = await RewardedAds.hasNetwork();
    if (!mounted) return;
    if (ok != _online) setState(() => _online = ok);
  }

  Future<void> _openBackup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackupScreen(
          storage: widget.storage,
          onThemeModeChanged: widget.onThemeModeChanged,
          onImported: widget.onImported,
        ),
      ),
    );
  }

  Future<void> _watchRewarded() async {
    if (_busy) return;
    await _refreshNetwork();
    if (!_online) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要網路才能觀看廣告')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await RewardedAds.show(
        onEarned: () => widget.adFree.grantFromNow(),
      );
      if (!mounted) return;
      switch (result) {
        case RewardedShowResult.earned:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('廣告已關閉 24 小時')),
          );
        case RewardedShowResult.noFill:
        case RewardedShowResult.failed:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('目前沒有可播的廣告，請稍後再試')),
          );
        case RewardedShowResult.offline:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要網路才能觀看廣告')),
          );
        case RewardedShowResult.dismissedWithoutReward:
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(String productId) async {
    final billing = widget.billing;
    if (!billing.canPurchase) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(billing.message ?? 'Play 訂閱商品尚未開放，請稍後'),
        ),
      );
      return;
    }
    final product = billing.productById(productId);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Play 訂閱商品尚未開放，請稍後')),
      );
      return;
    }
    await billing.buy(product);
    if (!mounted) return;
    if (billing.message != null && !widget.entitlement.isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(billing.message!)),
      );
    }
  }

  String get _rewardButtonLabel {
    if (widget.adFree.isAdFree) {
      return '廣告已關閉　剩餘 ${widget.adFree.remainingHours} 小時';
    }
    return '觀看以關閉廣告';
  }

  Future<void> _onVersionLongPress() async {
    _versionLongPressTicks++;
    if (_versionLongPressTicks < 1) return;
    await widget.entitlement.setTesterMode(true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已開啟 QA 測試模式（長按版本）')),
    );
    final unlock = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QA 解鎖'),
        content: const Text('測試解鎖訂閱（僅關廣告，非 Play 購買）？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('關閉測試訂閱'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解鎖'),
          ),
        ],
      ),
    );
    if (unlock == true) {
      await widget.entitlement.debugUnlock();
    } else if (unlock == false) {
      await widget.entitlement.debugLock();
    }
  }


  Future<void> _loadDbStatus() async {
    try {
      await widget.names.ensureLoaded();
      final markets = await widget.names.readMarketSyncMeta();
      final active = await widget.names.activeCount();
      if (!mounted) return;
      setState(() {
        _dbStatus = _formatMarketStatus(markets, active);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _dbStatus = '無法讀取資料庫：$e');
    }
  }

  String _formatMarketStatus(List<MarketSyncMeta> markets, int activeTotal) {
    final lines = <String>[];
    var latest = '';
    for (final m in markets) {
      final last =
          m.lastSuccessAt.isEmpty ? '尚未成功' : _formatLocal(m.lastSuccessAt);
      final status = m.errorMessage.isEmpty
          ? (m.lastSuccessAt.isEmpty ? '—' : '成功')
          : '失敗';
      final err = m.errorMessage.isEmpty ? '' : '（${m.errorMessage}）';
      lines.add(
        '${m.market.labelZh}：${m.recordCount} 檔　$status　上次：$last$err',
      );
      if (m.lastSuccessAt.compareTo(latest) > 0) latest = m.lastSuccessAt;
    }
    final head = latest.isEmpty
        ? '合計約 $activeTotal 檔　尚未更新'
        : '合計約 $activeTotal 檔　最近成功：${_formatLocal(latest)}';
    return ([head, ...lines]).join('\n');
  }

  String _formatLocal(String iso) {
    try {
      final t = DateTime.parse(iso).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _updateSecuritiesDb() async {
    if (_dbBusy) return;
    setState(() => _dbBusy = true);
    try {
      final result = await widget.names.syncNow();
      if (!mounted) return;
      final markets = await widget.names.readMarketSyncMeta();
      final active = await widget.names.activeCount();
      setState(() {
        _dbStatus = _formatMarketStatus(markets, active);
      });
      final ok = result.markets.where((m) => m.success).length;
      final fail = result.markets.where((m) => !m.success && !m.skipped).length;
      final detail = result.markets
          .map((m) => '${m.market.labelZh}${m.statusZh}')
          .join('、');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fail == 0
                ? '股票資料庫已更新（$ok 市場成功，$active 檔）'
                : '部分更新：$detail',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新失敗：$e')),
      );
      await _loadDbStatus();
    } finally {
      if (mounted) setState(() => _dbBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subscribed = widget.entitlement.isPremium;
    final adFreeActive = widget.adFree.isAdFree;
    final canWatch = !_busy &&
        _online &&
        FeatureFlags.rewardedAdFreeEnabled &&
        !subscribed;
    final billing = widget.billing;
    final q = billing.productById(BillingProductIds.quarterly);
    final y = billing.productById(BillingProductIds.yearly);
    final qLabel = q?.price ?? billing.fallbackPriceLabel(BillingProductIds.quarterly);
    final yLabel = y?.price ?? billing.fallbackPriceLabel(BillingProductIds.yearly);

    return Scaffold(
      appBar: AppBar(title: const Text('設置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('外觀', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '白天／夜模式，或跟隨系統自動切換',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          RadioGroup<ThemeMode>(
            groupValue: widget.themeMode,
            onChanged: (mode) async {
              if (mode == null) return;
              await widget.onThemeModeChanged(mode);
              if (mounted) setState(() {});
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('白天（亮色）'),
                  secondary: Icon(Icons.light_mode_outlined),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('夜色（暗色）'),
                  secondary: Icon(Icons.dark_mode_outlined),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('跟隨系統'),
                  secondary: Icon(Icons.brightness_auto_outlined),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text('訂閱', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '訂閱後關閉橫幅廣告；功能會陸續新增，訂閱能支持開發',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '所有功能皆可免費使用，訂閱僅關閉廣告',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
          ),
          const SizedBox(height: 12),
          if (subscribed) ...[
            Card(
              color: cs.primaryContainer,
              child: ListTile(
                leading: Icon(Icons.verified, color: cs.onPrimaryContainer),
                title: Text(
                  '訂閱生效中（${widget.entitlement.source.labelZh}）',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  widget.entitlement.productId == null
                      ? '橫幅廣告已關閉'
                      : '方案：${widget.entitlement.productId}',
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
              ),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_view_month_outlined),
              title: const Text('季繳'),
              subtitle: Text(qLabel),
              trailing: FilledButton(
                onPressed: billing.purchaseInFlight
                    ? null
                    : () => _buy(BillingProductIds.quarterly),
                child: const Text('訂閱'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('年繳'),
              subtitle: Text(yLabel),
              trailing: FilledButton(
                onPressed: billing.purchaseInFlight
                    ? null
                    : () => _buy(BillingProductIds.yearly),
                child: const Text('訂閱'),
              ),
            ),
            if (!billing.canPurchase) ...[
              const SizedBox(height: 4),
              Text(
                billing.message ?? 'Play 訂閱商品尚未開放，請稍後',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.error,
                    ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await billing.refreshProducts();
                  await billing.restore();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        billing.canPurchase
                            ? '已重新整理商品／嘗試還原購買'
                            : (billing.message ??
                                'Play 訂閱商品尚未開放，請稍後'),
                      ),
                    ),
                  );
                },
                child: const Text('重新整理／還原購買'),
              ),
            ),
          ],
          if (FeatureFlags.rewardedAdFreeEnabled && !subscribed) ...[
            const Divider(height: 32),
            Text('廣告', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '觀看一支短片，關閉廣告 24 小時',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '到期後廣告會恢復，可再看一次',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '24 小時從看完當下起算（本機時間）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '不看也能完整使用',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: canWatch ? _watchRewarded : null,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      adFreeActive
                          ? Icons.visibility_off_outlined
                          : Icons.play_circle_outline,
                    ),
              label: Text(_rewardButtonLabel),
            ),
            if (!_online) ...[
              const SizedBox(height: 8),
              Text(
                '需要網路才能觀看廣告',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.error,
                    ),
              ),
            ],
          ],
          const Divider(height: 32),
          Text('股票資料庫', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '官方上市／上櫃／興櫃證券主檔（與報價分開）。各市場獨立驗證後才寫入；失敗不會清掉舊資料。同一天內自動略過，可手動強制更新。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            _dbStatus,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _dbBusy ? null : _updateSecuritiesDb,
            icon: _dbBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
            label: Text(_dbBusy ? '更新中…' : '更新股票資料庫'),
          ),
          const Divider(height: 32),
          Text('備份', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '匯出／匯入觀察名單、持倉、賣出紀錄與主題（JSON）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.backup_outlined, color: cs.primary),
            title: const Text('備份／還原'),
            subtitle: const Text('JSON 匯出與匯入業務資料'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openBackup,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onLongPress: _onVersionLongPress,
            child: Text(
              _versionLabel.isEmpty ? '股市助手' : '股市助手 $_versionLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
