from pathlib import Path
p = Path(r"C:\Users\user\Documents\stock-helper-flutter\lib\widgets\ad_banner_placeholder.dart")
text = """import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Bottom ad slot above the NavigationBar.
///
/// ADS-TEST 1.0.3: delayed MobileAds init (~2s after first frame) then live Banner.
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
  bool _sdkReady = false;
  bool _loading = true;
  String? _status;

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
      setState(() {
        _sdkReady = true;
        _status = 'SDK ready - loading banner';
      });
      await _loadBanner();
    } catch (e, st) {
      debugPrint('MobileAds.initialize failed (app continues): $e\\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sdkReady = false;
        _status = 'AdMob init failed (safe)';
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
              _status = 'ADS-TEST live banner';
            });
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            debugPrint('BannerAd failed: $error');
            if (!mounted) return;
            setState(() {
              _banner = null;
              _loading = false;
              _status = 'Banner load failed (safe)';
            });
          },
        ),
        request: const AdRequest(),
      );
      await banner.load();
    } catch (e, st) {
      debugPrint('BannerAd load threw (app continues): $e\\n$st');
      if (!mounted) return;
      setState(() {
        _banner = null;
        _loading = false;
        _status = 'Banner exception (safe)';
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'ADS-TEST - live AdMob',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = cs.outlineVariant.withValues(alpha: isDark ? 0.7 : 0.9);
    final fill = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
        : cs.surfaceContainerLow.withValues(alpha: 0.85);
    final String label;
    if (_loading) {
      label = _sdkReady
          ? 'ADS-TEST loading...'
          : 'ADS-TEST waiting (delayed init)';
    } else {
      label = _status ?? 'Ad slot';
    }

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
"""
p.write_text(text, encoding="utf-8")
print("wrote", p.stat().st_size)
for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
    if "ADS-TEST loading" in line or "delayed init" in line or "debugPrint" in line:
        print(i, line)
