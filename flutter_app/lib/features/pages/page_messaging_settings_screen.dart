import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import 'pages_theme.dart';

const _kWeekdays = <String, String>{
  'mon': 'Monday',
  'tue': 'Tuesday',
  'wed': 'Wednesday',
  'thu': 'Thursday',
  'fri': 'Friday',
  'sat': 'Saturday',
  'sun': 'Sunday',
};

/// Auto Replies / Away Messages / Business Hours Responses settings
/// (Step 9 of the brief). Gated by the standard `pages_update` RLS policy
/// (owner or `manage_settings`) — see migration 080's comment on why this
/// is settings-level rather than `manage_messages`-level.
class PageMessagingSettingsScreen extends StatefulWidget {
  const PageMessagingSettingsScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageMessagingSettingsScreen> createState() => _PageMessagingSettingsScreenState();
}

class _PageMessagingSettingsScreenState extends State<PageMessagingSettingsScreen> {
  final _repo = PageRepository();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _autoReplyEnabled = false;
  final _autoReplyCtrl = TextEditingController();
  bool _awayMessageEnabled = false;
  final _awayMessageCtrl = TextEditingController();
  Map<String, dynamic> _schedule = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoReplyCtrl.dispose();
    _awayMessageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.getPage(widget.pageId);
      if (page == null) throw Exception('Page not found.');
      if (!mounted) return;
      setState(() {
        _autoReplyEnabled = page['auto_reply_enabled'] as bool? ?? false;
        _autoReplyCtrl.text = page['auto_reply_message'] as String? ?? '';
        _awayMessageEnabled = page['away_message_enabled'] as bool? ?? false;
        _awayMessageCtrl.text = page['away_message'] as String? ?? '';
        _schedule = Map<String, dynamic>.from(page['business_hours_schedule'] as Map? ?? const {});
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load settings. $e'; _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repo.updateMessagingSettings(
        widget.pageId,
        autoReplyEnabled: _autoReplyEnabled,
        autoReplyMessage: _autoReplyCtrl.text.trim().isEmpty ? '' : _autoReplyCtrl.text.trim(),
        awayMessageEnabled: _awayMessageEnabled,
        awayMessage: _awayMessageCtrl.text.trim().isEmpty ? '' : _awayMessageCtrl.text.trim(),
        businessHoursSchedule: _schedule,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Messaging settings saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editDay(String key) async {
    final current = _schedule[key] as Map?;
    var open = current != null ? _parseTime(current['open'] as String?) : const TimeOfDay(hour: 9, minute: 0);
    var close = current != null ? _parseTime(current['close'] as String?) : const TimeOfDay(hour: 18, minute: 0);
    var closed = current == null;

    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_kWeekdays[key]!, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Closed all day'),
                value: closed,
                onChanged: (v) => setSheetState(() => closed = v),
              ),
              if (!closed) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Opens'),
                  trailing: Text(open.format(ctx)),
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: open);
                    if (picked != null) setSheetState(() => open = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Closes'),
                  trailing: Text(close.format(ctx)),
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: close);
                    if (picked != null) setSheetState(() => close = picked);
                  },
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    closed ? null : {'open': _formatTime(open), 'close': _formatTime(close)},
                  ),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brandTeal, foregroundColor: AppColors.onBrandTeal),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null && !closed) return; // sheet dismissed without pressing Done
    setState(() {
      final next = Map<String, dynamic>.from(_schedule);
      if (result == null) {
        next.remove(key);
      } else {
        next[key] = result;
      }
      _schedule = next;
    });
  }

  static TimeOfDay _parseTime(String? s) {
    if (s == null) return const TimeOfDay(hour: 9, minute: 0);
    final parts = s.split(':');
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
  }

  static String _formatTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messaging settings', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load', message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(PageTokens.spaceLg),
                  children: [
                    PageSectionHeader(title: 'Auto reply'),
                    Text('Sent automatically the first time someone messages this page.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable auto reply'),
                      value: _autoReplyEnabled,
                      onChanged: (v) => setState(() => _autoReplyEnabled = v),
                    ),
                    if (_autoReplyEnabled)
                      TextField(
                        controller: _autoReplyCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: pageFieldDecoration(context, labelText: 'Message', hintText: 'Thanks for reaching out! We\'ll reply as soon as we can.'),
                      ),
                    const Divider(height: 32),
                    PageSectionHeader(title: 'Away message'),
                    Text(
                      'Sent instead of the auto reply when the first message arrives outside the business hours set below.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable away message'),
                      value: _awayMessageEnabled,
                      onChanged: (v) => setState(() => _awayMessageEnabled = v),
                    ),
                    if (_awayMessageEnabled)
                      TextField(
                        controller: _awayMessageCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: pageFieldDecoration(context, labelText: 'Message', hintText: 'We\'re currently closed. We\'ll get back to you during business hours.'),
                      ),
                    const Divider(height: 32),
                    PageSectionHeader(title: 'Business hours'),
                    Text(
                      'Used only to decide auto reply vs. away message above. Leave every day unset to always send the auto reply.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in _kWeekdays.entries)
                      _DayRow(label: entry.value, hours: _schedule[entry.key] as Map?, onTap: () => _editDay(entry.key)),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandTeal,
                          foregroundColor: AppColors.onBrandTeal,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                        ),
                        child: _saving
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                            : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.label, required this.hours, required this.onTap});
  final String label;
  final Map? hours;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(
        hours == null ? 'Not set' : '${hours!['open']} – ${hours!['close']}',
        style: TextStyle(color: hours == null ? Theme.of(context).colorScheme.onSurfaceVariant : AppColors.brandTeal, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
