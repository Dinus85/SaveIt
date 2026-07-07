// lib/services/firebase_data_service.dart
// Firebase Data Service - Gestione completa Firestore per SaveIn App
// Version: 1.6 - 🔧 FIX PARENTID: Aggiunto supporto completo per parentId nelle cartelle

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:savein/models.dart';

/// Exception personalizzata per errori Firebase
class FirebaseDataException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  FirebaseDataException(this.message, {this.code, this.originalError});

  @override
  String toString() =>
      'FirebaseDataException: $message${code != null ? ' ($code)' : ''}';
}

class _GlobalPostCanonicalData {
  final String? url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? previewStorageUrl;
  final String? creatorName;
  final String? creatorUsername;

  const _GlobalPostCanonicalData({
    this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.previewStorageUrl,
    this.creatorName,
    this.creatorUsername,
  });

  factory _GlobalPostCanonicalData.fromMap(Map<String, dynamic> data) {
    String? text(String key) {
      final value = data[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return _GlobalPostCanonicalData(
      url: text('url'),
      title: text('title'),
      description: text('description'),
      imageUrl: text('imageUrl'),
      previewStorageUrl: text('previewStorageUrl'),
      creatorName: text('creatorName'),
      creatorUsername: text('creatorUsername'),
    );
  }
}

class _GlobalPostResult {
  final String? globalPostId;
  final String? urlHash;
  final String? normalizedUrl;
  final _GlobalPostCanonicalData canonical;

  const _GlobalPostResult({
    required this.globalPostId,
    required this.urlHash,
    required this.normalizedUrl,
    required this.canonical,
  });
}

/// Exception per errori di conversione Firestore
class FirestoreConversionException implements Exception {
  final String message;
  final dynamic originalError;

  FirestoreConversionException(this.message, {this.originalError});

  @override
  String toString() => 'FirestoreConversionException: $message';
}

/// Extension per convertire Folder da/verso Firestore - 🔧 FIX: Aggiunto parentId
extension FolderFirestoreService on Folder {
  static Folder fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) {
        throw FirestoreConversionException(
            'Document data is null for folder ${doc.id}');
      }

      return Folder(
        id: doc.id,
        name: data['name'] as String? ?? '',
        color: data['color'] as String? ?? '#BB86FC',
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt:
            (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isDefault: data['isDefault'] as bool? ?? false,
        parentId:
            data['parentId'] as String?, // 🔧 FIX: Leggi parentId da Firestore
        isShared: data['isShared'] as bool? ?? false,
      );
    } catch (e) {
      throw FirestoreConversionException(
          'Failed to convert folder from Firestore: $e',
          originalError: e);
    }
  }

  Map<String, dynamic> toFirestoreService() {
    return {
      'name': name,
      'color': color,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
      'isDefault': isDefault,
      'parentId': parentId, // 🔧 FIX: Scrivi parentId su Firestore
      'isShared': isShared,
    };
  }
}

/// Extension per convertire SavedPost da/verso Firestore
extension SavedPostFirestoreService on SavedPost {
  static SavedPost fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) {
        throw FirestoreConversionException(
            'Document data is null for post ${doc.id}');
      }

      return SavedPost(
        id: doc.id,
        url: data['url'] as String? ?? '',
        title: data['title'] as String? ?? '',
        description: data['description'] as String? ?? '',
        imageUrl: data['imageUrl'] as String?,
        creatorName: data['creatorName'] as String?,
        creatorUsername: data['creatorUsername'] as String?,
        previewStorageUrl: data['previewStorageUrl'] as String?,
        tags: List<String>.from(data['tags'] as List? ?? []),
        folderId: data['folderId'] as String? ?? '',
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt:
            (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isShared: data['isShared'] as bool? ?? false,
        globalPostId: data['globalPostId'] as String?,
        urlHash: data['urlHash'] as String?,
        normalizedUrl: data['normalizedUrl'] as String?,
      );
    } catch (e) {
      throw FirestoreConversionException(
          'Failed to convert post from Firestore: $e',
          originalError: e);
    }
  }

  Map<String, dynamic> toFirestoreService() {
    return {
      'url': url,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'creatorName': creatorName,
      'creatorUsername': creatorUsername,
      'previewStorageUrl': previewStorageUrl,
      'tags': tags,
      'folderId': folderId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
      'isShared': isShared,
      'globalPostId': globalPostId,
      'urlHash': urlHash,
      'normalizedUrl': normalizedUrl,
    };
  }
}

/// Service principale per operazioni Firestore - SENZA TEST AGGRESSIVI
class FirebaseDataService {
  static final FirebaseDataService _instance = FirebaseDataService._internal();
  factory FirebaseDataService() => _instance;
  FirebaseDataService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  // Stream controllers per real-time updates
  StreamController<List<Folder>>? _foldersController;
  StreamController<List<SavedPost>>? _postsController;

  // Cache locale per performance
  List<Folder>? _cachedFolders;
  List<SavedPost>? _cachedPosts;
  DateTime? _lastFolderSync;
  DateTime? _lastPostSync;
  // UID a cui appartiene la cache — se cambia utente la cache è invalidata
  String? _cachedUserId;

