import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/services/performance_service.dart';

void main() {
  final svc = PerformanceService.instance;

  tearDown(() => svc.shouldSampleOverride = null);

  test('startup metrics are always sampled; unknown metrics never', () {
    expect(svc.shouldSample('app_start'), isTrue);
    expect(svc.shouldSample('first_frame'), isTrue);
    expect(svc.shouldSample('made_up'), isFalse);
  });

  test('feed_load is sampled below 100%', () {
    expect(PerformanceService.sampleRates['feed_load'], lessThan(1.0));
    final sent = List.generate(2000, (_) => svc.shouldSample('feed_load')).where((b) => b).length;
    expect(sent, greaterThan(0));
    expect(sent, lessThan(2000));
  });

  test('report without a signed-in Supabase client is a silent no-op', () {
    svc.shouldSampleOverride = (_) => true;
    expect(() => svc.report('feed_load', const Duration(milliseconds: 900)), returnsNormally);
  });
}
