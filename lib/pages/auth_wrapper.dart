import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/sharing_service.dart';
import '../services/migration_service.dart';
import '../services/app_notification_service.dart';
import '../pages/login_page.dart';
import '../pages/admin_dashboard_page.dart';
import '../widgets/migration_ui.dart';
import '../main.dart';

// WRAPPER COMPLETAMENTE REATTIVO CON MIGRAZIONE INTEGRATA
class AuthWrapper extends StatelessWidget {
  static Future<bool>? _migrationCheckFuture;
  static String? _migrationCheckUserId;

  final bool isDarkTheme;
  final Function(bool) onThemeChanged;
  final bool marketingProfileEnabled;
  final bool marketingCommsEnabled;
  final Function(bool) onMarketingProfileChanged;
  final Function(bool) onMarketingCommsChanged;
  final Function(SharedContent) onSharedContent;

  const AuthWrapper({
    Key? key,
    required this.isDarkTheme,
    required this.onThemeChanged,
    required this.marketingProfileEnabled,
    required this.marketingCommsEnabled,
    required this.onMarketingProfileChanged,
    required this.onMarketingCommsChanged,
    required this.onSharedContent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    // CORREZIONE: Usa StreamBuilder che ascolta direttamente Firebase Auth
    return StreamBuilder<User?>(
      stream: authService.userStream,
      builder: (context, snapshot) {
        // Mostra loading durante inizializzazione o while waiting for stream
        if (!authService.isInitialized ||
            snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen();
        }

        // Se c'è un errore nel stream
        if (snapshot.hasError) {
          return _buildErrorScreen(snapshot.error.toString());
        }

        final user = snapshot.data;

        // Se non è loggato, mostra login
        if (user == null) {
          return LoginPage(
            isDarkTheme: isDarkTheme,
            onThemeChanged: onThemeChanged,
          );
        }

        // Se è loggato, verifica se serve migrazione
        return _buildAuthenticatedFlow(user);
      },
    );
  }

  bool get _isAdminEntryPoint {
    try {
      final baseUri = Uri.base;
      final path = baseUri.path.toLowerCase();
      final fragment = baseUri.fragment.toLowerCase();
      final adminQuery = (baseUri.queryParameters['admin'] ?? '').toLowerCase();

      return path.endsWith('/admin') ||
          path.contains('/admin/') ||
          path.endsWith('/dashboard') ||
          path.contains('/dashboard/') ||
          fragment.contains('admin') ||
          fragment.contains('dashboard') ||
          adminQuery == '1' ||
          adminQuery == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Flusso per utente autenticato con verifica migrazione
  Widget _buildAuthenticatedFlow(User user) {
    if (user.isBlocked) {
      return _buildBlockedAccountScreen(user);
    }

    if (_isAdminEntryPoint) {
      return _buildAdminFlow(user);
    }

    return FutureBuilder<bool>(
      future: _getMigrationCheckFuture(user.id),
      builder: (context, migrationSnapshot) {
        if (migrationSnapshot.connectionState == ConnectionState.waiting) {
          return _buildTransitionScreen(user.name);
        }

        final needsMigration = migrationSnapshot.data ?? false;

        if (needsMigration) {
          // Mostra UI migrazione
          return MigrationWidget(
            isDarkTheme: isDarkTheme,
            onMigrationCompleted: () {
              // La migrazione è completata, ricarica questo widget
              // Il FutureBuilder si aggiornerà automaticamente
            },
            onMigrationSkipped: () {
              // L'utente ha saltato, continua con app normale
            },
            onMigrationFailed: () {
              // Errore migrazione, ma permetti di continuare
            },
          );
        }

        // Nessuna migrazione necessaria, mostra app normale
        return AppNotificationListener(
          userId: user.id,
          child: _CrossPromoNotificationGate(
            child: _buildSuccessTransition(user),
          ),
        );
      },
    );
  }

  Widget _buildAdminFlow(User user) {
    if (user.canAccessDashboard) {
      return AdminDashboardPage(
        isDarkTheme: isDarkTheme,
        onThemeChanged: onThemeChanged,
      );
    }

    return FutureBuilder<User?>(
      future: AuthService().reloadCurrentUserFromFirestore(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen();
        }

        final refreshedUser =
            snapshot.data ?? AuthService().currentUser ?? user;
        if (refreshedUser.canAccessDashboard) {
          return AdminDashboardPage(
            isDarkTheme: isDarkTheme,
            onThemeChanged: onThemeChanged,
          );
        }

        return _buildUnauthorizedAdminScreen(refreshedUser);
      },
    );
  }

  /// Verifica se è necessaria la migrazione
  Future<bool> _getMigrationCheckFuture(String userId) {
    if (_migrationCheckFuture != null && _migrationCheckUserId == userId) {
      return _migrationCheckFuture!;
    }

    _migrationCheckUserId = userId;
    _migrationCheckFuture = _checkMigrationNeeded();
    return _migrationCheckFuture!;
  }

  Future<bool> _checkMigrationNeeded() async {
    try {
      final migrationService = MigrationService();

      // Se già completata, non serve migrazione
      final isCompleted = await migrationService.isMigrationCompleted();
      if (isCompleted) {
        return false;
      }

      // Verifica se ci sono dati legacy da migrare
      final legacyData = await migrationService.detectLegacyData();
      return legacyData != null && !legacyData.isEmpty;
    } catch (e) {
      print('ERRORE: Verifica migrazione fallita: $e');
      // In caso di errore, continua senza migrazione
      return false;
    }
  }

  Widget _buildSuccessTransition(User user) {
    return WebHomePage(
      isDarkTheme: isDarkTheme,
      marketingProfileEnabled: marketingProfileEnabled,
      marketingCommsEnabled: marketingCommsEnabled,
      onThemeChanged: onThemeChanged,
      onMarketingProfileChanged: onMarketingProfileChanged,
      onMarketingCommsChanged: onMarketingCommsChanged,
      onSharedContent: onSharedContent,
    );
  }

  Widget _buildUnauthorizedAdminScreen(User user) {
    final backgroundColor = isDarkTheme ? Colors.grey[900] : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDarkTheme ? Colors.grey[850] : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade300, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.admin_panel_settings,
                  color: Colors.red.shade400, size: 48),
              const SizedBox(height: 16),
              Text(
                'Accesso admin negato',
                style: TextStyle(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'L\'utente ${user.email} non ha il ruolo admin e non può aprire il pannello di gestione.',
                style: TextStyle(color: subtitleColor, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await AuthService().logout();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedAccountScreen(User user) {
    final backgroundColor = isDarkTheme ? Colors.grey[900] : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDarkTheme ? Colors.grey[850] : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.shade300, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, color: Colors.orange.shade500, size: 48),
              const SizedBox(height: 16),
              Text(
                'Account bloccato',
                style: TextStyle(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                user.blockedReason?.isNotEmpty == true
                    ? user.blockedReason!
                    : 'Il tuo account è stato bloccato da un amministratore.',
                style: TextStyle(color: subtitleColor, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await AuthService().logout();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor:
          isDarkTheme ? Color.fromARGB(255, 212, 255, 236) : Color(0xFFE0F2FE),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo animato
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Image.asset(
                  'assets/icon/app_logo_internal.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),

            SizedBox(height: 32),

            // Titolo (immagine)
            Image.asset(
              'assets/icon/SaveIn!.png',
              height: 80,
              fit: BoxFit.contain,
            ),

            SizedBox(height: 8),

            Text(
              'Organizza il web',
              style: TextStyle(
                color: isDarkTheme ? Colors.black54 : Colors.black54,
                fontSize: 16,
                fontStyle: FontStyle.italic,
              ),
            ),

            SizedBox(height: 40),

            // Loading indicator
            CircularProgressIndicator(
              color: Colors.blue,
              strokeWidth: 3,
            ),

            SizedBox(height: 16),

            Text(
              'Inizializzazione autenticazione...',
              style: TextStyle(
                color: isDarkTheme ? Colors.black54 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String error) {
    return Scaffold(
      backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 64,
            ),
            SizedBox(height: 24),
            Text(
              'Errore Autenticazione',
              style: TextStyle(
                color: isDarkTheme ? Colors.white : Colors.black87,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Si è verificato un problema durante l\'autenticazione. Riprova.',
                style: TextStyle(
                  color: isDarkTheme ? Colors.white70 : Colors.black54,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                // Reinizializza AuthService
                AuthService().initialize();
              },
              child: Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }

  // Screen di transizione con nome utente
  Widget _buildTransitionScreen(String userName) {
    return Scaffold(
      backgroundColor:
          isDarkTheme ? Color.fromARGB(255, 212, 255, 236) : Color(0xFFE0F2FE),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Icon(
                Icons.check,
                color: Colors.white,
                size: 40,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Benvenuto ${userName.split(' ').first}!',
              style: TextStyle(
                color: isDarkTheme ? Colors.black : Colors.black87,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Preparazione app...',
              style: TextStyle(
                color: isDarkTheme ? Colors.black54 : Colors.black54,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(
              color: Colors.green,
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _CrossPromoNotificationGate extends StatefulWidget {
  final Widget child;

  const _CrossPromoNotificationGate({required this.child});

  @override
  State<_CrossPromoNotificationGate> createState() =>
      _CrossPromoNotificationGateState();
}

class _CrossPromoNotificationGateState
    extends State<_CrossPromoNotificationGate> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    AuthService().addListener(_maybeShowCrossPromoNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowCrossPromoNotification();
    });
  }

  @override
  void dispose() {
    AuthService().removeListener(_maybeShowCrossPromoNotification);
    super.dispose();
  }

  void _maybeShowCrossPromoNotification() {
    if (!mounted || _showing) return;
    final result = AuthService().consumeCrossPromotionNotification();
    if (result == null) return;
    _showing = true;
    final activatedAt = DateTime.now();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFF0FFF4),
        title: const Row(
          children: [
            Text('🎉', style: TextStyle(fontSize: 28)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cross-promo completata!',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🎁 Grazie alla cross-promotion hai ricevuto ${result.durationDays} giorni di SaveIn Premium in regalo!',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1B5E20),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF66BB6A)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✨ Premium attivo dal ${_formatDate(activatedAt)} al ${_formatDate(result.premiumUntil)}.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _premiumFeatureRow(
                    Icons.folder_copy_rounded,
                    'Più cartelle, sottocartelle e livelli di organizzazione',
                  ),
                  _premiumFeatureRow(
                    Icons.sell_rounded,
                    'Tag manuali per ritrovare subito ogni contenuto',
                  ),
                  _premiumFeatureRow(
                    Icons.block_rounded,
                    'Nessuna pubblicità durante l’uso',
                  ),
                  _premiumFeatureRow(
                    Icons.auto_awesome_rounded,
                    'Esperienza più fluida e senza i limiti del piano Free',
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Fantastico! 🚀'),
          ),
        ],
      ),
    ).whenComplete(() {
      _showing = false;
    });
  }

  String _formatDate(DateTime date) {
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _premiumFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF14532D),
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// LOGOUT BUTTON MIGLIORATO
class LogoutButton extends StatelessWidget {
  final VoidCallback? onLogoutComplete;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  const LogoutButton({
    Key? key,
    this.onLogoutComplete,
    this.padding,
    this.constraints,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _showLogoutDialog(context),
      icon: const Icon(Icons.logout, color: Colors.red),
      tooltip: 'Logout',
      padding: padding ?? const EdgeInsets.all(8.0),
      constraints: constraints,
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final parentContext = context;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.logout, color: Colors.red, size: 24),
            SizedBox(width: 12),
            Text(
              'Logout',
              style:
                  TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sei sicuro di voler uscire dall\'app?',
              style: TextStyle(color: Colors.black54),
            ),
            SizedBox(height: 12),
            if (AuthService().currentUser != null)
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AuthService().currentUser!.email,
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
              ElevatedButton(
                onPressed: () async {
                  // Chiudi il dialog prima di iniziare il logout
                  Navigator.pop(dialogContext);

                  try {
                    // Esegui il logout
                    await AuthService().logout();
                    
                    // Il logout triggera il rebuild di AuthWrapper che mostrerà LoginPage.
                    // Dobbiamo però assicurarci di chiudere tutte le pagine aperte sopra AuthWrapper (come AccountPage).
                    
                    // Usiamo il navigatorKey globale se disponibile, altrimenti il context del genitore.
                    // popUntil(route.isFirst) ci riporta alla primissima pagina dell'app (AuthWrapper).
                    if (navigatorKey.currentState != null) {
                      navigatorKey.currentState!.popUntil((route) => route.isFirst);
                    } else if (parentContext.mounted) {
                      Navigator.of(parentContext, rootNavigator: true).popUntil((route) => route.isFirst);
                    }
                    
                    onLogoutComplete?.call();
                  } catch (e) {
                    debugPrint('Errore durante logout: $e');
                    if (parentContext.mounted) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(content: Text('Errore durante il logout: $e')),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Logout',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
    );
  }
}

// AUTH GUARD MIGLIORATO
class AuthGuard {
  static bool get isAuthenticated => AuthService().isLoggedIn;

  static User? get currentUser => AuthService().currentUser;

  static Future<void> logout() async {
    await AuthService().logout();
    // Non serve più navigazione manuale - AuthWrapper è reattivo!
  }

  static void requireAuth(BuildContext context, VoidCallback callback) {
    if (isAuthenticated) {
      callback();
    } else {}
  }
}
