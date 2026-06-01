import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/supabase_client.dart';

/// Phase 4 beta-only runtime context shared by feedback, analytics, and error logs.
/// Keep this isolated so beta validation plumbing can be removed cleanly after launch.
class BetaContextService {
  BetaContextService._();

  static final BetaContextService instance = BetaContextService._();
  final String sessionId = _makeSessionId();

  String? _appVersion;

  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  Future<String> appVersion() async {
    final cached = _appVersion;
    if (cached != null) return cached;
    _appVersion = AppEnv.appVersion;
    return _appVersion!;
  }

  String get platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      _ => 'unknown',
    };
  }

  String? get currentUserId => _client?.auth.currentUser?.id;
}

String _makeSessionId() {
  final random = Random.secure();
  String hex(int bytes) => List.generate(bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return '${hex(4)}-${hex(2)}-4${hex(2).substring(1)}-${(8 + random.nextInt(4)).toRadixString(16)}${hex(2).substring(1)}-${hex(6)}';
}