  static const Duration _cacheValidityDuration = Duration(minutes: 5);

  /// Ottiene l'ID dell'utente corrente autenticato
  String get _currentUserId {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseDataException(
          'Utente non autenticato. È richiesto il login per accedere ai dati.',
          code: 'user_not_authenticated');
    }
    return user.uid;
  }

  /// Reference alla collezione folders dell'utente corrente
  CollectionReference<Map<String, dynamic>> get _foldersCollection =>
      _firestore.collection('users').doc(_currentUserId).collection('folders');

  /// Reference alla collezione posts dell'utente corrente
  CollectionReference<Map<String, dynamic>> get _postsCollection =>
      _firestore.collection('users').doc(_currentUserId).collection('posts');

  /// Reference alla collezione shared_items dell'utente corrente
  CollectionReference<Map<String, dynamic>> get _sharedItemsCollection =>
      _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('shared_items');

  // ============================================================================
  // TEST CONNETTIVITÀ SEMPLIFICATO - RISOLVE IL PROBLEMA PERMISSION-DENIED
  // ============================================================================

  /// Test base connettività Firebase - SOLO LETTURA, SENZA SCRITTURE
  Future<bool> testBasicConnectivity() async {
    try {
      if (kDebugMode) print('========== TEST CONNETTIVITÀ BASE ==========');

      // Test 1: Verifica Firebase App
      if (kDebugMode) print('DEBUG: Test 1 - Verifica Firebase App...');
      final app = _firestore.app;
      if (kDebugMode) print('DEBUG: Firebase App OK: ${app.options.projectId}');

      // Test 2: Verifica autenticazione
      if (kDebugMode) print('DEBUG: Test 2 - Verifica autenticazione...');
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw FirebaseDataException('No authenticated user found');
      }
      if (kDebugMode) print('DEBUG: User autenticato: ${currentUser.uid}');

      // Test 3: SOLO LETTURA - Prova a leggere (senza scrivere)
      if (kDebugMode)
        print('DEBUG: Test 3 - Test lettura collezione folders...');
      try {
        final foldersQuery = _foldersCollection.limit(1);
        await foldersQuery.get();
        if (kDebugMode) print('DEBUG: ✅ Lettura collezione folders OK');
      } catch (e) {
        if (kDebugMode)
          print('DEBUG: ⚠️ Collezione folders non accessibile: $e');
        // Non lanciare errore - potrebbe essere vuota
      }

      if (kDebugMode) {
        print('DEBUG: ✅ Test connettività base completato');
        print('=============================================');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('DEBUG: ❌ Test connettività base fallito: $e');
        print('=============================================');
      }

      if (e.toString().contains('permission-denied')) {
        throw FirebaseDataException(
            'Regole Firebase negano accesso. Verifica configurazione.',
            code: 'permission_denied',
            originalError: e);
      }

      throw FirebaseDataException('Test connettività fallito: $e',
          code: 'connectivity_failed', originalError: e);
    }
  }

  // ============================================================================
  // OPERAZIONI FOLDER SEMPLIFICATE - 🔧 FIX: Supporto parentId completo
  // ============================================================================

  /// Carica tutte le cartelle dell'utente
  Future<List<Folder>> getFolders({bool forceRefresh = false}) async {
    try {
      if (kDebugMode)
        print(
            'DEBUG: Firebase - Inizio getFolders(forceRefresh: $forceRefresh)');
      // 1. Nostra cache in-memoria
      if (!forceRefresh && _isFolderCacheValid()) {
        if (kDebugMode) {
          print(
              'DEBUG: Firebase - Cache folders in-memory hit (${_cachedFolders!.length} items)');
        }
        return List<Folder>.from(_cachedFolders!);
      }

      // 2. Fetch da server
      final result = await _fetchFoldersFromServer();
      if (kDebugMode)
        print(
            'DEBUG: Firebase - getFolders completato con successo (${result.length} items)');
      return result;
    } on FirebaseException catch (e) {
      if (kDebugMode)
        print('ERRORE Firebase getFolders: ${e.code} - ${e.message}');

      if (_cachedFolders != null) {
        if (kDebugMode)
          print(
              'DEBUG: Firebase - Usando cache fallback (${_cachedFolders!.length} items)');
        return List<Folder>.from(_cachedFolders!);
      }

      throw FirebaseDataException(
          'Impossibile caricare le cartelle: ${e.message}',
          code: e.code,
          originalError: e);
    } catch (e) {
      if (kDebugMode) print('ERRORE generale getFolders: $e');

      if (_cachedFolders != null) {
        if (kDebugMode)
          print('DEBUG: Firebase - Usando cache fallback per errore generale');
        return List<Folder>.from(_cachedFolders!);
      }

      throw FirebaseDataException(
          'Errore durante il caricamento delle cartelle: $e');
    }
  }

  Future<List<Folder>> _fetchFoldersFromServer() async {
    if (kDebugMode)
      print(
          'DEBUG: Firebase - Caricando folders da Firestore... via await _foldersCollection.get()');

    final snapshot = await _foldersCollection.orderBy('createdAt').get();
    if (kDebugMode)
      print(
          'DEBUG: Firebase - _foldersCollection.get() completato con ${snapshot.docs.length} documenti');
    final folders = snapshot.docs
        .map((doc) => FolderFirestoreService.fromFirestore(doc))
        .toList();

    if (!folders.any((f) => f.isDefault)) {
      if (kDebugMode)
        print('DEBUG: Firebase - Cartella "Tutti" non trovata, creandola...');
      final defaultFolder = await _createDefaultFolder();
      folders.insert(0, defaultFolder);
    }

    _cachedFolders = folders;
    _lastFolderSync = DateTime.now();
    _cachedUserId = _auth.currentUser?.uid;

    if (kDebugMode)
      print(
          'DEBUG: Firebase - Caricate ${folders.length} folders con successo');
    return folders;
  }

  /// Crea una nuova cartella - 🔧 FIX: Aggiunto parametro parentId
  Future<Folder> createFolder({
    required String name,
    required String color,
    String? parentId, // 🔧 FIX: Aggiunto parametro parentId
    bool isShared = false, // 🆕 NUOVO: Indica se la cartella è condivisa
  }) async {
    try {
      if (kDebugMode)
        print(
            'DEBUG: Firebase - Creando folder: $name (parentId: $parentId, isShared: $isShared)');

      // Test connettività base prima di creare
      await testBasicConnectivity();

      // Valida parametri
      if (name.trim().isEmpty) {
        throw FirebaseDataException(
            'Il nome della cartella non può essere vuoto');
      }

      if (name.length > 100) {
        throw FirebaseDataException(
            'Il nome della cartella è troppo lungo (max 100 caratteri)');
      }

      // Verifica che non esista già una cartella con lo stesso nome nello stesso parent
      final existingFolders = await getFolders(
          forceRefresh: true); // FIX: Forza refresh per evitare falsi duplicati
      if (existingFolders.any((f) =>
          f.name.toLowerCase() == name.toLowerCase() &&
          !f.isDefault &&
          f.parentId == parentId)) {
        throw FirebaseDataException(
            'Esiste già una cartella con questo nome in questa posizione');
      }

      final now = DateTime.now();

      // Crea oggetto Folder temporaneo per conversione
      final tempFolder = Folder(
        id: '',
        name: name.trim(),
        color: color,
        createdAt: now,
        updatedAt: now,
        isDefault: false,
        parentId: parentId, // 🔧 FIX: Includi parentId
        isShared: isShared,
      );

      // Salva su Firestore
      final docRef =
          await _foldersCollection.add(tempFolder.toFirestoreService());

      // Crea oggetto Folder finale con ID generato
      final folder = Folder(
        id: docRef.id,
        name: name.trim(),
        color: color,
        createdAt: now,
        updatedAt: now,
        isDefault: false,
        parentId: parentId, // 🔧 FIX: Includi parentId
        isShared: isShared,
      );

      // Invalida cache per forzare ricaricamento
      _invalidateFolderCache();

      if (kDebugMode) {
        print(
            'DEBUG: Firebase - Folder creata con ID: ${docRef.id}, parentId: $parentId');
      }
      return folder;
    } on FirebaseException catch (e) {
      if (kDebugMode)
        print('ERRORE Firebase createFolder: ${e.code} - ${e.message}');
      throw FirebaseDataException(
          'Impossibile creare la cartella: ${e.message}',
          code: e.code,
          originalError: e);
    } catch (e) {
      if (e is FirebaseDataException) rethrow;
      if (kDebugMode) print('ERRORE generale createFolder: $e');
      throw FirebaseDataException(
          'Errore durante la creazione della cartella: $e');
    }
  }

  /// Aggiorna una cartella esistente
  Future<void> updateFolder(Folder folder) async {
    try {
      if (kDebugMode) {
        print(
            'DEBUG: Firebase - Aggiornando folder: ${folder.name} (ID: ${folder.id}, parentId: ${folder.parentId})');
      }

      if (folder.isDefault) {
        throw FirebaseDataException(
            'Non è possibile modificare la cartella "Tutti"');
      }

      final updateData =
          folder.copyWith(updatedAt: DateTime.now()).toFirestoreService();

      await _foldersCollection.doc(folder.id).update(updateData);

      // Invalida cache
      _invalidateFolderCache();

      if (kDebugMode) print('DEBUG: Firebase - Folder aggiornata con successo');
    } on FirebaseException catch (e) {
      if (kDebugMode)
        print('ERRORE Firebase updateFolder: ${e.code} - ${e.message}');
      throw FirebaseDataException(
          'Impossibile aggiornare la cartella: ${e.message}',
          code: e.code,
          originalError: e);
    } catch (e) {
      if (e is FirebaseDataException) rethrow;
      if (kDebugMode) print('ERRORE generale updateFolder: $e');
      throw FirebaseDataException(
          'Errore durante l\'aggiornamento della cartella: $e');
    }
  }

  /// Elimina una cartella e TUTTE le sue sottocartelle ricorsivamente
  Future<void> deleteFolder(String folderId) async {
    try {
      if (kDebugMode)
        print('DEBUG: Firebase - Eliminando folder ricorsivamente: $folderId');

      // Verifica che non sia la cartella default "Tutti"
      final folderDoc = await _foldersCollection.doc(folderId).get();
      if (!folderDoc.exists) {
        throw FirebaseDataException('Cartella non trovata');
      }

      final folderData = folderDoc.data();
      if (folderData?['isDefault'] == true) {
        throw FirebaseDataException(
            'Non è possibile eliminare la cartella "Tutti"');
      }

      final folderIdsToDelete = await _collectFolderTreeIds(folderId);

      // ✅ ELIMINA I POST NELLA CARTELLA E IN TUTTE LE SOTTOCARTELLE
      await _deletePostsInFolders(folderIdsToDelete);

      // ✅ ELIMINA RICORSIVAMENTE TUTTE LE SOTTOCARTELLE
      await _deleteSubfoldersRecursively(folderId);

      // ✅ ELIMINA LA CARTELLA PRINCIPALE
      await _foldersCollection.doc(folderId).delete();

      // Invalida cache cartelle e post: la cancellazione ora è completa.
      _invalidateFolderCache();
      _invalidatePostCache();

      if (kDebugMode) {
        print(
            'DEBUG: Firebase - Cartella, sottocartelle e post collegati eliminati');
      }
    } on FirebaseException catch (e) {
      if (kDebugMode)
        print('ERRORE Firebase deleteFolder: ${e.code} - ${e.message}');
      throw FirebaseDataException(
          'Impossibile eliminare la cartella: ${e.message}',
          code: e.code,
          originalError: e);
    } catch (e) {
      if (e is FirebaseDataException) rethrow;
      if (kDebugMode) print('ERRORE generale deleteFolder: $e');
      throw FirebaseDataException(
          'Errore durante l\'eliminazione della cartella: $e');
    }
  }

  Future<Set<String>> _collectFolderTreeIds(String rootFolderId) async {
    final ids = <String>{rootFolderId};
    var changed = true;

    while (changed) {
      changed = false;
      final snapshot = await _foldersCollection.get();
      for (final doc in snapshot.docs) {
        final parentId = (doc.data()['parentId'] as String?)?.trim();
        if (parentId != null && parentId.isNotEmpty && ids.contains(parentId)) {
          changed = ids.add(doc.id) || changed;
        }
      }
    }

    return ids;
  }

  Future<void> _deletePostsInFolders(Set<String> folderIds) async {
    for (final folderId in folderIds) {
      final snapshot =
          await _postsCollection.where('folderId', isEqualTo: folderId).get();
      if (snapshot.docs.isEmpty) continue;

      var batch = _firestore.batch();
      var count = 0;
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
        count++;
        if (count >= 450) {
          await batch.commit();
          batch = _firestore.batch();
          count = 0;
        }
      }
      if (count > 0) {
        await batch.commit();
      }
    }
  }

  // ============================================================================
  // OPERAZIONI POST
  // ============================================================================

  /// Carica tutti i post dell'utente, opzionalmente filtrati per cartella
  Future<List<SavedPost>> getPosts(
      {String? folderId, bool forceRefresh = false}) async {
    try {
      if (kDebugMode)
        print(
            'DEBUG: Firebase - Inizio getPosts(folderId: $folderId, forceRefresh: $forceRefresh)');
      // Controlla cache se non è richiesto refresh forzato
      if (!forceRefresh && _isPostCacheValid()) {
        if (kDebugMode) {
          print(
              'DEBUG: Firebase - Usando cache posts (${_cachedPosts!.length} items)');
        }
        var posts = List<SavedPost>.from(_cachedPosts!);

        if (folderId != null) {
          posts = posts.where((p) => p.folderId == folderId).toList();
        }

        return posts..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      if (kDebugMode)
        print(
            'DEBUG: Firebase - Caricando posts da Firestore... via query.get()');

      Query<Map<String, dynamic>> query = _postsCollection;

      if (folderId != null) {
        query = query.where('folderId', isEqualTo: folderId);
      }

      final snapshot = await query.orderBy('createdAt', descending: true).get();
      if (kDebugMode)
        print(
            'DEBUG: Firebase - query.get() completato con ${snapshot.docs.length} documenti');

      final posts = snapshot.docs
          .map((doc) => SavedPostFirestoreService.fromFirestore(doc))
          .toList();

      // Aggiorna cache solo se non filtrato
      if (folderId == null) {
        _cachedPosts = posts;
        _lastPostSync = DateTime.now();
        _cachedUserId = _auth.currentUser?.uid;
      }

      if (kDebugMode)
        print('DEBUG: Firebase - Caricati ${posts.length} posts con successo');
      return posts;
    } on FirebaseException catch (e) {
      if (kDebugMode)
        print('ERRORE Firebase getPosts: ${e.code} - ${e.message}');

      // Fallback alla cache se disponibile
      if (_cachedPosts != null && folderId == null) {
        if (kDebugMode) {
          print(
              'DEBUG: Firebase - Usando cache fallback (${_cachedPosts!.length} items)');
        }
        return List<SavedPost>.from(_cachedPosts!)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      throw FirebaseDataException('Impossibile caricare i post: ${e.message}',
          code: e.code, originalError: e);
    } catch (e) {
      if (kDebugMode) print('ERRORE generale getPosts: $e');
      throw FirebaseDataException('Errore durante il caricamento dei post: $e');
    }
  }

  Future<_GlobalPostResult> _ensureGlobalPost({
    required String url,
    required String title,
    required String description,
    String? imageUrl,
    String? previewStorageUrl,
    String? creatorName,
    String? creatorUsername,
  }) async {
    final callable = _functions.httpsCallable('ensureGlobalPost');
    final result = await callable.call<Map<String, dynamic>>({
      'post': {
        'url': url.trim(),
        'title': title.trim(),
        'description': description.trim(),
        'imageUrl': imageUrl?.trim(),
        'previewStorageUrl': previewStorageUrl?.trim(),
        'creatorName': creatorName?.trim(),
        'creatorUsername': creatorUsername?.trim(),
      },
    });
    final data = Map<String, dynamic>.from(result.data);
    final canonical = data['canonical'] is Map
        ? Map<String, dynamic>.from(data['canonical'] as Map)
        : <String, dynamic>{};

    return _GlobalPostResult(
      globalPostId: data['globalPostId']?.toString(),
      urlHash: data['urlHash']?.toString(),
      normalizedUrl: data['normalizedUrl']?.toString(),
      canonical: _GlobalPostCanonicalData.fromMap(canonical),
    );
  }

  /// Crea un nuovo post
  Future<SavedPost> createPost({
    required String url,
    required String title,
    required String description,
    String? imageUrl,
    String? previewStorageUrl,
    String? creatorName,
    String? creatorUsername,
    required List<String> tags,
    required String folderId,
    bool isShared = false,
  }) async {
    try {
      if (kDebugMode)
        print('DEBUG: Firebase - Creando post: $title (isShared: $isShared)');

      // Valida parametri
      if (title.trim().isEmpty) {
        throw FirebaseDataException('Il titolo del post non può essere vuoto');
      }

      if (url.trim().isEmpty) {
        throw FirebaseDataException('L\'URL del post non può essere vuoto');
      }

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        throw FirebaseDataException(
            'L\'URL deve iniziare con http:// o https://');
      }

      // Verifica che la cartella esista
      final folders = await getFolders();
      if (!folders.any((f) => f.id == folderId)) {
        throw FirebaseDataException('Cartella di destinazione non trovata');
      }

      final globalPost = await _ensureGlobalPost(
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        previewStorageUrl: previewStorageUrl,
        creatorName: creatorName,
        creatorUsername: creatorUsername,
      );
      final canonical = globalPost.canonical;
      final now = DateTime.now();

      // Crea oggetto SavedPost temporaneo per conversione
      final tempPost = SavedPost(
        id: '',
        url: canonical.url ?? url.trim(),
        title: canonical.title ?? title.trim(),
        description: canonical.description ?? description.trim(),
        imageUrl: canonical.imageUrl ?? imageUrl?.trim(),
        previewStorageUrl:
            canonical.previewStorageUrl ?? previewStorageUrl?.trim(),
        creatorName: canonical.creatorName ?? creatorName?.trim(),
        creatorUsername: canonical.creatorUsername ?? creatorUsername?.trim(),
        tags: tags.map((tag) => tag.trim()).toList(),
        folderId: folderId,
        createdAt: now,
        updatedAt: now,
        isShared: isShared,
        globalPostId: globalPost.globalPostId,
        urlHash: globalPost.urlHash,
        normalizedUrl: globalPost.normalizedUrl,
      );

      // Salva su Firestore
      final docRef = await _postsCollection.add(tempPost.toFirestoreService());

      // Crea oggetto SavedPost finale con ID generato
      final post = SavedPost(
        id: docRef.id,
        url: canonical.url ?? url.trim(),
        title: canonical.title ?? title.trim(),
        description: canonical.description ?? description.trim(),
        imageUrl: canonical.imageUrl ?? imageUrl?.trim(),
        previewStorageUrl:
            canonical.previewStorageUrl ?? previewStorageUrl?.trim(),
        creatorName: canonical.creatorName ?? creatorName?.trim(),
        creatorUsername: canonical.creatorUsername ?? creatorUsername?.trim(),
        tags: tags.map((tag) => tag.trim()).toList(),
        folderId: folderId,
        createdAt: now,
        updatedAt: now,
        isShared: isShared,
        globalPostId: globalPost.globalPostId,
        urlHash: globalPost.urlHash,
        normalizedUrl: globalPost.normalizedUrl,
      );

      // Invalida cache per forzare ricaricamento
      _invalidatePostCache();

      if (kDebugMode)
        print('DEBUG: Firebase - Post creato con ID: ${docRef.id}');
      return post;
    } on FirebaseException catch (e) {
      if (kDebugMode)
        print('ERRORE Firebase createPost: ${e.code} - ${e.message}');
      throw FirebaseDataException('Impossibile creare il post: ${e.message}',
          code: e.code, originalError: e);
    } catch (e) {
      if (e is FirebaseDataException) rethrow;
      if (kDebugMode) print('ERRORE generale createPost: $e');
      throw FirebaseDataException('Errore durante la creazione del post: $e');
    }
  }

  /// Aggiorna un post esistente
  Future<void> updatePost(SavedPost post) async {
    try {
      if (kDebugMode) {
        print(
            'DEBUG: Firebase - Aggiornando post: ${post.title} (ID: ${post.id})');
      }

      final updateData =
          post.copyWith(updatedAt: DateTime.now()).toFirestoreService();

      await _postsCollection.doc(post.id).update(updateData);

      // Invalida cache
      _invalidatePostCache();

      if (kDebugMode) print('DEBUG: Firebase - Post aggiornato con successo');
    } on FirebaseException catch (e) {
      if (kDebugMode)
        print('ERRORE Firebase updatePost: ${e.code} - ${e.message}');
      throw FirebaseDataException(
          'Impossibile aggiornare il post: ${e.message}',
          code: e.code,
          originalError: e);
    } catch (e) {
      if (e is FirebaseDataException) rethrow;
      if (kDebugMode) print('ERRORE generale updatePost: $e');
      throw FirebaseDataException(
          'Errore durante l\'aggiornamento del post: $e');
    }
  }

  /// Elimina un post
  Future<void> deletePost(String postId) async {
    try {
      if (kDebugMode) print('DEBUG: Firebase - Eliminando post: $postId');

      await _postsCollection.doc(postId).delete();

      // Invalida cache
      _invalidatePostCache();

      if (kDebugMode) print('DEBUG: Firebase - Post eliminato con successo');
    } on FirebaseException catch (e) {
      if (kDebugMode)
        print('ERRORE Firebase deletePost: ${e.code} - ${e.message}');
      throw FirebaseDataException('Impossibile eliminare il post: ${e.message}',
          code: e.code, originalError: e);
    } catch (e) {
      if (kDebugMode) print('ERRORE generale deletePost: $e');
      throw FirebaseDataException(
          'Errore durante l\'eliminazione del post: $e');
    }
  }

  // ============================================================================
  // STREAM REAL-TIME
  // ============================================================================

  /// Stream real-time delle cartelle dell'utente
  Stream<List<Folder>> foldersStream() {
    try {
      if (kDebugMode)
        print('DEBUG: Firebase - Inizializzando stream folders...');

      return _foldersCollection
          .orderBy('createdAt')
          .snapshots()
          .map((snapshot) {
        final folders = snapshot.docs
            .map((doc) => FolderFirestoreService.fromFirestore(doc))
            .toList();

        // Aggiorna cache
        _cachedFolders = folders;
        _lastFolderSync = DateTime.now();
        _cachedUserId = _auth.currentUser?.uid;

        if (kDebugMode) {
          print(
              'DEBUG: Firebase - Stream folders aggiornato: ${folders.length} items');
        }
        return folders;
      }).handleError((error) {
        if (kDebugMode) print('ERRORE Firebase foldersStream: $error');
      });
    } catch (e) {
      if (kDebugMode) print('ERRORE generale foldersStream: $e');
      throw FirebaseDataException(
          'Errore nell\'inizializzazione dello stream folders: $e');
    }
  }

  /// Stream real-time dei post dell'utente
  Stream<List<SavedPost>> postsStream({String? folderId}) {
    try {
      if (kDebugMode) {
        print(
            'DEBUG: Firebase - Inizializzando stream posts (folder: $folderId)...');
      }

      Query<Map<String, dynamic>> query = _postsCollection;

      if (folderId != null) {
        query = query.where('folderId', isEqualTo: folderId);
      }

      return query
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        final posts = snapshot.docs
            .map((doc) => SavedPostFirestoreService.fromFirestore(doc))
            .toList();

        // Aggiorna cache solo se non filtrato
        if (folderId == null) {
          _cachedPosts = posts;
          _lastPostSync = DateTime.now();
          _cachedUserId = _auth.currentUser?.uid;
        }

        if (kDebugMode) {
          print(
              'DEBUG: Firebase - Stream posts aggiornato: ${posts.length} items');
        }
        return posts;
      }).handleError((error) {
        if (kDebugMode) print('ERRORE Firebase postsStream: $error');
      });
    } catch (e) {
      if (kDebugMode) print('ERRORE generale postsStream: $e');
      throw FirebaseDataException(
          'Errore nell\'inizializzazione dello stream posts: $e');
    }
  }

  // ============================================================================
  // UTILITÀ E INIZIALIZZAZIONE
  // ============================================================================

  /// Inizializza i dati di default (cartella "Tutti")
  Future<void> initializeDefaultData() async {
    try {
      if (kDebugMode) print('DEBUG: Firebase - Inizializzando dati default...');

      final folders = await getFolders();

      if (!folders.any((f) => f.isDefault)) {
        if (kDebugMode)
          print('DEBUG: Firebase - Creando cartella default "Tutti"');
        await _createDefaultFolder();
      } else {
        if (kDebugMode)
          print('DEBUG: Firebase - Cartella "Tutti" già esistente');
      }
    } catch (e) {
      if (kDebugMode) print('ERRORE initializeDefaultData: $e');
      throw FirebaseDataException('Errore durante l\'inizializzazione: $e');
    }
  }

  /// Pulisce tutte le cache
  void clearCache() {
    if (kDebugMode) print('DEBUG: Firebase - Pulendo cache...');
    _cachedFolders = null;
    _cachedPosts = null;
    _lastFolderSync = null;
    _lastPostSync = null;
    _cachedUserId = null;
  }

  // ============================================================================
  // OPERAZIONI DI SHARING
  // ============================================================================

  /// Cerca un utente per email
  Future<Map<String, dynamic>?> findUserByEmail(String email) async {
    try {
      final rawEmail = email.trim();
      final normalizedEmail = rawEmail.toLowerCase();
      if (normalizedEmail.isEmpty) return null;

      try {
        final callable = _functions.httpsCallable('findShareRecipientByEmail');
        final response = await callable.call(<String, dynamic>{
          'email': rawEmail,
        });
        final data = Map<String, dynamic>.from(response.data as Map);
        return {
          'id': data['id']?.toString() ?? '',
          'name': data['name']?.toString() ?? 'Utente',
          'email': data['email']?.toString() ?? rawEmail,
        };
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'not-found') return null;
        if (kDebugMode) print('ERRORE findShareRecipientByEmail: $e');
      }

      final users = _firestore.collection('users');

      QueryDocumentSnapshot<Map<String, dynamic>>? match;

      for (final query in [
        users.where('normalizedEmail', isEqualTo: normalizedEmail).limit(1),
        users.where('emailLower', isEqualTo: normalizedEmail).limit(1),
        users.where('email_lower', isEqualTo: normalizedEmail).limit(1),
        users.where('email', isEqualTo: rawEmail).limit(1),
        users.where('email', isEqualTo: normalizedEmail).limit(1),
      ]) {
        final snapshot = await query.get();
        if (snapshot.docs.isNotEmpty) {
          match = snapshot.docs.first;
          break;
        }
      }

      if (match == null) {
        final legacySnapshot = await users.limit(1000).get();
        for (final doc in legacySnapshot.docs) {
          final candidateEmail =
              (doc.data()['email'] ?? doc.data()['normalizedEmail'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
          if (candidateEmail == normalizedEmail) {
            match = doc;
            break;
          }
        }
      }

      if (match == null) return null;

      final data = match.data();
      return {
        'id': match.id,
        'name': data['name'] ?? 'Utente',
        'email': data['email'] ?? email,
      };
    } catch (e) {
      if (kDebugMode) print('ERRORE findUserByEmail: $e');
      return null;
    }
  }

  /// Condivide un post o una cartella con un altro utente
  Future<void> shareItem({
    required String resourceId,
    required String type, // 'post' o 'folder'
    required String recipientId,
    required Map<String, dynamic> originalData,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('Utente non autenticato');

      final callable = _functions.httpsCallable('shareItemWithUser');
      await callable.call(<String, dynamic>{
        'resourceId': resourceId,
        'type': type,
        'recipientId': recipientId,
        'originalData': originalData,
      });

      if (kDebugMode)
        print('DEBUG: Item condiviso con successo con $recipientId');
    } on FirebaseFunctionsException catch (e) {
      final message = e.message ?? 'Errore durante la condivisione';
      if (kDebugMode) {
        print('ERRORE shareItem callable: ${e.code} - $message');
      }
      throw FirebaseDataException(message, code: e.code, originalError: e);
    } catch (e) {
      if (kDebugMode) print('ERRORE shareItem: $e');
      throw FirebaseDataException('Errore durante la condivisione: $e');
    }
  }

  /// Ottiene gli elementi condivisi con l'utente corrente
  Future<List<Map<String, dynamic>>> getSharedItems() async {
    try {
      final snapshot = await _sharedItemsCollection
          .orderBy('sharedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) print('ERRORE getSharedItems: $e');
      return [];
    }
  }

  /// Carica anteprima live di una condivisione diretta utente-utente.
  Future<Map<String, dynamic>> previewSharedResource({
    required String shareId,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('Utente non autenticato');

      final callable = _functions.httpsCallable('previewSharedResource');
      final response = await callable.call(<String, dynamic>{
        'shareId': shareId,
      });
      final data = Map<String, dynamic>.from(response.data as Map);
      final preview = data['preview'];
      if (preview is Map) {
        return Map<String, dynamic>.from(preview);
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final message = e.message ?? 'Errore durante il caricamento anteprima';
      if (kDebugMode) {
        print('ERRORE previewSharedResource callable: ${e.code} - $message');
      }
      throw FirebaseDataException(message, code: e.code, originalError: e);
    } catch (e) {
      if (kDebugMode) print('ERRORE previewSharedResource: $e');
      throw FirebaseDataException(
        'Errore durante il caricamento anteprima: $e',
      );
    }
  }

  /// Importa un elemento condiviso copiandolo direttamente dal Firestore
  /// dell'utente mittente tramite Cloud Function.
  Future<Map<String, dynamic>> importSharedResource({
    String? shareId,
    String? token,
    String? targetFolderId,
    String? targetParentFolderId,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('Utente non autenticato');

      final callable = _functions.httpsCallable('importSharedResource');
      final response = await callable.call(<String, dynamic>{
        if (shareId != null && shareId.trim().isNotEmpty) 'shareId': shareId,
        if (token != null && token.trim().isNotEmpty) 'token': token,
        if (targetFolderId != null && targetFolderId.trim().isNotEmpty)
          'targetFolderId': targetFolderId,
        if (targetParentFolderId != null &&
            targetParentFolderId.trim().isNotEmpty)
          'targetParentFolderId': targetParentFolderId,
      });

      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      final message = e.message ?? 'Errore durante l\'importazione';
      if (kDebugMode) {
        print('ERRORE importSharedResource callable: ${e.code} - $message');
      }
      throw FirebaseDataException(message, code: e.code, originalError: e);
    } catch (e) {
      if (kDebugMode) print('ERRORE importSharedResource: $e');
      throw FirebaseDataException('Errore durante l\'importazione: $e');
    }
  }

  /// Chiude tutti gli stream attivi
  void dispose() {
    if (kDebugMode) print('DEBUG: Firebase - Chiudendo stream...');
    _foldersController?.close();
    _postsController?.close();
    clearCache();
  }

  // ============================================================================
  // METODI PRIVATI
  // ============================================================================

  /// Crea la cartella default "Tutti"
  Future<Folder> _createDefaultFolder() async {
    final now = DateTime.now();

    final tempDefaultFolder = Folder(
      id: '',
      name: 'Tutti',
      color: '#BB86FC',
      createdAt: now,
      updatedAt: now,
      isDefault: true,
      parentId: null,
    );

    final docRef =
        await _foldersCollection.add(tempDefaultFolder.toFirestoreService());

    return Folder(
      id: docRef.id,
      name: 'Tutti',
      color: '#BB86FC',
      createdAt: now,
      updatedAt: now,
      isDefault: true,
      parentId: null,
    );
  }

  /// Elimina ricorsivamente tutte le sottocartelle
  Future<void> _deleteSubfoldersRecursively(String parentFolderId) async {
    try {
      if (kDebugMode)
        print('DEBUG: Cercando sottocartelle di $parentFolderId...');

      // ✅ LEGGI DIRETTAMENTE DA FIRESTORE (non dalla cache!)
      final subFoldersSnapshot = await _foldersCollection
          .where('parentId', isEqualTo: parentFolderId)
          .get();

      if (subFoldersSnapshot.docs.isEmpty) {
        if (kDebugMode)
          print('DEBUG: Nessuna sottocartella trovata per $parentFolderId');
        return;
      }

      if (kDebugMode) {
        print(
            'DEBUG: Trovate ${subFoldersSnapshot.docs.length} sottocartelle da eliminare');
      }

      // ✅ ELIMINA PARALLELAMENTE OGNI SOTTOCARTELLA
      final List<Future<void>> deletionFutures = [];

      for (var subFolderDoc in subFoldersSnapshot.docs) {
        final subFolderId = subFolderDoc.id;
        final subFolderName = subFolderDoc.data()['name'] ?? 'unnamed';

        // Aggiungi alla lista per esecuzione parallela
        deletionFutures.add(Future(() async {
          if (kDebugMode) {
            print(
                'DEBUG: Eliminando sottocartella: $subFolderName (ID: $subFolderId)');
          }

          // RICORSIONE: Elimina prima le SUE sottocartelle
          await _deleteSubfoldersRecursively(subFolderId);

          // Poi elimina questa sottocartella
          await _foldersCollection.doc(subFolderId).delete();

          if (kDebugMode)
            print('DEBUG: Sottocartella eliminata: $subFolderName');
        }));
      }

      // Attendi che tutte le eliminazioni siano completate
      if (deletionFutures.isNotEmpty) {
        await Future.wait(deletionFutures);
      }

      if (kDebugMode)
        print('DEBUG: Tutte le sottocartelle di $parentFolderId eliminate');
    } catch (e) {
      if (kDebugMode)
        print('ERRORE: Eliminazione ricorsiva sottocartelle fallita: $e');
      throw FirebaseDataException(
          'Errore durante l\'eliminazione delle sottocartelle: $e',
          originalError: e);
    }
  }

  /// Controlla se la cache folders è ancora valida (stessa UID e non scaduta)
  bool _isFolderCacheValid() {
    final uid = _auth.currentUser?.uid;
    return _cachedFolders != null &&
        _lastFolderSync != null &&
        _cachedUserId == uid &&
        DateTime.now().difference(_lastFolderSync!) < _cacheValidityDuration;
  }

  /// Controlla se la cache posts è ancora valida (stessa UID e non scaduta)
  bool _isPostCacheValid() {
    final uid = _auth.currentUser?.uid;
    return _cachedPosts != null &&
        _lastPostSync != null &&
        _cachedUserId == uid &&
        DateTime.now().difference(_lastPostSync!) < _cacheValidityDuration;
  }

  /// Invalida la cache folders
  void _invalidateFolderCache() {
    _cachedFolders = null;
    _lastFolderSync = null;
  }

  /// Invalida la cache posts
  void _invalidatePostCache() {
    _cachedPosts = null;
    _lastPostSync = null;
  }
}
