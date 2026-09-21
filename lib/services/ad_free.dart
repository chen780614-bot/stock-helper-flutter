import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists local ad-free window (DateTime.now() < adFreeUntil).
class AdFreeController extends ChangeNotifier {
  AdFreeController();

  static const _key = 'ad_free_until_v1';
  static const Duration rewardDuration = Duration(hours: 24);

  DateTime? _adFreeUntil;
  bool _loaded = false;
  bool _wasActive = false;

  bool get isLoaded => _loaded;
  DateTime? get adFreeUntil => _adFreeUntil;

  bool get isAdFree {
    final until = _adFreeUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  /// Remaining whole hours (at least 1 while still active).
  int get remainingHours {
    final until = _adFreeUntil;
    if (until == null) return 0;
    final left = until.difference(DateTime.now());
    if (left.isNegative || left.inSeconds <= 0) return 0;
    final h = left.inHours;
    return h < 1 ? 1 : h;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      _adFreeUntil = DateTime.tryParse(raw)?.toLocal();
    }
    _wasActive = isAdFree;
    _loaded = true;
    notifyListeners();
  }

  Future<void> grantFromNow() async {
    final until = DateTime.now().add(rewardDuration);
    _adFreeUntil = until;
    _wasActive = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, until.toIso8601String());
    notifyListeners();
  }

  /// Returns true once when window just expired.
  bool checkExpiredTransition() {
    final active = isAdFree;
    if (_wasActive && !active) {
      _wasActive = false;
      notifyListeners();
      return true;
    }
    if (active) _wasActive = true;
    return false;
  }

  void tick() {
    final expired = checkExpiredTransition();
    if (expired || isAdFree) {
      notifyListeners();
    }
  }
}
