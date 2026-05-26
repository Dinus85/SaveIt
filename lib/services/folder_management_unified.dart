// ============================================================================
// FOLDER MANAGEMENT UNIFIED
// ============================================================================
// Gestione completa e centralizzata di:
// - Creazione/eliminazione cartelle e sottocartelle
// - Sincronizzazione database ↔ UI
// - Gestione anteprime con immagini dei post
// - Operazioni CRUD su cartelle e post
//
// Questo file unifica la logica precedentemente sparsa in 8 file diversi
// per una manutenzione più semplice e comprensibile
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/folder.dart';
import '../models.dart';
import '../data_service.dart';
import '../utils/constants.dart';

// ============================================================================
// SECTION 1: MODELLI DI DATI
// ============================================================================

/// Rappresenta il mapping tra struttura database e UI
class FolderHierarchyNode {
  final Folder dbFolder; // Riferimento al database (con parentId)
  final MockFolder uiFolder; // Riferimento all'UI (con children/parent)
  final List<FolderHierarchyNode> children;

  FolderHierarchyNode({
    required this.dbFolder,
    required this.uiFolder,
    this.children = const [],
  });
}

/// Statistiche sulle anteprime di una cartella
class FolderPreviewStats {
  final int totalImagesAvailable;
  final int recentImagesCount;
  final List<String> imageUrls;
  final bool hasEnoughForGrid;

  FolderPreviewStats({
    required this.totalImagesAvailable,
    required this.recentImagesCount,
    required this.imageUrls,
  }) : hasEnoughForGrid = imageUrls.length >= 2;
}

// ============================================================================
// SECTION 2: FOLDER HIERARCHY MANAGER
// ============================================================================
// Gestisce la creazione e navigazione della struttura gerarchica

