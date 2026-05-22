import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/widgets/reusables.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});
  @override
  State<CommunitiesScreen> createState() => _C();
}

class _C extends State<CommunitiesScreen> {
  final repo = CommunityRepository();
  final q = TextEditingController();
  late Future<List<Map<String, dynamic>>> f = repo.listCommunities();
  Map<String, bool> joined = {};

  Future<void> _loadJoined(List<Map<String, dynamic>> communities) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    joined = await repo.joinedStates(communities.map((e) => e['id'].toString()).toList(), uid);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Communities')),
        floatingActionButton: FloatingActionButton(onPressed: () => context.push('/create-community'), child: const Icon(Icons.add)),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(controller: q, decoration: InputDecoration(hintText: 'Search', suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => f = repo.listCommunities(q.text.trim()))))),
          ),
          Expanded(
            child: FutureBuilder(
              future: f,
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final data = s.data!;
                _loadJoined(data);
                if (data.isEmpty) return const Center(child: Text('No communities'));
                return ListView(
                  children: data
                      .map((e) => CommunityCard(
                            community: e,
                            joined: joined[e['id'].toString()] ?? false,
                            onOpen: () => context.push('/community?id=${e['id']}'),
                            onJoinLeave: () async {
                              final uid = SupabaseConfig.client.auth.currentUser?.id;
                              if (uid == null) return;
                              final isJoined = joined[e['id'].toString()] ?? false;
                              if (isJoined) {
                                await repo.leaveCommunity(e['id'], uid);
                              } else {
                                await repo.joinCommunity(e['id'], uid);
                              }
                              setState(() => f = repo.listCommunities(q.text.trim()));
                            },
                          ))
                      .toList(),
                );
              },
            ),
          )
        ]),
      );
}
