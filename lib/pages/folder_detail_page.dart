import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Per HapticFeedback
import 'package:cached_network_image/cached_network_image.dart';
import 'package:savein/models/folder.dart';
import 'package:savein/widgets/folder_card.dart';
import 'package:savein/widgets/post_preview_image.dart';
import 'package:savein/widgets/search_results_widget.dart';
import 'package:savein/widgets/multi_select_post_manager.dart';
import 'package:savein/services/access_control_service.dart';
import 'package:savein/services/folder_service.dart';
import 'package:savein/services/sharing_service.dart';
import 'package:savein/services/share_link_service.dart';
import 'package:savein/services/reminder_service.dart';
import 'package:savein/services/auth_service.dart';
import 'package:savein/services/interstitial_ad_service.dart';
import 'package:savein/utils/theme_helpers.dart';
import 'package:savein/utils/dialog_helpers.dart';
import 'package:savein/pages/account_page.dart';
import 'package:savein/pages/auth_wrapper.dart';
import 'package:savein/pages/shared_items_page.dart';
import 'package:savein/widgets/custom_bottom_nav.dart';
import 'package:savein/data_service.dart';
import 'package:savein/widgets/reminder_dialog.dart';

// Pagina dettaglio cartella CON APERTURA REALE DEI POST E SELEZIONE MULTIPLA
class FolderDetailPage extends StatefulWidget {
  final MockFolder folder;
  final bool isDarkTheme;
  final List<MockFolder> allFolders;
  final VoidCallback onFolderUpdated;
  final Function(bool)? onThemeChanged;
  final String? highlightPostId;
  final String? highlightFolderId;

  const FolderDetailPage({
    Key? key,
    required this.folder,
    required this.isDarkTheme,
    required this.allFolders,
    required this.onFolderUpdated,
    this.onThemeChanged,
    this.highlightPostId,
    this.highlightFolderId,
  }) : super(key: key);

  @override
  _FolderDetailPageState createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final AppAccessService _accessService = AppAccessService();
  final FolderService _folderService = FolderService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _contentScrollController = ScrollController();
  bool _showScrollToTopButton = false;

  // Copia locale aggiornabile del folder
  late MockFolder _currentFolder;

  List<MockPost> _posts = [];
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;

  Timer? _searchDebounceTimer;
  String _lastTrackedQuery = '';

  // 🔥 FIX: Traccia i timer per cancellarli nel dispose
  Timer? _firstRefreshTimer;
  Timer? _secondRefreshTimer;
  Timer? _highlightTimer;
  Timer? _highlightRetryTimer;
  bool _showReminderHighlight = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  // GlobalKey per trovare la posizione reale del post/subfolder evidenziato nello scroll
  final GlobalKey _highlightedPostKey = GlobalKey();
  final GlobalKey _highlightedFolderKey = GlobalKey();

  String? get _subfolderCreationError => _currentFolder.isSpecial
      ? 'Non puoi creare sottocartelle in "Tutti".'
      : null;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 🔥 NUOVO: Registra observer per lifecycle
    WidgetsBinding.instance.addObserver(this);

    // Inizializza la copia locale
    _currentFolder = widget.folder;

    print(
        'DEBUG: FolderDetailPage inizializzato per cartella: ${_currentFolder.name}');

    _searchController.addListener(_onSearchChanged);
    _contentScrollController.addListener(_onContentScroll);

    _folderService.trackFolderOpened(_currentFolder);

