import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared button widgets matching the 股市助手 design system.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label),
            ],
          );
    final btn = FilledButton(
      onPressed: onPressed,
      style: appPrimaryButtonStyle(scheme),
      child: child,
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label),
            ],
          );
    final btn = FilledButton(
      onPressed: onPressed,
      style: appSecondaryButtonStyle(scheme),
      child: child,
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class AppOutlineButton extends StatelessWidget {
  const AppOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label),
            ],
          );
    final btn = OutlinedButton(
      onPressed: onPressed,
      style: appOutlineButtonStyle(scheme),
      child: child,
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class AppDangerButton extends StatelessWidget {
  const AppDangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.delete_outline,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label),
            ],
          );
    final btn = FilledButton(
      onPressed: onPressed,
      style: appPrimaryButtonStyle(scheme, danger: true),
      child: child,
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final btn = IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      style: appIconButtonStyle(scheme),
    );
    return btn;
  }
}
