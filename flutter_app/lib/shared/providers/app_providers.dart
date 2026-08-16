import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/beta_access_service.dart';
import '../../features/data/repositories.dart';

final authServiceProvider = Provider((_) => AuthService());
final betaAccessServiceProvider = Provider((_) => BetaAccessService());
final betaAccessProvider = FutureProvider<bool>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState.session == null) return false;
  return ref.watch(betaAccessServiceProvider).currentUserHasAccess();
});
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authServiceProvider).authChanges());
final feedRepositoryProvider = Provider((_) => FeedRepository());
final profileRepositoryProvider = Provider((_) => ProfileRepository());

/// Live count of the current user's unread notifications, for the bell
/// badge. Rebuilds whenever auth state changes (so it picks up a fresh
/// `currentUser` on login/logout even though it's `.autoDispose` and stays
/// watched continuously by the always-visible bell icon), does one initial
/// count fetch, then keeps itself current via a Realtime subscription on
/// `notifications` (already enabled — migration 044b) filtered to this
/// user's `recipient_id`. Any insert/update (e.g. marking something read)
/// triggers a cheap re-count rather than trying to hand-patch state.
final unreadNotificationCountProvider = StreamProvider.autoDispose<int>((ref) {
  ref.watch(authStateProvider);
  final client = SupabaseConfig.maybeClient;
  final uid = client?.auth.currentUser?.id;
  if (client == null || uid == null) return Stream.value(0);

  final controller = StreamController<int>();

  Future<void> refresh() async {
    try {
      final unread = await client.from('notifications').count(CountOption.exact).eq('recipient_id', uid).eq('is_read', false);
      if (!controller.isClosed) controller.add(unread);
    } catch (_) {
      // Transient network blip: leave the last known count rather than
      // flashing the badge to an error/zero state.
    }
  }

  final channel = client
      .channel('public:notifications-unread-$uid')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'recipient_id', value: uid),
        callback: (_) => refresh(),
      )
      .subscribe();

  refresh();

  ref.onDispose(() {
    controller.close();
    client.removeChannel(channel);
  });

  return controller.stream;
});

final homeFeedProvider = FutureProvider.family<List<PostModel>, int>((ref, page) async {
  final client = SupabaseConfig.maybeClient;
  if (client == null) return [];

  final uid = client.auth.currentUser?.id;
  final repo = ref.watch(feedRepositoryProvider);
  if (uid == null) return repo.publicFeed(page: page);
  return repo.homeFeed(uid, page: page);
});

/// The current user's own row from `users` — backs the top-bar profile
/// avatar link and the "is this a brand-new account" check used to decide
/// where "People you may know" appears in the feed. `autoDispose` so it
/// picks up avatar/name changes made in Edit Profile the next time it's
/// watched, rather than caching a stale copy for the whole session.
final currentUserProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final uid = SupabaseConfig.currentUserId;
  if (uid == null) return null;
  return ref.watch(profileRepositoryProvider).loadProfile(uid);
});

/// A small, shuffled batch of people the current user doesn't already
/// follow — powers the "You may know these people" row on the home feed.
/// `autoDispose` so it re-fetches with a fresh shuffle each time the row
/// is (re)mounted rather than caching stale recommendations forever.
final recommendedUsersProvider = FutureProvider.autoDispose<List<RecommendedUser>>((ref) async {
  final client = SupabaseConfig.maybeClient;
  final uid = client?.auth.currentUser?.id;
  if (client == null || uid == null) return [];
  return ref.watch(profileRepositoryProvider).recommendedUsers(uid);
});

/// Ids of recommended users whose "Add Friend" button has been tapped this
/// session, so their card can flip to "Requested" and disable immediately
/// without waiting on a round trip back through [recommendedUsersProvider].
final sentFriendRequestsProvider = StateProvider.autoDispose<Set<String>>((ref) => <String>{});

/// Public, not-already-joined communities for the home feed's "Suggested
/// for you" groups row — mirrors [recommendedUsersProvider]'s shape and
/// autoDispose/re-shuffle behavior exactly, just for communities instead
/// of people. CommunityRepository has no existing provider registration
/// (CommunitiesScreen instantiates it directly), so this does the same
/// rather than introducing a new indirection just for this one call.
final suggestedCommunitiesProvider = FutureProvider.autoDispose<List<SuggestedCommunity>>((ref) async {
  final client = SupabaseConfig.maybeClient;
  final uid = client?.auth.currentUser?.id;
  if (client == null || uid == null) return [];
  return CommunityRepository().suggestedCommunitiesForFeed(uid);
});

/// Mirrors [suggestedCommunitiesProvider] for the home feed's "Suggested
/// Pages" row — reuses the same `page_suggested` RPC/[PageRepository.suggestedPages]
/// already powering PageDiscoveryScreen's "Suggested" tab, rather than a
/// second, separate query. That RPC already excludes followed pages and
/// ranks by category affinity to what the user follows, server-side.
final suggestedPagesProvider = FutureProvider.autoDispose<List<SuggestedPage>>((ref) async {
  final client = SupabaseConfig.maybeClient;
  final uid = client?.auth.currentUser?.id;
  if (client == null || uid == null) return [];
  final rows = await PageRepository().suggestedPages(limit: 10);
  return rows.map(SuggestedPage.fromMap).toList();
});

/// Ids of suggested communities that have been joined or marked "Not
/// interested" this session, so their card can disappear immediately
/// without waiting on a round trip back through
/// [suggestedCommunitiesProvider]. Session-only by design, same as
/// [sentFriendRequestsProvider] — a fresh app launch is allowed to
/// resurface a dismissed suggestion, the same way Facebook's own
/// "Not interested" only clears that single card instance.
final dismissedSuggestedCommunitiesProvider = StateProvider.autoDispose<Set<String>>((ref) => <String>{});
final joinedSuggestedCommunitiesProvider = StateProvider.autoDispose<Set<String>>((ref) => <String>{});

/// Session-only, same reasoning as the communities pair above.
final dismissedSuggestedPagesProvider = StateProvider.autoDispose<Set<String>>((ref) => <String>{});
final followedSuggestedPagesProvider = StateProvider.autoDispose<Set<String>>((ref) => <String>{});
