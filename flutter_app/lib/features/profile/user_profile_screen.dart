import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key, this.userId = ''});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: FutureBuilder(
        future: ProfileRepository().loadProfile(userId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final u = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u['username'] ?? ''),
                Text(u['bio'] ?? ''),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final me = SupabaseConfig.client.auth.currentUser?.id;
                        if (me != null) {
                          await ProfileRepository().follow(userId, me);
                        }
                      },
                      child: const Text('Follow'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final me = SupabaseConfig.client.auth.currentUser?.id;
                        if (me != null) {
                          await ProfileRepository().block(userId, me);
                        }
                      },
                      child: const Text('Block'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}