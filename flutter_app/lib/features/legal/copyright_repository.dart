import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Client for the DMCA-style copyright workflow (migration 130). Every write
/// goes through a SECURITY DEFINER RPC; the tables are SELECT-only for clients.
class CopyrightRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<String> submitNotice({
    required String claimantName,
    required String claimantEmail,
    String? claimantAddress,
    required String workDescription,
    String? originalWorkUrl,
    String? targetPostId,
    String? infringingUrl,
    required bool goodFaith,
    required bool accuracy,
    required String signature,
  }) async {
    final id = await _c.rpc('submit_copyright_notice', params: {
      'p_claimant_name': claimantName.trim(),
      'p_claimant_email': claimantEmail.trim(),
      'p_claimant_address': _nullIfBlank(claimantAddress),
      'p_work_description': workDescription.trim(),
      'p_original_work_url': _nullIfBlank(originalWorkUrl),
      'p_target_post_id': targetPostId,
      'p_infringing_url': _nullIfBlank(infringingUrl),
      'p_good_faith': goodFaith,
      'p_accuracy': accuracy,
      'p_signature': signature.trim(),
    });
    return id as String;
  }

  /// Notices the current user filed or that target their content (staff see all, via RLS).
  Future<List<Map<String, dynamic>>> notices() async =>
      ((await _c.from('copyright_notices').select().order('created_at', ascending: false)) as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> counterNotices() async =>
      ((await _c.from('copyright_counter_notices').select().order('created_at', ascending: false)) as List)
          .cast<Map<String, dynamic>>();

  Future<void> withdraw(String noticeId) async {
    await _c.rpc('withdraw_copyright_notice', params: {'p_notice_id': noticeId});
  }

  Future<String> submitCounterNotice({
    required String noticeId,
    required String statement,
    required bool consent,
    required String signature,
  }) async {
    final id = await _c.rpc('submit_counter_notice', params: {
      'p_notice_id': noticeId,
      'p_statement': statement.trim(),
      'p_consent': consent,
      'p_signature': signature.trim(),
    });
    return id as String;
  }

  /// Staff: [action] is 'review', 'remove' or 'reject'.
  Future<void> resolveNotice(String noticeId, String action, {String? notes}) async {
    await _c.rpc('admin_resolve_copyright_notice', params: {
      'p_notice_id': noticeId,
      'p_action': action,
      'p_notes': _nullIfBlank(notes),
    });
  }

  /// Staff: restore the content (counter-notice accepted) or keep it removed.
  Future<void> resolveCounterNotice(String counterId, {required bool restore, String? notes}) async {
    await _c.rpc('admin_resolve_counter_notice', params: {
      'p_counter_id': counterId,
      'p_restore': restore,
      'p_notes': _nullIfBlank(notes),
    });
  }

  static String? _nullIfBlank(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

/// Pure validation mirroring the CHECK constraints in migration 130, so users get
/// instant feedback instead of a database error. Returns null when valid.
class CopyrightFormValidator {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool _isHttpUrl(String v) {
    final u = Uri.tryParse(v);
    return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
  }

  static String? validateNotice({
    required String name,
    required String email,
    required String workDescription,
    required String signature,
    String? originalWorkUrl,
    String? infringingUrl,
    String? targetPostId,
    required bool goodFaith,
    required bool accuracy,
  }) {
    final n = name.trim();
    if (n.length < 2 || n.length > 200) return 'Enter your full legal name (2–200 characters).';
    final e = email.trim();
    if (e.length > 254 || !_email.hasMatch(e)) return 'Enter a valid contact email address.';
    final w = workDescription.trim();
    if (w.length < 10) return 'Describe the copyrighted work (at least 10 characters).';
    if (w.length > 2000) return 'The description is too long (maximum 2000 characters).';
    final orig = originalWorkUrl?.trim() ?? '';
    if (orig.isNotEmpty && !_isHttpUrl(orig)) return 'The link to your original work must start with http:// or https://.';
    final inf = infringingUrl?.trim() ?? '';
    if (targetPostId == null && inf.isEmpty) return 'Provide the link to the content you are reporting.';
    if (inf.isNotEmpty && !_isHttpUrl(inf)) return 'The link to the infringing content must start with http:// or https://.';
    if (!goodFaith) return 'You must confirm your good-faith belief that the use is not authorised.';
    if (!accuracy) return 'You must confirm that the information in the notice is accurate.';
    final s = signature.trim();
    if (s.length < 2 || s.length > 200) return 'Type your full name as your electronic signature.';
    return null;
  }

  static String? validateCounterNotice({
    required String statement,
    required String signature,
    required bool consent,
  }) {
    final st = statement.trim();
    if (st.length < 10) return 'Explain why the removal was a mistake (at least 10 characters).';
    if (st.length > 2000) return 'The statement is too long (maximum 2000 characters).';
    if (!consent) return 'You must consent to the stated jurisdiction to file a counter-notice.';
    final s = signature.trim();
    if (s.length < 2 || s.length > 200) return 'Type your full name as your electronic signature.';
    return null;
  }

  /// Maps database exception codes from the RPCs to readable text.
  static String friendlyError(Object error) {
    final m = error.toString();
    if (m.contains('rate_limited')) return 'You have filed too many notices today. Please try again tomorrow.';
    if (m.contains('post_not_found')) return 'That post no longer exists.';
    if (m.contains('target_required')) return 'Provide the post or the link you are reporting.';
    if (m.contains('cannot_counter')) return 'A counter-notice can only be filed by the author after content was removed.';
    if (m.contains('cannot_withdraw')) return 'This notice can no longer be withdrawn.';
    if (m.contains('already_resolved') || m.contains('not_open')) return 'This item has already been resolved.';
    if (m.contains('forbidden')) return 'You do not have permission to do that.';
    if (m.contains('not_authenticated')) return 'Please sign in first.';
    return 'Something went wrong. Please try again.';
  }
}