class FolderHierarchyManager {
  /// Crea una gerarchia completa di cartelle da un path
  /// Esempio: "Tech › Flutter › Tips" crea tre livelli di cartelle
  ///
  /// Returns: ID Firebase della cartella finale creata
  static Future<String> createHierarchyFromPath(
    String fullPath, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 300),
  }) async {
    print('🎯 [HIERARCHY] Creazione gerarchia da path: $fullPath');

    // Parse del path
    final pathParts = _parsePathIntoParts(fullPath);
    if (pathParts.isEmpty) {
      throw Exception('Path vuoto o non valido');
    }

    print('📋 [HIERARCHY] Livelli da creare: ${pathParts.join(" → ")}');

    String? currentParentId; // null = root level
    String? currentFolderId;

    // Loop per ogni livello della gerarchia
    for (int i = 0; i < pathParts.length; i++) {
      final folderName = pathParts[i];
      final isRoot = i == 0;

      print(
          '📁 [HIERARCHY] Livello $i: "$folderName" (${isRoot ? "ROOT" : "CHILD"})');

      // Invalida cache e ricarica per vedere le cartelle appena create
      await _refreshDatabaseCache();

      // Carica folders aggiornate dal database
      final realFolders = await DataService.instance.getFolders();
      print('📚 [HIERARCHY] Cartelle in database: ${realFolders.length}');

      // Cerca se la cartella esiste già
      Folder? existingFolder = await _findExistingFolder(
          realFolders, folderName, isRoot, currentParentId);

      if (existingFolder != null) {
        // Cartella già esiste, usa il suo ID come parent per il prossimo livello
        currentFolderId = existingFolder.id;
        currentParentId = existingFolder.id;
        print(
            '✅ [HIERARCHY] Cartella "$folderName" già esistente (ID: ${existingFolder.id})');
        continue;
      }

      // Cartella non esiste, creala
      print('🔨 [HIERARCHY] Creando cartella "$folderName"...');

      if (isRoot) {
        // Crea cartella root (parentId = null)
        await _createRootFolder(folderName);
      } else {
        // Crea sottocartella (parentId = currentParentId)
        await _createChildFolder(currentParentId!, folderName);
      }

      // Attendi propagazione e ricarica
      await Future.delayed(Duration(milliseconds: 500));
      await _refreshDatabaseCache();

      // Trova l'ID della cartella appena creata
      final updatedFolders = await DataService.instance.getFolders();
      Folder? createdFolder = await _findExistingFolder(
          updatedFolders, folderName, isRoot, currentParentId);

      if (createdFolder == null) {
        throw Exception(
            'Cartella "$folderName" creata ma non trovata nel database');
      }

      currentFolderId = createdFolder.id;
      currentParentId = createdFolder.id;
      print(
          '✅ [HIERARCHY] Cartella "$folderName" creata (ID: ${createdFolder.id})');
    }

    if (currentFolderId == null) {
      throw Exception('Nessuna cartella creata');
    }

    print('🎉 [HIERARCHY] Gerarchia completata - ID finale: $currentFolderId');
    return currentFolderId;
  }

  /// Parse del path in parti separate
  static List<String> _parsePathIntoParts(String fullPath) {
    String cleanPath = fullPath.trim();
    if (cleanPath.startsWith('Home › ')) {
      cleanPath = cleanPath.substring(7);
    }

    return cleanPath
        .split(' › ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  /// Cerca una cartella esistente nel database
  static Future<Folder?> _findExistingFolder(
    List<Folder> folders,
    String name,
    bool isRoot,
    String? parentId,
  ) async {
    try {
      if (isRoot) {
        // Root level: cerca con parentId == null
        return folders.firstWhere(
          (f) => f.name == name && !f.isDefault && f.parentId == null,
        );
      } else {
        // Child level: cerca con parentId specifico
        return folders.firstWhere(
          (f) => f.name == name && f.parentId == parentId,
        );
      }
    } catch (e) {
      return null;
    }
  }

  /// Invalida cache e ricarica dal database
  static Future<void> _refreshDatabaseCache() async {
    DataService.instance.invalidateCache(
        folders: true, posts: true); // ⭐ Anche posts per sincronizzazione
    await DataService.instance.reloadFromDisk();
  }

  /// Crea una cartella root (parentId = null)
  static Future<void> _createRootFolder(String name) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) throw Exception('User not authenticated');

    final firestore = FirebaseFirestore.instance;
    final foldersCollection = firestore
        .collection('users')
        .doc(firebaseUser.uid)
        .collection('folders');

    final folderData = {
      'name': name.trim(),
      'color': '#${_getRandomColor().value.toRadixString(16).substring(2)}',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDefault': false,
      'parentId': null,
    };

    await foldersCollection.add(folderData);
    print('✅ [CREATE] Cartella root "$name" creata');
  }

  /// Crea una sottocartella (parentId = specificato)
  static Future<void> _createChildFolder(String parentId, String name) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) throw Exception('User not authenticated');

    final firestore = FirebaseFirestore.instance;
    final foldersCollection = firestore
        .collection('users')
        .doc(firebaseUser.uid)
        .collection('folders');

    final folderData = {
      'name': name.trim(),
      'color': '#${_getRandomColor().value.toRadixString(16).substring(2)}',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDefault': false,
      'parentId': parentId,
    };

    await foldersCollection.add(folderData);
    print('✅ [CREATE] Sottocartella "$name" creata (parent: $parentId)');
  }

  /// Genera un colore casuale per le cartelle
  static Color _getRandomColor() {
    final colors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400,
      Colors.teal.shade400,
      Colors.indigo.shade400,
      Colors.pink.shade400,
    ];
    return colors[DateTime.now().millisecondsSinceEpoch % colors.length];
  }

  /// Costruisce il path completo di una MockFolder
  /// Esempio: "Tech › Flutter › Tips"
  static String buildFolderPath(MockFolder folder) {
    List<String> path = [];
    MockFolder? current = folder;

    while (current != null && !current.isSpecial) {
      path.insert(0, current.name);
      current = current.parent;
    }

    return path.isEmpty ? 'Home' : 'Home › ${path.join(' › ')}';
  }

  /// Trova una MockFolder dal suo path
  static MockFolder? findFolderByPath(
      List<MockFolder> rootFolders, String path) {
    final parts = _parsePathIntoParts(path);
    if (parts.isEmpty) return null;

    // Cerca la root
    MockFolder? current;
    for (var folder in rootFolders) {
      if (folder.name == parts.first && !folder.isSpecial) {
        current = folder;
        break;
      }
    }

    if (current == null) return null;

    // Naviga la gerarchia
    for (int i = 1; i < parts.length; i++) {
      final targetName = parts[i];
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
}

// ============================================================================
// SECTION 3: FOLDER SYNCHRONIZATION MANAGER
// ============================================================================
// Sincronizza la struttura del database con la UI

class FolderSynchronizationManager {
  /// Sincronizza cartelle dal database all'UI usando parentId
  /// Ricostruisce l'intera struttura ad albero di MockFolder
  static Future<List<MockFolder>> syncFoldersFromDatabase(
      List<Folder> dbFolders) async {
    print('🔄 [SYNC] Sincronizzazione cartelle da database');
    print('📚 [SYNC] Totale cartelle DB: ${dbFolders.length}');

    // Crea lista risultati
    List<MockFolder> rootFolders = [];

    // Trova cartella "Tutti"
    final defaultFolder = dbFolders.firstWhere(
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
      color: _hexToColor(defaultFolder.color),
      level: 0,
      isSpecial: true,
    );

    rootFolders.add(tuttiFolder);

    // Map per tracciare ID DB → MockFolder
    final Map<String, MockFolder> idToMockFolder = {};

    // PASSO 1: Crea tutte le cartelle root (parentId == null)
    final roots =
        dbFolders.where((f) => !f.isDefault && f.parentId == null).toList();
    print('📁 [SYNC] Cartelle root: ${roots.length}');

    for (var dbFolder in roots) {
      final mockFolder = MockFolder(
        name: dbFolder.name,
        count: 'Caricando...',
        color: _hexToColor(dbFolder.color),
        level: 0,
        isSpecial: false,
        parent: null,
        children: [],
      );

      rootFolders.add(mockFolder);
      idToMockFolder[dbFolder.id] = mockFolder;
      print('  ✅ ${dbFolder.name} (ID: ${dbFolder.id})');
    }

    // PASSO 2: Crea le sottocartelle in ordine di profondità
    final children =
        dbFolders.where((f) => !f.isDefault && f.parentId != null).toList();
    print('📂 [SYNC] Sottocartelle: ${children.length}');

    int maxIterations = 10;
    int iteration = 0;
    Set<String> createdIds = idToMockFolder.keys.toSet();

    while (createdIds.length < dbFolders.where((f) => !f.isDefault).length &&
        iteration < maxIterations) {
      iteration++;
      int createdThisRound = 0;

      for (var dbFolder in children) {
        // Salta se già creata
        if (createdIds.contains(dbFolder.id)) continue;

        // Salta se parent non ancora creato
        if (!createdIds.contains(dbFolder.parentId!)) continue;

        final parentMock = idToMockFolder[dbFolder.parentId!];
        if (parentMock == null) continue;

        final mockFolder = MockFolder(
          name: dbFolder.name,
          count: 'Vuota',
          color: _hexToColor(dbFolder.color),
          level: parentMock.level + 1,
          isSpecial: false,
          parent: parentMock,
          children: [],
        );

        parentMock.children.add(mockFolder);
        idToMockFolder[dbFolder.id] = mockFolder;
        createdIds.add(dbFolder.id);
        createdThisRound++;

        print(
            '  ✅ ${dbFolder.name} sotto ${parentMock.name} (livello ${mockFolder.level})');
      }

      if (createdThisRound == 0) break;
    }

    print(
        '✅ [SYNC] Gerarchia ricostruita: ${rootFolders.length} root, ${createdIds.length} totali');
    return rootFolders;
  }

  /// Trova la Folder del database corrispondente a una MockFolder UI
  /// Segue la catena parent → child usando parentId
  static Folder? findDatabaseFolderFromMock(
    List<Folder> dbFolders,
    MockFolder mockFolder,
  ) {
    if (mockFolder.isSpecial) return null;

    // Costruisci path dalla mock folder alla root
    List<String> mockPath = [];
    MockFolder? current = mockFolder;

    while (current != null && !current.isSpecial) {
      mockPath.insert(0, current.name);
      current = current.parent;
    }

    print('🔍 [SEARCH] Cercando DB folder per path: ${mockPath.join(" › ")}');

    // Cerca nel database seguendo parentId
    Folder? found;

    for (int i = 0; i < mockPath.length; i++) {
      final targetName = mockPath[i];

      if (i == 0) {
        // Root level: cerca senza parent
        try {
          found = dbFolders.firstWhere(
            (f) => f.name == targetName && !f.isDefault && f.parentId == null,
          );
          print('  ✅ Root trovata: ${found.name} (ID: ${found.id})');
        } catch (e) {
          print('  ❌ Root "$targetName" non trovata');
          return null;
        }
      } else {
        // Child level: cerca con parentId specifico
        if (found == null) return null;

        final previousId = found.id;
        try {
          found = dbFolders.firstWhere(
            (f) => f.name == targetName && f.parentId == previousId,
          );
          print('  ✅ Child trovata: ${found.name} (ID: ${found.id})');
        } catch (e) {
          print('  ❌ Child "$targetName" con parent $previousId non trovata');
          return null;
        }
      }
    }

    return found;
  }

  /// Converte colore hex in Color
  static Color _hexToColor(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) {
        buffer.write('ff');
      }
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }
}

