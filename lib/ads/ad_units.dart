import 'package:flutter/foundation.dart';

/// AdMob unit IDs. Test IDs only in debug; release uses production.
class AdUnits {
  static const String appId = 'ca-app-pub-6129276259083936~2938448043';

  static const String _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String _prodBanner = 'ca-app-pub-6129276259083936/9028731176';

  /// Google sample rewarded (debug only).
  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  /// Production rewarded unit (股市助手_獎勵短片_關廣告24h).
  static const String _prodRewarded = 'ca-app-pub-6129276259083936/3983892240';

  static String get banner => kDebugMode ? _testBanner : _prodBanner;

  static String get rewarded => kDebugMode ? _testRewarded : _prodRewarded;
}
