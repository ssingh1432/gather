import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/time_ago.dart';
import 'page_visitor_post_repository.dart';

class PageVisitorPostCard extends StatefulWidget {
  const PageVisitorPostCard({super.key, required this.post, required this.page});
  final Map<String, dynamic> post;
  final Map<String, dynamic> page;

  @override
  State<PageVisitorPostCard> createState() => _PageVisitorPostCardState();
}

class _PageVisitorPostCardState extends State<PageVisitorPostCard> {
  final _repo = PageVisitorPostRepository();
  bool _liked = false;
  int _likes = 0;
  int _comments = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _likes = (widget.post['like_count'] as int?) ?? 0;
    _comments = (widget.post['comment_count'] as int?) ?? 0;
    _loadLikeState();
  }

  Future<void> _loadLikeState() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    try {
      final liked = await _repo.getLikeState(widget.post['id'] as String, uid);
      if (mounted) setState(() => _liked = liked);
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }
    if (_busy) return;
    final previous = _liked;
    setState(() {
      _busy = true;
      _liked = !previous;
      _likes += previous ? -1 : 1;
    });
    try {
      await _repo.setLike(widget.post['id'] as String, !previous);
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = previous;
          _likes += previous ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update like.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commentsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CommentsSheet(postId: widget.post['id'] as String),
    );
    if (!mounted) return;
    try {
      final count = await _repo.commentCount(widget.post['id'] as String);
      if (mounted) setState(() => _comments = count);
    } catch (_) {}
  }

  Future<void> _share() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }

    final id = widget.post['id'] as String;
    final pageId = widget.post['page_id'] as String;
    final text = (widget.post['content'] as String?)?.trim();
    final pageName = widget.page['name']?.toString() ?? 'Page';
    final author = widget.post['users'] is Map
        ? Map<String, dynamic>.from(widget.post['users'] as Map)
        : <String, dynamic>{};
    final authorName = author['display_name']?.toString().trim();
    final poster = authorName?.isNotEmpty == true ? authorName! : 'Gather user';
    final url = 'https://eiquoab.xyz/page?id=$pageId&visitorPostId=$id';
    final body = [
      'Posted by $poster on $pageName',
      if (text?.isNotEmpty == true) text!,
      url,
    ].join('\n\n');

    try {
      await Share.share(body);
      await _repo.recordShare(id, uid);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share this post.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.post['users'] is Map
        ? Map<String, dynamic>.from(widget.post['users'] as Map)
        : <String, dynamic>{};
    final name = author['display_name']?.toString().trim();
    final username = author['username']?.toString().trim();
    final poster = name?.isNotEmpty == true
        ? name!
        : username?.isNotEmpty == true
            ? '@$username'
            : 'Gather user';
    final media = widget.post['media'] is List
        ? List<Map<String, dynamic>>.from(
            (widget.post['media'] as List).whereType<Map>(),
          )
        : const <Map<String, dynamic>>[];
    final event = widget.post['page_events'] is Map
        ? Map<String, dynamic>.from(widget.post['page_events'] as Map)
        : null;
    final created = widget.post['created_at']?.toString();
    final pageName = widget.page['name']?.toString() ?? 'Page';
    final authorSubtitle = username?.isNotEmpty == true && name?.isNotEmpty == true
        ? '@$username'
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                _Avatar(
                  url: author['profile_photo_url']?.toString(),
                  icon: Icons.person_outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poster,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'posted on $pageName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (authorSubtitle != null)
                        Text(
                          authorSubtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                _Avatar(
                  url: widget.page['logo_url']?.toString(),
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
          ),
          if (created != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                timeAgo(DateTime.parse(created)),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if ((widget.post['content'] as String?)?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(widget.post['content'] as String),
            ),
          if (media.isNotEmpty) _MediaList(items: media),
          if (event != null) _EventAttachment(event: event),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _toggleLike,
                  icon: Icon(
                    _liked ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                  ),
                  label: Text('$_likes'),
                ),
                TextButton.icon(
                  onPressed: _commentsSheet,
                  icon: const Icon(Icons.comment_outlined, size: 18),
                  label: Text('$_comments'),
                ),
                TextButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.icon});
  final String? url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (url?.isNotEmpty == true) {
      return ClipOval(
        child: Image.network(
          url!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => CircleAvatar(
            radius: 18,
            child: Icon(icon, size: 18),
          ),
        ),
      );
    }
    return CircleAvatar(radius: 18, child: Icon(icon, size: 18));
  }
}

class _MediaList extends StatelessWidget {
  const _MediaList({required this.items});
  final List<Map<String, dynamic>> items;

  Future<void> _openAttachment(BuildContext context, String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this attachment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items)
            if (item['type'] == 'image')
              Image.network(
                item['url'] as String,
                width: double.infinity,
                height: 260,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 100,
                  child: Center(child: Text('Image unavailable')),
                ),
              )
            else
              InkWell(
                onTap: () => _openAttachment(
                  context,
                  item['url']?.toString() ?? '',
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        item['type'] == 'video'
                            ? Icons.videocam_outlined
                            : Icons.insert_drive_file_outlined,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item['name']?.toString() ?? 'Attachment'),
                      ),
                      const Icon(Icons.open_in_new, size: 18),
                    ],
                  ),
                ),
              ),
        ],
      );
}

class _EventAttachment extends StatelessWidget {
  const _EventAttachment({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event['title']?.toString() ?? 'Event',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (event['start_time'] != null)
                    Text(
                      DateTime.parse(event['start_time'] as String)
                          .toLocal()
                          .toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (event['location'] != null)
                    Text(
                      event['location'].toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId});
  final String postId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _repo = PageVisitorPostRepository();
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _comments = await _repo.listComments(widget.postId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }

    setState(() => _sending = true);
    try {
      await _repo.addComment(widget.postId, '', text);
      _controller.clear();
      _loading = true;
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add comment.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Comments',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                        ? const Center(child: Text('No comments yet.'))
                        : ListView.builder(
                            itemCount: _comments.length,
                            itemBuilder: (_, i) {
                              final c = _comments[i];
                              final u = c['users'] is Map
                                  ? Map<String, dynamic>.from(c['users'] as Map)
                                  : <String, dynamic>{};
                              final name = u['display_name']?.toString().trim();
                              final username = u['username']?.toString().trim();
                              return ListTile(
                                leading: _Avatar(
                                  url: u['profile_photo_url']?.toString(),
                                  icon: Icons.person_outline,
                                ),
                                title: Text(
                                  name?.isNotEmpty == true
                                      ? name!
                                      : '@${username ?? 'user'}',
                                ),
                                subtitle: Text(c['content']?.toString() ?? ''),
                              );
                            },
                          ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  8,
                  12,
                  MediaQuery.viewInsetsOf(context).bottom + 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Write a comment…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
