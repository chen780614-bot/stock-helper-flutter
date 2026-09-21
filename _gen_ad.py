# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:\Users\user\Documents\stock-helper-flutter")

# --- Clean ad banner: remove ADS-TEST visible strings, keep delayed init + prod unit ---
ad = r'''import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Bottom ad slot above the NavigationBar.
///
/// Delayed MobileAds init (~2s after first frame) then production Banner.
/// Init/load failures are caught so the app must not force-close.
class AdBannerPlaceholder extends StatefulWidget {
  const AdBannerPlaceholder({super.key});

  static const double bannerHeight = 54;

  static const String testBannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  static const String prodBannerUnitId =
      'ca-app-pub-6129276259083936/9028731176';

  @override
  State<AdBannerPlaceholder> createState() => _AdBannerPlaceholderState();
}

class _AdBannerPlaceholderState extends State<AdBannerPlaceholder> {
  BannerAd? _banner;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 2), _initAdsDelayed);
    });
  }

  Future<void> _initAdsDelayed() async {
    if (!mounted) return;
    try {
      await MobileAds.instance.initialize();
      if (!mounted) return;
      await _loadBanner();
    } catch (e, st) {
      debugPrint('MobileAds.initialize failed (app continues): $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadBanner() async {
    try {
      final banner = BannerAd(
        size: AdSize.banner,
        adUnitId: AdBannerPlaceholder.prodBannerUnitId,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() {
              _banner = ad as BannerAd;
              _loading = false;
            });
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            debugPrint('BannerAd failed: $error');
            if (!mounted) return;
            setState(() {
              _banner = null;
              _loading = false;
            });
          },
        ),
        request: const AdRequest(),
      );
      await banner.load();
    } catch (e, st) {
      debugPrint('BannerAd load threw (app continues): $e\n$st');
      if (!mounted) return;
      setState(() {
        _banner = null;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ad = _banner;
    if (ad != null) {
      return Material(
        color: cs.surface,
        child: SizedBox(
          width: double.infinity,
          height: ad.size.height.toDouble(),
          child: Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = cs.outlineVariant.withValues(alpha: isDark ? 0.7 : 0.9);
    final fill = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
        : cs.surfaceContainerLow.withValues(alpha: 0.85);
    final label = _loading ? '廣告載入中…' : '廣告暫時無法顯示';

    return Material(
      color: cs.surface,
      child: SizedBox(
        height: AdBannerPlaceholder.bannerHeight,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: CustomPaint(
            painter: _DashedRRectPainter(
              color: borderColor,
              radius: 8,
              strokeWidth: 1.2,
              dashWidth: 5,
              dashGap: 3.5,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashGap,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.dashGap != dashGap;
  }
}
'''
(root / "lib" / "widgets" / "ad_banner_placeholder.dart").write_text(ad, encoding="utf-8")
print("ad banner cleaned")

# main.dart comment cleanup
main = (root / "lib" / "main.dart").read_text(encoding="utf-8")
main = main.replace(
    "  // TEST 1.0.3: MobileAds.initialize is delayed inside AdBannerPlaceholder\n"
    "  // (first frame + ~2s), not awaited here, so launch never blocks on GMA.\n",
    "  // MobileAds.initialize is delayed inside AdBannerPlaceholder\n"
    "  // (first frame + ~2s), not awaited here, so launch never blocks on GMA.\n",
)
(root / "lib" / "main.dart").write_text(main, encoding="utf-8")
print("main comment cleaned")
