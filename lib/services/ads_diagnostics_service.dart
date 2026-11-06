import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth_service.dart';

/// Traccia il percorso delle ads (init, consenso, richieste, errori AdMob)
/// in `users/{uid}/ad_diagnostics`, leggibile dalla dashboard/admin.
/// Le build store non hanno log visibili: senza questo non si capisce
/// dove si ferma la richiesta.
class AdsDiagnostics {
  AdsDiagnostics._();

  /// Tetto per sessione, per non riempire Firestore se un banner ritenta in loop.
  static const int _maxEventsPerSession = 80;

  static int _sent = 0;
  static String? _appVersion;

  static void log(String event, [Map<String, Object?> details = const {}]) {
    if (kIsWeb) return;
    if (kDebugMode) debugPrint('AdsDiag $event $details');
    if (_sent >= _maxEventsPerSession) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _sent++;
    _write(uid, event, details);
  }

  static Future<void> _write(
    String uid,
    String event,
    Map<String, Object?> details,
  ) async {
    try {
      _appVersion ??= await PackageInfo.fromPlatform()
          .then((info) => '${info.version}+${info.buildNumber}');
      final appUser = AuthService().currentUser;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ad_diagnostics')
          .add({
        'event': event,
        'details': details,
        'platform': defaultTargetPlatform.name,
        'appVersion': _appVersion,
        'appUserLoaded': appUser != null,
        'effectiveRole': appUser?.effectiveRole.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('AdsDiag write skip: $e');
    }
  }
}
