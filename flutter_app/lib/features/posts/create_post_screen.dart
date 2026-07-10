import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/beta_error_logging_service.dart';
import '../../shared/utils/feelings.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.communityId, this.quotePostId});
  final String? communityId;

  /// When set, this post is published as a quote/reply-share of the given
  /// post id (the "Share to your feed" flow from the post card).
  final String? quotePostId;

  @override
  State<CreatePostScreen> createState() => _P();
}

class _P extends State<CreatePostScreen> {
  final text = TextEditingController();
  final location = TextEditingController();
  final tagsCtrl = TextEditingController();
  XFile? image;
  bool loading = false;
  String? err;
  String? _pendingPostId;
  bool _published = false;
  FeelingOption? _feeling;

  PostModel? _quotedPost;
  bool _loadingQuote = false;

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
    if (widget.quotePostId != null) {
      _loadQuotedPost();
    }
  }

  Future<void> _loadQuotedPost() async {
    setState(() => _loadingQuote = true);
    try {
      final post = await FeedRepository().getPost(widget.quotePostId!);
      if (mounted) setState(() => _quotedPost = post);
    } catch (_) {
      // If the quoted post can't load, publishing still works — the
      // reply_to_post_id insert will simply be rejected server-side if it's
      // genuinely gone, so we just drop the preview rather than block posting.
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
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
    location.dispose();
    tagsCtrl.dispose();
    super.dispose();
  }

  String get _redirectLocation {
    final communityId = widget.communityId;
    if (communityId == null || communityId.isEmpty) return '/create-post';
    return '/create-post?communityId=${Uri.encodeComponent(communityId)}';
  }

  List<String> get _parsedTags => tagsCtrl.text
      .split(RegExp(r'[,\s]+'))
      .map((t) => t.trim().replaceFirst(RegExp(r'^#'), ''))
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

    Future<void> _publish() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        context.go('/login?redirect=${Uri.encodeComponent(_redirectLocation)}');
      }
      return;
    }

    if (text.text.trim().isEmpty && image == null) {
      if (mounted) setState(() => err = 'Add text or image');
      return;
    }

    if (mounted) {
      setState(() {
        loading = true;
        err = null;
      });
    }

    try {
      final postRepository = PostRepository();

      _pendingPostId ??= (await postRepository.createPost({
        'author_id': uid,
        'community_id': widget.communityId,
        'text_content': text.text.trim(),
        'location': location.text.trim().isEmpty ? null : location.text.trim(),
        'feeling': _feeling?.stored,
        'tags': _parsedTags,
        'reply_to_post_id': widget.quotePostId,
      }))['id'].toString();

      if (image != null) {
        final uploaded = await postRepository.uploadPostImage(_pendingPostId!, image!);
        await postRepository.addPostMedia(_pendingPostId!, uploaded.originalUrl);
      }

      _published = true;

      if (mounted) {
        text.clear();
        image = null;
        context.go('/');
      }
    } catch (e, stackTrace) {
      BetaErrorLoggingService.instance.record(e, stackTrace, 
        context: 'post_creation_submit', 
        metadata: {'community_id': widget.communityId}
      );

      if (mounted) {
        setState(() => err = 'Upload failed. Please check your connection and retry. $e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _pickFeeling() async {
    final selected = await showModalBottomSheet<FeelingOption>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          childAspectRatio: 3.2,
          children: [
            for (final option in kFeelingOptions)
              InkWell(
                onTap: () => Navigator.pop(sheetContext, option),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(border: Border.all(color: Theme.of(sheetContext).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
                  child: Text('${option.emoji} ${option.label}'),
                ),
              ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _feeling = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.quotePostId != null ? 'Share to your feed' : 'Create Post')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: text,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Text content', hintText: "What's on your mind?"),
            ),
            const SizedBox(height: 12),
            if (_loadingQuote) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
            if (_quotedPost != null) ...[
              _QuotedPostPreviewCard(post: _quotedPost!),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    image = await ImagePicker().pickImage(source: ImageSource.gallery);
                    setState(() {});
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(image == null ? 'Add photo' : 'Photo selected'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickFeeling,
                  icon: Text(_feeling?.emoji ?? '🙂'),
                  label: Text(_feeling == null ? 'Feeling' : _feeling!.label),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: location,
              decoration: const InputDecoration(labelText: 'Location', hintText: 'e.g. Kathmandu, Nepal', prefixIcon: Icon(Icons.location_on_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tagsCtrl,
              decoration: const InputDecoration(labelText: 'Tags', hintText: 'e.g. music, nepal, travel', prefixIcon: Icon(Icons.tag)),
            ),
            if (err != null) ...[
              const SizedBox(height: 12),
              Text(err!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              const Text('You can press Publish again to retry the same post upload.'),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _publish,
                child: loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Publish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotedPostPreviewCard extends StatelessWidget {
  const _QuotedPostPreviewCard({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(url: post.authorAvatarUrl, radius: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.authorUsername ?? 'Unknown', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                if (post.textContent.isNotEmpty)
                  Text(post.textContent, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
