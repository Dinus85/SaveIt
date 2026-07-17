import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:savein/firebase_options.dart';
import 'package:savein/advanced_analytics_service.dart';

import 'package:savein/models/folder.dart';
import 'package:savein/models.dart' show Folder, MockPost, Reminder;
import 'package:savein/widgets/folder_card.dart';
import 'package:savein/widgets/search_results_widget.dart';
import 'package:savein/pages/folder_detail_page.dart';
import 'package:savein/pages/account_page.dart';
import 'package:savein/services/folder_service.dart';
import 'package:savein/services/simple_analytics_service.dart';
import 'package:savein/services/interstitial_ad_service.dart';
import 'package:savein/services/access_control_service.dart';
import 'package:savein/widgets/banner_ad_widget.dart';
import 'package:savein/services/auth_service.dart';
import 'package:savein/widgets/custom_bottom_nav.dart';
import 'package:savein/services/sharing_service.dart';
import 'package:savein/services/share_extension_service.dart';
import 'package:savein/widgets/new_signup_premium_promo_dialog.dart';
import 'package:savein/utils/theme_helpers.dart';
import 'package:savein/utils/dialog_helpers.dart';
import 'package:savein/utils/sync_utilities.dart';
import 'package:savein/pages/auth_wrapper.dart';
import 'package:savein/pages/shared_items_page.dart'; // NUOVO
import 'package:savein/pages/shared_link_page.dart';
import 'package:savein/data_service.dart';
import 'package:savein/services/app_notification_service.dart';
import 'package:savein/services/reminder_service.dart';
import 'package:savein/services/plan_limits_service.dart';
import 'package:savein/widgets/first_launch_tutorial_dialog.dart';
import 'package:savein/services/promo_popup_service.dart';
import 'package:savein/services/app_config_service.dart';
import 'package:savein/pages/force_update_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Notifier usato per triggerare l'highlight di una cartella root nella Home
/// dopo un pop di tutte le route (reminder su cartella root).
final ValueNotifier<String?> homeHighlightFolderNotifier = ValueNotifier(null);

Future<void> openReminderTargetInApp({
  String? postId,
  String? folderId,
}) async {
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return;

  final folderService = FolderService();
  final isPostReminder = postId != null && postId.isNotEmpty;

  if (!folderService.isInitialized) {
    await folderService.initializeFolders();
  }
  if (isPostReminder || (folderId != null && folderId.isNotEmpty)) {
    try {
      await folderService.syncWithDataService();
    } catch (_) {}
  }

  MockFolder? findFolderById(String? id) {
    if (id == null || id.isEmpty) return null;

    MockFolder? found;
    void visit(MockFolder folder) {
      if (found != null) return;
      if (folder.id == id) {
        found = folder;
        return;
      }
      for (final child in folder.children) {
        visit(child);
      }
    }

    for (final folder in folderService.folders) {
      visit(folder);
    }
    return found;
  }

  MockPost? targetPost;
  if (isPostReminder) {
    try {
      targetPost =
          folderService.allPosts.firstWhere((post) => post.id == postId);
    } catch (_) {
      targetPost = null;
    }
  }

  final folderReminderTarget =
      !isPostReminder && targetPost == null ? findFolderById(folderId) : null;
  final postFolderTarget = isPostReminder
      ? (targetPost?.sourceFolder ?? findFolderById(folderId))
      : null;

  // Caso speciale: reminder su cartella ROOT (in Home, parent == null).
  // → Torniamo alla Home e triggeriamo l'highlight lì via notifier.
  if (!isPostReminder &&
      folderReminderTarget != null &&
      folderReminderTarget.parent == null) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    // Piccolo delay per dare tempo alla Home di essere visibile
    await Future.delayed(const Duration(milliseconds: 150));
    homeHighlightFolderNotifier.value =
        null; // reset per forzare il notify anche se stesso id
    await Future.delayed(const Duration(milliseconds: 50));
    homeHighlightFolderNotifier.value = folderReminderTarget.id;
    return;
  }

  // Per i reminder su subfolder: apriamo il parent e evidenziamo la subfolder
  // Per i reminder su post: apriamo la cartella del post
  final targetFolder =
      isPostReminder ? postFolderTarget : folderReminderTarget?.parent;

  final String? highlightFolderIdForNav =
      !isPostReminder ? folderReminderTarget?.id : null;

  if (targetFolder == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Il contenuto del reminder non è più disponibile.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FolderDetailPage(
        folder: targetFolder,
        isDarkTheme: Theme.of(context).brightness == Brightness.dark,
        allFolders: folderService.folders,
        onFolderUpdated: () {},
        highlightPostId: isPostReminder ? postId : null,
        highlightFolderId: highlightFolderIdForNav,
      ),
    ),
  );
}

// FUNZIONE DEBUG TOKEN - Solo in modalitÃ  debug
Future<void> debugAuthTokenStatus() async {
  if (!kDebugMode) return; // Skip in produzione

  try {
    print('=== DEBUG TOKEN STATUS ===');
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      print('âŒ ERRORE: Nessun utente autenticato');
      return;
    }

    print('âœ… Utente: ${firebaseUser.email}');
    print('âœ… UID: ${firebaseUser.uid}');

    try {
      final token = await firebaseUser.getIdToken(false);
      print('âœ… Token ottenuto');
      final freshToken = await firebaseUser.getIdToken(true);
      print('âœ… TOKEN REFRESH COMPLETATO');
    } catch (tokenError) {
      print('âŒ ERRORE TOKEN: $tokenError');
    }
    print('========================');
  } catch (e) {
    print('âŒ ERRORE DEBUG: $e');
  }
}

Future<bool> forceRefreshAuthToken() async {
  try {
    if (kDebugMode) print('ðŸ”„ Forzando refresh token...');
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.getIdToken(true);
      if (kDebugMode) print('âœ… Token refreshato');
      return true;
    }
    return false;
  } catch (e) {
    if (kDebugMode) print('âŒ Token refresh fallito: $e');
    return false;
  }
}

Future<void> forceReauth() async {
  try {
    if (kDebugMode) print('ðŸ”„ Forzando ri-autenticazione...');
    final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await firebase_auth.FirebaseAuth.instance.signOut();
      if (kDebugMode) print('âœ… Logout completato');
    }
  } catch (e) {
    if (kDebugMode) print('âŒ Errore durante ri-autenticazione: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  AppNotificationService.registerBackgroundHandler();

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await AuthService().initialize();

  ReminderService.onNotificationTapped = (postId, postTitle, folderId) async {
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      await InterstitialAdService.instance.showReminderOpenGate(context);
    }
    await openReminderTargetInApp(postId: postId, folderId: folderId);
  };

  ReminderService.onFolderNotificationTapped = (folderId, folderName) async {
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      await InterstitialAdService.instance.showReminderOpenGate(context);
    }
    await openReminderTargetInApp(folderId: folderId);
  };

  runApp(const SaveInApp());

  unawaited(_initializeNonBlockingStartupServices());

  // Test immagini solo in debug mode
  if (kDebugMode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _testImagePreviewFunctionality();
    });
  }
}

Future<void> _initializeNonBlockingStartupServices() async {
  try {
    await InterstitialAdService.instance.initialize().timeout(
          const Duration(seconds: 5),
        );
  } catch (e) {
    if (kDebugMode) {
      print('DEBUG: inizializzazione AdMob non bloccante fallita: $e');
    }
  }

  try {
    await ReminderService.instance.initialize().timeout(
          const Duration(seconds: 5),
        );
  } catch (e) {
    if (kDebugMode) {
      print('DEBUG: inizializzazione reminder non bloccante fallita: $e');
    }
  }
}

void _testImagePreviewFunctionality() {
  if (!kDebugMode) return;

  try {
    final folderService = FolderService();
    print('========== TEST ANTEPRIMA IMMAGINI ==========');
    folderService.testImagePreviewFunctionality();
    final totalWithImages = folderService.getTotalPostsWithImages();
    print('Post totali con immagini: $totalWithImages');
    print('=============================================');
  } catch (e) {
    print('ERRORE: Test anteprima immagini fallito: $e');
  }
}

class SaveInApp extends StatefulWidget {
  const SaveInApp({super.key});

  @override
  _SaveInAppState createState() => _SaveInAppState();
}

