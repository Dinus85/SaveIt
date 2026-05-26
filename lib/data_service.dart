// lib/data_service.dart
// DataService con integrazione autenticazione Firebase - Fase 8 COMPLETATA
// FIX: Gestione corretta collezioni post vuote per nuovi utenti
// VERSIONE CORRETTA: Ritorna lista vuota invece di eccezione per collezioni vuote
// ðŸ”¥ AGGIUNTO: Sistema di callback per aggiornamento ottimistico UI
// ðŸ”§ FIX PARENTID: Aggiunto supporto completo per parentId nelle cartelle
// ðŸŽ¯ FIX CACHE VUOTA: Invalida cache posts vuota per forzare fetch Firebase

import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models.dart';
import 'services/firebase_data_service.dart';
import 'services/auth_service.dart';
import 'services/post_preview_cache.dart';
import 'services/post_preview_remote_storage.dart';

/// Exception per errori di autenticazione
class AuthenticationRequiredException implements Exception {
  final String message;

  AuthenticationRequiredException(this.message);

  @override
  String toString() => 'AuthenticationRequiredException: $message';
}

/// Exception per operazioni offline
class OfflineOperationException implements Exception {
  final String message;
  final dynamic originalError;

  OfflineOperationException(this.message, {this.originalError});

  @override
  String toString() => 'OfflineOperationException: $message';
}

/// Risultato sintetico del backup anteprime su remoto.
class PreviewBackupResult {
  final int totalInstagramPosts;
  final int scanned;
  final int skipped;
  final int uploaded;
  final int updated;
  final int failed;

  const PreviewBackupResult({
    required this.totalInstagramPosts,
    required this.scanned,
    required this.skipped,
    required this.uploaded,
    required this.updated,
    required this.failed,
  });
}

/// ðŸ†• NUOVO: Tipo di callback per notifiche UI
typedef DataChangeCallback = void Function(
    String changeType, Map<String, dynamic> changeData);

/// DataService FINALE ottimizzato per performance multi-utente
/// FASE 8: Eliminata dipendenza SharedPreferences, solo Firebase
/// ðŸ”¥ AGGIUNTO: Sistema di callback per aggiornamento ottimistico
class DataService {
  static const String _defaultFolderId = 'all_folder';

  static DataService? _instance;
  static DataService get instance {
    _instance ??= DataService._();
    return _instance!;
  }

  DataService._();

  // Services dependencies
  final FirebaseDataService _firebaseService = FirebaseDataService();
  final AuthService _authService = AuthService();

  // Cache multi-utente ottimizzata
  final Map<String, List<Folder>> _userFoldersCache = {};
  final Map<String, List<SavedPost>> _userPostsCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheValidityDuration = Duration(minutes: 3);

  // 🔥 NUOVO: Gestione richieste in corso (Request Collapsing)
  final Map<String, Future<List<Folder>>> _foldersInFlight = {};
  final Map<String, Future<List<SavedPost>>> _postsInFlight = {};

  // ðŸ†• NUOVO: Sistema di callback per notificare cambiamenti all'UI
  final List<DataChangeCallback> _dataChangeCallbacks = [];

  /// ðŸ†• NUOVO: Registra callback per ricevere notifiche di cambiamenti dati
  void registerDataChangeCallback(DataChangeCallback callback) {
    if (!_dataChangeCallbacks.contains(callback)) {
      _dataChangeCallbacks.add(callback);
      if (kDebugMode) {
        print(
            'DEBUG: DataService - Callback registrato (${_dataChangeCallbacks.length} totali)');
      }
    }
  }

  /// ðŸ†• NUOVO: Rimuove callback registrato
  void unregisterDataChangeCallback(DataChangeCallback callback) {
    _dataChangeCallbacks.remove(callback);
    if (kDebugMode) {
      print(
          'DEBUG: DataService - Callback rimosso (${_dataChangeCallbacks.length} rimasti)');
    }
  }

  /// ðŸ†• NUOVO: Notifica tutti i callback registrati di un cambiamento
  void _notifyDataChange(String changeType, Map<String, dynamic> changeData) {
    if (kDebugMode) {
      print(
          'DEBUG: DataService - Notificando ${_dataChangeCallbacks.length} callback: $changeType');
    }

    for (final callback in _dataChangeCallbacks) {
      try {
        callback(changeType, changeData);
      } catch (e) {
        if (kDebugMode) print('ERRORE: Callback DataService fallito: $e');
      }
    }
  }

  /// Ottiene l'ID dell'utente corrente autenticato
  String? get currentUserId {
    try {
      final user = _authService.currentUser;
      return user?.id;
    } catch (e) {
      if (kDebugMode) print('DEBUG: Errore ottenimento currentUserId: $e');
      return null;
    }
  }

  /// Verifica se l'utente Ã¨ autenticato
  bool get isUserAuthenticated {
    return _authService.isLoggedIn && currentUserId != null;
  }

  /// Verifica autenticazione con context utente E DEBUG FIREBASE SEMPLIFICATO
  void _requireAuthentication() {
    final isAuth = _authService.isLoggedIn;
    final currentUserFromAuth = _authService.currentUser;
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (kDebugMode) {
      print('========== DEBUG AUTENTICAZIONE ==========');
      print('DEBUG AUTH: AuthService logged in: $isAuth');
      print('DEBUG AUTH: AuthService currentUser: ${currentUserFromAuth?.id}');
      print('DEBUG AUTH: AuthService email: ${currentUserFromAuth?.email}');
      print('DEBUG AUTH: Firebase Auth currentUser: ${firebaseUser?.uid}');
      print('DEBUG AUTH: Firebase Auth email: ${firebaseUser?.email}');
      print(
          'DEBUG AUTH: User tokens match: ${currentUserFromAuth?.id == firebaseUser?.uid}');
      print('DEBUG AUTH: Firebase token exists: ${firebaseUser != null}');
      print('=========================================');
    }

    if (!isUserAuthenticated) {
      throw AuthenticationRequiredException(
          'Operazione richiede autenticazione. Firebase UID: ${firebaseUser?.uid}, AuthService: $isAuth');
    }
  }

  /// Cache multi-utente intelligente
  bool _isUserCacheValid(String userId) {
    final timestamp = _cacheTimestamps[userId];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheValidityDuration;
  }

  // Cache posts valida solo se esiste, non è vuota e il timestamp è valido
  bool _isPostsCacheValid(String userId) {
    final posts = _userPostsCache[userId];
    if (posts == null || posts.isEmpty) return false;
    return _isUserCacheValid(userId);
  }

