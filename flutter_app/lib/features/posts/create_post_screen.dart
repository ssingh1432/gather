import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.communityId});
  final String? communityId;

  @override
  State<CreatePostScreen> createState() => _P();
}

class _P extends State<CreatePostScreen> {
  final text = TextEditingController();
  XFile? image;
  bool loading = false;
  String? err;

  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.currentUserId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/login?redirect=${Uri.encodeComponent(_redirectLocation)}');
        }
      });
    }
  }

  String get _redirectLocation {
    final communityId = widget.communityId;
    if (communityId == null || communityId.isEmpty) return '/create-post';
    return '/create-post?communityId=${Uri.encodeComponent(communityId)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Post')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: text,
              decoration: const InputDecoration(labelText: 'Text content'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                image = await ImagePicker().pickImage(source: ImageSource.gallery);
                setState(() {});
              },
              child: Text(image == null ? 'Pick image' : 'Image selected'),
            ),
            if (err != null) Text(err!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                final uid = SupabaseConfig.client.auth.currentUser?.id;
                if (uid == null) {
                  context.go('/login?redirect=${Uri.encodeComponent(_redirectLocation)}');
                  return;
                }

                if (text.text.trim().isEmpty && image == null) {
                  setState(() => err = 'Add text or image');
                  return;
                }

                setState(() => loading = true);

                try {
                  final created = await SupabaseConfig.client
                      .from('posts')
                      .insert({
                    'author_id': uid,
                    'community_id': widget.communityId,
                    'text_content': text.text.trim(),
                  })
                      .select()
                      .single();

                  if (image != null) {
                    final url = await PostRepository().uploadPostImage(uid, image!);
                    if (url != null) {
                      await PostRepository().addPostMedia(created['id'], url);
                    }
                  }
                } catch (e) {
                  setState(() => err = e.toString());
                } finally {
                  if (mounted) {
                    setState(() => loading = false);
                    Navigator.of(context).pop();
                  }
                }
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }
}