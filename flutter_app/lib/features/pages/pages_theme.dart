import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Design tokens used only by the Professional Page feature.
///
/// Deliberately its own small file (not imported from `features/communities`)
/// so Pages and Communities can evolve independently, even though the values
/// mirror the Community redesign's tokens for now — both derive from
/// [AppColors]/the ambient [ColorScheme], so Pages reads as "clean, minimal,
/// professional" and consistent with the rest of Gather, per the Page System
/// design brief (clean layouts, consistent radii/spacing, no heavy shadows
/// or oversized buttons).
class PageTokens {
  PageTokens._();

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusPill = 999;

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

class PageColors {
  PageColors._();

  static Color surfaceCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark ? scheme.surfaceContainerHigh : scheme.surface;
  }

  static Color surfaceMuted(BuildContext context) => Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

  static Color border(BuildContext context) => Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6);

  static LinearGradient coverFallbackGradient(BuildContext context) {
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

InputDecoration pageFieldDecoration(
  BuildContext context, {
  required String labelText,
  String? hintText,
  String? helperText,
  TextStyle? helperStyle,
  Widget? suffixIcon,
  Widget? prefixIcon,
}) {
  final radius = BorderRadius.circular(PageTokens.radiusSm);
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    helperStyle: helperStyle,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: PageColors.surfaceMuted(context),
    border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.brandTeal, width: 1.5)),
  );
}

class PageSectionHeader extends StatelessWidget {
  const PageSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceSm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// A small pill-shaped stat, matching CommunityStatChip visually (follower
/// count, review count, rating, etc. on a Page header/card).
class PageStatChip extends StatelessWidget {
  const PageStatChip({super.key, required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: PageColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color ?? scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Shared logo/cover picker frame for Create/Edit Page — same visual
/// language as CommunityImagePickerFrame (bordered frame, gradient
/// placeholder, brand-teal edit badge).
class PageImagePickerFrame extends StatelessWidget {
  const PageImagePickerFrame({
    super.key,
    required this.label,
    required this.circular,
    required this.aspect,
    required this.onTap,
    required this.hasImage,
    required this.preview,
    this.placeholderIcon = Icons.image_outlined,
  });

  final String label;
  final bool circular;
  final double aspect;
  final VoidCallback onTap;
  final bool hasImage;
  final Widget? preview;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final radius = circular ? PageTokens.radiusPill : PageTokens.radiusMd;
    final content = hasImage && preview != null
        ? preview!
        : Container(
            decoration: BoxDecoration(gradient: PageColors.coverFallbackGradient(context)),
            alignment: Alignment.center,
            child: Icon(placeholderIcon, color: Colors.white.withValues(alpha: 0.9), size: circular ? 26 : 32),
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), border: Border.all(color: PageColors.border(context))),
                  child: AspectRatio(
                    aspectRatio: circular ? 1 : aspect,
                    child: SizedBox(width: circular ? 88 : double.infinity, child: content),
                  ),
                ),
              ),
              Positioned(
                right: circular ? -2 : 8,
                bottom: circular ? -2 : 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandTeal,
                    border: Border.all(color: PageColors.surfaceCard(context), width: 2),
                  ),
                  child: Icon(hasImage ? Icons.edit : Icons.add_a_photo, size: 13, color: AppColors.onBrandTeal),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Page type options (Step 4 of the brief) — used by the create/edit form.
const kPageTypes = <String, String>{
  'business': 'Business',
  'restaurant': 'Restaurant',
  'church': 'Church',
  'school': 'School',
  'news': 'News',
  'creator': 'Creator',
  'brand': 'Brand',
  'government': 'Government',
  'ngo': 'NGO',
  'entertainment': 'Entertainment',
  'sports': 'Sports',
  'technology': 'Technology',
  'other': 'Other',
};

/// Page team roles (Step 5 of the brief) — every role below (i.e. every
/// role except 'owner', which is tracked on `pages.owner_id` and never
/// appears in `page_roles`; see migration 072's `current_user_page_role`)
/// is assignable from the Team Management screen.
const kPageRoles = <String, String>{
  'manager': 'Manager',
  'editor': 'Editor',
  'content_creator': 'Content Creator',
  'moderator': 'Moderator',
  'customer_support': 'Customer Support',
  'analyst': 'Analyst',
};

const kPageRoleDescriptions = <String, String>{
  'owner': 'Full control. Can manage the team, settings, and everything else.',
  'manager': 'Full control except transferring or deleting the page.',
  'editor': 'Creates and manages posts, events, and reviews.',
  'content_creator': 'Creates and manages posts and events.',
  'moderator': 'Handles reviews and reports.',
  'customer_support': 'Replies to the page inbox and customer chat.',
  'analyst': 'Read-only access to page analytics.',
};

/// Page post types (Step 7 of the brief). "Stories" is explicitly listed
/// as future-ready in the brief and has no table/type yet.
const kPagePostTypes = <String, String>{
  'post': 'Post',
  'photo': 'Photo',
  'video': 'Video',
  'poll': 'Poll',
  'offer': 'Offer',
  'job': 'Job',
  'article': 'Article',
};

const kPagePostTypeIcons = <String, IconData>{
  'post': Icons.article_outlined,
  'photo': Icons.image_outlined,
  'video': Icons.videocam_outlined,
  'poll': Icons.poll_outlined,
  'offer': Icons.local_offer_outlined,
  'job': Icons.work_outline,
  'article': Icons.description_outlined,
};

/// Cover photo + overlapping circular logo — shared by the draft Preview
/// screen and the public Profile screen (Step 6) so both stay visually
/// identical without duplicating the layout math.
class PageCoverAndLogo extends StatelessWidget {
  const PageCoverAndLogo({super.key, required this.page});
  final Map<String, dynamic> page;

  @override
  Widget build(BuildContext context) {
    final coverUrl = page['cover_url'] as String?;
    final logoUrl = page['logo_url'] as String?;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AspectRatio(
          aspectRatio: 3,
          child: coverUrl != null
              ? Image.network(coverUrl, fit: BoxFit.cover)
              : Container(decoration: BoxDecoration(gradient: PageColors.coverFallbackGradient(context))),
        ),
        Positioned(
          left: PageTokens.spaceLg,
          bottom: -32,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: PageColors.surfaceCard(context), width: 3),
              color: PageColors.surfaceMuted(context),
              image: logoUrl != null ? DecorationImage(image: NetworkImage(logoUrl), fit: BoxFit.cover) : null,
            ),
            child: logoUrl == null ? const Icon(Icons.storefront, size: 28) : null,
          ),
        ),
      ],
    );
  }
}
