import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Design tokens used only by the Community feature.
///
/// This intentionally lives inside `features/communities` (rather than in
/// the global `core/theme`) so the visual redesign of Community screens
/// stays isolated and never changes the look of any other feature. Every
/// value here derives from [AppColors] / the ambient [ColorScheme] so the
/// Community UI still feels like part of Gather, just more polished.
class CommunityTokens {
  CommunityTokens._();

  // Spacing scale -----------------------------------------------------
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  // Radii ---------------------------------------------------------------
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusPill = 999;

  // Elevation / shadows --------------------------------------------------
  static List<BoxShadow> cardShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: (isDark ? Colors.black : AppColors.brandTeal.withValues(alpha: 0.12))
            .withValues(alpha: isDark ? 0.35 : 0.08),
        blurRadius: 18,
        offset: const Offset(0, 6),
        spreadRadius: -6,
      ),
    ];
  }

  static List<BoxShadow> subtleShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
        blurRadius: 10,
        offset: const Offset(0, 3),
        spreadRadius: -4,
      ),
    ];
  }
}

/// Shared color/gradient helpers for Community surfaces.
class CommunityColors {
  CommunityColors._();

  static Color surfaceCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark ? scheme.surfaceContainerHigh : scheme.surface;
  }

  static Color surfaceMuted(BuildContext context) => Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

  static Color border(BuildContext context) => Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6);

  static LinearGradient bannerFallbackGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [AppColors.brandTeal.withValues(alpha: 0.55), AppColors.onBrandTeal]
          : [AppColors.brandTealLight, AppColors.brandTeal],
    );
  }
}

/// A small pill-shaped stat used across Community headers/cards
/// (member count, post count, online count, etc).
class CommunityStatChip extends StatelessWidget {
  const CommunityStatChip({super.key, required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: CommunityColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(CommunityTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color ?? scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// A consistent section header used across Community screens
/// (e.g. "Suggested for you", "About", "Moderators").
class CommunitySectionHeader extends StatelessWidget {
  const CommunitySectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          CommunityTokens.spaceLg,
          CommunityTokens.spaceLg,
          CommunityTokens.spaceLg,
          CommunityTokens.spaceSm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}
