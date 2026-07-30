import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'access_control_service.dart';
import 'ads_consent_service.dart';
import 'plan_limits_service.dart';

class InterstitialAdService {
  InterstitialAdService._internal();

  static final InterstitialAdService instance =
      InterstitialAdService._internal();

  /// Unità di produzione (usate in release/profile).
  static const String _androidInterstitialAdUnitId =
      'ca-app-pub-1397392558961350/5839880574';
  static const String _iosInterstitialAdUnitId =
      'ca-app-pub-1397392558961350/9950660131';

  static const String androidBannerAdUnitId =
      'ca-app-pub-1397392558961350/4746290759';
  static const String iosBannerAdUnitId =
      'ca-app-pub-1397392558961350/4315988838';

  /// Unità di test ufficiali Google: in debug garantiscono fill su device/simulator.
  static const String _androidTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _iosTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _androidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _iosTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/2934735716';

  final AuthService _authService = AuthService();

  bool _isInitialized = false;
  bool _isShowingAd = false;
  Future<void>? _initializing;

  /// In debug usa le unit di test Google così le ads si vedono davvero in prova.
  /// In release/profile usa le unit SaveIn (compariranno anche su AdMob).
  static bool get useTestAds => kDebugMode;

  static String get bannerAdUnitId {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (useTestAds) {
      return isIos ? _iosTestBannerAdUnitId : _androidTestBannerAdUnitId;
    }
    return isIos ? iosBannerAdUnitId : androidBannerAdUnitId;
  }

  Future<void> initialize() async {
    if (kIsWeb) return;
    if (_isInitialized) return;
    if (_initializing != null) return _initializing!;

    _initializing = () async {
      try {
        // Consenso UMP prima di MobileAds (obbligatorio in UE).
        await AdsConsentService.instance.gatherConsent();
        await MobileAds.instance.initialize();
        // In debug forza ads non personalizzate: evita blocchi ATT/privacy in test.
        if (kDebugMode) {
          await MobileAds.instance.updateRequestConfiguration(
            RequestConfiguration(
              tagForChildDirectedTreatment:
                  TagForChildDirectedTreatment.unspecified,
              tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.unspecified,
            ),
          );
        }
        _isInitialized = true;
        if (kDebugMode) {
          debugPrint(
            'AdMob inizializzato (testAds=$useTestAds, platform=$defaultTargetPlatform)',
          );
        }
      } catch (e, st) {
        debugPrint('AdMob initialize error: $e\n$st');
        rethrow;
      } finally {
        _initializing = null;
      }
    }();

    return _initializing!;
  }

