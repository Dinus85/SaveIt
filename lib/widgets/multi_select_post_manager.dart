// lib/widgets/multi_select_post_manager.dart
// Widget per gestire la selezione multipla dei post con azioni batch

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:savein/models/folder.dart';
import 'package:savein/services/folder_service.dart';
import 'package:savein/services/sharing_service.dart';
import 'package:savein/data_service.dart';
import 'package:savein/utils/theme_helpers.dart';
import 'package:savein/utils/dialog_helpers.dart';

/// Gestore dello stato per la selezione multipla dei post
class MultiSelectPostState extends ChangeNotifier {
  final Set<String> _selectedPostIds = <String>{};
  bool _isSelectionMode = false;

  /// Post attualmente selezionati
  Set<String> get selectedPostIds => Set.unmodifiable(_selectedPostIds);
  
  /// Numero di post selezionati
  int get selectedCount => _selectedPostIds.length;
  
  /// Se siamo in modalità selezione
  bool get isSelectionMode => _isSelectionMode;
  
  /// Verifica se un post è selezionato
  bool isSelected(String postId) => _selectedPostIds.contains(postId);

  /// Attiva la modalità selezione con il primo post
  void startSelection(String postId) {
    _isSelectionMode = true;
    _selectedPostIds.clear();
    _selectedPostIds.add(postId);
    notifyListeners();
    
    // Feedback tattile per indicare l'inizio della selezione
    HapticFeedback.mediumImpact();
  }

  /// Aggiunge o rimuove un post dalla selezione
  void toggleSelection(String postId) {
    if (_selectedPostIds.contains(postId)) {
      _selectedPostIds.remove(postId);
      HapticFeedback.lightImpact();
    } else {
      _selectedPostIds.add(postId);
      HapticFeedback.lightImpact();
    }
    
    // Se non ci sono più post selezionati, esci dalla modalità selezione
    if (_selectedPostIds.isEmpty) {
      exitSelectionMode();
    } else {
      notifyListeners();
    }
  }

  /// Seleziona tutti i post forniti
  void selectAll(List<String> postIds) {
    _selectedPostIds.clear();
    _selectedPostIds.addAll(postIds);
    _isSelectionMode = true;
    notifyListeners();
    HapticFeedback.mediumImpact();
  }

  /// Deseleziona tutti i post
  void deselectAll() {
    _selectedPostIds.clear();
    notifyListeners();
    HapticFeedback.lightImpact();
  }

  /// Esce dalla modalità selezione
  void exitSelectionMode() {
    _isSelectionMode = false;
    _selectedPostIds.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _selectedPostIds.clear();
    super.dispose();
  }
}

/// Widget per gestire la selezione multipla dei post
class MultiSelectPostManager extends StatefulWidget {
  final List<MockPost> posts;
  final bool isDarkTheme;
  final FolderService folderService;
  final VoidCallback onPostsUpdated;
  final Widget Function(MockPost post, bool isSelected, VoidCallback onTap, VoidCallback onLongPress) childBuilder;
  /// Se `true` la lista gestisce il proprio scroll (ListView in Expanded).
  /// Se `false` la lista diventa non-scrollabile (shrinkWrap) per evitare
  /// conflitti con scroll/RefreshIndicator del parent.
  final bool scrollable;
  final bool asSliver;

  const MultiSelectPostManager({
    Key? key,
    required this.posts,
    required this.isDarkTheme,
    required this.folderService,
    required this.onPostsUpdated,
    required this.childBuilder,
    this.scrollable = true,
    this.asSliver = false,
  }) : super(key: key);

  @override
  _MultiSelectPostManagerState createState() => _MultiSelectPostManagerState();
}

class _MultiSelectPostManagerState extends State<MultiSelectPostManager> {
  final MultiSelectPostState _selectionState = MultiSelectPostState();

