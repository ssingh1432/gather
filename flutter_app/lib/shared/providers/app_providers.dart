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

final homeFeedProvider = FutureProvider.family<List<PostModel>, int>((ref, page) async {
  final client = SupabaseConfig.maybeClient;
  if (client == null) return [];

  final uid = client.auth.currentUser?.id;
  final repo = ref.watch(feedRepositoryProvider);
  if (uid == null) return repo.publicFeed(page: page);
  return repo.homeFeed(uid, page: page);
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
