import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'page_media_gallery.dart';

export '../../core/theme/app_theme.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [scheme.primary.withValues(alpha: 0.55), scheme.onPrimary]
          : [scheme.primaryContainer, scheme.primary],
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
  final scheme = Theme.of(context).colorScheme;
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
    focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
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
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1))),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class PageStatChip extends StatelessWidget {
  const PageStatChip({super.key, required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chipColor = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: PageColors.surfaceMuted(context), borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: chipColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class PageImagePickerFrame extends StatelessWidget {
  const PageImagePickerFrame({super.key, required this.label, required this.circular, required this.aspect, required this.onTap, required this.hasImage, required this.preview, this.placeholderIcon = Icons.image_outlined});
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
    final scheme = Theme.of(context).colorScheme;
    final content = hasImage && preview != null
        ? preview!
        : Container(
            decoration: BoxDecoration(gradient: PageColors.coverFallbackGradient(context)),
            alignment: Alignment.center,
            child: Icon(placeholderIcon, color: scheme.onPrimary.withValues(alpha: 0.9), size: circular ? 26 : 32),
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
                  child: AspectRatio(aspectRatio: circular ? 1 : aspect, child: SizedBox(width: circular ? 88 : double.infinity, child: content)),
                ),
              ),
              Positioned(
                right: circular ? -2 : 8,
                bottom: circular ? -2 : 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary, border: Border.all(color: PageColors.surfaceCard(context), width: 2)),
                  child: Icon(hasImage ? Icons.edit : Icons.add_a_photo, size: 13, color: scheme.onPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const kPageTypes = <String, String>{
  'business': 'Business', 'restaurant': 'Restaurant', 'church': 'Church', 'school': 'School', 'news': 'News', 'creator': 'Creator', 'brand': 'Brand', 'government': 'Government', 'ngo': 'NGO', 'entertainment': 'Entertainment', 'sports': 'Sports', 'technology': 'Technology', 'other': 'Other',
};
const kPageRoles = <String, String>{
  'manager': 'Manager', 'editor': 'Editor', 'content_creator': 'Content Creator', 'moderator': 'Moderator', 'customer_support': 'Customer Support', 'analyst': 'Analyst',
};
const kPageRoleDescriptions = <String, String>{
  'owner': 'Full control. Can manage the team, settings, and everything else.', 'manager': 'Full control except transferring or deleting the page.', 'editor': 'Creates and manages posts, events, and reviews.', 'content_creator': 'Creates and manages posts and events.', 'moderator': 'Handles reviews and reports.', 'customer_support': 'Replies to the page inbox and customer chat.', 'analyst': 'Read-only access to page analytics.',
};
const kPagePostTypes = <String, String>{
  'post': 'Post', 'photo': 'Photo', 'video': 'Video', 'poll': 'Poll', 'offer': 'Offer', 'job': 'Job', 'article': 'Article',
};
const kPagePostTypeIcons = <String, IconData>{
  'post': Icons.article_outlined, 'photo': Icons.image_outlined, 'video': Icons.videocam_outlined, 'poll': Icons.poll_outlined, 'offer': Icons.local_offer_outlined, 'job': Icons.work_outline, 'article': Icons.description_outlined,
};

class PageCoverAndLogo extends StatelessWidget {
  const PageCoverAndLogo({super.key, required this.page});
  final Map<String, dynamic> page;
  @override
  Widget build(BuildContext context) {
    final coverUrl = page['cover_url'] as String?;
    final logoUrl = page['logo_url'] as String?;
    final surface = PageColors.surfaceCard(context);
    final scheme = Theme.of(context).colorScheme;
    Widget coverFallback() => Container(
          decoration: BoxDecoration(gradient: PageColors.coverFallbackGradient(context)),
          alignment: Alignment.center,
          child: Icon(Icons.image_outlined, color: scheme.onPrimary.withValues(alpha: 0.9), size: 32),
        );
    Widget logoFallback() => const Center(child: Icon(Icons.storefront, size: 28));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AspectRatio(
          aspectRatio: 3,
          child: coverUrl != null ? PageNetworkImage(url: coverUrl, fit: BoxFit.cover, errorWidget: (_) => coverFallback()) : coverFallback(),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.16)]),
              ),
            ),
          ),
        ),
        Positioned(
          left: PageTokens.spaceLg,
          bottom: -32,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: surface, width: 3), color: PageColors.surfaceMuted(context)),
            clipBehavior: Clip.antiAlias,
            child: logoUrl != null ? PageNetworkImage(url: logoUrl, fit: BoxFit.cover, errorWidget: (_) => logoFallback()) : logoFallback(),
          ),
        ),
      ],
    );
  }
}