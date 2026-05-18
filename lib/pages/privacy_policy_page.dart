// lib/pages/privacy_policy_page.dart
// VERSIONE CORRETTA - Hero tag fisso + SafeArea

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme_helpers.dart';
import '../services/remote_content_service.dart';

class PrivacyPolicyPage extends StatefulWidget {
  final bool isDarkTheme;

  const PrivacyPolicyPage({Key? key, required this.isDarkTheme}) : super(key: key);

  @override
  _PrivacyPolicyPageState createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  final RemoteContentService _contentService = RemoteContentService();
  
  RemoteContent? _content;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final content = await _contentService.loadContent('privacy_policy', forceRefresh: forceRefresh);
      setState(() {
        _content = content;
        _isLoading = false;
      });
      
      if (forceRefresh) {

      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore nel caricamento del contenuto: $e';
        _isLoading = false;
      });
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
          _content?.title ?? 'Privacy Policy',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: themeColors.iconColor, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _buildStatusIndicator(),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: themeColors.iconColor),
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _loadContent();
                  break;
                case 'force_refresh':
                  _loadContent(forceRefresh: true);
                  break;
                case 'copy':
                  _copyToClipboard();
                  break;
                case 'info':
                  _showContentInfo();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: themeColors.textColor),
                    SizedBox(width: 8),
                    Text('Aggiorna', style: TextStyle(color: themeColors.textColor)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'force_refresh',
                child: Row(
                  children: [
                    Icon(Icons.cloud_download, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Forza Aggiornamento', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy, color: themeColors.textColor),
                    SizedBox(width: 8),
                    Text('Copia Testo', style: TextStyle(color: themeColors.textColor)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info, color: themeColors.textColor),
                    SizedBox(width: 8),
                    Text('Info Contenuto', style: TextStyle(color: themeColors.textColor)),
                  ],
                ),
              ),
            ],
          ),
        ],
        toolbarHeight: 80,
      ),
      body: _buildBody(themeColors),
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
                heroTag: "fab_privacy_policy",
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

  Widget _buildStatusIndicator() {
    if (_content == null) return SizedBox.shrink();
    
    final isRemote = !_content!.version.contains('fallback');
    
    return Container(
      margin: EdgeInsets.only(right: 8),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isRemote ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRemote ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRemote ? Icons.cloud_done : Icons.cloud_off,
            color: isRemote ? Colors.green : Colors.orange,
            size: 12,
          ),
          SizedBox(width: 4),
          Text(
            isRemote ? 'REMOTO' : 'LOCALE',
            style: TextStyle(
              color: isRemote ? Colors.green : Colors.orange,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeColors themeColors) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Caricamento privacy policy...',
              style: TextStyle(color: themeColors.textColor),
            ),
            SizedBox(height: 8),
            Text(
              'Tentativo caricamento remoto in corso',
              style: TextStyle(color: themeColors.hintColor, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 64),
            SizedBox(height: 16),
            Text(
              'Errore di caricamento',
              style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: themeColors.textColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadContent,
              child: Text('Riprova'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12),
          margin: EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Privacy Policy Aggiornata',
                      style: TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                'Versione: ${_content?.version ?? 'N/A'} • Aggiornato: ${_formatDate(_content?.lastUpdated)}',
                style: TextStyle(color: Colors.green, fontSize: 11),
              ),
            ],
          ),
        ),

        Expanded(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 16),
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
            child: SingleChildScrollView(
              child: Text(
                _content?.content ?? 'Contenuto non disponibile',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  void _copyToClipboard() {
    if (_content != null) {
      Clipboard.setData(ClipboardData(text: _content!.content));

    }
  }

  void _showContentInfo() {
    if (_content == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Info Contenuto',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Titolo:', _content!.title),
            _buildInfoRow('Versione:', _content!.version),
            _buildInfoRow('Ultimo Aggiornamento:', _formatDate(_content!.lastUpdated)),
            _buildInfoRow('Caratteri:', _content!.content.length.toString()),
            _buildInfoRow('Fonte:', _content!.version.contains('fallback') ? 'Locale (Fallback)' : 'Remoto (GitHub)'),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog() {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Nuova Cartella',
          style: TextStyle(
            color: widget.isDarkTheme ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Torna alla home per creare una nuova cartella',
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.grey.shade300 : Colors.black54,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'Nome cartella',
                hintStyle: TextStyle(
                  color: widget.isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                filled: true,
                fillColor: widget.isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
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
              Navigator.pop(context);
              Navigator.popUntil(context, (route) => route.isFirst);

            },
            child: Text('Vai alla Home'),
          ),
        ],
      ),
    );
  }
}