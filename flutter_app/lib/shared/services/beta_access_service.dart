import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Phase 4 beta-only access checks. Server RPCs and RLS remain authoritative;
/// client checks only provide early, friendly messages.
class BetaAccessService {
  SupabaseClient get _client => SupabaseConfig.client;

  Future<bool> isEmailAllowed(String email) async {
    final allowed = await _client.rpc('beta_email_allowed', params: {'email': email.trim().toLowerCase()});
    return allowed == true;
  }

  Future<bool> claimForCurrentUser() async {
    final claimed = await _client.rpc('claim_beta_access_for_current_user');
    return claimed == true;
  }

  Future<bool> currentUserHasAccess() async {
    final allowed = await _client.rpc('current_user_has_beta_access');
    return allowed == true;
  }
}
