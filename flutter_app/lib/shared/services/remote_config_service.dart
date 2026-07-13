import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Reads simple feature-flag / tuning values from the public.app_config
/// table so things like ads can be turned on, off, or adjusted from the
/// database without shipping a new app build.
///
/// Values are cached in memory after the first successful fetch; if the
/// fetch fails (offline, table missing, etc.) safe defaults are used —
/// ads default to OFF, never on, if config can't be reached.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const _defaults = <String, dynamic>{
    'ads_enabled': false,
    'ads_test_mode': true,
    'ads_feed_interval': 8,
  };

  Map<String, dynamic> _cache = Map.of(_defaults);
  bool _loaded = false;

  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  Future<void> load() async {
    final client = _client;
    if (client == null) return;
    try {
      final rows = await client.from('app_config').select('key, value');
      final fresh = Map.of(_defaults);
      for (final row in rows as List) {
        fresh[row['key'] as String] = row['value'];
      }
      _cache = fresh;
      _loaded = true;
    } catch (_) {
      // Keep previous cache (or defaults) — ads stay off on any failure.
    }
  }

  bool get adsEnabled => _cache['ads_enabled'] == true;
  bool get adsTestMode => _cache['ads_test_mode'] != false; // default true (safe)
  int get adsFeedInterval {
    final v = _cache['ads_feed_interval'];
    if (v is int) return v.clamp(3, 50);
    if (v is num) return v.toInt().clamp(3, 50);
    return 8;
  }

  bool get isLoaded => _loaded;

  /// Reads an arbitrary string config value (e.g. a real AdMob unit ID),
  /// returning null if unset. Values are stored as JSON, so a plain
  /// string key stores/reads as a JSON string.
  String? stringValue(String key) {
    final v = _cache[key];
    return v is String && v.isNotEmpty ? v : null;
  }
}
