import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'pages_theme.dart';

/// Ratings & Reviews (Step 10 of the Page System brief).
///
/// One review per user per page (write == edit-in-place). Two separate
/// moderation paths, matching the `page_reports` precedent (074):
///   - The page team (owner / `manage_reviews`) can hide a review directly
///     for spam/off-topic — the "Moderation" bullet.
///   - Anyone can file a formal abuse report, which goes to site-level
///     moderators only, never the page's own team — the "Review Reporting"
///     bullet, so a page can't silence a critic by reporting them and
///     resolving its own report.
class PageReviewsScreen extends StatefulWidget {
  const PageReviewsScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageReviewsScreen> createState() => _PageReviewsScreenState();
}

class _PageReviewsScreenState extends State<PageReviewsScreen> {
  final _repo = PageRepository();
  static const _pageSize = 20;

  bool _loading = true;
  String? _error;
  bool _loadingMore = false;
  bool _hasMore = true;

  bool _canModerate = false;
  Map<String, dynamic>? _myReview;
  Map<int, int> _breakdown = const {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
  double _avg = 0;
  int _total = 0;
  String _sort = 'recent';
  List<Map<String, dynamic>> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.hasPagePermission(widget.pageId, 'manage_reviews'),
        _repo.myPageReview(widget.pageId),
        _repo.pageRatingBreakdown(widget.pageId),
        _repo.listPageReviews(widget.pageId, limit: _pageSize, offset: 0, sort: _sort),
      ]);
      final breakdown = results[2] as Map<int, int>;
      final total = breakdown.values.fold<int>(0, (a, b) => a + b);
      final avg = total == 0 ? 0.0 : breakdown.entries.fold<double>(0, (a, e) => a + e.key * e.value) / total;
      if (!mounted) return;
      setState(() {
        _canModerate = results[0] as bool;
        _myReview = results[1] as Map<String, dynamic>?;
        _breakdown = breakdown;
        _total = total;
        _avg = avg;
        _reviews = results[3] as List<Map<String, dynamic>>;
        _hasMore = _reviews.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t load reviews.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _repo.listPageReviews(widget.pageId, limit: _pageSize, offset: _reviews.length, sort: _sort);
      if (!mounted) return;
      setState(() {
        _reviews = [..._reviews, ...more];
        _hasMore = more.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _changeSort(String sort) async {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    await _load();
  }

  Future<void> _openWriteReview() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WriteReviewSheet(pageId: widget.pageId, existing: _myReview),
    );
    if (result == true) _load();
  }

  Future<void> _deleteMyReview() async {
    final review = _myReview;
    if (review == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your review?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deletePageReview(review['id'] as String);
      if (mounted) _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t delete review.')));
    }
  }

  Future<void> _toggleHelpful(Map<String, dynamic> review) async {
    final voted = review['voted_helpful'] == true;
    setState(() {
      review['voted_helpful'] = !voted;
      review['helpful_count'] = (review['helpful_count'] as int) + (voted ? -1 : 1);
    });
    try {
      await _repo.toggleReviewHelpful(review['id'] as String, !voted);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        review['voted_helpful'] = voted;
        review['helpful_count'] = (review['helpful_count'] as int) + (voted ? 1 : -1);
      });
    }
  }

  Future<void> _report(Map<String, dynamic> review) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportReviewSheet(pageId: widget.pageId, reviewId: review['id'] as String),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report sent to Gather moderators.')));
    }
  }

  Future<void> _respond(Map<String, dynamic> review) async {
    final controller = TextEditingController(text: review['owner_response'] as String? ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Respond to review'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 2000,
          decoration: pageFieldDecoration(context, labelText: 'Your response'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Post response')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await _repo.respondToPageReview(review['id'] as String, result);
      if (mounted) _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t post response.')));
    }
  }

  Future<void> _toggleHidden(Map<String, dynamic> review) async {
    final hide = review['status'] == 'published';
    try {
      await _repo.setPageReviewVisibility(review['id'] as String, hidden: hide);
      if (mounted) _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t update review.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load reviews', message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: PageTokens.spaceXxl),
                    children: [
                      _buildSummary(context),
                      _buildMyReviewCta(context),
                      _buildSortRow(context),
                      if (_reviews.isEmpty)
                        const EmptyState(icon: Icons.star_outline, title: 'No reviews yet', message: 'Be the first to share your experience.')
                      else
                        ..._reviews.map((r) => _ReviewCard(
                              review: r,
                              canModerate: _canModerate,
                              isMine: r['user_id'] == _myReview?['user_id'],
                              onHelpful: () => _toggleHelpful(r),
                              onReport: () => _report(r),
                              onRespond: () => _respond(r),
                              onToggleHidden: () => _toggleHidden(r),
                            )),
                      if (_hasMore)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: PageTokens.spaceLg),
                          child: Center(
                            child: _loadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton(onPressed: _loadMore, child: const Text('Load more')),
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton: !_canModerate
          ? FloatingActionButton.extended(
              onPressed: _myReview != null ? () => _showMyReviewActions() : _openWriteReview,
              icon: Icon(_myReview != null ? Icons.edit_outlined : Icons.rate_review_outlined),
              label: Text(_myReview != null ? 'Your review' : 'Write a review'),
            )
          : null,
    );
  }

  void _showMyReviewActions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit review'), onTap: () { Navigator.pop(ctx); _openWriteReview(); }),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete review'), onTap: () { Navigator.pop(ctx); _deleteMyReview(); }),
        ]),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final maxCount = _breakdown.values.isEmpty ? 1 : _breakdown.values.reduce((a, b) => a > b ? a : b);
    return Container(
      margin: const EdgeInsets.fromLTRB(PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceLg, 0),
      padding: const EdgeInsets.all(PageTokens.spaceLg),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(_avg.toStringAsFixed(1), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              _StarRow(rating: _avg, size: 16),
              const SizedBox(height: 4),
              Text('$_total review${_total == 1 ? '' : 's'}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(width: PageTokens.spaceXl),
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((star) {
                final count = _breakdown[star] ?? 0;
                final fraction = maxCount == 0 ? 0.0 : count / maxCount;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text('$star', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 6,
                            backgroundColor: PageColors.surfaceMuted(context),
                            valueColor: const AlwaysStoppedAnimation(AppColors.brandTeal),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(width: 22, child: Text('$count', style: Theme.of(context).textTheme.labelSmall)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyReviewCta(BuildContext context) {
    if (_canModerate || _myReview != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceLg, 0),
      child: OutlinedButton.icon(
        onPressed: _openWriteReview,
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Write a review'),
      ),
    );
  }

  Widget _buildSortRow(BuildContext context) {
    const options = {'recent': 'Most recent', 'helpful': 'Most helpful', 'highest': 'Highest rated', 'lowest': 'Lowest rated'};
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg, vertical: PageTokens.spaceSm),
        children: options.entries
            .map((e) => Padding(
                  padding: const EdgeInsets.only(right: PageTokens.spaceSm),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _sort == e.key,
                    onSelected: (_) => _changeSort(e.key),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating, this.size = 18});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating > i && rating < i + 1;
        return Icon(
          half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
          size: size,
          color: AppColors.brandTeal,
        );
      }),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.canModerate,
    required this.isMine,
    required this.onHelpful,
    required this.onReport,
    required this.onRespond,
    required this.onToggleHidden,
  });

  final Map<String, dynamic> review;
  final bool canModerate;
  final bool isMine;
  final VoidCallback onHelpful;
  final VoidCallback onReport;
  final VoidCallback onRespond;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final hidden = review['status'] == 'hidden';
    final removed = review['status'] == 'removed';
    final createdAt = DateTime.tryParse(review['created_at'] as String? ?? '');
    return Opacity(
      opacity: hidden || removed ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.fromLTRB(PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceLg, 0),
        padding: const EdgeInsets.all(PageTokens.spaceLg),
        decoration: BoxDecoration(
          color: PageColors.surfaceCard(context),
          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
          border: Border.all(color: PageColors.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: (review['profile_photo_url'] as String?) != null ? NetworkImage(review['profile_photo_url'] as String) : null,
                  child: (review['profile_photo_url'] as String?) == null ? const Icon(Icons.person_outline, size: 18) : null,
                ),
                const SizedBox(width: PageTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@${review['username'] ?? 'user'}', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _StarRow(rating: (review['rating'] as num).toDouble(), size: 14),
                          const SizedBox(width: 6),
                          if (createdAt != null) Text(timeAgo(createdAt), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          if (review['edited'] == true) ...[
                            const SizedBox(width: 4),
                            Text('· edited', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (v) {
                    if (v == 'report') onReport();
                    if (v == 'respond') onRespond();
                    if (v == 'toggle_hidden') onToggleHidden();
                  },
                  itemBuilder: (ctx) => [
                    if (!isMine) const PopupMenuItem(value: 'report', child: Text('Report review')),
                    if (canModerate) PopupMenuItem(value: 'respond', child: Text(review['owner_response'] != null ? 'Edit response' : 'Respond')),
                    if (canModerate) PopupMenuItem(value: 'toggle_hidden', child: Text(hidden ? 'Unhide review' : 'Hide review')),
                  ],
                ),
              ],
            ),
            if (removed) ...[
              const SizedBox(height: PageTokens.spaceSm),
              Text('This review was removed by a moderator.', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ] else ...[
              if ((review['title'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: PageTokens.spaceSm),
                Text(review['title'] as String, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 6),
              Text(review['body'] as String? ?? ''),
              if (hidden) ...[
                const SizedBox(height: 6),
                Text('Hidden by the page team — only visible to you and the reviewer.', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: PageTokens.spaceSm),
              InkWell(
                onTap: onHelpful,
                borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        review['voted_helpful'] == true ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 16,
                        color: review['voted_helpful'] == true ? AppColors.brandTeal : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Helpful${(review['helpful_count'] as int? ?? 0) > 0 ? ' (${review['helpful_count']})' : ''}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: review['voted_helpful'] == true ? AppColors.brandTeal : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              if ((review['owner_response'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: PageTokens.spaceSm),
                Container(
                  padding: const EdgeInsets.all(PageTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: PageColors.surfaceMuted(context),
                    borderRadius: BorderRadius.circular(PageTokens.radiusSm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Response from the page', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(review['owner_response'] as String, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _WriteReviewSheet extends StatefulWidget {
  const _WriteReviewSheet({required this.pageId, this.existing});
  final String pageId;
  final Map<String, dynamic>? existing;

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  final _repo = PageRepository();
  late int _rating = (widget.existing?['rating'] as int?) ?? 5;
  late final _titleController = TextEditingController(text: widget.existing?['title'] as String? ?? '');
  late final _bodyController = TextEditingController(text: widget.existing?['body'] as String? ?? '');
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_bodyController.text.trim().isEmpty) {
      setState(() => _error = 'Please write a few words about your experience.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _repo.upsertPageReview(
        widget.pageId,
        rating: _rating,
        title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
        body: _bodyController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Couldn\'t save your review. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(PageTokens.spaceLg),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(PageTokens.radiusLg)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing != null ? 'Edit your review' : 'Write a review', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: PageTokens.spaceLg),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    return IconButton(
                      onPressed: () => setState(() => _rating = i + 1),
                      icon: Icon(_rating >= i + 1 ? Icons.star : Icons.star_border, color: AppColors.brandTeal, size: 32),
                    );
                  }),
                ),
              ),
              const SizedBox(height: PageTokens.spaceMd),
              TextField(
                controller: _titleController,
                maxLength: 120,
                decoration: pageFieldDecoration(context, labelText: 'Title (optional)'),
              ),
              const SizedBox(height: PageTokens.spaceMd),
              TextField(
                controller: _bodyController,
                maxLines: 4,
                maxLength: 2000,
                decoration: pageFieldDecoration(context, labelText: 'Your review'),
              ),
              if (_error != null) ...[
                const SizedBox(height: PageTokens.spaceSm),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: PageTokens.spaceMd),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Post review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportReviewSheet extends StatefulWidget {
  const _ReportReviewSheet({required this.pageId, required this.reviewId});
  final String pageId;
  final String reviewId;

  @override
  State<_ReportReviewSheet> createState() => _ReportReviewSheetState();
}

class _ReportReviewSheetState extends State<_ReportReviewSheet> {
  final _repo = PageRepository();
  final _detailsController = TextEditingController();
  String? _reason;
  bool _submitting = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) return;
    setState(() => _submitting = true);
    try {
      await _repo.reportPageReview(widget.reviewId, widget.pageId, _reason!, details: _detailsController.text.trim().isEmpty ? null : _detailsController.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t send report. It may already be reported.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(PageTokens.spaceLg),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(PageTokens.radiusLg)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report review', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: PageTokens.spaceSm),
              Text('Sent to Gather moderators, not the page.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: PageTokens.spaceMd),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ModerationRepository.reportCategoryLabels.entries
                    .map((e) => ChoiceChip(label: Text(e.value), selected: _reason == e.key, onSelected: (_) => setState(() => _reason = e.key)))
                    .toList(),
              ),
              const SizedBox(height: PageTokens.spaceMd),
              TextField(
                controller: _detailsController,
                maxLines: 3,
                decoration: pageFieldDecoration(context, labelText: 'Additional details (optional)'),
              ),
              const SizedBox(height: PageTokens.spaceMd),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _reason == null || _submitting ? null : _submit,
                  child: _submitting ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
