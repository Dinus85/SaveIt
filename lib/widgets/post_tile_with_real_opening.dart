// File: lib/widgets/post_tile_with_real_opening.dart
// Widget specializzato per apertura reale dei post con supporto aggiornamenti ottimistici

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:savein/models/folder.dart';
import 'package:savein/services/folder_service.dart';
import 'package:savein/services/sharing_service.dart';
import 'package:savein/data_service.dart';

/// Widget wrapper che gestisce l'apertura reale dei post con notifiche di aggiornamento ottimistico
/// 
/// Uso:
/// ```dart
/// PostTileWithRealOpening(
///   post: myPost,
///   isDarkTheme: true,
///   folderService: folderService,
///   onPostUpdated: () => refreshPosts(),
///   child: MyPostWidget(post),
///   onLongPress: () => showContextMenu(),
/// )
/// ```
class PostTileWithRealOpening extends StatefulWidget {
  final MockPost post;
  final bool isDarkTheme;
  final FolderService folderService;
  final VoidCallback onPostUpdated;
  final Widget child;
  final bool trackViews;
  final VoidCallback? onTapOverride;
  final VoidCallback? onLongPress;
  final bool enableOptimisticUpdates; // ðŸ†• NUOVO: Flag per abilitare aggiornamenti ottimistici

  const PostTileWithRealOpening({
    Key? key,
    required this.post,
    required this.isDarkTheme,
    required this.folderService,
    required this.onPostUpdated,
    required this.child,
    this.trackViews = true,
    this.onTapOverride,
    this.onLongPress,
    this.enableOptimisticUpdates = true, // ðŸ†• NUOVO: Default abilitato
  }) : super(key: key);

  @override
  _PostTileWithRealOpeningState createState() => _PostTileWithRealOpeningState();
}

class _PostTileWithRealOpeningState extends State<PostTileWithRealOpening> {
  // ðŸ†• NUOVO: Callback DataService per ricevere notifiche di aggiornamento
  DataChangeCallback? _dataServiceCallback;
  bool _isCallbackRegistered = false;

  @override
  void initState() {
    super.initState();
    
    // ðŸ†• NUOVO: Registra callback per aggiornamenti ottimistici se abilitato
    if (widget.enableOptimisticUpdates) {
      _setupOptimisticUpdateCallback();
    }
  }

  @override
  void dispose() {
    // ðŸ†• NUOVO: Rimuovi callback durante dispose
    _removeOptimisticUpdateCallback();
    super.dispose();
  }

  // ðŸ†• NUOVO: Configura callback per aggiornamenti ottimistici relativi al post corrente
  void _setupOptimisticUpdateCallback() {
    if (_isCallbackRegistered) return;
    
    print('DEBUG: PostTile - Setup callback ottimistico per post: ${widget.post.title}');
    
    _dataServiceCallback = (String changeType, Map<String, dynamic> changeData) {
      if (!mounted) return;
      
      // Gestisci solo notifiche relative al post corrente
      switch (changeType) {
        case 'post_removed':
          _handlePostRemoved(changeData);
          break;
        case 'post_added':
          // Per aggiunta post, verifica se influisce su questo tile
          _handlePostAdded(changeData);
          break;
        case 'folder_deleted':
          _handleFolderDeleted(changeData);
          break;
        case 'cache_invalidated':
        case 'cache_reloaded':
          _handleCacheRefresh(changeData);
          break;
        default:
          // Altri tipi di cambiamento non ci interessano a livello di singolo post
          break;
      }
    };
    
    try {
      DataService.instance.registerDataChangeCallback(_dataServiceCallback!);
      _isCallbackRegistered = true;
      print('DEBUG: PostTile - Callback ottimistico registrato per: ${widget.post.title}');
    } catch (e) {
      print('DEBUG: PostTile - Errore registrazione callback: $e');
    }
  }

  // ðŸ†• NUOVO: Rimuovi callback quando non piÃ¹ necessario
  void _removeOptimisticUpdateCallback() {
    if (_isCallbackRegistered && _dataServiceCallback != null) {
      try {
        DataService.instance.unregisterDataChangeCallback(_dataServiceCallback!);
        _isCallbackRegistered = false;
        print('DEBUG: PostTile - Callback rimosso per: ${widget.post.title}');
      } catch (e) {
        print('DEBUG: PostTile - Errore rimozione callback: $e');
      }
    }
  }

