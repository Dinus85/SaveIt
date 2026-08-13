import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Raccolta consenso GDPR/UMP (Privacy & messaging AdMob) prima delle ads.
///
/// Form UMP all'avvio se richiesto. Stato sync su Firestore
/// (`users/{uid}.consents.admob`) per il filtro in dashboard.
class AdsConsentService {
  AdsConsentService._();

  static final AdsConsentService instance = AdsConsentService._();

  bool _gathering = false;
  bool _hasReset = false; // 🆕 Per evitare reset multipli nella stessa sessione
  Completer<bool>? _inFlight;

  /// Il form UMP resta aperto finché l'utente non conferma. Un timeout corto
  /// chiudeva l'attesa e riapriva il popup ads sopra il form, interrompendo
  /// il salvataggio di "Accetta tutto".
  static const Duration _formWait = Duration(minutes: 10);

  /// Aggiorna info e mostra il form solo se ancora richiesto da UMP.
  Future<bool> gatherConsent({bool forceEeaDebug = false}) async {
    if (kIsWeb) return false;

    // 🔥 NUOVO: Forza reset consenso se necessario per nuova versione build
    await resetConsentIfNeeded();

    if (_inFlight != null) return _inFlight!.future;

    _inFlight = Completer<bool>();
    _gathering = true;

    try {
      await _requestConsentInfoUpdate(forceEeaDebug: forceEeaDebug);
      await _showConsentFormIfRequired();
      await _refreshConsentAfterForm(forceEeaDebug: forceEeaDebug);

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

      final status = await ConsentInformation.instance.getConsentStatus();

      // loadConsentForm a ogni tap mostra un form "nuovo" con toggle di default
      // (alcuni sì, alcuni no) e può sovrascrivere Accetta tutto.
      // Prima volta: form consenso. Dopo: solo privacy options (scelte salvate).
      if (status == ConsentStatus.required || status == ConsentStatus.unknown) {
        await _showConsentFormIfRequired();
      } else {
        await showPrivacyOptionsForm();
      }

      await _refreshConsentAfterForm(forceEeaDebug: forceEeaDebug);
      final can = await canRequestAds();
      await syncAdmobConsentToFirestore();
      return can;
    } catch (e, st) {
      debugPrint('UMP openAdsConsentUi error: $e\n$st');
      return canRequestAds();
    }
  }

  Future<void> _showConsentFormIfRequired() async {
    final formDone = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
      if (error != null) {
        debugPrint(
          'UMP loadAndShowConsentFormIfRequired: ${error.errorCode} ${error.message}',
        );
      }
      if (!formDone.isCompleted) formDone.complete();
    });
    await formDone.future.timeout(_formWait, onTimeout: () {});
  }

  /// UMP scrive la stringa IAB in modo asincrono: rileggere subito
  /// `canRequestAds` può ancora dare false dopo Accetta tutto.
  Future<void> _refreshConsentAfterForm({bool forceEeaDebug = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _requestConsentInfoUpdate(forceEeaDebug: forceEeaDebug);
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
      _formWait,
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

  /// 🆕 Forza il reset del consenso UMP se è la prima volta che si avvia questa build.
  /// Serve per rinfrescare i consensi dopo cambiamenti alle policy AdMob.
  Future<void> resetConsentIfNeeded() async {
    if (kIsWeb || _hasReset) return;

    try {
      const int currentConsentVersion = 3; // Incrementare per forzare un nuovo reset
      final prefs = await SharedPreferences.getInstance();
      final lastResetVersion = prefs.getInt('last_consent_reset_version') ?? 0;

      if (lastResetVersion < currentConsentVersion) {
        debugPrint('UMP: Resetting consent state (v$lastResetVersion -> v$currentConsentVersion)');
        await ConsentInformation.instance.reset();
        await prefs.setInt('last_consent_reset_version', currentConsentVersion);
        _hasReset = true;
      }
    } catch (e) {
      debugPrint('UMP resetConsentIfNeeded error: $e');
    }
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
