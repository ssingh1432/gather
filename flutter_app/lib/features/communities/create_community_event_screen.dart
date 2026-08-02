import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/repositories.dart';
import '../../shared/utils/recurrence_expander.dart';
import '../../shared/widgets/profile_view.dart' show PickedImagePreview;
import '../../shared/utils/time_ago.dart' show formatEventDateTime;

/// Creates a community-native event (Step 11). Supports a simple recurrence
/// picker (none / weekly / every 2 weeks / monthly) rather than exposing raw
/// RRULE syntax to the user — Gather targets everyday community organizers,
/// not calendar power users.
class CreateCommunityEventScreen extends StatefulWidget {
  const CreateCommunityEventScreen({super.key, required this.communityId});
  final String communityId;

  @override
  State<CreateCommunityEventScreen> createState() => _CreateCommunityEventScreenState();
}

enum _RecurrenceChoice { none, weekly, biweekly, monthly }

class _CreateCommunityEventScreenState extends State<CreateCommunityEventScreen> {
  final repo = CommunityRepository();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _onlineUrlCtrl = TextEditingController();

  DateTime? _startsAt;
  DateTime? _endsAt;
  _RecurrenceChoice _recurrence = _RecurrenceChoice.none;
  DateTime? _recurrenceEndAt;
  XFile? _coverImage;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _onlineUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() => _startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickEnd() async {
    final base = _startsAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _endsAt ?? base.add(const Duration(hours: 1)),
      firstDate: base,
      lastDate: base.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endsAt ?? base.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() => _endsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickRecurrenceEnd() async {
    final base = _startsAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _recurrenceEndAt ?? base.add(const Duration(days: 90)),
      firstDate: base,
      lastDate: base.add(const Duration(days: 730)),
    );
    if (date != null) setState(() => _recurrenceEndAt = date);
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _coverImage = picked);
  }

  String? get _recurrenceRule {
    switch (_recurrence) {
      case _RecurrenceChoice.none:
        return null;
      case _RecurrenceChoice.weekly:
        return 'FREQ=WEEKLY;INTERVAL=1';
      case _RecurrenceChoice.biweekly:
        return 'FREQ=WEEKLY;INTERVAL=2';
      case _RecurrenceChoice.monthly:
        return 'FREQ=MONTHLY;INTERVAL=1';
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please give the event a title.');
      return;
    }
    if (_startsAt == null) {
      setState(() => _error = 'Please choose a start date and time.');
      return;
    }
    if (_endsAt != null && _endsAt!.isBefore(_startsAt!)) {
      setState(() => _error = 'End time must be after the start time.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final isRecurring = _recurrence != _RecurrenceChoice.none;
      final eventId = await repo.createCommunityEvent(
        communityId: widget.communityId,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        startsAt: _startsAt!,
        endsAt: _endsAt,
        locationText: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        onlineUrl: _onlineUrlCtrl.text.trim().isEmpty ? null : _onlineUrlCtrl.text.trim(),
        isRecurring: isRecurring,
        recurrenceRule: _recurrenceRule,
        recurrenceEndAt: _recurrenceEndAt,
      );

      if (_coverImage != null) {
        final url = await repo.uploadEventCover(widget.communityId, eventId, _coverImage!);
        await repo.updateCommunityEvent(eventId, {'cover_image_url': url});
      }

      if (isRecurring) {
        final duration = _endsAt != null ? _endsAt!.difference(_startsAt!) : null;
        final dates = RecurrenceExpander.expand(
          firstStart: _startsAt!,
          rule: '${_recurrenceRule!};UNTIL=${(_recurrenceEndAt ?? _startsAt!.add(const Duration(days: 180))).toIso8601String()}',
        );
        // The trigger already created an occurrence for starts_at via the
        // non-recurring path is skipped here (is_recurring=true), so add
        // the full expanded set including the first date.
        await repo.addRecurringOccurrences(eventId, dates, duration: duration);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not create event: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New community event'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          GestureDetector(
            onTap: _pickCover,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 140,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: _coverImage == null
                    ? const Center(child: Icon(Icons.add_photo_alternate_outlined, size: 36))
                    : PickedImagePreview(bytesFuture: _coverImage!.readAsBytes()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Event title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(_startsAt == null ? 'Start date & time' : formatEventDateTime(_startsAt!)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickStart,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text(_endsAt == null ? 'End date & time (optional)' : formatEventDateTime(_endsAt!)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickEnd,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationCtrl,
            decoration: const InputDecoration(labelText: 'Location (optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.place_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _onlineUrlCtrl,
            decoration: const InputDecoration(labelText: 'Online link (optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.videocam_outlined)),
          ),
          const SizedBox(height: 20),
          Text('Repeats', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Never'), selected: _recurrence == _RecurrenceChoice.none, onSelected: (_) => setState(() => _recurrence = _RecurrenceChoice.none)),
              ChoiceChip(label: const Text('Weekly'), selected: _recurrence == _RecurrenceChoice.weekly, onSelected: (_) => setState(() => _recurrence = _RecurrenceChoice.weekly)),
              ChoiceChip(label: const Text('Every 2 weeks'), selected: _recurrence == _RecurrenceChoice.biweekly, onSelected: (_) => setState(() => _recurrence = _RecurrenceChoice.biweekly)),
              ChoiceChip(label: const Text('Monthly'), selected: _recurrence == _RecurrenceChoice.monthly, onSelected: (_) => setState(() => _recurrence = _RecurrenceChoice.monthly)),
            ],
          ),
          if (_recurrence != _RecurrenceChoice.none)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(_recurrenceEndAt == null ? 'Repeat until (default: 6 months)' : 'Repeats until ${_recurrenceEndAt.toString().split(' ').first}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _pickRecurrenceEnd,
            ),
        ],
      ),
    );
  }
}
