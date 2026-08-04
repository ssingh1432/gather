import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/utils/time_ago.dart';
import 'community_theme.dart';
import 'create_community_event_screen.dart';

/// Community calendar/list of upcoming events (Step 11). Reads from
/// event_occurrences (see migration 061) so recurring and one-off events
/// render through the same query — every event, recurring or not, has at
/// least one occurrence row.
class CommunityEventsScreen extends StatefulWidget {
  const CommunityEventsScreen({super.key, required this.communityId, this.communityName});
  final String communityId;
  final String? communityName;

  @override
  State<CommunityEventsScreen> createState() => _CommunityEventsScreenState();
}

class _CommunityEventsScreenState extends State<CommunityEventsScreen> {
  final repo = CommunityRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _occurrences = const [];
  Map<String, Map<String, dynamic>?> _myRsvps = {};
  bool _canManageEvents = false;

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
      final uid = SupabaseConfig.currentUserId;
      _canManageEvents = await repo.hasPermission(widget.communityId, 'manage_events');
      _occurrences = await repo.listCommunityUpcomingEvents(widget.communityId);
      if (uid != null) {
        final rsvps = <String, Map<String, dynamic>?>{};
        for (final occ in _occurrences) {
          rsvps[occ['id'] as String] = await repo.myOccurrenceRsvp(occ['id'] as String, uid);
        }
        _myRsvps = rsvps;
      }
    } catch (e) {
      _error = 'Could not load events: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rsvp(String occurrenceId, String status) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    try {
      await repo.rsvpToOccurrence(occurrenceId, uid, status);
      final updated = await repo.myOccurrenceRsvp(occurrenceId, uid);
      setState(() => _myRsvps[occurrenceId] = updated);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not RSVP: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.communityName?.isNotEmpty == true ? '${widget.communityName} · Events' : 'Community Events',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: appBarBottomBorder(context),
      ),
      floatingActionButton: _canManageEvents
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.brandTeal,
              foregroundColor: AppColors.onBrandTeal,
              icon: const Icon(Icons.add),
              label: const Text('New event', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => CreateCommunityEventScreen(communityId: widget.communityId)),
                );
                if (created == true) _load();
              },
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _occurrences.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.event_outlined,
                            title: 'No upcoming events',
                            message: 'Community events will show up here once someone schedules one.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(CommunityTokens.spaceLg),
                        itemCount: _occurrences.length,
                        separatorBuilder: (_, __) => const SizedBox(height: CommunityTokens.spaceMd),
                        itemBuilder: (_, i) => _EventOccurrenceCard(
                          occurrence: _occurrences[i],
                          myRsvpStatus: _myRsvps[_occurrences[i]['id']]?['status'] as String?,
                          onRsvp: (status) => _rsvp(_occurrences[i]['id'] as String, status),
                        ),
                      ),
      ),
    );
  }
}

class _EventOccurrenceCard extends StatelessWidget {
  const _EventOccurrenceCard({required this.occurrence, required this.myRsvpStatus, required this.onRsvp});
  final Map<String, dynamic> occurrence;
  final String? myRsvpStatus;
  final ValueChanged<String> onRsvp;

  @override
  Widget build(BuildContext context) {
    final event = (occurrence['events'] as Map<String, dynamic>?) ?? const {};
    final title = (occurrence['title_override'] as String?) ?? (event['title'] as String?) ?? 'Untitled event';
    final description = (occurrence['description_override'] as String?) ?? (event['description'] as String?);
    final location = (occurrence['location_override'] as String?) ?? (event['location_text'] as String?);
    final onlineUrl = event['online_url'] as String?;
    final isRecurring = event['is_recurring'] == true;
    final startsAt = DateTime.tryParse(occurrence['starts_at'] as String? ?? '');
    final coverUrl = event['cover_image_url'] as String?;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: CommunityColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
        border: Border.all(color: CommunityColors.border(context)),
        boxShadow: CommunityTokens.subtleShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverUrl != null && coverUrl.isNotEmpty)
            AspectRatio(aspectRatio: 16 / 9, child: Image.network(coverUrl, fit: BoxFit.cover)),
          Padding(
            padding: const EdgeInsets.all(CommunityTokens.spaceMd),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (startsAt != null) _DateBadge(date: startsAt),
                if (startsAt != null) const SizedBox(width: CommunityTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                          if (isRecurring) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.repeat, size: 16, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                      if (startsAt != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          formatEventDateTime(startsAt),
                          style: const TextStyle(color: AppColors.brandTeal, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                      if (location != null && location.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            Icon(Icons.place_outlined, size: 15, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(child: Text(location, style: Theme.of(context).textTheme.bodySmall)),
                          ]),
                        ),
                      if (onlineUrl != null && onlineUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            Icon(Icons.videocam_outlined, size: 15, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text('Online event', style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        ),
                      if (description != null && description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(description, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.3)),
                        ),
                      const SizedBox(height: CommunityTokens.spaceMd),
                      Wrap(
                        spacing: 8,
                        children: [
                          _RsvpChip(label: 'Going', selected: myRsvpStatus == 'going', onTap: () => onRsvp('going')),
                          _RsvpChip(label: 'Interested', selected: myRsvpStatus == 'interested', onTap: () => onRsvp('interested')),
                          _RsvpChip(label: "Can't go", selected: myRsvpStatus == 'not_going', onTap: () => onRsvp('not_going')),
                        ],
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
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});
  final DateTime date;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.brandTealLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(CommunityTokens.radiusSm),
          border: Border.all(color: AppColors.brandTeal.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(_months[date.month - 1], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brandTeal)),
            Text('${date.day}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.brandTeal)),
          ],
        ),
      );
}

class _RsvpChip extends StatelessWidget {
  const _RsvpChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
        selectedColor: AppColors.brandTealLight,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected ? AppColors.onBrandTeal : null),
      );
}