  // Cache folders valida solo se esiste e il timestamp è valido.
  // Il caricamento dei post aggiorna lo stesso timestamp utente, quindi
  // getFolders non deve considerare valida una cache cartelle mai popolata.
  bool _isFoldersCacheValid(String userId) {
    final folders = _userFoldersCache[userId];
    if (folders == null || folders.isEmpty) return false;
    return _isUserCacheValid(userId);
  }

  void _updateUserCache(
      String userId, List<Folder>? folders, List<SavedPost>? posts) {
    if (folders != null) _userFoldersCache[userId] = List.from(folders);
    if (posts != null) _userPostsCache[userId] = List.from(posts);
    _cacheTimestamps[userId] = DateTime.now();
  }

  void _clearUserCache(String? userId) {
    if (userId != null) {
      _userFoldersCache.remove(userId);
      _userPostsCache.remove(userId);
      _cacheTimestamps.remove(userId);
    }
  }

  /// ðŸ†• NUOVO: Aggiorna cache aggiungendo un post specifico (per aggiornamento ottimistico)
  void addPostToCache(SavedPost post) {
    final userId = currentUserId;
    if (userId == null) return;

    if (kDebugMode) {
      print('DEBUG: DataService - Aggiungendo post alla cache: ${post.title}');
    }

    // Aggiorna cache posts se esiste
    if (_userPostsCache.containsKey(userId)) {
      final currentPosts = List<SavedPost>.from(_userPostsCache[userId]!);

      // Rimuovi post esistente con stesso ID (se presente)
      currentPosts.removeWhere((p) => p.id == post.id);

      // Aggiungi nuovo post in cima (piÃ¹ recente)
      currentPosts.insert(0, post);

      _userPostsCache[userId] = currentPosts;
      _cacheTimestamps[userId] = DateTime.now();

      if (kDebugMode) {
        print(
            'DEBUG: DataService - Post aggiunto alla cache. Totale: ${currentPosts.length}');
      }

      // ðŸ†• Notifica il cambiamento
      _notifyDataChange('post_added', {
        'postId': post.id,
        'postTitle': post.title,
        'folderId': post.folderId,
        'userId': userId,
        'cacheSize': currentPosts.length,
      });
    }
  }

  /// ðŸ†• NUOVO: Rimuove post specifico dalla cache (per eliminazioni)
  void removePostFromCache(String postId) {
    final userId = currentUserId;
    if (userId == null) return;

    if (kDebugMode) {
      print('DEBUG: DataService - Rimuovendo post dalla cache: $postId');
    }

    if (_userPostsCache.containsKey(userId)) {
      final currentPosts = List<SavedPost>.from(_userPostsCache[userId]!);
      final initialSize = currentPosts.length;

      currentPosts.removeWhere((p) => p.id == postId);

      if (currentPosts.length < initialSize) {
        _userPostsCache[userId] = currentPosts;
        _cacheTimestamps[userId] = DateTime.now();

        if (kDebugMode) {
          print(
              'DEBUG: DataService - Post rimosso dalla cache. Totale: ${currentPosts.length}');
        }

        // ðŸ†• Notifica il cambiamento
        _notifyDataChange('post_removed', {
          'postId': postId,
          'userId': userId,
          'cacheSize': currentPosts.length,
        });
      }
    }
  }

  /// ðŸ†• NUOVO: Aggiorna cache aggiungendo una cartella specifica (per aggiornamento ottimistico)
  void addFolderToCache(Folder folder) {
    final userId = currentUserId;
    if (userId == null) return;

    if (kDebugMode) {
      print(
          'DEBUG: DataService - Aggiungendo cartella alla cache: ${folder.name}');
    }

    if (_userFoldersCache.containsKey(userId)) {
      final currentFolders = List<Folder>.from(_userFoldersCache[userId]!);

      // Rimuovi cartella esistente con stesso ID (se presente)
      currentFolders.removeWhere((f) => f.id == folder.id);

      // Aggiungi nuova cartella
      currentFolders.add(folder);

      // Riordina: cartelle default sempre prime
      currentFolders.sort((a, b) {
        if (a.isDefault) return -1;
        if (b.isDefault) return 1;
        return a.name.compareTo(b.name);
      });

      _userFoldersCache[userId] = currentFolders;
      _cacheTimestamps[userId] = DateTime.now();

      if (kDebugMode) {
        print(
            'DEBUG: DataService - Cartella aggiunta alla cache. Totale: ${currentFolders.length}');
      }

      // ðŸ†• Notifica il cambiamento
      _notifyDataChange('folder_added', {
        'folderId': folder.id,
        'folderName': folder.name,
        'isDefault': folder.isDefault,
        'parentId': folder.parentId,
        'userId': userId,
        'cacheSize': currentFolders.length,
      });
    }
  }

  /// ðŸ†• NUOVO: Invalida cache specifica per forzare reload
  void invalidateCache({bool folders = false, bool posts = false}) {
    final userId = currentUserId;
    if (userId == null) return;

    if (kDebugMode) {
      print(
          'DEBUG: DataService - Invalidando cache (folders: $folders, posts: $posts)');
    }

    if (folders) {
      _userFoldersCache.remove(userId);
    }

    if (posts) {
      _userPostsCache.remove(userId);
    }

    if (folders || posts) {
      _cacheTimestamps.remove(userId);

      // Pulisci anche cache FirebaseDataService
      _firebaseService.clearCache();
    }
  }

  /// Operazione con cache multi-utente e TEST CONNETTIVITÃ€ SEMPLIFICATO
  Future<T> _executeWithOptimizedCache<T>(
    Future<T> Function() firebaseOperation,
    T Function()? cacheOperation,
    String operationName, {
    bool allowCache = true,
  }) async {
    // Verifica autenticazione prima di qualsiasi operazione
    _requireAuthentication();

    final userId = currentUserId!;

    try {
      if (kDebugMode) {
        print(
            'DEBUG: DataService - Eseguendo $operationName (userId: $userId)');
      }

      // FIX: TEST CONNETTIVITÃ€ SEMPLIFICATO - RIMOSSO TEST AGGRESSIVO
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          throw Exception('Firebase Auth: Utente non autenticato');
        }
      } catch (connectivityError) {
        if (kDebugMode) {
          print('DEBUG: ⚠️ Test connettività base FALLITO: $connectivityError');
        }

        if (connectivityError.toString().contains('permission-denied')) {
          throw AuthenticationRequiredException(
              'Firebase regole negano accesso: $connectivityError');
        }

        // Se siamo offline e abbiamo un'operazione cache, usiamola subito senza tentare Firebase
        if (cacheOperation != null) {
          if (kDebugMode)
            print(
                'DEBUG: 🌐 Offline rilevato, uso cache immediata per $operationName');
          return cacheOperation();
        }

        throw OfflineOperationException(
            'Firebase non raggiungibile e nessuna cache disponibile: $connectivityError');
      }

