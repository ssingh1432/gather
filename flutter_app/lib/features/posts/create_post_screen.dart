import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/beta_error_logging_service.dart';
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
  String? _pendingPostId;
  bool _published = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.postCreationStarted(communityId: widget.communityId);
    if (SupabaseConfig.currentUserId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/login?redirect=${Uri.encodeComponent(_redirectLocation)}');
        }
      });
    }
  }

  @override
  void dispose() {
    if (!_published && (text.text.trim().isNotEmpty || image != null)) {
      AnalyticsService.instance.postCreationAbandoned(
        communityId: widget.communityId,
        hadText: text.text.trim().isNotEmpty,
        hadImage: image != null,
      );
    }
    text.dispose();
    super.dispose();
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
            if (err != null) ...[
              Text(err!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              const Text('You can press Publish again to retry the same post upload.'),
            ],
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
                  final postRepository = PostRepository();
                  // Keep the post id after a failed image upload so tapping
                  // Publish again retries the same storage paths instead of
                  // creating duplicate posts or orphaned media.
                  _pendingPostId ??= (await postRepository.createPost({
                    'author_id': uid,
                    'community_id': widget.communityId,
                    'text_content': text.text.trim(),
                  }))['id'].toString();

                  if (image != null) {
                    final uploaded = await postRepository.uploadPostImage(_pendingPostId!, image!);
                    await postRepository.addPostMedia(_pendingPostId!, uploaded.originalUrl);
                  }
                  _published = true;
                  if (mounted) Navigator.of(context).pop();
                } catch (e, stackTrace) {
                  BetaErrorLoggingService.instance.record(e, stackTrace, context: 'post_creation_submit', metadata: {'community_id': widget.communityId});
                  if (mounted) {
                    setState(() => err = 'Upload failed. Please check your connection and retry. $e');
                  }
                } finally {
                  if (mounted) {
                    setState(() => loading = false);
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