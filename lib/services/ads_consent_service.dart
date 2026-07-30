import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Raccolta consenso GDPR/UMP (Privacy & messaging AdMob) prima delle ads.
class AdsConsentService {
  AdsConsentService._();

  static final AdsConsentService instance = AdsConsentService._();

  bool _gathering = false;
  Completer<bool>? _inFlight;

  /// Aggiorna info consenso, mostra form se richiesto, restituisce canRequestAds.
  Future<bool> gatherConsent({bool forceEeaDebug = false}) async {
    if (kIsWeb) return false;
    if (_inFlight != null) return _inFlight!.future;

    _inFlight = Completer<bool>();
    _gathering = true;

    try {
      final params = ConsentRequestParameters(
        consentDebugSettings: kDebugMode && forceEeaDebug
            ? ConsentDebugSettings(
                debugGeography: DebugGeography.debugGeographyEea,
              )
            : null,
      );

      final updateDone = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () {
          if (!updateDone.isCompleted) updateDone.complete();
        },
        (FormError error) {
          debugPrint(
            'UMP requestConsentInfoUpdate error: ${error.errorCode} ${error.message}',
          );
          if (!updateDone.isCompleted) updateDone.complete();
        },
      );
      await updateDone.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {},
      );

      final formDone = Completer<void>();
      ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
        if (error != null) {
          debugPrint(
            'UMP loadAndShowConsentFormIfRequired: ${error.errorCode} ${error.message}',
          );
        }
        if (!formDone.isCompleted) formDone.complete();
      });
      await formDone.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {},
      );

      final canRequest = await ConsentInformation.instance.canRequestAds();
      if (kDebugMode) {
        final status = await ConsentInformation.instance.getConsentStatus();
        debugPrint('UMP canRequestAds=$canRequest consentStatus=$status');
      }
      if (!_inFlight!.isCompleted) _inFlight!.complete(canRequest);
      return canRequest;
    } catch (e, st) {
      debugPrint('UMP gatherConsent error: $e\n$st');
      // In caso di errore, prova comunque: può esserci consenso di sessione precedente.
      try {
        final canRequest = await ConsentInformation.instance.canRequestAds();
        if (!_inFlight!.isCompleted) _inFlight!.complete(canRequest);
        return canRequest;
      } catch (_) {
        if (!_inFlight!.isCompleted) _inFlight!.complete(false);
        return false;
      }
    } finally {
      _gathering = false;
      _inFlight = null;
    }
  }

  Future<bool> canRequestAds() async {
    if (kIsWeb) return false;
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      return false;
    }
  }

  Future<bool> isPrivacyOptionsRequired() async {
    if (kIsWeb) return false;
    try {
      final status =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Riapre le opzioni privacy (revoca / modifica consenso).
  Future<FormError?> showPrivacyOptionsForm() async {
    if (kIsWeb) return null;
    final done = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (!done.isCompleted) done.complete(error);
    });
    return done.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => null,
    );
  }

  bool get isGathering => _gathering;
}
