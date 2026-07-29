import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/interstitial_ad_service.dart';
import '../services/access_control_service.dart';
import '../services/plan_limits_service.dart';

/// Banner pubblicitario orizzontale mostrato solo agli utenti Free.
/// Si carica in autonomia e si dispone a larghezza piena tra le cartelle.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({Key? key}) : super(key: key);

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    PlanLimitsService.rulesRevision.addListener(_onRulesChanged);
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
    if (_bannerAd == null && !_isLoaded) {
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    if (kIsWeb || !AppAccessService().hasAds) return;

    try {
      await InterstitialAdService.instance.initialize();
    } catch (e) {
      debugPrint('BannerAd skip: AdMob non inizializzato ($e)');
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
      request: const AdRequest(),
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
  }

  @override
  void dispose() {
    PlanLimitsService.rulesRevision.removeListener(_onRulesChanged);
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
