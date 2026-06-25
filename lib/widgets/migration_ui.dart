import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/sharing_service.dart';
import '../services/migration_service.dart';
import '../pages/login_page.dart';
import 'package:savein/models.dart'; // Per User
import '../pages/auth_wrapper.dart';
import '../main.dart';

// MigrationWidget completo
class MigrationWidget extends StatefulWidget {
  final bool isDarkTheme;
  final VoidCallback? onMigrationCompleted;
  final VoidCallback? onMigrationSkipped;
  final VoidCallback? onMigrationFailed;

  const MigrationWidget({
    Key? key,
    required this.isDarkTheme,
    this.onMigrationCompleted,
    this.onMigrationSkipped,
    this.onMigrationFailed,
  }) : super(key: key);

  @override
  _MigrationWidgetState createState() => _MigrationWidgetState();
}

class _MigrationWidgetState extends State<MigrationWidget> {
  final MigrationService _migrationService = MigrationService();

  bool _isMigrating = false;
  String _currentStep = '';
  double _progress = 0.0;
  String? _errorMessage;
  bool _migrationCompleted = false;

  @override
  void initState() {
    super.initState();
    _checkMigrationStatus();
  }

  Future<void> _checkMigrationStatus() async {
    try {
      final legacyData = await _migrationService.detectLegacyData();
      final isCompleted = await _migrationService.isMigrationCompleted();

      if (isCompleted || legacyData == null || legacyData.isEmpty) {
        // Nessuna migrazione necessaria
        widget.onMigrationCompleted?.call();
      }
    } catch (e) {
      print('Errore check migrazione: $e');
      setState(() {
        _errorMessage = 'Errore durante la verifica: ${e.toString()}';
      });
    }
  }

  Future<void> _startMigration() async {
    setState(() {
      _isMigrating = true;
      _progress = 0.0;
      _currentStep = 'Inizializzazione...';
      _errorMessage = null;
    });

    try {
      // Ascolto del progresso - FIX: Corretto accesso alle proprietà
      _migrationService.progressStream.listen((progress) {
        if (mounted) {
          setState(() {
            _progress = progress.progressPercentage /
                100.0; // FIX: Cambiato da progress.progress a progress.progressValue
            _currentStep = progress.currentStep;
          });
        }
      });

      final result = await _migrationService.performMigration();

      if (result.success) {
        setState(() {
          _migrationCompleted = true;
          _currentStep = 'Migrazione completata!';
          _progress = 1.0;
        });

        // Breve delay per mostrare successo
        await Future.delayed(Duration(seconds: 2));
        widget.onMigrationCompleted?.call();
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'Migrazione fallita';
          _isMigrating = false;
        });
        widget.onMigrationFailed?.call();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore durante migrazione: ${e.toString()}';
        _isMigrating = false;
      });
      widget.onMigrationFailed?.call();
    }
  }

  void _skipMigration() {
    widget.onMigrationSkipped?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          widget.isDarkTheme ? Colors.grey[900] : Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo e titolo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.sync,
                  color: Colors.white,
                  size: 40,
                ),
              ),

              SizedBox(height: 32),

              Text(
                'Aggiornamento dati',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: widget.isDarkTheme ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 16),

              Text(
                'Abbiamo rilevato dei dati da aggiornare al nuovo sistema cloud. '
                'Questo processo migliorerà le prestazioni e permetterà la sincronizzazione su più dispositivi.',
                style: TextStyle(
                  fontSize: 16,
                  color: widget.isDarkTheme ? Colors.white70 : Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 48),

              // Sezione migrazione
              if (_isMigrating) ...[
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: widget.isDarkTheme ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _migrationCompleted ? Colors.green : Colors.blue,
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        _currentStep,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: widget.isDarkTheme
                              ? Colors.white
                              : Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.isDarkTheme
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_errorMessage != null) ...[
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 48,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Errore durante l\'aggiornamento',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.red[800],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _skipMigration,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[600],
                              ),
                              child: Text('Salta'),
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _startMigration,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: Text('Riprova'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Bottoni iniziali
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _startMigration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Inizia aggiornamento',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _skipMigration,
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          widget.isDarkTheme ? Colors.white70 : Colors.black54,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Salta per ora',
                      style: TextStyle(
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],

              SizedBox(height: 32),

              // Info aggiuntive
              if (!_isMigrating) ...[
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'I tuoi dati saranno al sicuro durante tutto il processo. '
                          'Puoi sempre effettuare l\'aggiornamento in seguito.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[800],
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// WRAPPER COMPLETAMENTE REATTIVO CON MIGRAZIONE INTEGRATA
class AuthWrapper extends StatelessWidget {
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

  /// Flusso per utente autenticato con verifica migrazione
  Widget _buildAuthenticatedFlow(User user) {
    return FutureBuilder<bool>(
      future: _checkMigrationNeeded(),
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
        return _buildSuccessTransition(user);
      },
    );
  }

  /// Verifica se è necessaria la migrazione
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
    return FutureBuilder(
      future: Future.delayed(Duration(milliseconds: 100)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildTransitionScreen(user.name);
        }

        return WebHomePage(
          isDarkTheme: isDarkTheme,
          marketingProfileEnabled: marketingProfileEnabled,
          marketingCommsEnabled: marketingCommsEnabled,
          onThemeChanged: onThemeChanged,
          onMarketingProfileChanged: onMarketingProfileChanged,
          onMarketingCommsChanged: onMarketingCommsChanged,
          onSharedContent: onSharedContent,
        );
      },
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

// LOGOUT BUTTON MIGLIORATO

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
