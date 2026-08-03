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
/// Wraps a ListTile-shaped row (member, join-request, banned user, etc.)
/// in the same card treatment used elsewhere in the Community redesign,
/// so rosters/queues look consistent with the rest of the feature.
class CommunityRowCard extends StatelessWidget {
  const CommunityRowCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: CommunityTokens.spaceLg, vertical: 3),
        child: Container(
          decoration: BoxDecoration(
            color: CommunityColors.surfaceCard(context),
            borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
            border: Border.all(color: CommunityColors.border(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
}

/// Small colored role pill (owner/admin/moderator/trusted member) shared
/// by the member roster.
class CommunityRoleChip extends StatelessWidget {
  const CommunityRoleChip({super.key, required this.role});
  final String role;

  static const _colors = {
    'owner': Color(0xFFC79100),
    'admin': Color(0xFF7C3AED),
    'moderator': AppColors.brandTeal,
    'trusted_member': Color(0xFF546E7A),
  };

  @override
  Widget build(BuildContext context) {
    if (role == 'member') return const SizedBox.shrink();
    final color = _colors[role] ?? Theme.of(context).colorScheme.outline;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CommunityTokens.radiusPill),
      ),
      child: Text(
        role.replaceAll('_', ' '),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

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
