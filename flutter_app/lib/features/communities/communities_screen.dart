import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});
  @override
  State<CommunitiesScreen> createState() => _C();
}

class _C extends State<CommunitiesScreen> {
  final repo = CommunityRepository();
  final q = TextEditingController();
  late Future<List<Map<String, dynamic>>> f = _load();
  Map<String, bool> joined = {};

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await repo.listCommunities(q.text.trim());
    final uid = SupabaseConfig.currentUserId;
    if (uid != null && data.isNotEmpty) {
      joined = await repo.joinedStates(data.map((e) => e['id'].toString()).toList(), uid);
    } else {
      joined = {};
    }
    return data;
  }

  void _retry() => setState(() => f = _load());

  Future<void> _handleJoinLeave(Map<String, dynamic> community) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      redirectToLogin(context, redirect: '/communities', message: 'Please log in or create an account to join a community.');
      return;
    }
    final id = community['id'].toString();
    final isMember = joined[id] ?? false;
    try {
      if (isMember) {
        await repo.leaveCommunity(id, uid);
      } else {
        final result = await repo.requestJoin(id);
        if (result == 'requested' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Join request sent. An owner or admin will review it.')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update membership: $e')));
      return;
    }
    _retry();
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Communities')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (SupabaseConfig.currentUserId == null) {
            redirectToLogin(context, redirect: '/create-community', message: 'Please log in or create an account to create a community.');
            return;
          }
          context.push('/create-community');
        },
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: q,
            decoration: InputDecoration(
              hintText: 'Search communities',
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _retry),
            ),
            onSubmitted: (_) => _retry(),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: f,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const FeedSkeletonList(itemCount: 4);
              }
              if (snapshot.hasError) {
                return ErrorRetryState(title: 'Unable to load communities', message: 'Network failure. Check your connection and try again.', onRetry: _retry);
              }
              final data = snapshot.data ?? const <Map<String, dynamic>>[];
              if (data.isEmpty) {
                return EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No communities',
                  message: q.text.trim().isEmpty ? 'Be the first to create a community.' : 'Try a different search or create it yourself.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _retry(),
                child: ListView(
                  children: data
                      .map((e) => CommunityCard(
                            community: e,
                            joined: joined[e['id'].toString()] ?? false,
                            onOpen: () => context.push('/community?id=${e['id']}'),
                            onJoinLeave: () => _handleJoinLeave(e),
                          ))
                      .toList(),
                ),
              );
            },
          ),
        )
      ]),
    );
  }
}
