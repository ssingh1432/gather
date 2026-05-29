import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});
  @override
  State<CreateCommunityScreen> createState() => _CC();
}

class _CC extends State<CreateCommunityScreen> {
  final name = TextEditingController();
  final desc = TextEditingController();
  final img = TextEditingController();
  String? err;
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Community')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: desc,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: img,
              decoration: const InputDecoration(labelText: 'Image URL'),
            ),
            if (err != null) Text(err!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                if (name.text.trim().isEmpty) {
                  setState(() => err = 'Name required');
                  return;
                }
                final uid = SupabaseConfig.client.auth.currentUser?.id;
                if (uid == null) return;

                setState(() => loading = true);

                try {
                  final cty = await CommunityRepository().createCommunity({
                    'name': name.text.trim(),
                    'description': desc.text.trim(),
                    'image_url': img.text.trim(),
                    'created_by': uid,
                  });
                  await CommunityRepository().joinCommunity(cty['id'], uid);
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  setState(() => err = e.toString());
                } finally {
                  if (mounted) setState(() => loading = false);
                }
              },
              child: loading
                  ? const CircularProgressIndicator()
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}