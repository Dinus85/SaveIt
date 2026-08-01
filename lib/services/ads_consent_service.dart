import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'auth_service.dart';

/// Raccolta consenso GDPR/UMP (Privacy & messaging AdMob) prima delle ads.
///
/// Form UMP all'avvio se richiesto. Stato sync su Firestore
/// (`users/{uid}.consents.admob`) per il filtro in dashboard.
class AdsConsentService {
  AdsConsentService._();

  static final AdsConsentService instance = AdsConsentService._();

  bool _gathering = false;
  Completer<bool>? _inFlight;

  /// Aggiorna info e mostra il form solo se ancora richiesto da UMP.
  Future<bool> gatherConsent({bool forceEeaDebug = false}) async {
    if (kIsWeb) return false;
    if (_inFlight != null) return _inFlight!.future;

    _inFlight = Completer<bool>();
    _gathering = true;

    try {
      await _requestConsentInfoUpdate(forceEeaDebug: forceEeaDebug);

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
      await syncAdmobConsentToFirestore();
      if (!_inFlight!.isCompleted) _inFlight!.complete(canRequest);
      return canRequest;
    } catch (e, st) {
      debugPrint('UMP gatherConsent error: $e\n$st');
      try {
        final canRequest = await ConsentInformation.instance.canRequestAds();
        await syncAdmobConsentToFirestore();
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

  /// Apre il form consenso / opzioni privacy **nell'app** (senza andare in Account).
  Future<bool> openAdsConsentUi({bool forceEeaDebug = false}) async {
    if (kIsWeb) return false;

    try {
      await _requestConsentInfoUpdate(forceEeaDebug: forceEeaDebug);

      final formAvailable =
          await ConsentInformation.instance.isConsentFormAvailable();
      if (formAvailable) {
        final shown = Completer<void>();
        ConsentForm.loadConsentForm(
          (ConsentForm form) {
            form.show((FormError? error) {
              if (error != null) {
                debugPrint(
                  'UMP consent form show error: ${error.errorCode} ${error.message}',
                );
              }
              unawaited(form.dispose());
              if (!shown.isCompleted) shown.complete();
            });
          },
          (FormError error) {
            debugPrint(
              'UMP loadConsentForm error: ${error.errorCode} ${error.message}',
            );
            if (!shown.isCompleted) shown.complete();
          },
        );
        await shown.future.timeout(
          const Duration(seconds: 90),
          onTimeout: () {},
        );
      } else {
        final privacyStatus = await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus();
        if (privacyStatus == PrivacyOptionsRequirementStatus.required) {
          await showPrivacyOptionsForm();
        } else {
          final formDone = Completer<void>();
          ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
            if (!formDone.isCompleted) formDone.complete();
          });
          await formDone.future.timeout(
            const Duration(seconds: 60),
            onTimeout: () {},
          );
          await showPrivacyOptionsForm();
        }
      }

      final can = await canRequestAds();
      await syncAdmobConsentToFirestore();
      return can;
    } catch (e, st) {
      debugPrint('UMP openAdsConsentUi error: $e\n$st');
      return canRequestAds();
    }
  }

  Future<void> _requestConsentInfoUpdate({bool forceEeaDebug = false}) async {
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

  Future<FormError?> showPrivacyOptionsForm() async {
    if (kIsWeb) return null;
    final done = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (!done.isCompleted) done.complete(error);
    });
    final error = await done.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => null,
    );
    await syncAdmobConsentToFirestore();
    return error;
  }

  AdRequest buildAdRequest({bool forceNonPersonalized = false}) {
    if (forceNonPersonalized) {
      return const AdRequest(nonPersonalizedAds: true);
    }
    return const AdRequest();
  }

  /// Scrive `consents.admob` su Firestore per la dashboard admin.
  Future<void> syncAdmobConsentToFirestore() async {
    if (kIsWeb) return;
    try {
      final can = await ConsentInformation.instance.canRequestAds();
      final status = await ConsentInformation.instance.getConsentStatus();
      await AuthService().syncAdmobConsentToFirestore(
        canRequestAds: can,
        status: status.name,
      );
    } catch (e) {
      debugPrint('UMP syncAdmobConsentToFirestore skip: $e');
    }
  }

  bool get isGathering => _gathering;
}
