import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../services/auth_service.dart';
import '../utils/theme_helpers.dart';
import 'help_center_page.dart';

class ContactPage extends StatefulWidget {
  final bool isDarkTheme;

  const ContactPage({Key? key, required this.isDarkTheme}) : super(key: key);

  @override
  _ContactPageState createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _userEmail = 'Email non disponibile';
  bool _isLoading = false;
  int _characterCount = 0;
  final int _maxCharacters = 250;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_updateCharacterCount);
    _loadUserEmail();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _updateCharacterCount() {
    setState(() {
      _characterCount = _messageController.text.length;
    });
  }

  Future<void> _loadUserEmail() async {
    try {
      String? email;

      final authUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        email = authUser.email;
      }

      if (email == null || email.isEmpty) {
        final localUser = AuthService().currentUser;
        email = localUser?.email;
      }

      if (email != null && email.isNotEmpty) {
        setState(() {
          _userEmail = email!;
        });
      }
    } catch (e) {
      debugPrint('DEBUG: errore durante il caricamento email utente: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    
    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      appBar: AppBar(
        backgroundColor: themeColors.mainBackgroundColor,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          'Contattaci',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: themeColors.iconColor, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        toolbarHeight: 80,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
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
                  Row(
                    children: [
                      Icon(Icons.contact_support, color: Colors.blue, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Invia una Segnalazione',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Hai riscontrato un problema o hai suggerimenti? Scrivici e ti risponderemo il prima possibile.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
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
                  Text(
                    'La tua email:',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _userEmail,
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  Text(
                    'Oggetto:',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  TextField(
                    controller: _subjectController,
                    style: TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Descrivi brevemente il problema...',
                      hintStyle: TextStyle(color: Colors.black54),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  Text(
                    'Messaggio:',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  TextField(
                    controller: _messageController,
                    style: TextStyle(color: Colors.black87),
                    maxLines: 6,
                    maxLength: _maxCharacters,
                    decoration: InputDecoration(
                      hintText: 'Descrivi il problema in dettaglio o condividi i tuoi suggerimenti...',
                      hintStyle: TextStyle(color: Colors.black54),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      counterText: '$_characterCount/$_maxCharacters caratteri',
                      counterStyle: TextStyle(
                        color: _characterCount > _maxCharacters * 0.9 
                          ? Colors.orange 
                          : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.blue.withOpacity(0.6),
                        disabledForegroundColor: Colors.black,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.black, width: 1),
                        ),
                      ),
                      child: _isLoading
                          ? CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                          : Text(
                              'Invia Messaggio',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(Icons.help_outline, color: Colors.green, size: 32),
                  SizedBox(height: 8),
                  Text(
                    'Prima di scriverci, hai controllato le FAQ?',
                    style: TextStyle(
                      color: themeColors.titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Potresti trovare subito la risposta che cerchi',
                    style: TextStyle(color: themeColors.subtitleColor, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => HelpCenterPage(isDarkTheme: widget.isDarkTheme),
                        ),
                      );
                    },
                    icon: Icon(Icons.help_center, size: 18, color: Colors.green),
                    label: Text('Vai alle FAQ', style: TextStyle(color: Colors.green)),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 32),
          ],
        ),
      ),
      
      bottomNavigationBar: SafeArea(
        child: Container(
          color: themeColors.bottomBarColor,
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                icon: Icon(Icons.home, color: themeColors.iconColor, size: 28),
              ),
              FloatingActionButton(
                onPressed: () => _showCreateFolderDialog(),
                backgroundColor: Colors.white,
                child: Icon(Icons.add, color: Colors.black, size: 28),
                mini: false,
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.person, color: themeColors.iconColor, size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendMessage() async {
    if (_subjectController.text.trim().isEmpty || _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Per favore compila tutti i campi'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('DEBUG: Inviando email tramite Cloud Function...');

      final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'Devi effettuare l\'accesso per inviare un messaggio.',
          details: null,
        );
      }

      try {
        await currentUser.getIdToken(true);
      } catch (tokenError) {
        debugPrint('DEBUG: errore durante il refresh del token: $tokenError');
      }
      
      // Chiama la Cloud Function
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable(
        'sendContactEmail',
        options: HttpsCallableOptions(timeout: Duration(seconds: 30)),
      );
      
      final result = await callable.call(<String, dynamic>{
        'subject': _subjectController.text.trim(),
        'message': _messageController.text.trim(),
      });
      
      print('DEBUG: Risposta Cloud Function: ${result.data}');
      
      setState(() {
        _isLoading = false;
      });
      
      // Mostra messaggio di successo
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Messaggio inviato con successo!'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        
        // Pulisci i campi
        _subjectController.clear();
        _messageController.clear();
      }
    } catch (e) {
      print('ERRORE: Invio email fallito: $e');
      
      setState(() {
        _isLoading = false;
      });
      
      String errorMessage = 'Errore durante l\'invio del messaggio';
      
      // Estrai messaggio di errore specifico se disponibile
      if (e is FirebaseFunctionsException) {
        errorMessage = e.message ?? errorMessage;
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Errore invio messaggio',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  errorMessage,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showCreateFolderDialog() {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Nuova Cartella',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Torna alla home per creare una nuova cartella',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(color: Colors.black87),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Nome cartella',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                Navigator.popUntil(context, (route) => route.isFirst);
                
                
              }
            },
            child: Text('Vai alla Home'),
          ),
        ],
      ),
    );
  }
}