import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/utils/time_ago.dart';
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
        title: Text(widget.communityName?.isNotEmpty == true ? '${widget.communityName} · Events' : 'Community Events'),
        bottom: appBarBottomBorder(context),
      ),
      floatingActionButton: _canManageEvents
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New event'),
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
                        padding: const EdgeInsets.all(12),
                        itemCount: _occurrences.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverUrl != null && coverUrl.isNotEmpty)
            AspectRatio(aspectRatio: 16 / 9, child: Image.network(coverUrl, fit: BoxFit.cover)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    if (isRecurring) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.repeat, size: 18)),
                  ],
                ),
                const SizedBox(height: 4),
                if (startsAt != null)
                  Text(
                    formatEventDateTime(startsAt),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                  ),
                if (location != null && location.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [const Icon(Icons.place_outlined, size: 16), const SizedBox(width: 4), Expanded(child: Text(location))]),
                  ),
                if (onlineUrl != null && onlineUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: const [Icon(Icons.videocam_outlined, size: 16), SizedBox(width: 4), Text('Online event')]),
                  ),
                if (description != null && description.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(description, maxLines: 3, overflow: TextOverflow.ellipsis)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Going'),
                      selected: myRsvpStatus == 'going',
                      onSelected: (_) => onRsvp('going'),
                    ),
                    ChoiceChip(
                      label: const Text('Interested'),
                      selected: myRsvpStatus == 'interested',
                      onSelected: (_) => onRsvp('interested'),
                    ),
                    ChoiceChip(
                      label: const Text("Can't go"),
                      selected: myRsvpStatus == 'not_going',
                      onSelected: (_) => onRsvp('not_going'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
