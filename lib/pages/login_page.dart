import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import necessario per TextInput
import 'package:flutter/gestures.dart';
import '../utils/theme_helpers.dart';
import '../services/auth_service.dart';
import 'registration_page.dart';
import '../main.dart';

// PAGINA DI LOGIN CORRETTA - NON SERVE PIÃ™ NAVIGAZIONE MANUALE
class LoginPage extends StatefulWidget {
  final bool isDarkTheme;
  final Function(bool) onThemeChanged;

  const LoginPage({
    Key? key,
    required this.isDarkTheme,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _showWelcomeBack = false;

  // Animazione
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _loadSavedCredentials() async {
    final savedEmail = await AuthService().getRememberedEmail();
    if (savedEmail != null && savedEmail.isNotEmpty) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
        _showWelcomeBack = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);

    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 40),
                  _buildHeader(themeColors),
                  SizedBox(height: 48),
                  _buildGoogleSignInButton(themeColors),
                  SizedBox(height: 24),
                  _buildDivider(themeColors),
                  SizedBox(height: 24),
                  _buildLoginForm(themeColors),
                  SizedBox(height: 24),
                  _buildRememberAndForgotSection(themeColors),
                  SizedBox(height: 32),
                  _buildLoginButton(themeColors),
                  SizedBox(height: 32),
                  _buildSignUpLink(themeColors),
                  SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/icon/app_logo_internal.png',
                  width: 52,
                  height: 52,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/icon/SaveIn!.png',
                  height: 80,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: 4),
                Text(
                  'Organizza il web',
                  style: TextStyle(
                    color: themeColors.subtitleColor,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: 32),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 300),
          child: _showWelcomeBack
              ? Column(
                  key: ValueKey('welcome_back'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bentornato!',
                      style: TextStyle(
                        color: themeColors.titleColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'I tuoi contenuti ti aspettano',
                      style: TextStyle(
                        color: themeColors.subtitleColor,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ],
                )
              : Column(
                  key: ValueKey('sign_in'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Accedi al tuo account',
                      style: TextStyle(
                        color: themeColors.titleColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Accedi per gestire i tuoi contenuti salvati',
                      style: TextStyle(
                        color: themeColors.subtitleColor,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildGoogleSignInButton(ThemeColors themeColors) {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith<Color>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.disabled)) {
                return Colors.grey.shade300;
              }
              return Colors.white;
            },
          ),
          foregroundColor: MaterialStateProperty.resolveWith<Color>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.pressed)) {
                return Colors.black87;
              }
              if (states.contains(MaterialState.disabled)) {
                return Colors.grey.shade400;
              }
              return Colors.black87;
            },
          ),
          overlayColor: MaterialStateProperty.all(Colors.grey.shade100),
          surfaceTintColor: MaterialStateProperty.all(Colors.transparent),
          elevation: MaterialStateProperty.all(2),
          padding:
              MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 16)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.black, width: 1),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.g_mobiledata, color: Colors.white, size: 16),
            ),
            SizedBox(width: 12),
            Text(
              'Continua con Google',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(ThemeColors themeColors) {
    return Row(
      children: [
        Expanded(child: Divider(color: themeColors.hintColor)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'oppure',
            style: TextStyle(
              color: themeColors.hintColor,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(child: Divider(color: themeColors.hintColor)),
      ],
    );
  }

  Widget _buildLoginForm(ThemeColors themeColors) {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Email',
              style: TextStyle(
                color: themeColors.titleColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              style: TextStyle(color: Colors.black87),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.username
              ],
              decoration: _getInputDecoration(
                'Inserisci la tua email',
                Icons.email_outlined,
              ),
              validator: (value) {
                if (value?.trim().isEmpty ?? true) {
                  return 'L\'email è obbligatoria';
                }
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                    .hasMatch(value!)) {
                  return 'Inserisci un\'email valida';
                }
                return null;
              },
            ),
            SizedBox(height: 20),
            Text(
              'Password',
              style: TextStyle(
                color: themeColors.titleColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              style: TextStyle(color: Colors.black87),
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              decoration: _getInputDecoration(
                'Inserisci la tua password',
                Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              onEditingComplete: () => TextInput.finishAutofillContext(),
              validator: (value) {
                if (value?.trim().isEmpty ?? true) {
                  return 'La password è obbligatoria';
                }
                if (value!.length < 6) {
                  return 'La password deve avere almeno 6 caratteri';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRememberAndForgotSection(ThemeColors themeColors) {
    return Row(
      children: [
        Row(
          children: [
            Checkbox(
              value: _rememberMe,
              onChanged: (value) {
                setState(() {
                  _rememberMe = value ?? false;
                });
              },
              activeColor: Colors.blue,
              checkColor: Colors.white,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Text(
              'Ricordami',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Spacer(),
        GestureDetector(
          onTap: _showForgotPasswordDialog,
          child: Text(
            'Password dimenticata?',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton(ThemeColors themeColors) {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signInWithEmail,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.blue.withOpacity(0.6),
          disabledForegroundColor: Colors.black,
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
                  color: Colors.black,
                ),
              )
            : Text(
                'Accedi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildSignUpLink(ThemeColors themeColors) {
    return Center(
      child: RichText(
        text: TextSpan(
          text: 'Non hai ancora un account? ',
          style: TextStyle(
            color: themeColors.subtitleColor,
            fontSize: 16,
          ),
          children: [
            TextSpan(
              text: 'Registrati',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RegistrationPage(
                        isDarkTheme: widget.isDarkTheme,
                        onThemeChanged: widget.onThemeChanged,
                      ),
                    ),
                  );
                },
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _getInputDecoration(String hint, IconData icon,
      {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade600),
      prefixIcon: Icon(icon, color: Colors.grey.shade600),
      suffixIcon: suffixIcon,
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

  // LOGIN CON EMAIL - CORRETTO: NON FA PIÃ™ NAVIGAZIONE MANUALE
  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      print('DEBUG: Tentativo login email: ${_emailController.text}');

      final result = await AuthService().loginUser(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );

      if (result.success && result.user != null) {
        print(
            'DEBUG: LOGIN EMAIL RIUSCITO - AuthWrapper si aggiornerÃ  automaticamente');

        // CRITICO: Mostra solo feedback e lascia che AuthWrapper gestisca la navigazione
        _showSuccessSnackBar(
            'Login completato! Benvenuto ${result.user!.name.split(' ').first}!');

        // Forza il salvataggio delle credenziali con TextInput
        TextInput.finishAutofillContext();

        // AuthWrapper sta ascoltando AuthService e mostrerÃ  automaticamente WebHomePage
      } else {
        print('DEBUG: LOGIN EMAIL FALLITO: ${result.message}');
        _showErrorDialog(result.message ?? 'Credenziali non corrette');
      }
    } catch (e) {
      print('ERRORE: Login email: $e');
      _showErrorDialog(
          'Errore durante il login. Verifica la connessione internet.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // GOOGLE SIGN-IN - CORRETTO: CONSIDERA ANCHE FIREBASE AUTH STATUS
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      print('DEBUG: Tentativo Google Sign-In');

      final result = await AuthService().loginWithGoogle();

      // ðŸ”¥ CORREZIONE: Controlla anche se Firebase Auth ha l'utente
      final firebaseHasUser = AuthService().isLoggedIn;

      if (result.success || firebaseHasUser) {
        print(
            'DEBUG: GOOGLE SIGN-IN RIUSCITO - AuthWrapper si aggiornerÃ  automaticamente');

        final userName =
            result.user?.name ?? AuthService().currentUser?.name ?? 'Utente';
        _showSuccessSnackBar(
            'Login Google completato! Benvenuto ${userName.split(' ').first}!');

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => WebHomePage(
              isDarkTheme: widget.isDarkTheme,
              marketingProfileEnabled: false,
              marketingCommsEnabled: false,
              onThemeChanged: widget.onThemeChanged,
              onMarketingProfileChanged: (value) {},
              onMarketingCommsChanged: (value) {},
              onSharedContent: (content) {},
            ),
          ),
          (route) => false,
        );
      } else {
        print('DEBUG: GOOGLE SIGN-IN FALLITO: ${result.message}');
        final pendingGoogleEmail = AuthService().pendingGoogleEmail;
        if (pendingGoogleEmail != null && pendingGoogleEmail.isNotEmpty) {
          _emailController.text = pendingGoogleEmail;
          _rememberMe = true;
        }
        _showErrorDialog(
            result.message ?? 'Errore durante il login con Google');
      }
    } catch (e) {
      print('ERRORE: Google Sign-In: $e');

      // ðŸ”¥ CORREZIONE: Anche in caso di errore, controlla Firebase Auth
      final firebaseHasUser = AuthService().isLoggedIn;
      if (firebaseHasUser) {
        print('DEBUG: Errore nell\'UI ma Firebase Auth Google ha successo');
        _showSuccessSnackBar('Login Google completato!');
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => WebHomePage(
              isDarkTheme: widget.isDarkTheme,
              marketingProfileEnabled: false,
              marketingCommsEnabled: false,
              onThemeChanged: widget.onThemeChanged,
              onMarketingProfileChanged: (value) {},
              onMarketingCommsChanged: (value) {},
              onSharedContent: (content) {},
            ),
          ),
          (route) => false,
        );
      } else {
        _showErrorDialog(
            'Errore durante l\'autenticazione con Google. Verifica la connessione.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showForgotPasswordDialog() {
    final TextEditingController emailController = TextEditingController(
      text: _emailController.text,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.blue, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Password Dimenticata',
                style: TextStyle(
                    color: Colors.black87, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inserisci la tua email per ricevere le istruzioni per reimpostare la password.',
              style: TextStyle(color: Colors.black54),
            ),
            SizedBox(height: 16),
            TextField(
              controller: emailController,
              style: TextStyle(color: Colors.black87),
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: Colors.grey.shade600),
                prefixIcon:
                    Icon(Icons.email_outlined, color: Colors.grey.shade600),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;

              Navigator.pop(context);

              setState(() => _isLoading = true);
              await AuthService().sendPasswordResetEmail(email);
              if (mounted) setState(() => _isLoading = false);

              if (mounted) _showResetEmailSentDialog(email);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('Invia'),
          ),
        ],
      ),
    );
  }

  void _showResetEmailSentDialog(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.mark_email_read, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Email Inviata!',
                style: TextStyle(
                    color: Colors.black87, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Abbiamo inviato le istruzioni per reimpostare la password a:',
              style: TextStyle(color: Colors.black54),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                email,
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Controlla la tua casella email e segui le istruzioni.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // CORRETTO: Solo SnackBar, no navigazione
  void _showSuccessSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showErrorDialog(String message) {
    final isBlockedMessage = message.toLowerCase().contains('account bloccato');
    final title = isBlockedMessage ? 'Account bloccato' : 'Errore di Login';
    final icon = isBlockedMessage ? Icons.block : Icons.error;
    final iconColor = isBlockedMessage ? Colors.orange.shade700 : Colors.red;
    final visibleMessage = isBlockedMessage
        ? message.replaceFirst(RegExp(r'^Account bloccato:\s*'), '')
        : message;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: iconColor, size: 28),
            SizedBox(width: 12),
            Text(
              title,
              style:
                  TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          visibleMessage,
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
