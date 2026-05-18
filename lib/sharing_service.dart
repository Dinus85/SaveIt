import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/material.dart';
import 'models/folder.dart'; // Usa il modello esistente
import 'services/folder_service.dart'; // Usa il servizio esistente

class SharingService {
  static SharingService? _instance;
  static SharingService get instance {
    _instance ??= SharingService._();
    return _instance!;
  }

  SharingService._();

  StreamSubscription? _intentDataStreamSubscription;
  Function(SharedContent)? _onSharedContent;

  // Initialize sharing intent listener
  void initialize({Function(SharedContent)? onSharedContent}) {
    _onSharedContent = onSharedContent;
    
    // Listen for shared content when app is running
    _intentDataStreamSubscription = ReceiveSharingIntent.textStream.listen(
      (String value) {
        _handleSharedText(value);
      },
      onError: (err) {
        print("Errore durante la ricezione del contenuto condiviso: $err");
      },
    );

    // Check for shared content when app was closed and opened by sharing
    ReceiveSharingIntent.initialText.then((String? value) {
      if (value != null) {
        _handleSharedText(value);
      }
    });
  }

  void _handleSharedText(String text) {
    final urls = _extractUrlsFromText(text);
    
    if (urls.isNotEmpty) {
      // Take the first URL found
      final url = urls.first;
      final sharedContent = SharedContent(
        url: url,
        text: text,
        platform: _getSocialPlatform(url),
      );
      
      _onSharedContent?.call(sharedContent);
    }
  }

  List<String> _extractUrlsFromText(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"]+|www\.[^\s<>"]+',
      caseSensitive: false,
    );
    
    return urlRegex.allMatches(text).map((match) => match.group(0)!).toList();
  }

  // Metodo locale per determinare la piattaforma social
  String? _getSocialPlatform(String url) {
    final domain = _getDomainFromUrl(url).toLowerCase();
    
    if (domain.contains('instagram')) return 'Instagram';
    if (domain.contains('tiktok')) return 'TikTok';
    if (domain.contains('youtube')) return 'YouTube';
    if (domain.contains('twitter') || domain.contains('x.com')) return 'Twitter/X';
    if (domain.contains('facebook')) return 'Facebook';
    if (domain.contains('linkedin')) return 'LinkedIn';
    if (domain.contains('pinterest')) return 'Pinterest';
    if (domain.contains('reddit')) return 'Reddit';
    
    return null;
  }

  // Metodo locale per estrarre il dominio
  String _getDomainFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
    }
  }

  // Show dialog to save shared content
  static Future<void> showSaveDialog(
    BuildContext context, 
    SharedContent sharedContent,
  ) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => SaveSharedContentDialog(
        sharedContent: sharedContent,
      ),
    );
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}

class SharedContent {
  final String url;
  final String text;
  final String? platform;

  SharedContent({
    required this.url,
    required this.text,
    this.platform,
  });
}

class SaveSharedContentDialog extends StatefulWidget {
  final SharedContent sharedContent;

  const SaveSharedContentDialog({
    Key? key,
    required this.sharedContent,
  }) : super(key: key);

  @override
  _SaveSharedContentDialogState createState() => _SaveSharedContentDialogState();
}

class _SaveSharedContentDialogState extends State<SaveSharedContentDialog> {
  late TextEditingController _titleController;
  late TextEditingController _tagsController;
  MockFolder? _selectedFolder;
  List<MockFolder> _folders = [];
  bool _isLoading = false;
  final FolderService _folderService = FolderService();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: _generateTitle(),
    );
    _tagsController = TextEditingController();
    _loadFolders();
  }

  String _generateTitle() {
    final domain = _getDomainFromUrl(widget.sharedContent.url);
    final platform = widget.sharedContent.platform;
    
    if (platform != null) {
      return 'Contenuto da $platform';
    }
    return 'Contenuto da $domain';
  }

  void _loadFolders() {
    setState(() {
      // Prende tutte le cartelle non speciali (esclude "Tutti")
      _folders = _folderService.folders.where((f) => !f.isSpecial).toList();
      _selectedFolder = _folders.isNotEmpty ? _folders.first : null;
    });
  }

  String _getDomainFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return 'sconosciuto';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Row(
        children: [
          Icon(Icons.bookmark_add, color: Colors.white),
          SizedBox(width: 8),
          Text('Salva contenuto condiviso', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview card
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contenuto da salvare',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.link, color: Colors.grey[500], size: 12),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _getDomainFromUrl(widget.sharedContent.url),
                          style: TextStyle(color: Colors.grey[400], fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.sharedContent.platform != null) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.sharedContent.platform!,
                            style: TextStyle(color: Colors.blue, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.sharedContent.url,
                      style: TextStyle(color: Colors.blue, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 16),
            
            // Title field
            Text('Titolo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            TextField(
              controller: _titleController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Dai un titolo al contenuto...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 2,
            ),
            
            SizedBox(height: 12),
            
            // Folder selection
            Text('Cartella', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            if (_folders.isEmpty)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Nessuna cartella disponibile. Crea prima una cartella nell\'app.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButton<MockFolder>(
                  value: _selectedFolder,
                  isExpanded: true,
                  dropdownColor: Colors.grey[800],
                  style: TextStyle(color: Colors.white),
                  underline: Container(),
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  items: _folders.map((folder) {
                    return DropdownMenuItem<MockFolder>(
                      value: folder,
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: folder.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(folder.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (MockFolder? value) {
                    setState(() {
                      _selectedFolder = value;
                    });
                  },
                ),
              ),
            
            SizedBox(height: 12),
            
            // Tags field
            Text('Tags', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            TextField(
              controller: _tagsController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'es: ricetta, dolce, facile (senza #)',
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            
            SizedBox(height: 8),
            Text(
              'Suggerimento: aggiungi tags senza il simbolo #',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Annulla', style: TextStyle(color: Colors.grey[400])),
        ),
        ElevatedButton(
          onPressed: (_isLoading || _folders.isEmpty) ? null : _saveContent,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('Salva'),
        ),
      ],
    );
  }

  Future<void> _saveContent() async {
    if (_titleController.text.trim().isEmpty || _selectedFolder == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Parse tags
      final tagsText = _tagsController.text.trim();
      final tags = tagsText.isEmpty
          ? <String>[]
          : tagsText.split(',').map((tag) => tag.trim().replaceAll('#', '')).where((tag) => tag.isNotEmpty).toList();

      // Create post usando il costruttore corretto di MockPost
      final post = MockPost(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        url: widget.sharedContent.url,
        description: 'Contenuto condiviso da ${widget.sharedContent.platform ?? _getDomainFromUrl(widget.sharedContent.url)}',
        tags: tags,
        views: 0,
      );

      // Aggiungi il post alla cartella selezionata
      _selectedFolder!.posts.add(post);
      
      // Aggiorna anche la cartella "Tutti" se esiste
      final tuttiFolder = _folderService.folders.firstWhere(
        (f) => f.isSpecial && f.name == 'Tutti',
        orElse: () => _selectedFolder!,
      );
      if (tuttiFolder != _selectedFolder) {
        tuttiFolder.posts.add(post);
      }

      Navigator.of(context).pop();
      

    } catch (e) {
      print('Errore durante il salvataggio: $e');

    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    super.dispose();
  }
}