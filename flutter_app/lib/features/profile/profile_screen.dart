import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/auth_service.dart';
import '../data/repositories.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _PS();
}

class _PS extends State<ProfileScreen> {
  final u = TextEditingController(), b = TextEditingController(), p = TextEditingController();
  Map<String, dynamic>? profile;
  int followers = 0;
  int following = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    final repo = ProfileRepository();
    profile = await repo.loadProfile(uid);
    followers = await repo.followers(uid);
    following = await repo.following(uid);
    u.text = profile?['username'] ?? '';
    b.text = profile?['bio'] ?? '';
    p.text = profile?['profile_photo_url'] ?? '';
    setState(() {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: profile == null
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('Followers: $followers • Following: $following'),
                  TextField(controller: u, decoration: const InputDecoration(labelText: 'Username')),
                  TextField(controller: b, decoration: const InputDecoration(labelText: 'Bio')),
                  TextField(controller: p, decoration: const InputDecoration(labelText: 'Photo URL')),
                  ElevatedButton(
                      onPressed: () async {
                        final uid = SupabaseConfig.client.auth.currentUser!.id;
                        await ProfileRepository().updateProfile(uid, {'username': u.text.trim(), 'bio': b.text.trim(), 'profile_photo_url': p.text.trim()});
                      },
                      child: const Text('Save')),
                  ElevatedButton(
                      onPressed: () async {
                        await AuthService().signOut();
                        if (mounted) context.go('/login');
                      },
                      child: const Text('Logout'))
                ]),
              ),
      );
}
