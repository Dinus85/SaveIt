// File: lib/services/folder_service.dart
// Entry point principale per FolderService
// Combina tutti i mixin in una classe unica

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savein/models/folder.dart';
import 'package:savein/models.dart';
import 'package:savein/utils/constants.dart';
import 'package:savein/pages/simple_stats_page.dart';
import 'package:savein/data_service.dart' show DataService;
import 'package:savein/services/auth_service.dart';
import 'package:savein/advanced_analytics_models.dart';

// Import dei moduli
import 'package:savein/services/folder_service_models.dart';
import 'package:savein/services/folder_service_base.dart';
import 'package:savein/services/folder_service_sync.dart';
import 'package:savein/services/folder_service_crud.dart';
import 'package:savein/services/folder_service_search.dart';
import 'package:savein/services/folder_service_analytics.dart';
import 'package:savein/services/folder_service_sharing.dart';

// ⭐ NUOVO: Import sistema unificato
import 'package:savein/services/folder_management_unified.dart';

// Export per rendere i tipi accessibili a chi importa FolderService
export 'package:savein/services/folder_service_models.dart';
export 'package:savein/models.dart' show MockPost, MockFolder;

/// FolderService - Servizio principale per gestione cartelle e post
/// Combina tutti i mixin per fornire funzionalità complete
class FolderService extends FolderServiceBase
    with
        FolderServiceSync,
        FolderServiceCRUD,
        FolderServiceSearch,
        FolderServiceAnalytics,
        FolderServiceSharing {
  // ============================================================================
  // SINGLETON PATTERN
  // ============================================================================

  static FolderService? _instance;
  bool _isLoadingPostsInBackground = false;

  factory FolderService() {
    _instance ??= FolderService._internal();
    return _instance!;
  }

  FolderService._internal() {
    initializeStreamControllers();
    setupAuthenticationListener();
  }

  static void destroyInstance() {
    print('DEBUG: DISTRUGGENDO SINGLETON FolderService');
    _instance?.cleanup();
    _instance = null;
  }

  // ============================================================================
  // INIZIALIZZAZIONE PRINCIPALE
  // ============================================================================

  Future<void> initializeFolders() async {
    final startTime = DateTime.now();
    startActionTiming('initialization');

    print('DEBUG: ========== INIZIALIZZAZIONE FASE 6 CON CACHE FIX ==========');
    updateHealthStatus(ServiceHealthStatus.authenticating);

    final shouldClearCache = await _shouldClearCache();
    if (shouldClearCache) {
      print('DEBUG: Cache inconsistente, pulendo...');
      await clearAllCache();
    }

    if (isInitialized) {
      print('DEBUG: Già inizializzato, ricaricando...');

      if (currentUserId != null && loadFromCache(currentUserId!)) {
        // 🔥 FIX: Double-check che la gerarchia sia valida prima di notificare l'UI
        print(
            'DEBUG: Cache caricata, verifica finale prima di mostrare all\'utente...');

        // Verifica che folders contenga solo cartelle level 0
        final invalidFolders = folders
            .where((f) => !f.isSpecial && (f.level != 0 || f.parent != null))
            .toList();
        if (invalidFolders.isNotEmpty) {
          print(
              'DEBUG: ⚠️ ATTENZIONE: Trovate ${invalidFolders.length} cartelle non-root nella lista principale!');
          for (var folder in invalidFolders) {
            print(
                'DEBUG:   - "${folder.name}" (level: ${folder.level}, hasParent: ${folder.parent != null})');
          }
          print('DEBUG: 🔄 Forzando reload completo...');
          folders.clear();
          allPosts.clear();
          await _loadPersistedData();
          return;
        }

        notifyDataChanged();
        updateHealthStatus(ServiceHealthStatus.healthy);
        return;
      }

      await _loadPersistedData();

      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.actionPerformed,
        properties: {
          'action': 'service_reinitialized',
          'reason': 'already_initialized',
        },
      );
      return;
    }

    print('DEBUG: Prima inizializzazione...');

    try {
      await advancedAnalytics.initialize();
    } catch (e) {
      print('ERRORE: Inizializzazione analytics fallita: $e');
    }

    try {
      await executeAuthenticatedOperation(() async {
        folders = [
          MockFolder(
              name: 'Tutti',
              count: '0 Post',
              color: Colors.purple.shade200,
              level: 0,
              isSpecial: true),
        ];

        await _loadPersistedData();
        updateTuttiCount();
      }, 'initialization');

      isInitialized = true;

      if (currentUserId != null) {
        cacheUserData(currentUserId!);
      }

      final duration = endActionTiming('initialization');
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.actionPerformed,
        properties: {
          'action': 'service_initialized',
          'folders_count': folders.length,
          'posts_count': allPosts.length,
          'initialization_time_ms': duration?.inMilliseconds,
        },
        actionDuration: duration,
      );

      await calculateOrganizationalMetrics();

      notifyDataChanged();
      updateHealthStatus(ServiceHealthStatus.healthy);

      print(
          'DEBUG: FolderService inizializzato con ${folders.length} cartelle');
    } catch (e) {
      print('ERRORE: Inizializzazione fallita: $e');
      updateHealthStatus(ServiceHealthStatus.error,
          errorMessage: 'Init failed: $e');

      await _createEmergencyFallback();
      throw e;
    }
  }

  // ============================================================================
  // CARICAMENTO DATI
  // ============================================================================

  @override
  Future<void> loadUserSpecificData() async {
    if (currentUserId == null) return;

    if (loadFromCache(currentUserId!)) {
      // 🔥 FIX: Double-check gerarchia prima di notificare l'UI
      final invalidFolders = folders
          .where((f) => !f.isSpecial && (f.level != 0 || f.parent != null))
          .toList();
      if (invalidFolders.isNotEmpty) {
        print(
            'DEBUG: ⚠️ Cache corrotta in loadUserSpecificData, forzando reload...');
        folders.clear();
        allPosts.clear();
        await _loadPersistedData();
        cacheUserData(currentUserId!);
        notifyDataChanged();
        return;
      }

      notifyDataChanged();
      return;
    }

    await _loadPersistedData();
    cacheUserData(currentUserId!);
    notifyDataChanged();
  }

  Future<void> _loadPersistedData() async {
    startActionTiming('load_data');

    try {
      await executeAuthenticatedOperation(() async {
        List<Folder> realFolders = [];
        try {
          realFolders = await DataService.instance.getFolders();
        } catch (foldersError) {
          print(
              'DEBUG: Caricamento cartelle da DataService fallito: $foldersError');
          await DataService.instance.initializeDefaultData();
          realFolders =
              await DataService.instance.getFolders(forceRefresh: true);
        }

        if (!realFolders.any((f) => f.isDefault)) {
          realFolders.add(Folder(
            id: 'tutti_emergency_${DateTime.now().millisecondsSinceEpoch}',
            name: 'Tutti',
            color: '#BB86FC',
            createdAt: DateTime.now(),
            isDefault: true,
          ));
        }

        // FIX: Usa il nome corretto del metodo
        await syncFoldersFromDataServiceWithParentId(realFolders);

        if (folders.isEmpty) {
          throw Exception('Nessuna cartella dopo sincronizzazione');
        }

        if (!folders.any((f) => f.isSpecial)) {
          throw Exception('Cartella Tutti mancante');
        }

        _loadPostsInBackground(realFolders);
      }, 'load_persisted_data');

      updateTuttiCount();

      if (currentUserId != null) {
        cacheUserData(currentUserId!);
      }
      notifyDataChanged();

      final duration = endActionTiming('load_data');
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.actionPerformed,
        properties: {
          'action': 'data_loaded',
          'folders_loaded': folders.length,
          'posts_loaded': allPosts.length,
          'load_time_ms': duration?.inMilliseconds,
        },
        actionDuration: duration,
      );
    } catch (e, stackTrace) {
      print('ERRORE: Caricamento fallito: $e');
      print('STACK: $stackTrace');

      updateHealthStatus(ServiceHealthStatus.error,
          errorMessage: 'Load failed: $e');

      if (folders.isEmpty) {
        folders = [
          MockFolder(
            name: 'Tutti',
            count: '${allPosts.length} Post',
            color: Colors.purple.shade200,
            level: 0,
            isSpecial: true,
          ),
        ];
        notifyDataChanged();
        _retryLoadFoldersInBackground();
      }

      rethrow;
    }
  }

  Future<List<Folder>> _loadFoldersDirectFromFirestore() async {
    print('DEBUG: Caricamento diretto da Firestore...');

    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw Exception('Firebase user è null');
    }

    final firestore = FirebaseFirestore.instance;
    final foldersCollection = firestore
        .collection('users')
        .doc(firebaseUser.uid)
        .collection('folders');

    final snapshot = await foldersCollection.get();
    print('DEBUG: Ricevuti ${snapshot.docs.length} documenti');

    final folders = <Folder>[];

    for (var doc in snapshot.docs) {
      try {
        final data = doc.data();

        final folder = Folder(
          id: doc.id,
          name: data['name'] ?? 'Unnamed',
          color: data['color'] ?? '#BB86FC',
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
          isDefault: data['isDefault'] ?? false,
          parentId: data['parentId'] as String?,
          isShared: data['isShared'] ?? false,
        );

        folders.add(folder);
      } catch (e) {
        print('DEBUG: Errore documento ${doc.id}: $e');
      }
    }

    return folders;
  }

  void _retryLoadFoldersInBackground() {
    Timer(Duration(seconds: 5), () async {
      try {
        final realFolders = await _loadFoldersDirectFromFirestore();

        if (realFolders.length > 1) {
          await syncFoldersFromDataServiceWithParentId(realFolders);
          notifyDataChanged();
          updateHealthStatus(ServiceHealthStatus.healthy);
        }
      } catch (e) {
        Timer(Duration(seconds: 10), () => _retryLoadFoldersInBackground());
      }
    });
  }

  Future<void> _createEmergencyFallback() async {
    try {
      folders = [
        MockFolder(
          name: 'Tutti',
          count: '${allPosts.length} Post',
          color: Colors.purple.shade200,
          level: 0,
          isSpecial: true,
        ),
      ];

      updateHealthStatus(ServiceHealthStatus.degraded,
          errorMessage: 'Running in emergency mode');

      notifyDataChanged();
      _retryLoadFoldersInBackground();
    } catch (e) {
      print('ERRORE: Anche fallback è fallito: $e');
    }
  }

  Future<bool> _shouldClearCache() async {
    // Evita letture Firestore preventive all'avvio. Eventuali inconsistenze
    // vengono gestite dal normale caricamento/sync senza bloccare la prima UI.
    return false;
  }

  // ============================================================================
  // CALLBACK OTTIMISTICI
  // ============================================================================

  @override
  void handleDataServiceCallback(
      String changeType, Map<String, dynamic> changeData) {
    print('DEBUG: 📢 Callback ricevuto: $changeType');

    switch (changeType) {
      case 'post_added':
        _handlePostAddedOptimistically(changeData);
        break;
      case 'post_removed':
        _handlePostRemovedOptimistically(changeData);
        break;
      case 'folder_added':
        _handleFolderAddedOptimistically(changeData);
        break;
      case 'folder_deleted':
        _handleFolderDeletedOptimistically(changeData);
        break;
      case 'cache_invalidated':
        _handleCacheInvalidatedOptimistically(changeData);
        break;
      case 'cache_reloaded':
      case 'user_logged_in':
      case 'data_cleared':
        _handleDataStructureChangedOptimistically(changeData);
        break;
      default:
        _handleGenericDataChangeOptimistically(changeData);
    }
  }

  void _handlePostAddedOptimistically(Map<String, dynamic> data) {
    print('DEBUG: 📝 Gestendo aggiunta post ottimistica');
    _refreshFolderCountsOptimistically();
    notifyUICallbacks();
    _backgroundSyncAfterChange('post_added');
  }

  void _handlePostRemovedOptimistically(Map<String, dynamic> data) {
    print('DEBUG: 🗑️ Gestendo rimozione post ottimistica');
    _refreshFolderCountsOptimistically();
    notifyUICallbacks();
    _backgroundSyncAfterChange('post_removed');
  }

  void _handleFolderAddedOptimistically(Map<String, dynamic> data) {
    print('DEBUG: 📁 Gestendo aggiunta cartella ottimistica');
    _backgroundSyncAfterChange('folder_added');
    notifyUICallbacks();
  }

  void _handleFolderDeletedOptimistically(Map<String, dynamic> data) {
    print('DEBUG: 🗂️ Gestendo eliminazione cartella');
    _backgroundSyncAfterChange('folder_deleted');
    notifyUICallbacks();
  }

  void _handleCacheInvalidatedOptimistically(Map<String, dynamic> data) {
    print('DEBUG: 🔄 Gestendo invalidazione cache');
    _backgroundSyncAfterChange('cache_invalidated');
  }

  void _handleDataStructureChangedOptimistically(Map<String, dynamic> data) {
    print('DEBUG: 🔄 Gestendo cambiamento strutturale');

    Future.microtask(() async {
      try {
        await initializeFolders();
        notifyUICallbacks();
      } catch (e) {
        print('DEBUG: Errore reinizializzazione: $e');
      }
    });
  }

  void _handleGenericDataChangeOptimistically(Map<String, dynamic> data) {
    print('DEBUG: ⚡ Gestendo cambiamento generico');
    _refreshFolderCountsOptimistically();
    notifyUICallbacks();
  }

  void _refreshFolderCountsOptimistically() {
    try {
      updateTuttiCount();
      updateAllFolderCounts();

      if (currentUserId != null) {
        cacheUserData(currentUserId!);
      }

      notifyDataChanged();
    } catch (e) {
      print('DEBUG: Errore refresh ottimistico: $e');
    }
  }

  void _backgroundSyncAfterChange(String changeType) {
    Future.microtask(() async {
      try {
        await Future.delayed(Duration(milliseconds: 500));
        await syncWithDataService();
      } catch (e) {
        updateHealthStatus(ServiceHealthStatus.degraded,
            errorMessage: 'Background sync failed: $e');
      }
    });
  }

  // ============================================================================
  // METODI PUBBLICI AGGIUNTIVI
  // ============================================================================

  void setOnDataChangedCallback(VoidCallback? callback) {
    if (callback != null) {
      registerUIUpdateCallback(callback);
    }
  }

  void triggerOptimisticUpdate() {
    _refreshFolderCountsOptimistically();
    notifyUICallbacks();
  }

  Map<String, dynamic> getCallbackSystemStatus() {
    return {
      'dataservice_callback_registered': isDataServiceCallbackRegistered,
      'ui_callbacks_count': uiUpdateCallbacks.length,
      'health_status': currentHealth.status.toString(),
      'current_user': currentUserId,
      'folders_count': folders.length,
      'posts_count': allPosts.length,
    };
  }

  Future<void> handleAppResumed() async {
    try {
      final isConsistent = await _quickConsistencyCheck();

      if (!isConsistent) {
        await clearAllCache();
        await forceReloadFromDatabase();
        notifyDataChanged();
      } else {
        await _refreshDataFromDatabase();
      }
    } catch (e) {
      print('DEBUG: Errore gestendo resume: $e');
    }
  }

  Future<void> handleAppPaused() async {
    try {
      if (currentUserId != null) {
        cacheUserData(currentUserId!);
      }
      await _flushCache();
    } catch (e) {
      print('DEBUG: Errore salvando stato: $e');
    }
  }

  Future<bool> _quickConsistencyCheck() async {
    try {
      if (folders.isEmpty || folders.length == 1) return false;

      try {
        final folders = await DataService.instance.getFolders();
        return folders.length > 1;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<void> _refreshDataFromDatabase() async {
    try {
      final currentFolderCount = folders.length;

      try {
        final realFolders = await _loadFoldersDirectFromFirestore();

        if (realFolders.length != currentFolderCount) {
          await syncFoldersFromDataServiceWithParentId(realFolders);
          notifyDataChanged();
        }
      } catch (e) {
        print('DEBUG: Refresh fallito: $e');
      }
    } catch (e) {
      print('DEBUG: Errore refresh: $e');
    }
  }

  Future<void> _flushCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
    } catch (e) {
      print('DEBUG: Errore flush cache: $e');
    }
  }

  // ============================================================================
  // METODI DIAGNOSTICI
  // ============================================================================

  Future<void> forceRefreshFromDataService() async {
    await syncWithDataService();
  }

  Future<void> initializeHybridData() async {
    // Carica prima cartelle (UI rapida), post in background.
    await syncStartupWithDataService();
  }

  Future<void> debugCompareData() async {
    print('=== Debug: Comparing Data ===');
    try {
      final realFolders = await DataService.instance.getFolders();
      final realPosts = await DataService.instance.getPosts();

      print('Real folders: ${realFolders.length}');
      print('Mock folders: ${folders.length}');
      print('Real posts: ${realPosts.length}');
      print('Mock posts: ${allPosts.length}');
    } catch (e) {
      print('Error comparing data: $e');
    }
  }

  void testImagePreviewFunctionality() {
    print('=== Testing Image Preview ===');
    for (var folder in folders) {
      final images = getLastPostImagesForFolder(folder);
      print('${folder.name}: ${images.length} images');
    }
  }

  Map<String, List<String>> getAllFoldersImagePreview() {
    final result = <String, List<String>>{};
    for (var folder in folders) {
      result[folder.name] = getLastPostImagesForFolder(folder);
    }
    return result;
  }

  MockPost? getLastPostInFolderRecursive(MockFolder folder) {
    final allPostsInFolder = getAllPostsInFolderRecursive(folder);
    return allPostsInFolder.isNotEmpty ? allPostsInFolder.first : null;
  }

  // Alias per compatibilità con sharing_service
  Future<void> createSubfolder(String parentPath, String folderName) async {
    final parentFolder = findFolderByPath(parentPath);
    if (parentFolder != null) {
      await createSubfolderInFolder(parentFolder, folderName);
    } else {
      await createPersistentFolder(folderName);
    }
  }

  void debugPrintStructure() {
    print('\n=== STRUTTURA CARTELLE ===');
    print('Cartelle root: ${folders.length}');
    for (var folder in folders) {
      _printFolder(folder, 0);
    }
    print('==========================\n');
  }

  void _printFolder(MockFolder folder, int indent) {
    final indentStr = '  ' * indent;
    print('$indentStr- ${folder.name} (livello ${folder.level})');
    for (var child in folder.children) {
      _printFolder(child, indent + 1);
    }
  }

  // ============================================================================
  // ⭐ NUOVO: METODI HELPER PER UNIFIED MANAGER
  // ============================================================================
  // Questi metodi usano il nuovo sistema unificato sotto il cofano
  // mantenendo compatibilità con il codice esistente
  // ============================================================================

  /// Crea gerarchia completa da path usando il nuovo sistema unificato
  /// Esempio: "Tech › Flutter › Tips" crea tutti i livelli se non esistono
  Future<String> createHierarchyFromPathUnified(String fullPath) async {
    return await FolderHierarchyManager.createHierarchyFromPath(fullPath);
  }

  /// Ottieni statistiche anteprima usando il nuovo sistema
  FolderPreviewStats getFolderPreviewStatsUnified(MockFolder folder) {
    return FolderPreviewManager.getFolderPreviewImages(folder, allPosts,
        maxImages: 4);
  }

  /// Sincronizza cartelle usando il nuovo sistema (utility per debug)
  Future<List<MockFolder>> syncFoldersUnified(List<Folder> dbFolders) async {
    return await FolderSynchronizationManager.syncFoldersFromDatabase(
        dbFolders);
  }

  /// Sincronizza post usando il nuovo sistema (utility per debug)
  Future<List<MockPost>> syncPostsUnified(
    List<SavedPost> dbPosts,
    List<Folder> dbFolders,
    List<MockFolder> uiFolders,
  ) async {
    return await PostManagement.syncPostsFromDatabase(
      dbPosts,
      dbFolders,
      uiFolders,
    );
  }

  /// Trova Folder database da MockFolder usando nuovo sistema
  Folder? findDatabaseFolderUnified(
      List<Folder> dbFolders, MockFolder mockFolder) {
    return FolderSynchronizationManager.findDatabaseFolderFromMock(
        dbFolders, mockFolder);
  }

  // ============================================================================

  void _loadPostsInBackground(List<Folder> realFolders) {
    if (_isLoadingPostsInBackground) return;
    _isLoadingPostsInBackground = true;

    Future.microtask(() async {
      try {
        final realPosts = await getPostsWithRetry();
        print('DEBUG: Caricati ${realPosts.length} post');

        await syncPostsFromDataService(realPosts, realFolders);
        updateTuttiCount();

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }

        notifyDataChanged();

        advancedAnalytics.trackAdvancedEvent(
          AdvancedEventType.actionPerformed,
          properties: {
            'action': 'posts_loaded_background',
            'posts_loaded': allPosts.length,
            'folders_loaded': folders.length,
          },
        );
      } catch (e) {
        print('ERRORE: Caricamento post in background fallito: $e');
        updateHealthStatus(
          ServiceHealthStatus.degraded,
          errorMessage: 'Background posts load failed: $e',
        );
      } finally {
        _isLoadingPostsInBackground = false;
      }
    });
  }

  Future<void> dispose() async {
    print('DEBUG: Chiudendo FolderService...');

    try {
      await advancedAnalytics.endSmartSession();
      cleanup();
    } catch (e) {
      print('ERRORE: Dispose fallito: $e');
    }
  }
}
