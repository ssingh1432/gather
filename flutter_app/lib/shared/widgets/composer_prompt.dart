import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import 'auth_redirects.dart';
import 'reusables.dart';

/// A tappable "What's on your mind?" bar shown at the top of the home feed.
/// Tapping it (or the photo shortcut) opens the full composer — this stays
/// intentionally lightweight so it doesn't compete with the feed below.
class ComposerPrompt extends StatelessWidget {
  const ComposerPrompt({super.key, this.communityId});
  final String? communityId;

  String get _createPostRoute => communityId == null || communityId!.isEmpty ? '/create-post' : '/create-post?communityId=${Uri.encodeComponent(communityId!)}';

  void _openComposer(BuildContext context) {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      redirectToLogin(context, redirect: _createPostRoute, message: 'Please log in or create an account to post.');
      return;
    }
    context.push(_createPostRoute);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          const ProfileAvatarSelf(),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openComposer(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text("What's on your mind?", style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _openComposer(context),
            icon: Icon(Icons.image_outlined, color: theme.colorScheme.primary),
            tooltip: 'Add photo',
          ),
        ]),
      ),
    );
  }
}

/// Small helper so [ComposerPrompt] doesn't need to fetch the current
/// user's avatar itself — falls back to a plain person icon, which is
/// enough context for a tappable prompt bar.
class ProfileAvatarSelf extends StatelessWidget {
  const ProfileAvatarSelf({super.key});

  @override
  Widget build(BuildContext context) => const ProfileAvatar(radius: 18);
}
