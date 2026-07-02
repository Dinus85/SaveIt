import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:savein/models/folder.dart';
import 'package:savein/utils/theme_helpers.dart';
import 'package:savein/pages/simple_stats_page.dart';
import 'package:savein/pages/privacy_policy_page.dart';
import 'package:savein/pages/terms_conditions_page.dart';
import 'package:savein/pages/marketing_communications_page.dart';
import 'package:savein/services/access_control_service.dart';
import 'package:savein/services/auth_service.dart';
import 'package:savein/services/billing_service.dart';
import 'package:savein/services/promo_popup_service.dart';
import 'package:savein/pages/login_page.dart';
import 'package:savein/pages/help_center_page.dart';
import 'package:savein/pages/contact_page.dart';
import 'package:savein/pages/auth_wrapper.dart';
import 'package:savein/widgets/custom_bottom_nav.dart';
import 'package:savein/widgets/first_launch_tutorial_dialog.dart';
import 'package:savein/widgets/new_signup_premium_promo_dialog.dart';
import 'package:savein/data_service.dart';
import 'package:savein/services/folder_service.dart';

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
  final Function(bool) onThemeChanged;

  const _AccountDeletionLoadingPageReactive({
    Key? key,
    required this.isDarkTheme,
    required this.onThemeChanged,
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

              // Forza la Login: in alcune navigazioni la root e' gia' la Home.
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => LoginPage(
                      isDarkTheme: widget.isDarkTheme,
                      onThemeChanged: widget.onThemeChanged,
                    ),
                  ),
                  (route) => false,
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

  int _getTotalPosts() {
    return FolderService().getAccountStats()['totalPosts'] ?? 0;
  }

  int _getTotalFolders() {
    return FolderService().getAccountStats()['totalFolders'] ?? 0;
  }

  String _formatBirthDate(DateTime? birthDate) {
    if (birthDate == null) return 'Da inserire';
    final day = birthDate.day.toString().padLeft(2, '0');
    final month = birthDate.month.toString().padLeft(2, '0');
    return '$day/$month/${birthDate.year}';
  }

  String _formatGender(String? gender) {
    switch ((gender ?? '').trim().toLowerCase()) {
      case 'maschio':
        return 'Maschio';
      case 'femmina':
        return 'Femmina';
      case 'preferisco_non_dirlo':
      case 'preferisco non dirlo':
        return 'Preferisco non dirlo';
      default:
        return 'Da inserire';
    }
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

  Future<void> _showTutorial(BuildContext context) async {
    await SaveInFirstLaunchTutorial.show(context);
  }

  Future<void> _showVersionInfo(BuildContext context) async {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;
    final packageInfo = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Image.asset(
              'assets/icon/SaveIn!.png',
              height: 44,
              fit: BoxFit.contain,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Versione corrente',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versione: ${packageInfo.version}',
                style: TextStyle(color: subtitleColor)),
            SizedBox(height: 8),
            Text('Build: ${packageInfo.buildNumber}',
                style: TextStyle(color: subtitleColor)),
            SizedBox(height: 8),
            Text('Piattaforma: ${_currentPlatformLabel()}',
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

  String _currentPlatformLabel() {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
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
      builder: (dialogContext) => AlertDialog(
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
    final pageContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Annulla', style: TextStyle(color: hintColor)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              print('DEBUG: Iniziando logout da AccountPage');

              await AuthService().logout();
              if (!pageContext.mounted) return;

              print('DEBUG: Logout completato - navigazione forzata a LoginPage');
              Navigator.of(pageContext, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => LoginPage(
                    isDarkTheme: isDarkTheme,
                    onThemeChanged: onThemeChanged,
                  ),
                ),
                (route) => false,
              );
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
          onThemeChanged: onThemeChanged,
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
        final String displayRole = AppAccessService()
            .roleLabel(currentUser?.effectiveRole ?? AppUserRole.free);

        return Scaffold(
          backgroundColor: backgroundColor,
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    border: Border(
                      bottom: BorderSide(
                        color: isDarkTheme
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: navIconColor, size: 28),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Account',
                          style: TextStyle(
                            color: appBarTextColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (currentUser != null)
                        LogoutButton(onLogoutComplete: () {}),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profilo utente
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoRow('Nome:', displayName, cardTextColor,
                                  cardSubtitleColor),
                              const SizedBox(height: 12),
                              _buildInfoRow('Email:', displayEmail,
                                  cardTextColor, cardSubtitleColor),
                              const SizedBox(height: 12),
                              _buildInfoRow('Username:', displayUsername,
                                  cardTextColor, cardSubtitleColor),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                  'Data di nascita:',
                                  _formatBirthDate(currentUser?.birthDate),
                                  cardTextColor,
                                  cardSubtitleColor),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                  'Sesso:',
                                  _formatGender(currentUser?.gender),
                                  cardTextColor,
                                  cardSubtitleColor),
                              const SizedBox(height: 12),
                              _buildInfoRow('Piano:', displayRole,
                                  cardTextColor, cardSubtitleColor),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                  'Statistiche:',
                                  '${_getTotalPosts()} Post | ${_getTotalFolders()} Cartelle',
                                  cardTextColor,
                                  cardSubtitleColor),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                        _buildCrossPromoAccountBanner(),
                        const SizedBox(height: 8),
                        _buildPlanCard(
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
                        const SizedBox(height: 12),

                        _buildOptionCard(
                          'Modifica Profilo',
                          'Nome, username, data di nascita e sesso',
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

                        const SizedBox(height: 24),

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
                          (newValue) =>
                              _handleMarketingCommsChange(context, newValue),
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
                          'Rivedi tutorial',
                          'Guarda di nuovo i 3 passaggi iniziali',
                          Icons.slideshow_outlined,
                          cardColor,
                          cardTextColor,
                          cardSubtitleColor,
                          () => _showTutorial(context),
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
                            padding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
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
                ),
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
    try {
      final result = await AuthService().activateSmartChefLaunchPromo();
      if (!context.mounted) return;

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
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildCrossPromoAccountBanner() {
    return FutureBuilder<PromotionBanner?>(
      future: PromoPopupService.getAccountBanner(),
      builder: (context, snapshot) {
        final banner = snapshot.data;
        if (banner == null) return SizedBox.shrink();
        if (!banner.isCrossPromo) {
          return _buildGenericPromoAccountBanner(banner);
        }
        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Color(0xFFFFFBF5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Color(0xFFFFB74D), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: Color(0xFFFF9800).withValues(alpha: 0.14),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (banner.imageUrl.trim().isNotEmpty)
                AspectRatio(
                  aspectRatio: 3,
                  child: Image.network(
                    banner.imageUrl.trim(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner.title.isNotEmpty
                          ? '🎁 ${banner.title}'
                          : '🎁 Promo SaveIn + SmartChef',
                      style: TextStyle(
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      banner.message.isNotEmpty
                          ? banner.message
                          : 'Attiva il vantaggio e completalo usando la stessa email in entrambe le app.',
                      style: TextStyle(
                        color: Color(0xFF6B4E16),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 12),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
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
                            label: Text(
                              banner.ctaLabel.isNotEmpty
                                  ? banner.ctaLabel
                                  : 'Attiva promo',
                            ),
                          ),
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
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGenericPromoAccountBanner(PromotionBanner banner) {
    final hasActionUrl = banner.actionUrl.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(0xFFB8E6DC), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (banner.imageUrl.trim().isNotEmpty)
            AspectRatio(
              aspectRatio: 3,
              child: Image.network(
                banner.imageUrl.trim(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner.title.isNotEmpty ? banner.title : 'Promo SaveIn',
                  style: TextStyle(
                    color: Color(0xFF2C5F5D),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                if (banner.message.trim().isNotEmpty) ...[
                  SizedBox(height: 6),
                  Text(
                    banner.message,
                    style: TextStyle(
                      color: Color(0xFF344054),
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
                if (hasActionUrl) ...[
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await AuthService().recordPromotionBannerEvent(
                          promotionId: banner.id,
                          eventType: 'click',
                          placement: 'savein_account',
                        );
                        final uri = Uri.tryParse(banner.actionUrl.trim());
                        if (uri == null) return;
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: Icon(Icons.open_in_new),
                      label: Text(
                        banner.ctaLabel.trim().isNotEmpty
                            ? banner.ctaLabel
                            : 'Scopri',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
    final role = currentUser?.effectiveRole ?? AppUserRole.free;
    final premiumUntil = currentUser?.premiumUntil;
    final showPremiumExpiry =
        role == AppUserRole.premium || role == AppUserRole.admin;

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
          if (role == AppUserRole.free) ...[
            _buildNewSignupPromoAccountNotice(context),
          ],
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
          if (showPremiumExpiry) ...[
            SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.event_available_rounded,
                    color: Color(0xFF15803D),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      premiumUntil == null
                          ? 'Scadenza Premium: senza scadenza'
                          : 'Scadenza Premium: ${_formatDate(premiumUntil)}',
                      style: const TextStyle(
                        color: Color(0xFF14532D),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10),
            _buildManageSubscriptionBox(context),
          ],
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              onPressed: () => _showPlanComparisonSlides(context),
              icon: const Icon(Icons.compare_arrows_outlined),
              label: const Text('Vedi differenze Free/Premium'),
            ),
          ),
          if (role == AppUserRole.free) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                onPressed: () =>
                    _showPlanComparisonSlides(context, startAtPremium: true),
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('Diventa Premium'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManageSubscriptionBox(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.autorenew_rounded,
                color: Color(0xFF2563EB),
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rinnovo automatico gestito dallo store',
                  style: TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Puoi attivare o disattivare il rinnovo dalla schermata ufficiale '
            'degli abbonamenti Apple/Google. SaveIn aggiorna piano e scadenza '
            'quando lo store conferma rinnovi o scadenze.',
            style: TextStyle(
              color: Color(0xFF1E40AF),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _openStoreSubscriptions(context),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Gestisci rinnovo automatico'),
          ),
        ],
      ),
    );
  }

  Future<void> _openStoreSubscriptions(BuildContext context) async {
    final uri = _storeSubscriptionsUri();
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gestione abbonamenti non disponibile su questa piattaforma',
          ),
        ),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Uri? _storeSubscriptionsUri() {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return Uri.parse('itms-apps://apps.apple.com/account/subscriptions');
      case TargetPlatform.android:
        return Uri.parse(
          'https://play.google.com/store/account/subscriptions'
          '?package=eu.savein.app&sku=$kSaveInPremiumProductId',
        );
      default:
        return null;
    }
  }

  void _showPlanComparisonSlides(
    BuildContext context, {
    bool startAtPremium = false,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => _PlanComparisonSlidesDialog(
        initialPage: startAtPremium ? 2 : 0,
      ),
    );
  }

  Widget _buildNewSignupPromoAccountNotice(BuildContext context) {
    return FutureBuilder<NewSignupPremiumPromoConfig?>(
      future: AuthService().getNewSignupPremiumPromoConfig(),
      builder: (context, snapshot) {
        final config = snapshot.data;
        if (config == null) return const SizedBox.shrink();

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openNewSignupPremiumPromo(context),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF2563EB).withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.card_giftcard,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Promo attiva: ${config.durationDays} giorni Premium gratis',
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Tocca qui per vedere le slide e attivarla.',
                        style: TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF2563EB)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openNewSignupPremiumPromo(BuildContext context) async {
    final config = await AuthService().getNewSignupPremiumPromoConfig();
    if (!context.mounted || config == null) {
      return;
    }

    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => NewSignupPremiumPromoDialog(
            durationDays: config.durationDays,
            priceAfterTrial: config.priceAfterTrial,
          ),
        ) ??
        false;
    if (!context.mounted || !accepted) return;

    try {
      final premiumUntil = await AuthService().activateNewSignupPremiumPromo();
      if (!context.mounted) return;
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
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _PlanComparisonSlidesDialog extends StatefulWidget {
  final int initialPage;

  const _PlanComparisonSlidesDialog({
    this.initialPage = 0,
  });

  @override
  State<_PlanComparisonSlidesDialog> createState() =>
      _PlanComparisonSlidesDialogState();
}

class _PlanComparisonSlidesDialogState
    extends State<_PlanComparisonSlidesDialog> {
  static final Uri _privacyPolicyUri = Uri.parse('https://savein.eu/privacy');
  static final Uri _termsUri = Uri.parse('https://savein.eu/terms');

  late final PageController _controller;
  late int _index;
  ProductDetails? _product;
  bool _loadingProduct = true;
  bool _purchasing = false;
  bool _restoring = false;

  static const _slides = [
    _PlanSlideData(
      icon: Icons.folder_copy_outlined,
      title: '📁 Cartelle e sottocartelle',
      freeText:
          'Con Free puoi creare fino a 10 cartelle nella home, con profondità home + 1 livello e massimo 4 sottocartelle per cartella.',
      premiumText:
          'Con Premium superi i limiti Free: più cartelle, più livelli e più libertà per organizzare tutti i contenuti.',
      color: Color(0xFF2C7A7B),
    ),
    _PlanSlideData(
      icon: Icons.tag_outlined,
      title: '🏷️ Tag e ricerca',
      freeText:
          'Con Free puoi cercare nei contenuti salvati e usare gli hashtag automatici quando vengono estratti dal contenuto.',
      premiumText:
          'Con Premium puoi aggiungere anche tag manuali, così rendi ogni salvataggio più facile da ritrovare.',
      color: Color(0xFF2563EB),
    ),
    _PlanSlideData(
      icon: Icons.block_outlined,
      title: '🚀 Pubblicità',
      freeText:
          'Con Free possono essere mostrati annunci durante l’uso dell’app.',
      premiumText:
          'Con Premium usi SaveIn senza annunci e con un’esperienza più fluida ✨',
      color: Color(0xFFEA580C),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialPage.clamp(0, _slides.length - 1).toInt();
    _controller = PageController(initialPage: _index);
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    if (!BillingService.isSupportedPlatform) {
      if (mounted) setState(() => _loadingProduct = false);
      return;
    }
    final product = await BillingService.loadProduct();
    if (!mounted) return;
    setState(() {
      _product = product;
      _loadingProduct = false;
    });
  }

  Future<void> _purchasePremium() async {
    final product = _product;
    if (product == null || _purchasing) return;
    setState(() => _purchasing = true);
    try {
      final result = await BillingService.purchaseAndVerify(product);
      await AuthService().reloadCurrentUserFromFirestore();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Premium attivo fino al ${_formatPremiumDate(result.premiumUntil)}.',
          ),
          backgroundColor: const Color(0xFF15803D),
        ),
      );
    } on BillingException catch (e) {
      if (!mounted) return;
      if (e.code != BillingErrorCode.purchaseCancelled) {
        _showBillingMessage(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      _showBillingMessage('Acquisto non riuscito. Riprova.');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restorePremium() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final result = await BillingService.restorePurchases();
      if (result != null) {
        await AuthService().reloadCurrentUserFromFirestore();
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Premium ripristinato fino al ${_formatPremiumDate(result.premiumUntil)}.',
            ),
            backgroundColor: const Color(0xFF15803D),
          ),
        );
        return;
      }
      _showBillingMessage('Nessun abbonamento attivo da ripristinare.');
    } on BillingException catch (e) {
      if (!mounted) return;
      _showBillingMessage(e.message);
    } catch (_) {
      if (!mounted) return;
      _showBillingMessage('Ripristino non riuscito. Riprova.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _showBillingMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openLegalUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatPremiumDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page < 0 || page >= _slides.length) return;
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
    final height = size.height < 720 ? size.height * 0.82 : 560.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFF111827)),
          child: IconTheme(
            data: const IconThemeData(color: Color(0xFF111827)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF2563EB),
                                    Color(0xFF7C3AED)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.diamond_outlined,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Free vs Premium',
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) {
                      return _PlanComparisonSlide(slide: _slides[index]);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    children: [
                      if (_index == _slides.length - 1 &&
                          BillingService.isSupportedPlatform) ...[
                        if (_loadingProduct)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_product != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: (_purchasing || _restoring)
                                  ? null
                                  : _purchasePremium,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                _purchasing
                                    ? 'Acquisto in corso...'
                                    : 'Passa a Premium (${_product!.price}/mese)',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _SubscriptionDisclosure(
                            price: _product!.price,
                            onOpenPrivacy: () =>
                                _openLegalUrl(_privacyPolicyUri),
                            onOpenTerms: () => _openLegalUrl(_termsUri),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: (_purchasing || _restoring)
                                ? null
                                : _restorePremium,
                            child: Text(
                              _restoring
                                  ? 'Ripristino...'
                                  : 'Ripristina acquisti',
                            ),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Abbonamento non ancora disponibile su questo store.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                      Row(
                        children: [
                          IconButton(
                            onPressed:
                                _index == 0 ? null : () => _goTo(_index - 1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _slides.length,
                                (i) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _index ? 18 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: i == _index
                                        ? _slides[_index].color
                                        : Colors.black26,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_index == _slides.length - 1)
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Chiudi'),
                            )
                          else
                            IconButton(
                              onPressed: () => _goTo(_index + 1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionDisclosure extends StatelessWidget {
  final String price;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenTerms;

  const _SubscriptionDisclosure({
    required this.price,
    required this.onOpenPrivacy,
    required this.onOpenTerms,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: Colors.grey.shade700,
      fontSize: 11.5,
      height: 1.35,
    );
    final linkStyle = textStyle.copyWith(
      color: const Color(0xFF2563EB),
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SaveIn Premium: abbonamento mensile con rinnovo automatico a '
            '$price al mese.',
            style: textStyle,
          ),
          const SizedBox(height: 4),
          Text(
            'Il pagamento viene addebitato sull’Apple ID. L’abbonamento si '
            'rinnova automaticamente salvo disdetta almeno 24 ore prima della '
            'scadenza. Puoi gestirlo o annullarlo in Impostazioni > Apple ID > '
            'Abbonamenti.',
            style: textStyle,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            children: [
              InkWell(
                onTap: onOpenPrivacy,
                child: Text('Privacy Policy', style: linkStyle),
              ),
              InkWell(
                onTap: onOpenTerms,
                child: Text('Termini di utilizzo (EULA)', style: linkStyle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanComparisonSlide extends StatelessWidget {
  final _PlanSlideData slide;

  const _PlanComparisonSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 110,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  slide.color,
                  Color.lerp(slide.color, Colors.black, 0.18)!,
                ],
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: slide.color.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(slide.icon, size: 38, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    slide.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PlanInfoBox(
            title: 'Free',
            text: slide.freeText,
            color: Colors.grey.shade700,
          ),
          const SizedBox(height: 12),
          _PlanInfoBox(
            title: 'Premium',
            text: slide.premiumText,
            color: slide.color,
          ),
        ],
      ),
    );
  }
}

class _PlanInfoBox extends StatelessWidget {
  final String title;
  final String text;
  final Color color;

  const _PlanInfoBox({
    required this.title,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
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
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSlideData {
  final IconData icon;
  final String title;
  final String freeText;
  final String premiumText;
  final Color color;

  const _PlanSlideData({
    required this.icon,
    required this.title,
    required this.freeText,
    required this.premiumText,
    required this.color,
  });
}

// ── Launcher popup promo ──────────────────────────────────────────────────────

class _PromoLauncher extends StatefulWidget {
  final Future<void> Function(BuildContext context) onActivateCrossPromo;
  final Future<void> Function() onOpenOtherApp;

  const _PromoLauncher({
    required this.onActivateCrossPromo,
    required this.onOpenOtherApp,
  });

  @override
  State<_PromoLauncher> createState() => _PromoLauncherState();
}

class _PromoLauncherState extends State<_PromoLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PromoPopupService.showIfNeeded(
          context,
          onActivateCrossPromo: widget.onActivateCrossPromo,
          onOpenOtherApp: widget.onOpenOtherApp,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
  final _birthDateController = TextEditingController();

  bool _isLoading = false;
  bool _hasChanges = false;
  bool _isChangingPassword = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  String _originalName = '';
  String _originalUsername = '';
  DateTime? _originalBirthDate;
  String? _originalGender;

  DateTime? _birthDate;
  String? _gender;

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
    _birthDateController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final currentUser = AuthService().currentUser;
    if (currentUser != null) {
      setState(() {
        _originalName = currentUser.name;
        _originalUsername = currentUser.username ?? '@utente';
        _originalBirthDate = currentUser.birthDate;
        _originalGender = currentUser.gender;

        _nameController.text = _originalName;
        _usernameController.text = _originalUsername.replaceFirst('@', '');
        _birthDate = _originalBirthDate;
        _gender = _originalGender;

        if (_birthDate != null) {
          _birthDateController.text =
              "${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}";
        }
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
          _birthDate != _originalBirthDate ||
          _gender != _originalGender ||
          hasPasswordChange;
      _isChangingPassword = hasPasswordChange;
    });
  }

  Future<void> _selectBirthDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('it', 'IT'),
    );
    if (picked != null && picked != _birthDate) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text =
            "${picked.day}/${picked.month}/${picked.year}";
        _checkForChanges();
      });
    }
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
    final genderLocked = (_originalGender ?? '').trim().isNotEmpty;

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

              // Data di nascita
              Text(
                'Data di nascita',
                style: TextStyle(
                  color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              TextFormField(
                controller: _birthDateController,
                readOnly: true,
                onTap: _originalBirthDate != null
                    ? null
                    : () => _selectBirthDate(context),
                style: TextStyle(
                    color: _originalBirthDate != null
                        ? Colors.grey.shade600
                        : Colors.black87),
                decoration: _getInputDecoration(
                  'Seleziona la tua data di nascita',
                  Icons.calendar_today_outlined,
                ).copyWith(
                  fillColor: _originalBirthDate != null
                      ? Colors.grey.shade100
                      : Colors.white,
                  suffixIcon: _originalBirthDate != null
                      ? Icon(Icons.lock_outline,
                          color: Colors.grey.shade400, size: 20)
                      : null,
                ),
              ),
              SizedBox(height: 8),
              Text(
                _originalBirthDate != null
                    ? 'La data di nascita non può essere modificata'
                    : 'Chiediamo la tua data di nascita per offrirti sconti e regali speciali in quel periodo.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),

              SizedBox(height: 20),

              // Sesso
              Text(
                'Sesso',
                style: TextStyle(
                  color: ThemeHelpers.getTitleColor(widget.isDarkTheme),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _gender,
                dropdownColor: Colors.white,
                style: TextStyle(
                    color:
                        genderLocked ? Colors.grey.shade600 : Colors.black87),
                decoration: _getInputDecoration(
                  'Seleziona il tuo sesso',
                  Icons.people_outline,
                ).copyWith(
                  fillColor: genderLocked ? Colors.grey.shade100 : Colors.white,
                  suffixIcon: genderLocked
                      ? Icon(Icons.lock_outline,
                          color: Colors.grey.shade400, size: 20)
                      : null,
                ),
                items: [
                  DropdownMenuItem(value: 'maschio', child: Text('Maschio')),
                  DropdownMenuItem(value: 'femmina', child: Text('Femmina')),
                  DropdownMenuItem(
                      value: 'preferisco non dirlo',
                      child: Text('Preferisco non dirlo')),
                ],
                onChanged: genderLocked
                    ? null
                    : (value) {
                        setState(() {
                          _gender = value;
                          _checkForChanges();
                        });
                      },
              ),
              SizedBox(height: 8),
              Text(
                genderLocked
                    ? 'Il sesso non può essere modificato dopo il primo inserimento'
                    : 'Puoi scegliere se indicarlo ora. Dopo il primo salvataggio non sarà più modificabile.',
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
          birthDate: _birthDate,
          gender: _gender,
          newPassword: _newPasswordController.text,
        );
      } else {
        // Aggiorna solo il profilo
        success = await AuthService().updateUserProfile(
          name: newName,
          username: newUsername,
          birthDate: _birthDate,
          gender: _gender,
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
