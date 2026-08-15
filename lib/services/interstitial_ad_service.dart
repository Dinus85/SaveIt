import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'access_control_service.dart';
import 'ads_consent_service.dart';
import 'ads_ids.dart';
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

  /// Se true (import da share in corso) non parte l'interstitial di sessione.
  static bool suppressSessionAds = false;

  /// Ultimo motivo per cui l'interstitial non e' partita (diagnostica UI).
  String? lastFailureReason;

  /// Solo in debug locale: unit di test Google. TestFlight e store: unit SaveIn.
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

  /// Prima apertura del giorno e/o interstitial dopo N ore di inattività.
  /// Nello stesso resume/avvio mostra al massimo un interstitial (priorità: giornaliero).
  Future<bool> showSessionAdsIfNeeded() async {
    if (suppressSessionAds) return false;
    if (!_shouldUseAds) return false;

    final userId = _currentUserId;
    if (userId == null) return false;

    final prefs = await SharedPreferences.getInstance();

    if (PlanLimitsService.dailyOpenInterstitialEnabled()) {
      final today = _todayKey();
      final lastShown = prefs.getString(_dailyOpenAdKey(userId));
      if (lastShown != today) {
        final shown = await _showInterstitial();
        if (shown) {
          await prefs.setString(_dailyOpenAdKey(userId), today);
        }
        return shown;
      }
    }

    final idleHours = PlanLimitsService.idleInterstitialHours();
    if (idleHours == null) return false;

    final lastMs = prefs.getInt(_lastSessionKey(userId));
    if (lastMs == null) return false;

    final idleFor = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastMs),
    );
    if (idleFor < Duration(hours: idleHours)) return false;

    return _showInterstitial();
  }

  Future<bool> showDailyOpenAdIfNeeded() async {
    return showSessionAdsIfNeeded();
  }

  /// Salva il momento in cui l'app va in background, per l'interstitial di inattività.
  Future<void> markSessionPaused() async {
    if (kIsWeb) return;
    final userId = _currentUserId;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastSessionKey(userId),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Ogni N aperture post (contatore persistente, anche tra giorni).
  /// Se l'ads non parte, il post si apre comunque.
  Future<void> showPostOpenAdIfRequired() async {
    if (!_shouldUseAds || _isShowingAd) return;

    final everyN = PlanLimitsService.postOpenInterstitialEveryN();
    if (everyN == null) return;

    final userId = _currentUserId;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _postOpensKey(userId);
    final count = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, count);
    if (count % everyN != 0) return;

    await _showInterstitial();
  }

  Future<void> markDailyOpenSatisfied() async {
    final userId = _currentUserId;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyOpenAdKey(userId), _todayKey());
  }

  static void beginImportFlow() {
    suppressSessionAds = true;
  }

  static void endImportFlow() {
    suppressSessionAds = false;
  }

  /// Ogni import Free richiede un'ads (rewarded, fallback interstitial).
  /// Non usa più il modulo ogni 5.
  Future<bool> showImportAdIfRequired([BuildContext? context]) async {
    if (!_shouldUseAds) return true;
    if (context == null || !context.mounted) {
      final shown = await _showRewardedOrInterstitial();
      if (shown) await markDailyOpenSatisfied();
      return shown;
    }
    final ok = await showFeatureAdGate(context, 'import_shared_post');
    if (ok) await markDailyOpenSatisfied();
    return ok;
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
  /// Se `requiresAd` è false: sblocca subito.
  /// Se l'ads vera viene consegnata: va vista, poi si sblocca.
  /// Reminder: se AdMob non ha inventario, la funzione resta usabile.
  /// Altre feature: dialog Riprova / consenso / Annulla.
  Future<bool> showFeatureAdGate(BuildContext context, String feature) async {
    if (!_shouldUseAds) return true;
    final isImport = feature == 'import_shared_post' ||
        feature == 'import_shared_folder';
    if (!isImport && !await _featureRequiresAd(feature)) return true;
    if (!context.mounted) return false;

    final allowWithoutRealAd = feature == 'reminders';
    final useRewarded = isImport ||
        feature == 'share_post' ||
        feature == 'share_folder';

    while (context.mounted) {
      var shown = useRewarded
          ? await _showRewardedOrInterstitial()
          : await _showInterstitial(
              context: context,
              requestConsentIfNeeded: false,
            );
      if (!shown) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!context.mounted) return false;
        shown = useRewarded
            ? await _showRewardedOrInterstitial()
            : await _showInterstitial(
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
      if (shown) {
        if (isImport) await markDailyOpenSatisfied();
        return true;
      }
      if (allowWithoutRealAd) return true;
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
          // Su iOS il form UMP non salva se parte mentre il dialog Flutter
          // sta ancora chiudendosi.
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (!context.mounted) return false;
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

  String _lastSessionKey(String userId) => 'ads_last_session_at_$userId';

  String _postOpensKey(String userId) => 'ads_post_opens_$userId';

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

  String? get _rewardedAdUnitId {
    return AdsIds.rewardedAdUnitId;
  }

  /// Rewarded se l'unità esiste; altrimenti interstitial. Sempre un'ads vera.
  Future<bool> _showRewardedOrInterstitial() async {
    final rewardedId = _rewardedAdUnitId;
    if (rewardedId != null) {
      final shown = await _showRewarded(rewardedId);
      if (shown) return true;
    }
    return _showInterstitial(requestConsentIfNeeded: false);
  }

  Future<bool> _showRewarded(String adUnitId) async {
    if (!_shouldUseAds || _isShowingAd) {
      lastFailureReason = _isShowingAd ? 'busy' : 'not_free';
      return false;
    }
    try {
      await initialize();
    } catch (_) {
      lastFailureReason = 'init_error';
      return false;
    }
    final canRequest = await AdsConsentService.instance.canRequestAds();
    if (!canRequest) {
      lastFailureReason = 'consent';
      return false;
    }

    final loadDone = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: adUnitId,
      request: AdsConsentService.instance.buildAdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!loadDone.isCompleted) loadDone.complete(ad);
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd load error: $error');
          lastFailureReason = 'no_fill';
          if (!loadDone.isCompleted) loadDone.complete(null);
        },
      ),
    );
    final ad = await loadDone.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        lastFailureReason = 'timeout';
        return null;
      },
    );
    if (ad == null) return false;

    final shown = Completer<bool>();
    var earned = false;
    _isShowingAd = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _isShowingAd = false;
        if (!shown.isCompleted) shown.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        lastFailureReason = 'show_error';
        ad.dispose();
        _isShowingAd = false;
        if (!shown.isCompleted) shown.complete(false);
      },
    );
    ad.show(
      onUserEarnedReward: (_, __) {
        earned = true;
      },
    );
    return shown.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _isShowingAd = false;
        lastFailureReason = 'timeout';
        return earned;
      },
    );
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
            'Tocca “Attiva pubblicità”. Nel form conviene “Consenti” '
            'sulla prima schermata. Se apri Gestisci, dopo Accetta tutto '
            'scorri in fondo e tocca Conferma, altrimenti le scelte non si salvano.\n\n'
            'Oppure passa a Premium per usarla senza ads.';
      case 'no_fill':
      case 'timeout':
      case 'show_error':
        return 'La pubblicità non è disponibile in questo momento '
            '(il consenso risulta già registrato).\n\n'
            'Tocca Riprova. In alternativa passa a Premium.';
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
