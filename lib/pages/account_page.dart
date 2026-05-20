import 'package:flutter/material.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../models/folder.dart';
import '../utils/theme_helpers.dart';
import '../pages/simple_stats_page.dart';
import '../pages/privacy_policy_page.dart';
import '../pages/terms_conditions_page.dart';
import '../pages/marketing_communications_page.dart';
import '../services/access_control_service.dart';
import '../services/auth_service.dart';
import '../pages/login_page.dart';
import 'help_center_page.dart';
import 'contact_page.dart';
import '../widgets/custom_bottom_nav.dart';
import '../data_service.dart';

// Helper class per validazione password
class PasswordValidator {
  static const int minLength = 8;
  static const int maxLength = 128;

  static List<PasswordCriterion> validatePassword(String password) {
    return [
      PasswordCriterion(
        'Almeno $minLength caratteri',
        password.length >= minLength,
        Icons.text_fields,
      ),
      PasswordCriterion(
        'Almeno una lettera maiuscola',
        password.contains(RegExp(r'[A-Z]')),
        Icons.keyboard_arrow_up,
      ),
      PasswordCriterion(
        'Almeno una lettera minuscola',
        password.contains(RegExp(r'[a-z]')),
        Icons.keyboard_arrow_down,
      ),
      PasswordCriterion(
        'Almeno un numero',
        password.contains(RegExp(r'[0-9]')),
        Icons.numbers,
      ),
      PasswordCriterion(
        'Almeno un carattere speciale (!@#\$%^&*)',
        password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]')),
        Icons.security,
      ),
    ];
  }

  static bool isPasswordValid(String password) {
    if (password.length < minLength || password.length > maxLength)
      return false;
    final criteria = validatePassword(password);
    return criteria.every((c) => c.isValid);
  }

  static String? getPasswordError(String password) {
    if (password.isEmpty) return 'La password è obbligatoria';
    if (password.length < minLength)
      return 'Password troppo corta (minimo $minLength caratteri)';
    if (password.length > maxLength)
      return 'Password troppo lunga (massimo $maxLength caratteri)';
    if (!isPasswordValid(password))
      return 'La password non soddisfa tutti i criteri di sicurezza';
    return null;
  }
}

// Classe per criteri password
class PasswordCriterion {
  final String description;
  final bool isValid;
  final IconData icon;

  PasswordCriterion(this.description, this.isValid, this.icon);
}

// PAGINA DI ELIMINAZIONE ACCOUNT CORRETTA - NAVIGAZIONE FORZATA AL LOGIN
class _AccountDeletionLoadingPageReactive extends StatefulWidget {
  final bool isDarkTheme;

  const _AccountDeletionLoadingPageReactive({
    Key? key,
    required this.isDarkTheme,
  }) : super(key: key);

  @override
  _AccountDeletionLoadingPageReactiveState createState() =>
      _AccountDeletionLoadingPageReactiveState();
}