class _SaveInAppState extends State<SaveInApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _marketingProfileEnabled = false;
  bool _marketingCommsEnabled = false;

  final SimpleAnalyticsService _analytics = SimpleAnalyticsService();
  final SharingService _sharingService = SharingService.instance;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _appLinkSubscription;

  bool get _isDarkTheme => _themeMode == ThemeMode.dark;

  bool _wasInBackground = false;
  DateTime? _lastBackgroundTime;
  Widget? _forcedGate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _initAppLinks();
    _loadUserPreferences(); // âœ… AGGIUNGI QUESTA RIGA
    if (!kIsWeb) {
      _checkForcedGateInBackground();
    }
  }

  Future<Widget?> _maybeBuildForcedGate() async {
    final cfg = await AppConfigService.fetch();
    final build = await AppConfigService.currentBuildNumber();
    final minBuild = cfg.minBuildForCurrentPlatform();
    final storeUrl = cfg.storeUrlForCurrentPlatform();

    if (cfg.maintenance) {
      return ForceUpdatePage(
        title: 'Manutenzione in corso',
        message: cfg.message.isNotEmpty
            ? cfg.message
            : 'Stiamo aggiornando SaveIn!. Riprova tra poco.',
        storeUrl: storeUrl,
        showExitHint: false,
      );
    }

    if (minBuild > 0 && build > 0 && build < minBuild) {
      return ForceUpdatePage(
        title: 'Aggiornamento richiesto',
        message: cfg.message.isNotEmpty
            ? cfg.message
            : 'Per continuare devi aggiornare SaveIn! alla versione più recente.',
        storeUrl: storeUrl,
      );
    }

    return null;
  }

  Future<void> _checkForcedGateInBackground() async {
    final forced = await _maybeBuildForcedGate();
    if (!mounted || forced == null) return;
    setState(() => _forcedGate = forced);
  }

  Future<void> _initAppLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleAppLink(initialUri);
      }
      _appLinkSubscription = _appLinks.uriLinkStream.listen(
        _handleAppLink,
        onError: (error) {
          if (kDebugMode) DebugLogger.logError('App link SaveIn', error);
        },
      );
    } catch (e) {
      if (kDebugMode) DebugLogger.logError('Inizializzazione app links', e);
    }
  }

  void _handleAppLink(Uri uri) {
    if (uri.host != 'savein.eu' || uri.pathSegments.length < 2) return;
    if (uri.pathSegments.first != 's') return;
    final token = uri.pathSegments[1].trim();
    if (token.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SharedLinkPage(
            token: token,
            isDarkTheme: _isDarkTheme,
          ),
        ),
      );
    });
  }

  Future<void> _loadUserPreferences() async {
    try {
      print('DEBUG: ðŸ“‹ Caricamento preferenze utente...');

      // Attendi che AuthService sia completamente inizializzato
      await Future.delayed(Duration(milliseconds: 100));

      // Ottieni l'utente corrente da AuthService
      final currentUser = AuthService().currentUser;

      if (currentUser != null) {
        print('DEBUG: Utente trovato: ${currentUser.email}');
        print(
            'DEBUG: Consenso marketing salvato: ${currentUser.acceptedMarketing}');

        // 🔥 FIX: Controlla mounted prima di setState
        if (mounted) {
          setState(() {
            _marketingCommsEnabled = currentUser.acceptedMarketing;
            _marketingProfileEnabled = currentUser.acceptedMarketing;
          });
        }

        print(
            'DEBUG: âœ… Preferenze marketing caricate: $_marketingCommsEnabled');
      } else {
        print(
            'DEBUG: âš ï¸ Nessun utente autenticato, usando valori di default');
      }
    } catch (e) {
      print('DEBUG: âŒ Errore caricamento preferenze: $e');
      // In caso di errore, mantieni i valori di default (false)
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // âœ… Salva entrambe le sessioni
    _analytics.endSession();

    // âœ… NUOVO: Salva anche sessione avanzata (backup safety)
    try {
      final advancedAnalytics = AdvancedAnalyticsService();
      advancedAnalytics.endSmartSession();
    } catch (e) {
      print('DEBUG: Errore chiusura advanced analytics: $e');
    }

    _sharingService.dispose();
    _appLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (kDebugMode) print('DEBUG: Lifecycle cambiato a: $state');

    if (state == AppLifecycleState.paused) {
      _wasInBackground = true;
      _lastBackgroundTime = DateTime.now();
      _analytics.endSession();
      unawaited(ShareExtensionService.instance.exportCatalog());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(
        ShareExtensionService.instance.refreshCatalogAndImport(),
      );

      if (_wasInBackground) {
        _wasInBackground = false;
        if (kDebugMode) {
          print('DEBUG: App resumed - sincronizzo profilo utente da Firestore');
        }
        unawaited(AuthService().reloadCurrentUserFromFirestore());

        // Cross-device: post/anteprime salvati da iOS devono apparire
        // subito anche su Android (e viceversa) senza pull-to-refresh.
        final backgroundedAt = _lastBackgroundTime;
        final shouldRefreshPosts = backgroundedAt == null ||
            DateTime.now().difference(backgroundedAt) >
                const Duration(seconds: 2);
        if (shouldRefreshPosts &&
            firebase_auth.FirebaseAuth.instance.currentUser != null) {
          unawaited(_refreshContentAfterResume());
        }
      }
    }
  }

  Future<void> _refreshContentAfterResume() async {
    try {
      await FolderService().handleAppResumed();
      SharingService.notifyDataChangedFromExternal();
      if (kDebugMode) {
        print('DEBUG: Resume sync post/cartelle completato');
      }
    } catch (error) {
      if (kDebugMode) {
        print('DEBUG: Resume sync post/cartelle fallito: $error');
      }
    }
  }

  Future<void> _initServices() async {
    try {
      if (kDebugMode) DebugLogger.logStart('Inizializzazione servizi app');

      await _analytics.initialize();

      AuthService().onUserProfileChanged = () {
        PlanLimitsService.invalidateUsageCache();
        unawaited(
          ShareExtensionService.instance.refreshCatalogAndImport(),
        );
      };

      // Pre-carica i limiti e l'utilizzo per velocizzare i controlli UI
      PlanLimitsService.startLiveSync();
      unawaited(PlanLimitsService.getUsage(forceRefresh: true));

      _sharingService.initialize(
        onSharedContent: _handleSharedContent,
      );
      unawaited(
        ShareExtensionService.instance.refreshCatalogAndImport(),
      );

      if (kDebugMode) DebugLogger.logSuccess('Tutti i servizi inizializzati');
    } catch (e) {
      if (kDebugMode) DebugLogger.logError('Inizializzazione servizi', e);
    }
  }

  void _handleSharedContent(SharedContent sharedContent) {
    if (kDebugMode) {
      DebugLogger.logStart(
          '========== CONTENUTO CONDIVISO RICEVUTO ==========');
      DebugLogger.log('URL: ${sharedContent.url}');
      DebugLogger.log('Hashtag: ${sharedContent.extractedHashtags.length}');
    }

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showSharingDialog(sharedContent);
    });
  }

