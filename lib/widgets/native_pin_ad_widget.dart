import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/access_control_service.dart';
import '../services/ads_consent_service.dart';
import '../services/ads_ids.dart';
import '../services/interstitial_ad_service.dart';
import 'banner_ad_widget.dart';

/// Pin native AdMob nello stile della griglia Pinterest.
/// Se l'unità native non è configurata o il load fallisce, usa il banner.
class NativePinAdWidget extends StatefulWidget {
  const NativePinAdWidget({super.key});

  @override
  State<NativePinAdWidget> createState() => _NativePinAdWidgetState();
}

class _NativePinAdWidgetState extends State<NativePinAdWidget> {
  NativeAd? _nativeAd;
  bool _ready = false;
  bool _useBannerFallback = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb || !AppAccessService().hasAds) return;
    final unitId = AdsIds.nativeAdUnitId;
    if (unitId == null) {
      if (mounted) setState(() => _useBannerFallback = true);
      return;
    }

    try {
      await InterstitialAdService.instance.initialize();
      final canRequest = await AdsConsentService.instance.canRequestAds();
      if (!canRequest) {
        if (mounted) setState(() => _useBannerFallback = true);
        return;
      }
      if (!mounted) return;

      final ad = NativeAd(
        adUnitId: unitId,
        factoryId: AdsIds.nativeFactoryId,
        request: AdsConsentService.instance.buildAdRequest(),
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() {
              _nativeAd = ad as NativeAd;
              _ready = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('NativePinAd load error: $error');
            ad.dispose();
            if (mounted) {
              setState(() {
                _nativeAd = null;
                _ready = false;
                _useBannerFallback = true;
              });
            }
          },
        ),
      );
      await ad.load();
    } catch (e) {
      debugPrint('NativePinAd skip: $e');
      if (mounted) setState(() => _useBannerFallback = true);
    }
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppAccessService().hasAds) return const SizedBox.shrink();
    if (_useBannerFallback) {
      return const BannerAdWidget();
    }
    if (!_ready || _nativeAd == null) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 280,
        child: AdWidget(ad: _nativeAd!),
      ),
    );
  }
}
