// File: lib/services/folder_service_sync.dart
// Sincronizzazione con supporto parentId (NON nomi concatenati)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savein/models/folder.dart';
import 'package:savein/models.dart';
import 'package:savein/data_service.dart';
import '../advanced_analytics_models.dart';

import 'folder_service_models.dart';
import 'folder_service_base.dart';
import 'auth_service.dart';

/// Mixin per sincronizzazione con supporto parentId
mixin FolderServiceSync on FolderServiceBase {
  // ============================================================================
  // SINCRONIZZAZIONE PRINCIPALE
  // ============================================================================

  Future<void> syncWithDataService() async {
    if (kDebugMode)
      print('DEBUG: ========== SINCRONIZZAZIONE CON PARENTID ==========');

    await _syncAuthFromAuthServiceIfNeeded();

    startActionTiming('sync_data');
    updateHealthStatus(ServiceHealthStatus.authenticating);

    try {
      await executeAuthenticatedOperation(() async {
        final realPosts = await getPostsWithRetry();
        if (kDebugMode) print('DEBUG: getPostsWithRetry returned ${realPosts.length}');
        final realFolders = await DataService.instance.getFolders();
        if (kDebugMode) print('DEBUG: getFolders returned ${realFolders.length}');

        if (kDebugMode)
          print(
              'DEBUG: Database -> ${realFolders.length} cartelle, ${realPosts.length} post');

        // NUOVO: Sincronizza usando parentId
        await syncFoldersFromDataServiceWithParentId(realFolders);
        await syncPostsFromDataService(realPosts, realFolders);

        updateTuttiCount();

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }
        notifyDataChanged();
        updateHealthStatus(ServiceHealthStatus.healthy);

        return true;
      }, 'sync_with_dataservice');

      final duration = endActionTiming('sync_data');
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.actionPerformed,
        properties: {
          'action': 'data_synchronized',
          'folders_synced': folders.length,
          'posts_synced': allPosts.length,
          'sync_time_ms': duration?.inMilliseconds,
          'user_id': currentUserId,
          'using_parent_id': true,
        },
        actionDuration: duration,
      );

      if (kDebugMode) print('DEBUG: Sincronizzazione completata con parentId');
    } catch (e) {
      if (kDebugMode) print('ERRORE: Sincronizzazione fallita: $e');
      updateHealthStatus(ServiceHealthStatus.error,
          errorMessage: 'Sync failed: $e');
      throw e;
    }
  }

  Future<void> _syncAuthFromAuthServiceIfNeeded() async {
    if (isAuthenticated && currentUserId != null) return;

    final authService = AuthService();
    final user = authService.currentUser;
    if (user != null) {
      isAuthenticated = true;
      currentUserId = user.id;
      if (kDebugMode) {
        print('DEBUG: Auth sincronizzata da AuthService (userId: ${user.id})');
      }
      return;
    }

    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      isAuthenticated = true;
      currentUserId = firebaseUser.uid;
      if (kDebugMode) {
        print(
            'DEBUG: Auth sincronizzata da FirebaseAuth (userId: ${firebaseUser.uid})');
      }
    }
  }

  Future<void> syncStartupWithDataService() async {
    if (kDebugMode) {
      print('DEBUG: ========== SINCRONIZZAZIONE STARTUP LEGGERA ==========');
    }

    await _syncAuthFromAuthServiceIfNeeded();

    startActionTiming('startup_sync_data');
    updateHealthStatus(ServiceHealthStatus.authenticating);

    try {
      await executeAuthenticatedOperation(() async {
        final realFolders = await DataService.instance.getFolders();

        await syncFoldersFromDataServiceWithParentId(realFolders);
        updateTuttiCount();

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }
        notifyDataChanged();
        updateHealthStatus(ServiceHealthStatus.healthy);

        unawaited(_loadStartupPostsInBackground(realFolders));
        return true;
      }, 'startup_sync_with_dataservice');

      final duration = endActionTiming('startup_sync_data');
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.actionPerformed,
        properties: {
          'action': 'startup_folders_synchronized',
          'folders_synced': folders.length,
          'sync_time_ms': duration?.inMilliseconds,
          'user_id': currentUserId,
          'using_parent_id': true,
        },
        actionDuration: duration,
      );

      if (kDebugMode) print('DEBUG: Startup folders sincronizzate');
    } catch (e) {
      if (kDebugMode) print('ERRORE: Startup sync fallita: $e');
      updateHealthStatus(ServiceHealthStatus.error,
          errorMessage: 'Startup sync failed: $e');
      rethrow;
    }
  }

  Future<void> _loadStartupPostsInBackground(List<Folder> realFolders) async {
    try {
      final realPosts = await getPostsWithRetry();
      await syncPostsFromDataService(realPosts, realFolders);
      updateTuttiCount();

      if (currentUserId != null) {
        cacheUserData(currentUserId!);
      }
      notifyDataChanged();
      updateHealthStatus(ServiceHealthStatus.healthy);

      if (kDebugMode) {
        print(
            'DEBUG: Startup posts caricati in background: ${realPosts.length}');
      }
    } catch (e) {
      if (kDebugMode) print('DEBUG: Caricamento post background fallito: $e');
      updateHealthStatus(ServiceHealthStatus.degraded,
          errorMessage: 'Posts background load failed: $e');
    }
  }

  // ============================================================================
  // SINCRONIZZAZIONE CARTELLE CON PARENTID
  // ============================================================================

  Future<void> syncFoldersFromDataServiceWithParentId(
      List<Folder> realFolders) async {
    if (kDebugMode)
      print(
          'DEBUG: ========== SINCRONIZZAZIONE CARTELLE CON PARENTID ==========');

    // Trova cartella "Tutti"
    final defaultFolder = realFolders.firstWhere(
      (f) => f.isDefault,
      orElse: () => Folder(
        id: 'tutti_fallback',
        name: 'Tutti',
        color: '#BB86FC',
        createdAt: DateTime.now(),
        isDefault: true,
      ),
    );

    final tuttiFolder = MockFolder(
      name: defaultFolder.name,
      count: '0 Post',
      color: hexToColor(defaultFolder.color),
      level: 0,
      isSpecial: true,
    );

    // Reset struttura
    folders.clear();
    folders.add(tuttiFolder);

    // Map per tracciare Folder -> MockFolder
    final Map<String, MockFolder> folderIdToMockFolder = {};

    // PASSO 1: Crea tutte le cartelle root (parentId == null)
    final rootFolders =
        realFolders.where((f) => !f.isDefault && f.parentId == null).toList();

    if (kDebugMode) print('DEBUG: Trovate ${rootFolders.length} cartelle root');

    for (var realFolder in rootFolders) {
      final mockFolder = MockFolder(
        id: realFolder.id, // 🆕 Assegna ID reale
        name: realFolder.name,
        count: 'Caricando...',
        color: hexToColor(realFolder.color),
        level: 0,
        isSpecial: false,
        parent: null,
        children: [],
        isShared: realFolder.isShared, // 🆕 NUOVO
      );

      folders.add(mockFolder);
      folderIdToMockFolder[realFolder.id] = mockFolder;

      if (kDebugMode)
        print(
            'DEBUG: Root folder creata: ${realFolder.name} (ID: ${realFolder.id})');
    }

    // PASSO 2: Crea le sottocartelle in ordine di profondità
    // Ordina per garantire che i parent siano creati prima dei children
    final childFolders =
        realFolders.where((f) => !f.isDefault && f.parentId != null).toList();

    if (kDebugMode)
      print('DEBUG: Trovate ${childFolders.length} sottocartelle');

    // Continua fino a che tutte le sottocartelle sono create
    int maxIterations = 15; // Aumentato limite profondità
    int iteration = 0;
    Set<String> createdIds = folderIdToMockFolder.keys.toSet();

    while (createdIds.length < realFolders.where((f) => !f.isDefault).length &&
        iteration < maxIterations) {
      iteration++;
      int createdThisRound = 0;

      for (var realFolder in childFolders) {
        // Salta se già creata
        if (createdIds.contains(realFolder.id)) continue;

        // Se il parentId non esiste proprio tra le cartelle reali, la mettiamo in root per non perderla
        final parentExistsInReal =
            realFolders.any((f) => f.id == realFolder.parentId);
        if (!parentExistsInReal) {
          if (kDebugMode)
            print(
                'WARNING: ⚠️ Cartella ${realFolder.name} ha un parentId inesistente (${realFolder.parentId}). Spostata in root.');
          final mockFolder = MockFolder(
            id: realFolder.id,
            name: realFolder.name,
            count: 'Vuota',
            color: hexToColor(realFolder.color),
            level: 0,
            isSpecial: false,
            parent: null,
            children: [],
            isShared: realFolder.isShared,
          );
          folders.add(mockFolder);
          folderIdToMockFolder[realFolder.id] = mockFolder;
          createdIds.add(realFolder.id);
          createdThisRound++;
          continue;
        }

        // Salta se parent non ancora creato in questo round
        if (!createdIds.contains(realFolder.parentId!)) continue;

        final parentMock = folderIdToMockFolder[realFolder.parentId!];
        if (parentMock == null) continue;

        final mockFolder = MockFolder(
          id: realFolder.id,
          name: realFolder.name,
          count: 'Vuota',
          color: hexToColor(realFolder.color),
          level: parentMock.level + 1,
          isSpecial: false,
          parent: parentMock,
          children: [],
          isShared: realFolder.isShared,
        );

        parentMock.children.add(mockFolder);
        folderIdToMockFolder[realFolder.id] = mockFolder;
        createdIds.add(realFolder.id);
        createdThisRound++;

        if (kDebugMode)
          print(
              'DEBUG: Child folder creata: ${realFolder.name} sotto ${parentMock.name}');
      }

      if (createdThisRound == 0) break;
    }

    if (folders.isEmpty) {
      folders.add(MockFolder(
        name: 'Tutti',
        count: '0 Post',
        color: Colors.purple.shade200,
        level: 0,
        isSpecial: true,
      ));
    }

    print(
        'DEBUG: Gerarchia ricostruita - ${folders.length} cartelle root, ${createdIds.length} totali');
  }

  // ============================================================================
  // SINCRONIZZAZIONE POST
  // ============================================================================

  Future<void> syncPostsFromDataService(
      List<SavedPost> realPosts, List<Folder> realFolders) async {
    if (kDebugMode) print('DEBUG: Convertendo ${realPosts.length} post...');

    allPosts.clear();

    // Map per trovare velocemente MockFolder da Folder.id
    final Map<String, MockFolder> folderIdToMockFolder = {};

    // 🆕 Popola map ricorsivamente usando ID diretti
    void mapFolders(MockFolder mockFolder) {
      if (!mockFolder.isSpecial && mockFolder.id != null) {
        folderIdToMockFolder[mockFolder.id!] = mockFolder;
      }

      for (var child in mockFolder.children) {
        mapFolders(child);
      }
    }

    for (var folder in folders) {
      mapFolders(folder);
    }

    // Converti post
    for (var realPost in realPosts) {
      MockFolder? sourceFolder;

      final realFolder = realFolders.firstWhere(
        (f) => f.id == realPost.folderId,
        orElse: () => realFolders.first,
      );

      if (realFolder.isDefault) {
        sourceFolder = folders.firstWhere(
          (f) => f.isSpecial,
          orElse: () => folders.first,
        );
      } else {
        sourceFolder = folderIdToMockFolder[realFolder.id];

        if (sourceFolder == null) {
          if (kDebugMode) {
            print(
                'WARNING: ⚠️ Post "${realPost.title}" ha folderId "${realPost.folderId}" non trovato nella mappa');
            print(
                'WARNING: RealFolder associato: ${realFolder.name} (ID: ${realFolder.id}, parentId: ${realFolder.parentId})');
            print(
                'WARNING: IDs disponibili nella mappa: ${folderIdToMockFolder.keys.join(", ")}');
            print('WARNING: Usando fallback a "Tutti"');
          }
          sourceFolder = folders.firstWhere(
            (f) => f.isSpecial,
            orElse: () => folders.first,
          );
        }
      }

      final mockPost = MockPost(
        id: realPost.id,
        title: realPost.title,
        url: realPost.url,
        description: realPost.description,
        savedDate: realPost.createdAt,
        sourceFolder: sourceFolder,
        tags: List.from(realPost.tags),
        imageUrl: realPost.imageUrl,
        creatorName: realPost.creatorName,
        creatorUsername: realPost.creatorUsername,
        previewStorageUrl: realPost.previewStorageUrl,
        isShared: realPost.isShared, // 🆕 NUOVO
      );

      allPosts.add(mockPost);
    }

    if (kDebugMode)
      print('DEBUG: Conversione post completata - ${allPosts.length} post');
  }

  /// Helper per trovare l'ID reale di un MockFolder
  String? findRealFolderId(List<Folder> realFolders, MockFolder mockFolder) {
    if (mockFolder.isSpecial) return null;

    final parentRealId = mockFolder.parent != null
        ? findRealFolderId(realFolders, mockFolder.parent!)
        : null;

    final found = realFolders.firstWhere(
      (f) =>
          f.name == mockFolder.name &&
          f.parentId == parentRealId &&
          !f.isDefault,
      orElse: () => Folder(
        id: 'not_found',
        name: 'Not Found',
        color: '#000000',
        createdAt: DateTime.now(),
      ),
    );

    return found.id != 'not_found' ? found.id : null;
  }

  // ============================================================================
  // METODI LEGACY (deprecati ma mantenuti per compatibilità)
  // ============================================================================

  MockFolder? findFolderByPath(String path) {
    if (path.isEmpty) return null;

    String cleanPath = path;
    if (cleanPath.startsWith('Home › ')) {
      cleanPath = cleanPath.substring(7);
    }

    final pathParts = cleanPath.split(' › ');

    MockFolder? currentFolder = folders.firstWhere(
      (f) => f.name == pathParts.first && !f.isSpecial,
      orElse: () =>
          MockFolder(name: '', count: '', color: Colors.grey, level: -1),
    );

    if (currentFolder == null || currentFolder.level == -1) return null;

    for (int i = 1; i < pathParts.length; i++) {
      final targetName = pathParts[i];
      MockFolder? found;

      for (var child in currentFolder!.children) {
        if (child.name == targetName) {
          found = child;
          break;
        }
      }

      if (found == null) return null;
      currentFolder = found;
    }

    return currentFolder;
  }

  MockFolder? findFolderByCompletePath(List<String> pathParts) {
    if (pathParts.isEmpty) return null;

    MockFolder? current = folders.firstWhere(
      (f) => !f.isSpecial && f.name == pathParts.first,
      orElse: () =>
          MockFolder(name: '', count: '', color: Colors.grey, level: -1),
    );

    if (current == null || current.level == -1) return null;

    for (int i = 1; i < pathParts.length; i++) {
      final targetName = pathParts[i];
      MockFolder? found;

      for (var child in current!.children) {
        if (child.name == targetName) {
          found = child;
          break;
        }
      }

      if (found == null) return null;
      current = found;
    }

    return current;
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  Future<List<SavedPost>> getPostsWithRetry(
      {String? folderId, int maxRetries = 2}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        if (kDebugMode) print('DEBUG: getPostsWithRetry - Chiamando DataService.instance.getPosts(folderId: $folderId) (tentativo $i)');
        final posts = await DataService.instance.getPosts(folderId: folderId);
        if (kDebugMode) print('DEBUG: getPostsWithRetry - Completato con ${posts.length} post (tentativo $i)');

        // Se i post sono vuoti alla prima chiamata, potrebbe essere che Firestore stia ancora caricando
        // ma per un utente nuovo è normale. Riduciamo il delay e facciamo retry solo se non siamo in web
        // (il web è solitamente più reattivo su queste cose o ha già la cache).
        if (i == 0 && posts.isEmpty && folderId == null) {
          if (kDebugMode)
            print('DEBUG: Prima chiamata getPosts vuota, attesa breve...');
          await Future.delayed(Duration(milliseconds: 500));
          continue;
        }

        return posts;
      } catch (e) {
        if (kDebugMode)
          print('DEBUG: Errore getPostsWithRetry (tentativo ${i + 1}): $e');
        if (i == maxRetries - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 300));
      }
    }

    return <SavedPost>[];
  }

  Future<void> syncWithDelayAndRetry() async {
    print('DEBUG: Sync ritardato con retry...');

    try {
      await Future.delayed(syncDelayAfterSave);

      await executeWithRetry(() async {
        final realPosts = await getPostsWithRetry();
        if (kDebugMode) print('DEBUG: getPostsWithRetry returned ${realPosts.length}');
        final realFolders = await DataService.instance.getFolders();
        if (kDebugMode) print('DEBUG: getFolders returned ${realFolders.length}');

        await syncFoldersFromDataServiceWithParentId(realFolders);
        await syncPostsFromDataService(realPosts, realFolders);

        updateTuttiCount();

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }
        notifyDataChanged();
      }, 'sync_with_delay_and_retry');
    } catch (e) {
      print('ERRORE: Sync ritardato fallito: $e');
      updateHealthStatus(ServiceHealthStatus.degraded,
          errorMessage: 'Delayed sync failed: $e');
    }
  }

  void updateTuttiCount() {
    if (folders.isEmpty) {
      folders.add(MockFolder(
        name: 'Tutti',
        count: '0 Post',
        color: Colors.purple.shade200,
        level: 0,
        isSpecial: true,
      ));
    }

    final tuttiFolder = folders.firstWhere(
      (f) => f.isSpecial,
      orElse: () => folders.first,
    );

    final totalPosts = allPosts.length;
    tuttiFolder.count = totalPosts > 0 ? '$totalPosts Post' : 'Vuota';

    updateAllFolderCounts();
    notifyDataChanged();
  }

  void updateAllFolderCounts() {
    for (var folder in folders) {
      if (!folder.isSpecial) {
        updateFolderCount(folder);
      }
    }
  }

  void updateFolderCount(MockFolder folder) {
    final subfolderCount = folder.children.length;
    final totalPosts = getPostCountForFolderAndChildren(folder);

    if (subfolderCount == 0 && totalPosts == 0) {
      folder.count = 'Vuota';
    } else if (subfolderCount == 0) {
      folder.count = '$totalPosts Post';
    } else if (totalPosts == 0) {
      folder.count =
          '$subfolderCount ${subfolderCount == 1 ? 'cartella' : 'cartelle'}';
    } else {
      folder.count =
          '$subfolderCount ${subfolderCount == 1 ? 'cartella' : 'cartelle'} • $totalPosts Post';
    }

    for (var child in folder.children) {
      updateFolderCount(child);
    }
  }

  int getPostCountForFolderAndChildren(MockFolder folder) {
    int count = allPosts.where((post) => post.sourceFolder == folder).length;

    for (var child in folder.children) {
      count += getPostCountForFolderAndChildren(child);
    }

    return count;
  }

  Color hexToColor(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }

  // ============================================================================
  // CACHE E DIAGNOSTICA
  // ============================================================================

  Future<void> debugCacheStatus() async {
    try {
      print('DEBUG: ========== DIAGNOSI CACHE ==========');

      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        print('DEBUG: Utente non autenticato');
        return;
      }

      print('DEBUG: User ID: ${firebaseUser.uid}');

      final firestore = FirebaseFirestore.instance;
      final foldersRef = firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('folders');

      final directSnapshot = await foldersRef.get();
      print('DEBUG: Cartelle in Firestore: ${directSnapshot.docs.length}');

      for (var doc in directSnapshot.docs) {
        final data = doc.data();
        print('  - ${data['name']} (parentId: ${data['parentId']})');
      }

      final serviceFolders = await DataService.instance.getFolders();
      print('DEBUG: Cartelle tramite DataService: ${serviceFolders.length}');

      if (directSnapshot.docs.length != serviceFolders.length) {
        print('DEBUG: ⚠️ INCONSISTENZA rilevata');
      }
    } catch (e) {
      print('ERRORE: Diagnosi cache fallita: $e');
    }
  }

  Future<void> clearAllCache() async {
    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys();

        for (String key in keys) {
          if (key.contains(firebaseUser.uid) ||
              key.contains('folders_cache') ||
              key.contains('posts_cache')) {
            await prefs.remove(key);
          }
        }
      }

      await DataService.instance.reloadFromDisk();
      print('DEBUG: Cache pulita completamente');
    } catch (e) {
      print('DEBUG: Errore pulizia cache: $e');
    }
  }

  Future<void> forceReloadFromDatabase() async {
    print('DEBUG: Forzando reload completo...');

    updateHealthStatus(ServiceHealthStatus.authenticating);
    clearUserCache();
    isInitialized = false;

    await syncWithDataService();
  }
}