      // FIX: Cache solo per operazioni di lettura
      if (allowCache && cacheOperation != null && _isUserCacheValid(userId)) {
        if (kDebugMode)
          print('DEBUG: DataService - Cache hit per utente $userId');
        return cacheOperation();
      }

      // Esegui operazione Firebase (sempre per operazioni di scrittura)
      if (kDebugMode) print('DEBUG: DataService - Eseguendo firebaseOperation() per $operationName');
      final result = await firebaseOperation();
      if (kDebugMode) print('DEBUG: DataService - firebaseOperation() completata per $operationName');
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('========== ERRORE IN $operationName ==========');
        print('ERRORE: $e');
        if (e is FirebaseException) {
          print('FIREBASE CODE: ${e.code}');
        }
        print('=====================================');
      }

      // Fallback intelligente cache multi-utente
      if (cacheOperation != null) {
        if (kDebugMode)
          print(
              'DEBUG: DataService - Usando cache utente come fallback per $operationName');
        try {
          return cacheOperation();
        } catch (fallbackError) {
          if (kDebugMode) {
            print(
                'ERRORE: Anche cache fallback fallita per $operationName: $fallbackError');
          }
        }
      }

      // Gestione errori specifici
      if (e.toString().contains('user_not_authenticated')) {
        throw AuthenticationRequiredException(
            'Sessione scaduta. Effettua nuovamente il login.');
      }

      if (e.toString().contains('permission-denied')) {
        throw AuthenticationRequiredException(
            'Regole Firebase negano accesso. Verifica configurazione Firestore.');
      }

      throw OfflineOperationException(
          'Operazione $operationName non disponibile offline: ${e.toString()}',
          originalError: e);
    }
  }

  // ====== INIZIALIZZAZIONE OTTIMIZZATA ======

  /// Initialize default folder if not exists - FASE 8 OTTIMIZZATA
  Future<void> initializeDefaultData() async {
    try {
      _requireAuthentication();

      final userId = currentUserId!;
      if (kDebugMode) {
        print(
            'DEBUG: DataService - Inizializzando dati default per utente: $userId');
      }

      await _firebaseService.initializeDefaultData();
    } on AuthenticationRequiredException {
      if (kDebugMode) {
        print(
            'WARNING: DataService - Inizializzazione dati richiede autenticazione');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) print('ERRORE: DataService initializeDefaultData: $e');
      throw Exception('Errore inizializzazione dati default: $e');
    }
  }

  // ====== OPERAZIONI FOLDER OTTIMIZZATE ======

  /// Get folders con cache multi-utente ottimizzata
  Future<List<Folder>> getFolders({bool forceRefresh = false}) async {
    final userId = currentUserId!;

    // 🔥 Request Collapsing: se c'è già una richiesta identica in corso, restituisci quella
    final requestKey = '${userId}_$forceRefresh';
    if (_foldersInFlight.containsKey(requestKey)) {
      if (kDebugMode) {
        print('DEBUG: DataService - Richiesta folders già in corso, accodo...');
      }
      return _foldersInFlight[requestKey]!;
    }

    final folderFuture = _executeWithOptimizedCache<List<Folder>>(
        () async {
          if (kDebugMode) print('DEBUG: DataService - Chiamando _firebaseService.getFolders()');
          final folders =
              await _firebaseService.getFolders(forceRefresh: forceRefresh);
          if (kDebugMode) print('DEBUG: DataService - _firebaseService.getFolders() ritornato ${folders.length} cartelle');
          
          // Aggiorna cache multi-utente
          _updateUserCache(userId, folders, null);

          // Ordina: cartelle default sempre prime
          folders.sort((a, b) {
            if (a.isDefault) return -1;
            if (b.isDefault) return 1;
            return a.name.compareTo(b.name);
          });

          if (kDebugMode) {
            print(
                'DEBUG: DataService - Caricate ${folders.length} cartelle per utente: $userId');
          }
          return folders;
        },
        () {
          // Cache operation
          final cachedFolders = _userFoldersCache[userId];
          if (cachedFolders != null) {
            if (kDebugMode) {
              print(
                  'DEBUG: DataService - Cache folders hit per utente $userId (${cachedFolders.length} items)');
            }
            return List.from(cachedFolders);
          }

          if (kDebugMode) {
            print('DEBUG: ℹ️ Nessuna cache cartelle, ritorno lista vuota');
          }
          return <Folder>[];
        },
        'getFolders',
        allowCache: !forceRefresh && _isFoldersCacheValid(userId),
      )
    .whenComplete(() { _foldersInFlight.remove(requestKey); });

    _foldersInFlight[requestKey] = folderFuture;
    return folderFuture;
  }

  /// Save folder ottimizzato - ðŸ”§ FIX: Aggiunto supporto parentId
  Future<void> saveFolder(Folder folder) async {
    await _executeWithOptimizedCache<void>(
      () async {
        final userId = currentUserId!;
        if (kDebugMode) {
          print(
              'DEBUG: DataService (FASE 8) - Salvando cartella: ${folder.name} per utente: $userId');
        }

        if (folder.id.isEmpty) {
          await _firebaseService.createFolder(
            name: folder.name,
            color: folder.color,
            parentId: folder.parentId, // 🔧 FIX: Passa parentId
          );

          // La creazione produce un nuovo ID: meglio invalidare la cache per un reload sicuro
          _clearUserCache(userId);
        } else {
          await _firebaseService.updateFolder(folder);

          // Aggiorna la cache locale se presente, evitando un reload completo
          if (_userFoldersCache.containsKey(userId)) {
            final currentFolders =
                List<Folder>.from(_userFoldersCache[userId]!);
            final folderIndex =
                currentFolders.indexWhere((f) => f.id == folder.id);

            if (folderIndex != -1) {
              currentFolders[folderIndex] = folder;

              currentFolders.sort((a, b) {
                if (a.isDefault) return -1;
                if (b.isDefault) return 1;
                return a.name.compareTo(b.name);
              });

              _userFoldersCache[userId] = currentFolders;
              _cacheTimestamps[userId] = DateTime.now();

              if (kDebugMode)
                print('DEBUG: Cache cartelle aggiornata dopo salvataggio');
            } else {
              // Entry non trovata: fallback su invalidazione cache
              _clearUserCache(userId);
            }
          } else {
            _clearUserCache(userId);
          }
        }

        if (kDebugMode) {
          print(
              'DEBUG: DataService (FASE 8) - Cartella salvata: ${folder.name} per utente: $userId');
        }
      },
      () {
        throw OfflineOperationException(
            'Salvataggio cartelle richiede connessione internet');
      },
      'saveFolder',
      allowCache: false,
    );
  }

  /// Create folder ottimizzato con ATTESA propagazione Firestore
  Future<Folder> createFolder({
    required String name,
    required String color,
    String? parentId,
    bool isShared = false, // 🆕 NUOVO
  }) async {
    return await _executeWithOptimizedCache<Folder>(
      () async {
        final userId = currentUserId!;
        if (kDebugMode) {
          print(
              'DEBUG: DataService (FASE 8) - Creando cartella: $name per utente: $userId (parentId: $parentId, isShared: $isShared)');
        }

        // STEP 1: Crea la cartella
        final folder = await _firebaseService.createFolder(
          name: name,
          color: color,
          parentId: parentId,
          isShared: isShared,
        );

        if (kDebugMode) print('DEBUG: Cartella creata con ID: ${folder.id}');

        // STEP 2: ATTENDI che Firestore propaghi i dati
        if (kDebugMode) print('DEBUG: Attendendo propagazione Firestore...');
        await _waitForFolderPropagation(folder.id, maxAttempts: 5);

        // STEP 3: Solo DOPO la propagazione, invalida cache
        _clearUserCache(userId);
        _firebaseService.clearCache();

        // STEP 4: Notifica il cambiamento (ora i dati sono disponibili)
        _notifyDataChange('folder_added', {
          'folderId': folder.id,
          'folderName': folder.name,
          'isDefault': folder.isDefault,
          'parentId': folder.parentId,
          'userId': userId,
        });

        if (kDebugMode) {
          print(
              'DEBUG: DataService (FASE 8) - Cartella creata e verificata: ${folder.name} (ID: ${folder.id})');
        }
        return folder;
      },
      () {
        throw OfflineOperationException(
            'Creazione cartelle richiede connessione internet');
      },
      'createFolder',
      allowCache: false,
    );
  }

  /// ðŸ†• NUOVO: Aspetta che la cartella sia effettivamente disponibile in Firestore
  Future<void> _waitForFolderPropagation(String folderId,
      {int maxAttempts = 5}) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (kDebugMode) {
          print(
              'DEBUG: Verifica propagazione cartella (tentativo $attempt/$maxAttempts)...');
        }

        // Forza ricaricamento da Firestore (bypass cache)
        _firebaseService.clearCache();
        final folders = await _firebaseService.getFolders(forceRefresh: true);

        // Cerca la cartella appena creata
        final found = folders.any((f) => f.id == folderId);

        if (found) {
          if (kDebugMode) {
            print(
                'DEBUG: âœ… Cartella propagata correttamente (tentativo $attempt)');
          }
          return;
        }

        if (kDebugMode)
          print('DEBUG: â³ Cartella non ancora disponibile, retry...');
        await Future.delayed(
            Duration(milliseconds: 300 * attempt)); // Backoff progressivo
      } catch (e) {
        if (kDebugMode)
          print('DEBUG: Errore verifica propagazione (tentativo $attempt): $e');
        if (attempt == maxAttempts) {
          if (kDebugMode) {
            print(
                'WARNING: Propagazione non confermata dopo $maxAttempts tentativi');
          }
          return; // Procedi comunque
        }
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  /// Delete folder con eliminazione ricorsiva di tutte le sottocartelle
  Future<void> deleteFolder(String folderId) async {
    await _executeWithOptimizedCache<void>(
      () async {
        final userId = currentUserId!;
        if (kDebugMode) {
          print(
              'DEBUG: DataService - Eliminando cartella ricorsivamente: $folderId per utente: $userId');
        }

        // STEP 1: Elimina cartella e sottocartelle (gestito in FirebaseDataService)
        await _firebaseService.deleteFolder(folderId);

        // STEP 2: Breve attesa per propagazione eliminazione
        await Future.delayed(Duration(milliseconds: 300));

        // STEP 3: ⭐ FIX ANTEPRIME: Invalida ANCHE i post per mantenere sincronizzazione!
        if (kDebugMode)
          print('DEBUG: Invalidando cache folders E posts per sicurezza');
        invalidateCache(folders: true, posts: true);

        // STEP 4: Ricarica cartelle E posts usando i metodi DataService (non _firebaseService diretto)
        // ⭐ FIX: Chiamare getFolders/getPosts di DataService per aggiornare la cache corretta
        // Dato che abbiamo appena invalidato la cache, queste chiamate caricheranno da Firebase
        if (kDebugMode) {
          print(
              'DEBUG: Ricaricando cartelle e posts dopo eliminazione ricorsiva...');
        }

        final loadedFolders = await getFolders();
        if (kDebugMode) {
          print(
              'DEBUG: getFolders() completato - caricati ${loadedFolders.length} folders');
          print(
              'DEBUG: _userFoldersCache contiene: ${_userFoldersCache[userId]?.length ?? 0} folders');
        }

        final loadedPosts = await getPosts();
        if (kDebugMode) {
          print(
              'DEBUG: getPosts() completato - caricati ${loadedPosts.length} posts');
          print(
              'DEBUG: _userPostsCache contiene: ${_userPostsCache[userId]?.length ?? 0} posts');
        }

        // âœ… Sia folders che posts vengono ricaricati per evitare inconsistenze
        if (kDebugMode) {
          print(
              'DEBUG: Cache folders e posts ricaricate: ${_userPostsCache[userId]?.length ?? 0} post');
        }

        // STEP 5: Notifica il cambiamento
        _notifyDataChange('folder_deleted', {
          'folderId': folderId,
          'userId': userId,
        });

        if (kDebugMode) {
          print(
              'DEBUG: DataService - Cartella e sottocartelle eliminate ricorsivamente: $folderId');
        }
      },
      () {
        throw OfflineOperationException(
            'Eliminazione cartelle richiede connessione internet');
      },
      'deleteFolder',
      allowCache: false,
    );
  }
  // ====== OPERAZIONI POST OTTIMIZZATE CON FIX COLLEZIONI VUOTE ======

  /// Get posts con gestione collezioni vuote - FIX CACHE VUOTA MIGLIORATO
  Future<List<SavedPost>> getPosts({String? folderId}) async {
    final userId = currentUserId!;
    final allowCache = _isPostsCacheValid(userId);

    // 🔥 Request Collapsing: se c'è già una richiesta identica in corso, restituisci quella
    final requestKey = '${userId}_${folderId ?? "all"}';
    if (_postsInFlight.containsKey(requestKey)) {
      if (kDebugMode) {
        print(
            'DEBUG: DataService - Richiesta posts già in corso per $folderId, accodo...');
      }
      return _postsInFlight[requestKey]!;
    }

    final postFuture = _executeWithOptimizedCache<List<SavedPost>>(
        () async {
          try {
            if (kDebugMode) print('DEBUG: DataService - Chiamando _firebaseService.getPosts(folderId: $folderId)');
            // FIX: Chiamata Firebase con gestione collezione vuota
            final posts = await _firebaseService.getPosts(folderId: folderId);
            if (kDebugMode) print('DEBUG: DataService - _firebaseService.getPosts() ritornato ${posts.length} post');

            // Aggiorna cache solo se non filtrato
            if (folderId == null) {
              _updateUserCache(userId, null, posts);
            }

            posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            if (kDebugMode) {
              print(
                  'DEBUG: DataService - Caricati ${posts.length} posts per utente: $userId');
            }

            return posts;
          } catch (e) {
            if (kDebugMode) print('DEBUG: Errore Firebase posts: $e');

            // FIX: Gestisci collezione vuota o non esistente
            if (_isEmptyCollectionError(e)) {
              if (kDebugMode) {
                print(
                    'DEBUG: Collezione posts vuota o non esistente - restituendo lista vuota');
              }
              final emptyPosts = <SavedPost>[];

              // Aggiorna cache con lista vuota
              if (folderId == null) {
                _updateUserCache(userId, null, emptyPosts);
              }

              return emptyPosts;
            }

            // Re-lancia altri tipi di errore
            rethrow;
          }
        },
        () {
          // 🔥 FIX PRINCIPALE: Cache operation migliorata
          final cachedPosts = _userPostsCache[userId];

          // Se non c'è cache, ritorna lista vuota invece di lanciare eccezione
          if (cachedPosts == null || cachedPosts.isEmpty) {
            if (kDebugMode) {
              print('DEBUG: ℹ️ Nessuna cache post, ritorno lista vuota');
            }
            return <SavedPost>[];
          }

          var posts = List<SavedPost>.from(cachedPosts);

          if (folderId != null) {
            posts = posts.where((p) => p.folderId == folderId).toList();
          }

          posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (kDebugMode) {
            print(
                'DEBUG: DataService - Cache posts hit per utente $userId (${posts.length} items)');
          }
          return posts;
        },
        'getPosts',
        allowCache: allowCache,
      )
    .whenComplete(() { _postsInFlight.remove(requestKey); });

    _postsInFlight[requestKey] = postFuture;
    return postFuture;
  }

  /// Metodo helper per identificare errori di collezione vuota
  bool _isEmptyCollectionError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('not found') ||
        errorString.contains('does not exist') ||
        errorString.contains('collection not found') ||
        errorString.contains('no documents') ||
        (error is FirebaseException &&
            (error.code == 'not-found' || error.code == 'permission-denied'));
  }

  /// Search posts ottimizzato
  Future<List<SavedPost>> searchPosts(String query) async {
    return await _executeWithOptimizedCache<List<SavedPost>>(() async {
      final userId = currentUserId!;
      if (kDebugMode) {
        print(
            'DEBUG: DataService (FASE 8) - Ricerca post per: "$query" per utente: $userId');
      }

      final allPosts = await getPosts();
      final searchQuery = query.toLowerCase();

      final filteredPosts = allPosts.where((post) {
        final titleMatch = post.title.toLowerCase().contains(searchQuery);
        final descriptionMatch =
            post.description.toLowerCase().contains(searchQuery);
        final tagsMatch =
            post.tags.any((tag) => tag.toLowerCase().contains(searchQuery));

        return titleMatch || descriptionMatch || tagsMatch;
      }).toList();

      if (kDebugMode) {
        print(
            'DEBUG: DataService (FASE 8) - Trovati ${filteredPosts.length} post per ricerca');
      }
      return filteredPosts;
    }, () {
      // Ricerca in cache
      final userId = currentUserId!;
      final cachedPosts = _userPostsCache[userId];
      if (cachedPosts != null) {
        final searchQuery = query.toLowerCase();
        final filteredPosts = cachedPosts.where((post) {
          final titleMatch = post.title.toLowerCase().contains(searchQuery);
          final descriptionMatch =
              post.description.toLowerCase().contains(searchQuery);
          final creatorMatch =
              (post.creatorName?.toLowerCase().contains(searchQuery) ??
                      false) ||
                  (post.creatorUsername?.toLowerCase().contains(searchQuery) ??
                      false);
          final tagsMatch =
              post.tags.any((tag) => tag.toLowerCase().contains(searchQuery));

          return titleMatch || descriptionMatch || creatorMatch || tagsMatch;
        }).toList();

        if (kDebugMode) {
          print(
              'DEBUG: DataService - Ricerca cache trovato ${filteredPosts.length} post');
        }
        return filteredPosts;
      }

      if (kDebugMode)
        print('DEBUG: Ricerca cache fallita - restituendo lista vuota');
      return <SavedPost>[];
    }, 'searchPosts');
  }

  /// Save post ottimizzato
  Future<void> savePost(SavedPost post) async {
    await _executeWithOptimizedCache<void>(
      () async {
        final userId = currentUserId!;
        var savedPost = post;
        print(
            'DEBUG: DataService (FASE 8) - Salvando post: ${post.title} per utente: $userId');

        if (post.id.isEmpty) {
          savedPost = await _firebaseService.createPost(
            url: post.url,
            title: post.title,
            description: post.description,
            imageUrl: post.imageUrl,
            creatorName: post.creatorName,
            creatorUsername: post.creatorUsername,
            tags: post.tags,
            folderId: post.folderId,
          );
        } else {
          await _firebaseService.updatePost(post);
        }

        // 🔥 Aggiorna cache in-place per evitare flicker e reload pesanti
        addPostToCache(savedPost);

        // 🔥 NUOVO: Cache persistente anteprima (in background, non blocca)
        _cachePostPreviewInBackground(savedPost);

        print(
            'DEBUG: DataService (FASE 8) - Post salvato: ${post.title} per utente: $userId');
      },
      () {
        throw OfflineOperationException(
            'Salvataggio post richiede connessione internet');
      },
      'savePost',
      allowCache: false,
    );
  }

  /// Create post ottimizzato - ðŸ”¥ AGGIORNATO PER AGGIORNAMENTO OTTIMISTICO
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
    return await _executeWithOptimizedCache<SavedPost>(
      () async {
        final userId = currentUserId!;
        print(
            'DEBUG: DataService (FASE 8) - Creando post: $title per utente: $userId (isShared: $isShared)');

        final post = await _firebaseService.createPost(
          url: url,
          title: title,
          description: description,
          imageUrl: imageUrl,
          previewStorageUrl: previewStorageUrl,
          creatorName: creatorName,
          creatorUsername: creatorUsername,
          tags: tags,
          folderId: folderId,
          isShared: isShared,
        );

        // ðŸ†• NUOVO: Aggiorna cache ottimisticamente subito dopo salvataggio
        print(
            'DEBUG: DataService - Aggiungendo post appena creato alla cache per aggiornamento ottimistico');
        addPostToCache(post);

        // 🔥 NUOVO: Cache persistente anteprima (in background, non blocca)
        _cachePostPreviewInBackground(post);

        print(
            'DEBUG: DataService (FASE 8) - Post creato: ${post.title} (ID: ${post.id}) per utente: $userId');
        return post;
      },
      () {
        throw OfflineOperationException(
            'Creazione post richiede connessione internet');
      },
      'createPost',
      allowCache: false,
    );
  }

  /// Delete post ottimizzato
  Future<void> deletePost(String postId) async {
    await _executeWithOptimizedCache<void>(
      () async {
        final userId = currentUserId!;
        if (kDebugMode) {
          print(
              'DEBUG: DataService (FASE 8) - Eliminando post: $postId per utente: $userId');
        }

        await _firebaseService.deletePost(postId);

        // ðŸ†• NUOVO: Rimuovi dalla cache immediatamente
        removePostFromCache(postId);

        // 🔥 NUOVO: Cancella cache persistente anteprima (best-effort)
        try {
          await const PostPreviewCache().deleteCachedPreview(postId);
        } catch (_) {}

        if (kDebugMode) {
          print(
              'DEBUG: DataService (FASE 8) - Post eliminato: $postId per utente: $userId');
        }
      },
      () {
        throw OfflineOperationException(
            'Eliminazione post richiede connessione internet');
      },
      'deletePost',
      allowCache: false,
    );
  }

  void _cachePostPreviewInBackground(SavedPost post) {
    if (post.id.isEmpty) return;
    final imageUrl = post.imageUrl?.trim();
    final remoteUrl = post.previewStorageUrl?.trim();
    if ((imageUrl?.isNotEmpty != true) && (remoteUrl?.isNotEmpty != true))
      return;

    // Non bloccare mai salvataggio UI/DB
    unawaited(
      Future.microtask(
        () => const PostPreviewCache().ensureCachedPreview(
          postId: post.id,
          imageUrl: remoteUrl,
          fallbackImageUrl: imageUrl,
        ),
      ),
    );

    // Backup remoto best-effort: mantiene le anteprime stabili anche se l'URL originale scade.
    if (post.previewStorageUrl?.trim().isNotEmpty != true) {
      final userId = currentUserId;
      if (userId != null && userId.isNotEmpty) {
        unawaited(
          Future.microtask(() async {
            try {
              final cache = const PostPreviewCache();
              await cache.ensureCachedPreview(
                postId: post.id,
                imageUrl: remoteUrl,
                fallbackImageUrl: imageUrl,
              );
              final localPath = await cache.getCachedPreviewPath(post.id);
              if (localPath == null) return;

              final uploadedRemoteUrl =
                  await const PostPreviewRemoteStorage().uploadCachedPreview(
                userId: userId,
                postId: post.id,
                localPath: localPath,
                sourceUrl: post.url,
              );
              if (uploadedRemoteUrl == null ||
                  uploadedRemoteUrl.trim().isEmpty) {
                return;
              }

              final updatedPost = post.copyWith(
                previewStorageUrl: uploadedRemoteUrl.trim(),
                updatedAt: DateTime.now(),
              );
              await _firebaseService.updatePost(updatedPost);
              addPostToCache(updatedPost);
            } catch (e) {
              print('DEBUG: Upload preview remoto fallito per ${post.id}: $e');
            }
          }),
        );
      }
    }
  }

  /// Backup "best-effort" delle anteprime su storage remoto (utile per Instagram).
  ///
  /// - Tenta di usare prima la cache locale (se esiste).
  /// - Se manca, prova a scaricare da `imageUrl` e poi caricare (potrebbe fallire su IG).
  /// - Scrive `previewStorageUrl` nel documento post su Firestore.
  Future<PreviewBackupResult> backupInstagramPreviewsToRemote({
    bool onlyMissingRemote = true,
    int? maxItems,
  }) async {
    _requireAuthentication();

    final userId = currentUserId!;
    final all = await getPosts();

    final igPosts = all.where((p) => _isInstagramUrl(p.url)).toList();
    final toProcess = (maxItems != null && maxItems > 0)
        ? igPosts.take(maxItems).toList()
        : igPosts;

    int scanned = 0;
    int skipped = 0;
    int uploaded = 0;
    int updated = 0;
    int failed = 0;

    final cache = const PostPreviewCache();
    final remote = const PostPreviewRemoteStorage();

    for (final post in toProcess) {
      scanned++;

      if (onlyMissingRemote &&
          (post.previewStorageUrl?.trim().isNotEmpty == true)) {
        skipped++;
        continue;
      }

      try {
        // 1) prova cache già presente
        String? localPath = await cache.getCachedPreviewPath(post.id);

        // 2) se manca, prova a crearla da imageUrl (best-effort)
        if (localPath == null) {
          final imageUrl = post.imageUrl?.trim();
          final remoteUrl = post.previewStorageUrl?.trim();
          if (imageUrl != null && imageUrl.isNotEmpty ||
              remoteUrl != null && remoteUrl.isNotEmpty) {
            await cache.ensureCachedPreview(
              postId: post.id,
              imageUrl: remoteUrl,
              fallbackImageUrl: imageUrl,
            );
            localPath = await cache.getCachedPreviewPath(post.id);
          }
        }

        if (localPath == null) {
          skipped++;
          continue;
        }

        final downloadUrl = await remote.uploadCachedPreview(
          userId: userId,
          postId: post.id,
          localPath: localPath,
        );

        if (downloadUrl == null || downloadUrl.trim().isEmpty) {
          failed++;
          continue;
        }

        uploaded++;

        final updatedPost = post.copyWith(
          previewStorageUrl: downloadUrl.trim(),
          updatedAt: DateTime.now(),
        );

        await _firebaseService.updatePost(updatedPost);
        addPostToCache(updatedPost);
        updated++;
      } catch (e) {
        failed++;
        print('DEBUG: Backup anteprima fallito per post ${post.id}: $e');
      }
    }

    return PreviewBackupResult(
      totalInstagramPosts: igPosts.length,
      scanned: scanned,
      skipped: skipped,
      uploaded: uploaded,
      updated: updated,
      failed: failed,
    );
  }

  bool _isInstagramUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      return host.contains('instagram.com') || host.contains('instagr.am');
    } catch (_) {
      final lower = url.toLowerCase();
      return lower.contains('instagram.com') || lower.contains('instagr.am');
    }
  }

  // ====== METODI UTILITY OTTIMIZZATI ======

  /// Get post count ottimizzato con gestione collezione vuota
  Future<int> getPostCountForFolder(String folderId) async {
    try {
      final posts = await getPosts(folderId: folderId);
      return posts.length;
    } on AuthenticationRequiredException {
      print('WARNING: getPostCountForFolder richiede autenticazione');
      return 0;
    } catch (e) {
      print('DEBUG: getPostCountForFolder fallback per collezione vuota: $e');
      return 0;
    }
  }

  /// Get tags ottimizzato con gestione collezione vuota
  Future<List<String>> getAllTags() async {
    return await _executeWithOptimizedCache<List<String>>(() async {
      final posts = await getPosts();
      final allTags = <String>{};

      for (var post in posts) {
        allTags.addAll(post.tags);
      }

      return allTags.toList()..sort();
    }, () {
      // Cache tags con fallback lista vuota
      final userId = currentUserId!;
      final cachedPosts = _userPostsCache[userId];
      if (cachedPosts != null) {
        final allTags = <String>{};
        for (var post in cachedPosts) {
          allTags.addAll(post.tags);
        }
        return allTags.toList()..sort();
      }

      print('DEBUG: Tags cache vuoto - restituendo lista vuota');
      return <String>[];
    }, 'getAllTags');
  }

  /// Clear data ottimizzato multi-utente
  Future<void> clearAllData() async {
    await _executeWithOptimizedCache<void>(() async {
      final userId = currentUserId!;
      if (kDebugMode) {
        print('DEBUG: DataService (FASE 8) - Pulizia dati per utente: $userId');
      }

      final folders = await getFolders();
      final posts = await getPosts();

      // Delete all posts first
      for (var post in posts) {
        await deletePost(post.id);
      }

      // Delete all non-default folders
      for (var folder in folders) {
        if (!folder.isDefault) {
          await deleteFolder(folder.id);
        }
      }

      await initializeDefaultData();

      // Clear cache per questo utente
      _clearUserCache(userId);

      // ðŸ†• NUOVO: Notifica pulizia completa
      _notifyDataChange('data_cleared', {
        'userId': userId,
      });

      if (kDebugMode) {
        print(
            'DEBUG: DataService (FASE 8) - Pulizia completata per utente: $userId');
      }
    }, () {
      throw OfflineOperationException(
          'Pulizia dati richiede connessione internet');
    }, 'clearAllData');
  }

  // ====== METODI GESTIONE STATI OTTIMIZZATI ======

  /// Force reload ottimizzato - SOLO FIREBASE
  Future<void> reloadFromDisk() async {
    try {
      if (!isUserAuthenticated) {
        print('WARNING: reloadFromDisk richiede autenticazione');
        return;
      }

      final userId = currentUserId!;
      print(
          'DEBUG: DataService (FASE 8) - Forzando refresh cache Firebase per utente: $userId');

      // Clear Firebase cache to force refresh from server
      _firebaseService.clearCache();

      // Clear user-specific cache
      _clearUserCache(userId);

      // ðŸ†• NUOVO: Notifica reload
      _notifyDataChange('cache_reloaded', {
        'userId': userId,
      });

      print(
          'DEBUG: DataService (FASE 8) - Cache Firebase e utente pulite per utente: $userId');
    } catch (e) {
      print('ERRORE: DataService reloadFromDisk: $e');
    }
  }

  /// Check authentication ottimizzato
  bool checkAuthenticationStatus() {
    final isAuth = isUserAuthenticated;
    final userId = currentUserId;
    print(
        'DEBUG: DataService (FASE 8) - Stato autenticazione: $isAuth (userId: $userId)');
    return isAuth;
  }

  /// Get user info ottimizzato
  Map<String, dynamic> getCurrentUserInfo() {
    final userId = currentUserId;
    return {
      'isAuthenticated': isUserAuthenticated,
      'userId': userId,
      'userEmail': _authService.currentUser?.email,
      'userName': _authService.currentUser?.name,
      'userCacheSize':
          userId != null ? (_userFoldersCache[userId]?.length ?? 0) : 0,
      'userPostsCacheSize':
          userId != null ? (_userPostsCache[userId]?.length ?? 0) : 0,
      'cacheLastUpdate':
          userId != null ? _cacheTimestamps[userId]?.toIso8601String() : null,
      'totalCachedUsers': _userFoldersCache.keys.length,
      'registeredCallbacks': _dataChangeCallbacks.length,
    };
  }

  /// Handle logout ottimizzato
  void handleUserLogout() {
    final userId = currentUserId;
    print('DEBUG: DataService (FASE 8) - Gestendo logout utente: $userId');

    // Clear cache for this specific user
    _clearUserCache(userId);

    // Clear Firebase service cache
    _firebaseService.clearCache();

    print(
        'DEBUG: DataService (FASE 8) - Cache utente pulita dopo logout: $userId');
  }

  /// Handle login ottimizzato
  Future<void> handleUserLogin() async {
    if (!isUserAuthenticated) {
      print('WARNING: handleUserLogin chiamato ma utente non autenticato');
      return;
    }

    try {
      final userId = currentUserId!;
      print('DEBUG: DataService (FASE 8) - Gestendo login utente: $userId');

      // 🔥 NUOVO: Assicurati che il campo normalizedEmail esista per la ricerca
      final user = _authService.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'normalizedEmail': user.email.toLowerCase().trim(),
          'email': user.email,
          'name': user.name,
          'lastLogin': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      print('DEBUG: DataService (FASE 8) - Login gestito per utente: $userId');
    } catch (e) {
      print('ERRORE: handleUserLogin: $e');
    }
  }

  // ====== METODI DI SHARING ======

  /// Cerca un utente per email
  Future<Map<String, dynamic>?> findUserByEmail(String email) async {
    return await _firebaseService.findUserByEmail(email);
  }

  /// Condivide un post con un altro utente
  Future<void> sharePost(SavedPost post, String recipientEmail) async {
    final recipient = await findUserByEmail(recipientEmail);
    if (recipient == null) {
      throw Exception('Utente con email $recipientEmail non trovato');
    }

    if (recipient['id'] == currentUserId) {
      throw Exception('Non puoi condividere con te stesso');
    }

    await _firebaseService.shareItem(
      resourceId: post.id,
      type: 'post',
      recipientId: recipient['id'],
      originalData: post.toFirestoreService(),
    );
  }

  /// Condivide una cartella con un altro utente
  Future<void> shareFolder(Folder folder, String recipientEmail) async {
    final recipient = await findUserByEmail(recipientEmail);
    if (recipient == null) {
      throw Exception('Utente con email $recipientEmail non trovato');
    }

    if (recipient['id'] == currentUserId) {
      throw Exception('Non puoi condividere con te stesso');
    }

    // Per le cartelle, includiamo anche il colore e altre info
    await _firebaseService.shareItem(
      resourceId: folder.id,
      type: 'folder',
      recipientId: recipient['id'],
      originalData: folder.toFirestoreService(),
    );
  }

  /// Ottiene gli elementi condivisi con l'utente corrente
  Future<List<Map<String, dynamic>>> getSharedItems() async {
    return await _firebaseService.getSharedItems();
  }

  /// Accetta un elemento condiviso (lo salva nella propria collezione)
  Future<void> acceptSharedItem(Map<String, dynamic> sharedItem,
      {String? targetFolderId}) async {
    final type = sharedItem['type'];
    final originalData = sharedItem['originalData'] as Map<String, dynamic>;
    final ownerName = sharedItem['ownerName'];

    if (type == 'post') {
      // Trova la cartella di destinazione reale
      String finalFolderId = targetFolderId ?? '';

      if (finalFolderId.isEmpty || finalFolderId == 'all_folder') {
        final folders = await getFolders();
        finalFolderId = folders.firstWhere((f) => f.isDefault).id;
      }

      // Crea un nuovo post basato sui dati originali
      await createPost(
        url: originalData['url'],
        title: '[Condiviso da $ownerName] ${originalData['title']}',
        description: originalData['description'],
        imageUrl: originalData['imageUrl'],
        creatorName: originalData['creatorName'],
        creatorUsername: originalData['creatorUsername'],
        tags: List<String>.from(originalData['tags'] ?? [])..add('condiviso'),
        folderId: finalFolderId,
        isShared: true, // 🆕 NUOVO
      );
    } else if (type == 'folder') {
      // Crea una nuova cartella basata sui dati originali
      await createFolder(
        name: '[Condivisa da $ownerName] ${originalData['name']}',
        color: originalData['color'],
        isShared: true, // 🆕 NUOVO
      );
    }

    // Rimuovi l'elemento dalla lista dei condivisi dopo l'accettazione
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('shared_items')
        .doc(sharedItem['id'])
        .delete();
  }

  /// Rifiuta un elemento condiviso
  Future<void> rejectSharedItem(String shareId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('shared_items')
        .doc(shareId)
        .delete();
  }

  // ====== METODI PERFORMANCE E MONITORING ======

  /// Performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return {
      'total_cached_users': _userFoldersCache.keys.length,
      'cache_validity_duration_minutes': _cacheValidityDuration.inMinutes,
      'current_user_cache_valid':
          currentUserId != null ? _isUserCacheValid(currentUserId!) : false,
      'memory_usage': {
        'folders_cache_entries': _userFoldersCache.length,
        'posts_cache_entries': _userPostsCache.length,
        'timestamps_entries': _cacheTimestamps.length,
      },
      'last_operations': {
        'current_user': currentUserId,
        'authenticated': isUserAuthenticated,
      },
      'callbacks': {
        'registered_callbacks': _dataChangeCallbacks.length,
      },
    };
  }

  /// Cache cleanup per performance
  void performCacheCleanup() {
    final now = DateTime.now();
    final expiredUsers = <String>[];

    // Find expired cache entries
    _cacheTimestamps.forEach((userId, timestamp) {
      if (now.difference(timestamp) > _cacheValidityDuration) {
        expiredUsers.add(userId);
      }
    });

    // Remove expired entries
    for (final userId in expiredUsers) {
      _clearUserCache(userId);
    }

    if (kDebugMode) {
      print(
          'DEBUG: DataService (FASE 8) - Cache cleanup: ${expiredUsers.length} utenti scaduti rimossi');
    }

    // ðŸ†• NUOVO: Notifica cleanup se necessario
    if (expiredUsers.isNotEmpty) {
      _notifyDataChange('cache_cleaned', {
        'expired_users': expiredUsers.length,
      });
    }
  }

  // ====== DEBUG METHODS FASE 8 ======

  /// Debug ottimizzato con context multi-utente
  Future<void> debugShowAllData() async {
    try {
      if (!isUserAuthenticated) {
        if (kDebugMode) {
          print('=== DEBUG FASE 8 - UTENTE NON AUTENTICATO ===');
          print('Autenticazione richiesta per visualizzare dati');
          print('===============================================');
        }
        return;
      }

      final userId = currentUserId!;
      if (kDebugMode) {
        print('=== DEBUG FASE 8 - UTENTE: $userId ===');

        final folders = await getFolders();
        final posts = await getPosts();

        print('FASE 8 - Firebase Folders (${folders.length}):');
        for (var folder in folders) {
          print(
              '  - ${folder.name} (ID: ${folder.id}, Default: ${folder.isDefault}, ParentID: ${folder.parentId})');
        }

        print('FASE 8 - Firebase Posts (${posts.length}):');
        if (posts.isEmpty) {
          print('  - Nessun post trovato (normale per nuovo utente)');
        } else {
          for (var post in posts.take(5)) {
            print('  - ${post.title} (Folder: ${post.folderId})');
          }
          if (posts.length > 5) {
            print('  ... e altri ${posts.length - 5} post');
          }
        }

        print('FASE 8 - Performance Metrics:');
        final metrics = getPerformanceMetrics();
        metrics.forEach((key, value) {
          print('  - $key: $value');
        });

        print('=======================================');
      }
    } catch (e) {
      if (kDebugMode) print('ERRORE: DataService debugShowAllData: $e');
    }
  }

  /// Force cleanup completo
  Future<void> debugForceCompleteCleanup() async {
    try {
      if (!isUserAuthenticated) {
        if (kDebugMode) print('=== PULIZIA FASE 8 RICHIEDE AUTENTICAZIONE ===');
        return;
      }

      final userId = currentUserId!;
      if (kDebugMode)
        print('=== PULIZIA FORZATA FIREBASE FASE 8 PER UTENTE: $userId ===');

      await clearAllData();

      if (kDebugMode)
        print(
            '==== PULIZIA FIREBASE FASE 8 COMPLETATA PER UTENTE: $userId ====');
    } catch (e) {
      if (kDebugMode)
        print('ERRORE: DataService debugForceCompleteCleanup: $e');
    }
  }

  // ====== CLEANUP FINALE ======

  /// Dispose ottimizzato
  void dispose() {
    final userId = currentUserId;
    if (kDebugMode)
      print('DEBUG: DataService (FASE 8) - Disposing per utente: $userId');

    // Clear all user caches
    _userFoldersCache.clear();
    _userPostsCache.clear();
    _cacheTimestamps.clear();

    // ðŸ†• NUOVO: Pulisci callback registrati
    _dataChangeCallbacks.clear();

    // Dispose Firebase service
    _firebaseService.dispose();

    if (kDebugMode) print('DEBUG: DataService (FASE 8) - Dispose completato');
  }
}