  @override
  void initState() {
    super.initState();
    _selectionState.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _selectionState.removeListener(_onSelectionChanged);
    _selectionState.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asSliver) {
      return SliverMainAxisGroup(
        slivers: [
          if (_selectionState.isSelectionMode)
            SliverToBoxAdapter(child: _buildSelectionActionBar()),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final post = widget.posts[index];
                final isSelected = _selectionState.isSelected(post.id);

                return widget.childBuilder(
                  post,
                  isSelected,
                  () => _handlePostTap(post),
                  () => _handlePostLongPress(post),
                );
              },
              childCount: widget.posts.length,
            ),
          ),
        ],
      );
    }

    final list = ListView.builder(
      itemCount: widget.posts.length,
      shrinkWrap: !widget.scrollable,
      physics: widget.scrollable ? null : const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final post = widget.posts[index];
        final isSelected = _selectionState.isSelected(post.id);

        return widget.childBuilder(
          post,
          isSelected,
          () => _handlePostTap(post),
          () => _handlePostLongPress(post),
        );
      },
    );

    return Column(
      children: [
        // Barra delle azioni quando in modalità selezione
        if (_selectionState.isSelectionMode)
          _buildSelectionActionBar(),
        
        // Lista dei post
        if (widget.scrollable) Expanded(child: list) else list,
      ],
    );
  }

  /// Gestisce il tap su un post
  void _handlePostTap(MockPost post) {
    if (_selectionState.isSelectionMode) {
      // In modalità selezione, aggiungi/rimuovi dalla selezione
      _selectionState.toggleSelection(post.id);
    } else {
      // Comportamento normale: apri il post
      _openPost(post);
    }
  }

  /// Gestisce il long press su un post
  void _handlePostLongPress(MockPost post) {
    if (!_selectionState.isSelectionMode) {
      // Inizia la modalità selezione
      _selectionState.startSelection(post.id);
    } else {
      // Già in modalità selezione, aggiungi/rimuovi
      _selectionState.toggleSelection(post.id);
    }
  }

  /// Apre un post normalmente
  void _openPost(MockPost post) async {
    try {
      print('DEBUG: MultiSelectPostManager - Apertura reale del post: ${post.title}');
      print('DEBUG: MultiSelectPostManager - URL: ${post.url}');
      
      // Traccia la visualizzazione
      widget.folderService.trackPostViewed(post);
      
      // Apri il link reale usando SharingService
      await SharingService.openPostDirectly(context, post.url);
      
      print('DEBUG: MultiSelectPostManager - Post aperto con successo');
      
    } catch (e) {
      print('ERRORE: MultiSelectPostManager - Apertura fallita: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore apertura link: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Costruisce la barra delle azioni per la selezione multipla
  Widget _buildSelectionActionBar() {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isDarkTheme ? Colors.grey[850] : Colors.blue[50],
        border: Border(
          bottom: BorderSide(
            color: widget.isDarkTheme ? Colors.grey[700]! : Colors.blue[200]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Icona di chiusura
          IconButton(
            onPressed: _selectionState.exitSelectionMode,
            icon: Icon(Icons.close, color: themeColors.iconColor),
            constraints: BoxConstraints(maxWidth: 40, maxHeight: 40),
            padding: EdgeInsets.zero,
          ),
          
          SizedBox(width: 8),
          
          // Contatore post selezionati
          Expanded(
            child: Text(
              '${_selectionState.selectedCount} ${_selectionState.selectedCount == 1 ? 'post selezionato' : 'post selezionati'}',
              style: TextStyle(
                color: themeColors.textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          // Seleziona tutti / Deseleziona tutti
          TextButton(
            onPressed: () {
              if (_selectionState.selectedCount == widget.posts.length) {
                _selectionState.deselectAll();
              } else {
                _selectionState.selectAll(widget.posts.map((p) => p.id).toList());
              }
            },
            child: Text(
              _selectionState.selectedCount == widget.posts.length 
                ? 'Deseleziona tutti' 
                : 'Seleziona tutti',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          SizedBox(width: 8),
          
          // Menu azioni
          PopupMenuButton<String>(
            onSelected: _handleBatchAction,
            icon: Icon(Icons.more_vert, color: themeColors.iconColor),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'move',
                child: Row(
                  children: [
                    Icon(Icons.drive_file_move_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 12),
                    Text('Sposta post'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    SizedBox(width: 12),
                    Text('Elimina post', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Gestisce le azioni batch sui post selezionati
  void _handleBatchAction(String action) {
    final selectedPosts = widget.posts
        .where((post) => _selectionState.isSelected(post.id))
        .toList();

    if (selectedPosts.isEmpty) return;

    switch (action) {
      case 'move':
        _showBatchMoveDialog(selectedPosts);
        break;
      case 'delete':
        _showBatchDeleteDialog(selectedPosts);
        break;
    }
  }

  /// Mostra il dialog per spostare i post selezionati
  void _showBatchMoveDialog(List<MockPost> posts) {
    DialogHelpers.showMovePostDialog(
      context,
      widget.isDarkTheme,
      posts.first, // Usa il primo post come riferimento per il dialog
      widget.folderService.folders,
      (destination) async {
        await _movePostsBatch(posts, destination);
      },
      isMultipleSelection: true,
      selectedCount: posts.length,
    );
  }

  /// Mostra il dialog per eliminare i post selezionati
  void _showBatchDeleteDialog(List<MockPost> posts) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text(
              'Elimina Post',
              style: TextStyle(
                color: themeColors.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sei sicuro di voler eliminare ${posts.length} ${posts.length == 1 ? 'post' : 'post'}?',
              style: TextStyle(color: themeColors.subtitleColor),
            ),
            SizedBox(height: 12),
            Text(
              'Questa operazione non può essere annullata.',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Post da eliminare:',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  ...posts.take(3).map((post) => Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${post.title.length > 40 ? post.title.substring(0, 40) + '...' : post.title}',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                      ),
                    ),
                  )).toList(),
                  if (posts.length > 3)
                    Text(
                      '... e altri ${posts.length - 3} post',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
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
            child: Text(
              'Annulla',
              style: TextStyle(color: themeColors.hintColor),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deletePostsBatch(posts);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Elimina ${posts.length} post'),
          ),
        ],
      ),
    );
  }

  /// Sposta i post selezionati in batch
  Future<void> _movePostsBatch(List<MockPost> posts, MockFolder? destination) async {
    try {
      print('DEBUG: Spostamento batch di ${posts.length} post...');
      
      // Mostra indicatore di caricamento
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 16),
                Text('Spostamento di ${posts.length} post...'),
              ],
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blue,
          ),
        );
      }

      // Sposta ogni post
      for (final post in posts) {
        await widget.folderService.movePost(post, destination);
      }

      // Esci dalla modalità selezione
      _selectionState.exitSelectionMode();
      
      // Aggiorna l'UI
      widget.onPostsUpdated();
      
      // Mostra messaggio di successo
      if (mounted) {
        final destinationName = destination?.name ?? 'Tutti';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${posts.length} post spostati in "$destinationName"'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      print('DEBUG: Spostamento batch completato con successo');
      
    } catch (e) {
      print('ERRORE: Spostamento batch fallito: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante lo spostamento: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Elimina i post selezionati in batch
  Future<void> _deletePostsBatch(List<MockPost> posts) async {
    try {
      print('DEBUG: Eliminazione batch di ${posts.length} post...');
      
      // Mostra indicatore di caricamento
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 16),
                Text('Eliminazione di ${posts.length} post...'),
              ],
            ),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }

      // Elimina ogni post
      for (final post in posts) {
        await widget.folderService.deletePost(post.id);
      }

      // Esci dalla modalità selezione
      _selectionState.exitSelectionMode();
      
      // Aggiorna l'UI
      widget.onPostsUpdated();
      
      // Mostra messaggio di successo
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${posts.length} post eliminati'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      print('DEBUG: Eliminazione batch completata con successo');
      
    } catch (e) {
      print('ERRORE: Eliminazione batch fallita: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante l\'eliminazione: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

/// Widget per visualizzare un post con supporto alla selezione multipla
class SelectablePostTile extends StatelessWidget {
  final MockPost post;
  final bool isSelected;
  final bool isDarkTheme;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget child;

  const SelectablePostTile({
    Key? key,
    required this.post,
    required this.isSelected,
    required this.isDarkTheme,
    required this.onTap,
    required this.onLongPress,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
              ? Colors.blue 
              : (isDarkTheme ? Colors.grey[700]! : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected 
            ? Colors.blue.withOpacity(0.1)
            : (isDarkTheme ? Colors.grey[850] : Colors.white),
        ),
        child: Stack(
          children: [
            // Contenuto del post
            child,
            
            // Indicatore di selezione
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}