  // ðŸ†• NUOVO: Gestisce rimozione post - nasconde tile se post corrente eliminato
  void _handlePostRemoved(Map<String, dynamic> data) {
    final removedPostId = data['postId'] as String?;
    
    if (removedPostId != null && removedPostId == widget.post.id) {
      print('DEBUG: PostTile - Il post corrente Ã¨ stato eliminato: ${widget.post.title}');
      
      // Notifica il parent widget che il post Ã¨ stato eliminato
      widget.onPostUpdated();
      
      // Mostra feedback visivo di rimozione
      if (mounted) {
        _showOptimisticFeedback(
          'Post eliminato', 
          Icons.delete, 
          Colors.red,
          duration: Duration(seconds: 1)
        );
      }
    }
  }

  // ðŸ†• NUOVO: Gestisce aggiunta post - aggiorna contatori se in stessa cartella
  void _handlePostAdded(Map<String, dynamic> data) {
    final addedToFolder = data['folderId'] as String?;
    
    // Se il nuovo post Ã¨ stato aggiunto alla stessa cartella, potrebbe influire sui contatori
    if (addedToFolder != null && addedToFolder == widget.post.sourceFolder?.name) {
      print('DEBUG: PostTile - Nuovo post aggiunto alla stessa cartella');
      widget.onPostUpdated();
    }
  }

  // ðŸ†• NUOVO: Gestisce eliminazione cartella - notifica se il post era in quella cartella
  void _handleFolderDeleted(Map<String, dynamic> data) {
    final deletedFolderId = data['folderId'] as String?;
    
    // Controlla se il post corrente era nella cartella eliminata
    if (deletedFolderId != null && widget.post.sourceFolder != null) {
      // PoichÃ© non abbiamo l'ID della cartella nel MockPost, confrontiamo per nome
      // In un'implementazione reale, dovremmo avere l'ID della cartella
      print('DEBUG: PostTile - Cartella eliminata, verificando impatto su post');
      widget.onPostUpdated();
    }
  }

  // ðŸ†• NUOVO: Gestisce refresh cache generale
  void _handleCacheRefresh(Map<String, dynamic> data) {
    print('DEBUG: PostTile - Cache refresh, aggiornando vista');
    widget.onPostUpdated();
  }

  // ðŸ†• NUOVO: Mostra feedback visivo per operazioni ottimistiche
  void _showOptimisticFeedback(String message, IconData icon, Color color, {Duration? duration}) {
    if (!mounted) return;
    
    
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onTapOverride?.call() ?? _openPostDirectly(context),
      onLongPress: widget.onLongPress,
      child: widget.child,
    );
  }

  /// Apre il post nel browser reale con tracking ottimistico
  Future<void> _openPostDirectly(BuildContext context) async {
    try {
      print('DEBUG: PostTileWithRealOpening - Apertura reale del post: ${widget.post.title}');
      print('DEBUG: PostTileWithRealOpening - URL: ${widget.post.url}');
      
      // ðŸ†• NUOVO: Traccia la visualizzazione con aggiornamento ottimistico
      if (widget.trackViews) {
        widget.folderService.trackPostViewed(widget.post);
        
        // Notifica aggiornamento ottimistico per statistiche di visualizzazione
        if (widget.enableOptimisticUpdates) {
          widget.onPostUpdated();
        }
      }
      
      // Apri il link reale usando SharingService
      await SharingService.openPostDirectly(context, widget.post.url);
      
      print('DEBUG: PostTileWithRealOpening - Post aperto con successo');
      
      // ðŸ†• NUOVO: Feedback ottimistico per apertura riuscita
      if (mounted && widget.enableOptimisticUpdates) {
        _showOptimisticFeedback(
          'Post aperto',
          Icons.open_in_new, 
          Colors.green,
          duration: Duration(seconds: 1)
        );
      }
      
    } catch (e) {
      print('ERRORE: PostTileWithRealOpening - Apertura fallita: $e');
      

    }
  }

  /// Mostra snackbar di errore
  void _showErrorSnackBar(BuildContext context, String message) {
    
  }

  /// Copia URL negli appunti come fallback
  void _copyUrlToClipboard(BuildContext context) {
    try {
      Clipboard.setData(ClipboardData(text: widget.post.url));
      
      
    } catch (e) {
      print('ERRORE: Copia URL fallita: $e');
    }
  }
}

/// Widget avanzato per post clickable con piÃ¹ opzioni e aggiornamenti ottimistici
class AdvancedPostTile extends StatefulWidget {
  final MockPost post;
  final bool isDarkTheme;
  final FolderService folderService;
  final VoidCallback onPostUpdated;
  final Widget child;
  final bool showContextMenu;
  final List<PopupMenuEntry<String>>? customMenuItems;
  final Function(String)? onMenuItemSelected;
  final bool enableOptimisticUpdates; // ðŸ†• NUOVO

