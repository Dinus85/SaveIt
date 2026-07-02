import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import '../utils/theme_helpers.dart';
import '../pages/privacy_policy_page.dart';
import '../pages/terms_conditions_page.dart';
import '../pages/marketing_communications_page.dart';
import '../services/auth_service.dart';
import '../widgets/first_launch_tutorial_dialog.dart';
import '../main.dart'; // Aggiunto import per WebHomePage

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

// Helper class per validazione email
class EmailValidator {
  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  static String? getEmailError(String email) {
    if (email.isEmpty) return 'L\'email è obbligatoria';
    if (!isValidEmail(email)) return 'Formato email non valido';
    return null;
  }
}

class PasswordCriterion {
  final String description;
  final bool isValid;
  final IconData icon;

  PasswordCriterion(this.description, this.isValid, this.icon);
}

// PAGINA DI REGISTRAZIONE CORRETTA - APPROCCIO REATTIVO
class RegistrationPage extends StatefulWidget {
  final bool isDarkTheme;
  final Function(bool) onThemeChanged;

  const RegistrationPage({
    Key? key,
    required this.isDarkTheme,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  _RegistrationPageState createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _confirmEmailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _birthDateController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  bool _optOutMarketing = false;

  DateTime? _birthDate;
  String? _gender;

  // Stato validazione password
  List<PasswordCriterion> _passwordCriteria = [];
  bool _showPasswordCriteria = false;

  // Controllo corrispondenza password
  bool _passwordsMatch = true;
  String _passwordMatchError = '';

  // Controllo corrispondenza email
  bool _emailsMatch = true;
  String _emailMatchError = '';
  bool _isEmailValid = true;
  String _emailValidationError = '';

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onConfirmPasswordChanged);
    _emailController.addListener(_onEmailChanged);
    _confirmEmailController.addListener(_onConfirmEmailChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _confirmEmailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    setState(() {
      _passwordCriteria =
          PasswordValidator.validatePassword(_passwordController.text);
      _showPasswordCriteria = _passwordController.text.isNotEmpty;
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

  void _onEmailChanged() {
    setState(() {
      _checkEmailValidation();
      if (_confirmEmailController.text.isNotEmpty) {
        _checkEmailMatch();
      }
    });
  }

  void _onConfirmEmailChanged() {
    setState(() {
      _checkEmailMatch();
    });
  }

  void _checkEmailValidation() {
    final email = _emailController.text;

    if (email.isEmpty) {
      _isEmailValid = true;
      _emailValidationError = '';
    } else if (!EmailValidator.isValidEmail(email)) {
      _isEmailValid = false;
      _emailValidationError = 'Formato email non valido (es: nome@dominio.com)';
    } else {
      _isEmailValid = true;
      _emailValidationError = '';
    }
  }

  void _checkEmailMatch() {
    final email = _emailController.text;
    final confirmEmail = _confirmEmailController.text;

    if (confirmEmail.isEmpty) {
      _emailsMatch = true;
      _emailMatchError = '';
    } else if (email != confirmEmail) {
      _emailsMatch = false;
      _emailMatchError = 'Le email non corrispondono';
    } else {
      _emailsMatch = true;
      _emailMatchError = '';
    }
  }

  void _checkPasswordMatch() {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (confirmPassword.isEmpty) {
      _passwordsMatch = true;
      _passwordMatchError = '';
    } else if (password != confirmPassword) {
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

    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(themeColors),
              SizedBox(height: 32),
              if (_shouldShowGoogleSignIn)
                _buildGoogleSignUpButton(themeColors),
              if (_shouldShowAppleSignIn) ...[
                if (_shouldShowGoogleSignIn) SizedBox(height: 12),
                _buildAppleSignUpButton(themeColors),
              ],
              if (_shouldShowProviderDivider) ...[
                SizedBox(height: 24),
                _buildDivider(themeColors),
                SizedBox(height: 24),
              ],
              _buildRegistrationForm(themeColors),
              SizedBox(height: 24),
              _buildConsentSection(themeColors),
              SizedBox(height: 32),
              _buildSignUpButton(themeColors),
              SizedBox(height: 24),
              _buildLoginLink(themeColors),
              SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  bool get _shouldShowGoogleSignIn {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  bool get _shouldShowAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _shouldShowProviderDivider =>
      _shouldShowGoogleSignIn || _shouldShowAppleSignIn;

  Widget _buildHeader(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bookmark, color: themeColors.iconColor, size: 32),
            SizedBox(width: 12),
            Image.asset(
              'assets/icon/SaveIn!.png',
              height: 88,
              fit: BoxFit.contain,
            ),
          ],
        ),
        SizedBox(height: 16),
        Text(
          'Crea il tuo account',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Organizza i tuoi contenuti preferiti dal web in un posto sicuro',
          style: TextStyle(
            color: themeColors.subtitleColor,
            fontSize: 16,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleSignUpButton(ThemeColors themeColors) {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signUpWithGoogle,
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

  Widget _buildAppleSignUpButton(ThemeColors themeColors) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signUpWithApple,
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith<Color>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.disabled)) {
                return Colors.grey.shade400;
              }
              return Colors.black;
            },
          ),
          foregroundColor: MaterialStateProperty.all(Colors.white),
          overlayColor: MaterialStateProperty.all(Colors.white12),
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
            Icon(Icons.apple, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Text(
              'Continua con Apple',
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

  Widget _buildRegistrationForm(ThemeColors themeColors) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nome completo',
            style: TextStyle(
              color: themeColors.titleColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            style: TextStyle(color: Colors.black87),
            textCapitalization: TextCapitalization.words,
            decoration:
                _getInputDecoration('Mario Rossi', Icons.person_outline),
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
            decoration: _getInputDecoration(
                    'mario.rossi@email.com', Icons.email_outlined)
                .copyWith(
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: !_isEmailValid ? Colors.red : Colors.black,
                    width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: !_isEmailValid ? Colors.red : Colors.blue, width: 2),
              ),
            ),
            validator: (value) => EmailValidator.getEmailError(value ?? ''),
          ),
          if (!_isEmailValid && _emailValidationError.isNotEmpty) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _emailValidationError,
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
          SizedBox(height: 20),
          Text(
            'Conferma email',
            style: TextStyle(
              color: themeColors.titleColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: _confirmEmailController,
            style: TextStyle(color: Colors.black87),
            keyboardType: TextInputType.emailAddress,
            decoration:
                _getInputDecoration('Ripeti la email', Icons.email_outlined)
                    .copyWith(
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: !_emailsMatch ? Colors.red : Colors.black, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: !_emailsMatch ? Colors.red : Colors.blue, width: 2),
              ),
            ),
            validator: (value) {
              if (value?.trim().isEmpty ?? true) {
                return 'Conferma la email';
              }
              if (value != _emailController.text) {
                return 'Le email non corrispondono';
              }
              return null;
            },
          ),
          if (!_emailsMatch && _emailMatchError.isNotEmpty) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _emailMatchError,
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
            decoration: _getInputDecoration(
              'Crea una password sicura',
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
            validator: (value) =>
                PasswordValidator.getPasswordError(value ?? ''),
          ),
          if (_showPasswordCriteria) ...[
            SizedBox(height: 12),
            _buildPasswordCriteria(themeColors),
          ],
          SizedBox(height: 20),
          Text(
            'Conferma password',
            style: TextStyle(
              color: themeColors.titleColor,
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
              'Ripeti la password',
              Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: Colors.grey.shade600,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
            ).copyWith(
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: !_passwordsMatch ? Colors.red : Colors.black,
                    width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: !_passwordsMatch ? Colors.red : Colors.blue,
                    width: 2),
              ),
            ),
            validator: (value) {
              if (value?.trim().isEmpty ?? true) {
                return 'Conferma la password';
              }
              if (value != _passwordController.text) {
                return 'Le password non corrispondono';
              }
              return null;
            },
          ),
          if (!_passwordsMatch && _passwordMatchError.isNotEmpty) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
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
          SizedBox(height: 20),
          Text(
            'Data di nascita',
            style: TextStyle(
              color: themeColors.titleColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: _birthDateController,
            readOnly: true,
            onTap: () => _selectBirthDate(context),
            style: TextStyle(color: Colors.black87),
            decoration: _getInputDecoration(
              'Seleziona la tua data di nascita',
              Icons.calendar_today_outlined,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Chiediamo la tua data di nascita per offrirti sconti e regali speciali in quel periodo.',
            style: TextStyle(
              color: themeColors.subtitleColor,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Sesso',
            style: TextStyle(
              color: themeColors.titleColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _gender,
            dropdownColor: Colors.white,
            style: TextStyle(color: Colors.black87),
            decoration: _getInputDecoration(
              'Seleziona il tuo sesso',
              Icons.people_outline,
            ),
            items: [
              DropdownMenuItem(value: 'maschio', child: Text('Maschio')),
              DropdownMenuItem(value: 'femmina', child: Text('Femmina')),
              DropdownMenuItem(
                  value: 'preferisco non dirlo',
                  child: Text('Preferisco non dirlo')),
            ],
            onChanged: (value) {
              setState(() {
                _gender = value;
              });
            },
          ),
        ],
      ),
    );
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
      });
    }
  }

  Widget _buildPasswordCriteria(ThemeColors themeColors) {
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

  Widget _buildConsentSection(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Consensi richiesti',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        _buildConsentCheckbox(
          'Accetto la Privacy Policy',
          _acceptedPrivacy,
          (value) => setState(() => _acceptedPrivacy = value ?? false),
          true,
          themeColors,
          onInfoTap: () => _openPrivacyPolicy(),
        ),
        _buildConsentCheckbox(
          'Accetto i Termini e Condizioni d\'uso',
          _acceptedTerms,
          (value) => setState(() => _acceptedTerms = value ?? false),
          true,
          themeColors,
          onInfoTap: () => _openTermsConditions(),
        ),
        _buildConsentCheckbox(
          'Non voglio ricevere comunicazioni marketing (offerte, novità e suggerimenti personalizzati)',
          _optOutMarketing,
          (value) => setState(() => _optOutMarketing = value ?? false),
          false,
          themeColors,
          onInfoTap: () => _openMarketingInfo(),
        ),
      ],
    );
  }

  Widget _buildConsentCheckbox(String title, bool value,
      Function(bool?) onChanged, bool required, ThemeColors themeColors,
      {VoidCallback? onInfoTap}) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              required && !value ? Colors.red.withOpacity(0.5) : Colors.black,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blue,
          ),
          SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (required)
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  if (!required)
                    TextSpan(
                      text: ' (opzionale)',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (onInfoTap != null)
            IconButton(
              onPressed: onInfoTap,
              icon: Icon(Icons.info_outline, color: Colors.blue, size: 20),
              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.all(4),
            ),
        ],
      ),
    );
  }

  Widget _buildSignUpButton(ThemeColors themeColors) {
    final canSignUp = _acceptedPrivacy && _acceptedTerms;

    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (canSignUp && !_isLoading) ? _signUpWithEmail : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canSignUp ? Colors.white : Colors.grey.shade400,
          foregroundColor: Colors.black,
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
                'Crea Account',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
      ),
    );
  }

  Widget _buildLoginLink(ThemeColors themeColors) {
    return Center(
      child: RichText(
        text: TextSpan(
          text: 'Hai già un account? ',
          style: TextStyle(
            color: themeColors.subtitleColor,
            fontSize: 16,
          ),
          children: [
            TextSpan(
              text: 'Accedi',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.pop(context);
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

  // Metodi per aprire le policy
  void _openPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PrivacyPolicyPage(isDarkTheme: widget.isDarkTheme),
      ),
    );
  }

  void _openTermsConditions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TermsConditionsPage(isDarkTheme: widget.isDarkTheme),
      ),
    );
  }

  void _openMarketingInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MarketingCommunicationsPage(isDarkTheme: widget.isDarkTheme),
      ),
    );
  }

  // GOOGLE SIGN-UP FORZATO - NAVIGAZIONE DOPO SINCRONIZZAZIONE COMPLETA
  Future<void> _signUpWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final result = await AuthService().loginWithGoogle();

      if (result.success && result.user != null) {
        final userName = result.user!.name.split(' ').first;

        // NAVIGAZIONE FORZATA IMMEDIATA - LA SINCRONIZZAZIONE È GIÀ COMPLETA
        if (mounted) {
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
                    )),
            (route) => false,
          );

          // Mostra popup di benvenuto dopo la navigazione
          Future.delayed(Duration(milliseconds: 300), () {
            if (mounted) {
              _showWelcomeDialog(userName, isNewUser: true);
            }
          });
        }
      } else {
        _showErrorDialog(
            result.message ?? 'Errore durante la registrazione con Google');
      }
    } catch (e) {
      _showErrorDialog(
          'Errore durante la registrazione con Google. Verifica la connessione.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signUpWithApple() async {
    setState(() => _isLoading = true);

    try {
      final result = await AuthService().loginWithApple();

      if (result.success && result.user != null) {
        final userName = result.user!.name.split(' ').first;

        if (mounted) {
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
                    )),
            (route) => false,
          );

          Future.delayed(Duration(milliseconds: 300), () {
            if (mounted) {
              _showWelcomeDialog(userName, isNewUser: true);
            }
          });
        }
      } else {
        _showErrorDialog(
            result.message ?? 'Errore durante la registrazione con Apple');
      }
    } catch (e) {
      _showErrorDialog(
          'Errore durante la registrazione con Apple. Verifica la connessione.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // REGISTRAZIONE EMAIL FORZATA - NAVIGAZIONE DOPO SINCRONIZZAZIONE COMPLETA
  Future<void> _signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedPrivacy || !_acceptedTerms) {
      _showErrorDialog(
          'Devi accettare Privacy Policy e Termini e Condizioni per continuare');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService().registerUser(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        acceptedTerms: _acceptedTerms,
        acceptedPrivacy: _acceptedPrivacy,
        acceptedMarketing: !_optOutMarketing,
        birthDate: _birthDate,
        gender: _gender,
      );

      if (result.success && result.user != null) {
        final userName = result.user!.name.split(' ').first;

        // NAVIGAZIONE FORZATA IMMEDIATA - LA SINCRONIZZAZIONE È GIÀ COMPLETA
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (context) => WebHomePage(
                      isDarkTheme: widget.isDarkTheme,
                      marketingProfileEnabled: !_optOutMarketing,
                      marketingCommsEnabled: !_optOutMarketing,
                      onThemeChanged: widget.onThemeChanged,
                      onMarketingProfileChanged: (value) {},
                      onMarketingCommsChanged: (value) {},
                      onSharedContent: (content) {},
                    )),
            (route) => false,
          );

          // Mostra popup di benvenuto dopo la navigazione
          Future.delayed(Duration(milliseconds: 300), () {
            if (mounted) {
              _showWelcomeDialog(userName, isNewUser: true);
            }
          });
        }
      } else {
        _showErrorDialog(result.message ?? 'Errore durante la registrazione');
      }
    } catch (e) {
      _showErrorDialog(
          'Errore durante la registrazione. Verifica la connessione.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // POPUP DI BENVENUTO PER NUOVI UTENTI
  void _showWelcomeDialog(String userName, {bool isNewUser = false}) {
    final welcomeFuture = SaveInFirstLaunchTutorial.show(
      context,
      markSeenOnClose: true,
      welcomeUserName: isNewUser ? userName : null,
    );
    SaveInFirstLaunchTutorial.trackExternalWelcome(welcomeFuture);
  }

  // 🔥 CORRETTO: Solo SnackBar, no navigazione
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