    // Dopo import: aggiorna la lista quando arrivano anteprima/metadati in background.
    if (widget.highlightPostId != null) {
      _folderService.setOnDataChangedCallback(_updateUISafely);
      _firstRefreshTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _loadPosts();
      });
      _secondRefreshTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) _loadPosts();
      });
    } else {
      // L'aggiornamento avviene SOLO con pull-to-refresh manuale
      _folderService.setOnDataChangedCallback(null);
    }

    _loadPostsEnsuringSync();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealReminderTarget();
    });
  }

  @override
  void dispose() {
    // 🔥 NUOVO: Rimuovi observer per lifecycle
    WidgetsBinding.instance.removeObserver(this);

    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    // 🔥 FIX: Cancella i timer di refresh per evitare setState dopo dispose
    _firstRefreshTimer?.cancel();
    _secondRefreshTimer?.cancel();
    _highlightTimer?.cancel();
    _highlightRetryTimer?.cancel();
    _pulseController.dispose();
    _folderService
        .setOnDataChangedCallback(null); // 🔥 NUOVO: Rimuovi il callback
    _contentScrollController.removeListener(_onContentScroll);
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('DEBUG: FolderDetailPage - Lifecycle cambiato a: $state');

    if (state == AppLifecycleState.resumed) {
      // 🔥 FIX: Al resume NON facciamo nulla di visibile.
      // Il refresh dei dati avverrà in background tramite SaveInApp -> FolderService
      // Quando i dati saranno pronti, verrà chiamato il callback che invocherà _updateUISafely().
      // Questo previene flash, sparizioni e cambi di cartella indesiderati.
      print(
          'DEBUG: App resumed - Attendo aggiornamenti silenziosi dal servizio...');
    }
  }

  // ✅ NUOVO: Metodo per trovare e aggiornare il folder corrente
  void _updateCurrentFolder() {
    MockFolder? updatedFolder = _findFolderInServiceHierarchy(_currentFolder);

    if (updatedFolder != null) {
      if (mounted) {
        setState(() {
          _currentFolder = updatedFolder;
        });
        print(
            'DEBUG: Folder corrente aggiornato: ${_currentFolder.name}, children: ${_currentFolder.children.length}');
      }
    } else {
      // 🔥 FIX: Se la cartella non viene trovata (es. durante reload parziale),
      // NON aggiornare _currentFolder e NON chiamare setState.
      // Questo mantiene i vecchi dati visibili finché non arriva un update valido.
      print(
          'WARNING: Folder corrente non trovato in FolderService - Ignoro update per evitare sparizione UI');
    }
  }

  // ✅ NUOVO: Trova il folder corrispondente nella gerarchia di FolderService
  MockFolder? _findFolderInServiceHierarchy(MockFolder target) {
    if (target.isSpecial) {
      try {
        return _folderService.folders.firstWhere(
          (folder) => folder.isSpecial && folder.name == target.name,
        );
      } catch (_) {
        return null;
      }
    }

    final pathSegments = _buildFolderPathSegments(target);
    if (pathSegments.isEmpty) {
      return null;
    }

    final found = _folderService.findFolderByCompletePath(pathSegments);
    return found;
  }

  // Helper per confrontare liste di post
  bool _arePostListsEqual(List<MockPost> oldList, List<MockPost> newList) {
    if (oldList.length != newList.length) return false;
    for (int i = 0; i < oldList.length; i++) {
      if (oldList[i].id != newList[i].id) return false;
      if (oldList[i].title != newList[i].title) return false;
      if (oldList[i].imageUrl != newList[i].imageUrl) return false;
      if (oldList[i].previewStorageUrl != newList[i].previewStorageUrl) {
        return false;
      }
    }
    return true;
  }

  // 🔥 FIX: Aggiorna UI solo se i dati sono validi E diversi per evitare flash
  void _updateUISafely() {
    final updatedFolder = _findFolderInServiceHierarchy(_currentFolder);

    if (updatedFolder == null) {
      print(
          'WARNING: Cartella corrente sparita dal servizio, mantengo vecchia UI');
      return;
    }

    final newPosts = _folderService.getPostsForFolder(updatedFolder);

    // 1. Controllo validità: Se il servizio è vuoto (reload in corso), ignoriamo
    if (newPosts.isEmpty && _posts.isNotEmpty) {
      if (_folderService.allPosts.isEmpty) {
        print(
            'DEBUG: Rilevato possibile reload in corso (0 post totali), ignoro update vuoto');
        return;
      }
    }

    // 2. Controllo differenze: Aggiorniamo solo se c'è un cambiamento reale
    if (_arePostListsEqual(_posts, newPosts) &&
        _currentFolder == updatedFolder) {
      print('DEBUG: Nessun cambiamento rilevante nei dati. Skip update UI.');
      return;
    }

    if (mounted) {
      setState(() {
        _currentFolder = updatedFolder;
        _posts = newPosts;
      });
      print(
          'DEBUG: UI aggiornata: ${_currentFolder.name}, ${_posts.length} post');
    }
  }

  List<String> _buildFolderPathSegments(MockFolder folder) {
    final segments = <String>[];
    MockFolder? current = folder;

    while (current != null && !current.isSpecial) {
      segments.insert(0, current.name);
      current = current.parent;
    }

    return segments;
  }

  void _loadPosts() {
    if (mounted) {
      setState(() {
        _posts = _folderService.getPostsForFolder(_currentFolder);
      });
      print(
          'DEBUG: Caricati ${_posts.length} post per cartella: ${_currentFolder.name}');
    }
  }

  // 🔥 FIX FINALE: Caricamento semplificato SENZA sync/update automatici
  // I dati vengono caricati SOLO una volta all'apertura, poi rimangono statici
  // L'aggiornamento avviene SOLO con pull-to-refresh manuale
  Future<void> _loadPostsEnsuringSync() async {
    // Mostra i post usando la cartella passata dal widget, SENZA cercare aggiornamenti
    if (mounted) {
      setState(() {
        _posts = _folderService.getPostsForFolder(_currentFolder);
      });
      print(
          'DEBUG: Caricati ${_posts.length} post per cartella: ${_currentFolder.name} (path: ${buildFullPathForFolder(_currentFolder)})');
    }
  }

  void _onContentScroll() {
    if (!_contentScrollController.hasClients) return;
    final pos = _contentScrollController.position;

    // Mostra bottone "torna su" dopo un po' di scroll
    const showAfter = 450.0;
    final shouldShow = pos.pixels > showAfter;
    if (shouldShow != _showScrollToTopButton && mounted) {
      setState(() {
        _showScrollToTopButton = shouldShow;
      });
    }
  }

  Future<void> _scrollToTop() async {
    if (!_contentScrollController.hasClients) return;
    try {
      await _contentScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  // Helper per costruire il path completo della cartella (per debug)
  String buildFullPathForFolder(MockFolder folder) {
    if (folder.isSpecial) return folder.name;

    List<String> pathParts = [];
    MockFolder? current = folder;

    while (current != null && !current.isSpecial) {
      pathParts.insert(0, current.name);
      current = current.parent;
    }

    return pathParts.join(' › ');
  }

  // 🔥 NUOVO: Metodo per forzare il refresh automatico con retry
  Future<void> _forceRefreshPosts() async {
    try {
      print(
          'DEBUG: Forzando refresh automatico per cartella: ${_currentFolder.name}');

      // STEP 1: Sync completo con retry
      int retryCount = 0;
      final maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          // Sincronizza con il database
          await DataService.instance.reloadFromDisk();
          await _folderService.syncWithDataService();
          break; // Successo, esci dal loop
        } catch (e) {
          retryCount++;
          if (retryCount < maxRetries) {
            print('DEBUG: Retry $retryCount/$maxRetries - Errore sync: $e');
            await Future.delayed(Duration(milliseconds: 500));
          } else {
            print('DEBUG: Sync fallito dopo $maxRetries tentativi: $e');
          }
        }
      }

      // STEP 2: Aggiorna il folder corrente
      _updateCurrentFolder();

      // STEP 3: Ricarica i post
      if (mounted) {
        _loadPosts();
      }

      print('DEBUG: ✅ Refresh automatico completato');
    } catch (e) {
      print('ERRORE: Refresh automatico fallito: $e');
    }
  }

  // 🔥 NUOVO: Ordina alfabeticamente le sottocartelle
  List<MockFolder> _getSortedSubfolders() {
    final children = List<MockFolder>.from(_currentFolder.children);
    children
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return children;
  }

  Future<void> _onPullToRefreshFolder() async {
    try {
      print('DEBUG: ========== PULL TO REFRESH FOLDER ==========');

      // 🔥 STEP 1: Feedback tattile
      HapticFeedback.lightImpact();

      // 🔥 STEP 2: Invalida cache posts per forzare reload
      DataService.instance.invalidateCache(folders: false, posts: true);

      // 🔥 STEP 3: Aspetta un attimo per propagazione
      await Future.delayed(Duration(milliseconds: 200));

      // 🔥 STEP 4: Ricarica dati
      await _folderService.syncWithDataService();

      // 🔥 STEP 5: Aggiorna il folder corrente
      _updateCurrentFolder();

      // 🔥 STEP 6: Ricarica i post
      _loadPosts();

      // 🔥 STEP 7: Aggiorna UI
      if (mounted) {
        setState(() {
          // Forza rebuild
        });
      }

      // 🔥 STEP 8: Notifica parent
      if (mounted) {
        widget.onFolderUpdated();
      }

      print('DEBUG: ✅ Pull-to-refresh cartella completato');
    } catch (e) {
      print('ERRORE: Pull-to-refresh cartella fallito: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore aggiornamento: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _onSearchChanged() {
    // 🔥 FIX: Controlla se il widget è ancora montato
    if (!mounted) return;

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults.clear();
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSearching = true;
        _searchResults =
            _folderService.searchUnified(query, trackSearch: false);
      });
    }

    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(Duration(milliseconds: 1500), () {
      // 🔥 FIX: Controlla mounted nel callback del timer
      if (!mounted) return;
      if (query != _lastTrackedQuery && query.length >= 2) {
        _folderService.searchUnified(query, trackSearch: true);
        _lastTrackedQuery = query;
        print(
            'DEBUG: Ricerca tracciata: "$query" con ${_searchResults.length} risultati');
      }
    });

    print(
        'DEBUG: Ricerca nella cartella ${_currentFolder.name} per "$query" ha restituito ${_searchResults.length} risultati');
  }

  String _buildBreadcrumb(MockFolder folder) {
    List<String> path = [];
    MockFolder? current = folder.parent;

    while (current != null) {
      if (!current.isSpecial) {
        path.insert(0, current.name);
      }
      current = current.parent;
    }

    if (path.isEmpty) {
      return 'Cartella principale';
    }

    return path.join(' > ');
  }

  String _buildPostBreadcrumb(MockFolder? sourceFolder) {
    if (sourceFolder == null) {
      return 'Tutti';
    }

    List<String> path = [];
    MockFolder? current = sourceFolder;

    while (current != null) {
      if (!current.isSpecial) {
        path.insert(0, current.name);
      }
      current = current.parent;
    }

    if (path.isEmpty) {
      return 'Home';
    }

    return 'Home > ${path.join(' > ')}';
  }

  void _revealReminderTarget() {
    if (!mounted ||
        (widget.highlightPostId == null && widget.highlightFolderId == null)) {
      return;
    }

    setState(() => _showReminderHighlight = true);
    _pulseController.repeat(reverse: true);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _pulseController.stop();
        setState(() => _showReminderHighlight = false);
      }
    });

    final startedAt = DateTime.now();
    void retryUntilFound() {
      if (!mounted || !_showReminderHighlight) return;
      final found = _scrollToReminderTargetIfAvailable();
      if (found) return;
      if (DateTime.now().difference(startedAt) >= const Duration(seconds: 5)) {
        return;
      }
      _highlightRetryTimer?.cancel();
      _highlightRetryTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted && widget.highlightPostId != null) {
          _loadPosts();
        }
        retryUntilFound();
      });
    }

    retryUntilFound();
  }

  bool _scrollToReminderTargetIfAvailable() {
    final postId = widget.highlightPostId;
    if (postId != null && postId.isNotEmpty) {
      final postIndex = _posts.indexWhere((post) => post.id == postId);
      if (postIndex < 0) return false;

      // Prima passa: porta il post approssimativamente in vista con la stima
      // (necessario perché SliverList non renderizza elementi fuori schermo)
      if (!_contentScrollController.hasClients) return false;
      final keyCtx = _highlightedPostKey.currentContext;
      if (keyCtx == null) {
        // Post non ancora costruito da SliverList → scroll approssimativo per metterlo in vista
        final estimatedOffset = _estimatedPostOffset(postIndex);
        _animateToCenteredOffset(estimatedOffset);
        // Dopo l'animazione il widget sarà renderizzato, centratura esatta nel prossimo retry
        return false;
      }
      // Seconda passa: usa la posizione reale per centratura precisa
      _centerOnKey(_highlightedPostKey);
      return true;
    }

    final folderId = widget.highlightFolderId;
    if (folderId != null &&
        folderId.isNotEmpty &&
        folderId != _currentFolder.id) {
      final index =
          _getSortedSubfolders().indexWhere((folder) => folder.id == folderId);
      if (index < 0) return false;

      if (!_contentScrollController.hasClients) return false;
      final keyCtx = _highlightedFolderKey.currentContext;
      if (keyCtx == null) {
        // Subfolder non ancora costruita dal SliverGrid → stima grossolana per portarla in vista
        final row = index ~/ 2;
        _animateToCenteredOffset(16.0 + (row * 190.0));
        return false;
      }
      // Posizione reale nota → centrata precisa
      _centerOnKey(_highlightedFolderKey);
      return true;
    }
    return widget.highlightFolderId == _currentFolder.id;
  }

  /// Scrolla il CustomScrollView in modo che il widget con [key] sia centrato.
  void _centerOnKey(GlobalKey key) {
    final keyCtx = key.currentContext;
    if (keyCtx == null || !_contentScrollController.hasClients) return;
    final box = keyCtx.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Trova il RenderBox del Scrollable
    final scrollable = Scrollable.maybeOf(keyCtx);
    if (scrollable == null) return;
    final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
    if (scrollableBox == null) return;

    // Posizione dell'item relativa al viewport
    final itemOffset = box.localToGlobal(Offset.zero, ancestor: scrollableBox);
    final itemHeight = box.size.height;
    final viewportHeight = _contentScrollController.position.viewportDimension;
    final currentOffset = _contentScrollController.offset;

    // itemOffset.dy è dove l'item si trova ATTUALMENTE nel viewport
    // Vogliamo che il centro dell'item sia al centro del viewport
    final itemTopInScroll = currentOffset + itemOffset.dy;
    final centeredOffset = itemTopInScroll - (viewportHeight - itemHeight) / 2;

    _contentScrollController.animateTo(
      centeredOffset.clamp(
          0.0, _contentScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  double _estimatedPostOffset(int postIndex) {
    final subfolderRows = (_currentFolder.children.length / 2).ceil();
    final subfoldersHeight = _currentFolder.children.isNotEmpty
        ? 16.0 + (subfolderRows * 190.0)
        : 0.0;
    const postsHeaderHeight = 76.0;
    return subfoldersHeight + postsHeaderHeight + (postIndex * 150.0);
  }

  bool _animateToCenteredOffset(double itemOffset) {
    if (!_contentScrollController.hasClients) return false;
    final viewportHeight = _contentScrollController.position.viewportDimension;
    final maxScroll = _contentScrollController.position.maxScrollExtent;
    if (viewportHeight <= 0 || maxScroll <= 0) return false;
    // Sottraggo metà viewport per centrare il post a schermo
    final centeredOffset = itemOffset - (viewportHeight * 0.5);
    final target = centeredOffset.clamp(0.0, maxScroll);
    _contentScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);

    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeaderWithSearch(themeColors),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _isSearching
                    ? _buildSearchResults(themeColors)
                    : _buildFolderContent(themeColors),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        isDarkTheme: widget.isDarkTheme,
        onHomeTap: () => Navigator.popUntil(context, (route) => route.isFirst),
        onAddTap: () => _showCreateFolderDialog(themeColors),
        onAccountTap: _openAccountPage,
      ),
      floatingActionButton: (!_isSearching && _showScrollToTopButton)
          ? FloatingActionButton.small(
              onPressed: _scrollToTop,
              backgroundColor:
                  widget.isDarkTheme ? Colors.black87 : Colors.white,
              foregroundColor:
                  widget.isDarkTheme ? Colors.white : Colors.black87,
              child: const Icon(Icons.keyboard_arrow_up),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildHeaderWithSearch(ThemeColors themeColors) {
    final highlightCurrentFolder = _showReminderHighlight &&
        widget.highlightFolderId != null &&
        widget.highlightFolderId == _currentFolder.id;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlightCurrentFolder
            ? Colors.orange.withOpacity(0.16)
            : themeColors.mainBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: highlightCurrentFolder
                ? Colors.orange
                : (widget.isDarkTheme
                    ? Colors.grey.shade800
                    : Colors.grey.shade200),
            width: highlightCurrentFolder ? 2 : 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back,
                    color: themeColors.iconColor, size: 28),
                onPressed: () {
                  if (_isSearching) {
                    // Se in modalità ricerca, torna alla vista normale della cartella
                    if (mounted) {
                      setState(() {
                        _isSearching = false;
                        _searchController.clear();
                      });
                    }
                  } else {
                    // Altrimenti torna alla home
                    if (mounted) {
                      widget.onFolderUpdated();
                      Navigator.pop(context);
                    }
                  }
                },
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _isSearching
                    ? Text(
                        'Ricerca per',
                        style: TextStyle(
                          color: themeColors.titleColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentFolder.name,
                            style: TextStyle(
                              color: themeColors.titleColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_currentFolder.level > 0) ...[
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  color: themeColors.iconColor,
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _buildBreadcrumb(_currentFolder),
                                    style: TextStyle(
                                      color: themeColors.textColor
                                          .withOpacity(0.8),
                                      fontSize: 12,
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
              ),
              if (AuthService().currentUser != null && !_isSearching)
                LogoutButton(
                  onLogoutComplete: () {},
                  isDarkTheme: widget.isDarkTheme,
                  onThemeChanged: widget.onThemeChanged,
                ),
            ],
          ),
          SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: _isSearching
                  ? Border.all(color: Colors.black, width: 1)
                  : Border.all(color: Colors.black, width: 1),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: const Color.fromARGB(255, 66, 66, 66)),
              decoration: InputDecoration(
                hintText: 'Cerca cartelle e #hashtags...',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSearching && _searchResults.isNotEmpty)
                      Container(
                        margin: EdgeInsets.only(right: 8),
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 206, 208, 210),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_searchResults.length}',
                          style: TextStyle(
                            color: const Color.fromARGB(255, 8, 8, 8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    _searchController.text.isNotEmpty
                        ? IconButton(
                            icon:
                                Icon(Icons.clear, color: Colors.grey.shade600),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : Icon(Icons.search, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ThemeColors themeColors) {
    return SearchResultsWidget(
      searchResults: _searchResults,
      isDarkTheme: widget.isDarkTheme,
      onResultTap: _openSearchResult,
      onRefresh: _onPullToRefreshFolder,
    );
  }

  void _openAccountPage() {
    print('DEBUG: Tentativo di aprire AccountPage');

    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AccountPage(
            isDarkTheme: widget.isDarkTheme,
            marketingProfileEnabled: false,
            marketingCommsEnabled: false,
            onThemeChanged: (isDark) {
              print('DEBUG: Cambio tema richiesto: $isDark');
              if (widget.onThemeChanged != null) {
                widget.onThemeChanged!(isDark);
              }
            },
            onMarketingProfileChanged: (enabled) {
              print('DEBUG: Cambio marketing profile: $enabled');
            },
            onMarketingCommsChanged: (enabled) {
              print('DEBUG: Cambio marketing comms: $enabled');
            },
            folders: _folderService.folders,
          ),
        ),
      );
      print('DEBUG: AccountPage navigation chiamata con successo');
    } catch (e) {
      print('ERRORE: Impossibile aprire AccountPage: $e');
    }
  }

  void _openSharedItemsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SharedItemsPage(
          isDarkTheme: widget.isDarkTheme,
        ),
      ),
    );
  }

  void _openSearchResult(SearchResult result) {
    if (result.type == 'folder' && result.folder != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FolderDetailPage(
            folder: result.folder!,
            isDarkTheme: widget.isDarkTheme,
            allFolders: widget.allFolders,
            onFolderUpdated: widget.onFolderUpdated,
            onThemeChanged: widget.onThemeChanged,
          ),
        ),
      ).then((_) {
        // 🔥 FIX: NON aggiornare il folder corrente automaticamente per evitare confusione
        // con cartelle omonime. L'aggiornamento avviene solo con pull-to-refresh manuale.
        if (mounted) {
          setState(() {
            _loadPosts();
          });
        }
      });
    } else if (result.type == 'post' && result.post != null) {
      _openPostDirectly(result.post!);
    }
  }

  // ✅ CORRETTO: Usa il vero metodo di apertura URL
  void _openPostDirectly(MockPost post) async {
    _folderService.trackPostViewed(post);

    try {
      print('DEBUG: Apertura reale del post: ${post.title}');
      print('DEBUG: URL: ${post.url}');

      // USA IL METODO REALE DI APERTURA
      await SharingService.openPostDirectly(context, post.url);
    } catch (e) {
      print('ERRORE: Apertura post fallita: $e');
    }
  }

  Widget _buildFolderContent(ThemeColors themeColors) {
    final hasSubfolders = _currentFolder.children.isNotEmpty;
    final hasPosts = _posts.isNotEmpty;

    if (!hasSubfolders && !hasPosts) {
      // Per stato vuoto, usa RefreshIndicator con contenuto non scrollabile
      return RefreshIndicator(
        onRefresh: _onPullToRefreshFolder,
        color: Colors.blue,
        backgroundColor: widget.isDarkTheme ? Colors.grey[800] : Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height - 200,
            child: _buildEmptyState(themeColors),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onPullToRefreshFolder,
      color: Colors.blue,
      backgroundColor: widget.isDarkTheme ? Colors.grey[800] : Colors.white,
      child: CustomScrollView(
        controller: _contentScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Sezione Sottocartelle
          if (hasSubfolders)
            SliverPadding(
              padding: const EdgeInsets.only(top: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.0,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sortedChildren = _getSortedSubfolders();
                    final subfolder = sortedChildren[index];
                    final highlightSubfolder = _showReminderHighlight &&
                        widget.highlightFolderId != null &&
                        widget.highlightFolderId == subfolder.id;

                    final card = MockFolderCard(
                      folder: subfolder,
                      onTap: () => _openSubfolder(subfolder),
                      onRename: _showRenameSubfolderDialog,
                      onDelete: _showDeleteSubfolderDialog,
                      onMove: _showMoveSubfolderDialog,
                      allFolders: widget.allFolders,
                      isDarkTheme: widget.isDarkTheme,
                    );

                    if (highlightSubfolder) {
                      return AnimatedBuilder(
                        key: _highlightedFolderKey,
                        animation: _pulseAnim,
                        builder: (context, child) {
                          final pulse = _pulseAnim.value;
                          return Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.orange
                                  .withOpacity(0.18 + pulse * 0.22),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.orange
                                    .withOpacity(0.7 + pulse * 0.3),
                                width: 2.5 + pulse * 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange
                                      .withOpacity(0.25 + pulse * 0.35),
                                  blurRadius: 10 + pulse * 12,
                                  spreadRadius: 1 + pulse * 3,
                                ),
                              ],
                            ),
                            child: child,
                          );
                        },
                        child: card,
                      );
                    }
                    return card;
                  },
                  childCount: _currentFolder.children.length,
                ),
              ),
            ),

          // Spaziatore tra sottocartelle e post
          if (hasSubfolders && hasPosts)
            const SliverToBoxAdapter(child: SizedBox(height: 32)),

          // Sezione Post
          if (hasPosts)
            SliverPadding(
              padding: EdgeInsets.zero,
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bookmark,
                            color: themeColors.iconColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _currentFolder.isSpecial
                              ? 'Tutti i Post Salvati'
                              : 'Post in questa cartella',
                          style: ThemeHelpers.getSectionTitleStyle(
                              widget.isDarkTheme),
                        ),
                        const Spacer(),
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
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

          if (hasPosts)
            SliverPadding(
              padding: EdgeInsets.zero,
              sliver: MultiSelectPostManager(
                scrollable: false,
                asSliver: true,
                posts: _posts,
                isDarkTheme: widget.isDarkTheme,
                folderService: _folderService,
                onPostsUpdated: () => _loadPosts(),
                childBuilder: (post, isSelected, onTap, onLongPress) {
                  return SelectablePostTile(
                    post: post,
                    isSelected: isSelected,
                    isDarkTheme: widget.isDarkTheme,
                    onTap: onTap,
                    onLongPress: onLongPress,
                    child: _buildPostCard(post, themeColors),
                  );
                },
              ),
            ),

          // Spazio extra in fondo per non finire sotto la bottom nav
          SliverToBoxAdapter(
            child: SizedBox(
              height: 24 + 96 + MediaQuery.of(context).padding.bottom,
            ),
          ),
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
            _currentFolder.isSpecial ? Icons.folder_special : Icons.folder_open,
            color: themeColors.subtitleColor,
            size: 64,
          ),
          SizedBox(height: 16),
          Text(
            _currentFolder.isSpecial ? 'Nessun post salvato' : 'Cartella vuota',
            style: TextStyle(color: themeColors.subtitleColor, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text(
            _currentFolder.isSpecial
                ? 'I post che salvi appariranno qui'
                : _subfolderCreationError == null
                    ? 'Usa il pulsante + per creare sottocartelle'
                    : _subfolderCreationError!,
            style: TextStyle(color: themeColors.subtitleColor, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // MODIFIED: Card post con fix per overflow + highlight animato reminder
  Widget _buildPostCard(MockPost post, ThemeColors themeColors) {
    final highlightPost = _showReminderHighlight &&
        widget.highlightPostId != null &&
        widget.highlightPostId == post.id;

    Widget buildCard({double? pulseValue}) {
      final pulse = pulseValue ?? 0.0;
      final BoxDecoration baseDecoration =
          ThemeHelpers.getCardDecoration(widget.isDarkTheme);
      final BoxDecoration decoration = highlightPost
          ? baseDecoration.copyWith(
              color: Colors.orange.withOpacity(0.18 + pulse * 0.22),
              border: Border.all(
                color: Colors.orange.withOpacity(0.7 + pulse * 0.3),
                width: 2.5 + pulse * 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.25 + pulse * 0.35),
                  blurRadius: 10 + pulse * 12,
                  spreadRadius: 1 + pulse * 3,
                ),
              ],
            )
          : baseDecoration.copyWith(
              color: post.isShared
                  ? (widget.isDarkTheme
                      ? Colors.blue.withOpacity(0.15)
                      : Colors.blue.withOpacity(0.05))
                  : null,
              border: post.isShared
                  ? Border.all(color: Colors.blue.withOpacity(0.5), width: 1.5)
                  : null,
            );
      return Container(
        key: highlightPost ? _highlightedPostKey : null,
        margin: EdgeInsets.only(bottom: 12),
        decoration: decoration,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Immagine
                _buildPostImage(post, themeColors),

                SizedBox(width: 12),

                // Contenuto testuale (occupa tutto lo spazio disponibile)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.title.isNotEmpty ? post.title : post.description,
                        style: TextStyle(
                          color: themeColors.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      SizedBox(height: 8),

                      Text(
                        post.description.isNotEmpty
                            ? post.description
                            : 'Nessuna descrizione disponibile',
                        style: TextStyle(
                          color: themeColors.subtitleColor,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      Spacer(),

                      SizedBox(height: 12),

                      // Data e percorso cartella
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              color: themeColors.hintColor, size: 14),
                          SizedBox(width: 4),
                          Text(
                            _formatDate(post.savedDate),
                            style: TextStyle(
                                color: themeColors.hintColor, fontSize: 12),
                          ),
                          SizedBox(width: 12),
                          Icon(Icons.folder_outlined,
                              color: themeColors.hintColor, size: 14),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _buildPostBreadcrumb(post.sourceFolder),
                              style: TextStyle(
                                  color: themeColors.hintColor, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 6),

                      // Dominio sorgente
                      Row(
                        children: [
                          Icon(Icons.language,
                              color: themeColors.hintColor, size: 14),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _extractDomain(post.url),
                              style: TextStyle(
                                  color: themeColors.hintColor, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      // Badge "post importato"
                      if (post.isShared) ...[
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.blue.shade400, width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.download_rounded,
                                      color: Colors.blue.shade600, size: 11),
                                  SizedBox(width: 4),
                                  Text(
                                    'post importato',
                                    style: TextStyle(
                                      color: Colors.blue.shade600,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                SizedBox(width: 12),

                // Colonna pulsanti destra — distanze uguali tra i tre
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_accessService.canManageManualTags)
                      GestureDetector(
                        onTap: () =>
                            _showEditHashtagsDialog(post, themeColors),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: widget.isDarkTheme
                                ? Colors.grey.shade800
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.blue.withOpacity(0.5), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: Icon(Icons.tag, color: Colors.blue, size: 16),
                        ),
                      ),
                    GestureDetector(
                      onTap: () => _showPostActionsMenu(post, themeColors),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: widget.isDarkTheme
                              ? Colors.grey.shade800
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blue.withOpacity(0.5), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: Offset(0, 2))
                          ],
                        ),
                        child:
                            Icon(Icons.more_vert, color: Colors.blue, size: 16),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _sharePost(post),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: widget.isDarkTheme
                                  ? Colors.white70
                                  : Colors.white,
                              width: 1),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: Offset(0, 1))
                          ],
                        ),
                        child: Icon(Icons.share, color: Colors.white, size: 14),
                      ),
                    ),
                    StreamBuilder(
                      stream:
                          ReminderService.instance.getPostReminders(post.id),
                      builder: (context, snapshot) {
                        final hasReminder =
                            (snapshot.data as List?)?.isNotEmpty == true;
                        return GestureDetector(
                          onTap: () => _showReminderDialog(post),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: hasReminder
                                      ? Colors.green.shade600
                                      : (widget.isDarkTheme
                                          ? Colors.grey.shade800
                                          : Colors.white),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: hasReminder
                                        ? Colors.yellow.shade300
                                        : Colors.orange.withOpacity(0.7),
                                    width: hasReminder ? 2 : 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (hasReminder
                                              ? Colors.green
                                              : Colors.black)
                                          .withOpacity(
                                              hasReminder ? 0.35 : 0.1),
                                      blurRadius: hasReminder ? 8 : 4,
                                      offset: Offset(0, 2),
                                    )
                                  ],
                                ),
                                child: Icon(
                                  hasReminder
                                      ? Icons.notifications_active
                                      : Icons.notifications_none,
                                  color: hasReminder
                                      ? Colors.white
                                      : Colors.orange,
                                  size: 16,
                                ),
                              ),
                              if (hasReminder)
                                Positioned(
                                  right: -3,
                                  top: -3,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.yellow.shade300,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: widget.isDarkTheme
                                            ? Colors.grey.shade900
                                            : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } // end buildCard

    if (highlightPost) {
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, _) => buildCard(pulseValue: _pulseAnim.value),
      );
    }
    return buildCard();
  }

  Future<void> _showReminderDialog(MockPost post) async {
    final canUse = await _accessService.checkFeatureAvailable(
      context,
      'reminders',
      'Reminder',
    );
    if (!canUse || !mounted) return;

    await _accessService.showAdGateForFeature(context, 'reminders');
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => ReminderDialog.forPost(
        postId: post.id,
        postTitle: post.title,
        postUrl: post.url,
        postFolderId: post.sourceFolder?.id ?? _currentFolder.id,
        isDarkTheme: widget.isDarkTheme,
      ),
    );
  }

  // ✅ DIALOG SENZA PULSANTI: Salvataggio immediato e fix overflow
  void _showEditHashtagsDialog(MockPost post, ThemeColors themeColors) {
    if (!_accessService.canManageManualTags) {
      return;
    }

    final TextEditingController hashtagController = TextEditingController();
    List<String> currentTags =
        List.from(post.tags); // Copia modificabile dei tag

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor:
              widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: EdgeInsets.symmetric(
              horizontal: 20, vertical: 40), // Padding dal bordo schermo
          child: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height *
                  0.7, // Max 70% altezza schermo
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // HEADER con X per chiudere
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: widget.isDarkTheme
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tag, color: Colors.blue, size: 24),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Modifica Hashtags',
                          style: TextStyle(
                            color: themeColors.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // X per chiudere
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            color: themeColors.hintColor,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // CONTENUTO scrollabile
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mostra gli hashtag esistenti come chip
                        if (currentTags.isNotEmpty) ...[
                          Row(
                            children: [
                              Text(
                                'Hashtag attuali',
                                style: TextStyle(
                                  color: themeColors.subtitleColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${currentTags.length}',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: currentTags
                                .map((tag) => Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () async {
                                          setDialogState(() {
                                            currentTags.remove(tag);
                                          });
                                          // Salva immediatamente
                                          await _folderService.updatePostTags(
                                              post.id, currentTags);
                                          // Aggiorna UI
                                          if (mounted) {
                                            setState(() {
                                              _loadPosts();
                                            });
                                          }
                                        },
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                color: Colors.blue
                                                    .withOpacity(0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '#$tag',
                                                style: TextStyle(
                                                  color: Colors.blue,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              SizedBox(width: 6),
                                              Icon(
                                                Icons.close,
                                                color: Colors.blue.shade700,
                                                size: 14,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                          SizedBox(height: 20),
                        ] else ...[
                          Container(
                            padding: EdgeInsets.all(12),
                            margin: EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: widget.isDarkTheme
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: themeColors.hintColor,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Nessun hashtag presente',
                                    style: TextStyle(
                                      color: themeColors.hintColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Campo per aggiungere nuovi hashtag
                        Text(
                          'Aggiungi hashtag:',
                          style: TextStyle(
                            color: themeColors.subtitleColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: hashtagController,
                                style: TextStyle(
                                    color: themeColors.textColor, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Nuovo hashtag',
                                  hintStyle: TextStyle(
                                      color: themeColors.hintColor,
                                      fontSize: 14),
                                  filled: true,
                                  fillColor: widget.isDarkTheme
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade100,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: Icon(Icons.tag,
                                      color: Colors.blue, size: 18),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  isDense: true,
                                ),
                                onSubmitted: (value) async {
                                  if (value.trim().isNotEmpty) {
                                    final newTag =
                                        value.replaceAll('#', '').trim();
                                    if (!currentTags.contains(newTag)) {
                                      setDialogState(() {
                                        currentTags.add(newTag);
                                        hashtagController.clear();
                                      });
                                      // Salva immediatamente
                                      await _folderService.updatePostTags(
                                          post.id, currentTags);
                                      // Aggiorna UI
                                      if (mounted) {
                                        setState(() {
                                          _loadPosts();
                                        });
                                      }
                                    }
                                  }
                                },
                              ),
                            ),
                            SizedBox(width: 8),
                            Material(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () async {
                                  final value = hashtagController.text;
                                  if (value.trim().isNotEmpty) {
                                    final newTag =
                                        value.replaceAll('#', '').trim();
                                    if (!currentTags.contains(newTag)) {
                                      setDialogState(() {
                                        currentTags.add(newTag);
                                        hashtagController.clear();
                                      });
                                      // Salva immediatamente
                                      await _folderService.updatePostTags(
                                          post.id, currentTags);
                                      // Aggiorna UI
                                      if (mounted) {
                                        setState(() {
                                          _loadPosts();
                                        });
                                      }
                                    }
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 12),
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  color: Colors.green, size: 14),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Le modifiche vengono salvate automaticamente',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ENHANCED: Widget per immagine del post con Open Graph + fallback
  Widget _buildPostImage(MockPost post, ThemeColors themeColors) {
    final hasPreview = post.imageUrl?.trim().isNotEmpty == true ||
        post.previewStorageUrl?.trim().isNotEmpty == true;

    // Se il post ha un'immagine Open Graph o un backup remoto/cache, usala
    if (hasPreview) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.isDarkTheme
                ? Colors.grey.shade700
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: PostPreviewImage(
            postId: post.id,
            postUrl: post.url,
            imageUrl: post.imageUrl,
            remoteImageUrl: post.previewStorageUrl,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Fallback alla thumbnail generata
    return _buildFallbackThumbnail(post, themeColors);
  }

  // Thumbnail di fallback basata sul dominio (metodo originale)
  Widget _buildFallbackThumbnail(MockPost post, ThemeColors themeColors) {
    String domain = '';
    try {
      final uri = Uri.parse(post.url);
      domain = uri.host.toLowerCase();
    } catch (e) {
      domain = '';
    }

    Color thumbnailColor;
    IconData thumbnailIcon;

    if (domain.contains('youtube.com') || domain.contains('youtu.be')) {
      thumbnailColor = Color(0xFFFF0000);
      thumbnailIcon = Icons.play_circle_filled;
    } else if (domain.contains('github.com')) {
      thumbnailColor = Color(0xFF24292e);
      thumbnailIcon = Icons.code;
    } else if (domain.contains('flutter.dev')) {
      thumbnailColor = Color(0xFF02569B);
      thumbnailIcon = Icons.phone_android;
    } else if (domain.contains('giallozafferano.it')) {
      thumbnailColor = Color(0xFFE17B47);
      thumbnailIcon = Icons.restaurant_menu;
    } else if (domain.contains('cookaround.com')) {
      thumbnailColor = Color(0xFF8B4513);
      thumbnailIcon = Icons.local_dining;
    } else if (domain.contains('donnamoderna.com')) {
      thumbnailColor = Color(0xFFE91E63);
      thumbnailIcon = Icons.menu_book;
    } else if (domain.contains('venetoinfo.it') ||
        domain.contains('veneziaunica.it')) {
      thumbnailColor = Color(0xFF006A94);
      thumbnailIcon = Icons.location_city;
    } else if (domain.contains('veneto.info')) {
      thumbnailColor = Color(0xFF4CAF50);
      thumbnailIcon = Icons.landscape;
    } else if (domain.contains('villepalladiane.it')) {
      thumbnailColor = Color(0xFF8D6E63);
      thumbnailIcon = Icons.account_balance;
    } else {
      thumbnailColor = _getColorFromDomain(domain);
      thumbnailIcon = Icons.language;
    }

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: thumbnailColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              widget.isDarkTheme ? Colors.grey.shade700 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              thumbnailIcon,
              color: _getContrastColor(thumbnailColor),
              size: 32,
            ),
          ),
          if (domain.isNotEmpty && !_isKnownSite(domain))
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade400, width: 0.5),
                ),
                child: Center(
                  child: Text(
                    domain.isNotEmpty ? domain[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubfoldersSection(ThemeColors themeColors) {
    // 🔥 NUOVO: Non mostrare nulla se non ci sono sottocartelle
    if (_currentFolder.children.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: _currentFolder.children.length,
          itemBuilder: (context, index) {
            // 🔥 NUOVO: Ordina alfabeticamente le sottocartelle
            final sortedChildren = _getSortedSubfolders();
            final subfolder = sortedChildren[index];
            return MockFolderCard(
              folder: subfolder,
              onTap: () => _openSubfolder(subfolder),
              onRename: _showRenameSubfolderDialog,
              onDelete: _showDeleteSubfolderDialog,
              onMove: _showMoveSubfolderDialog,
              allFolders: widget.allFolders,
              isDarkTheme: widget.isDarkTheme,
            );
          },
        ),
      ],
    );
  }

  void _openPost(MockPost post) async {
    _folderService.trackPostViewed(post);
    _openPostDirectly(post);
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

  // NUOVO: Estrae il dominio dall'URL
  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      String domain = uri.host.toLowerCase();

      // Rimuovi 'www.' se presente
      if (domain.startsWith('www.')) {
        domain = domain.substring(4);
      }

      return domain;
    } catch (e) {
      print('DEBUG: Errore parsing URL per dominio: $e');
      return 'URL non valido';
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
            // 🔥 FIX: Controlla mounted prima di setState
            if (mounted) {
              setState(() {
                _loadPosts();
              });
            }
            if (mounted) {
              widget.onFolderUpdated();
            }
          },
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    ).then((_) {
      // ✅ Aggiorna solo i dati locali senza pulire la cache
      if (mounted) {
        setState(() {
          _loadPosts();
        });
      }
    });
  }

  // 🔥 CORRETTO: Dialog di creazione sottocartella con async/await
  void _showCreateFolderDialog(ThemeColors themeColors) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Nuova sottocartella',
          style: TextStyle(
              color: themeColors.textColor, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Livello ${_currentFolder.level + 1}',
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
            if (_subfolderCreationError != null) ...[
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
                        _subfolderCreationError!,
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
            child:
                Text('Annulla', style: TextStyle(color: themeColors.hintColor)),
          ),
          TextButton(
            onPressed: _subfolderCreationError == null
                ? () async {
                    // 🔥 AGGIUNTO async
                    if (controller.text.trim().isNotEmpty) {
                      print(
                          'DEBUG: Creando sottocartella "${controller.text.trim()}" in "${_currentFolder.name}"');

                      try {
                        // 🔥 AGGIUNTO await - Ora aspetta che la sottocartella sia salvata
                        await _folderService.createSubfolderInFolder(
                            _currentFolder, controller.text.trim());

                        // ✅ AGGIORNA UI DOPO che la sottocartella è stata salvata
                        _updateCurrentFolder();

                        // 🔥 FIX: Controlla mounted prima di setState
                        if (mounted) {
                          setState(() {
                            _loadPosts();
                          });
                        }

                        if (mounted) {
                          widget.onFolderUpdated();
                        }
                        Navigator.pop(context);
                      } catch (e) {
                        // 🔥 AGGIUNTO gestione errori
                        print('ERRORE: Creazione sottocartella fallita: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceFirst('Exception: ', ''),
                              ),
                              backgroundColor: Colors.orange.shade700,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                        Navigator.pop(context);
                      }
                    }
                  }
                : null,
            child: Text('Crea',
                style: TextStyle(
                    color: _subfolderCreationError == null
                        ? Colors.blue
                        : Colors.grey[600],
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRenameSubfolderDialog(MockFolder subfolder) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    final TextEditingController controller =
        TextEditingController(text: subfolder.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Rinomina sottocartella',
          style: TextStyle(
              color: themeColors.textColor, fontWeight: FontWeight.bold),
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
            child:
                Text('Annulla', style: TextStyle(color: themeColors.hintColor)),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                print(
                    'DEBUG: Rinominando sottocartella da "${subfolder.name}" a "${controller.text.trim()}"');

                Navigator.pop(context); // Chiudi dialog rinomina

                try {
                  // 🔥 FIX: Rimosso loading dialog bloccante per UX istantanea
                  // Esegui operazione asincrona
                  await _folderService.renameFolder(
                      subfolder, controller.text.trim());

                  if (mounted) {
                    setState(() {
                      _loadPosts();
                    });

                    widget.onFolderUpdated();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Cartella rinominata'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Errore: ${e.toString()}'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                }
              }
            },
            child: Text('Salva',
                style:
                    TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
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
        backgroundColor:
            widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Elimina sottocartella',
          style: TextStyle(
              color: themeColors.textColor, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Sei sicuro di voler eliminare la sottocartella "${subfolder.name}"?\n\nTutte le sue sottocartelle e contenuti verranno eliminati.',
          style: TextStyle(color: themeColors.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('Annulla', style: TextStyle(color: themeColors.hintColor)),
          ),
          TextButton(
            onPressed: () async {
              print('DEBUG: Eliminando sottocartella: ${subfolder.name}');

              Navigator.pop(context);

              try {
                // ✅ STEP 1: Elimina dal database
                await _folderService.deleteFolder(subfolder);

                // ✅ STEP 2: Notifica il parent
                if (mounted) {
                  widget.onFolderUpdated();
                }

                // ✅ STEP 3: Forza sincronizzazione completa
                await _folderService.syncWithDataService();

                // ✅ STEP 4: CRITICO - Aggiorna il riferimento locale
                _updateCurrentFolder();

                // ✅ STEP 5: Ricarica i post e forza refresh UI
                if (mounted) {
                  setState(() {
                    _loadPosts();
                  });
                }
              } catch (e) {
                print('ERRORE: Eliminazione sottocartella fallita: $e');
              }
            },
            child: Text('Elimina',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showMoveSubfolderDialog(MockFolder folderToMove) {
    print(
        'DEBUG: FOLDER DETAIL - Avviando spostamento per sottocartella: ${folderToMove.name}');

    DialogHelpers.showMoveFolderDialog(
      context,
      widget.isDarkTheme,
      folderToMove,
      _folderService.folders,
      (destination) async {
        print(
            'DEBUG: FOLDER DETAIL - Destinazione selezionata: ${destination?.name ?? "Home"}');

        try {
          // Attendi completamento operazione (che include salvataggio DB)
          await _folderService.moveFolder(folderToMove, destination);

          if (mounted) {
            setState(() {
              _loadPosts();
            });
            widget.onFolderUpdated();
          }
        } catch (e) {
          print('ERRORE: Spostamento fallito nella pagina dettaglio: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Errore spostamento: $e'),
                  backgroundColor: Colors.red),
            );
          }
        }

        final destinationPath = _buildDestinationPath(destination);
      },
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  String _buildDestinationPath(MockFolder? destination) {
    if (destination == null) {
      return 'Home';
    }

    List<String> path = [];
    MockFolder? current = destination;

    while (current != null) {
      if (!current.isSpecial) {
        path.insert(0, current.name);
      }
      current = current.parent;
    }

    if (path.isEmpty) {
      return 'Home';
    }

    return 'Home > ${path.join(' > ')}';
  }

  Color _getColorFromDomain(String domain) {
    if (domain.isEmpty) return Colors.grey;

    final colors = [
      Colors.blue.shade500,
      Colors.green.shade500,
      Colors.orange.shade500,
      Colors.purple.shade500,
      Colors.red.shade500,
      Colors.teal.shade500,
      Colors.indigo.shade500,
      Colors.pink.shade500,
    ];

    final hash = domain.hashCode;
    return colors[hash.abs() % colors.length];
  }

  Color _getContrastColor(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  bool _isKnownSite(String domain) {
    final knownSites = [
      'youtube.com',
      'youtu.be',
      'github.com',
      'flutter.dev',
      'giallozafferano.it',
      'cookaround.com',
      'donnamoderna.com',
      'venetoinfo.it',
      'veneziaunica.it',
      'veneto.info',
      'villepalladiane.it',
    ];

    return knownSites.any((site) => domain.contains(site));
  }

  void _showPostActionsMenu(MockPost post, ThemeColors themeColors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: widget.isDarkTheme
                        ? Colors.grey.shade700
                        : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.article, color: Colors.blue, size: 16),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.title,
                          style: TextStyle(
                            color: themeColors.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          _buildPostBreadcrumb(post.sourceFolder),
                          style: TextStyle(
                            color: themeColors.hintColor,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            _buildActionOption(
              Icons.drive_file_move_outline,
              'Sposta Post',
              Colors.blue,
              () {
                Navigator.pop(context);
                _showMovePostDialog(post, themeColors);
              },
            ),

            _buildActionOption(
              Icons.share,
              'Condividi Post',
              Colors.green,
              () {
                Navigator.pop(context);
                _sharePost(post);
              },
            ),

            _buildActionOption(
              Icons.delete_outline,
              'Elimina Post',
              Colors.red,
              () {
                Navigator.pop(context);
                _showDeletePostDialog(post, themeColors);
              },
            ),

            _buildActionOption(
              Icons.launch,
              'Apri Link',
              Colors.purple,
              () {
                Navigator.pop(context);
                _openPost(post);
              },
            ),

            SizedBox(height: 16),

            // 🔥 FIX: Aggiungi padding extra per evitare sovrapposizione con navigazione
            SizedBox(
                height: MediaQuery.of(context).padding.bottom > 0 ? 8 : 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionOption(
      IconData icon, String title, Color color, VoidCallback onTap) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: themeColors.textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  void _showMovePostDialog(MockPost post, ThemeColors themeColors) {
    print('DEBUG: Avviando spostamento per post: ${post.title}');

    DialogHelpers.showMovePostDialog(
      context,
      widget.isDarkTheme,
      post,
      _folderService.folders,
      (destination) async {
        print(
            'DEBUG: Destinazione selezionata per post: ${destination?.name ?? "Tutti"}');

        // Sposta il post
        await _folderService.movePost(post, destination);

        // Aggiorna localmente subito, la sync globale avverrà in background
        if (mounted) {
          setState(() {
            _loadPosts();
          });
        }

        if (mounted) {
          widget.onFolderUpdated();
        }

        final destinationPath =
            destination != null ? _buildDestinationPath(destination) : 'Tutti';
      },
    );
  }

  // 🔥🔥🔥 FIX PRINCIPALE: ELIMINAZIONE POST CON AWAIT E MESSAGGIO MIGLIORATO 🔥🔥🔥
  void _showDeletePostDialog(MockPost post, ThemeColors themeColors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Elimina Post',
          style: TextStyle(
              color: themeColors.textColor, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sei sicuro di voler eliminare questo post? Questa azione non può essere annullata.',
              style: TextStyle(color: themeColors.subtitleColor),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.article, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      post.title,
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
            child:
                Text('Annulla', style: TextStyle(color: themeColors.hintColor)),
          ),
          TextButton(
            onPressed: () async {
              // 🔥 AGGIUNTO async
              print('DEBUG: Eliminando post: ${post.title}');

              try {
                // 🔥 FIX CRITICO: Await dell'eliminazione persistente
                await _folderService.deletePost(post.id);

                Navigator.pop(context);

                // 🔥 FIX MESSAGGIO: Limita lunghezza titolo e mostra messaggio pulito
                String displayTitle = post.title;
                if (displayTitle.length > 30) {
                  displayTitle = '${displayTitle.substring(0, 30)}...';
                }

                // 🔥 FIX: Controlla mounted prima di setState
                if (mounted) {
                  setState(() {
                    _loadPosts();
                  });
                }

                if (mounted) {
                  widget.onFolderUpdated();
                }
              } catch (e) {
                // 🔥 GESTIONE ERRORI: Mostra errore se eliminazione fallisce
                print('ERRORE: Eliminazione post fallita: $e');

                Navigator.pop(context);
              }
            },
            child: Text('Elimina',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _sharePost(MockPost post) {
    DialogHelpers.showShareItemDialog(
      context,
      widget.isDarkTheme,
      'post',
      post.title,
      (email) async {
        final realPosts = await DataService.instance.getPosts();
        final postToShare = realPosts.firstWhere((p) => p.id == post.id);
        await DataService.instance.sharePost(postToShare, email);
      },
      canStartShare: () async {
        return AppAccessService().checkFeatureAvailable(
          context,
          'share_post',
          'Condivisione Post',
        );
      },
      systemShareContentBuilder: () async {
        final realPosts = await DataService.instance.getPosts();
        final postToShare = realPosts.firstWhere((p) => p.id == post.id);
        final link =
            await ShareLinkService.instance.createPostShareLink(postToShare);
        return 'C’è un contenuto SaveIn che ti aspetta: ${post.title}\n\n'
            '$link\n\n'
            'Aprilo con SaveIn per salvarlo e ritrovarlo quando vuoi.';
      },
      previewImageUrl: post.previewStorageUrl ?? post.imageUrl,
    );
  }
}

// 🆕 NUOVO: La gestione dell'apertura post è ora integrata nel MultiSelectPostManager
// La vecchia classe PostTileWithRealOpening è stata sostituita dal sistema di selezione multipla
