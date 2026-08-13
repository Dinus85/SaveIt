import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/interstitial_ad_service.dart';
import '../services/access_control_service.dart';
import '../services/ads_consent_service.dart';
import '../services/plan_limits_service.dart';

/// Banner pubblicitario orizzontale mostrato solo agli utenti Free.
/// Si carica in autonomia e si dispone a larghezza piena tra le cartelle.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({Key? key}) : super(key: key);

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget>
    with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlanLimitsService.rulesRevision.addListener(_onRulesChanged);
    AdsConsentService.instance.consentTick.addListener(_onConsentChanged);
    _loadAd();
  }

  void _onRulesChanged() {
    // Solo Free vede i banner: se il piano cambia, rilancia o nascondi.
    if (!mounted) return;
    if (!AppAccessService().hasAds) {
      _bannerAd?.dispose();
      setState(() {
        _bannerAd = null;
        _isLoaded = false;
      });
      return;
    }
    _retryIfNeeded();
  }

  void _onConsentChanged() {
    _retryIfNeeded();
  }

  void _retryIfNeeded() {
    if (!mounted) return;
    if (!AppAccessService().hasAds) return;
    if (_isLoaded && _bannerAd != null) return;
    _loadAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryIfNeeded();
    }
  }

  Future<void> _loadAd() async {
    if (kIsWeb || !AppAccessService().hasAds) return;
    if (_loading || (_isLoaded && _bannerAd != null)) return;
    _loading = true;

    try {
      await InterstitialAdService.instance.initialize();

      final canRequest = await AdsConsentService.instance.canRequestAds();
      if (!canRequest) {
        debugPrint('BannerAd skip: UMP canRequestAds=false');
        return;
      }

      if (!mounted) return;

      final adUnitId = InterstitialAdService.bannerAdUnitId;
      if (kDebugMode) {
        debugPrint('BannerAd loading unit=$adUnitId');
      }

      final banner = BannerAd(
        adUnitId: adUnitId,
        size: AdSize.banner,
        // UMP/TCF decide personalizzate vs NPA; non forzare sempre NPA.
        request: AdsConsentService.instance.buildAdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() {
              _bannerAd = ad as BannerAd;
              _isLoaded = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('BannerAd load error: $error');
            ad.dispose();
            if (mounted) {
              setState(() {
                _bannerAd = null;
                _isLoaded = false;
              });
            }
          },
        ),
      );

      _bannerAd = banner;
      await banner.load();
    } catch (e) {
      debugPrint('BannerAd skip: AdMob non inizializzato ($e)');
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlanLimitsService.rulesRevision.removeListener(_onRulesChanged);
    AdsConsentService.instance.consentTick.removeListener(_onConsentChanged);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppAccessService().hasAds || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      height: _bannerAd!.size.height.toDouble(),
      alignment: Alignment.center,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
