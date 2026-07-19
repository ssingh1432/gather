import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../providers/app_providers.dart';
import 'reusables.dart';

/// Small profile-photo link shown at the top of the app, alongside the
/// brand name, so a person's own avatar is always one tap away from
/// wherever they are in the feed — mirroring the top-bar avatar pattern in
/// Facebook/Instagram. Signed-out visitors see a plain login icon instead.
class TopBarProfileLink extends ConsumerWidget {
  const TopBarProfileLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      return IconButton(
        icon: const Icon(Icons.account_circle_outlined),
        tooltip: 'Log in',
        onPressed: () => context.push('/login'),
      );
    }

    final profileAsync = ref.watch(currentUserProfileProvider);
    final avatarUrl = profileAsync.asData?.value?['profile_photo_url'] as String?;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.push('/profile'),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ProfileAvatar(url: avatarUrl, radius: 16),
        ),
      ),
    );
  }
}