// ðŸ”¥ SOSTITUISCI il metodo _showSharingDialog in main.dart con questo

  void _showSharingDialog(SharedContent sharedContent) {
    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) return;

    final isLoggedIn = AuthService().isLoggedIn;

    if (!isLoggedIn) {
      _showLoginRequiredDialog(context, sharedContent);
      return;
    }

    try {
      SharingService.showSaveDialog(
        context,
        sharedContent,
        isDarkTheme: _isDarkTheme,
      ).then((result) async {
        // ðŸ”¥ NUOVO: Se result non Ã¨ null, significa che il salvataggio Ã¨ andato a buon fine
        if (result != null && result['folderPath'] != null) {
          print('DEBUG: ðŸ“ Post salvato, preparando navigazione...');
          print('DEBUG: Cartella: ${result['folderPath']}');

          // Naviga subito; sincronizzazione in background
          try {
            FolderService().syncWithDataService();
          } catch (_) {}
          _navigateToSavedFolder(result['folderPath']!, result['postId']!);
        }
      }).catchError((error) {
        if (kDebugMode)
          DebugLogger.logError('Dialog salvataggio fallito', error);
      });
    } catch (e) {
      if (kDebugMode) DebugLogger.logError('Eccezione in showSaveDialog', e);
    }
  }

  void _showLoginRequiredDialog(
      BuildContext context, SharedContent sharedContent) {
    final hasHashtags = sharedContent.extractedHashtags.isNotEmpty;
    final contentDescription = hasHashtags
        ? 'contenuto condiviso con ${sharedContent.extractedHashtags.length} hashtag'
        : 'contenuto condiviso';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkTheme ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text(
              'Login richiesto',
              style: TextStyle(
                color: _isDarkTheme ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Per salvare $contentDescription Ã¨ necessario essere autenticati.',
          style: TextStyle(
            color: _isDarkTheme ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annulla',
              style: TextStyle(
                color: _isDarkTheme ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toggleTheme(bool isDark) {
    // 🔥 FIX: Controlla mounted prima di setState
    if (!mounted) return;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    _analytics.trackThemeChanged(isDark);
  }

  void _toggleMarketingProfile(bool enabled) {
    // 🔥 FIX: Controlla mounted prima di setState
    if (!mounted) return;
    setState(() {
      _marketingProfileEnabled = enabled;
    });
  }

  void _toggleMarketingComms(bool enabled) {
    // 🔥 FIX: Controlla mounted prima di setState
    if (!mounted) return;
    print('DEBUG: ðŸ”„ Toggle marketing comms chiamato: $enabled');
    setState(() {
      _marketingCommsEnabled = enabled;
    });
    print(
        'DEBUG: âœ… Stato marketing comms aggiornato in main.dart: $_marketingCommsEnabled');
    // Il salvataggio effettivo Ã¨ gestito da account_page.dart tramite AuthService
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaveIn!',
      theme: ThemeHelpers.createLightTheme(),
      darkTheme: ThemeHelpers.createDarkTheme(),
      themeMode: _themeMode,
      navigatorKey: navigatorKey,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [
        Locale('it', 'IT'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      home: _forcedGate ??
          AuthWrapper(
            isDarkTheme: _isDarkTheme,
            marketingProfileEnabled: _marketingProfileEnabled,
            marketingCommsEnabled: _marketingCommsEnabled,
            onThemeChanged: _toggleTheme,
            onMarketingProfileChanged: _toggleMarketingProfile,
            onMarketingCommsChanged: _toggleMarketingComms,
            onSharedContent: _handleSharedContent,
          ),
      debugShowCheckedModeBanner: false,
    );
  }

  void _navigateToSavedFolder(String folderPath, String postId) async {
    if (kDebugMode) {
      print('DEBUG: ========== NAVIGAZIONE POST SALVATAGGIO ==========');
      print('DEBUG: Tentativo navigazione a: "$folderPath"');
      print('DEBUG: Post ID: $postId');
      print('DEBUG: Caratteri path: ${folderPath.codeUnits}');
    }

    try {
      await Future.delayed(Duration(milliseconds: 300));

      final BuildContext? navContext = navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) {
        print('DEBUG: ❌ Context non disponibile per navigazione');
        return;
      }

      final folderService = FolderService();
      await folderService.forceRefreshFromDataService();

      print(
          'DEBUG: Cartelle disponibili: ${folderService.folders.map((f) => f.name).toList()}');

      MockFolder? targetFolder;

      if (folderPath == 'Tutti' || folderPath.isEmpty) {
        targetFolder = folderService.folders.firstWhere((f) => f.isSpecial,
            orElse: () => folderService.folders.first);
      } else {
        print('DEBUG: Splitting path: "$folderPath"');
        final pathParts = folderPath.split(' › ');
        print('DEBUG: Path parts: $pathParts (${pathParts.length} parti)');

        MockFolder? current = folderService.folders.firstWhere(
          (f) => !f.isSpecial && f.name == pathParts.first,
          orElse: () =>
              MockFolder(name: '', count: '', color: Colors.grey, level: -1),
        );
        print(
            'DEBUG: Cartella root trovata: ${current?.name ?? "NESSUNA"} (level: ${current?.level ?? -1})');

        if (current != null && current.level != -1) {
          for (int i = 1; i < pathParts.length; i++) {
            final targetName = pathParts[i];
            print(
                'DEBUG: Cercando sottocartella: "$targetName" in ${current!.name}');
            print(
                'DEBUG: Children disponibili: ${current.children.map((c) => c.name).toList()}');

            MockFolder? found;
            for (var child in current.children) {
              if (child.name == targetName) {
                found = child;
                break;
              }
            }

            if (found == null) {
              print('DEBUG: ⚠️ Sottocartella "$targetName" NON trovata!');
              break;
            }

            print('DEBUG: ✅ Sottocartella "$targetName" trovata!');
            current = found;
          }
          targetFolder =
              (current != null && current.level != -1) ? current : null;
          print(
              'DEBUG: Target folder finale: ${targetFolder?.name ?? "NESSUNA"}');
        }

        if (targetFolder == null) {
          print(
              'DEBUG: ⚠️ Cartella non trovata per path: $folderPath, usando Tutti come fallback');
          targetFolder = folderService.folders.firstWhere(
            (f) => f.isSpecial,
            orElse: () => folderService.folders.first,
          );
        } else {
          print('DEBUG: ✅ Cartella trovata: ${targetFolder.name}');
        }
      }

      if (targetFolder != null && navContext.mounted) {
        print(
            'DEBUG: Navigando alla cartella dopo salvataggio: ${targetFolder.name}');
        await Navigator.of(navContext).push(
          MaterialPageRoute(
            builder: (context) => FolderDetailPage(
              folder: targetFolder!,
              isDarkTheme: _isDarkTheme,
              allFolders: folderService.folders,
              highlightPostId: postId,
              onFolderUpdated: () {
                if (mounted) setState(() {});
              },
              onThemeChanged: (isDark) => _toggleTheme(isDark),
            ),
          ),
        );

        // Quando torni dalla cartella, aggiorna la home
        print('DEBUG: Tornato dalla cartella, aggiornando home...');
        if (mounted) {
          setState(() {});
        }

        if (navContext.mounted) {
          String displayPath = folderPath.isEmpty || folderPath == 'Tutti'
              ? 'Tutti'
              : folderPath;
        }
      }
    } catch (e) {
      if (kDebugMode) print('ERRORE: Navigazione fallita: $e');
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {}
    }
  }
}

class WebHomePage extends StatefulWidget {
  final bool isDarkTheme;
  final bool marketingProfileEnabled;
  final bool marketingCommsEnabled;
  final Function(bool) onThemeChanged;
  final Function(bool) onMarketingProfileChanged;
  final Function(bool) onMarketingCommsChanged;
  final Function(SharedContent) onSharedContent;

  const WebHomePage({
    Key? key,
    required this.isDarkTheme,
    required this.marketingProfileEnabled,
    required this.marketingCommsEnabled,
    required this.onThemeChanged,
    required this.onMarketingProfileChanged,
    required this.onMarketingCommsChanged,
    required this.onSharedContent,
  }) : super(key: key);

  @override
  _WebHomePageState createState() => _WebHomePageState();
}

class _NewSignupPremiumPromoDialog extends StatefulWidget {
  final int durationDays;
  final String priceAfterTrial;

  const _NewSignupPremiumPromoDialog({
    required this.durationDays,
    required this.priceAfterTrial,
  });

  @override
  State<_NewSignupPremiumPromoDialog> createState() =>
      _NewSignupPremiumPromoDialogState();
}

class _NewSignupPremiumPromoDialogState
    extends State<_NewSignupPremiumPromoDialog> {
  final PageController _controller = PageController();
  int _index = 0;

  static const _comparisonSlides = [
    _NewSignupPromoPlanSlideData(
      icon: Icons.folder_copy_outlined,
      title: 'Cartelle e sottocartelle',
      freeText:
          'Con Free puoi creare fino a 10 cartelle nella home, con profondità home + 1 livello e massimo 4 sottocartelle per cartella.',
      premiumText:
          'Con Premium superi i limiti Free: più cartelle, più livelli e più libertà per organizzare tutti i contenuti.',
      color: Color(0xFF2C7A7B),
    ),
    _NewSignupPromoPlanSlideData(
      icon: Icons.tag_outlined,
      title: 'Tag e ricerca',
      freeText:
          'Con Free puoi cercare nei contenuti salvati e usare gli hashtag automatici quando vengono estratti dal contenuto.',
      premiumText:
          'Con Premium puoi aggiungere anche tag manuali, così rendi ogni salvataggio più facile da ritrovare.',
      color: Color(0xFF2563EB),
    ),
    _NewSignupPromoPlanSlideData(
      icon: Icons.insights_outlined,
      title: 'Statistiche e pubblicità',
      freeText:
          'Con Free hai statistiche base e possono essere mostrati annunci durante l’uso dell’app.',
      premiumText:
          'Con Premium hai statistiche più complete e usi SaveIn senza annunci.',
      color: Color(0xFF7C3AED),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page < 0 || page >= 4) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 520 ? size.width * 0.9 : 460.0;
    final height = size.height < 720 ? size.height * 0.82 : 590.0;
    const accentColor = Color(0xFF2563EB);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Prova Premium gratis',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: 4,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _NewSignupTrialSlide(
                      durationDays: widget.durationDays,
                      priceAfterTrial: widget.priceAfterTrial,
                    );
                  }
                  return _NewSignupPromoPlanSlide(
                    slide: _comparisonSlides[index - 1],
                    showActivateButton: index == 3,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Non ora'),
                  ),
                  const Spacer(),
                  Row(
                    children: List.generate(
                      4,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _index ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _index ? accentColor : Colors.black26,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_index == 3)
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Attiva gratis'),
                    )
                  else
                    IconButton(
                      onPressed: () => _goTo(_index + 1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewSignupTrialSlide extends StatelessWidget {
  final int durationDays;
  final String priceAfterTrial;

  const _NewSignupTrialSlide({
    required this.durationDays,
    required this.priceAfterTrial,
  });

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF2563EB);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 104,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.workspace_premium, size: 58, color: color),
          ),
          const SizedBox(height: 16),
          const Text(
            '1 mese Premium gratis',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Attiva ora SaveIn! Premium gratis per $durationDays giorni. '
            'Dal secondo mese il piano Premium costa €$priceAfterTrial al mese.',
            style: const TextStyle(fontSize: 15, height: 1.3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _NewSignupPromoInfoBox(
            title: 'Cosa succede se accetti',
            text:
                'Il tuo account passa subito da Free a Premium per il periodo gratuito. Potrai vedere la scadenza dalla pagina Account.',
            color: color,
          ),
        ],
      ),
    );
  }
}

class _NewSignupPromoPlanSlide extends StatelessWidget {
  final _NewSignupPromoPlanSlideData slide;
  final bool showActivateButton;

  const _NewSignupPromoPlanSlide({
    required this.slide,
    required this.showActivateButton,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 96,
            decoration: BoxDecoration(
              color: slide.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(slide.icon, size: 54, color: slide.color),
          ),
          const SizedBox(height: 14),
          Text(
            slide.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _NewSignupPromoInfoBox(
            title: 'Free',
            text: slide.freeText,
            color: Colors.grey.shade700,
          ),
          const SizedBox(height: 12),
          _NewSignupPromoInfoBox(
            title: 'Premium',
            text: slide.premiumText,
            color: slide.color,
          ),
          if (showActivateButton) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.workspace_premium),
              label: const Text('Prova Premium gratis'),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewSignupPromoInfoBox extends StatelessWidget {
  final String title;
  final String text;
  final Color color;

  const _NewSignupPromoInfoBox({
    required this.title,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.35)),
        ],
      ),
    );
  }
}

