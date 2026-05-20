import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

enum AppUserRole { free, premium, admin }

extension AppUserRoleX on AppUserRole {
  String get value {
    switch (this) {
      case AppUserRole.free:
        return 'free';
      case AppUserRole.premium:
        return 'premium';
      case AppUserRole.admin:
        return 'admin';
    }
  }

  static AppUserRole fromValue(String? value) {
    switch ((value ?? '').toLowerCase().trim()) {
      case 'premium':
        return AppUserRole.premium;
      case 'admin':
        return AppUserRole.admin;
      case 'free':
      default:
        return AppUserRole.free;
    }
  }
}

enum DashboardAccessRole { none, author, editor, admin }

extension DashboardAccessRoleX on DashboardAccessRole {
  String get value {
    switch (this) {
      case DashboardAccessRole.none:
        return 'none';
      case DashboardAccessRole.author:
        return 'author';
      case DashboardAccessRole.editor:
        return 'editor';
      case DashboardAccessRole.admin:
        return 'admin';
    }
  }

  static DashboardAccessRole fromValue(String? value) {
    switch ((value ?? '').toLowerCase().trim()) {
      case 'autore':
      case 'author':
        return DashboardAccessRole.author;
      case 'editore':
      case 'editor':
        return DashboardAccessRole.editor;
      case 'admin':
        return DashboardAccessRole.admin;
      case 'none':
      default:
        return DashboardAccessRole.none;
    }
  }
}

// Modello utente locale
class User {
  final String id;
  final String name;
  final String email;
  final String? username;
  final AppUserRole role;
  final DashboardAccessRole dashboardRole;
  final bool isBlocked;
  final String? blockedReason;
  final DateTime? blockedAt;
  final bool acceptedTerms;
  final bool acceptedPrivacy;
  final bool acceptedMarketing;
  final DateTime createdAt;
  final DateTime? premiumUntil;
  final String? premiumSource;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.username,
    this.role = AppUserRole.free,
    this.dashboardRole = DashboardAccessRole.none,
    this.isBlocked = false,
    this.blockedReason,
    this.blockedAt,
    required this.acceptedTerms,
    required this.acceptedPrivacy,
    required this.acceptedMarketing,
    required this.createdAt,
    this.premiumUntil,
    this.premiumSource,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      username: json['username'],
      role: AppUserRoleX.fromValue(json['role'] as String?),
      dashboardRole:
          DashboardAccessRoleX.fromValue(json['dashboardRole'] as String?),
      isBlocked: json['isBlocked'] ?? false,
      blockedReason: json['blockedReason'],
      blockedAt: json['blockedAt'] != null
          ? DateTime.tryParse(json['blockedAt'])
          : null,
      acceptedTerms: json['acceptedTerms'] ?? false,
      acceptedPrivacy: json['acceptedPrivacy'] ?? false,
      acceptedMarketing: json['acceptedMarketing'] ?? false,
      createdAt:
          DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      premiumUntil: json['premiumUntil'] != null
          ? DateTime.tryParse(json['premiumUntil'])
          : null,
      premiumSource: json['premiumSource'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'username': username,
      'role': role.value,
      'dashboardRole': dashboardRole.value,
      'isBlocked': isBlocked,
      'blockedReason': blockedReason,
      'blockedAt': blockedAt?.toIso8601String(),
      'acceptedTerms': acceptedTerms,
      'acceptedPrivacy': acceptedPrivacy,
      'acceptedMarketing': acceptedMarketing,
      'createdAt': createdAt.toIso8601String(),
      'premiumUntil': premiumUntil?.toIso8601String(),
      'premiumSource': premiumSource,
    };
  }

  User copyWith({
    String? name,
    String? email,
    String? username,
    AppUserRole? role,
    DashboardAccessRole? dashboardRole,
    bool? isBlocked,
    String? blockedReason,
    DateTime? blockedAt,
    bool? acceptedTerms,
    bool? acceptedPrivacy,
    bool? acceptedMarketing,
    DateTime? premiumUntil,
    String? premiumSource,
  }) {
    return User(
      id: this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      username: username ?? this.username,
      role: role ?? this.role,
      dashboardRole: dashboardRole ?? this.dashboardRole,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedReason: blockedReason ?? this.blockedReason,
      blockedAt: blockedAt ?? this.blockedAt,
      acceptedTerms: acceptedTerms ?? this.acceptedTerms,
      acceptedPrivacy: acceptedPrivacy ?? this.acceptedPrivacy,
      acceptedMarketing: acceptedMarketing ?? this.acceptedMarketing,
      createdAt: this.createdAt,
      premiumUntil: premiumUntil ?? this.premiumUntil,
      premiumSource: premiumSource ?? this.premiumSource,
    );
  }

  bool get hasActiveTimedPremium =>
      premiumUntil != null && premiumUntil!.isAfter(DateTime.now());
  AppUserRole get effectiveRole {
    if (role == AppUserRole.admin) return AppUserRole.admin;
    if (role == AppUserRole.premium) {
      if (premiumUntil == null || hasActiveTimedPremium) {
        return AppUserRole.premium;
      }
    }
    return AppUserRole.free;
  }

  bool get isFree => effectiveRole == AppUserRole.free;
  bool get isPremium => effectiveRole == AppUserRole.premium;
  bool get isAdmin => role == AppUserRole.admin;
  DashboardAccessRole get effectiveDashboardRole =>
      isAdmin ? DashboardAccessRole.admin : dashboardRole;
  bool get canAccessDashboard =>
      effectiveDashboardRole != DashboardAccessRole.none;
  bool get canManageDashboardAccess =>
      effectiveDashboardRole == DashboardAccessRole.admin;
  bool get canManageUserRoles =>
      effectiveDashboardRole == DashboardAccessRole.admin;
  bool get canBlockUsers =>
      effectiveDashboardRole == DashboardAccessRole.admin ||
      effectiveDashboardRole == DashboardAccessRole.editor;
}

class AuthResult {
  final bool success;
  final User? user;
  final String? message;

  AuthResult({
    required this.success,
    this.user,
    this.message,
  });
}

class CrossPromotionResult {
  final String status;
  final DateTime premiumUntil;
  final DateTime claimBy;
  final int durationDays;
  final int claimWindowDays;
  final String targetApp;

  CrossPromotionResult({
    required this.status,
    required this.premiumUntil,
    required this.claimBy,
    required this.durationDays,
    required this.claimWindowDays,
    required this.targetApp,
  });

