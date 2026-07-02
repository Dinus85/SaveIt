import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'simple_analytics_service.dart';
import '../advanced_analytics_service.dart';

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
  final DateTime? birthDate;
  final String? gender;

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
    this.birthDate,
    this.gender,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

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
      blockedAt: parseDate(json['blockedAt']),
      acceptedTerms: json['acceptedTerms'] ?? false,
      acceptedPrivacy: json['acceptedPrivacy'] ?? false,
      acceptedMarketing: json['acceptedMarketing'] ?? true,
      createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
      premiumUntil: parseDate(json['premiumUntil']),
      premiumSource: json['premiumSource'],
      birthDate: parseDate(json['birthDate']),
      gender: json['gender'],
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
      'birthDate': birthDate?.toIso8601String(),
      'gender': gender,
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
    bool clearPremiumUntil = false,
    String? premiumSource,
    bool clearPremiumSource = false,
    DateTime? birthDate,
    String? gender,
  }) {
    return User(
      id: id,
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
      createdAt: createdAt,
      premiumUntil:
          clearPremiumUntil ? null : premiumUntil ?? this.premiumUntil,
      premiumSource:
          clearPremiumSource ? null : premiumSource ?? this.premiumSource,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
    );
  }

  bool get hasActiveTimedPremium => _isPremiumExpiryActive(premiumUntil);

  static bool _isPremiumExpiryActive(DateTime? until) {
    if (until == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(until.year, until.month, until.day);
    return !today.isAfter(expiryDay);
  }

  AppUserRole get effectiveRole {
    if (role == AppUserRole.admin) return AppUserRole.admin;
    if (role == AppUserRole.premium && _isPremiumExpiryActive(premiumUntil)) {
      return AppUserRole.premium;
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

class NewSignupPremiumPromoConfig {
  final bool active;
  final int durationDays;
  final String priceAfterTrial;

  const NewSignupPremiumPromoConfig({
    required this.active,
    required this.durationDays,
    required this.priceAfterTrial,
  });

  factory NewSignupPremiumPromoConfig.fromMap(Map<String, dynamic> data) {
    return NewSignupPremiumPromoConfig(
      active: data['active'] == true,
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 30,
      priceAfterTrial: (data['priceAfterTrial'] ?? '2.99').toString(),
    );
  }
}

class NewSignupPremiumPromoEligibility {
  final bool active;
  final bool canClaim;
  final bool alreadyClaimed;
  final bool restored;
  final bool expired;
  final int durationDays;
  final String priceAfterTrial;
  final DateTime? premiumUntil;
  final DateTime? startedAt;

  const NewSignupPremiumPromoEligibility({
    required this.active,
    required this.canClaim,
    required this.alreadyClaimed,
    required this.restored,
    required this.expired,
    required this.durationDays,
    required this.priceAfterTrial,
    this.premiumUntil,
    this.startedAt,
  });

  factory NewSignupPremiumPromoEligibility.fromMap(Map<String, dynamic> data) {
    DateTime? parseOptionalDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString())?.toLocal();
    }

    return NewSignupPremiumPromoEligibility(
      active: data['active'] == true,
      canClaim: data['canClaim'] == true,
      alreadyClaimed: data['alreadyClaimed'] == true,
      restored: data['restored'] == true,
      expired: data['expired'] == true,
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 30,
      priceAfterTrial: (data['priceAfterTrial'] ?? '2.99').toString(),
      premiumUntil: parseOptionalDate(data['premiumUntil']),
      startedAt: parseOptionalDate(data['startedAt']),
    );
  }

  NewSignupPremiumPromoConfig get config => NewSignupPremiumPromoConfig(
        active: active,
        durationDays: durationDays,
        priceAfterTrial: priceAfterTrial,
      );
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
  final String imageUrl;
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
    required this.imageUrl,
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
      imageUrl: data['imageUrl']?.toString() ?? '',
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userProfileSubscription;
  Completer<void>? _initializationCompleter;
  Completer<void>? _consentLoadingCompleter;
  CrossPromotionResult? _pendingCrossPromotionNotification;
  firebase_auth.AuthCredential? _pendingGoogleCredential;
  String? _pendingGoogleEmail;
  final Set<String> _trackedPromotionEvents = <String>{};
  DateTime? _lastConsentSyncAt;
  String? _lastConsentSyncUserId;
  bool _isProcessingAuthStateChange = false;
  bool _isDeletingAccount = false;
  bool _isCompletingGoogleSignIn = false;
  static const Duration _consentSyncCooldown = Duration(seconds: 10);
  VoidCallback? onUserProfileChanged;

  // Getters pubblici
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isInitialized => _isInitialized;
  String? get pendingGoogleEmail => _pendingGoogleEmail;
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

  /// Legge il documento utente privilegiando il server.
  /// Ritorna `(doc, fromServer)`:
  ///   - fromServer = true  → dati freschi dal server
  ///   - fromServer = false → dati dalla cache locale (potrebbero essere stale)
  ///   - null               → impossibile leggere (completamente offline)
  Future<(DocumentSnapshot<Map<String, dynamic>>?, bool)> _fetchUserDocument(
      String userId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      return (doc, true);
    } catch (e) {
      if (kDebugMode) {
        print('DEBUG: fallback cache profilo utente: $e');
      }
    }
    try {
      final doc = await _firestore.collection('users').doc(userId).get(
            const GetOptions(source: Source.cache),
          );
      return (doc, false);
    } catch (e) {
      if (kDebugMode) {
        print('DEBUG: impossibile leggere documento utente (offline?): $e');
      }
      return (null, false);
    }
  }

  User _userFromFirestoreData(
    firebase_auth.User firebaseUser,
    Map<String, dynamic> data,
    String documentId, {
    User? fallback,
  }) {
    final email = (data['email'] as String?)?.trim().isNotEmpty == true
        ? (data['email'] as String).trim()
        : firebaseUser.email ?? fallback?.email ?? '';
    final name = (data['name'] as String?)?.trim().isNotEmpty == true
        ? (data['name'] as String).trim()
        : firebaseUser.displayName ?? fallback?.name ?? 'Utente';
    final marketingConsent = data['consents']?['marketing']?['accepted'] ??
        fallback?.acceptedMarketing ??
        true;

    final blockedAtValue = data['blockedAt'];
    final blockedAt = blockedAtValue is Timestamp
        ? blockedAtValue.toDate()
        : (blockedAtValue is String ? DateTime.tryParse(blockedAtValue) : null);

    return User(
      id: (data['userId'] as String?)?.trim().isNotEmpty == true
          ? (data['userId'] as String).trim()
          : documentId,
      name: name,
      email: email,
      username: data['username'] as String? ?? fallback?.username,
      role: AppUserRoleX.fromValue(data['role'] as String?),
      dashboardRole: DashboardAccessRoleX.fromValue(
        data['dashboardRole'] as String?,
      ),
      isBlocked: data['isBlocked'] ?? false,
      blockedReason: data['blockedReason'] as String?,
      blockedAt: blockedAt,
      acceptedTerms: data['acceptedTerms'] ?? fallback?.acceptedTerms ?? true,
      acceptedPrivacy:
          data['acceptedPrivacy'] ?? fallback?.acceptedPrivacy ?? true,
      acceptedMarketing: marketingConsent,
      createdAt: _dateFromFirestoreValue(data['createdAt']) ??
          fallback?.createdAt ??
          firebaseUser.metadata.creationTime ??
          DateTime.now(),
      premiumUntil: _dateFromFirestoreValue(data['premiumUntil']),
      premiumSource: data['premiumSource'] as String?,
      birthDate:
          _dateFromFirestoreValue(data['birthDate']) ?? fallback?.birthDate,
      gender: data['gender'] as String? ?? fallback?.gender,
    );
  }

  bool _hasProfileChanged(User? current, User updated) {
    if (current == null) return true;
    return current.role != updated.role ||
        current.effectiveRole != updated.effectiveRole ||
        current.dashboardRole != updated.dashboardRole ||
        current.isBlocked != updated.isBlocked ||
        current.blockedReason != updated.blockedReason ||
        current.premiumUntil != updated.premiumUntil ||
        current.premiumSource != updated.premiumSource ||
        current.acceptedMarketing != updated.acceptedMarketing ||
        current.name != updated.name ||
        current.email != updated.email;
  }

  Future<void> _applySyncedUserProfile(User syncedUser) async {
    if (!_hasProfileChanged(_currentUser, syncedUser)) {
      return;
    }

    _currentUser = syncedUser;
    await _saveUserLocally(syncedUser);
    notifyListeners();
    onUserProfileChanged?.call();
  }

  void _ensureUserProfileSync(String userId) {
    if (_userProfileSubscription != null) {
      return;
    }
    _startUserProfileSync(userId);
  }

  void _startUserProfileSync(String userId) {
    _userProfileSubscription?.cancel();
    _userProfileSubscription =
        _firestore.collection('users').doc(userId).snapshots().listen(
      (snapshot) async {
        final firebaseUser = _firebaseAuth.currentUser;
        final data = snapshot.data();
        if (firebaseUser == null ||
            firebaseUser.uid != userId ||
            !snapshot.exists ||
            data == null) {
          return;
        }

        final syncedUser = _userFromFirestoreData(
          firebaseUser,
          data,
          snapshot.id,
          fallback: _currentUser,
        );
        await _applySyncedUserProfile(syncedUser);
      },
      onError: (error) {
        if (kDebugMode) {
          print('DEBUG: errore listener profilo utente: $error');
        }
        _userProfileSubscription = null;
      },
    );
  }

  Future<User?> reloadCurrentUserFromFirestore() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    final (doc, fromServer) = await _fetchUserDocument(firebaseUser.uid);
    if (doc == null) {
      // Completamente offline: mantieni stato corrente, riattiva listener
      _ensureUserProfileSync(firebaseUser.uid);
      return _currentUser;
    }
    final data = doc.data();
    if (doc.exists && data != null) {
      final loadedUser = _userFromFirestoreData(
        firebaseUser,
        data,
        doc.id,
        fallback: _currentUser,
      );

      // Protezione anti-downgrade: non ridurre il ruolo usando dati dalla cache locale
      final currentRole = _currentUser?.effectiveRole ?? AppUserRole.free;
      final loadedRole = loadedUser.effectiveRole;
      final isDowngrade =
          currentRole == AppUserRole.premium && loadedRole == AppUserRole.free;
      if (isDowngrade && !fromServer) {
        if (kDebugMode) {
          print(
              'DEBUG: ⚠️ reloadCurrentUser: downgrade Premium→Free da cache stale ignorato');
        }
        _ensureUserProfileSync(firebaseUser.uid);
        return _currentUser;
      }

      _currentUser = loadedUser;
      await _saveUserLocally(_currentUser!);
      notifyListeners();
      onUserProfileChanged?.call();
      _startUserProfileSync(firebaseUser.uid);
    } else {
      _currentUser ??= _userFromFirebase(firebaseUser);
      await _loadMarketingConsentFromFirestore(forceRefresh: true);
    }
    return _currentUser;
  }

  Future<User?> _loadCachedUserIfAny(firebase_auth.User firebaseUser) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_${firebaseUser.uid}');
      if (userData == null) return null;
      final cachedUser = User.fromJson(jsonDecode(userData));
      final firebaseEmail = _normalizeEmail(firebaseUser.email ?? '');
      if (cachedUser.id == firebaseUser.uid &&
          _normalizeEmail(cachedUser.email) == firebaseEmail) {
        return cachedUser;
      }
    } catch (_) {}
    return null;
  }

  Stream<User?> get userStream async* {
    await for (final firebaseUser in _firebaseAuth.authStateChanges()) {
      if (firebaseUser == null || _isDeletingAccount) {
        _currentUser = null;
        await _userProfileSubscription?.cancel();
        _userProfileSubscription = null;
        await _clearLocalData(preserveUserProfileCache: !_isDeletingAccount);
        notifyListeners();
        yield null;
        continue;
      }

      if (_isCompletingGoogleSignIn) {
        if (kDebugMode) {
          print('DEBUG: ⏳ Stream auth in pausa durante bootstrap Google');
        }
        yield null;
        continue;
      }

      final firebaseEmail = _normalizeEmail(firebaseUser.email ?? '');
      final hasMatchingUser = _currentUser?.id == firebaseUser.uid &&
          _normalizeEmail(_currentUser?.email ?? '') == firebaseEmail;

      if (!hasMatchingUser) {
        final cachedUser = await _loadCachedUserIfAny(firebaseUser);
        _currentUser = cachedUser ?? _userFromFirebase(firebaseUser);
        notifyListeners();
      }

      yield _currentUser;

      await _loadUserData(firebaseUser);
      if (_currentUser?.id == firebaseUser.uid) {
        notifyListeners();
        yield _currentUser;
      }
    }
  }

  User _userFromFirebase(firebase_auth.User firebaseUser) {
    final displayName = firebaseUser.displayName?.trim();
    final fallbackName =
        displayName?.isNotEmpty == true ? displayName! : 'Utente';

    return User(
      id: firebaseUser.uid,
      name: fallbackName,
      email: firebaseUser.email ?? '',
      username: '@${fallbackName.toLowerCase().replaceAll(' ', '.')}',
      role: AppUserRole.free,
      isBlocked: false,
      acceptedTerms: true,
      acceptedPrivacy: true,
      acceptedMarketing: true,
      createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
    );
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

      // Caricamento iniziale utente: cache locale subito, Firestore in background.
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser != null) {
        if (kDebugMode) {
          print(
              'DEBUG: Utente Firebase attivo all\'avvio: ${firebaseUser.email}');
        }

        _isProcessingAuthStateChange = true;
        try {
          final cachedUser = await _loadCachedUserIfAny(firebaseUser);
          _currentUser = cachedUser ?? _userFromFirebase(firebaseUser);
        } finally {
          _isProcessingAuthStateChange = false;
        }

        unawaited(_loadUserData(firebaseUser).catchError((Object e) {
          if (kDebugMode) {
            print('DEBUG: loadUserData background fallito: $e');
          }
        }));
      } else {
        if (kDebugMode) {
          print('DEBUG: Nessun utente Firebase autenticato all\'avvio');
        }
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
    if (_isCompletingGoogleSignIn) {
      if (kDebugMode) {
        print('DEBUG: ⏳ Google Sign-In in completamento, salto listener auth');
      }
      return;
    }
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

      if (_isDeletingAccount) {
        _currentUser = null;
        await _userProfileSubscription?.cancel();
        _userProfileSubscription = null;
        await _clearLocalData();
        notifyListeners();
      } else if (firebaseUser != null) {
        // Evita ricaricamento se l'utente è lo stesso e abbiamo già i dati
        if (_currentUser?.id == firebaseUser.uid &&
            _currentUser?.email == firebaseUser.email) {
          if (kDebugMode) {
            print(
                'DEBUG: ℹ️ Utente già caricato, verifico listener profilo Firestore');
          }
          _ensureUserProfileSync(firebaseUser.uid);
        } else {
          await _loadUserData(firebaseUser);
        }
      } else {
        if (_currentUser != null) {
          _currentUser = null;
          await _userProfileSubscription?.cancel();
          _userProfileSubscription = null;
          await _clearLocalData(preserveUserProfileCache: true);
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
    _userProfileSubscription?.cancel();
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

        await _linkPendingGoogleCredentialIfNeeded(
          credential.user!,
          email,
        );
        await _loadUserData(credential.user!);

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

  Future<void> _linkPendingGoogleCredentialIfNeeded(
    firebase_auth.User firebaseUser,
    String email,
  ) async {
    final pendingCredential = _pendingGoogleCredential;
    final pendingEmail = _pendingGoogleEmail;
    if (pendingCredential == null || pendingEmail == null) return;
    if (_normalizeEmail(pendingEmail) != _normalizeEmail(email)) return;

    try {
      await firebaseUser.linkWithCredential(pendingCredential);
      if (kDebugMode) print('DEBUG: Google collegato all account esistente');
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        if (kDebugMode) {
          print('DEBUG: Google già collegato: ${e.code}');
        }
        return;
      }
      if (e.code == 'credential-already-in-use') {
        await _firebaseAuth.signOut();
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        _currentUser = null;
        notifyListeners();
        throw Exception(
          'Questo account Google risulta già collegato a un altro profilo. '
          'Per sicurezza sei stato disconnesso: accedi con email e password.',
        );
      }
      rethrow;
    } finally {
      _pendingGoogleCredential = null;
      _pendingGoogleEmail = null;
    }
  }

  Future<String?> _findExistingUserIdByEmail(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty) return null;

    try {
      var query = await _firestore
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
      if (query.docs.isEmpty) return null;
      final data = query.docs.first.data();
      return (data['userId'] as String?)?.trim().isNotEmpty == true
          ? (data['userId'] as String).trim()
          : query.docs.first.id;
    } catch (e) {
      if (kDebugMode) print('ERRORE lookup utente per email: $e');
      return null;
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

      _isCompletingGoogleSignIn = true;
      final userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      if (userCredential.user != null) {
        final firebaseUser = userCredential.user!;
        final googleEmail = firebaseUser.email ?? googleUser.email;
        final userDoc = await _firestore
            .collection('users')
            .doc(firebaseUser.uid)
            .get(const GetOptions(source: Source.serverAndCache));
        if (!userDoc.exists) {
          final displayName = firebaseUser.displayName?.trim();
          final name = displayName?.isNotEmpty == true
              ? displayName!
              : (googleUser.displayName?.trim().isNotEmpty == true
                  ? googleUser.displayName!.trim()
                  : 'Utente');
          final user = User(
            id: firebaseUser.uid,
            name: name,
            email: googleEmail,
            username: '@${name.toLowerCase().replaceAll(' ', '.')}',
            role: AppUserRole.free,
            isBlocked: false,
            acceptedTerms: true,
            acceptedPrivacy: true,
            acceptedMarketing: true,
            createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
          );
          _currentUser = user;
          await _saveUserLocally(user);
          await _saveUserToFirestore(user);
          notifyListeners();
        }
        await _loadUserData(firebaseUser);
        _isCompletingGoogleSignIn = false;
        notifyListeners();

        if (kDebugMode) {
          print(
              'DEBUG: ✔ Google Sign-In Firebase completato - Aspettando sincronizzazione...');
        }
        await _waitForUserSync(firebaseUser.email!);

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

      _isCompletingGoogleSignIn = false;
      return AuthResult(success: false, message: 'Errore Google Sign-In');
    } on firebase_auth.FirebaseAuthException catch (e) {
      _isCompletingGoogleSignIn = false;
      if (kDebugMode) print('ERRORE Google Sign-In Firebase: ${e.code} - $e');
      if (e.code == 'account-exists-with-different-credential') {
        _pendingGoogleCredential = e.credential;
        _pendingGoogleEmail = e.email;
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        return AuthResult(
          success: false,
          message: 'Questa email è già registrata con password. '
              'Inserisci la password e premi Accedi: collegheremo Google '
              'allo stesso account, poi potrai usare il login Google.',
        );
      }
      return AuthResult(
        success: false,
        message: _getFirebaseErrorMessage(e),
      );
    } catch (e) {
      _isCompletingGoogleSignIn = false;
      if (kDebugMode) print('ERRORE Google Sign-In: $e');
      return AuthResult(
        success: false,
        message:
            'Errore durante l\'autenticazione con Google. Verifica la connessione.',
      );
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<AuthResult> loginWithApple() async {
    try {
      if (kDebugMode) print('DEBUG: Apple Sign-In...');

      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        return AuthResult(
          success: false,
          message: 'Accedi con Apple non è disponibile su questo dispositivo.',
        );
      }

      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final identityToken = appleCredential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        return AuthResult(
          success: false,
          message: 'Apple non ha restituito un token valido. Riprova.',
        );
      }

      final credential = firebase_auth.OAuthProvider('apple.com').credential(
        idToken: identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      if (userCredential.user != null) {
        final firebaseUser = userCredential.user!;
        final userDoc = await _firestore
            .collection('users')
            .doc(firebaseUser.uid)
            .get(const GetOptions(source: Source.serverAndCache));

        if (!userDoc.exists) {
          final givenName = appleCredential.givenName?.trim() ?? '';
          final familyName = appleCredential.familyName?.trim() ?? '';
          final appleName = '$givenName $familyName'.trim();
          final displayName = firebaseUser.displayName?.trim();
          final email = firebaseUser.email?.trim().isNotEmpty == true
              ? firebaseUser.email!.trim()
              : (appleCredential.email?.trim() ?? '');
          final name = appleName.isNotEmpty
              ? appleName
              : (displayName?.isNotEmpty == true ? displayName! : 'Utente');

          final user = User(
            id: firebaseUser.uid,
            name: name,
            email: email,
            username: '@${name.toLowerCase().replaceAll(' ', '.')}',
            role: AppUserRole.free,
            isBlocked: false,
            acceptedTerms: true,
            acceptedPrivacy: true,
            acceptedMarketing: true,
            createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
          );
          _currentUser = user;
          await _saveUserLocally(user);
          await _saveUserToFirestore(user);
          notifyListeners();
        }

        await _loadUserData(firebaseUser);
        notifyListeners();

        final email = firebaseUser.email ?? _currentUser?.email;
        if (email != null && email.trim().isNotEmpty) {
          await _waitForUserSync(email);
        }

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

      return AuthResult(success: false, message: 'Errore Accedi con Apple');
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return AuthResult(success: false, message: 'Login annullato');
      }
      if (kDebugMode) print('ERRORE Apple Sign-In: ${e.code} - $e');
      return AuthResult(
        success: false,
        message: 'Errore durante l\'autenticazione con Apple. Riprova.',
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (kDebugMode) print('ERRORE Apple Sign-In Firebase: ${e.code} - $e');
      return AuthResult(
        success: false,
        message: _getFirebaseErrorMessage(e),
      );
    } catch (e) {
      if (kDebugMode) print('ERRORE Apple Sign-In: $e');
      return AuthResult(
        success: false,
        message:
            'Errore durante l\'autenticazione con Apple. Verifica la connessione.',
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
    DateTime? birthDate,
    String? gender,
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
          birthDate: birthDate,
          gender: gender,
        );

        _currentUser = user;
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
    final normalizedExpectedEmail = _normalizeEmail(expectedEmail);
    if (kDebugMode)
      print('DEBUG: 🔄 Aspettando sincronizzazione utente: $expectedEmail');

    int attempts = 0;
    const maxAttempts = 50;

    while (attempts < maxAttempts) {
      if (_currentUser != null &&
          _currentUser!.id == _firebaseAuth.currentUser?.uid &&
          _normalizeEmail(_currentUser!.email) == normalizedExpectedEmail) {
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
    if (firebaseUser != null &&
        _normalizeEmail(firebaseUser.email ?? '') == normalizedExpectedEmail) {
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

      _currentUser = null;
      await _userProfileSubscription?.cancel();
      _userProfileSubscription = null;
      await _clearLocalData(preserveUserProfileCache: true);
      notifyListeners();

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
      _isDeletingAccount = true;
      final userEmail = _currentUser!.email;
      final userId = _currentUser!.id;
      if (kDebugMode) print('DEBUG: 🔥 Eliminazione account: $userEmail');

      try {
        await _googleSignIn.signOut();
      } catch (e) {
        if (kDebugMode) print('WARNING: Errore disconnessione Google: $e');
      }

      await _deleteCurrentUserData(userId: userId, email: userEmail);

      await _firebaseAuth.currentUser!.delete();
      if (kDebugMode) print('DEBUG: Account Firebase eliminato');

      try {
        await _firebaseAuth.signOut();
      } catch (_) {}

      _currentUser = null;
      await _clearLocalData(deletedUserId: userId);
      await _clearAnalyticsServices();
      notifyListeners();

      if (kDebugMode) {
        print('DEBUG: ✔ Eliminazione completata - sessione locale pulita');
      }

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
    } finally {
      _isDeletingAccount = false;
    }
  }

  Future<void> _deleteCurrentUserData({
    required String userId,
    required String email,
  }) async {
    final userRef = _firestore.collection('users').doc(userId);
    final normalizedEmail = email.toLowerCase().trim();

    const userSubcollections = [
      'folders',
      'posts',
      'shared_items',
      'fcmTokens',
      'notifications',
      'reminders',
      'analytics',
      'account_history',
    ];

    for (final collectionName in userSubcollections) {
      await _deleteCollection(userRef.collection(collectionName));
    }

    await _ignoreCleanupErrors(
      'feature_usage',
      () => _deleteDocumentIfExists(
        _firestore.collection('feature_usage').doc(userId),
      ),
    );
    await _ignoreCleanupErrors(
      'shared_links',
      () => _deleteQuery(
        _firestore
            .collection('shared_links')
            .where('ownerId', isEqualTo: userId),
      ),
    );
    await _ignoreCleanupErrors(
      'promotion_redemptions',
      () => _deleteQuery(
        _firestore
            .collection('promotion_redemptions')
            .where('userId', isEqualTo: userId),
      ),
    );
    await _ignoreCleanupErrors(
      'new_signup_premium_promo_claims.firstUserId',
      () => _deleteQuery(
        _firestore
            .collection('new_signup_premium_promo_claims')
            .where('firstUserId', isEqualTo: userId),
      ),
    );
    await _ignoreCleanupErrors(
      'new_signup_premium_promo_claims.lastUserId',
      () => _deleteQuery(
        _firestore
            .collection('new_signup_premium_promo_claims')
            .where('lastUserId', isEqualTo: userId),
      ),
    );
    await _ignoreCleanupErrors(
      'cross_app_promos.sourceUid',
      () => _deleteQuery(
        _firestore
            .collection('cross_app_promos')
            .where('sourceUid', isEqualTo: userId),
      ),
    );
    await _ignoreCleanupErrors(
      'cross_app_promos.saveinUid',
      () => _deleteQuery(
        _firestore
            .collection('cross_app_promos')
            .where('saveinUid', isEqualTo: userId),
      ),
    );
    if (normalizedEmail.isNotEmpty) {
      await _ignoreCleanupErrors(
        'dashboard_accesses',
        () => _deleteDocumentIfExists(
          _firestore.collection('dashboard_accesses').doc(normalizedEmail),
        ),
      );
    }

    await _deleteUserStorage(userId);

    try {
      await userRef.delete();
      if (kDebugMode) print('DEBUG: ✅ Dati Firestore utente eliminati');
    } catch (e) {
      if (kDebugMode) print('WARNING: Errore eliminazione profilo utente: $e');
    }
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection, {
    int batchSize = 200,
  }) async {
    while (true) {
      final snapshot = await collection.limit(batchSize).get();
      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _deleteQuery(
    Query<Map<String, dynamic>> query, {
    int batchSize = 200,
  }) async {
    while (true) {
      final snapshot = await query.limit(batchSize).get();
      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _deleteDocumentIfExists(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final snapshot = await ref.get();
    if (snapshot.exists) {
      await ref.delete();
    }
  }

  Future<void> _ignoreCleanupErrors(
    String label,
    Future<void> Function() cleanup,
  ) async {
    try {
      await cleanup();
    } catch (e) {
      if (kDebugMode) print('WARNING: Cleanup $label saltato: $e');
    }
  }

  Future<void> _deleteUserStorage(String userId) async {
    try {
      await _deleteStorageFolder(FirebaseStorage.instance.ref('users/$userId'));
    } catch (e) {
      if (kDebugMode) print('WARNING: Errore eliminazione Storage utente: $e');
    }
  }

  Future<void> _deleteStorageFolder(Reference ref) async {
    final result = await ref.listAll();
    for (final item in result.items) {
      try {
        await item.delete();
      } catch (e) {
        if (kDebugMode) print('WARNING: Errore eliminazione file Storage: $e');
      }
    }
    for (final prefix in result.prefixes) {
      await _deleteStorageFolder(prefix);
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

  /// Salva l'utente completo su Firestore solo alla prima creazione.
  ///
  /// IMPORTANTE: se il documento esiste gia', non riscrivere mai campi di piano
  /// come role/premiumUntil/premiumSource dal client. Il piano e' deciso dalla
  /// dashboard/backend; durante login/logout il client puo' avere fallback Free.
  Future<void> _saveUserToFirestore(User user) async {
    try {
      print('DEBUG: 🌐 Salvando utente su Firestore...');

      final now = FieldValue.serverTimestamp();
      final userRef = _firestore.collection('users').doc(user.id);
      DocumentSnapshot<Map<String, dynamic>>? existingDoc;
      try {
        existingDoc =
            await userRef.get(const GetOptions(source: Source.server));
      } catch (e) {
        if (kDebugMode) {
          print(
              'DEBUG: ⚠️ Lettura server utente fallita, salvo solo metadata: $e');
        }
      }

      if (existingDoc == null || existingDoc.exists) {
        await _saveUserProfileMetadataToFirestore(user);
        return;
      }

      await userRef.set({
        'userId': user.id,
        'email': user.email,
        'normalizedEmail': user.email.toLowerCase().trim(),
        'name': user.name,
        'username': user.username,
        'app_id': 'savein',
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
        'birthDate':
            user.birthDate != null ? Timestamp.fromDate(user.birthDate!) : null,
        'gender': user.gender,
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

  Future<void> _saveUserProfileMetadataToFirestore(User user) async {
    final now = FieldValue.serverTimestamp();
    await _firestore.collection('users').doc(user.id).set({
      'userId': user.id,
      'email': user.email,
      'normalizedEmail': user.email.toLowerCase().trim(),
      'name': user.name,
      'username': user.username,
      'app_id': 'savein',
      'lastLogin': now,
      'birthDate':
          user.birthDate != null ? Timestamp.fromDate(user.birthDate!) : null,
      'gender': user.gender,
    }, SetOptions(merge: true));
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
        'consents': {
          'marketing': {
            'accepted': consent,
            'lastModified': now,
            'modifiedBy': 'user',
            'version': '1.0',
          }
        },
        'lastLogin': now,
      }, SetOptions(merge: true));

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
            data['consents']?['marketing']?['accepted'] ?? true;

        if (kDebugMode) {
          print('DEBUG: Consenso da Firestore: $marketingConsent');
          print('DEBUG: Consenso locale: ${_currentUser?.acceptedMarketing}');
        }

        if (_currentUser != null &&
            _currentUser!.acceptedMarketing != marketingConsent) {
          if (kDebugMode) {
            print('DEBUG: ⚠️ Consenso marketing diverso, sincronizzando...');
          }

          _currentUser =
              _currentUser!.copyWith(acceptedMarketing: marketingConsent);

          await _saveUserLocally(_currentUser!);
          notifyListeners();

          if (kDebugMode) {
            print('DEBUG: ✅ Consenso marketing sincronizzato da cloud');
          }
        } else {
          if (kDebugMode)
            print('DEBUG: ✅ Consenso marketing già sincronizzato');
        }
      } else {
        if (kDebugMode)
          print('DEBUG: ℹ️ Nessun documento Firestore, salvo solo metadata');
        if (_currentUser != null) {
          await _saveUserProfileMetadataToFirestore(_currentUser!);
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
    if (_currentUser!.dashboardRole == dashboardRole) {
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
    final firebaseEmail = _normalizeEmail(firebaseUser.email ?? '');

    // Carica subito dalla cache locale per non mostrare Free durante il fetch Firestore
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_${firebaseUser.uid}');
      if (userData != null) {
        final cachedUser = User.fromJson(jsonDecode(userData));
        if (cachedUser.id == firebaseUser.uid &&
            _normalizeEmail(cachedUser.email) == firebaseEmail) {
          _currentUser = cachedUser;
          print('DEBUG: ✅ Dati utente caricati da storage locale (anticipato)');
        }
      }
    } catch (_) {}

    try {
      print(
          'DEBUG: 🔧 Caricamento dati utente da Firestore: ${firebaseUser.email}');

      final (firestoreDoc, fromServer) =
          await _fetchUserDocument(firebaseUser.uid);

      // Completamente offline: usa la cache locale già caricata
      if (firestoreDoc == null) {
        print('DEBUG: ⚠️ Firestore non raggiungibile: uso cache locale');
        if (_currentUser != null && _currentUser!.id == firebaseUser.uid) {
          _ensureUserProfileSync(firebaseUser.uid);
          return;
        }
        // Nessuna cache disponibile: utente temporaneo Free, il listener aggiornerà
        _currentUser = User(
          id: firebaseUser.uid,
          name: firebaseUser.displayName ?? 'Utente',
          email: firebaseUser.email ?? '',
          username: null,
          role: AppUserRole.free,
          isBlocked: false,
          acceptedTerms: true,
          acceptedPrivacy: true,
          acceptedMarketing: true,
          createdAt: DateTime.now(),
        );
        _ensureUserProfileSync(firebaseUser.uid);
        return;
      }

      final firestoreData = firestoreDoc.data();

      if (!firestoreDoc.exists || firestoreData == null) {
        // Il documento non esiste secondo il server → account cancellato
        // Disconnetti solo se il dato è dal server (non da cache stale)
        if (!fromServer) {
          print(
              'DEBUG: ⚠️ Cache locale non ha il documento, ignoro (potrebbe essere stale)');
          if (_currentUser != null && _currentUser!.id == firebaseUser.uid) {
            _ensureUserProfileSync(firebaseUser.uid);
            return;
          }
        }
        print(
            'DEBUG: ⚠️ Documento utente mancante su Firestore: sessione locale eliminata');
        _currentUser = null;
        await _clearLocalData();
        try {
          await _firebaseAuth.signOut();
        } catch (_) {}
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        notifyListeners();
        return;
      }

      final loadedUser = _userFromFirestoreData(
        firebaseUser,
        firestoreData,
        firestoreDoc.id,
        fallback: _currentUser,
      );

      // Protezione anti-downgrade: non ridurre il ruolo usando dati dalla cache
      // locale (che potrebbe essere stale). Il listener real-time aggiornerà
      // quando il server sarà raggiungibile.
      final currentRole = _currentUser?.effectiveRole ?? AppUserRole.free;
      final loadedRole = loadedUser.effectiveRole;
      final isDowngrade =
          currentRole == AppUserRole.premium && loadedRole == AppUserRole.free;
      if (isDowngrade && !fromServer) {
        print(
            'DEBUG: ⚠️ Downgrade Premium→Free da cache stale ignorato, aspetto server');
        _ensureUserProfileSync(firebaseUser.uid);
        return;
      }

      _currentUser = loadedUser;
      await _saveUserLocally(_currentUser!);
      _startUserProfileSync(firebaseUser.uid);
      print(
          'DEBUG: ✅ Dati utente caricati/sincronizzati da Firestore (fromServer=$fromServer)');

      if (_currentUser?.id != firebaseUser.uid ||
          _normalizeEmail(_currentUser?.email ?? '') != firebaseEmail) {
        await _firebaseAuth.signOut();
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        _currentUser = null;
        notifyListeners();
        throw StateError('Utente autenticato non coerente con i dati locali');
      }

      // Sincronizza da Firestore per aggiornare ruolo, blocco, consenso marketing.
      // Essenziale per utenti il cui ruolo è stato cambiato dall'admin dashboard.
      await _loadMarketingConsentFromFirestore();
      await _syncDashboardAccessRoleFromFirestore();
      await _claimPendingSmartChefLaunchPromoIfAvailable();
      await syncNewSignupPremiumPromoFromServer();
    } catch (e) {
      print('ERRORE caricamento dati utente: $e');
      if (_currentUser != null && _currentUser!.id == firebaseUser.uid) {
        _ensureUserProfileSync(firebaseUser.uid);
        return;
      }
      // Anche nel catch, mai creare utente Free se c'è già un utente valido in cache
      _currentUser = User(
        id: firebaseUser.uid,
        name: firebaseUser.displayName ?? 'Utente',
        email: firebaseUser.email ?? '',
        username: null,
        role: AppUserRole.free,
        isBlocked: false,
        acceptedTerms: true,
        acceptedPrivacy: true,
        acceptedMarketing: true,
        createdAt: DateTime.now(),
      );
      _ensureUserProfileSync(firebaseUser.uid);
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

  Future<void> _clearLocalData({
    bool preserveUserProfileCache = false,
    String? deletedUserId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = (deletedUserId ?? '').trim();
      final userScopedPrefixes = uid.isEmpty
          ? const <String>[]
          : <String>[
              'user_$uid',
              'sc_stats_v1_$uid',
              'simple_stats_$uid',
              'analytics_$uid',
              'advanced_analytics_$uid',
              'folder_stats_$uid',
              'migration_$uid',
            ];
      final keys = prefs.getKeys().where((key) {
        if (preserveUserProfileCache && key.startsWith('user_')) {
          return false;
        }
        return key.startsWith('user_') ||
            userScopedPrefixes.any((prefix) => key.startsWith(prefix)) ||
            key == 'simple_analytics_events' ||
            key == 'total_time_milliseconds' ||
            key == 'last_session_end_time' ||
            key == 'advanced_analytics_events' ||
            key == 'user_sessions' ||
            key == 'content_interactions' ||
            key == 'cached_advanced_stats' ||
            key == 'last_user_id' ||
            key == 'is_logged_in';
      }).toList();

      for (String key in keys) {
        await prefs.remove(key);
      }

      print('DEBUG: 🗑️ Dati utente locali puliti');
    } catch (e) {
      print('ERRORE pulizia dati: $e');
    }
  }

  Future<void> _clearAnalyticsServices() async {
    try {
      await SimpleAnalyticsService().clearLocalAnalyticsData();
    } catch (_) {}
    try {
      await AdvancedAnalyticsService().clearLocalAnalyticsData();
    } catch (_) {}
  }

  Future<bool> updateOwnRole(AppUserRole role) async {
    if (kDebugMode) {
      print(
          'DEBUG: Cambio piano ignorato: il ruolo utente e gestito da dashboard/backend.');
    }
    return false;
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
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final result = CrossPromotionResult.fromMap(data);

    return result;
  }

  Future<NewSignupPremiumPromoConfig?> getNewSignupPremiumPromoConfig() async {
    final eligibility = await getNewSignupPremiumPromoEligibility();
    return eligibility.active ? eligibility.config : null;
  }

  Future<bool> shouldShowNewSignupPremiumPromo() async {
    final user = _currentUser;
    if (user == null || user.effectiveRole != AppUserRole.free) return false;
    final eligibility = await getNewSignupPremiumPromoEligibility();
    if (eligibility.restored) return false;
    if (!eligibility.canClaim) return false;

    final doc = await _firestore.collection('users').doc(user.id).get();
    final data = doc.data() ?? <String, dynamic>{};
    final createdAt =
        _dateFromFirestoreValue(data['createdAt']) ?? user.createdAt;
    final age = DateTime.now().difference(createdAt);
    if (age.inDays > 7) return false;

    if (data['newSignupPremiumPromoClaimedAt'] != null ||
        data['newSignupPremiumPromoDismissedAt'] != null) {
      return false;
    }
    return true;
  }

  Future<bool> canClaimNewSignupPremiumPromo() async {
    final eligibility = await getNewSignupPremiumPromoEligibility();
    return eligibility.canClaim;
  }

  Future<NewSignupPremiumPromoEligibility>
      getNewSignupPremiumPromoEligibility() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null || _currentUser == null) {
      return const NewSignupPremiumPromoEligibility(
        active: false,
        canClaim: false,
        alreadyClaimed: false,
        restored: false,
        expired: false,
        durationDays: 30,
        priceAfterTrial: '2.99',
      );
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'getNewSignupPremiumPromoEligibility',
    );
    final response = await callable.call(<String, dynamic>{});
    final raw = response.data;
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final eligibility = NewSignupPremiumPromoEligibility.fromMap(data);

    if (eligibility.restored && eligibility.premiumUntil != null) {
      _currentUser = _currentUser!.copyWith(
        role: AppUserRole.premium,
        premiumUntil: eligibility.premiumUntil,
        premiumSource: 'new_signup_promo',
      );
      await _saveUserLocally(_currentUser!);
      notifyListeners();
    }
    return eligibility;
  }

  Future<void> syncNewSignupPremiumPromoFromServer() async {
    final user = _currentUser;
    if (user == null || user.isAdmin) return;
    await getNewSignupPremiumPromoEligibility();
  }

  Future<DateTime> activateNewSignupPremiumPromo() async {
    final user = _currentUser;
    if (user == null) {
      throw Exception('Devi essere autenticato per attivare la promo.');
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'activateNewSignupPremiumPromo',
    );
    final response = await callable.call(<String, dynamic>{});
    final raw = response.data;
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final premiumUntil =
        DateTime.parse(data['premiumUntil'].toString()).toLocal();

    _currentUser = user.copyWith(
      role: AppUserRole.premium,
      premiumUntil: premiumUntil,
      premiumSource: 'new_signup_promo',
    );
    await _saveUserLocally(_currentUser!);
    notifyListeners();
    return premiumUntil;
  }

  Future<void> dismissNewSignupPremiumPromo() async {
    final user = _currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.id).set({
      'newSignupPremiumPromoDismissedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<PromotionBanner?> getActivePromotionBanner() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      if (kDebugMode)
        print('DEBUG: banner promo non caricato: utente Firebase nullo');
      return null;
    }
    final callable = FirebaseFunctions.instance.httpsCallable(
      'getActivePromotionBanner',
    );
    final response = await callable.call(<String, dynamic>{});
    final raw = response.data;
    if (kDebugMode) print('DEBUG: risposta getActivePromotionBanner: $raw');
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final bannerRaw = data['banner'];
    if (bannerRaw is! Map) {
      if (kDebugMode) print('DEBUG: nessun banner promo attivo ricevuto');
      return null;
    }
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
    if (_currentUser == null ||
        _currentUser!.isAdmin ||
        !_currentUser!.isFree) {
      return;
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'claimPendingSmartChefLaunchPromo',
      );
      final response = await callable.call(<String, dynamic>{});
      final raw = response.data;
      final data =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
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

  Future<bool> updateUserPremiumUntil({
    required String userId,
    required DateTime? premiumUntil,
  }) async {
    if (_currentUser == null || !_currentUser!.canManageUserRoles) {
      throw Exception('Solo un admin può gestire la scadenza Premium.');
    }

    final userDoc = await _firestore.collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw Exception('Utente non trovato.');
    }

    final userData = userDoc.data() ?? <String, dynamic>{};
    final previousRole = AppUserRoleX.fromValue(userData['role'] as String?);
    final willBecomePremium =
        premiumUntil != null && previousRole != AppUserRole.premium;
    final update = <String, dynamic>{
      'premiumUntil': premiumUntil == null
          ? FieldValue.delete()
          : Timestamp.fromDate(premiumUntil),
      'premiumSource':
          premiumUntil == null ? FieldValue.delete() : 'admin_dashboard',
      'premiumUpdatedAt': FieldValue.serverTimestamp(),
      'premiumUpdatedBy': _currentUser!.id,
      if (premiumUntil != null) 'role': AppUserRole.premium.value,
      if (premiumUntil != null) 'roleUpdatedAt': FieldValue.serverTimestamp(),
      if (premiumUntil != null) 'roleUpdatedBy': _currentUser!.id,
    };

    await _firestore.collection('users').doc(userId).set(
          update,
          SetOptions(merge: true),
        );

    await _writeAccountHistory(
      targetUserId: userId,
      type: 'premium_expiry_changed',
      title: premiumUntil == null
          ? 'Scadenza Premium rimossa'
          : 'Scadenza Premium aggiornata',
      before: {
        'role': (userData['role'] as String?) ?? '',
        'premiumUntil': userData['premiumUntil'],
      },
      after: {
        'role': premiumUntil == null
            ? ((userData['role'] as String?) ?? '')
            : AppUserRole.premium.value,
        'premiumUntil':
            premiumUntil == null ? null : Timestamp.fromDate(premiumUntil),
      },
      source: 'admin_dashboard',
    );

    if (willBecomePremium) {
      await _writeAccountHistory(
        targetUserId: userId,
        type: 'role_changed',
        title: 'Passaggio a premium',
        before: {
          'role': previousRole.value,
          'premiumUntil': userData['premiumUntil'],
        },
        after: {
          'role': AppUserRole.premium.value,
          'premiumUntil': Timestamp.fromDate(premiumUntil),
        },
        source: 'admin_dashboard',
      );
      await _writeAdminLog(
        action: 'role_changed',
        targetUserId: userId,
        details: {
          'oldRole': previousRole.value,
          'newRole': AppUserRole.premium.value,
          'premiumUntil': premiumUntil.toIso8601String(),
        },
      );
    }

    await _writeAdminLog(
      action: 'premium_expiry_changed',
      targetUserId: userId,
      details: {
        'oldRole': previousRole.value,
        'newRole': premiumUntil == null
            ? ((userData['role'] as String?) ?? '')
            : AppUserRole.premium.value,
        'premiumUntil': premiumUntil?.toIso8601String(),
      },
    );

    if (userId == _currentUser!.id) {
      await reloadCurrentUserFromFirestore();
    }

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
    String? password,
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

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'upsertDashboardLoginAccess',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    await callable.call(<String, dynamic>{
      'email': normalizedEmail,
      'dashboardRole': dashboardRole.value,
      if (password != null && password.isNotEmpty) 'password': password,
    });

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

  Future<bool> _upsertDashboardAccessRoleOnly({
    required String email,
    required DashboardAccessRole dashboardRole,
  }) async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'upsertDashboardLoginAccess',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    await callable.call(<String, dynamic>{
      'email': email,
      'dashboardRole': dashboardRole.value,
    });

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

    await _upsertDashboardAccessRoleOnly(
      email: normalizedEmail,
      dashboardRole: dashboardRole,
    );

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

    final currentPremiumUntil =
        _dateFromFirestoreValue(targetData['premiumUntil']);
    final hasActivePremiumUntil = User._isPremiumExpiryActive(
      currentPremiumUntil,
    );

    await _firestore.collection('users').doc(userId).set({
      'role': role.value,
      if (role == AppUserRole.free) 'premiumUntil': FieldValue.delete(),
      if (role == AppUserRole.free) 'premiumSource': FieldValue.delete(),
      if (role == AppUserRole.premium && !hasActivePremiumUntil)
        'premiumUntil': FieldValue.delete(),
      if (role == AppUserRole.premium && !hasActivePremiumUntil)
        'premiumSource': FieldValue.delete(),
      'roleUpdatedAt': FieldValue.serverTimestamp(),
      'roleUpdatedBy': _currentUser!.id,
      if (normalizedEmail != null && normalizedEmail.isNotEmpty)
        'normalizedEmail': normalizedEmail,
    }, SetOptions(merge: true));

    await _writeAccountHistory(
      targetUserId: userId,
      type: 'role_changed',
      title: 'Passaggio a ${role.value}',
      before: {
        'role': targetData['role'],
        'premiumUntil': targetData['premiumUntil'],
      },
      after: {
        'role': role.value,
        if (role == AppUserRole.free) 'premiumUntil': null,
      },
      source: 'admin_dashboard',
    );

    await _writeAdminLog(
      action: 'role_changed',
      targetUserId: userId,
      details: {
        'oldRole': (targetData['role'] as String?) ?? '',
        'newRole': role.value,
      },
    );

    if (userId == _currentUser!.id) {
      _currentUser = _currentUser!.copyWith(
        role: role,
        clearPremiumUntil: role == AppUserRole.free ||
            (role == AppUserRole.premium && !hasActivePremiumUntil),
        clearPremiumSource: role == AppUserRole.free ||
            (role == AppUserRole.premium && !hasActivePremiumUntil),
        premiumUntil: role == AppUserRole.premium && hasActivePremiumUntil
            ? currentPremiumUntil
            : null,
        premiumSource: role == AppUserRole.premium && hasActivePremiumUntil
            ? targetData['premiumSource'] as String?
            : null,
      );
      await _saveUserLocally(_currentUser!);
      notifyListeners();
      onUserProfileChanged?.call();
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

  Future<void> _writeAccountHistory({
    required String targetUserId,
    required String type,
    required String title,
    String source = '',
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) async {
    try {
      final actor = _currentUser;
      await _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('account_history')
          .add({
        'type': type,
        'title': title,
        'source': source,
        'actorUserId': actor?.id,
        'actorEmail': actor?.email,
        'before': before ?? <String, dynamic>{},
        'after': after ?? <String, dynamic>{},
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Lo storico non deve bloccare l'azione admin principale.
    }
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

    try {
      await _firestore.collection('admin_logs').add({
        'action': action,
        'targetUserId': targetUserId,
        'actorUserId': actor.id,
        'actorEmail': actor.email,
        'timestamp': FieldValue.serverTimestamp(),
        'details': details ?? <String, dynamic>{},
      });
    } catch (_) {
      // Il log non deve bloccare l'azione admin principale.
    }
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
    DateTime? birthDate,
    String? gender,
  }) async {
    if (_currentUser == null) return false;

    try {
      if (name != null && name != _currentUser!.name) {
        await _firebaseAuth.currentUser?.updateDisplayName(name);
      }

      final lockedBirthDate = _currentUser!.birthDate;
      final lockedGender = (_currentUser!.gender ?? '').trim().isNotEmpty
          ? _currentUser!.gender
          : null;

      _currentUser = _currentUser!.copyWith(
        name: name,
        username: username,
        birthDate: lockedBirthDate ?? birthDate,
        gender: lockedGender ?? gender,
      );

      await _saveUserLocally(_currentUser!);

      // ✅ Sync con Firestore
      if (_firebaseAuth.currentUser != null) {
        await _firestore.collection('users').doc(_currentUser!.id).update({
          'name': _currentUser!.name,
          'username': _currentUser!.username,
          'normalizedEmail': _currentUser!.email.toLowerCase().trim(),
          'birthDate': _currentUser!.birthDate != null
              ? Timestamp.fromDate(_currentUser!.birthDate!)
              : null,
          'gender': _currentUser!.gender,
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
    DateTime? birthDate,
    String? gender,
    required String newPassword,
  }) async {
    if (_currentUser == null || _firebaseAuth.currentUser == null) return false;

    try {
      await _firebaseAuth.currentUser!.updatePassword(newPassword);
      await updateUserProfile(
        name: name,
        username: username,
        birthDate: birthDate,
        gender: gender,
      );

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
      await callable
          .call(<String, dynamic>{'email': email.trim().toLowerCase()});
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