// ============================================================================
// SECTION 4: FOLDER PREVIEW MANAGER
// ============================================================================
// Gestisce le anteprime delle cartelle con immagini dei post

class FolderPreviewManager {
  /// Ottieni le immagini degli ultimi N post di una cartella (ricorsivo)
  /// Include anche i post delle sottocartelle
  static FolderPreviewStats getFolderPreviewImages(
    MockFolder folder,
    List<MockPost> allPosts, {
    int maxImages = 4,
  }) {
    print('🖼️ [PREVIEW] Generando anteprima per: ${folder.name}');

    final List<MockPost> postsWithImages = [];
    bool hasPreview(MockPost post) =>
        post.imageUrl?.trim().isNotEmpty == true ||
        post.previewStorageUrl?.trim().isNotEmpty == true;
    String previewUrl(MockPost post) =>
        post.previewStorageUrl?.trim().isNotEmpty == true
            ? post.previewStorageUrl!.trim()
            : post.imageUrl!.trim();

    if (folder.isSpecial) {
      // Cartella "Tutti": mostra tutti i post con immagini
      postsWithImages.addAll(allPosts.where(hasPreview));
    } else {
      // Cartella normale: raccogli post ricorsivamente
      _collectPostsRecursively(folder, allPosts, postsWithImages);
    }

    // Ordina per data (più recenti prima)
    postsWithImages.sort((a, b) => b.savedDate.compareTo(a.savedDate));

    // Estrai URL immagini
    final imageUrls = postsWithImages
        .take(maxImages)
        .map(previewUrl)
        .where((url) => url.isNotEmpty)
        .toList();

    print('  📊 Totale immagini disponibili: ${postsWithImages.length}');
    print('  🎯 Immagini recenti estratte: ${imageUrls.length}');

    return FolderPreviewStats(
      totalImagesAvailable: postsWithImages.length,
      recentImagesCount: imageUrls.length,
      imageUrls: imageUrls,
    );
  }

