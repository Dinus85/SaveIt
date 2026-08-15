import 'package:flutter/foundation.dart';

/// Ad unit AdMob SaveIn. Native/Rewarded di produzione: incolla qui gli ID
/// creati in AdMob (console). Finché sono vuoti: debug usa test Google,
/// release usa fallback banner/interstitial così l'ads in-feed non sparisce.
class AdsIds {
  AdsIds._();

  static const String nativeFactoryId = 'pinterestPin';

  static const String _androidNativeProduction = '';
  static const String _iosNativeProduction = '';
  static const String _androidRewardedProduction = '';
  static const String _iosRewardedProduction = '';

  static const String _androidTestNative = 'ca-app-pub-3940256099942544/2247696110';
  static const String _iosTestNative = 'ca-app-pub-3940256099942544/3986624511';
  static const String _androidTestRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const String _iosTestRewarded = 'ca-app-pub-3940256099942544/1712485313';

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  static bool get useTestAds => kDebugMode;

  static String? get nativeAdUnitId {
    if (useTestAds) {
      return _isIos ? _iosTestNative : _androidTestNative;
    }
    final id = _isIos ? _iosNativeProduction : _androidNativeProduction;
    if (id.trim().isEmpty) return null;
    return id;
  }

  static String? get rewardedAdUnitId {
    if (useTestAds) {
      return _isIos ? _iosTestRewarded : _androidTestRewarded;
    }
    final id = _isIos ? _iosRewardedProduction : _androidRewardedProduction;
    if (id.trim().isEmpty) return null;
    return id;
  }

  static bool get hasProductionNative =>
      _androidNativeProduction.trim().isNotEmpty &&
      _iosNativeProduction.trim().isNotEmpty;

  static bool get hasProductionRewarded =>
      _androidRewardedProduction.trim().isNotEmpty &&
      _iosRewardedProduction.trim().isNotEmpty;
}
