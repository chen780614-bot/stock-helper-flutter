import 'dart:async';

import 'package:flutter/material.dart';
import 'screens/allocate_screen.dart';
import 'screens/home_screen.dart';
import 'screens/holdings_screen.dart';
import 'screens/realized_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/watchlist_screen.dart';
import 'services/ad_free.dart';
import 'services/billing.dart';
import 'services/entitlement.dart';
import 'services/dividends.dart';
import 'services/names.dart';
import 'services/quotes.dart';
import 'services/storage.dart';
import 'theme.dart';
import 'widgets/ad_banner_placeholder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // MobileAds.initialize is delayed inside AdBannerPlaceholder /
  // RewardedAds, not awaited here, so launch never blocks on GMA.
  runApp(const StockHelperApp());
}

class StockHelperApp extends StatefulWidget {
  const StockHelperApp({super.key});

  @override
  State<StockHelperApp> createState() => _StockHelperAppState();
}

class _StockHelperAppState extends State<StockHelperApp> {
  final AppStorage _storage = AppStorage();
  final AdFreeController _adFree = AdFreeController();
  final EntitlementService _entitlement = EntitlementService();
  late final BillingService _billing = BillingService(_entitlement);
  ThemeMode _themeMode = ThemeMode.system;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final mode = await _storage.loadThemeMode();
    await _adFree.load();
    await _entitlement.load();
    await _billing.init();
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
      _ready = true;
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await _storage.saveThemeMode(mode);
  }

  @override
  void dispose() {
    _adFree.dispose();
    _billing.dispose();
    _entitlement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: '股市助手',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HomePage(
        storage: _storage,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        adFree: _adFree,
        entitlement: _entitlement,
        billing: _billing,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.storage,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.adFree,
    required this.entitlement,
    required this.billing,
  });

  final AppStorage storage;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;
  final AdFreeController adFree;
  final EntitlementService entitlement;
  final BillingService billing;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  int _realizedNonce = 0;
  int _holdingsNonce = 0;
  late final NamesService _names = NamesService(widget.storage);
  late final QuotesService _quotes = QuotesService(_names);
  late final DividendsService _dividends = DividendsService();
  int _homeNonce = 0;
  Timer? _expireTimer;

  @override
  void initState() {
    super.initState();
    // Cold start: hydrate local master; background sync if not same calendar day.
    // Never blocks UI on network.
    () async {
      try {
        await _names.ensureLoaded();
      } catch (_) {}
    }();

    widget.adFree.addListener(_onAdFreeChanged);
    widget.entitlement.addListener(_onAdFreeChanged);
    _expireTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.adFree.checkExpiredTransition() && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('廣告已恢復顯示')),
        );
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    widget.adFree.removeListener(_onAdFreeChanged);
    widget.entitlement.removeListener(_onAdFreeChanged);
    _expireTimer?.cancel();
    super.dispose();
  }

  void _onAdFreeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          storage: widget.storage,
          names: _names,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          adFree: widget.adFree,
          entitlement: widget.entitlement,
          billing: widget.billing,
          onImported: () {
            setState(() {
              _homeNonce++;
              _holdingsNonce++;
              _realizedNonce++;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ads priority: 1) paid sub  2) rewarded 24h  3) banner
    final showBanner =
        !widget.entitlement.isPremium && !widget.adFree.isAdFree;
    final pages = [
      HomeScreen(
        key: ValueKey(_homeNonce),
        storage: widget.storage,
        names: _names,
        quotes: _quotes,
        dividends: _dividends,
        active: _index == 0,
      ),
      WatchlistScreen(
        storage: widget.storage,
        names: _names,
        quotes: _quotes,
        active: _index == 1,
      ),
      HoldingsScreen(
        key: ValueKey(_holdingsNonce),
        storage: widget.storage,
        names: _names,
        quotes: _quotes,
        active: _index == 2,
        onThemeModeChanged: widget.onThemeModeChanged,
        onDataImported: () {
          setState(() {
            _homeNonce++;
            _holdingsNonce++;
            _realizedNonce++;
          });
        },
      ),
      RealizedScreen(key: ValueKey(_realizedNonce), storage: widget.storage),
      AllocateScreen(
        storage: widget.storage,
        names: _names,
        quotes: _quotes,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('股市助手'),
        actions: [
          IconButton(
            tooltip: '設置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      // Banner slightly above the tab bar (small lift) so users notice
      // when 24h ad-free hides it — not an aggressive exposure bump.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBanner) ...[
            const SizedBox(height: 6),
            const AdBannerPlaceholder(),
            const SizedBox(height: 4),
          ],
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              setState(() {
                _index = i;
                if (i == 0) _homeNonce++;
                if (i == 2) _holdingsNonce++;
                if (i == 3) _realizedNonce++;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '首頁',
              ),
              NavigationDestination(
                icon: Icon(Icons.visibility_outlined),
                selectedIcon: Icon(Icons.visibility),
                label: '觀察名單',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: '成本損益',
              ),
              NavigationDestination(
                icon: Icon(Icons.trending_up),
                selectedIcon: Icon(Icons.trending_up),
                label: '總收益',
              ),
              NavigationDestination(
                icon: Icon(Icons.pie_chart_outline),
                selectedIcon: Icon(Icons.pie_chart),
                label: '資本配置',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