  /// Raccoglie post ricorsivamente da una cartella e le sue sottocartelle
  static void _collectPostsRecursively(
    MockFolder folder,
    List<MockPost> allPosts,
    List<MockPost> result,
  ) {
    // Aggiungi post diretti di questa cartella
    final directPosts = allPosts
        .where((post) =>
            post.sourceFolder == folder &&
            (post.imageUrl?.trim().isNotEmpty == true ||
                post.previewStorageUrl?.trim().isNotEmpty == true))
        .toList();

    result.addAll(directPosts);

    // Ricorsione sui children
    for (var child in folder.children) {
      _collectPostsRecursively(child, allPosts, result);
    }
  }

  /// Ottieni statistiche complete sulle immagini di una cartella
  static Map<String, dynamic> getFolderImageStats(
    MockFolder folder,
    List<MockPost> allPosts,
  ) {
    final stats = getFolderPreviewImages(folder, allPosts, maxImages: 100);

    return {
      'totalImages': stats.totalImagesAvailable,
      'recentImages': stats.recentImagesCount,
      'hasEnoughForGrid': stats.hasEnoughForGrid,
      'canShowPreview': stats.imageUrls.isNotEmpty,
    };
  }

  /// Verifica se una cartella ha abbastanza immagini per una preview
  static bool canShowImagePreview(MockFolder folder, List<MockPost> allPosts) {
    final stats = getFolderPreviewImages(folder, allPosts, maxImages: 1);
    return stats.imageUrls.isNotEmpty;
  }
}

