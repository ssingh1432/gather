import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'beta_context_service.dart';

/// Phase 4 beta-only non-fatal error logger using Supabase instead of a heavy crash SDK.
class BetaErrorLoggingService {
  BetaErrorLoggingService._();

  static final BetaErrorLoggingService instance = BetaErrorLoggingService._();

  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  void record(Object error, StackTrace? stackTrace, {String? context, Map<String, dynamic>? metadata}) {
    unawaited(_record(error, stackTrace, context: context, metadata: metadata));
  }

  Future<void> _record(Object error, StackTrace? stackTrace, {String? context, Map<String, dynamic>? metadata}) async {
    // Always surface the real error to console first — Supabase logging is
    // best-effort and must never be the only place the error is visible.
    debugPrint('[BetaError]${context != null ? ' [$context]' : ''} $error');
    if (stackTrace != null) debugPrint(stackTrace.toString());

    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;

    try {
      await client.from('beta_error_logs').insert({
        'user_id': userId,
        'session_id': BetaContextService.instance.sessionId,
        'message': error.toString(),
        'stack_trace': stackTrace?.toString(),
        'context': context,
        'app_version': await BetaContextService.instance.appVersion(),
        'platform': BetaContextService.instance.platform,
        'metadata': metadata ?? <String, dynamic>{},
      });
    } catch (loggingError) {
      debugPrint('Beta error log dropped: $loggingError');
    }
  }
}
