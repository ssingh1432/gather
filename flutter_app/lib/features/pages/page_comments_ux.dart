import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';

/// Page-only comment/reply presentation.
///
/// The interaction model is deliberately familiar to modern social feeds:
/// author identity is separate from the person being replied to, Reply always
/// targets the exact comment supplied by the caller, and long reply chains are
/// rendered as a flat conversation rather than recursively nested widgets.
class PageCommentsUx extends StatelessWidget {
  const PageCommentsUx({
    super.key,
    required this.comments,
    required this.loading,
    required this.sending,
    required this.replyingTo,
    required this.onReply,
    required this.onCancelReply,
    required this.onSubmit,
    required this.controller,
    required this.focusNode,
  });

  final List<Map<String, dynamic>> comments;
  final bool loading;
  final bool sending;
  final Map<String, dynamic>? replyingTo;
  final void Function(Map<String, dynamic>) onReply;
  final VoidCallback onCancelReply;
  final VoidCallback onSubmit;
  final TextEditingController controller;
  final FocusNode focusNode;

  Map<String, dynamic> _user(Map<String, dynamic> c) => c['users'] is Map
      ? Map<String, dynamic>.from(c['users'] as Map)
      : <String, dynamic>{};

  String _username(Map<String, dynamic> c) {
    final value = _user(c)['username']?.toString().trim();
    return value?.isNotEmpty == true ? value! : 'user';
  }

  String _userId(Map<String, dynamic> c) => c['user_id']?.toString() ?? '';

  String? _avatar(Map<String, dynamic> c) {
    final value = _user(c)['profile_photo_url']?.toString();
    return value?.isNotEmpty == true ? value : null;
  }

  Map<String, dynamic>? _parentOf(Map<String, dynamic> comment) {
    final parentId = comment['parent_comment_id']?.toString();
    if (parentId == null || parentId.isEmpty) return null;
    for (final candidate in comments) {
      if (candidate['id']?.toString() == parentId) return candidate;
    }
    return null;
  }

  List<Map<String, dynamic>> _threadReplies(String rootId) {
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final comment in comments) {
      final parent = comment['parent_comment_id']?.toString();
      if (parent != null && parent.isNotEmpty) {
        byParent.putIfAbsent(parent, () => <Map<String, dynamic>>[]).add(comment);
      }
    }

    final result = <Map<String, dynamic>>[];
    final queue = List<Map<String, dynamic>>.from(byParent[rootId] ?? const []);
    final seen = <String>{rootId};
    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      final id = item['id']?.toString();
      if (id == null || !seen.add(id)) continue;
      result.add(item);
      queue.addAll(byParent[id] ?? const []);
    }
    return result;
  }

  Widget _profileLink(BuildContext context, Map<String, dynamic> comment) {
    final userId = _userId(comment);
    return GestureDetector(
      onTap: userId.isEmpty ? null : () => context.push('/user?id=$userId'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileAvatar(url: _avatar(comment), radius: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _username(comment),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Map<String, dynamic> comment, {
    Map<String, dynamic>? replyTo,
  }) {
    final theme = Theme.of(context);
    final targetId = replyTo == null ? '' : _userId(replyTo);
    final targetUsername = replyTo == null ? null : _username(replyTo);
    final created = DateTime.tryParse(comment['created_at']?.toString() ?? '');
    final commentId = comment['id']?.toString() ?? 'unknown';

    return Padding(
      key: ValueKey('page-comment-$commentId'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profileLink(context, comment),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (targetUsername != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 2),
                    child: InkWell(
                      key: ValueKey('page-reply-target-$commentId'),
                      onTap: targetId.isEmpty ? null : () => context.push('/user?id=$targetId'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.subdirectory_arrow_right_rounded, size: 15, color: theme.colorScheme.primary),
                            const SizedBox(width: 3),
                            Text(
                              '@$targetUsername',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .52),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    comment['content']?.toString() ?? '',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 3),
                  child: Row(
                    children: [
                      if (created != null) ...[
                        Text(timeAgo(created.toLocal()), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(width: 12),
                      ],
                      InkWell(
                        onTap: () => onReply(comment),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          child: Text(
                            'Reply',
                            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _showActions(context, comment),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          child: Icon(Icons.more_horiz_rounded, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showActions(BuildContext context, Map<String, dynamic> comment) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheetContext);
                onReply(comment);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Close'),
              onTap: () => Navigator.pop(sheetContext),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roots = comments
        .where((c) => c['parent_comment_id'] == null || c['parent_comment_id'].toString().isEmpty)
        .toList();
    final rows = <Widget>[];

    for (final root in roots) {
      rows.add(_row(context, root));
      final rootId = root['id']?.toString();
      if (rootId == null) continue;
      for (final reply in _threadReplies(rootId)) {
        rows.add(_row(context, reply, replyTo: _parentOf(reply)));
      }
    }

    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Text(
                'Comments',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : rows.isEmpty
                      ? Center(child: Text('No comments yet. Be the first to comment.', style: theme.textTheme.bodySmall))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          itemCount: rows.length,
                          itemBuilder: (_, index) => rows[index],
                        ),
            ),
            if (replyingTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Replying to @${_username(replyingTo!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onCancelReply,
                      icon: const Icon(Icons.close, size: 17),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                const ProfileAvatar(radius: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmit(),
                    decoration: InputDecoration(
                      hintText: replyingTo == null ? 'Write a comment…' : 'Write a reply…',
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  onPressed: sending ? null : onSubmit,
                  icon: sending
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.send_rounded, color: theme.colorScheme.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