// ============================================================================
// SECTION 5: POST MANAGEMENT
// ============================================================================
// Gestisce il salvataggio e l'assegnazione dei post alle cartelle

class PostManagement {
  /// Salva un post in una cartella specifica
  /// folderId deve essere l'ID Firebase della cartella target
  static Future<SavedPost> savePostToFolder({
    required String url,
    required String title,
    String? description,
    String? imageUrl,
    String? creatorName,
    String? creatorUsername,
    List<String>? tags,
    required String folderId,
  }) async {
    print('💾 [POST] Salvando post in cartella: $folderId');
    print('  📝 Titolo: $title');
    print('  🔗 URL: $url');

    final post = await DataService.instance.createPost(
      url: url,
      title: title,
      description: description ?? '',
      imageUrl: imageUrl,
      creatorName: creatorName,
      creatorUsername: creatorUsername,
      tags: tags ?? [],
      folderId: folderId,
    );

    print('✅ [POST] Post salvato con ID: ${post.id}');
    return post;
  }

  /// Sposta un post da una cartella a un'altra
  static Future<void> movePostToFolder(
    SavedPost post,
    String newFolderId,
  ) async {
    print('📦 [POST] Spostando post "${post.title}" in cartella: $newFolderId');

    final updatedPost = post.copyWith(
      folderId: newFolderId,
      updatedAt: DateTime.now(),
    );

    await DataService.instance.savePost(updatedPost);
    print('✅ [POST] Post spostato con successo');
  }

  /// Elimina un post
  static Future<void> deletePost(String postId) async {
    print('🗑️ [POST] Eliminando post: $postId');
    await DataService.instance.deletePost(postId);
    print('✅ [POST] Post eliminato');
  }

  /// Sincronizza i post dal database alle MockFolder UI
  static Future<List<MockPost>> syncPostsFromDatabase(
    List<SavedPost> dbPosts,
    List<Folder> dbFolders,
    List<MockFolder> uiFolders,
  ) async {
    print('🔄 [POST SYNC] Sincronizzando ${dbPosts.length} post');

    final List<MockPost> result = [];

    // Crea map DB Folder ID → MockFolder UI
    final Map<String, MockFolder> idToMockFolder = {};

    void mapFoldersRecursively(MockFolder folder) {
      if (!folder.isSpecial) {
        final dbFolder =
            FolderSynchronizationManager.findDatabaseFolderFromMock(
          dbFolders,
          folder,
        );
        if (dbFolder != null) {
          idToMockFolder[dbFolder.id] = folder;
        }
      }

      for (var child in folder.children) {
        mapFoldersRecursively(child);
      }
    }

    for (var folder in uiFolders) {
      mapFoldersRecursively(folder);
    }

    // Converti ogni post
    for (var dbPost in dbPosts) {
      MockFolder? sourceFolder;

      // Trova la cartella del database
      final dbFolder = dbFolders.firstWhere(
        (f) => f.id == dbPost.folderId,
        orElse: () => dbFolders.first, // Fallback a "Tutti"
      );

      if (dbFolder.isDefault) {
        // Post in "Tutti"
        sourceFolder = uiFolders.firstWhere(
          (f) => f.isSpecial,
          orElse: () => uiFolders.first,
        );
      } else {
        // Post in cartella normale
        sourceFolder = idToMockFolder[dbFolder.id];

        if (sourceFolder == null) {
          print(
              '⚠️ [POST SYNC] Post "${dbPost.title}" ha folderId non mappato, usando Tutti');
          sourceFolder = uiFolders.firstWhere(
            (f) => f.isSpecial,
            orElse: () => uiFolders.first,
          );
        }
      }

      final mockPost = MockPost(
        id: dbPost.id,
        title: dbPost.title,
        url: dbPost.url,
        description: dbPost.description,
        savedDate: dbPost.createdAt,
        sourceFolder: sourceFolder,
        tags: List.from(dbPost.tags),
        imageUrl: dbPost.imageUrl,
      );

      result.add(mockPost);
    }

    print('✅ [POST SYNC] ${result.length} post sincronizzati');
    return result;
  }
}