  factory CrossPromotionResult.fromMap(Map<String, dynamic> data) {
    return CrossPromotionResult(
      status: data['status']?.toString() ?? 'pending',
      premiumUntil: DateTime.parse(data['premiumUntil'].toString()).toLocal(),
      claimBy: DateTime.parse(data['claimBy'].toString()).toLocal(),
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 30,
      claimWindowDays: (data['claimWindowDays'] as num?)?.toInt() ?? 14,
      targetApp: data['targetApp']?.toString() ?? 'smartchef',
    );
  }
}

class PromotionBanner {
  final String id;
  final String type;
  final String title;
  final String message;
  final String ctaLabel;
  final String secondaryCtaLabel;
  final String action;
  final String actionUrl;
  final String targetApp;

  const PromotionBanner({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.ctaLabel,
    required this.secondaryCtaLabel,
    required this.action,
    required this.actionUrl,
    required this.targetApp,
  });

  bool get isCrossPromo => type == 'cross_promo';

  factory PromotionBanner.fromMap(Map<String, dynamic> data) {
    return PromotionBanner(
      id: data['id']?.toString() ?? '',
      type: data['type']?.toString() ?? 'generic_promo',
      title: data['title']?.toString() ?? '',
      message: data['message']?.toString() ?? '',
      ctaLabel: data['ctaLabel']?.toString() ?? 'Scopri',
      secondaryCtaLabel: data['secondaryCtaLabel']?.toString() ?? '',
      action: data['action']?.toString() ?? 'open_url',
      actionUrl: data['actionUrl']?.toString() ?? '',
      targetApp: data['targetApp']?.toString() ?? '',
    );
  }
}

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Firebase instances
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // ✅ AGGIUNTO

  // Stato interno
  User? _currentUser;
  bool _isInitialized = false;
  StreamSubscription<firebase_auth.User?>? _authSubscription;
  Completer<void>? _initializationCompleter;
  Completer<void>? _consentLoadingCompleter;
  CrossPromotionResult? _pendingCrossPromotionNotification;
  final Set<String> _trackedPromotionEvents = <String>{};
  DateTime? _lastConsentSyncAt;
  String? _lastConsentSyncUserId;
  bool _isProcessingAuthStateChange = false;
  static const Duration _consentSyncCooldown = Duration(seconds: 10);

  // Getters pubblici
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isInitialized => _isInitialized;
  CrossPromotionResult? consumeCrossPromotionNotification() {
    final result = _pendingCrossPromotionNotification;
    _pendingCrossPromotionNotification = null;
    return result;
  }

  String _normalizeEmail(String email) => email.toLowerCase().trim();

  DateTime? _dateFromFirestoreValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<User?> reloadCurrentUserFromFirestore() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    _currentUser ??= User(
      id: firebaseUser.uid,
      name: firebaseUser.displayName ?? 'Utente',
      email: firebaseUser.email ?? '',
      username:
          '@${(firebaseUser.displayName ?? 'utente').toLowerCase().replaceAll(' ', '.')}',
      role: AppUserRole.free,
      isBlocked: false,
      acceptedTerms: true,
      acceptedPrivacy: true,
      acceptedMarketing: false,
      createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
    );

    await _loadMarketingConsentFromFirestore(forceRefresh: true);
    return _currentUser;
  }

  Stream<User?> get userStream {
    return _firebaseAuth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser != null) {
        if (_currentUser?.id != firebaseUser.uid ||
            _currentUser?.email != firebaseUser.email) {
          await _loadUserData(firebaseUser);
        }
        return _currentUser;
      } else {
        _currentUser = null;
        notifyListeners();
        return null;
      }
    });
  }

  Future<void> initialize() async {
    if (_initializationCompleter != null) {
      return _initializationCompleter!.future;
    }

    if (_isInitialized) {
      return;
    }

    _initializationCompleter = Completer<void>();

    try {
      if (kDebugMode)
        print('DEBUG: 🔥 Inizializzazione AuthService REATTIVO...');

      // Sottoscrizione allo stream Firebase Auth
      _authSubscription = _firebaseAuth.authStateChanges().listen(
        _onFirebaseAuthStateChanged,
        onError: (error) {
          if (kDebugMode) print('ERRORE: Firebase Auth Stream: $error');
        },
      );

      // Caricamento iniziale utente
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser != null) {
        if (kDebugMode)
          print(
              'DEBUG: Utente Firebase attivo all\'avvio: ${firebaseUser.email}');

        // Blocchiamo temporaneamente il listener per evitare doppie chiamate durante l'init
        _isProcessingAuthStateChange = true;
        try {
          await _loadUserData(firebaseUser);
        } finally {
          _isProcessingAuthStateChange = false;
        }
      } else {
        if (kDebugMode)
          print('DEBUG: Nessun utente Firebase autenticato all\'avvio');
        _currentUser = null;
      }

      _isInitialized = true;
      notifyListeners();

      if (kDebugMode)
        print('DEBUG: ✔ AuthService inizializzato. Loggato: $isLoggedIn');
    } catch (e) {
      if (kDebugMode) print('ERRORE: Inizializzazione AuthService: $e');
      _isInitialized = true;
      notifyListeners();
    } finally {
      _initializationCompleter?.complete();
      _initializationCompleter = null;
    }
  }

  void _onFirebaseAuthStateChanged(firebase_auth.User? firebaseUser) async {
    if (_isProcessingAuthStateChange) {
      if (kDebugMode) print('DEBUG: ⏳ Salto cambio stato auth (già in corso)');
      return;
    }

    _isProcessingAuthStateChange = true;

    try {
      if (kDebugMode) {
        print(
            'DEBUG: 🔥 Firebase Auth State Changed: ${firebaseUser?.email ?? "NULL"}');
      }

      if (firebaseUser != null) {
        // Evita ricaricamento se l'utente è lo stesso e abbiamo già i dati
        if (_currentUser?.id == firebaseUser.uid &&
            _currentUser?.email == firebaseUser.email) {
          if (kDebugMode)
            print(
                'DEBUG: ℹ️ Utente già caricato, salto ricaricamento ridondante');
        } else {
          await _loadUserData(firebaseUser);
        }
      } else {
        if (_currentUser != null) {
          _currentUser = null;
          await _clearLocalData();
          notifyListeners();
        }
      }

      if (kDebugMode) {
        print(
            'DEBUG: Stato finale - Loggato: $isLoggedIn, User: ${_currentUser?.email}');
      }
    } finally {
      _isProcessingAuthStateChange = false;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<AuthResult> loginUser({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      if (kDebugMode) print('DEBUG: 🔥 Login Firebase Auth - Email: $email');

      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        if (rememberMe) {
          await _saveRememberedEmail(email);
        }

        if (kDebugMode) {
          print(
              'DEBUG: ✔ Login Firebase completato - Il listener aggiornerà lo stato');
        }
        await _waitForUserSync(email);

        if (_currentUser?.isBlocked == true) {
          final blockedReason = _currentUser?.blockedReason;
          await logout();
          return AuthResult(
            success: false,
            message: blockedReason?.isNotEmpty == true
                ? 'Account bloccato: $blockedReason'
                : 'Account bloccato. Contatta l\'amministratore.',
          );
        }

        return AuthResult(success: true, user: _currentUser);
      }

      return AuthResult(
        success: false,
        message: 'Errore durante il login',
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      String message = _getFirebaseErrorMessage(e);
      if (kDebugMode) print('ERRORE Firebase Auth Login: ${e.code} - $message');
      return AuthResult(success: false, message: message);
    } catch (e) {
      if (kDebugMode) print('ERRORE generale login: $e');
      return AuthResult(
        success: false,
        message: 'Errore di connessione. Verifica la tua connessione internet.',
      );
    }
  }

  Future<AuthResult> loginWithGoogle() async {
    try {
      if (kDebugMode) print('DEBUG: 🔥 Google Sign-In...');

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        if (kDebugMode) print('DEBUG: Google Sign-In annullato');
        return AuthResult(success: false, message: 'Login annullato');
      }

      if (kDebugMode) print('DEBUG: Google User: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      if (userCredential.user != null) {
        if (kDebugMode) {
          print(
              'DEBUG: ✔ Google Sign-In Firebase completato - Aspettando sincronizzazione...');
        }
        await _waitForUserSync(userCredential.user!.email!);

        if (_currentUser?.isBlocked == true) {
          final blockedReason = _currentUser?.blockedReason;
          await logout();
          return AuthResult(
            success: false,
            message: blockedReason?.isNotEmpty == true
                ? 'Account bloccato: $blockedReason'
                : 'Account bloccato. Contatta l\'amministratore.',
          );
        }

        return AuthResult(success: true, user: _currentUser);
      }

      return AuthResult(success: false, message: 'Errore Google Sign-In');
    } catch (e) {
      if (kDebugMode) print('ERRORE Google Sign-In: $e');
      return AuthResult(
        success: false,
        message:
            'Errore durante l\'autenticazione con Google. Verifica la connessione.',
      );
    }
  }

  Future<AuthResult> registerUser({
    required String name,
    required String email,
    required String password,
    required bool acceptedTerms,
    required bool acceptedPrivacy,
    required bool acceptedMarketing,
  }) async {
    try {
      if (kDebugMode) print('DEBUG: 🔥 Registrazione nuovo utente: $email');

      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        await credential.user!.updateDisplayName(name);

        final user = User(
          id: credential.user!.uid,
          name: name,
          email: email,
          username: '@${name.toLowerCase().replaceAll(' ', '.')}',
          role: AppUserRole.free,
          acceptedTerms: acceptedTerms,
          acceptedPrivacy: acceptedPrivacy,
          acceptedMarketing: acceptedMarketing,
          createdAt: DateTime.now(),
        );

        await _saveUserLocally(user);

        // ✅ NUOVO: Salva su Firestore alla registrazione
        await _saveUserToFirestore(user);

        if (kDebugMode) {
          print(
              'DEBUG: ✔ Registrazione completata - Aspettando sincronizzazione...');
        }
        await _waitForUserSync(email);

        return AuthResult(success: true, user: _currentUser);
      }

      return AuthResult(
          success: false, message: 'Errore durante la registrazione');
    } on firebase_auth.FirebaseAuthException catch (e) {
      String message = _getFirebaseErrorMessage(e);
      if (kDebugMode)
        print('ERRORE Firebase Auth Registration: ${e.code} - $message');
      return AuthResult(success: false, message: message);
    } catch (e) {
      if (kDebugMode) print('ERRORE registrazione: $e');
      return AuthResult(
        success: false,
        message: 'Errore durante la registrazione. Verifica la connessione.',
      );
    }
  }

  Future<void> _waitForUserSync(String expectedEmail) async {
    if (kDebugMode)
      print('DEBUG: 🔄 Aspettando sincronizzazione utente: $expectedEmail');

    int attempts = 0;
    const maxAttempts = 50;

    while (attempts < maxAttempts) {
      if (_currentUser != null && _currentUser!.email == expectedEmail) {
        if (kDebugMode) {
          print(
              'DEBUG: ✔ Sincronizzazione completata per: ${_currentUser!.email}');
        }
        notifyListeners();
        if (kDebugMode) {
          print(
              'DEBUG: 🔔 AuthWrapper notificato della sincronizzazione completata');
        }
        return;
      }

      await Future.delayed(Duration(milliseconds: 100));
      attempts++;

      if (attempts % 10 == 0) {
        if (kDebugMode) {
          print(
              'DEBUG: 🔄 Ancora in attesa... tentativi: $attempts/$maxAttempts');
        }
      }
    }

    if (kDebugMode) {
      print(
          'ERRORE: Timeout sincronizzazione utente dopo ${maxAttempts * 100}ms');
    }

    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null && firebaseUser.email == expectedEmail) {
      if (kDebugMode) {
        print(
            'DEBUG: 🔧 Tentativo recupero: Firebase ha l\'utente, forzo il caricamento...');
      }
      await _loadUserData(firebaseUser);
      notifyListeners();
      if (kDebugMode)
        print('DEBUG: 🔔 AuthWrapper notificato del recovery completato');
    }
  }

  Future<void> logout() async {
    try {
      if (kDebugMode) print('DEBUG: 🔥 Logout utente: ${_currentUser?.name}');

      await _firebaseAuth.signOut();

      try {
        await _googleSignIn.signOut();
        if (kDebugMode) print('DEBUG: Google Sign-In disconnesso');
      } catch (e) {
        if (kDebugMode) print('WARNING: Errore disconnessione Google: $e');
      }

      if (kDebugMode)
        print('DEBUG: ✔ Logout completato - Il listener pulirà lo stato');
    } catch (e) {
      if (kDebugMode) print('ERRORE durante il logout: $e');
    }
  }

  Future<AuthResult> deleteAccount() async {
    if (_currentUser == null || _firebaseAuth.currentUser == null) {
      return AuthResult(
        success: false,
        message: 'Nessun utente autenticato da eliminare',
      );
    }

    try {
      final userEmail = _currentUser!.email;
      final userId = _currentUser!.id;
      if (kDebugMode) print('DEBUG: 🔥 Eliminazione account: $userEmail');

      try {
        await _googleSignIn.signOut();
      } catch (e) {
        if (kDebugMode) print('WARNING: Errore disconnessione Google: $e');
      }

      // ✅ NUOVO: Elimina documento Firestore
      try {
        await _firestore.collection('users').doc(userId).delete();
        if (kDebugMode) print('DEBUG: ✅ Documento Firestore eliminato');
      } catch (e) {
        if (kDebugMode) print('WARNING: Errore eliminazione Firestore: $e');
      }

      await _firebaseAuth.currentUser!.delete();
      if (kDebugMode) print('DEBUG: Account Firebase eliminato');

      if (kDebugMode)
        print('DEBUG: ✔ Eliminazione completata - Il listener pulirà lo stato');

      return AuthResult(
        success: true,
        message: 'Account eliminato con successo',
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      String message = _getFirebaseErrorMessage(e);
      if (kDebugMode)
        print('ERRORE Firebase Auth Delete: ${e.code} - $message');
      return AuthResult(success: false, message: message);
    } catch (e) {
      if (kDebugMode) print('ERRORE eliminazione account: $e');
      return AuthResult(
        success: false,
        message: 'Errore durante l\'eliminazione dell\'account',
      );
    }
  }

  // ========================================
  // ✅ METODI MARKETING CONSENT CON FIRESTORE
  // ========================================

  /// Aggiorna il consenso marketing dell'utente (LOCAL + CLOUD)
  Future<bool> updateMarketingConsent(bool consent) async {
    if (_currentUser == null) {
      print(
          'ERRORE: Nessun utente autenticato per aggiornare consenso marketing');
      return false;
    }

    try {
      print(
          'DEBUG: Aggiornando consenso marketing: $consent per utente ${_currentUser!.email}');

      // STEP 1: Aggiorna User model locale
      _currentUser = _currentUser!.copyWith(
        acceptedMarketing: consent,
      );

      // STEP 2: Salva in SharedPreferences (cache locale - offline-first)
      await _saveUserLocally(_currentUser!);

      // STEP 3: ✅ Salva su Firestore (cloud sync)
      await _updateMarketingConsentFirestore(consent);

      // STEP 4: Notifica listeners per aggiornare UI
      notifyListeners();

      print('DEBUG: ✅ Consenso marketing salvato localmente e su cloud');
      return true;
    } catch (e) {
      print('ERRORE: Salvataggio consenso marketing fallito: $e');
      return false;
    }
  }

  /// Legge il consenso marketing corrente dell'utente
  bool getMarketingConsent() {
    if (_currentUser == null) {
      print('DEBUG: Nessun utente, consenso marketing = false (default)');
      return false;
    }

    final consent = _currentUser!.acceptedMarketing;
    print('DEBUG: Consenso marketing corrente: $consent');
    return consent;
  }

  // ========================================
  // ✅ METODI PRIVATI FIRESTORE
  // ========================================

  /// Salva l'utente completo su Firestore (registrazione)
  Future<void> _saveUserToFirestore(User user) async {
    try {
      print('DEBUG: 🌐 Salvando utente su Firestore...');

      final now = FieldValue.serverTimestamp();

      await _firestore.collection('users').doc(user.id).set({
        'userId': user.id,
        'email': user.email,
        'normalizedEmail': user.email.toLowerCase().trim(),
        'name': user.name,
        'username': user.username,
        'role': user.role.value,
        'dashboardRole': user.dashboardRole.value,
        'isBlocked': user.isBlocked,
        'blockedReason': user.blockedReason,
        'blockedAt':
            user.blockedAt != null ? Timestamp.fromDate(user.blockedAt!) : null,
        'roleUpdatedAt': now,
        'roleUpdatedBy': 'system',
        'createdAt': now,
        'lastLogin': now,
        'consents': {
          'marketing': {
            'accepted': user.acceptedMarketing,
            'consentDate': now,
            'lastModified': now,
            'modifiedBy': 'user',
            'version': '1.0',
          },
          'privacy': {
            'accepted': user.acceptedPrivacy,
            'consentDate': now,
            'version': '1.0',
          },
          'terms': {
            'accepted': user.acceptedTerms,
            'consentDate': now,
            'version': '1.0',
          },
        },
      });

      print('DEBUG: ✅ Utente salvato su Firestore');
    } catch (e) {
      print('ERRORE: Salvataggio utente su Firestore: $e');
      // Non bloccare la registrazione se Firestore fallisce
    }
  }

  /// Aggiorna solo il consenso marketing su Firestore
  Future<void> _updateMarketingConsentFirestore(bool consent) async {
    if (_firebaseAuth.currentUser == null) {
      throw Exception('Utente non autenticato per sync Firestore');
    }

    final userId = _firebaseAuth.currentUser!.uid;
    final now = FieldValue.serverTimestamp();

    try {
      if (kDebugMode) {
        print('DEBUG: 🌐 Sincronizzando consenso marketing su Firestore...');
      }

      await _firestore.collection('users').doc(userId).set({
        'userId': userId,
        'email': _currentUser!.email,
        'normalizedEmail': _currentUser!.email.toLowerCase().trim(),
        'name': _currentUser!.name,
        'username': _currentUser!.username,
        'role': _currentUser!.role.value,
        'dashboardRole': _currentUser!.dashboardRole.value,
        'isBlocked': _currentUser!.isBlocked,
        'blockedReason': _currentUser!.blockedReason,
        'blockedAt': _currentUser!.blockedAt != null
            ? Timestamp.fromDate(_currentUser!.blockedAt!)
            : null,
        'consents': {
          'marketing': {
            'accepted': consent,
            'lastModified': now,
            'modifiedBy': 'user',
            'version': '1.0',
          }
        },
        'lastLogin': now,
      }, SetOptions(merge: true)); // ✅ merge = non sovrascrive altri campi

      _lastConsentSyncUserId = userId;
      _lastConsentSyncAt = DateTime.now();

      if (kDebugMode) {
        print('DEBUG: ✅ Consenso marketing sincronizzato su Firestore');
      }
    } catch (e) {
      if (kDebugMode) print('ERRORE: Sincronizzazione Firestore fallita: $e');
      // Non rilanciare - il salvataggio locale è già avvenuto
    }
  }

  /// Carica i consensi da Firestore (all'avvio/login)
  Future<void> _loadMarketingConsentFromFirestore({
    bool forceRefresh = false,
  }) async {
    if (_firebaseAuth.currentUser == null) return;

    if (_consentLoadingCompleter != null) {
      if (kDebugMode) {
        print('DEBUG: ⏳ Caricamento consenso già in corso, attendo...');
      }
      return _consentLoadingCompleter!.future;
    }

    final userId = _firebaseAuth.currentUser!.uid;
    final lastSync = _lastConsentSyncAt;
    if (!forceRefresh &&
        _lastConsentSyncUserId == userId &&
        lastSync != null &&
        DateTime.now().difference(lastSync) < _consentSyncCooldown) {
      if (kDebugMode) {
        print('DEBUG: ✅ Consenso marketing già verificato di recente');
      }
      return;
    }

    _consentLoadingCompleter = Completer<void>();

    try {
      if (kDebugMode) {
        print('DEBUG: 🌐 Caricando consenso marketing da Firestore...');
      }

      final doc = await _firestore.collection('users').doc(userId).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        final marketingConsent =
            data['consents']?['marketing']?['accepted'] ?? false;
        final role = AppUserRoleX.fromValue(data['role'] as String?);
        final premiumUntil = _dateFromFirestoreValue(data['premiumUntil']);
        final premiumSource = data['premiumSource'] as String?;
        final userDashboardRole =
            DashboardAccessRoleX.fromValue(data['dashboardRole'] as String?);

        // 🔥 Ottimizzazione: non chiamare _loadDashboardAccessRoleForEmail se non necessario
        DashboardAccessRole dashboardRole = userDashboardRole;
        if (userDashboardRole == DashboardAccessRole.none) {
          final dashboardAccessRole = await _loadDashboardAccessRoleForEmail(
            (data['email'] as String?) ?? _currentUser?.email ?? '',
          );
          dashboardRole = dashboardAccessRole;
        }

        final isBlocked = data['isBlocked'] ?? false;
        final blockedReason = data['blockedReason'] as String?;
        final blockedAtValue = data['blockedAt'];
        final blockedAt = blockedAtValue is Timestamp
            ? blockedAtValue.toDate()
            : (blockedAtValue is String
                ? DateTime.tryParse(blockedAtValue)
                : null);

        if (kDebugMode) {
          print('DEBUG: Consenso da Firestore: $marketingConsent');
          print('DEBUG: Consenso locale: ${_currentUser?.acceptedMarketing}');
        }

        // Firestore è la fonte di verità
        if (_currentUser != null &&
            (_currentUser!.acceptedMarketing != marketingConsent ||
                _currentUser!.role != role ||
                _currentUser!.dashboardRole != dashboardRole ||
                _currentUser!.isBlocked != isBlocked ||
                _currentUser!.blockedReason != blockedReason ||
                _currentUser!.premiumUntil != premiumUntil ||
                _currentUser!.premiumSource != premiumSource)) {
          if (kDebugMode)
            print('DEBUG: ⚠️ Consenso diverso, sincronizzando da cloud...');

          _currentUser = _currentUser!.copyWith(
            acceptedMarketing: marketingConsent,
            role: role,
            dashboardRole: dashboardRole,
            isBlocked: isBlocked,
            blockedReason: blockedReason,
            blockedAt: blockedAt,
            premiumUntil: premiumUntil,
            premiumSource: premiumSource,
          );

          await _saveUserLocally(_currentUser!);
          notifyListeners();

          if (kDebugMode)
            print('DEBUG: ✅ Consenso sincronizzato da cloud a locale');
        } else {
          if (kDebugMode) print('DEBUG: ✅ Consensi già sincronizzati');
        }
      } else {
        if (kDebugMode)
          print('DEBUG: ℹ️ Nessun documento Firestore, creando...');
        if (_currentUser != null) {
          await _saveUserToFirestore(_currentUser!);
          await _syncDashboardAccessRoleFromFirestore();
        }
      }
      _lastConsentSyncUserId = userId;
      _lastConsentSyncAt = DateTime.now();
    } catch (e) {
      if (kDebugMode) print('DEBUG: ⚠️ Errore caricamento da Firestore: $e');
      // Continua con valore locale
    } finally {
      _consentLoadingCompleter?.complete();
      _consentLoadingCompleter = null;
    }
  }

  Future<DashboardAccessRole> _loadDashboardAccessRoleForEmail(
    String email,
  ) async {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty) return DashboardAccessRole.none;

    try {
      final doc = await _firestore
          .collection('dashboard_accesses')
          .doc(normalizedEmail)
          .get();
      if (!doc.exists) return DashboardAccessRole.none;
      final data = doc.data() ?? <String, dynamic>{};
      return DashboardAccessRoleX.fromValue(data['dashboardRole'] as String?);
    } catch (e) {
      print('DEBUG: ⚠️ Errore caricamento accesso dashboard separato: $e');
      return DashboardAccessRole.none;
    }
  }

  Future<void> _syncDashboardAccessRoleFromFirestore() async {
    if (_currentUser == null) return;
    final dashboardRole =
        await _loadDashboardAccessRoleForEmail(_currentUser!.email);
    if (dashboardRole == DashboardAccessRole.none ||
        _currentUser!.dashboardRole == dashboardRole) {
      return;
    }

    _currentUser = _currentUser!.copyWith(dashboardRole: dashboardRole);
    await _saveUserLocally(_currentUser!);
    notifyListeners();
  }

  // ========================================
  // METODI PRIVATI
  // ========================================

  Future<void> _loadUserData(firebase_auth.User firebaseUser) async {
    try {
      print('DEBUG: 🔧 Caricamento dati utente: ${firebaseUser.email}');

      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_${firebaseUser.uid}');

      if (userData != null) {
        _currentUser = User.fromJson(jsonDecode(userData));
        print('DEBUG: ✅ Dati utente caricati da storage locale');
      } else {
        _currentUser = User(
          id: firebaseUser.uid,
          name: firebaseUser.displayName ?? 'Utente',
          email: firebaseUser.email ?? '',
          username:
              '@${(firebaseUser.displayName ?? 'utente').toLowerCase().replaceAll(' ', '.')}',
          role: AppUserRole.free,
          isBlocked: false,
          acceptedTerms: true,
          acceptedPrivacy: true,
          acceptedMarketing: false,
          createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
        );

        await _saveUserLocally(_currentUser!);
        print('DEBUG: ✅ Nuovo profilo locale creato');
      }

      // Sincronizza da Firestore per aggiornare ruolo, blocco, consenso marketing.
      // Essenziale per utenti il cui ruolo è stato cambiato dall'admin dashboard.
      await _loadMarketingConsentFromFirestore();
      await _claimPendingSmartChefLaunchPromoIfAvailable();
    } catch (e) {
      print('ERRORE caricamento dati utente: $e');
      _currentUser = User(
        id: firebaseUser.uid,
        name: firebaseUser.displayName ?? 'Utente',
        email: firebaseUser.email ?? '',
        username: null,
        role: AppUserRole.free,
        isBlocked: false,
        acceptedTerms: true,
        acceptedPrivacy: true,
        acceptedMarketing: false,
        createdAt: DateTime.now(),
      );
    }
  }

  Future<void> _saveUserLocally(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_${user.id}', jsonEncode(user.toJson()));
      print('DEBUG: 💾 Dati utente salvati localmente');
    } catch (e) {
      print('ERRORE salvataggio locale: $e');
    }
  }

  Future<void> _clearLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) =>
              key.startsWith('user_') ||
              key == 'last_user_id' ||
              key == 'is_logged_in')
          .toList();

      for (String key in keys) {
        await prefs.remove(key);
      }

      print('DEBUG: 🗑️ Dati utente locali puliti');
    } catch (e) {
      print('ERRORE pulizia dati: $e');
    }
  }

  Future<bool> updateOwnRole(AppUserRole role) async {
    if (_currentUser == null) return false;
    if (role == AppUserRole.admin) {
      throw Exception('Il ruolo admin può essere assegnato solo da un admin.');
    }
    if (_currentUser!.isAdmin) {
      throw Exception(
          'Gli admin non possono modificare il proprio piano da questa schermata.');
    }

    try {
      _currentUser = _currentUser!.copyWith(role: role);
      await _saveUserLocally(_currentUser!);

      await _firestore.collection('users').doc(_currentUser!.id).set({
        'role': role.value,
        'roleUpdatedAt': FieldValue.serverTimestamp(),
        'roleUpdatedBy': _currentUser!.id,
        'email': _currentUser!.email,
        'normalizedEmail': _currentUser!.email.toLowerCase().trim(),
        'name': _currentUser!.name,
        'username': _currentUser!.username,
      }, SetOptions(merge: true));

      await _writeAdminLog(
        action: 'self_role_changed',
        targetUserId: _currentUser!.id,
        details: {
          'newRole': role.value,
        },
      );

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('ERRORE aggiornamento ruolo utente: $e');
      return false;
    }
  }

  Future<CrossPromotionResult> activateSmartChefLaunchPromo() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null || _currentUser == null) {
      throw Exception('Devi essere autenticato per attivare la promo.');
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'activateSmartChefLaunchPromo',
    );
    final response = await callable.call(<String, dynamic>{});
    final raw = response.data;
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final result = CrossPromotionResult.fromMap(data);

    _currentUser = _currentUser!.copyWith(
      role: AppUserRole.premium,
      premiumUntil: result.premiumUntil,
      premiumSource: 'cross_promo_savein_to_smartchef',
    );
    await _saveUserLocally(_currentUser!);
    notifyListeners();
    return result;
  }

  Future<PromotionBanner?> getActivePromotionBanner() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    final callable = FirebaseFunctions.instance.httpsCallable(
      'getActivePromotionBanner',
    );
    final response = await callable.call(<String, dynamic>{});
    final raw = response.data;
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final bannerRaw = data['banner'];
    if (bannerRaw is! Map) return null;
    final banner = PromotionBanner.fromMap(
      Map<String, dynamic>.from(bannerRaw),
    );
    return banner.id.trim().isEmpty ? null : banner;
  }

  Future<void> recordPromotionBannerEvent({
    required String promotionId,
    required String eventType,
    String placement = '',
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null || promotionId.trim().isEmpty) return;

    final key = '$promotionId|$eventType|$placement';
    if (eventType == 'view' && _trackedPromotionEvents.contains(key)) return;
    _trackedPromotionEvents.add(key);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'recordPromotionBannerEvent',
      );
      await callable.call(<String, dynamic>{
        'promotionId': promotionId,
        'eventType': eventType,
        'placement': placement,
      });
    } catch (e) {
      if (kDebugMode) {
        print('DEBUG: errore tracking banner promo: $e');
      }
    }
  }

  Future<void> _claimPendingSmartChefLaunchPromoIfAvailable() async {
    if (_currentUser == null || _currentUser!.isAdmin || !_currentUser!.isFree) {
      return;
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'claimPendingSmartChefLaunchPromo',
      );
      final response = await callable.call(<String, dynamic>{});
      final raw = response.data;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      if (data['claimed'] != true || data['premiumUntil'] == null) {
        return;
      }

      final result = CrossPromotionResult.fromMap({
        ...data,
        'status': 'claimed',
        'claimBy': data['claimBy'] ?? DateTime.now().toIso8601String(),
      });
      _currentUser = _currentUser!.copyWith(
        role: AppUserRole.premium,
        premiumUntil: result.premiumUntil,
        premiumSource: 'cross_promo_smartchef_to_savein',
      );
      _pendingCrossPromotionNotification = result;
      await _saveUserLocally(_currentUser!);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('DEBUG: Nessuna promo SmartChef pending o claim fallito: $e');
      }
    }
  }

  Future<bool> assignRoleToUserByEmail({
    required String email,
    required AppUserRole role,
  }) async {
    if (_currentUser == null || !_currentUser!.canManageUserRoles) {
      throw Exception('Solo un admin può assegnare ruoli.');
    }

    final normalizedEmail = email.toLowerCase().trim();
    if (normalizedEmail.isEmpty) {
      throw Exception('Email utente non valida.');
    }

    QuerySnapshot<Map<String, dynamic>> query = await _firestore
        .collection('users')
        .where('normalizedEmail', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      query = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
    }

    if (query.docs.isEmpty) {
      throw Exception('Utente non trovato.');
    }

    final targetDoc = query.docs.first;
    await _assignRoleToUserDocument(
      targetDoc.id,
      role: role,
      normalizedEmail: normalizedEmail,
    );

    return true;
  }

  Future<bool> assignRoleToUserId({
    required String userId,
    required AppUserRole role,
  }) async {
    if (_currentUser == null || !_currentUser!.canManageUserRoles) {
      throw Exception('Solo un admin può assegnare ruoli.');
    }

    final userDoc = await _firestore.collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw Exception('Utente non trovato.');
    }

    final data = userDoc.data() ?? <String, dynamic>{};
    final normalizedEmail = (data['normalizedEmail'] as String?) ??
        (data['email'] as String?)?.toLowerCase().trim();

    await _assignRoleToUserDocument(
      userId,
      role: role,
      normalizedEmail: normalizedEmail,
    );
    return true;
  }

  Future<bool> updateDashboardAccessRole({
    required String userId,
    required DashboardAccessRole dashboardRole,
  }) async {
    if (_currentUser == null || !_currentUser!.canManageDashboardAccess) {
      throw Exception('Solo un admin dashboard può gestire gli accessi.');
    }
    await _ensureDashboardWillStillHaveAdmin(
      targetUserId: userId,
      newDashboardRole: dashboardRole,
    );

    if (userId == _currentUser!.id &&
        dashboardRole != DashboardAccessRole.admin) {
      throw Exception(
          'Non puoi rimuovere il tuo accesso admin alla dashboard.');
    }

    await _firestore.collection('users').doc(userId).set({
      'dashboardRole': dashboardRole.value,
      'dashboardRoleUpdatedAt': FieldValue.serverTimestamp(),
      'dashboardRoleUpdatedBy': _currentUser!.id,
    }, SetOptions(merge: true));

    await _writeAdminLog(
      action: 'dashboard_access_changed',
      targetUserId: userId,
      details: {
        'newDashboardRole': dashboardRole.value,
      },
    );

    if (userId == _currentUser!.id) {
      _currentUser = _currentUser!.copyWith(dashboardRole: dashboardRole);
      await _saveUserLocally(_currentUser!);
      notifyListeners();
    }
    return true;
  }

  Future<bool> upsertDashboardAccess({
    required String email,
    required DashboardAccessRole dashboardRole,
  }) async {
    if (_currentUser == null || !_currentUser!.canManageDashboardAccess) {
      throw Exception('Solo un admin dashboard può gestire gli accessi.');
    }

    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw Exception('Email accesso dashboard non valida.');
    }
    if (dashboardRole == DashboardAccessRole.none) {
      throw Exception(
          'Scegli Autore, Editore o Admin per aggiungere un accesso.');
    }

    await _ensureDashboardAccessWillStillHaveAdmin(
      targetEmail: normalizedEmail,
      newDashboardRole: dashboardRole,
    );

    await _firestore.collection('dashboard_accesses').doc(normalizedEmail).set({
      'email': email.trim(),
      'normalizedEmail': normalizedEmail,
      'dashboardRole': dashboardRole.value,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _currentUser!.id,
      'updatedByEmail': _currentUser!.email,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _writeAdminLog(
      action: 'dashboard_access_upserted',
      targetUserId: normalizedEmail,
      details: {
        'email': normalizedEmail,
        'newDashboardRole': dashboardRole.value,
      },
    );

    return true;
  }

  Future<bool> updateDashboardAccessEmailRole({
    required String email,
    required DashboardAccessRole dashboardRole,
  }) async {
    if (_currentUser == null || !_currentUser!.canManageDashboardAccess) {
      throw Exception('Solo un admin dashboard può gestire gli accessi.');
    }

    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty) {
      throw Exception('Email accesso dashboard non valida.');
    }

    if (dashboardRole == DashboardAccessRole.none) {
      await _ensureDashboardAccessWillStillHaveAdmin(
        targetEmail: normalizedEmail,
        newDashboardRole: dashboardRole,
      );
      await _firestore
          .collection('dashboard_accesses')
          .doc(normalizedEmail)
          .delete();
    } else {
      await _ensureDashboardAccessWillStillHaveAdmin(
        targetEmail: normalizedEmail,
        newDashboardRole: dashboardRole,
      );
      await _firestore
          .collection('dashboard_accesses')
          .doc(normalizedEmail)
          .set({
        'dashboardRole': dashboardRole.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _currentUser!.id,
        'updatedByEmail': _currentUser!.email,
      }, SetOptions(merge: true));
    }

    await _writeAdminLog(
      action: 'dashboard_access_email_changed',
      targetUserId: normalizedEmail,
      details: {
        'email': normalizedEmail,
        'newDashboardRole': dashboardRole.value,
      },
    );

    return true;
  }

  Future<void> _ensureDashboardAccessWillStillHaveAdmin({
    required String targetEmail,
    required DashboardAccessRole newDashboardRole,
  }) async {
    final accessSnapshot =
        await _firestore.collection('dashboard_accesses').get();
    var adminCountAfterChange = 0;
    var targetExists = false;

    for (final doc in accessSnapshot.docs) {
      final data = doc.data();
      final email =
          ((data['normalizedEmail'] as String?) ?? doc.id).toLowerCase().trim();
      if (email == targetEmail) {
        targetExists = true;
      }
      final role = email == targetEmail
          ? newDashboardRole
          : DashboardAccessRoleX.fromValue(data['dashboardRole'] as String?);
      if (role == DashboardAccessRole.admin) {
        adminCountAfterChange++;
      }
    }

    if (!targetExists && newDashboardRole == DashboardAccessRole.admin) {
      adminCountAfterChange++;
    }

    if (adminCountAfterChange == 0) {
      throw Exception('non ci sono altri admin, non puoi non essercene uno');
    }
  }

  Future<void> _ensureDashboardWillStillHaveAdmin({
    required String targetUserId,
    AppUserRole? newAppRole,
    DashboardAccessRole? newDashboardRole,
  }) async {
    final usersSnapshot = await _firestore.collection('users').get();
    var adminCountAfterChange = 0;

    for (final doc in usersSnapshot.docs) {
      final data = doc.data();
      final currentAppRole = AppUserRoleX.fromValue(data['role'] as String?);
      final currentDashboardRole =
          DashboardAccessRoleX.fromValue(data['dashboardRole'] as String?);

      final appRole = doc.id == targetUserId
          ? newAppRole ?? currentAppRole
          : currentAppRole;
      final dashboardRole = doc.id == targetUserId
          ? newDashboardRole ?? currentDashboardRole
          : currentDashboardRole;

      if (appRole == AppUserRole.admin ||
          dashboardRole == DashboardAccessRole.admin) {
        adminCountAfterChange++;
      }
    }

    if (adminCountAfterChange == 0) {
      throw Exception('non ci sono altri admin, non puoi non essercene uno');
    }
  }

  Future<void> _assignRoleToUserDocument(
    String userId, {
    required AppUserRole role,
    String? normalizedEmail,
  }) async {
    final targetDoc = await _firestore.collection('users').doc(userId).get();
    final targetData = targetDoc.data() ?? <String, dynamic>{};
    await _ensureDashboardWillStillHaveAdmin(
      targetUserId: userId,
      newAppRole: role,
      newDashboardRole: DashboardAccessRoleX.fromValue(
          targetData['dashboardRole'] as String?),
    );

    await _firestore.collection('users').doc(userId).set({
      'role': role.value,
      'roleUpdatedAt': FieldValue.serverTimestamp(),
      'roleUpdatedBy': _currentUser!.id,
      if (normalizedEmail != null && normalizedEmail.isNotEmpty)
        'normalizedEmail': normalizedEmail,
    }, SetOptions(merge: true));

    await _writeAdminLog(
      action: 'role_changed',
      targetUserId: userId,
      details: {
        'newRole': role.value,
      },
    );

    if (userId == _currentUser!.id) {
      _currentUser = _currentUser!.copyWith(role: role);
      await _saveUserLocally(_currentUser!);
      notifyListeners();
    }
  }

  Future<bool> updateUserBlockedState({
    required String userId,
    required bool isBlocked,
    String? reason,
  }) async {
    if (_currentUser == null || !_currentUser!.canBlockUsers) {
      throw Exception('Non hai i permessi per bloccare o sbloccare account.');
    }
    if (userId == _currentUser!.id && isBlocked) {
      throw Exception('Non puoi bloccare il tuo account admin.');
    }

    final normalizedReason = reason?.trim();

    await _firestore.collection('users').doc(userId).set({
      'isBlocked': isBlocked,
      'blockedReason': isBlocked
          ? (normalizedReason?.isNotEmpty == true
              ? normalizedReason
              : 'Bloccato da admin')
          : null,
      'blockedAt': isBlocked ? FieldValue.serverTimestamp() : null,
      'blockedUpdatedAt': FieldValue.serverTimestamp(),
      'blockedUpdatedBy': _currentUser!.id,
    }, SetOptions(merge: true));

    await _writeAdminLog(
      action: isBlocked ? 'user_blocked' : 'user_unblocked',
      targetUserId: userId,
      details: {
        'reason': normalizedReason,
      },
    );

    if (_currentUser?.id == userId) {
      _currentUser = _currentUser!.copyWith(
        isBlocked: isBlocked,
        blockedReason: isBlocked
            ? (normalizedReason?.isNotEmpty == true
                ? normalizedReason
                : 'Bloccato da admin')
            : null,
        blockedAt: isBlocked ? DateTime.now() : null,
      );
      await _saveUserLocally(_currentUser!);
      notifyListeners();
    }

    return true;
  }

  Future<void> _writeAdminLog({
    required String action,
    required String targetUserId,
    Map<String, dynamic>? details,
  }) async {
    final actor = _currentUser;
    if (actor == null) {
      return;
    }

    await _firestore.collection('admin_logs').add({
      'action': action,
      'targetUserId': targetUserId,
      'actorUserId': actor.id,
      'actorEmail': actor.email,
      'timestamp': FieldValue.serverTimestamp(),
      'details': details ?? <String, dynamic>{},
    });
  }

  String _getFirebaseErrorMessage(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Email non registrata. Effettua prima la registrazione.';
      case 'wrong-password':
        return 'Password non corretta';
      case 'invalid-email':
        return 'Email non valida';
      case 'user-disabled':
        return 'Account disabilitato';
      case 'email-already-in-use':
        return 'Email già registrata';
      case 'weak-password':
        return 'Password troppo debole';
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Credenziali non valide';
      case 'too-many-requests':
        return 'Troppi tentativi. Riprova più tardi.';
      case 'network-request-failed':
        return 'Errore di connessione. Verifica la tua connessione internet.';
      case 'requires-recent-login':
        return 'Devi effettuare nuovamente il login per questa operazione';
      default:
        return 'Errore di autenticazione: ${e.message ?? e.code}';
    }
  }

  Future<bool> updateUserProfile({
    String? name,
    String? username,
  }) async {
    if (_currentUser == null) return false;

    try {
      if (name != null && name != _currentUser!.name) {
        await _firebaseAuth.currentUser?.updateDisplayName(name);
      }

      _currentUser = _currentUser!.copyWith(
        name: name,
        username: username,
      );

      await _saveUserLocally(_currentUser!);

      // ✅ Sync con Firestore
      if (_firebaseAuth.currentUser != null) {
        await _firestore.collection('users').doc(_currentUser!.id).update({
          'name': _currentUser!.name,
          'username': _currentUser!.username,
          'normalizedEmail': _currentUser!.email.toLowerCase().trim(),
        });
      }

      notifyListeners();

      if (kDebugMode)
        print('DEBUG: ✔ Profilo aggiornato: ${_currentUser!.name}');
      return true;
    } catch (e) {
      if (kDebugMode) print('ERRORE aggiornamento profilo: $e');
      return false;
    }
  }

  Future<bool> updateUserProfileAndPassword({
    String? name,
    String? username,
    required String newPassword,
  }) async {
    if (_currentUser == null || _firebaseAuth.currentUser == null) return false;

    try {
      await _firebaseAuth.currentUser!.updatePassword(newPassword);
      await updateUserProfile(name: name, username: username);

      if (kDebugMode) print('DEBUG: ✔ Password e profilo aggiornati');
      return true;
    } catch (e) {
      if (kDebugMode) print('ERRORE aggiornamento password: $e');
      return false;
    }
  }

  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable(
        'sendPasswordResetEmail',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call(<String, dynamic>{'email': email.trim().toLowerCase()});
      if (kDebugMode) print('DEBUG: Email reset password inviata a: $email');
      return true;
    } catch (e) {
      if (kDebugMode) print('ERRORE invio email reset: $e');
      return false;
    }
  }

  Future<void> _saveRememberedEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remembered_email', email);
    } catch (e) {
      print('ERRORE salvataggio email: $e');
    }
  }

  Future<String?> getRememberedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('remembered_email');
    } catch (e) {
      return null;
    }
  }

  Future<void> printDebugInfo() async {
    print('=== 🔥 DEBUG AUTH SERVICE REATTIVO ===');
    print('Inizializzato: $_isInitialized');
    print('Firebase User: ${_firebaseAuth.currentUser?.email}');
    print('Local User: ${_currentUser?.email}');
    print('Logged In: $isLoggedIn');
    print('=======================================');
  }
}
