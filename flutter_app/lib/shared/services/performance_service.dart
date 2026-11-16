import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/supabase_client.dart';
import 'beta_context_service.dart';

/// Lightweight client performance telemetry (Phase 15).
///
/// Fire-and-forget, sampled, signed-in users only; the server validates the
/// metric name/range and caps writes per user per hour, so this can never block
/// or break a product flow. Metrics: `app_start`, `first_frame`, `feed_load`.
class PerformanceService {
  PerformanceService._();

  static final PerformanceService instance = PerformanceService._();

  /// Fraction of events actually sent. Startup metrics are rare (once per
  /// launch) so they are always sent; feed loads are sampled.
  static const Map<String, double> sampleRates = <String, double>{
    'app_start': 1.0,
    'first_frame': 1.0,
    'feed_load': 0.25,
  };

  final Random _random = Random();

  /// Overridable in tests.
  @visibleForTesting
  bool Function(String metric)? shouldSampleOverride;

  bool shouldSample(String metric) {
    final override = shouldSampleOverride;
    if (override != null) return override(metric);
    final rate = sampleRates[metric];
    if (rate == null) return false;
    return rate >= 1.0 || _random.nextDouble() < rate;
  }

  void report(String metric, Duration elapsed, {String? route}) {
    if (!shouldSample(metric)) return;
    final client = SupabaseConfig.maybeClient;
    if (client == null || client.auth.currentUser == null) return;
    final ms = elapsed.inMilliseconds;
    if (ms < 0 || ms > 120000) return;
    unawaited(() async {
      try {
        await client.rpc('track_performance_metric', params: {
          'p_metric': metric,
          'p_value_ms': ms,
          'p_platform': BetaContextService.instance.platform,
          'p_app_version': await BetaContextService.instance.appVersion(),
          'p_route': route,
        });
      } catch (e) {
        debugPrint('Performance sample dropped: $e');
      }
    }());
  }
}