// ============================================================================
// SECTION 6: FOLDER OPERATIONS (CRUD)
// ============================================================================
// Operazioni di creazione, rinomina, eliminazione cartelle

class FolderOperations {
  /// Crea una nuova cartella root
  static Future<void> createRootFolder(String name) async {
    await FolderHierarchyManager._createRootFolder(name);
  }

  /// Crea una sottocartella
  static Future<void> createSubfolder(MockFolder parent, String name) async {
    // Trova l'ID del database del parent
    final dbFolders = await DataService.instance.getFolders();
    final parentDbFolder =
        FolderSynchronizationManager.findDatabaseFolderFromMock(
      dbFolders,
      parent,
    );

    if (parentDbFolder == null) {
      throw Exception('Cartella parent non trovata nel database');
    }

    await FolderHierarchyManager._createChildFolder(parentDbFolder.id, name);
  }

  /// Rinomina una cartella
  static Future<void> renameFolder(MockFolder folder, String newName) async {
    print('✏️ [RENAME] Rinominando "${folder.name}" → "$newName"');

    // Trova cartella nel database
    final dbFolders = await DataService.instance.getFolders();
    final dbFolder = FolderSynchronizationManager.findDatabaseFolderFromMock(
      dbFolders,
      folder,
    );

    if (dbFolder == null) {
      throw Exception('Cartella non trovata nel database');
    }

    // Aggiorna nel database
    final updated = dbFolder.copyWith(
      name: newName.trim(),
      updatedAt: DateTime.now(),
    );

    await DataService.instance.saveFolder(updated);

    // Aggiorna in memoria
    folder.name = newName.trim();

    print('✅ [RENAME] Cartella rinominata');
  }

  /// Elimina una cartella (e sposta i post in "Tutti")
  static Future<void> deleteFolder(MockFolder folder) async {
    print('🗑️ [DELETE] Eliminando cartella: ${folder.name}');

    if (folder.isSpecial) {
      throw Exception('Impossibile eliminare la cartella speciale "Tutti"');
    }

    // Trova cartella nel database
    final dbFolders = await DataService.instance.getFolders();
    final dbFolder = FolderSynchronizationManager.findDatabaseFolderFromMock(
      dbFolders,
      folder,
    );

    if (dbFolder == null) {
      throw Exception('Cartella non trovata nel database');
    }

    // Trova cartella "Tutti" per spostare i post
    final tuttiFolder = dbFolders.firstWhere((f) => f.isDefault);

    // Sposta tutti i post in "Tutti"
    final posts = await DataService.instance.getPosts();
    final postsInFolder =
        posts.where((p) => p.folderId == dbFolder.id).toList();

    print('  📦 Spostando ${postsInFolder.length} post in "Tutti"');
    for (var post in postsInFolder) {
      await PostManagement.movePostToFolder(post, tuttiFolder.id);
    }

    // Elimina cartella
    await DataService.instance.deleteFolder(dbFolder.id);

    // Rimuovi dalla struttura UI
    if (folder.parent != null) {
      folder.parent!.children.remove(folder);
    }

    print('✅ [DELETE] Cartella eliminata');
  }

