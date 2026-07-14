import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import 'reusables.dart';

/// Cover photo + overlapping avatar + name/handle/role badge — the top of
/// every profile, own or someone else's.
class ProfileCoverAndIdentity extends StatelessWidget {
  const ProfileCoverAndIdentity({
    super.key,
    required this.coverUrl,
    required this.avatarUrl,
    required this.displayName,
    required this.username,
    this.role = 'user',
  });

  final String? coverUrl;
  final String? avatarUrl;
  final String displayName;
  final String username;
  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _CoverPhoto(url: coverUrl),
            Positioned(
              bottom: -40,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, shape: BoxShape.circle),
                child: ProfileAvatar(url: avatarUrl, radius: 44),
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Flexible(
                child: Text(displayName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              ),
              if (role != 'user') ...[
                const SizedBox(width: 6),
                _RoleBadge(role: role),
              ],
            ],
          ),
        ),
        if (username.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('@$username', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ),
      ],
    );
  }
}

class _CoverPhoto extends StatelessWidget {
  const _CoverPhoto({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primary.withValues(alpha: 0.35), theme.colorScheme.primary.withValues(alpha: 0.12)],
        ),
      ),
      child: (url != null && url!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              fadeInDuration: const Duration(milliseconds: 150),
              errorWidget: (context, url, error) => const SizedBox.shrink(),
            )
          : null,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    final theme = Theme.of(context);
    return Tooltip(
      message: isAdmin ? 'Admin' : 'Moderator',
      child: Icon(isAdmin ? Icons.verified : Icons.shield_outlined, size: 18, color: theme.colorScheme.primary),
    );
  }
}

/// Posts / Followers / Following stat row. Followers and Following are
/// tappable and open [showUserListSheet].
class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({
    super.key,
    required this.postCount,
    required this.followerCount,
    required this.followingCount,
    required this.onTapFollowers,
    required this.onTapFollowing,
  });

  final int postCount;
  final int followerCount;
  final int followingCount;
  final VoidCallback onTapFollowers;
  final VoidCallback onTapFollowing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _Stat(label: 'Posts', value: postCount),
          _Stat(label: 'Followers', value: followerCount, onTap: onTapFollowers),
          _Stat(label: 'Following', value: followingCount, onTap: onTapFollowing),
        ],
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.onTap});
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text('$value', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
    return Expanded(child: onTap == null ? content : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: content));
  }
}

/// "Member since &lt;Month Year&gt;", location, and website — the small facts
/// row under the bio.
class ProfileFactsRow extends StatelessWidget {
  const ProfileFactsRow({super.key, required this.createdAt, this.location, this.websiteUrl, this.onTapWebsite});
  final DateTime? createdAt;
  final String? location;
  final String? websiteUrl;
  final ValueChanged<String>? onTapWebsite;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final chips = <Widget>[];

    if (location != null && location!.isNotEmpty) {
      chips.add(_Fact(icon: Icons.place_outlined, text: location!, style: style));
    }
    if (websiteUrl != null && websiteUrl!.isNotEmpty) {
      chips.add(_Fact(
        icon: Icons.link,
        text: _prettyUrl(websiteUrl!),
        style: style?.copyWith(color: theme.colorScheme.primary),
        onTap: onTapWebsite == null ? null : () => onTapWebsite!(websiteUrl!),
      ));
    }
    if (createdAt != null) {
      chips.add(_Fact(icon: Icons.calendar_today_outlined, text: 'Member since ${_months[createdAt!.month - 1]} ${createdAt!.year}', style: style));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 14, runSpacing: 6, children: chips);
  }

  String _prettyUrl(String url) => url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.style, this.onTap});
  final IconData icon;
  final String text;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: style?.color),
      const SizedBox(width: 4),
      Text(text, style: style),
    ]);
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// Instagram-style grid of a user's post thumbnails. Videos show the same
/// dark placeholder + play icon used on the feed for consistency.
class ProfilePostsGrid extends StatelessWidget {
  const ProfilePostsGrid({super.key, required this.posts});
  final List<PostModel> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: EmptyState(icon: Icons.grid_view_outlined, title: 'No posts yet'),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return InkWell(
          onTap: () => context.push('/post?id=${post.id}'),
          child: post.isVideo
              ? Container(
                  color: Colors.black87,
                  child: const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70)),
                )
              : (post.displayImageUrl != null
                  ? CachedNetworkImage(imageUrl: post.displayImageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      padding: const EdgeInsets.all(6),
                      child: Text(post.textContent, maxLines: 4, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    )),
        );
      },
    );
  }
}

/// Opens a bottom sheet listing users, loaded lazily via [loader]. Used for
/// both "Followers" and "Following".
void showUserListSheet(BuildContext context, {required String title, required Future<List<RecommendedUser>> Function() loader}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _UserListSheet(title: title, loader: loader),
  );
}

class _UserListSheet extends StatefulWidget {
  const _UserListSheet({required this.title, required this.loader});
  final String title;
  final Future<List<RecommendedUser>> Function() loader;

  @override
  State<_UserListSheet> createState() => _UserListSheetState();
}

class _UserListSheetState extends State<_UserListSheet> {
  late Future<List<RecommendedUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(widget.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: FutureBuilder<List<RecommendedUser>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const EmptyState(icon: Icons.error_outline, title: 'Could not load this list');
                  }
                  final users = snapshot.data ?? const [];
                  if (users.isEmpty) {
                    return const EmptyState(icon: Icons.people_outline, title: 'Nobody here yet');
                  }
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return ListTile(
                        leading: ProfileAvatar(url: user.avatarUrl, radius: 20),
                        title: Text(user.username),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/user?id=${user.id}');
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live preview of a locally-picked (not-yet-uploaded) image — works
/// identically on mobile and Web because `XFile.readAsBytes()` never
/// touches `dart:io`, unlike `Image.file`.
class PickedImagePreview extends StatelessWidget {
  const PickedImagePreview({super.key, required this.bytesFuture, this.fit = BoxFit.cover});
  final Future<List<int>> bytesFuture;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<int>>(
        future: bytesFuture,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();
          return Image.memory(Uint8List.fromList(data), fit: fit, gaplessPlayback: true);
        },
      );
}
