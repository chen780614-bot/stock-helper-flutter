import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_units.dart';

enum RewardedShowResult {
  earned,
  dismissedWithoutReward,
  noFill,
  failed,
  offline,
}

class RewardedAds {
  RewardedAds._();

  static bool _sdkReady = false;
  static Completer<void>? _initCompleter;

  static Future<void> ensureSdk() async {
    if (_sdkReady) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    final c = Completer<void>();
    _initCompleter = c;
    try {
      await MobileAds.instance.initialize();
      _sdkReady = true;
      c.complete();
    } catch (e, st) {
      debugPrint('MobileAds.initialize (rewarded) failed: $e\n$st');
      _initCompleter = null;
      c.completeError(e, st);
      rethrow;
    }
  }

  static Future<bool> hasNetwork() async {
    try {
      final result = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Load + show a rewarded ad. [onEarned] runs only after full watch reward.
  static Future<RewardedShowResult> show({
    required FutureOr<void> Function() onEarned,
  }) async {
    if (!await hasNetwork()) {
      return RewardedShowResult.offline;
    }

    try {
      await ensureSdk();
    } catch (_) {
      return RewardedShowResult.failed;
    }

    final completer = Completer<RewardedShowResult>();
    var earned = false;

    await RewardedAd.load(
      adUnitId: AdUnits.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) {
                completer.complete(
                  earned
                      ? RewardedShowResult.earned
                      : RewardedShowResult.dismissedWithoutReward,
                );
              }
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('Rewarded show failed: $error');
              ad.dispose();
              if (!completer.isCompleted) {
                completer.complete(RewardedShowResult.failed);
              }
            },
          );
          ad.show(
            onUserEarnedReward: (ad, reward) async {
              earned = true;
              try {
                await onEarned();
              } catch (e, st) {
                debugPrint('onEarned failed: $e\n$st');
              }
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded load failed: $error');
          if (!completer.isCompleted) {
            // No-fill / load errors → same user-facing message.
            completer.complete(RewardedShowResult.noFill);
          }
        },
      ),
    );

    return completer.future;
  }
}
