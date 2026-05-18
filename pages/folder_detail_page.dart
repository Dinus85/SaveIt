import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/folder.dart';
import '../widgets/folder_card.dart';
import '../services/folder_service.dart';
import '../utils/theme_helpers.dart';
import '../utils/dialog_helpers.dart';

// Pagina dettaglio cartella
class FolderDetailPage extends StatefulWidget {
  final MockFolder folder;
  final bool isDarkTheme;
  final List<MockFolder> allFolders;
  final VoidCallback onFolderUpdated;

  const FolderDetailPage({
    Key? key,
    required this.folder,
    required this.isDarkTheme,
    required this.allFolders,
    required this.onFolderUpdated,
  }) : super(key: key);

  @override
  _FolderDetailPageState createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  final FolderService _folderService = FolderService();
  List<MockPost> _posts = [];
  
  @override
  void initState() {
    super.initState();
    _folderService.initializeFolders();
    _loadPosts();
  }

  void _loadPosts() {
    setState(() {
      _posts = _folderService.getPostsForFolder(widget.folder);
    });
  }

  // Costruisce il breadcrumb del percorso della cartella
  String _buildBreadcrumb(MockFolder folder) {
    List<String> path = [];
    MockFolder? current = folder.parent;
    
    // Risali la gerarchia fino alla radice
    while (current != null) {
      if (!current.isSpecial) { // Non includere "Tutti" nel breadcrumb
        path.insert(0, current.name);
      }
      current = current.parent;
    }
    
    if (path.isEmpty) {
      return 'Cartella principale';
    }
    
    return path.join(' › ');
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    
    return Scaffold(
      backgroundColor: themeColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: themeColors.backgroundColor,
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.folder.name,
              style: ThemeHelpers.getAppTitleStyle(widget.isDarkTheme),
            ),
            if (widget.folder.level > 0) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: themeColors.subtitleColor,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _buildBreadcrumb(widget.folder),
                      style: TextStyle(
                        color: themeColors.subtitleColor, 
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: themeColors.textColor, size: 28),
          onPressed: () {
            widget.onFolderUpdated();
            Navigator.pop(context);
          },
        ),
        toolbarHeight: 80,
      ),
      body: _buildContent(themeColors),
      
      // Stessa barra sottostante della home
      bottomNavigationBar: Container(
        color: themeColors.backgroundColor,
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () {
                // Torna alla home
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              icon: Icon(Icons.home, color: themeColors.textColor, size: 28),
            ),
            FloatingActionButton(
              onPressed: () => _showCreateFolderDialog(themeColors),
              backgroundColor: Colors.white,
              child: Icon(Icons.add, color: Colors.black, size: 28),
              mini: false,
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.person, color: themeColors.textColor, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeColors themeColors) {
    final hasSubfolders = widget.folder.children.isNotEmpty;
    final hasPosts = _posts.isNotEmpty;
    
    if (!hasSubfolders && !hasPosts) {
      return _buildEmptyState(themeColors);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Post salvati
          if (hasPosts) ...[
            _buildPostsSection(themeColors),
            if (hasSubfolders) SizedBox(height: 32),
          ],
          
          // Sottocartelle
          if (hasSubfolders) ...[
            _buildSubfoldersSection(themeColors),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeColors themeColors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.folder.isSpecial ? Icons.folder_special : Icons.folder_open,
            color: themeColors.subtitleColor,
            size: 64,
          ),
          SizedBox(height: 16),
          Text(
            widget.folder.isSpecial 
                ? 'Nessun post salvato'
                : 'Cartella vuota',
            style: TextStyle(color: themeColors.subtitleColor, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text(
            widget.folder.isSpecial
                ? 'I post che salvi appariranno qui'
                : widget.folder.canHaveSubfolders
                    ? 'Usa il pulsante + per creare sottocartelle'
                    : 'Livello massimo raggiunto (4)',
            style: TextStyle(color: themeColors.subtitleColor, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPostsSection(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bookmark, color: themeColors.textColor, size: 20),
            SizedBox(width: 8),
            Text(
              widget.folder.isSpecial ? 'Tutti i Post Salvati' : 'Post in questa cartella',
              style: ThemeHelpers.getSectionTitleStyle(widget.isDarkTheme),
            ),
            Spacer(),
            Text(
              '${_posts.length} ${_posts.length == 1 ? 'post' : 'post'}',
              style: TextStyle(
                color: themeColors.subtitleColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        
        // Lista dei post
        ...(_posts.map((post) => _buildPostCard(post, themeColors)).toList()),
      ],
    );
  }

  Widget _buildPostCard(MockPost post, ThemeColors themeColors) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: ThemeHelpers.getCardDecoration(widget.isDarkTheme),
      child: InkWell(
        onTap: () => _openPost(post),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titolo e fonte
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      post.title,
                      style: TextStyle(
                        color: themeColors.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.launch,
                    color: Colors.blue,
                    size: 18,
                  ),
                ],
              ),
              
              SizedBox(height: 8),
              
              // Descrizione
              Text(
                post.description,
                style: TextStyle(
                  color: themeColors.subtitleColor,
                  fontSize: 14,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              SizedBox(height: 12),
              
              // Footer con info aggiuntive
              Row(
                children: [
                  // Data di salvataggio
                  Icon(Icons.schedule, color: themeColors.hintColor, size: 14),
                  SizedBox(width: 4),
                  Text(
                    _formatDate(post.savedDate),
                    style: TextStyle(
                      color: themeColors.hintColor,
                      fontSize: 12,
                    ),
                  ),
                  
                  // Cartella sorgente (solo se non siamo nella cartella "Tutti")
                  if (!widget.folder.isSpecial && post.sourceFolder != null) ...[
                    SizedBox(width: 16),
                    Icon(Icons.folder_outlined, color: themeColors.hintColor, size: 14),
                    SizedBox(width: 4),
                    Text(
                      post.sourceFolder!.name,
                      style: TextStyle(
                        color: themeColors.hintColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  
                  // Tags
                  if (post.tags.isNotEmpty) ...[
                    SizedBox(width: 16),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        children: post.tags.take(2).map((tag) => 
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubfoldersSection(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder, color: themeColors.textColor, size: 20),
            SizedBox(width: 8),
            Text(
              'Sottocartelle',
              style: ThemeHelpers.getSectionTitleStyle(widget.isDarkTheme),
            ),
            Spacer(),
            Text(
              '${widget.folder.children.length} ${widget.folder.children.length == 1 ? 'cartella' : 'cartelle'}',
              style: TextStyle(
                color: themeColors.subtitleColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        
        // Griglia delle sottocartelle
        GridView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: widget.folder.children.length,
          itemBuilder: (context, index) {
            return MockFolderCard(
              folder: widget.folder.children[index],
              onTap: () => _openSubfolder(widget.folder.children[index]),
              onRename: _showRenameSubfolderDialog,
              onDelete: _showDeleteSubfolderDialog,
              onMove: _showMoveSubfolderDialog,
              allFolders: widget.allFolders,
            );
          },
        ),
      ],
    );
  }

  void _openPost(MockPost post) async {
    try {
      final Uri url = Uri.parse(post.url);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impossibile aprire il link'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nell\'apertura del link'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Oggi';
    } else if (difference.inDays == 1) {
      return 'Ieri';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} giorni fa';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'settimana' : 'settimane'} fa';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _openSubfolder(MockFolder subfolder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FolderDetailPage(
          folder: subfolder,
          isDarkTheme: widget.isDarkTheme,
          allFolders: widget.allFolders,
          onFolderUpdated: () {
            setState(() {
              _loadPosts();
            });
            widget.onFolderUpdated();
          },
        ),
      ),
    );
  }

  void _showCreateFolderDialog(ThemeColors themeColors) {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Nuova sottocartella',
          style: TextStyle(color: themeColors.textColor, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Livello ${widget.folder.level + 1} di 4',
              style: TextStyle(color: themeColors.hintColor, fontSize: 12),
            ),
            SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(color: themeColors.textColor),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Nome sottocartella',
                hintStyle: TextStyle(color: themeColors.hintColor),
                filled: true,
                fillColor: themeColors.fieldColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              autofocus: true,
            ),
            if (!widget.folder.canHaveSubfolders) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.folder.isSpecial 
                            ? 'Non puoi creare sottocartelle in "Tutti"'
                            : 'Livello massimo raggiunto (4)',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: themeColors.hintColor)),
          ),
          TextButton(
            onPressed: widget.folder.canHaveSubfolders ? () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _folderService.createSubfolder(widget.folder, controller.text.trim());
                  _loadPosts(); // Ricarica per aggiornare i conteggi
                });
                // Aggiorna la home page
                widget.onFolderUpdated();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sottocartella "${_capitalizeFirst(controller.text)}" creata!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } : null,
            child: Text(
              'Crea', 
              style: TextStyle(
                color: widget.folder.canHaveSubfolders ? Colors.blue : Colors.grey[600], 
                fontWeight: FontWeight.bold
              )
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameSubfolderDialog(MockFolder subfolder) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    final TextEditingController controller = TextEditingController(text: subfolder.name);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Rinomina sottocartella',
          style: TextStyle(color: themeColors.textColor, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: themeColors.textColor),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Nome sottocartella',
            hintStyle: TextStyle(color: themeColors.hintColor),
            filled: true,
            fillColor: themeColors.fieldColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: themeColors.hintColor)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _folderService.renameFolder(subfolder, controller.text.trim());
                  _loadPosts();
                });
                widget.onFolderUpdated();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sottocartella rinominata in "${_capitalizeFirst(controller.text)}"'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text('Salva', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteSubfolderDialog(MockFolder subfolder) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Elimina sottocartella',
          style: TextStyle(color: themeColors.textColor, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Sei sicuro di voler eliminare la sottocartella "${subfolder.name}"?\n\nTutte le sue sottocartelle e contenuti verranno eliminati.',
          style: TextStyle(color: themeColors.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: themeColors.hintColor)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                widget.folder.children.remove(subfolder);
                _loadPosts();
              });
              widget.onFolderUpdated();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sottocartella "${subfolder.name}" eliminata'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            child: Text('Elimina', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showMoveSubfolderDialog(MockFolder folderToMove) {
    // Usa il nuovo sistema di spostamento con selezione
    DialogHelpers.showMoveFolderDialog(
      context,
      widget.isDarkTheme,
      folderToMove,
      widget.allFolders,
      (destination) {
        setState(() {
          _folderService.moveFolder(folderToMove, destination);
          _loadPosts();
        });
        widget.onFolderUpdated();
        
        // Messaggio con percorso completo
        final destinationPath = _buildDestinationPath(destination);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cartella "${folderToMove.name}" spostata in $destinationPath'),
            backgroundColor: Colors.green,
          ),
        );
      },
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  // Costruisce il percorso completo di destinazione
  String _buildDestinationPath(MockFolder? destination) {
    if (destination == null) {
      return 'Home';
    }
    
    List<String> path = [];
    MockFolder? current = destination;
    
    // Costruisci il percorso dalla destinazione alla radice
    while (current != null) {
      if (!current.isSpecial) { // Non includere "Tutti" nel percorso
        path.insert(0, current.name);
      }
      current = current.parent;
    }
    
    if (path.isEmpty) {
      return 'Home';
    }
    
    return 'Home > ${path.join(' > ')}';
  }
}