class _AccountDeletionLoadingPageReactiveState
    extends State<_AccountDeletionLoadingPageReactive> {
  int countdown = 3;
  Timer? timer;
  bool _deletionCompleted = false;
  String _statusMessage = 'Eliminazione in corso...';

  @override
  void initState() {
    super.initState();
    _startDeletionProcess();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _startDeletionProcess() async {
    print('DEBUG: Iniziando processo eliminazione REATTIVA con countdown');

    try {
      setState(() {
        _statusMessage = 'Eliminazione account in corso...';
      });

      // Avvia eliminazione
      final result = await AuthService().deleteAccount();

      if (result.success) {
        print(
            'DEBUG: Eliminazione account riuscita - Avviando countdown finale');

        setState(() {
          _deletionCompleted = true;
          _statusMessage = 'Account eliminato con successo!';
        });

        // Avvia countdown per reindirizzamento
        timer = Timer.periodic(Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              countdown--;
            });

            print('DEBUG: Countdown eliminazione: $countdown');

            if (countdown <= 0) {
              timer.cancel();
              print(
                  'DEBUG: Countdown completato - Navigando forzatamente al login');

              // CORREZIONE: Navigazione forzata al login invece di aspettare AuthWrapper
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (context) => LoginPage(
                            isDarkTheme: widget.isDarkTheme,
                            onThemeChanged: (isDark) {
                              // callback vuoto per evitare errori
                            },
                          )),
                  (route) => false, // Rimuove tutto lo stack di navigazione
                );
              }
            }
          }
        });
      } else {
        print('DEBUG: Eliminazione account fallita: ${result.message}');

        setState(() {
          _statusMessage = 'Errore durante l\'eliminazione: ${result.message}';
        });

        // Torna alla pagina account dopo 3 secondi
        Future.delayed(Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    } catch (e) {
      print('ERRORE: Eliminazione account: $e');

      setState(() {
        _statusMessage = 'Errore durante l\'eliminazione dell\'account';
      });

      // Torna alla pagina account dopo 3 secondi
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.isDarkTheme ? Colors.black : Colors.white;
    final textColor = widget.isDarkTheme ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Progress indicator
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                color: _deletionCompleted ? Colors.green : Colors.red,
                strokeWidth: 6,
              ),
            ),

            SizedBox(height: 40),

            // Titolo
            Text(
              'Eliminazione Account',
              style: TextStyle(
                color: textColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 16),

            // Status message
            Text(
              _statusMessage,
              style: TextStyle(
                color: textColor.withOpacity(0.8),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),

            if (_deletionCompleted) ...[
              SizedBox(height: 32),

              // Countdown finale
              Container(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.green.withOpacity(0.3), width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      'Reindirizzamento automatico in:',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '$countdown',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      countdown == 1 ? 'secondo' : 'secondi',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 40),

              // Messaggio finale
              Container(
                margin: EdgeInsets.symmetric(horizontal: 32),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Eliminazione completata con successo.\nGrazie per aver usato l’app.\n\nSarai reindirizzato automaticamente al login.',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Pagina Account implementata qui per la demo web
class AccountPage extends StatelessWidget {
  final bool isDarkTheme;
  final bool marketingProfileEnabled;
  final bool marketingCommsEnabled;
  final Function(bool) onThemeChanged;
  final Function(bool) onMarketingProfileChanged;
  final Function(bool) onMarketingCommsChanged;
  final List<MockFolder> folders;

  const AccountPage({
    Key? key,
    required this.isDarkTheme,
    required this.marketingProfileEnabled,
    required this.marketingCommsEnabled,
    required this.onThemeChanged,
    required this.onMarketingProfileChanged,
    required this.onMarketingCommsChanged,
    required this.folders,
  }) : super(key: key);

  // Calcola il numero totale di post (simulato basato sulle cartelle)
  int _getTotalPosts() {
    int totalPosts = 0;
    for (var folder in folders) {
      // Simula 1-2 post per cartella non vuota
      if (folder.count != 'Vuota') {
        totalPosts += 1;
      }
    }
    return totalPosts > 0 ? totalPosts : 1; // Almeno 1 post per demo
  }

  // Calcola il numero totale di cartelle e sottocartelle
  int _getTotalFolders() {
    int totalFolders = folders.length;

    void countSubfolders(MockFolder folder) {
      totalFolders += folder.children.length;
      for (var child in folder.children) {
        countSubfolders(child);
      }
    }

    for (var folder in folders) {
      countSubfolders(folder);
    }

    return totalFolders;
  }

  void _openHelpCenterPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HelpCenterPage(isDarkTheme: isDarkTheme),
      ),
    );
  }

  void _openContactPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContactPage(isDarkTheme: isDarkTheme),
      ),
    );
  }

  void _openStatsPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimpleStatsPage(isDarkTheme: isDarkTheme),
      ),
    );
  }

  void _openEditProfilePage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfilePage(isDarkTheme: isDarkTheme),
      ),
    ).then((_) {
      // Ricarica la pagina quando si torna dalla modifica
      (context as Element).markNeedsBuild();
    });
  }

  void _openPrivacyPolicyPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PrivacyPolicyPage(isDarkTheme: isDarkTheme),
      ),
    );
  }

  void _openTermsConditionsPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TermsConditionsPage(isDarkTheme: isDarkTheme),
      ),
    );
  }

  void _openMarketingCommunicationsPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MarketingCommunicationsPage(isDarkTheme: isDarkTheme),
      ),
    );
  }

  void _showVersionInfo(BuildContext context) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/SaveIn!.png',
              height: 56,
              fit: BoxFit.contain,
            ),
            SizedBox(width: 8),
            Text('Versione Corrente', style: TextStyle(color: textColor)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versione: 1.0.0', style: TextStyle(color: subtitleColor)),
            SizedBox(height: 8),
            Text('Build: 2025.01.08', style: TextStyle(color: subtitleColor)),
            SizedBox(height: 8),
            Text('Piattaforma: Web Demo',
                style: TextStyle(color: subtitleColor)),
            SizedBox(height: 16),
            Text(
              'La tua app per salvare e organizzare contenuti dal web in modo semplice e veloce.',
              style: TextStyle(color: subtitleColor, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Future<void> _backupInstagramPreviews(BuildContext context) async {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Backup anteprime Instagram',
            style: TextStyle(color: textColor)),
        content: Text(
          'Carica su cloud le anteprime trovate in cache sul dispositivo.\n\n'
          'Funziona solo per i post di Instagram e solo se l\'anteprima è ancora recuperabile (cache presente o URL ancora accessibile).',
          style: TextStyle(color: subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('Avvia'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Backup in corso... (potrebbe richiedere qualche minuto)',
                style: TextStyle(color: textColor),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final result =
          await DataService.instance.backupInstagramPreviewsToRemote();
      if (context.mounted) Navigator.pop(context); // close loading

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'IG: ${result.scanned}/${result.totalInstagramPosts} analizzati • '
              '${result.updated} aggiornati • ${result.failed} falliti',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // close loading
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup anteprime fallito: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _handleThemeChange(BuildContext context, bool newValue) {
    print(
        'DEBUG: Iniziando cambio tema da ${isDarkTheme ? 'scuro' : 'chiaro'} a ${newValue ? 'scuro' : 'chiaro'}');

    onThemeChanged(newValue);

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AccountPage(
          isDarkTheme: newValue,
          marketingProfileEnabled: marketingProfileEnabled,
          marketingCommsEnabled: marketingCommsEnabled,
          onThemeChanged: onThemeChanged,
          onMarketingProfileChanged: onMarketingProfileChanged,
          onMarketingCommsChanged: onMarketingCommsChanged,
          folders: folders,
        ),
        transitionDuration: Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );

    Future.delayed(Duration(milliseconds: 300), () {});

    print('DEBUG: Sostituzione pagina completata');
  }

  void _handleMarketingCommsChange(BuildContext context, bool newValue) async {
    print(
        'DEBUG: Cambio consenso marketing da $marketingCommsEnabled a $newValue');

    // Mostra loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkTheme ? Colors.grey.shade900 : Colors.white,
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Salvataggio in corso...',
                style: TextStyle(
                  color: isDarkTheme ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      // STEP 1: Salva tramite AuthService (persistenza locale)
      final success = await AuthService().updateMarketingConsent(newValue);

      if (success) {
        print('DEBUG: ✅ Consenso marketing salvato con successo');

        // STEP 2: Aggiorna callback parent (per sincronizzare main.dart)
        onMarketingCommsChanged(newValue);

        // STEP 3: Chiudi loading dialog
        if (context.mounted) {
          Navigator.pop(context);

          // STEP 4: Ricarica la pagina con il nuovo valore
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  AccountPage(
                isDarkTheme: isDarkTheme,
                marketingProfileEnabled: marketingProfileEnabled,
                marketingCommsEnabled: newValue, // ✅ Valore aggiornato
                onThemeChanged: onThemeChanged,
                onMarketingProfileChanged: onMarketingProfileChanged,
                onMarketingCommsChanged: onMarketingCommsChanged,
                folders: folders,
              ),
              transitionDuration: Duration(milliseconds: 200),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );

          // STEP 5: Mostra conferma
          Future.delayed(Duration(milliseconds: 300), () {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(
                        newValue ? Icons.check_circle : Icons.cancel,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Consenso marketing ${newValue ? 'attivato' : 'disattivato'}',
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: newValue ? Colors.green : Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          });
        }
      } else {
        throw Exception('Salvataggio fallito');
      }
    } catch (e) {
      print('ERRORE: Aggiornamento consenso marketing fallito: $e');

      // Chiudi loading dialog in caso di errore
      if (context.mounted) {
        Navigator.pop(context);

        // Mostra errore
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Errore durante il salvataggio. Riprova.'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Riprova',
              textColor: Colors.white,
              onPressed: () => _handleMarketingCommsChange(context, newValue),
            ),
          ),
        );
      }
    }
  }

  void _showComingSoon(BuildContext context) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Prossimamente', style: TextStyle(color: textColor)),
        content: Text(
          'Questa funzionalità sarà disponibile nella versione completa dell\'app.',
          style: TextStyle(color: subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // LOGOUT CORRETTO - NON FA PIU' NAVIGAZIONE MANUALE
  void _showLogoutDialog(BuildContext context) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Disconnetti', style: TextStyle(color: textColor)),
        content: Text(
          'Sei sicuro di voler disconnetterti dall\'account?',
          style: TextStyle(color: subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: hintColor)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              print('DEBUG: Iniziando logout da AccountPage');

              // CRITICO: Usa AuthService per logout - AuthWrapper gestirà la navigazione automaticamente
              await AuthService().logout();

              print(
                  'DEBUG: Logout completato - AuthWrapper mostrerà automaticamente LoginPage');

              // NON serve più navigazione manuale!
              // AuthWrapper sta ascoltando AuthService e mostrerà automaticamente LoginPage
            },
            child: Text('Disconnetti', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Dialog di conferma eliminazione account
  void _showDeleteAccountDialog(BuildContext context) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Elimina Account',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ATTENZIONE: Questa azione è IRREVERSIBILE!',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Eliminando l\'account perderai definitivamente:',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            _buildWarningItem(
                '• Tutti i tuoi contenuti salvati', subtitleColor),
            _buildWarningItem('• Tutte le cartelle create', subtitleColor),
            _buildWarningItem(
                '• Cronologia ricerche e statistiche', subtitleColor),
            _buildWarningItem('• Preferenze e impostazioni', subtitleColor),
            _buildWarningItem(
                '• Non potrai recuperare questi dati', Colors.red),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Potrebbe essere richiesta la riautenticazione per motivi di sicurezza.',
                      style: TextStyle(
                        color: Colors.red,
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
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: hintColor)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _proceedWithAccountDeletion(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Elimina Definitivamente',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningItem(String text, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight:
              text.contains('Non potrai') ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // ELIMINAZIONE ACCOUNT CORRETTA - USA LA PAGINA REATTIVA
  Future<void> _proceedWithAccountDeletion(BuildContext context) async {
    print('DEBUG: Iniziando eliminazione account REATTIVA');

    // Naviga alla pagina di loading reattiva
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => _AccountDeletionLoadingPageReactive(
          isDarkTheme: isDarkTheme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(isDarkTheme);
    final backgroundColor = themeColors.mainBackgroundColor;
    final cardColor = Colors.white;
    final cardTextColor = Colors.black87;
    final cardSubtitleColor = Colors.black54;
    final appBarTextColor = ThemeHelpers.getTitleColor(isDarkTheme);
    final navIconColor = ThemeHelpers.getIconColor(isDarkTheme);

    final authService = AuthService();

    return AnimatedBuilder(
      animation: authService,
      builder: (context, _) {
        final currentUser = authService.currentUser;
        final String displayName = currentUser?.name ?? 'Utente';
        final String displayEmail = currentUser?.email ?? 'email@esempio.com';
        final String displayUsername = currentUser?.username ?? '@utente';
        final String displayRole =
            AppAccessService().roleLabel(currentUser?.role ?? AppUserRole.free);

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(
            backgroundColor: backgroundColor,
            elevation: 0,
            titleSpacing: 16,
            title: Text(
              'Account',
              style: TextStyle(
                color: appBarTextColor,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: navIconColor, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
            toolbarHeight: 80,
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profilo utente
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Nome:', displayName, cardTextColor,
                          cardSubtitleColor),
                      SizedBox(height: 12),
                      _buildInfoRow('Email:', displayEmail, cardTextColor,
                          cardSubtitleColor),
                      SizedBox(height: 12),
                      _buildInfoRow('Username:', displayUsername, cardTextColor,
                          cardSubtitleColor),
                      SizedBox(height: 12),
                      _buildInfoRow('Piano:', displayRole, cardTextColor,
                          cardSubtitleColor),
                      SizedBox(height: 12),
                      _buildInfoRow(
                          'Statistiche:',
                          '${_getTotalPosts()} Post | ${_getTotalFolders()} Cartelle',
                          cardTextColor,
                          cardSubtitleColor),
                    ],
                  ),
                ),

                SizedBox(height: 24),
                _buildPlanCard(
                  context,
                  currentUser,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                ),
                _buildSmartChefPromoCard(
                  context,
                  currentUser,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                ),

                // Account
                Text(
                  'Account',
                  style: TextStyle(
                    color: appBarTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),

                _buildOptionCard(
                  'Modifica Profilo',
                  'Nome, username e foto profilo',
                  Icons.edit,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  () => _openEditProfilePage(context),
                ),

                _buildOptionCard(
                  'Privacy Policy',
                  'Informativa sulla privacy e trattamento dati',
                  Icons.privacy_tip,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  () => _openPrivacyPolicyPage(context),
                ),

                _buildOptionCard(
                  'Termini e Condizioni',
                  'Condizioni d\'uso e profilazione',
                  Icons.description,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  () => _openTermsConditionsPage(context),
                ),

                _buildOptionCard(
                  'Statistiche Utilizzo',
                  'Visualizza le tue abitudini',
                  Icons.analytics,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  () => _openStatsPage(context),
                ),

                if (currentUser?.isAdmin ?? false)
                  _buildOptionCard(
                    'Gestione ruoli admin',
                    'Assegna Free, Premium o Admin ad altri utenti',
                    Icons.admin_panel_settings,
                    cardColor,
                    cardTextColor,
                    cardSubtitleColor,
                    () => _showAdminRoleManagementDialog(context),
                  ),

                SizedBox(height: 24),

                // Impostazioni App
                Text(
                  'Impostazioni App',
                  style: TextStyle(
                    color: appBarTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),

                _buildMarketingCommsCard(
                  'Marketing - Comunicazioni',
                  'Consenso per email promozionali',
                  Icons.email,
                  marketingCommsEnabled,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  (newValue) => _handleMarketingCommsChange(context, newValue),
                  () => _openMarketingCommunicationsPage(context),
                ),

                _buildSwitchCard(
                  'Tema Scuro',
                  'Attiva/disattiva tema scuro',
                  Icons.dark_mode,
                  isDarkTheme,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  (newValue) => _handleThemeChange(context, newValue),
                ),

                SizedBox(height: 24),

                // Supporto
                Text(
                  'Supporto',
                  style: TextStyle(
                    color: appBarTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),

                _buildOptionCard(
                  'Centro Assistenza',
                  'FAQ e guide',
                  Icons.help_center,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  () => _openHelpCenterPage(context),
                ),

                _buildOptionCard(
                  'Contattaci',
                  'Segnala un problema',
                  Icons.contact_support,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  () => _openContactPage(context),
                ),

                _buildOptionCard(
                  'Versione Corrente',
                  'Versione 1.0.0',
                  Icons.info,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  () => _showVersionInfo(context),
                ),

                _buildOptionCard(
                  'Backup anteprime Instagram',
                  'Salva su cloud le anteprime per non perderle più',
                  Icons.cloud_upload_outlined,
                  cardColor,
                  cardTextColor,
                  cardSubtitleColor,
                  () => _backupInstagramPreviews(context),
                ),

                SizedBox(height: 32),

                // Disconnetti
                Container(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _showLogoutDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.black, width: 1),
                      ),
                    ),
                    child: Text(
                      'Disconnetti',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Scritta "Oppure"
                Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                    ),
                    child: Text(
                      'Oppure',
                      style: TextStyle(
                        color: appBarTextColor.withOpacity(0.7),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Elimina Account
                Container(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _showDeleteAccountDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[800],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.black, width: 1),
                      ),
                    ),
                    child: Text(
                      'Elimina Account',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 32),
              ],
            ),
          ),

          // Barra di navigazione
          bottomNavigationBar: CustomBottomNavigationBar(
            isDarkTheme: isDarkTheme,
            onHomeTap: () =>
                Navigator.popUntil(context, (route) => route.isFirst),
            onAddTap: () {},
            onAccountTap: () {},
            isAccountActive: true,
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(
      String label, String value, Color textColor, Color subtitleColor) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: label + ' ',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: subtitleColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    String title,
    String subtitle,
    IconData icon,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
    VoidCallback onTap,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: textColor, size: 24),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: subtitleColor,
            fontSize: 14,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios, color: subtitleColor, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSwitchCard(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: textColor, size: 24),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: subtitleColor,
            fontSize: 14,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.blue,
          inactiveThumbColor: Colors.grey.shade600,
          inactiveTrackColor: Colors.grey.shade400,
        ),
      ),
    );
  }

  Widget _buildMarketingCommsCard(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
    Function(bool) onChanged,
    VoidCallback onInfoTap,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: textColor, size: 24),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: subtitleColor,
            fontSize: 14,
          ),
        ),
        trailing: SizedBox(
          width: 96,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: onInfoTap,
                child: Container(
                  padding: EdgeInsets.all(6),
                  margin: EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.info_outline,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: Colors.blue,
                inactiveThumbColor: Colors.grey.shade600,
                inactiveTrackColor: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handlePlanChange(
    BuildContext context,
    AppUserRole targetRole,
  ) async {
    final accessService = AppAccessService();
    final targetLabel = accessService.roleLabel(targetRole);

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Cambia piano'),
            content: Text('Vuoi passare al piano $targetLabel?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Conferma'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final success = await AuthService().updateOwnRole(targetRole);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Piano aggiornato a $targetLabel'
              : 'Impossibile aggiornare il piano',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _openSmartChefStore() async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.smartchef.app',
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
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAdminRoleManagementDialog(BuildContext context) {
    final emailController = TextEditingController();
    AppUserRole selectedRole = AppUserRole.premium;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Gestione ruoli admin'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email utente',
                  hintText: 'utente@email.com',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<AppUserRole>(
                value: selectedRole,
                items: AppUserRole.values
                    .map(
                      (role) => DropdownMenuItem<AppUserRole>(
                        value: role,
                        child: Text(AppAccessService().roleLabel(role)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    selectedRole = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Ruolo',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await AuthService().assignRoleToUserByEmail(
                    email: emailController.text.trim(),
                    role: selectedRole,
                  );

                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ruolo aggiornato con successo'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(e.toString().replaceFirst('Exception: ', '')),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: Text('Salva ruolo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    User? currentUser,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
  ) {
    final accessService = AppAccessService();
    final role = currentUser?.role ?? AppUserRole.free;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium, color: textColor),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Piano attuale: ${accessService.roleLabel(role)}',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            role == AppUserRole.free
                ? 'Limiti attivi su cartelle, tag manuali e pubblicità.'
                : role == AppUserRole.premium
                    ? 'Nessun limite Free e nessuna pubblicità.'
                    : 'Privilegi Premium completi senza pagamento.',
            style: TextStyle(color: subtitleColor, fontSize: 14),
          ),
          SizedBox(height: 12),
          if (accessService.canSelfManagePlan)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: role == AppUserRole.free
                      ? null
                      : () => _handlePlanChange(context, AppUserRole.free),
                  child: Text('Passa a Free'),
                ),
                ElevatedButton(
                  onPressed: role == AppUserRole.premium
                      ? null
                      : () => _handlePlanChange(context, AppUserRole.premium),
                  child: Text('Passa a Premium'),
                ),
              ],
            )
          else
            Text(
              'Il ruolo Admin non può essere attivato o modificato autonomamente.',
              style: TextStyle(
                color: subtitleColor,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSmartChefPromoCard(
    BuildContext context,
    User? currentUser,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
  ) {
    if (currentUser == null || currentUser.isAdmin) {
      return SizedBox.shrink();
    }

    return FutureBuilder<PromotionBanner?>(
      future: AuthService().getActivePromotionBanner(),
      builder: (context, snapshot) {
        final banner = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting ||
            banner == null) {
          return SizedBox.shrink();
        }
        AuthService().recordPromotionBannerEvent(
          promotionId: banner.id,
          eventType: 'view',
          placement: 'savein_account',
        );

        final isCrossPromo = banner.isCrossPromo;
        final bgColor = isCrossPromo ? Color(0xFFFFF7E6) : cardColor;
        final borderColor =
            isCrossPromo ? Color(0xFFFFB020) : textColor.withOpacity(0.12);
        final icon = isCrossPromo
            ? Icons.local_fire_department
            : Icons.campaign_outlined;
        final iconColor = isCrossPromo ? Color(0xFFD97706) : textColor;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          margin: EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      banner.title,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                banner.message,
                style: TextStyle(color: subtitleColor, fontSize: 14),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isCrossPromo)
                    ElevatedButton.icon(
                      onPressed: () async {
                        await AuthService().recordPromotionBannerEvent(
                          promotionId: banner.id,
                          eventType: 'click',
                          placement: 'savein_account',
                        );
                        if (!context.mounted) return;
                        await _activateSmartChefPromo(context);
                      },
                      icon: Icon(Icons.card_giftcard),
                      label: Text(banner.ctaLabel),
                    )
                  else if (banner.actionUrl.trim().isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () async {
                        await AuthService().recordPromotionBannerEvent(
                          promotionId: banner.id,
                          eventType: 'click',
                          placement: 'savein_account',
                        );
                        await launchUrl(
                          Uri.parse(banner.actionUrl),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: Icon(Icons.open_in_new),
                      label: Text(banner.ctaLabel),
                    ),
                  if (isCrossPromo)
                    OutlinedButton.icon(
                      onPressed: _openSmartChefStore,
                      icon: Icon(Icons.open_in_new),
                      label: Text(
                        banner.secondaryCtaLabel.trim().isNotEmpty
                            ? banner.secondaryCtaLabel
                            : 'Apri SmartChef',
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// NUOVA PAGINA: Modifica Profilo
class EditProfilePage extends StatefulWidget {
  final bool isDarkTheme;

  const EditProfilePage({
    Key? key,
    required this.isDarkTheme,
  }) : super(key: key);

  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _hasChanges = false;
  bool _isChangingPassword = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  String _originalName = '';
  String _originalUsername = '';

  // Validazione password
  List<PasswordCriterion> _passwordCriteria = [];
  bool _showPasswordCriteria = false;
  bool _passwordsMatch = true;
  String _passwordMatchError = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();

    _nameController.addListener(_checkForChanges);
    _usernameController.addListener(_checkForChanges);
    _newPasswordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onConfirmPasswordChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final currentUser = AuthService().currentUser;
    if (currentUser != null) {
      setState(() {
        _originalName = currentUser.name;
        _originalUsername = currentUser.username ?? '@utente';
        _nameController.text = _originalName;
        _usernameController.text = _originalUsername.replaceFirst('@', '');
      });
    }
  }

  void _checkForChanges() {
    final currentName = _nameController.text.trim();
    final currentUsername = '@${_usernameController.text.trim()}';
    final hasPasswordChange = _currentPasswordController.text.isNotEmpty ||
        _newPasswordController.text.isNotEmpty ||
        _confirmPasswordController.text.isNotEmpty;

    setState(() {
      _hasChanges = currentName != _originalName ||
          currentUsername != _originalUsername ||
          hasPasswordChange;
      _isChangingPassword = hasPasswordChange;
    });
  }

  void _onPasswordChanged() {
    setState(() {
      _passwordCriteria =
          PasswordValidator.validatePassword(_newPasswordController.text);
      _showPasswordCriteria = _newPasswordController.text.isNotEmpty;
      if (_confirmPasswordController.text.isNotEmpty) {
        _checkPasswordMatch();
      }
    });
  }

  void _onConfirmPasswordChanged() {
    setState(() {
      _checkPasswordMatch();
    });
  }

  void _checkPasswordMatch() {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (confirmPassword.isEmpty) {
      _passwordsMatch = true;
      _passwordMatchError = '';
    } else if (newPassword != confirmPassword) {
      _passwordsMatch = false;
      _passwordMatchError = 'Le password non corrispondono';
    } else {
      _passwordsMatch = true;
      _passwordMatchError = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    final currentUser = AuthService().currentUser;

    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      appBar: AppBar(
        backgroundColor: themeColors.mainBackgroundColor,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          'Modifica Profilo',
          style: TextStyle(
            color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: ThemeHelpers.getIconColor(widget.isDarkTheme), size: 28),
          onPressed: () => _handleBackPress(),
        ),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveProfile,
              child: Text(
                'Salva',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
        toolbarHeight: 80,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Foto profilo
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.blue,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 8),

              Center(
                child: TextButton(
                  onPressed: () => _showComingSoon('Modifica foto profilo'),
                  child: Text(
                    'Cambia foto profilo',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 32),

              // Nome completo
              Text(
                'Nome completo',
                style: TextStyle(
                  color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: TextStyle(color: Colors.black87),
                textCapitalization: TextCapitalization.words,
                decoration: _getInputDecoration(
                    'Il tuo nome completo', Icons.person_outline),
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return 'Il nome è obbligatorio';
                  }
                  if (value!.trim().length < 2) {
                    return 'Il nome deve avere almeno 2 caratteri';
                  }
                  return null;
                },
              ),

              SizedBox(height: 20),

              // Username
              Text(
                'Username',
                style: TextStyle(
                  color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              TextFormField(
                controller: _usernameController,
                style: TextStyle(color: Colors.black87),
                decoration:
                    _getInputDecoration('username', Icons.alternate_email)
                        .copyWith(
                  prefixText: '@',
                  prefixStyle: TextStyle(color: Colors.black87, fontSize: 16),
                ),
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return 'L\'username è obbligatorio';
                  }
                  if (value!.trim().length < 3) {
                    return 'L\'username deve avere almeno 3 caratteri';
                  }
                  if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(value.trim())) {
                    return 'Username può contenere solo lettere, numeri, punti e underscore';
                  }
                  return null;
                },
              ),

              SizedBox(height: 20),

              // Email (non modificabile)
              Text(
                'Email',
                style: TextStyle(
                  color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email_outlined, color: Colors.grey.shade600),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        currentUser?.email ?? 'email@esempio.com',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Icon(Icons.lock_outline,
                        color: Colors.grey.shade400, size: 20),
                  ],
                ),
              ),

              SizedBox(height: 8),

              Text(
                'L\'email non può essere modificata per motivi di sicurezza',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),

              SizedBox(height: 32),

              // Sezione cambio password
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Cambia Password',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 16),

                    // Password attuale
                    Text(
                      'Password attuale',
                      style: TextStyle(
                        color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _currentPasswordController,
                      style: TextStyle(color: Colors.black87),
                      obscureText: _obscureCurrentPassword,
                      decoration: _getInputDecoration(
                        'Inserisci la password attuale',
                        Icons.lock_outline,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureCurrentPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureCurrentPassword =
                                  !_obscureCurrentPassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (_isChangingPassword &&
                            (value?.trim().isEmpty ?? true)) {
                          return 'Inserisci la password attuale per confermare';
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: 16),

                    // Nuova password
                    Text(
                      'Nuova password',
                      style: TextStyle(
                        color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _newPasswordController,
                      style: TextStyle(color: Colors.black87),
                      obscureText: _obscureNewPassword,
                      decoration: _getInputDecoration(
                        'Crea una nuova password sicura',
                        Icons.lock_outline,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNewPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureNewPassword = !_obscureNewPassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (_isChangingPassword) {
                          return PasswordValidator.getPasswordError(
                              value ?? '');
                        }
                        return null;
                      },
                    ),

                    // Criteri password
                    if (_showPasswordCriteria) ...[
                      SizedBox(height: 12),
                      _buildPasswordCriteria(),
                    ],

                    SizedBox(height: 16),

                    // Conferma nuova password
                    Text(
                      'Conferma nuova password',
                      style: TextStyle(
                        color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmPasswordController,
                      style: TextStyle(color: Colors.black87),
                      obscureText: _obscureConfirmPassword,
                      decoration: _getInputDecoration(
                        'Ripeti la nuova password',
                        Icons.lock_outline,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color:
                                  !_passwordsMatch ? Colors.red : Colors.black,
                              width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color:
                                  !_passwordsMatch ? Colors.red : Colors.blue,
                              width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (_isChangingPassword) {
                          if (value?.trim().isEmpty ?? true) {
                            return 'Conferma la nuova password';
                          }
                          if (value != _newPasswordController.text) {
                            return 'Le password non corrispondono';
                          }
                        }
                        return null;
                      },
                    ),

                    // Messaggio errore password match
                    if (!_passwordsMatch && _passwordMatchError.isNotEmpty) ...[
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _passwordMatchError,
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
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

              SizedBox(height: 40),

              // Pulsante salva
              if (_hasChanges)
                Container(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.black, width: 1),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Salva Modifiche',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

              SizedBox(height: 32),
            ],
          ),
        ),
      ),

      // Barra di navigazione bassa
      bottomNavigationBar: CustomBottomNavigationBar(
        isDarkTheme: widget.isDarkTheme,
        onHomeTap: () => Navigator.popUntil(context, (route) => route.isFirst),
        onAddTap: () {},
        onAccountTap: () => Navigator.pop(context),
        isAccountActive: true,
      ),
    );
  }

  Widget _buildPasswordCriteria() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Requisiti password:',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 12),
          ..._passwordCriteria
              .map((criterion) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          criterion.isValid
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: criterion.isValid
                              ? Colors.green
                              : Colors.grey.shade400,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Icon(criterion.icon,
                            color: Colors.grey.shade600, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            criterion.description,
                            style: TextStyle(
                              color: criterion.isValid
                                  ? Colors.green
                                  : Colors.grey.shade600,
                              fontSize: 13,
                              fontWeight: criterion.isValid
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ],
      ),
    );
  }

  InputDecoration _getInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade600),
      prefixIcon: Icon(icon, color: Colors.grey.shade600),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  void _handleBackPress() {
    if (_hasChanges) {
      _showUnsavedChangesDialog();
    } else {
      Navigator.pop(context);
    }
  }

  void _showUnsavedChangesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            SizedBox(width: 12),
            Text(
              'Modifiche non salvate',
              style:
                  TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Hai delle modifiche non salvate. Vuoi uscire senza salvare?',
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child:
                Text('Esci senza salvare', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveProfile();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('Salva e esci'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final newName = _nameController.text.trim();
      final newUsername = '@${_usernameController.text.trim()}';

      bool success = false;

      if (_isChangingPassword) {
        // Verifica password attuale
        final currentPassword = _currentPasswordController.text;
        const demoPassword = 'demo123'; // Password demo per testing

        if (currentPassword != demoPassword) {
          _showErrorDialog('Password attuale non corretta');
          setState(() => _isLoading = false);
          return;
        }

        // Aggiorna profilo e password
        success = await AuthService().updateUserProfileAndPassword(
          name: newName,
          username: newUsername,
          newPassword: _newPasswordController.text,
        );
      } else {
        // Aggiorna solo il profilo
        success = await AuthService().updateUserProfile(
          name: newName,
          username: newUsername,
        );
      }

      if (success) {
        _showSuccessDialog();
      } else {
        _showErrorDialog('Errore durante il salvataggio delle modifiche');
      }
    } catch (e) {
      _showErrorDialog('Errore durante il salvataggio: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text(
              'Profilo aggiornato!',
              style:
                  TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Le tue informazioni sono state salvate con successo.',
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
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

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text(
              'Errore',
              style:
                  TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(String feature) {}
}
