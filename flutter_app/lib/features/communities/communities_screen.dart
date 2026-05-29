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
  late Future<List<Map<String, dynamic>>> f = repo.listCommunities();
  Map<String, bool> joined = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Communities')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (SupabaseConfig.currentUserId == null) {
            redirectToLogin(
              context,
              redirect: '/create-community',
              message: 'Please log in or create an account to create a community.',
            );
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
              hintText: 'Search',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => f = repo.listCommunities(q.text.trim())),
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: f,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              return ListView(
                children: data
                    .map((e) => CommunityCard(
                  community: e,
                  joined: joined[e['id'].toString()] ?? false,
                  onOpen: () => context.push('/community?id=${e['id']}'),
                  onJoinLeave: () async {
                    // Join/Leave logic can be improved later
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
}
