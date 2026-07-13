import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'remote_config_service.dart';

/// AdMob is Android/iOS only — Flutter Web has no equivalent plugin here
/// (web monetization would be a separate AdSense-based integration later).
/// Everything in this file is a safe no-op on web and whenever ads are
/// disabled in remote config.
///
/// Deliberately sticks to BannerAd and RewardedAd, which work purely from
/// Dart. A custom in-feed "native" ad (styled like a post card) is a nice
/// upgrade later, but requires registering a NativeAdFactory in Android
/// Kotlin / iOS Swift code — worth doing once there's real traffic to
/// justify testing that on real devices.
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  bool _initialized = false;

  static bool get supportedOnThisPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Official Google test ad unit IDs. Always safe to ship — they never
  /// serve billable impressions and can't accidentally earn/charge money.
  /// Used whenever ads_test_mode is true (the default) or as a fallback
  /// if a real unit ID isn't configured yet.
  static String get _testBannerAdUnitId =>
      _isIOS ? 'ca-app-pub-3940256099942544/2934735716' : 'ca-app-pub-3940256099942544/6300978111';

  static String get _testRewardedAdUnitId =>
      _isIOS ? 'ca-app-pub-3940256099942544/1712485313' : 'ca-app-pub-3940256099942544/5224354917';

  /// Real ad unit IDs, once you have an AdMob account, go into the
  /// app_config table (so they can be set without a redeploy) rather than
  /// hardcoded here. Falls back to the Google test ID until configured.
  String get bannerAdUnitId {
    if (!RemoteConfigService.instance.adsTestMode) {
      final key = _isIOS ? 'ads_ios_banner_unit_id' : 'ads_android_banner_unit_id';
      final real = RemoteConfigService.instance.stringValue(key);
      if (real != null && real.isNotEmpty) return real;
    }
    return _testBannerAdUnitId;
  }

  String get rewardedAdUnitId {
    if (!RemoteConfigService.instance.adsTestMode) {
      final key = _isIOS ? 'ads_ios_rewarded_unit_id' : 'ads_android_rewarded_unit_id';
      final real = RemoteConfigService.instance.stringValue(key);
      if (real != null && real.isNotEmpty) return real;
    }
    return _testRewardedAdUnitId;
  }

  /// Initializes the Mobile Ads SDK. Call once at startup, only when ads
  /// are actually enabled — cheap to skip entirely otherwise.
  Future<void> initialize() async {
    if (_initialized || !supportedOnThisPlatform) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  BannerAd loadBannerAd({
    required void Function(Ad ad) onLoaded,
    required void Function(Ad ad, LoadAdError error) onFailed,
    AdSize size = AdSize.banner,
  }) {
    final ad = BannerAd(
      adUnitId: bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          onFailed(ad, error);
        },
      ),
    );
    ad.load();
    return ad;
  }

  /// Loads a rewarded ad. [onEarnedReward] fires only if the user watches
  /// through to completion — nothing to redeem for yet, but the plumbing
  /// is here for whenever there's a reward worth offering (profile boost,
  /// badge, etc).
  void loadRewardedAd({
    required void Function(RewardedAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }
}
