import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/services/media_upload_service.dart';
import '../data/repositories.dart';

/// Lets a user ask for the verified badge by submitting an ID document.
/// The document goes to a private bucket; only the user and staff can read it.
class RequestVerificationScreen extends StatefulWidget {
  const RequestVerificationScreen({super.key});

  @override
  State<RequestVerificationScreen> createState() => _RequestVerificationScreenState();
}

class _RequestVerificationScreenState extends State<RequestVerificationScreen> {
  static const _docTypes = {
    'citizenship': 'Citizenship certificate',
    'passport': 'Passport',
    'driving_license': 'Driving licence',
    'national_id': 'National ID',
  };

  String _type = 'citizenship';
  XFile? _doc;
  bool _busy = false;
  bool _loading = true;
  String? _status; // latest request status, if any
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final uid = SupabaseConfig.currentUserId;
      final user = await SupabaseConfig.client.from('users').select('is_verified').eq('id', uid!).single();
      if (user['is_verified'] == true) {
        _status = 'verified';
      } else {
        final rows = await SupabaseConfig.client
            .from('user_verification_requests')
            .select('status')
            .eq('user_id', uid)
            .order('submitted_at', ascending: false)
            .limit(1) as List;
        _status = rows.isEmpty ? null : rows.first['status'] as String?;
      }
    } catch (_) {
      _error = 'Could not load your verification status.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final safe = await materializeIfWeb(picked);
    setState(() => _doc = safe);
  }

  Future<void> _submit() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null || _doc == null) {
      setState(() => _error = 'Choose a photo of your document first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await MediaUploadService().uploadVerificationDoc(userId: uid, image: _doc!);
      await LegalRepository().submitVerification(idDocumentType: _type, idDocumentUrl: path);
      if (mounted) {
        setState(() => _status = 'pending');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not submit. You may already have a pending request.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _status == null || _status == 'rejected';
    return Scaffold(
      appBar: AppBar(title: const Text('Get verified')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_status == 'verified')
                  const ListTile(leading: Icon(Icons.verified), title: Text('Your account is verified.'))
                else if (_status == 'pending')
                  const ListTile(
                    leading: Icon(Icons.hourglass_top),
                    title: Text('Request under review'),
                    subtitle: Text('We will notify you once a moderator has reviewed your document.'),
                  )
                else ...[
                  if (_status == 'rejected')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('Your previous request was not approved. You can submit a new one.'),
                    ),
                  const Text(
                    'Upload a clear photo of a government ID. It is stored privately, only moderators handling '
                    'verification can see it, and it is used only to confirm your identity.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Document type'),
                    items: [for (final e in _docTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: canSubmit && !_busy ? (v) => setState(() => _type = v ?? _type) : null,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.upload_file),
                    label: Text(_doc == null ? 'Choose document photo' : 'Photo selected (tap to change)'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit for review'),
                  ),
                ],
              ],
            ),
    );
  }
}