  Future<bool> showDailyOpenAdIfNeeded() async {
    if (!_shouldUseAds) return false;

    final userId = _currentUserId;
    if (userId == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final lastShown = prefs.getString(_dailyOpenAdKey(userId));
    if (lastShown == today) {
      return false;
    }

    final shown = await _showInterstitial();
    if (shown) {
      await prefs.setString(_dailyOpenAdKey(userId), today);
    }
    return shown;
  }

  Future<bool> showImportAdIfRequired() async {
    if (!_shouldUseAds) return true;

    final userId = _currentUserId;
    if (userId == null) return true;

    final prefs = await SharedPreferences.getInstance();
    final successfulImports = prefs.getInt(_successfulImportsKey(userId)) ?? 0;
    final nextImportOrdinal = successfulImports + 1;

    if (nextImportOrdinal % AppAccessService.importInterstitialFrequency != 0) {
      return true;
    }

    return _showInterstitial();
  }

  /// Mostra una interstitial ad prima di aprire un reminder.
  /// Non fa nulla se l'utente è Premium o su web.
  Future<void> showReminderAd() async {
    if (!_shouldUseAds) return;
    await _showInterstitial();
  }

  /// Mostra un passaggio pubblicitario prima di aprire un reminder salvato.
  Future<void> showReminderOpenGate(BuildContext context) async {
    await showFeatureAdGate(context, 'reminders');
  }

  /// Richiede una interstitial prima di impostare un reminder per utenti Free.
  /// Per Premium/web restituisce true senza mostrare pubblicità.
  Future<bool> showReminderSetupAdIfRequired() async {
    if (!_shouldUseAds) return true;
    return _showInterstitial();
  }

  /// Mostra un passaggio pubblicitario prima di usare una funzione configurata
  /// con `requiresAd` nella dashboard limiti piani.
  Future<void> showFeatureAdGate(BuildContext context, String feature) async {
    if (!await _featureRequiresAd(feature)) return;

    // Due tentativi: a volte il primo load AdMob fallisce (no-fill / cold start).
    var shown = await _showInterstitial();
    if (!shown) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      shown = await _showInterstitial();
    }
    if (shown || !context.mounted) return;

    // Fallback obbligatorio se AdMob non ha inventario: attesa minima prima di Continua.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _AdFallbackDialog(),
    );
  }

  /// Mostra sempre un passaggio pubblicitario prima di impostare un reminder.
  /// Usa AdMob se disponibile, altrimenti mostra un popup fallback così il tap
  /// non passa direttamente alla funzione per gli utenti Free.
  Future<void> showReminderSetupGate(BuildContext context) async {
    await showFeatureAdGate(context, 'reminders');
  }

  Future<void> recordSuccessfulImport() async {
    if (!_shouldUseAds) return;

    final userId = _currentUserId;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_successfulImportsKey(userId)) ?? 0;
    await prefs.setInt(_successfulImportsKey(userId), current + 1);
  }

  bool get _shouldUseAds =>
      !kIsWeb && _authService.currentUser?.effectiveRole == AppUserRole.free;

  Future<bool> _featureRequiresAd(String feature) async {
    if (!_shouldUseAds) return false;
    return PlanLimitsService.featureRequiresAd(feature);
  }

  String? get _currentUserId => _authService.currentUser?.id;

  String _successfulImportsKey(String userId) => 'ads_successful_imports_$userId';

  String _dailyOpenAdKey(String userId) => 'ads_daily_open_$userId';

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  String? get _interstitialAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return useTestAds
            ? _androidTestInterstitialAdUnitId
            : _androidInterstitialAdUnitId;
      case TargetPlatform.iOS:
        return useTestAds
            ? _iosTestInterstitialAdUnitId
            : _iosInterstitialAdUnitId;
      default:
        return null;
    }
  }

  Future<bool> _showInterstitial() async {
    if (!_shouldUseAds || _isShowingAd) return false;

    final adUnitId = _interstitialAdUnitId;
    if (adUnitId == null) return false;

    try {
      await initialize();
    } catch (e) {
      debugPrint('InterstitialAd skip: AdMob non inizializzato ($e)');
      return false;
    }

    final canRequest = await AdsConsentService.instance.canRequestAds();
    if (!canRequest) {
      debugPrint('InterstitialAd skip: UMP canRequestAds=false');
      return false;
    }

    final completer = Completer<bool>();
    _isShowingAd = true;

    if (kDebugMode) {
      debugPrint('InterstitialAd loading unit=$adUnitId');
    }

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isShowingAd = false;
              if (!completer.isCompleted) {
                completer.complete(true);
              }
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('InterstitialAd show error: $error');
              ad.dispose();
              _isShowingAd = false;
              if (!completer.isCompleted) {
                completer.complete(false);
              }
            },
          );

          ad.show();
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd load error: $error');
          _isShowingAd = false;
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
      ),
    );

    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _isShowingAd = false;
        return false;
      },
    );
  }
}

/// Dialog obbligatorio quando AdMob non consegna l'interstitial.
class _AdFallbackDialog extends StatefulWidget {
  const _AdFallbackDialog();

  @override
  State<_AdFallbackDialog> createState() => _AdFallbackDialogState();
}

class _AdFallbackDialogState extends State<_AdFallbackDialog> {
  static const int _waitSeconds = 4;
  int _remaining = _waitSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining <= 1) {
        timer.cancel();
        setState(() => _remaining = 0);
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _remaining <= 0;
    return AlertDialog(
      title: const Text('Annuncio'),
      content: Text(
        canContinue
            ? 'Grazie. Ora puoi continuare.'
            : 'La pubblicità non è disponibile in questo momento.\n'
                'Attendi $_remaining secondi prima di continuare.',
      ),
      actions: [
        ElevatedButton(
          onPressed:
              canContinue ? () => Navigator.of(context).pop() : null,
          child: Text(canContinue ? 'Continua' : 'Attendi ($_remaining)'),
        ),
      ],
    );
  }
}
