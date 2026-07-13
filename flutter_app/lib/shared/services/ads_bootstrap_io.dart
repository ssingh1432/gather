import 'ads_service.dart';
import 'remote_config_service.dart';

/// Android/iOS/desktop build: initialize the Mobile Ads SDK, but only if
/// ads are actually enabled in remote config — no point paying SDK
/// startup cost otherwise.
Future<void> maybeInitAds() async {
  if (RemoteConfigService.instance.adsEnabled) {
    await AdsService.instance.initialize();
  }
}
