import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where premium status comes from.
enum EntitlementSource {
  none,
  debug,
  play,
}

extension EntitlementSourceX on EntitlementSource {
  String get storageValue => name;

  static EntitlementSource fromStorage(String? raw) {
    switch (raw) {
      case 'debug':
        return EntitlementSource.debug;
      case 'play':
        return EntitlementSource.play;
      default:
        return EntitlementSource.none;
    }
  }

  String get labelZh => switch (this) {
        EntitlementSource.none => '免費',
        EntitlementSource.debug => '測試解鎖',
        EntitlementSource.play => 'Google Play',
      };
}

/// Local entitlement state. Play Billing not wired yet — use debug/tester unlock for QA.
class EntitlementService extends ChangeNotifier {
  static const _premiumKey = 'entitlement_is_premium_v1';
  static const _sourceKey = 'entitlement_source_v1';
  static const _untilKey = 'entitlement_premium_until_v1';
  static const _testerKey = 'entitlement_tester_mode_v1';

  bool _ready = false;
  bool _isPremium = false;
  EntitlementSource _source = EntitlementSource.none;
  DateTime? _premiumUntil;
  bool _testerMode = false;
  static const _productKey = 'entitlement_product_id_v1';
  static const _purchaseKey = 'entitlement_purchase_id_v1';
  String? _productId;
  String? _purchaseId;
  String? get productId => _productId;
  String? get purchaseId => _purchaseId;

  bool get ready => _ready;
  bool get isPremium => _isPremium && !_expired;
  EntitlementSource get source =>
      isPremium ? _source : EntitlementSource.none;
  DateTime? get premiumUntil => _premiumUntil;
  bool get testerMode => _testerMode;

  bool get canShowDebugUnlock => kDebugMode || _testerMode;

  bool get _expired {
    if (_premiumUntil == null) return false;
    return DateTime.now().isAfter(_premiumUntil!);
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _isPremium = p.getBool(_premiumKey) ?? false;
    _source = EntitlementSourceX.fromStorage(p.getString(_sourceKey));
    final untilMs = p.getInt(_untilKey);
    _premiumUntil =
        untilMs == null ? null : DateTime.fromMillisecondsSinceEpoch(untilMs);
    _testerMode = p.getBool(_testerKey) ?? false;
    _productId = p.getString(_productKey);
    _purchaseId = p.getString(_purchaseKey);

    if (_isPremium && _expired) {
      _isPremium = false;
      _source = EntitlementSource.none;
      _premiumUntil = null;
      await _persistCore(p);
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _persistCore(SharedPreferences p) async {
    await p.setBool(_premiumKey, _isPremium);
    await p.setString(_sourceKey, _source.storageValue);
    if (_premiumUntil == null) {
      await p.remove(_untilKey);
    } else {
      await p.setInt(_untilKey, _premiumUntil!.millisecondsSinceEpoch);
    }
  }

  /// Enable hidden tester controls (e.g. after long-pressing version).
  Future<void> setTesterMode(bool enabled) async {
    _testerMode = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_testerKey, enabled);
    notifyListeners();
  }


  /// Verified / store-reported purchase → persist local ad-free entitlement.
  /// Never call this for missing/unavailable products.
  Future<void> grantFromPlay({
    required String productId,
    String? purchaseId,
    DateTime? until,
  }) async {
    _isPremium = true;
    _source = EntitlementSource.play;
    _premiumUntil = until; // null = treat as active until Play says otherwise
    _productId = productId;
    _purchaseId = purchaseId;
    final p = await SharedPreferences.getInstance();
    await _persistCore(p);
    await p.setString(_productKey, productId);
    if (purchaseId == null || purchaseId.isEmpty) {
      await p.remove(_purchaseKey);
    } else {
      await p.setString(_purchaseKey, purchaseId);
    }
    notifyListeners();
  }

  Future<void> clearPlayEntitlement() async {
    if (_source != EntitlementSource.play && !canShowDebugUnlock) return;
    _isPremium = false;
    _source = EntitlementSource.none;
    _premiumUntil = null;
    _productId = null;
    _purchaseId = null;
    final p = await SharedPreferences.getInstance();
    await _persistCore(p);
    await p.remove(_productKey);
    await p.remove(_purchaseKey);
    notifyListeners();
  }

  /// Internal QA unlock — not Play Billing.
  Future<void> debugUnlock({Duration? duration}) async {
    if (!canShowDebugUnlock) return;
    _isPremium = true;
    _source = EntitlementSource.debug;
    _premiumUntil =
        duration == null ? null : DateTime.now().add(duration);
    final p = await SharedPreferences.getInstance();
    await _persistCore(p);
    notifyListeners();
  }

  Future<void> debugLock() async {
    if (!canShowDebugUnlock && _source != EntitlementSource.debug) return;
    _isPremium = false;
    _source = EntitlementSource.none;
    _premiumUntil = null;
    final p = await SharedPreferences.getInstance();
    await _persistCore(p);
    notifyListeners();
  }
}
