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

  /// Registrato da `main.dart` per aprire Premium senza import circolari.
  static void Function(BuildContext context)? openPremiumPurchase;

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

  /// Ultimo motivo per cui l'interstitial non e' partita (diagnostica UI).
  String? lastFailureReason;

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
        // Consenso UMP all'avvio (form se richiesto), poi MobileAds.
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
  /// Restituisce true solo se l'ads e' stata vista (o non richiesta).
  Future<bool> showReminderOpenGate(BuildContext context) async {
    return showFeatureAdGate(context, 'reminders');
  }

  /// Richiede una interstitial prima di impostare un reminder per utenti Free.
  /// Per Premium/web restituisce true senza mostrare pubblicità.
  Future<bool> showReminderSetupAdIfRequired() async {
    if (!_shouldUseAds) return true;
    return _showInterstitial();
  }

  /// Mostra un passaggio pubblicitario prima di usare una funzione configurata
  /// con `requiresAd` nella dashboard limiti piani.
  ///
  /// Restituisce `true` solo se l'utente ha visto l'ads (o non e' richiesta).
  /// Se AdMob non consegna: dialog con Riprova / consenso / Annulla — **niente
  /// sblocco automatico**.
  Future<bool> showFeatureAdGate(BuildContext context, String feature) async {
    if (!await _featureRequiresAd(feature)) return true;
    if (!context.mounted) return false;

    while (context.mounted) {
      var shown = await _showInterstitial(
        context: context,
        requestConsentIfNeeded: false,
      );
      if (!shown) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!context.mounted) return false;
        shown = await _showInterstitial(
          context: context,
          requestConsentIfNeeded: false,
        );
      }
      // Fallback fill: se consenso ok ma no inventory personalizzato, riprova NPA.
      if (!shown &&
          (lastFailureReason == 'no_fill' || lastFailureReason == 'timeout')) {
        shown = await _showInterstitial(
          context: context,
          forceNonPersonalized: true,
          requestConsentIfNeeded: false,
        );
      }
      if (shown) return true;
      if (!context.mounted) return false;

      final action = await showDialog<_AdGateAction>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _AdRetryDialog(
          reason: lastFailureReason ?? 'unknown',
        ),
      );

      if (!context.mounted) return false;
      switch (action) {
        case _AdGateAction.retry:
          continue;
        case _AdGateAction.consent:
          // Form consenso direttamente qui (niente Account).
          await AdsConsentService.instance.openAdsConsentUi();
          continue;
        case _AdGateAction.premium:
          final openPremium = openPremiumPurchase;
          if (openPremium != null && context.mounted) {
            openPremium(context);
          }
          return false;
        case _AdGateAction.cancel:
        case null:
          return false;
      }
    }
    return false;
  }

  /// Mostra sempre un passaggio pubblicitario prima di impostare un reminder.
  Future<bool> showReminderSetupGate(BuildContext context) async {
    return showFeatureAdGate(context, 'reminders');
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

  Future<bool> _showInterstitial({
    BuildContext? context,
    bool forceNonPersonalized = false,
    bool requestConsentIfNeeded = true,
  }) async {
    if (!_shouldUseAds || _isShowingAd) {
      lastFailureReason = _isShowingAd ? 'busy' : 'not_free';
      return false;
    }

    final adUnitId = _interstitialAdUnitId;
    if (adUnitId == null) {
      lastFailureReason = 'unsupported_platform';
      return false;
    }

    try {
      await initialize();
    } catch (e) {
      debugPrint('InterstitialAd skip: AdMob non inizializzato ($e)');
      lastFailureReason = 'init_error';
      return false;
    }

    if (requestConsentIfNeeded) {
      // Di solito gia' raccolto in initialize(); qui solo se ancora richiesto.
      await AdsConsentService.instance.gatherConsent();
    }

    final canRequest = await AdsConsentService.instance.canRequestAds();
    if (!canRequest) {
      debugPrint('InterstitialAd skip: UMP canRequestAds=false');
      lastFailureReason = 'consent';
      return false;
    }

    final completer = Completer<bool>();
    _isShowingAd = true;
    final request = AdsConsentService.instance.buildAdRequest(
      forceNonPersonalized: forceNonPersonalized,
    );

    if (kDebugMode) {
      debugPrint(
        'InterstitialAd loading unit=$adUnitId npa=$forceNonPersonalized',
      );
    }

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          lastFailureReason = null;
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
              lastFailureReason = 'show_error';
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
          debugPrint(
            'InterstitialAd load error: code=${error.code} domain=${error.domain} message=${error.message}',
          );
          lastFailureReason = 'no_fill';
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
        lastFailureReason = 'timeout';
        _isShowingAd = false;
        return false;
      },
    );
  }
}

enum _AdGateAction { retry, consent, premium, cancel }

/// Dialog quando AdMob non consegna: Attiva ads / Riprova / Premium / Annulla.
class _AdRetryDialog extends StatelessWidget {
  const _AdRetryDialog({required this.reason});

  final String reason;

  String get _message {
    switch (reason) {
      case 'consent':
        return 'Questa funzione Free richiede una pubblicità.\n\n'
            'Tocca “Attiva pubblicità” per aprire qui il consenso '
            '(bastano anche le ads non personalizzate). '
            'Oppure passa a Premium per usarla senza ads.';
      case 'no_fill':
      case 'timeout':
      case 'show_error':
        return 'La pubblicità non è disponibile in questo momento.\n\n'
            'Tocca Riprova, oppure “Attiva pubblicità” per aggiornare il consenso. '
            'In alternativa passa a Premium.';
      case 'init_error':
        return 'Non è stato possibile avviare il sistema pubblicitario.\n\n'
            'Controlla la connessione e tocca Riprova.';
      default:
        return 'Questa funzione Free richiede una pubblicità.\n\n'
            'Tocca “Attiva pubblicità” o Riprova. Senza annuncio '
            'la funzione resta bloccata (oppure passa a Premium).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pubblicità richiesta'),
      content: SingleChildScrollView(child: Text(_message)),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_AdGateAction.cancel),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_AdGateAction.premium),
          child: const Text('Premium'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_AdGateAction.consent),
          child: const Text('Attiva pubblicità'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_AdGateAction.retry),
          child: const Text('Riprova'),
        ),
      ],
    );
  }
}
