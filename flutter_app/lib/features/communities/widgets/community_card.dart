import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../community_theme.dart';

/// Card used in the community discovery list (Community Home).
///
/// This is a like-for-like functional replacement of the previous
/// `CommunityCard` in `shared/widgets/reusables.dart` — same constructor,
/// same callbacks, same data shape — just restyled. It now lives inside
/// `features/communities` since it is only ever used by Community screens.
class CommunityCard extends StatelessWidget {
  final Map<String, dynamic> community;
  final VoidCallback onOpen;
  final VoidCallback onJoinLeave;
  final bool joined;

  const CommunityCard({
    super.key,
    required this.community,
    required this.onOpen,
    required this.onJoinLeave,
    required this.joined,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPrivate = community['visibility'] == 'private';
    final isVerified = community['is_verified'] == true;
    final memberCount = (community['member_count'] as num?)?.toInt() ?? 0;
    final iconUrl = community['image_url'] as String?;
    final name = (community['name'] as String?) ?? '';
    final description = community['description'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CommunityTokens.spaceLg,
        vertical: CommunityTokens.spaceSm / 2,
      ),
      child: Material(
        color: CommunityColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
              border: Border.all(color: CommunityColors.border(context)),
              boxShadow: CommunityTokens.subtleShadow(context),
            ),
            padding: const EdgeInsets.all(CommunityTokens.spaceMd),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(iconUrl: iconUrl),
                const SizedBox(width: CommunityTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, size: 15, color: AppColors.brandTeal),
                          ],
                          if (isPrivate) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.lock_outline, size: 13, color: scheme.onSurfaceVariant),
                          ],
                        ],
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3),
                        ),
                      ],
                      const SizedBox(height: CommunityTokens.spaceSm),
                      CommunityStatChip(
                        icon: Icons.groups_outlined,
                        label: '$memberCount member${memberCount == 1 ? '' : 's'}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CommunityTokens.spaceSm),
                _JoinButton(joined: joined, isPrivate: isPrivate, onPressed: onJoinLeave),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.iconUrl});
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = iconUrl != null && iconUrl!.isNotEmpty;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasImage ? null : CommunityColors.bannerFallbackGradient(context),
        image: hasImage ? DecorationImage(image: NetworkImage(iconUrl!), fit: BoxFit.cover) : null,
      ),
      child: hasImage ? null : const Icon(Icons.groups, color: Colors.white, size: 22),
    );
  }
}

class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.joined, required this.isPrivate, required this.onPressed});
  final bool joined;
  final bool isPrivate;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = joined ? 'Leave' : (isPrivate ? 'Request' : 'Join');
    if (joined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Text(label),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brandTeal,
        foregroundColor: AppColors.onBrandTeal,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Text(label),
    );
  }
}