  const AdvancedPostTile({
    Key? key,
    required this.post,
    required this.isDarkTheme,
    required this.folderService,
    required this.onPostUpdated,
    required this.child,
    this.showContextMenu = false,
    this.customMenuItems,
    this.onMenuItemSelected,
    this.enableOptimisticUpdates = true, // ðŸ†• NUOVO
  }) : super(key: key);

  @override
  _AdvancedPostTileState createState() => _AdvancedPostTileState();
}

class _AdvancedPostTileState extends State<AdvancedPostTile> {
  @override
  Widget build(BuildContext context) {
    if (widget.showContextMenu) {
      return GestureDetector(
        onLongPress: () => _showContextMenu(context),
        child: PostTileWithRealOpening(
          post: widget.post,
          isDarkTheme: widget.isDarkTheme,
          folderService: widget.folderService,
          onPostUpdated: widget.onPostUpdated,
          enableOptimisticUpdates: widget.enableOptimisticUpdates, // ðŸ†• NUOVO: Passa flag
          child: widget.child,
        ),
      );
    }
    
    return PostTileWithRealOpening(
      post: widget.post,
      isDarkTheme: widget.isDarkTheme,
      folderService: widget.folderService,
      onPostUpdated: widget.onPostUpdated,
      enableOptimisticUpdates: widget.enableOptimisticUpdates, // ðŸ†• NUOVO: Passa flag
      child: widget.child,
    );
  }

  void _showContextMenu(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + renderBox.size.width,
        position.dy + renderBox.size.height,
      ),
      items: widget.customMenuItems ?? [
        PopupMenuItem(
          value: 'open',
          child: ListTile(
            leading: Icon(Icons.open_in_new, size: 16),
            title: Text('Apri link'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            leading: Icon(Icons.copy, size: 16),
            title: Text('Copia URL'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'share',
          child: ListTile(
            leading: Icon(Icons.share, size: 16),
            title: Text('Condividi'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        // ðŸ†• NUOVO: Opzione per eliminare post con aggiornamento ottimistico
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete, size: 16, color: Colors.red),
            title: Text('Elimina post', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        widget.onMenuItemSelected?.call(value) ?? _handleDefaultMenuAction(context, value);
      }
    });
  }

  // ðŸ†• MODIFICATO: Aggiunta gestione eliminazione ottimistica
  void _handleDefaultMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'open':
        SharingService.openPostDirectly(context, widget.post.url);
        break;
      case 'copy':
        Clipboard.setData(ClipboardData(text: widget.post.url));
        
        break;
      case 'share':
        // Implementa condivisione nativa se necessario
        break;
      case 'delete': // ðŸ†• NUOVO: Gestione eliminazione ottimistica
        _showDeleteConfirmationDialog(context);
        break;
    }
  }

  // ðŸ†• NUOVO: Dialog di conferma eliminazione con aggiornamento ottimistico
  void _showDeleteConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text(
              'Elimina Post',
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Sei sicuro di voler eliminare il post "${widget.post.title}"?\n\nQuesta operazione non puÃ² essere annullata.',
          style: TextStyle(
            color: widget.isDarkTheme ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Annulla',
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => _deletePostOptimistically(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Elimina'),
          ),
        ],
      ),
    );
  }

  // ðŸ†• NUOVO: Eliminazione post con aggiornamento ottimistico
  Future<void> _deletePostOptimistically(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop(); // Chiudi dialog
    
    try {
      print('DEBUG: AdvancedPostTile - Eliminazione ottimistica post: ${widget.post.title}');
      
      // ðŸ”„ STEP 1: Aggiornamento ottimistico UI (immediato)
      if (widget.enableOptimisticUpdates) {
        widget.onPostUpdated(); // Nasconde immediatamente il tile
        
        // Feedback visivo immediato
        
        );
      }
      
      // ðŸ”„ STEP 2: Operazione effettiva (background)
      // Convertire MockPost a SavedPost per eliminazione tramite DataService
      final savedPost = widget.post.toSavedPost();
      
      await DataService.instance.deletePost(savedPost.id);
      
      print('DEBUG: AdvancedPostTile - Post eliminato con successo');
      
      // ðŸ”„ STEP 3: Conferma successo (il DataService notificherÃ  automaticamente via callback)
      if (mounted) {
        
      }
      
    } catch (e) {
      print('ERRORE: AdvancedPostTile - Eliminazione fallita: $e');
      
      // ðŸ”„ STEP 4: Gestione errore - ripristina UI se possibile
      if (mounted) {
        widget.onPostUpdated(); // Forza refresh per ripristinare stato
        
        
      }
    }
  }
}

/// Widget compatto per grid di post con apertura reale e aggiornamenti ottimistici
class CompactPostTile extends StatelessWidget {
  final MockPost post;
  final bool isDarkTheme;
  final FolderService folderService;
  final VoidCallback onPostUpdated;
  final bool enableOptimisticUpdates; // ðŸ†• NUOVO

