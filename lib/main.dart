import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:app_links/app_links.dart';
import 'firebase_options.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'advanced_analytics_service.dart';

import 'models/folder.dart';
import 'models.dart' show Reminder;
import 'widgets/folder_card.dart';
import 'widgets/search_results_widget.dart';
import 'pages/folder_detail_page.dart';
import 'pages/account_page.dart';
import 'services/folder_service.dart';
import 'services/simple_analytics_service.dart';
import 'services/interstitial_ad_service.dart';
import 'services/access_control_service.dart';
import 'widgets/banner_ad_widget.dart';
import 'services/auth_service.dart';
import 'widgets/custom_bottom_nav.dart';
import 'services/sharing_service.dart';
import 'utils/theme_helpers.dart';
import 'utils/dialog_helpers.dart';
import 'utils/sync_utilities.dart';
import 'pages/auth_wrapper.dart';
import 'pages/shared_items_page.dart'; // NUOVO
import 'pages/shared_link_page.dart';
import 'data_service.dart';
import 'services/app_notification_service.dart';
import 'services/reminder_service.dart';
import 'widgets/first_launch_tutorial_dialog.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

  ReminderService.onNotificationTapped = (postUrl, postTitle) async {
    await InterstitialAdService.instance.showReminderAd();
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      try {
        final uri = Uri.parse(postUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  };

  ReminderService.onFolderNotificationTapped = (folderId, folderName) async {
    await InterstitialAdService.instance.showReminderAd();
    // La navigazione alla cartella viene gestita tramite navigatorKey
    // quando l'app è già in esecuzione; altrimenti l'app si apre alla home
    // e il banner giornaliero mostrerà il reminder.
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
    await ReminderService.instance.requestPermissions().timeout(
          const Duration(seconds: 5),
        );
    await ReminderService.instance.rescheduleAllReminders().timeout(
          const Duration(seconds: 10),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _initAppLinks();
    _loadUserPreferences(); // âœ… AGGIUNGI QUESTA RIGA
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowFirstLaunchTutorial());
    });
  }

  Future<void> _maybeShowFirstLaunchTutorial() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await SaveInFirstLaunchTutorial.showIfNeeded(context);
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
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;

      // 🔥 FIX FINALE: NON fare nessun reload automatico.
      // L'interfaccia rimane congelata come prima, il reload avviene SOLO con pull-to-refresh manuale.
      // Questo previene che gli oggetti MockFolder vengano ricreati, mantenendo i riferimenti validi.
      if (kDebugMode) print('DEBUG: App resumed - Nessun reload automatico');
    }
  }

  Future<void> _initServices() async {
    try {
      if (kDebugMode) DebugLogger.logStart('Inizializzazione servizi app');

      await _analytics.initialize();

      _sharingService.initialize(
        onSharedContent: _handleSharedContent,
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
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      home: AuthWrapper(
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

class _WebHomePageState extends State<WebHomePage> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FolderService _folderService = FolderService();
  final SharingService _sharingService = SharingService.instance;

  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _isInitializing = false;
  bool _isRefreshing = false; // Previene loop
  StreamSubscription<firebase_auth.User?>? _authBannerSubscription;

  Timer? _searchDebounceTimer;
  Timer? _syncDebounce; // Debounce per sync
  Timer? _promotionBannerDebounce;
  String _lastTrackedQuery = '';

  Key _gridKey = UniqueKey();
  late DataChangeCallback _dataServiceCallback;

  // 🔥 NUOVO: Traccia lo stato dell'app per gestire il ritorno dal background
  bool _wasInBackground = false;
  DateTime? _lastBackgroundTime;
  bool _dailyOpenAdChecked = false;
  String? _promotionBannerUserId;
  PromotionBanner? _activeBanner;
  final Set<String> _trackedHomePromotionViews = {};

  @override
  void initState() {
    super.initState();
    // 🔥 NUOVO: Aggiungi observer per lifecycle
    WidgetsBinding.instance.addObserver(this);

    _searchController.addListener(_onSearchChanged);
    AuthService().addListener(_schedulePromotionBannerRefresh);
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
    });

    // Carica subito se utente già loggato
    final currentUid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      _promotionBannerUserId = currentUid;
      unawaited(_loadActivePromotionBanner());
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
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 🔥 FIX: Delegare il reload al root widget (SaveInApp)
    if (kDebugMode) print('DEBUG: WebHomePage - Lifecycle cambiato a: $state');
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadActivePromotionBanner());
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
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _maybeShowDailyOpenAd() async {
    if (_dailyOpenAdChecked) return;
    _dailyOpenAdChecked = true;
    await InterstitialAdService.instance.showDailyOpenAdIfNeeded();
  }

  Future<void> _checkDueReminders() async {
    try {
      final reminders = await ReminderService.instance.getDueRemindersToday();
      if (reminders.isEmpty || !mounted) return;
      _showRemindersBanner(reminders);
    } catch (_) {}
  }

  Future<void> _loadActivePromotionBanner() async {
    try {
      if (kDebugMode) print('DEBUG: Caricamento banner promozionale...');
      final banner = await AuthService().getActivePromotionBanner();
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

  void _schedulePromotionBannerRefresh() {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    _promotionBannerDebounce?.cancel();
    _promotionBannerDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      unawaited(_loadActivePromotionBanner());
    });
  }

  void _showRemindersBanner(List<Reminder> reminders) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
    }
  }

  Future<void> _initializeFolderService() async {
    if (_isInitializing) return;

    // 🔥 FIX: Controlla mounted prima di setState
    if (mounted) {
      setState(() {
        _isInitializing = true;
      });
    }

    try {
      if (kDebugMode) DebugLogger.logStart('Inizializzazione FolderService');

      // Svuota la cache Firebase prima di caricare: garantisce che al login
      // (anche dopo un cambio utente) vengano sempre letti dati freschi dal server.
      await DataService.instance.reloadFromDisk();
      await _folderService.initializeHybridData();

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

      return GestureDetector(
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
                color: Colors.black.withOpacity(0.14),
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
      );
    }

    return Container(
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
            color: Colors.black.withOpacity(0.06),
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
                      color: isCrossPromo ? Color(0xFFD97706) : Colors.black87,
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
                Wrap(
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
              ],
            ),
          ),
        ],
      ),
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
    final user = AuthService().currentUser;
    final email = user?.email ?? '';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Promo lancio SaveIn! + SmartChef'),
            content: Text(
              'Attivando la promo ottieni SaveIn! Premium per 30 giorni da oggi.\n\n'
              'Per ottenere anche SmartChef Premium gratis, devi registrarti o accedere '
              'a SmartChef entro 14 giorni usando la stessa email:\n$email',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text('Attiva promo'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

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
          title: Text('Premium SaveIn! attivato'),
          content: Text(
            'La versione Premium è stata attivata il giorno '
            '${_formatDate(DateTime.now())} e scadrà il '
            '${_formatDate(result.premiumUntil)}, dopo 30 giorni di utilizzo.\n\n'
            'Ora installa o apri SmartChef e accedi con la stessa email entro il '
            '${_formatDate(result.claimBy)} per attivare anche lì il mese gratuito.',
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

      rows.add(Row(
        children: [
          Expanded(
            child: MockFolderCard(
              folder: folder1,
              onTap: () => _openFolder(folder1),
              onRename: _showRenameDialog,
              onDelete: _showDeleteDialog,
              onMove: _showMoveFolderDialog,
              allFolders: _folderService.folders,
              isDarkTheme: widget.isDarkTheme,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: folder2 != null
                ? MockFolderCard(
                    folder: folder2,
                    onTap: () => _openFolder(folder2),
                    onRename: _showRenameDialog,
                    onDelete: _showDeleteDialog,
                    onMove: _showMoveFolderDialog,
                    allFolders: _folderService.folders,
                    isDarkTheme: widget.isDarkTheme,
                  )
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
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          _buildPromotionBanner(themeColors),
          if (_activeBanner != null) const SizedBox(height: 12),
          if (sortedFolders.isEmpty)
            SizedBox(
              height: 260,
              child: Center(
                child: Text(
                  'Trascina verso il basso per aggiornare le cartelle',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: themeColors.subtitleColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
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

          // Salva la cartella (aggiorna la lista in memoria)
          await _folderService.createPersistentFolder(name);

          // 🔥 FIX: Controlla mounted prima di setState
          if (mounted) {
            setState(() {
              _forceRefresh();
            });
          }

          if (kDebugMode) print('DEBUG: Creazione completata');

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

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: subtitleColor.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.notifications_active,
                  color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              Text(
                'Reminder di oggi',
                style: TextStyle(
                  color: textColor,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Hai ${reminders.length} contenuto${reminders.length > 1 ? "i" : ""} da rivedere oggi',
            style: TextStyle(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...reminders.map((reminder) => _ReminderItem(
                reminder: reminder,
                isDarkTheme: isDarkTheme,
                textColor: textColor,
                subtitleColor: subtitleColor,
                onTap: () async {
                  Navigator.pop(context);
                  await InterstitialAdService.instance.showReminderAd();
                  if (reminder.isFolderReminder) {
                    // Per i reminder di cartelle non c'è un URL da aprire;
                    // l'utente viene rimandato alla home per navigare nella cartella.
                  } else {
                    try {
                      final uri = Uri.parse(reminder.postUrl);
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  }
                },
              )),
        ],
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
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
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