class _NewSignupPromoPlanSlideData {
  final IconData icon;
  final String title;
  final String freeText;
  final String premiumText;
  final Color color;

  const _NewSignupPromoPlanSlideData({
    required this.icon,
    required this.title,
    required this.freeText,
    required this.premiumText,
    required this.color,
  });
}

class _WebHomePageState extends State<WebHomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FolderService _folderService = FolderService();
  final SharingService _sharingService = SharingService.instance;
  final ScrollController _homeScrollController = ScrollController();

  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _isInitializing = true;
  bool _folderServiceInitStarted = false;
  bool _isRefreshing = false; // Previene loop
  StreamSubscription<firebase_auth.User?>? _authBannerSubscription;

  Timer? _searchDebounceTimer;
  Timer? _syncDebounce; // Debounce per sync
  Timer? _promotionBannerDebounce;
  String _lastTrackedQuery = '';

  Key _gridKey = UniqueKey();
  late DataChangeCallback _dataServiceCallback;

  // Highlight cartella root da reminder
  String? _highlightRootFolderId;
  Timer? _highlightRootTimer;
  Timer? _homeScrollTimer;
  late AnimationController _homePulseController;
  late Animation<double> _homePulseAnim;
  final GlobalKey _highlightedHomeFolderKey = GlobalKey();

  // 🔥 NUOVO: Traccia lo stato dell'app per gestire il ritorno dal background
  bool _wasInBackground = false;
  DateTime? _lastBackgroundTime;
  bool _dailyOpenAdChecked = false;
  String? _promotionBannerUserId;
  String? _newSignupPromoCheckedUserId;
  bool _newSignupPromoShowing = false;
  bool _sharedImportPromptShowing = false;
  PromotionBanner? _activeBanner;
  final Set<String> _trackedHomePromotionViews = {};

  String _newSignupPromoDeferredKey(String userId) =>
      'new_signup_premium_promo_deferred_until_next_access_$userId';

  String _newSignupPromoShownDateKey(String userId) =>
      'new_signup_premium_promo_shown_date_$userId';

  String _newSignupPromoDismissedAtKey(String userId) =>
      'new_signup_premium_promo_dismissed_at_ms_$userId';

  String _notificationConsentAfterFirstFolderKey(String userId) =>
      'notification_consent_requested_after_first_folder_$userId';

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  bool _isNewSignupPromoDismissedWithin48h(
      SharedPreferences prefs, String userId) {
    final key = _newSignupPromoDismissedAtKey(userId);
    final ms = prefs.getInt(key);
    if (ms == null) return false;
    final dismissedAt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.now().difference(dismissedAt).inHours < 48;
  }

  @override
  void initState() {
    super.initState();
    // 🔥 NUOVO: Aggiungi observer per lifecycle
    WidgetsBinding.instance.addObserver(this);

    _homePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _homePulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _homePulseController, curve: Curves.easeInOut),
    );

    homeHighlightFolderNotifier.addListener(_onHomeHighlightFolderChanged);

    _searchController.addListener(_onSearchChanged);
    AuthService().addListener(_schedulePromotionBannerRefresh);
    AuthService().addListener(_handleLoggedOutWhileHomeVisible);
    _authBannerSubscription =
        firebase_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      final newUid = user?.uid;
      if (newUid == _promotionBannerUserId) return;
      _promotionBannerUserId = newUid;

      if (newUid == null) {
        if (mounted) setState(() => _activeBanner = null);
        return;
      }

      unawaited(_loadActivePromotionBanner());
      unawaited(_maybeShowNewSignupPremiumPromo());
      unawaited(_maybeShowPendingSharedImportPrompt());
    });

    // Carica subito se utente già loggato
    final currentUid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      _promotionBannerUserId = currentUid;
      unawaited(_loadActivePromotionBanner());
      unawaited(_maybeShowNewSignupPremiumPromo());
      unawaited(_maybeShowPendingSharedImportPrompt());
    }
    _initializeFolderService();
    _setupDataServiceCallback();

    SharingService.setOnDataChangedCallback(() {
      // 🔥 FIX: Doppio controllo mounted per evitare setState dopo dispose
      if (!mounted || _isRefreshing) return;
      forceUIRefreshAfterDataChange();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_maybeShowDailyOpenAd());
        unawaited(_checkDueReminders());
        unawaited(_maybeShowNewSignupPremiumPromo());
        unawaited(_maybeShowPendingSharedImportPrompt());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 🔥 FIX: Delegare il reload al root widget (SaveInApp)
    if (kDebugMode) print('DEBUG: WebHomePage - Lifecycle cambiato a: $state');
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadActivePromotionBanner());
      unawaited(_maybeShowPendingSharedImportPrompt());
    }
  }

  Future<void> _maybeShowPendingSharedImportPrompt() async {
    if (_sharedImportPromptShowing || !mounted) return;
    if (firebase_auth.FirebaseAuth.instance.currentUser == null) return;

    _sharedImportPromptShowing = true;
    try {
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      final importedOrRejected =
          await SharedItemsPage.showPendingSharedItemsPrompt(
        context,
        isDarkTheme: widget.isDarkTheme,
      );
      if (importedOrRejected && mounted) {
        await forceUIRefreshAfterDataChange();
      }
    } finally {
      _sharedImportPromptShowing = false;
    }
  }

  Future<void> _reloadHomeFoldersFromFirestoreOnce() async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('folders')
          .orderBy('createdAt')
          .get(const GetOptions(source: Source.serverAndCache));

      final realFolders =
          snapshot.docs.map((doc) => Folder.fromFirestore(doc)).toList();
      await _folderService.syncFoldersFromDataServiceWithParentId(realFolders);
      _folderService.updateTuttiCount();
      _folderService.updateHealthStatus(
        ServiceHealthStatus.healthy,
        userContext: firebaseUser.uid,
      );
    } catch (e) {
      if (kDebugMode) {
        DebugLogger.logError('Reload cartelle Home da Firestore fallito', e);
      }
      _folderService.updateHealthStatus(
        ServiceHealthStatus.error,
        errorMessage: 'Reload cartelle Home fallito: $e',
        userContext: firebaseUser.uid,
      );
      rethrow;
    }
  }

  @override
  void dispose() {
    // 🔥 FIX: Rimuovi observer per lifecycle PRIMA di tutto
    WidgetsBinding.instance.removeObserver(this);

    // 🔥 FIX: Cancella i timer PRIMA di tutto per evitare che chiamino setState
    _searchDebounceTimer?.cancel();
    _syncDebounce?.cancel();
    _promotionBannerDebounce?.cancel();
    _authBannerSubscription?.cancel();

    // 🔥 FIX: Rimuovi i callback PRIMA di disporre i controller
    SharingService.setOnDataChangedCallback(null);

    try {
      DataService.instance.unregisterDataChangeCallback(_dataServiceCallback);
    } catch (e) {
      if (kDebugMode) print('DEBUG: Errore rimozione callback: $e');
    }

    // Ora rimuovi i listener e disponi i controller
    AuthService().removeListener(_schedulePromotionBannerRefresh);
    AuthService().removeListener(_handleLoggedOutWhileHomeVisible);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    homeHighlightFolderNotifier.removeListener(_onHomeHighlightFolderChanged);
    _highlightRootTimer?.cancel();
    _homeScrollTimer?.cancel();
    _homePulseController.dispose();
    _homeScrollController.dispose();

    super.dispose();
  }

  void _onHomeHighlightFolderChanged() {
    final id = homeHighlightFolderNotifier.value;
    if (id == null || !mounted) return;
    setState(() => _highlightRootFolderId = id);
    _homePulseController.repeat(reverse: true);
    _highlightRootTimer?.cancel();
    _highlightRootTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _homePulseController.stop();
        setState(() => _highlightRootFolderId = null);
      }
    });
    // Prima passa: scroll con stima per portare la card in vista
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToHighlightedFolder(id);
      // Seconda passa: dopo il rebuild (la card è ora renderizzata con GlobalKey), centra preciso
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _highlightRootFolderId != null) {
          _centerHomeOnKey(_highlightedHomeFolderKey);
        }
      });
    });
  }

  void _scrollToHighlightedFolder(String folderId) {
    if (!_homeScrollController.hasClients) return;

    // Prova prima con il GlobalKey per posizione reale
    final keyCtx = _highlightedHomeFolderKey.currentContext;
    if (keyCtx != null) {
      _centerHomeOnKey(_highlightedHomeFolderKey);
      return;
    }

    // Fallback con stima se il widget non è ancora costruito
    final sortedFolders = _getSortedFolders();
    final index = sortedFolders.indexWhere((f) => f.id == folderId);
    if (index < 0) return;

    // Ogni riga contiene 2 cartelle, altezza riga circa 120px + 12px spacing
    const rowHeight = 132.0;
    final row = index ~/ 2;
    double offset = row * rowHeight;
    final adRows = row ~/ 2;
    offset += adRows * 60.0;

    final viewportHeight = _homeScrollController.position.viewportDimension;
    final maxScroll = _homeScrollController.position.maxScrollExtent;
    if (viewportHeight <= 0 || maxScroll <= 0) return;

    final centeredOffset =
        (offset - viewportHeight * 0.5).clamp(0.0, maxScroll);
    _homeScrollController.animateTo(
      centeredOffset,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );

    // Ritenta con posizione reale dopo il render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _highlightRootFolderId != null) {
        _scrollToHighlightedFolder(folderId);
      }
    });
  }

  void _centerHomeOnKey(GlobalKey key) {
    final keyCtx = key.currentContext;
    if (keyCtx == null || !_homeScrollController.hasClients) return;
    final box = keyCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final scrollable = Scrollable.maybeOf(keyCtx);
    if (scrollable == null) return;
    final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
    if (scrollableBox == null) return;

    final itemOffset = box.localToGlobal(Offset.zero, ancestor: scrollableBox);
    final itemHeight = box.size.height;
    final viewportHeight = _homeScrollController.position.viewportDimension;
    final currentOffset = _homeScrollController.offset;

    final itemTopInScroll = currentOffset + itemOffset.dy;
    final centeredOffset = itemTopInScroll - (viewportHeight - itemHeight) / 2;

    _homeScrollController.animateTo(
      centeredOffset.clamp(0.0, _homeScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _maybeShowDailyOpenAd() async {
    if (_dailyOpenAdChecked) return;
    _dailyOpenAdChecked = true;
    await InterstitialAdService.instance.showDailyOpenAdIfNeeded();
  }

  Future<void> _checkDueReminders() async {
    try {
      final user = AuthService().currentUser;
      if (user == null) return;

      final canUseReminders =
          await PlanLimitsService.canUseFeature('reminders');
      if (!canUseReminders) return;

      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      final lastShownKey = 'last_reminders_shown_date_${user.id}';

      if (prefs.getString(lastShownKey) == today) {
        return;
      }

      final reminders = await ReminderService.instance.getDueRemindersToday();
      if (reminders.isEmpty || !mounted) return;

      await prefs.setString(lastShownKey, today);
      _showRemindersBanner(reminders);
    } catch (_) {}
  }

  Future<void> _loadActivePromotionBanner() async {
    try {
      if (kDebugMode) print('DEBUG: Caricamento banner promozionale...');
      final banner = await PromoPopupService.getBannerToShow();
      if (!mounted) return;
      final currentBannerId = _activeBanner?.id;
      final newBannerId = banner?.id;
      if (currentBannerId == newBannerId) {
        if (kDebugMode) {
          print(
              'DEBUG: Banner promozionale invariato: ${newBannerId ?? "nessuno"}');
        }
        _trackHomePromotionBannerView(banner?.id);
        return;
      }
      setState(() {
        _activeBanner = banner;
      });
      if (kDebugMode) {
        print(
            'DEBUG: Banner promozionale caricato: ${banner?.id ?? "nessuno"}');
      }
      _trackHomePromotionBannerView(banner?.id);
    } catch (e) {
      if (kDebugMode) print('DEBUG: Errore caricamento banner: $e');
    }
  }

  // Rete di sicurezza: se per qualsiasi motivo questa WebHomePage resta
  // visibile dopo un logout (es. perché non è più annidata dentro un
  // AuthWrapper vivo e reattivo), la chiudiamo forzatamente sostituendo
  // l'intero stack con un AuthWrapper nuovo di zecca, che mostrerà
  // correttamente LoginPage. Usiamo un breve ritardo prima di controllare
  // 'mounted': se il meccanismo reattivo standard di AuthWrapper ha già
  // fatto il suo lavoro, questo widget sarà già stato smontato e non faremo
  // nulla di duplicato.
  void _handleLoggedOutWhileHomeVisible() {
    if (AuthService().isLoggedIn) return;

    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || AuthService().isLoggedIn) return;

      debugPrint(
          'DEBUG LOGOUT: WebHomePage ancora visibile dopo logout, forzo reset a AuthWrapper');

      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AuthWrapper(
            isDarkTheme: widget.isDarkTheme,
            onThemeChanged: widget.onThemeChanged,
            marketingProfileEnabled: widget.marketingProfileEnabled,
            marketingCommsEnabled: widget.marketingCommsEnabled,
            onMarketingProfileChanged: widget.onMarketingProfileChanged,
            onMarketingCommsChanged: widget.onMarketingCommsChanged,
            onSharedContent: widget.onSharedContent,
          ),
        ),
        (route) => false,
      );
    });
  }

  void _schedulePromotionBannerRefresh() {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    PlanLimitsService.invalidateUsageCache();

    _promotionBannerDebounce?.cancel();
    _promotionBannerDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      unawaited(_loadActivePromotionBanner());
      unawaited(_maybeShowNewSignupPremiumPromo());
    });
  }

  Future<void> _maybeShowNewSignupPremiumPromo() async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    final user = AuthService().currentUser;
    if (firebaseUser == null || user == null) return;
    if (_newSignupPromoShowing || _newSignupPromoCheckedUserId == user.id) {
      return;
    }

    _newSignupPromoCheckedUserId = user.id;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final pendingWelcomeName = AuthService().consumePendingSignupWelcomeName();
    if (pendingWelcomeName != null) {
      final welcomeFuture = SaveInFirstLaunchTutorial.show(
        context,
        markSeenOnClose: true,
        welcomeUserName: pendingWelcomeName,
      );
      SaveInFirstLaunchTutorial.trackExternalWelcome(welcomeFuture);
      await welcomeFuture;
      if (!mounted) return;
    }

    final showedWelcomeTutorial =
        await SaveInFirstLaunchTutorial.showIfNeeded(context);
    if (!mounted) return;
    await SaveInFirstLaunchTutorial.waitForActiveWelcome();
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final deferredKey = _newSignupPromoDeferredKey(user.id);
    final shownDateKey = _newSignupPromoShownDateKey(user.id);
    final today = _todayKey();
    if (showedWelcomeTutorial ||
        SaveInFirstLaunchTutorial.consumeShownInCurrentSession()) {
      await prefs.setBool(deferredKey, true);
      return;
    }
    if (prefs.getBool(deferredKey) == true) {
      await prefs.remove(deferredKey);
    } else if (_isNewSignupPromoDismissedWithin48h(prefs, user.id)) {
      return;
    } else if (prefs.getString(shownDateKey) == today) {
      return;
    }

    final shouldShow = await AuthService().shouldShowNewSignupPremiumPromo();
    if (!mounted || !shouldShow) return;
    final config = await AuthService().getNewSignupPremiumPromoConfig();
    if (!mounted || config == null) return;

    _newSignupPromoShowing = true;
    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => NewSignupPremiumPromoDialog(
            durationDays: config.durationDays,
            priceAfterTrial: config.priceAfterTrial,
          ),
        ) ??
        false;
    _newSignupPromoShowing = false;
    if (!mounted) return;

    if (!accepted) {
      await prefs.setInt(
        _newSignupPromoDismissedAtKey(user.id),
        DateTime.now().millisecondsSinceEpoch,
      );
      return;
    }

    DateTime premiumUntil;
    try {
      premiumUntil = await AuthService().activateNewSignupPremiumPromo();
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Promo non disponibile'),
          content: Text(_cleanNewSignupPromoError(error)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Premium attivato'),
        content: Text(
          'Hai attivato 1 mese gratuito di SaveIn! Premium.\n'
          'Scadenza: ${premiumUntil.day.toString().padLeft(2, '0')}/'
          '${premiumUntil.month.toString().padLeft(2, '0')}/${premiumUntil.year}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _cleanNewSignupPromoError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.contains('[firebase_functions/already-exists]') ||
        message.contains('already-exists')) {
      return 'Hai già utilizzato questa promozione.';
    }
    return message.isEmpty
        ? 'Non è stato possibile attivare la promozione. Riprova più tardi.'
        : message;
  }

  void _showRemindersBanner(List<Reminder> reminders) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _RemindersBannerSheet(
        reminders: reminders,
        isDarkTheme: widget.isDarkTheme,
      ),
    );
  }

  void _setupDataServiceCallback() {
    _dataServiceCallback =
        (String changeType, Map<String, dynamic> changeData) {
      // 🔥 FIX: Controlla mounted prima di qualsiasi operazione
      if (!mounted || _isRefreshing) return;

      // Debounce per 300ms per evitare troppe chiamate
      _syncDebounce?.cancel();
      _syncDebounce = Timer(Duration(milliseconds: 300), () {
        // 🔥 FIX: Quadruplo controllo mounted nel callback del timer per sicurezza
        if (!mounted) {
          if (kDebugMode)
            print('DEBUG: Widget dismounted, cancellando operazione callback');
          return;
        }
        if (_isRefreshing) {
          if (kDebugMode) print('DEBUG: Già in refresh, skippando callback');
          return;
        }
        _handleDataChange(changeType, changeData);
      });
    };

    try {
      DataService.instance.registerDataChangeCallback(_dataServiceCallback);
      if (kDebugMode) print('DEBUG: Callback DataService registrato');
    } catch (e) {
      if (kDebugMode) print('DEBUG: Errore registrazione callback: $e');
    }
  }

  void _handleDataChange(String changeType, Map<String, dynamic> changeData) {
    // 🔥 FIX: Controlla se il widget è ancora montato
    if (!mounted) return;

    // Ignora eventi di cache cleaning che non richiedono UI update
    if (changeType == 'cache_cleaned') return;

    // Per tutti gli altri eventi, forza refresh
    forceUIRefreshAfterDataChange();
  }

  Future<void> forceUIRefreshAfterDataChange() async {
    // 🔥 FIX: Controlla mounted all'inizio
    if (!mounted || _isRefreshing) return;

    _isRefreshing = true;
    try {
      await _folderService.syncWithDataService();
      // 🔥 FIX: Controlla mounted prima di setState
      if (mounted) {
        setState(() {
          _forceRefresh();
        });
      }
    } catch (e) {
      if (kDebugMode) print('ERRORE: Aggiornamento UI fallito: $e');
    } finally {
      // 🔥 FIX: Resetta sempre _isRefreshing per evitare lock
      _isRefreshing = false;
    }
  }

  Future<void> _onPullToRefresh() async {
    try {
      if (kDebugMode) DebugLogger.logStart('Pull to refresh');

      HapticFeedback.lightImpact();
      await DataService.instance.reloadFromDisk();
      await _folderService.forceRefreshFromDataService();

      if (mounted) {
        setState(() {
          _forceRefresh();
        });
      }

      // 🔥 NUOVO: Rinfresca anche il banner promozionale senza bloccare la lista
      unawaited(_loadActivePromotionBanner());

      if (kDebugMode) DebugLogger.logSuccess('Pull-to-refresh completato');
    } catch (e) {
      if (kDebugMode) DebugLogger.logError('Pull-to-refresh fallito', e);
      // FIX 03/07/2026: prima un fallimento qui era invisibile all'utente
      // (solo un print in debug). Ora mostriamo un feedback esplicito.
      if (mounted) {
        setState(() {
          _forceRefresh();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Aggiornamento cartelle non riuscito: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _initializeFolderService() async {
    if (_folderServiceInitStarted) return;
    _folderServiceInitStarted = true;

    var initCompleted = false;
    final safetyTimer = Timer(const Duration(seconds: 30), () {
      if (!initCompleted && mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });

    try {
      if (kDebugMode) DebugLogger.logStart('Inizializzazione FolderService');

      // Mostra subito i dati in cache (se presenti) mentre parte il sync server.
      final userId = AuthService().currentUser?.id ??
          firebase_auth.FirebaseAuth.instance.currentUser?.uid;
      if (userId != null && _folderService.loadFromCache(userId) && mounted) {
        setState(() {
          _forceRefresh();
          _isInitializing = false;
        });
      }

      await _folderService
          .initializeHybridData()
          .timeout(const Duration(seconds: 25));

      // Refresh server in background senza bloccare la prima UI.
      unawaited(() async {
        try {
          await DataService.instance.reloadFromDisk();
          await _folderService.syncWithDataService().timeout(
                const Duration(seconds: 25),
              );
          DataService.instance.repairMissingPreviewsInBackground();
          if (mounted) {
            setState(() {
              _forceRefresh();
            });
          }
        } catch (e) {
          if (kDebugMode) {
            DebugLogger.logError('Refresh background cartelle fallito', e);
          }
        }
      }());

      // Verifica integrita' solo in debug, senza bloccare lo startup.
      if (kDebugMode) {
        Future.microtask(() async {
          try {
            await Future.delayed(const Duration(seconds: 3));
            final integrity = await _folderService.verifyDataIntegrity();
            DebugLogger.log('Integrita: ${integrity.toString()}');
          } catch (e) {
            DebugLogger.logError('Verifica integrita background fallita', e);
          }
        });
      }

      if (mounted) {
        setState(() {
          _forceRefresh();
        });
      }

      if (kDebugMode) DebugLogger.logSuccess('FolderService inizializzato');
    } catch (e) {
      if (kDebugMode) DebugLogger.logError('Inizializzazione fallita', e);

      try {
        await _folderService.forceReloadFromDatabase();
        if (mounted) {
          setState(() {
            _forceRefresh();
          });
        }
      } catch (retryError) {
        if (kDebugMode) DebugLogger.logError('Retry fallito', retryError);
      }
    } finally {
      initCompleted = true;
      safetyTimer.cancel();
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    // 🔥 FIX: Controlla se il widget è ancora montato
    if (!mounted) return;

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults.clear();
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSearching = true;
        _searchResults =
            _folderService.searchUnified(query, trackSearch: false);
      });
    }

    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(Duration(milliseconds: 1500), () {
      // 🔥 FIX: Controlla mounted nel callback del timer
      if (!mounted) return;
      if (query != _lastTrackedQuery && query.length >= 2) {
        _folderService.searchUnified(query, trackSearch: true);
        _lastTrackedQuery = query;
      }
    });
  }

  void _forceRefresh() {
    // 🔥 FIX: Controlla se il widget è ancora montato prima di chiamare setState
    if (!mounted) return;
    _gridKey = UniqueKey();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);

    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(themeColors),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _isSearching
                    ? _buildSearchResults(themeColors)
                    : _isInitializing
                        ? _buildLoadingState(themeColors)
                        : _buildFoldersGrid(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        isDarkTheme: widget.isDarkTheme,
        onHomeTap: _goToHome,
        onAddTap: _showCreateFolderDialog,
        onAccountTap: _openAccountPage,
        isHomeActive: true,
      ),
    );
  }

  void _openSharedItemsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SharedItemsPage(
          isDarkTheme: widget.isDarkTheme,
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeColors themeColors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          SizedBox(height: 24),
          Text(
            'Caricamento cartelle...',
            style: TextStyle(
              color: themeColors.textColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeColors themeColors) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 🔥 FIX: Mostra pulsante indietro se in modalità ricerca
              if (_isSearching) ...[
                IconButton(
                  icon: Icon(Icons.arrow_back,
                      color: themeColors.iconColor, size: 24),
                  onPressed: _goToHome,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
                SizedBox(width: 8),
                Text(
                  'Ricerca per',
                  style: ThemeHelpers.getAppTitleStyle(widget.isDarkTheme),
                ),
              ] else ...[
                Image.asset(
                  'assets/icon/SaveIn!.png',
                  height: 64,
                  fit: BoxFit.contain,
                ),
              ],
              Spacer(),
              if (AuthService().currentUser != null && !_isSearching)
                LogoutButton(
                  onLogoutComplete: () {},
                  isDarkTheme: widget.isDarkTheme,
                  onThemeChanged: widget.onThemeChanged,
                ),
            ],
          ),
          SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: const Color.fromARGB(255, 66, 66, 66)),
              decoration:
                  ThemeHelpers.getSearchDecoration(widget.isDarkTheme).copyWith(
                hintText: 'Cerca cartelle, #hashtags e contenuti...',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSearching && _searchResults.isNotEmpty)
                      Container(
                        margin: EdgeInsets.only(right: 8),
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 206, 208, 210),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_searchResults.length}',
                          style: TextStyle(
                            color: const Color.fromARGB(255, 8, 8, 8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    _searchController.text.isNotEmpty
                        ? IconButton(
                            icon:
                                Icon(Icons.clear, color: themeColors.hintColor),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : Icon(Icons.search, color: themeColors.hintColor),
                  ],
                ),
              ),
            ),
          ),
          if (!_isSearching) SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildPromotionBanner(ThemeColors themeColors) {
    final banner = _activeBanner;
    if (banner == null) {
      return const SizedBox.shrink();
    }

    final isCrossPromo = banner.isCrossPromo;
    if (!isCrossPromo) {
      final imageUrl = banner.imageUrl.trim();
      if (imageUrl.isEmpty) return const SizedBox.shrink();

      return Stack(
        children: [
          GestureDetector(
            onTap: banner.actionUrl.trim().isEmpty
                ? null
                : () async {
                    await AuthService().recordPromotionBannerEvent(
                      promotionId: banner.id,
                      eventType: 'click',
                      placement: 'savein_home_search',
                    );
                    await launchUrl(
                      Uri.parse(banner.actionUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 3,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  await PromoPopupService.markGenericPromoDismissed();
                  if (!mounted) return;
                  setState(() => _activeBanner = null);
                },
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCrossPromo ? Color(0xFFFFF7E6) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCrossPromo ? Color(0xFFFFB020) : Colors.black12,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (banner.imageUrl.trim().isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 3,
                          child: Image.network(
                            banner.imageUrl.trim(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Icon(
                          isCrossPromo
                              ? Icons.local_fire_department
                              : Icons.campaign_outlined,
                          color:
                              isCrossPromo ? Color(0xFFD97706) : Colors.black87,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            banner.title,
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      banner.message,
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                    SizedBox(height: 10),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (isCrossPromo)
                            ElevatedButton(
                              onPressed: () async {
                                await AuthService().recordPromotionBannerEvent(
                                  promotionId: banner.id,
                                  eventType: 'click',
                                  placement: 'savein_home_search',
                                );
                                if (!context.mounted) return;
                                await _activateSmartChefPromo(context);
                              },
                              child: Text(banner.ctaLabel),
                            )
                          else if (banner.actionUrl.trim().isNotEmpty)
                            ElevatedButton(
                              onPressed: () async {
                                await AuthService().recordPromotionBannerEvent(
                                  promotionId: banner.id,
                                  eventType: 'click',
                                  placement: 'savein_home_search',
                                );
                                await launchUrl(
                                  Uri.parse(banner.actionUrl),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                              child: Text(banner.ctaLabel),
                            ),
                          if (isCrossPromo)
                            OutlinedButton(
                              onPressed: _openSmartChefStore,
                              child: Text(
                                banner.secondaryCtaLabel.trim().isNotEmpty
                                    ? banner.secondaryCtaLabel
                                    : 'Apri SmartChef',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: Colors.white.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                await PromoPopupService.markCrossPromoDismissed(banner.id);
                if (!mounted) return;
                setState(() => _activeBanner = null);
              },
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, size: 18, color: Color(0xFF7A4A00)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _trackHomePromotionBannerView(String? promotionId) {
    if (promotionId == null ||
        promotionId.trim().isEmpty ||
        _trackedHomePromotionViews.contains(promotionId)) {
      return;
    }

    _trackedHomePromotionViews.add(promotionId);
    unawaited(AuthService().recordPromotionBannerEvent(
      promotionId: promotionId,
      eventType: 'view',
      placement: 'savein_home_search',
    ));
  }

  Future<void> _openSmartChefStore() async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=it.smartchef.app',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _activateSmartChefPromo(BuildContext context) async {
    try {
      final result = await AuthService().activateSmartChefLaunchPromo();
      if (!context.mounted) return;
      unawaited(AuthService().getActivePromotionBanner().then((banner) {
        if (mounted) {
          setState(() {
            _activeBanner = banner;
          });
        }
      }));

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Color(0xFFFFFBF5),
          title: Text('🎁 Promo prenotata!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Perfetto, abbiamo messo da parte il tuo regalo Premium.',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Color(0xFFFFB74D)),
                ),
                child: Text(
                  '📲 Ora apri SmartChef e accedi/registrati con la stessa email entro il ${_formatDate(result.claimBy)}.\n\n✨ Appena SmartChef conferma l’email, il Premium si attiverà su entrambe le app.',
                  style: TextStyle(
                    color: Color(0xFF6B4E16),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Chiudi'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _openSmartChefStore();
              },
              child: Text('Apri SmartChef'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  String _formatDate(DateTime date) {
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _buildSearchResults(ThemeColors themeColors) {
    return SearchResultsWidget(
      searchResults: _searchResults,
      isDarkTheme: widget.isDarkTheme,
      onResultTap: _openSearchResult,
      onRefresh: _onPullToRefresh,
    );
  }

  void _openSearchResult(SearchResult result) {
    if (result.type == 'folder' && result.folder != null) {
      _openFolder(result.folder!);
    } else if (result.type == 'post' && result.post != null) {
      _openPostDirectly(result.post!);
    }
  }

  Future<void> _openPostDirectly(MockPost post) async {
    _folderService.trackPostViewed(post);
    await SharingService.openPostDirectly(context, post.url);
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Impossibile aprire il link: $url');
      }
    } catch (e) {
      if (kDebugMode) DebugLogger.logError('Apertura URL fallita', e);
    }
  }

  Widget _buildFoldersGrid() {
    final sortedFolders = _getSortedFolders();
    final showAds = AppAccessService().hasAds;
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);

    // Costruisce una lista di widget: righe da 2 cartelle + banner ogni 4 cartelle
    final List<Widget> rows = [];
    for (int i = 0; i < sortedFolders.length; i += 2) {
      final folder1 = sortedFolders[i];
      final folder2 =
          i + 1 < sortedFolders.length ? sortedFolders[i + 1] : null;

      Widget buildFolderCardCell(MockFolder folder) {
        final isHighlighted = _highlightRootFolderId == folder.id;
        final card = MockFolderCard(
          folder: folder,
          onTap: () => _openFolder(folder),
          onRename: _showRenameDialog,
          onDelete: _showDeleteDialog,
          onMove: _showMoveFolderDialog,
          allFolders: _folderService.folders,
          isDarkTheme: widget.isDarkTheme,
        );
        if (isHighlighted) {
          return AnimatedBuilder(
            key: _highlightedHomeFolderKey,
            animation: _homePulseAnim,
            builder: (context, child) {
              final pulse = _homePulseAnim.value;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.7 + pulse * 0.3),
                    width: 2.5 + pulse * 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.25 + pulse * 0.35),
                      blurRadius: 10 + pulse * 12,
                      spreadRadius: 1 + pulse * 3,
                    ),
                  ],
                  color: Colors.orange.withOpacity(0.10 + pulse * 0.15),
                ),
                child: child,
              );
            },
            child: card,
          );
        }
        return card;
      }

      rows.add(Row(
        children: [
          Expanded(child: buildFolderCardCell(folder1)),
          const SizedBox(width: 12),
          Expanded(
            child: folder2 != null
                ? buildFolderCardCell(folder2)
                : const SizedBox.shrink(),
          ),
        ],
      ));

      // Banner dopo ogni 4 cartelle (ogni 2 righe), solo per utenti Free
      if (showAds && (i + 2) % 4 == 0 && i + 2 < sortedFolders.length) {
        rows.add(const BannerAdWidget());
      }
    }

    return RefreshIndicator(
      onRefresh: _onPullToRefresh,
      color: Colors.blue,
      backgroundColor: widget.isDarkTheme ? Colors.grey[800] : Colors.white,
      child: ListView(
        key: _gridKey,
        controller: _homeScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          _buildPromotionBanner(themeColors),
          if (_activeBanner != null) const SizedBox(height: 12),
          if (sortedFolders.isEmpty) _buildEmptyFoldersState(themeColors),
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1 &&
                rows[i + 1] is! BannerAdWidget &&
                rows[i] is! BannerAdWidget)
              const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // FIX 03/07/2026: prima, quando la sincronizzazione cartelle falliva in
  // modo persistente (es. su un dispositivo reale subito dopo login), la UI
  // mostrava solo un generico "Trascina per aggiornare" senza nessun
  // dettaglio sull'errore reale, ne' un modo esplicito di ritentare oltre al
  // gesto di pull-to-refresh (facile da non notare). Ora mostriamo l'errore
  // vero (da FolderService.currentHealth, gia' popolato dai punti di sync
  // esistenti) e un pulsante "Riprova" esplicito.
  Widget _buildEmptyFoldersState(ThemeColors themeColors) {
    final health = _folderService.currentHealth;
    final hasError = health.status == ServiceHealthStatus.error ||
        health.status == ServiceHealthStatus.degraded ||
        health.status == ServiceHealthStatus.offline;
    final errorMessage = health.errorMessage;

    return SizedBox(
      height: 260,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasError) ...[
                Icon(Icons.cloud_off, color: Colors.orange, size: 36),
                SizedBox(height: 12),
                Text(
                  'Non è stato possibile caricare le tue cartelle.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: themeColors.titleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (errorMessage != null && errorMessage.isNotEmpty) ...[
                  SizedBox(height: 6),
                  Text(
                    errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: themeColors.subtitleColor,
                      fontSize: 12,
                    ),
                  ),
                ],
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    _folderServiceInitStarted = false;
                    _initializeFolderService();
                  },
                  icon: Icon(Icons.refresh),
                  label: Text('Riprova'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ] else ...[
                Text(
                  'Trascina verso il basso per aggiornare le cartelle',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: themeColors.subtitleColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 🔥 FIX: Ordina solo le cartelle di livello 0 (root), mantenendo "Tutti" in prima posizione
  List<MockFolder> _getSortedFolders() {
    // Filtra solo le cartelle di livello 0 (root folders)
    final rootFolders =
        _folderService.folders.where((folder) => folder.level == 0).toList();

    if (rootFolders.isEmpty) {
      return [];
    }

    // Trova la cartella "Tutti"
    final tuttiFolder = rootFolders.firstWhere(
      (f) => f.isSpecial,
      orElse: () => rootFolders.first,
    );

    // Rimuovi "Tutti" dalla lista
    rootFolders.remove(tuttiFolder);

    // Ordina le altre cartelle alfabeticamente (case-insensitive)
    rootFolders
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Rimetti "Tutti" in prima posizione
    rootFolders.insert(0, tuttiFolder);

    return rootFolders;
  }

  void _goToHome() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    // 🔥 FIX: Controlla mounted prima di setState
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searchResults.clear();
    });
  }

  // NUOVO: Estrae il dominio dall'URL
  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      String domain = uri.host.toLowerCase();

      // Rimuovi 'www.' se presente
      if (domain.startsWith('www.')) {
        domain = domain.substring(4);
      }

      return domain;
    } catch (e) {
      print('DEBUG: Errore parsing URL per dominio: $e');
      return 'URL non valido';
    }
  }

  void _openFolder(MockFolder folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FolderDetailPage(
          folder: folder,
          isDarkTheme: widget.isDarkTheme,
          allFolders: _folderService.folders,
          onFolderUpdated: () {
            // 🔥 FIX CRITICO: Controlla mounted prima di setState nel callback
            if (!mounted) {
              if (kDebugMode)
                print(
                    'DEBUG: onFolderUpdated chiamato ma widget non più montato');
              return;
            }
            setState(() {
              _folderService.updateTuttiCount();
              _forceRefresh();
            });
          },
          onThemeChanged: (isDark) {
            widget.onThemeChanged(isDark);
          },
        ),
      ),
    ).then((_) {
      // 🔥 FIX: Refresh automatico quando si torna dalla cartella
      if (mounted) {
        setState(() {
          print('DEBUG: Refresh automatico dopo navigazione dalla cartella');
        });
      }
    });
  }

  void _openAccountPage() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountPage(
          isDarkTheme: widget.isDarkTheme,
          marketingProfileEnabled: widget.marketingProfileEnabled,
          marketingCommsEnabled: widget.marketingCommsEnabled,
          onThemeChanged: (isDark) {
            widget.onThemeChanged(isDark);
          },
          onMarketingProfileChanged: widget.onMarketingProfileChanged,
          onMarketingCommsChanged: widget.onMarketingCommsChanged,
          folders: _folderService.folders,
        ),
      ),
    );

    // 🔥 FIX: Controlla mounted prima di setState dopo navigazione
    if (result == true && mounted) {
      setState(() {
        _forceRefresh();
      });
    }
  }

  void _showCreateFolderDialog() {
    DialogHelpers.showCreateFolderDialog(
      context,
      widget.isDarkTheme,
      (name) async {
        try {
          if (kDebugMode) DebugLogger.logStart('Creazione cartella: $name');

          // Debug token solo in debug mode
          if (kDebugMode) {
            await debugAuthTokenStatus();
            await forceRefreshAuthToken();
          }

          final hadRealFolderBeforeCreate =
              await _currentUserHasRealFolderBeforeCreate();

          // Salva la cartella: FolderService valida il conteggio reale delle
          // cartelle Home usando i limiti dinamici Free/Premium della dashboard.
          await _folderService.createPersistentFolder(name);

          // 🔥 FIX: Controlla mounted prima di setState
          if (mounted) {
            setState(() {
              _forceRefresh();
            });
          }

          if (kDebugMode) print('DEBUG: Creazione completata');

          await _maybeRequestNotificationConsentAfterFirstFolder(
            folderName: name,
            hadRealFolderBeforeCreate: hadRealFolderBeforeCreate,
          );

          if (kDebugMode) DebugLogger.logSuccess('Cartella creata: $name');
        } catch (e) {
          if (kDebugMode) DebugLogger.logError('Creazione fallita', e);
          if (mounted) {
            _showRetryDialog(name, e.toString());

            // Se fallisce, ricarica per rimuovere la cartella ottimistica
            setState(() {
              _forceRefresh();
            });
          }
        }
      },
    );
  }

  bool _isRealUserFolderName(String name) {
    return name.trim().toLowerCase() != 'tutti';
  }

  Future<bool> _currentUserHasRealFolderBeforeCreate() async {
    try {
      final folders = await DataService.instance
          .getFolders(forceRefresh: true)
          .timeout(const Duration(seconds: 6));
      return folders.any(
          (folder) => !folder.isDefault && _isRealUserFolderName(folder.name));
    } catch (e) {
      if (kDebugMode) {
        print('DEBUG: controllo prima cartella da backend fallito: $e');
      }
      return _folderService.folders.any(
          (folder) => !folder.isSpecial && _isRealUserFolderName(folder.name));
    }
  }

  Future<void> _maybeRequestNotificationConsentAfterFirstFolder({
    required String folderName,
    required bool hadRealFolderBeforeCreate,
  }) async {
    if (hadRealFolderBeforeCreate || !_isRealUserFolderName(folderName)) {
      return;
    }

    final userId = firebase_auth.FirebaseAuth.instance.currentUser?.uid ??
        AuthService().currentUser?.id;
    if (userId == null || userId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _notificationConsentAfterFirstFolderKey(userId);
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);

    try {
      await AppNotificationService.instance
          .requestPermissionAndRegisterToken(userId)
          .timeout(const Duration(seconds: 10));
      await ReminderService.instance.requestPermissions().timeout(
            const Duration(seconds: 5),
          );
      await ReminderService.instance.rescheduleAllReminders().timeout(
            const Duration(seconds: 10),
          );
    } catch (e) {
      if (kDebugMode) {
        print(
            'DEBUG: richiesta consenso notifiche dopo prima cartella fallita: $e');
      }
    }
  }

  void _showRetryDialog(String folderName, String errorMessage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              'Errore creazione',
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Errore durante la creazione della cartella "$folderName".\n\n$errorMessage\n\nVuoi riprovare?',
          style: TextStyle(
            color: widget.isDarkTheme ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annulla',
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showCreateFolderDialog();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('Riprova'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(MockFolder folder) {
    DialogHelpers.showRenameFolderDialog(
      context,
      widget.isDarkTheme,
      folder,
      (newName) async {
        try {
          // 🔥 FIX: Rimosso loading dialog bloccante per UX istantanea
          // L'aggiornamento ottimistico avviene dentro renameFolder
          await _folderService.renameFolder(folder, newName);

          if (mounted) {
            setState(() {
              _forceRefresh();
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cartella rinominata'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            // Se fallisce, ricarica per ripristinare stato
            setState(() {
              _forceRefresh();
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Errore: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      },
    );
  }

  void _showDeleteDialog(MockFolder folder) {
    DialogHelpers.showDeleteFolderDialog(
      context,
      widget.isDarkTheme,
      folder,
      () async {
        try {
          _showLoadingDialog('Eliminando cartella...');

          // âœ… SEMPLIFICATO - Non serve piÃ¹ gestire manualmente la sincronizzazione post
          await _folderService.deleteFolder(folder);

          if (mounted) {
            Navigator.of(context).pop(); // Chiude loading dialog

            // Aggiorna UI - deleteFolder già invalida la cache e notifica i callback
            setState(() {
              _forceRefresh();
            });
          }
        } catch (e) {
          if (kDebugMode) DebugLogger.logError('Eliminazione fallita', e);

          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }

          if (mounted) {
            _showErrorDialog(
              'Errore eliminazione',
              'Impossibile eliminare la cartella "${folder.name}".\n\n${e.toString()}',
            );
          }
        }
      },
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey[900] : Colors.white,
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: widget.isDarkTheme ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: widget.isDarkTheme ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showMoveFolderDialog(MockFolder folder) {
    DialogHelpers.showMoveFolderDialog(
      context,
      widget.isDarkTheme,
      folder,
      _folderService.folders,
      (destination) async {
        try {
          await _folderService.moveFolder(folder, destination);

          if (mounted) {
            setState(() {
              _forceRefresh();
            });
          }
        } catch (e) {
          print('ERRORE: Spostamento fallito nella home: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Errore spostamento: $e'),
                  backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Banner sheet reminder del giorno
// ---------------------------------------------------------------------------

class _RemindersBannerSheet extends StatelessWidget {
  final List<Reminder> reminders;
  final bool isDarkTheme;

  const _RemindersBannerSheet({
    required this.reminders,
    required this.isDarkTheme,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDarkTheme ? Colors.grey[900]! : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.white60 : Colors.black54;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: Colors.orange, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reminder di oggi',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: subtitleColor, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Hai ${reminders.length} contenuto${reminders.length > 1 ? "i" : ""} da rivedere oggi',
              style: TextStyle(color: subtitleColor, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reminders
                      .map((reminder) => _ReminderItem(
                            reminder: reminder,
                            isDarkTheme: isDarkTheme,
                            textColor: textColor,
                            subtitleColor: subtitleColor,
                            onTap: () async {
                              final canOpen = await AppAccessService()
                                  .checkFeatureAvailable(
                                context,
                                'reminders',
                                'Reminder',
                              );
                              if (!canOpen) return;

                              Navigator.pop(context);
                              await InterstitialAdService.instance
                                  .showReminderOpenGate(context);
                              await ReminderService.instance
                                  .markReminderOpened(reminder);
                              await openReminderTargetInApp(
                                postId: reminder.isFolderReminder
                                    ? null
                                    : reminder.postId,
                                folderId: reminder.folderId,
                              );
                            },
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderItem extends StatelessWidget {
  final Reminder reminder;
  final bool isDarkTheme;
  final Color textColor;
  final Color subtitleColor;
  final VoidCallback onTap;

  const _ReminderItem({
    required this.reminder,
    required this.isDarkTheme,
    required this.textColor,
    required this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(
              reminder.isFolderReminder ? Icons.folder_outlined : Icons.alarm,
              color: Colors.orange,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reminder.isFolderReminder)
                    Text(
                      'Cartella',
                      style: TextStyle(color: subtitleColor, fontSize: 11),
                    ),
                  Text(
                    reminder.displayTitle,
                    style: TextStyle(color: textColor, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              reminder.isFolderReminder ? Icons.folder_open : Icons.open_in_new,
              color: subtitleColor,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