  const CompactPostTile({
    Key? key,
    required this.post,
    required this.isDarkTheme,
    required this.folderService,
    required this.onPostUpdated,
    this.enableOptimisticUpdates = true, // ðŸ†• NUOVO
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PostTileWithRealOpening(
      post: post,
      isDarkTheme: isDarkTheme,
      folderService: folderService,
      onPostUpdated: onPostUpdated,
      enableOptimisticUpdates: enableOptimisticUpdates, // ðŸ†• NUOVO
      child: Container(
        decoration: BoxDecoration(
          color: isDarkTheme ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkTheme ? Colors.grey[700]! : Colors.grey[300]!,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con dominio
            Container(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(
                    _getPlatformIcon(),
                    size: 12,
                    color: isDarkTheme ? Colors.grey[400] : Colors.grey[600],
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _getDomain(),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDarkTheme ? Colors.grey[400] : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            
            // Titolo
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  post.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDarkTheme ? Colors.white : Colors.black87,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            
            // Footer con data
            Container(
              padding: EdgeInsets.all(8),
              child: Text(
                _formatDate(post.savedDate),
                style: TextStyle(
                  fontSize: 10,
                  color: isDarkTheme ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPlatformIcon() {
    final domain = _getDomain().toLowerCase();
    if (domain.contains('youtube')) return Icons.play_circle_outline;
    if (domain.contains('github')) return Icons.code;
    if (domain.contains('instagram')) return Icons.camera_alt;
    if (domain.contains('twitter') || domain.contains('x.com')) return Icons.alternate_email;
    return Icons.link;
  }

  String _getDomain() {
    try {
      final uri = Uri.parse(post.url);
      return uri.host.replaceAll('www.', '');
    } catch (e) {
      return post.url;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) return 'Oggi';
    if (difference.inDays == 1) return 'Ieri';
    if (difference.inDays < 7) return '${difference.inDays}g fa';
    return '${date.day}/${date.month}';
  }
}

/// ðŸ†• NUOVO: Widget wrapper ottimistico per operazioni batch sui post
class OptimisticPostBatchOperations extends StatelessWidget {
  final List<MockPost> posts;
  final bool isDarkTheme;
  final FolderService folderService;
  final VoidCallback onPostsUpdated;

  const OptimisticPostBatchOperations({
    Key? key,
    required this.posts,
    required this.isDarkTheme,
    required this.folderService,
    required this.onPostsUpdated,
  }) : super(key: key);

  /// Elimina multipli post con feedback ottimistico
  Future<void> deletePostsBatch(BuildContext context, List<MockPost> postsToDelete) async {
    if (postsToDelete.isEmpty) return;
    
    try {
      print('DEBUG: Eliminazione batch di ${postsToDelete.length} post...');
      
      // Feedback ottimistico immediato
      
      
      // Aggiornamento ottimistico UI
      onPostsUpdated();
      
      // Operazioni effettive in background
      for (final post in postsToDelete) {
        final savedPost = post.toSavedPost();
        await DataService.instance.deletePost(savedPost.id);
      }
      
      print('DEBUG: Eliminazione batch completata con successo');
      
      // Conferma successo
      if (context.mounted) {
        
      }
      
    } catch (e) {
      print('ERRORE: Eliminazione batch fallita: $e');
      
      // Ripristina UI in caso di errore
      onPostsUpdated();
      
      if (context.mounted) {
       
      }
    }
  }

  /// Sposta multipli post con feedback ottimistico
  Future<void> movePostsBatch(
    BuildContext context, 
    List<MockPost> postsToMove, 
    String targetFolderId
  ) async {
    if (postsToMove.isEmpty) return;
    
    try {
      print('DEBUG: Spostamento batch di ${postsToMove.length} post...');
      
      // Feedback ottimistico immediato
      
      
      // Aggiornamento ottimistico UI
      onPostsUpdated();
      
      // Operazioni effettive (questo richiederebbe l'implementazione di movePost nel DataService)
      // Per ora simuliamo l'operazione
      await Future.delayed(Duration(seconds: 1));
      
      print('DEBUG: Spostamento batch completato con successo');
      
      // Conferma successo
      if (context.mounted) {
        
      }
      
    } catch (e) {
      print('ERRORE: Spostamento batch fallito: $e');
      
      // Ripristina UI in caso di errore
      onPostsUpdated();
      
      if (context.mounted) {
        
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Questo widget Ã¨ principalmente un utility container
    // Non ha una propria UI ma fornisce metodi per operazioni batch
    return Container();
  }
}