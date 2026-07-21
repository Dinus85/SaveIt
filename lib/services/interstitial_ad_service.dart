import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'access_control_service.dart';
import 'plan_limits_service.dart';

class InterstitialAdService {
  InterstitialAdService._internal();

  static final InterstitialAdService instance = InterstitialAdService._internal();

  static const String _androidInterstitialAdUnitId =
      'ca-app-pub-1397392558961350/5839880574';
  static const String _iosInterstitialAdUnitId =
      'ca-app-pub-1397392558961350/9950660131';

  static const String androidBannerAdUnitId =
      'ca-app-pub-1397392558961350/4746290759';
  static const String iosBannerAdUnitId =
      'ca-app-pub-1397392558961350/4315988838';

  final AuthService _authService = AuthService();

  bool _isInitialized = false;
  bool _isShowingAd = false;

  Future<void> initialize() async {
    if (_isInitialized || kIsWeb) return;
    await MobileAds.instance.initialize();
    _isInitialized = true;
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

    final shown = await _showInterstitial();
    if (shown || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuncio'),
        content: const Text(
          'Per usare questa funzione con un account Free devi prima visualizzare una pubblicità.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continua'),
          ),
        ],
      ),
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

    final usage = await PlanLimitsService.getUsage(forceRefresh: true);
    return usage[feature]?.requiresAd ?? false;
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
        return _androidInterstitialAdUnitId;
      case TargetPlatform.iOS:
        return _iosInterstitialAdUnitId;
      default:
        return null;
    }
  }

  Future<bool> _showInterstitial() async {
    if (!_shouldUseAds || _isShowingAd) return false;

    final adUnitId = _interstitialAdUnitId;
    if (adUnitId == null) return false;

    await initialize();

    final completer = Completer<bool>();
    _isShowingAd = true;

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
