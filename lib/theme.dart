import 'package:flutter/material.dart';

/// Design tokens from 股市助手 button system (light/dark).
class AppColors {
  AppColors._();

  // Teal primary from design ~ #0AB6A0
  static const Color primary = Color(0xFF0AB6A0);
  static const Color primaryPressed = Color(0xFF089E8C);
  static const Color primaryMuted = Color(0xFFB2EBE3);
  static const Color primarySoft = Color(0xFFE6F8F5);

  static const Color danger = Color(0xFFE57373);
  static const Color dangerPressed = Color(0xFFEF5350);
  static const Color dangerSoft = Color(0xFFFFEBEE);

  static const Color disabledFillLight = Color(0xFFCFD8DC);
  static const Color disabledFillDark = Color(0xFF455A64);
  static const Color disabledFg = Color(0xFF90A4AE);

  static const Color darkSurface = Color(0xFF111E30);
  static const Color darkCard = Color(0xFF1A2A40);
}

/// Taiwan-style P&L: red = gain, green = loss. Readable in light and dark.
Color pnlColor(BuildContext context, double value) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (value > 0) {
    return dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
  }
  if (value < 0) {
    return dark ? const Color(0xFF69F0AE) : const Color(0xFF2E7D32);
  }
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

const double kAppButtonRadius = 16;
const double kAppButtonMinHeight = 56;

RoundedRectangleBorder get kAppButtonShape =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(kAppButtonRadius));

ButtonStyle appPrimaryButtonStyle(ColorScheme scheme, {bool danger = false}) {
  final bg = danger ? AppColors.danger : AppColors.primary;
  final pressed = danger ? AppColors.dangerPressed : AppColors.primaryPressed;
  return ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(Size(64, kAppButtonMinHeight)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    shape: WidgetStatePropertyAll(kAppButtonShape),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return Colors.white.withValues(alpha: 0.7);
      }
      return Colors.white;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return scheme.brightness == Brightness.dark
            ? AppColors.disabledFillDark
            : AppColors.disabledFillLight;
      }
      if (states.contains(WidgetState.pressed)) return pressed;
      return bg;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.black.withValues(alpha: 0.08);
      }
      return null;
    }),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.2),
    ),
  );
}

ButtonStyle appSecondaryButtonStyle(ColorScheme scheme) {
  final soft = scheme.brightness == Brightness.dark
      ? AppColors.primary.withValues(alpha: 0.18)
      : AppColors.primarySoft;
  final softPressed = scheme.brightness == Brightness.dark
      ? AppColors.primary.withValues(alpha: 0.28)
      : AppColors.primaryMuted.withValues(alpha: 0.55);
  return ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(Size(64, kAppButtonMinHeight)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    shape: WidgetStatePropertyAll(kAppButtonShape),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return AppColors.disabledFg;
      return AppColors.primary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return scheme.brightness == Brightness.dark
            ? AppColors.disabledFillDark.withValues(alpha: 0.5)
            : const Color(0xFFF5F5F5);
      }
      if (states.contains(WidgetState.pressed)) return softPressed;
      return soft;
    }),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  );
}

ButtonStyle appOutlineButtonStyle(ColorScheme scheme) {
  return ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(Size(64, kAppButtonMinHeight)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    shape: WidgetStatePropertyAll(kAppButtonShape),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return AppColors.disabledFg;
      return AppColors.primary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return scheme.brightness == Brightness.dark
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.primarySoft;
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return const BorderSide(color: AppColors.disabledFg, width: 1.5);
      }
      return const BorderSide(color: AppColors.primary, width: 1.5);
    }),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  );
}

ButtonStyle appIconButtonStyle(ColorScheme scheme) {
  return ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(
      Size(kAppButtonMinHeight, kAppButtonMinHeight),
    ),
    maximumSize: const WidgetStatePropertyAll(
      Size(kAppButtonMinHeight, kAppButtonMinHeight),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
    shape: WidgetStatePropertyAll(kAppButtonShape),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return AppColors.disabledFg;
      return AppColors.primary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return scheme.brightness == Brightness.dark
            ? AppColors.disabledFillDark.withValues(alpha: 0.4)
            : const Color(0xFFF5F5F5);
      }
      if (states.contains(WidgetState.pressed)) {
        return scheme.brightness == Brightness.dark
            ? AppColors.primary.withValues(alpha: 0.2)
            : AppColors.primarySoft;
      }
      return scheme.brightness == Brightness.dark
          ? AppColors.darkCard
          : Colors.white;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: AppColors.disabledFg.withValues(alpha: 0.4));
      }
      return BorderSide(
        color: scheme.brightness == Brightness.dark
            ? AppColors.primary.withValues(alpha: 0.35)
            : AppColors.primaryMuted,
      );
    }),
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: isDark
        ? AppColors.primary.withValues(alpha: 0.22)
        : AppColors.primarySoft,
    onPrimaryContainer: isDark ? AppColors.primaryMuted : AppColors.primaryPressed,
    secondary: isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0),
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: AppColors.dangerSoft,
    surface: isDark ? AppColors.darkSurface : const Color(0xFFF7FAFC),
    surfaceContainerLow: isDark ? AppColors.darkCard : Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: scheme.surfaceContainerLow,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: appPrimaryButtonStyle(scheme),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: appPrimaryButtonStyle(scheme),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: appOutlineButtonStyle(scheme),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppColors.disabledFg;
          return AppColors.primary;
        }),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        shape: WidgetStatePropertyAll(kAppButtonShape),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: appIconButtonStyle(scheme),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: kAppButtonShape,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 24,
    ),
  );
}

Widget sectionHeader(BuildContext context, String title, {String? subtitle}) {
  final t = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: t.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
        ],
      ],
    ),
  );
}

Widget emptyState(BuildContext context, {
  required IconData icon,
  required String message,
  String? hint,
}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 48, color: cs.outline),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ],
    ),
  );
}

Widget summaryCard(BuildContext context, {required List<Widget> children}) {
  final cs = Theme.of(context).colorScheme;
  return Card(
    color: cs.primaryContainer.withValues(alpha: 0.55),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: cs.onPrimaryContainer,
              height: 1.45,
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}
