import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'beta_context_service.dart';

/// Phase 4 beta-only feedback persistence. Submissions are fire-and-forget from UI callers.
class BetaFeedbackService {
  BetaFeedbackService._();

  static final BetaFeedbackService instance = BetaFeedbackService._();

  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  void submit({required String kind, required String message}) {
    unawaited(_submit(kind: kind, message: message));
  }

  Future<void> _submit({required String kind, required String message}) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;

    try {
      await client.from('beta_feedback').insert({
        'user_id': userId,
        'kind': kind,
        'message': message.trim(),
        'app_version': await BetaContextService.instance.appVersion(),
        'platform': BetaContextService.instance.platform,
        'session_id': BetaContextService.instance.sessionId,
      });
    } catch (error, stackTrace) {
      debugPrint('Beta feedback dropped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