  /// Sposta una cartella sotto un altro parent
  static Future<void> moveFolder(
      MockFolder folder, MockFolder? newParent) async {
    print(
        '📦 [MOVE] Spostando "${folder.name}" sotto "${newParent?.name ?? 'root'}"');

    // Trova cartelle nel database
    final dbFolders = await DataService.instance.getFolders();
    final dbFolder = FolderSynchronizationManager.findDatabaseFolderFromMock(
      dbFolders,
      folder,
    );

    if (dbFolder == null) {
      throw Exception('Cartella non trovata nel database');
    }

    String? newParentId;
    if (newParent != null && !newParent.isSpecial) {
      final dbParent = FolderSynchronizationManager.findDatabaseFolderFromMock(
        dbFolders,
        newParent,
      );
      newParentId = dbParent?.id;
    }

    // Aggiorna nel database
    final updated = dbFolder.copyWith(
      parentId: newParentId,
      updatedAt: DateTime.now(),
    );

    await DataService.instance.saveFolder(updated);

    // Aggiorna struttura UI
    if (folder.parent != null) {
      folder.parent!.children.remove(folder);
    }

    folder.parent = newParent;

    if (newParent != null) {
      newParent.children.add(folder);
      folder.level = newParent.level + 1;
    } else {
      folder.level = 0;
    }

    print('✅ [MOVE] Cartella spostata');
  }
}

// ============================================================================
// SECTION 7: UTILITY FUNCTIONS
// ============================================================================

class FolderUtils {
  /// Conta tutti i post in una cartella (ricorsivo)
  static int countPostsInFolder(MockFolder folder, List<MockPost> allPosts) {
    int count = allPosts.where((p) => p.sourceFolder == folder).length;

    for (var child in folder.children) {
      count += countPostsInFolder(child, allPosts);
    }

    return count;
  }

  /// Aggiorna il conteggio display di una cartella
  static void updateFolderCount(MockFolder folder, List<MockPost> allPosts) {
    final subfolderCount = folder.children.length;
    final totalPosts = countPostsInFolder(folder, allPosts);

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

    // Ricorsione sui children
    for (var child in folder.children) {
      updateFolderCount(child, allPosts);
    }
  }

  /// Aggiorna tutti i conteggi delle cartelle
  static void updateAllFolderCounts(
      List<MockFolder> folders, List<MockPost> allPosts) {
    for (var folder in folders) {
      if (folder.isSpecial) {
        // Cartella "Tutti"
        final totalPosts = allPosts.length;
        folder.count = totalPosts > 0 ? '$totalPosts Post' : 'Vuota';
      } else {
        updateFolderCount(folder, allPosts);
      }
    }
  }

  /// Ottiene tutti i post ricorsivamente da una cartella
  static List<MockPost> getAllPostsRecursive(
      MockFolder folder, List<MockPost> allPosts) {
    List<MockPost> result = [];

    // Post diretti
    result.addAll(allPosts.where((p) => p.sourceFolder == folder));

    // Post dai children
    for (var child in folder.children) {
      result.addAll(getAllPostsRecursive(child, allPosts));
    }

    return result;
  }

  /// Stampa la struttura gerarchica per debug
  static void printFolderStructure(List<MockFolder> folders,
      {String prefix = ''}) {
    for (var folder in folders) {
      if (!folder.isSpecial) {
        print('$prefix├─ ${folder.name} (livello ${folder.level})');
        if (folder.children.isNotEmpty) {
          printFolderStructure(folder.children, prefix: '$prefix│  ');
        }
      }
    }
  }
}

// ============================================================================
// EXPORTS
// ============================================================================

/// Classe principale che espone tutte le funzionalità
class UnifiedFolderManager {
  // Hierarchy
  static final hierarchy = FolderHierarchyManager();

  // Synchronization
  static final sync = FolderSynchronizationManager();

  // Previews
  static final preview = FolderPreviewManager();

  // Posts
  static final posts = PostManagement();

  // Operations
  static final operations = FolderOperations();

  // Utils
  static final utils = FolderUtils();
}
