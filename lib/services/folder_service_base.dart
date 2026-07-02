// File: lib/services/folder_service_base.dart
// Classe base FolderService con singleton e inizializzazione

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savein/models/folder.dart';
import 'package:savein/models.dart';
import '../utils/constants.dart';
import 'package:savein/data_service.dart' show DataService, DataChangeCallback;
import 'simple_analytics_service.dart';
import '../advanced_analytics_service.dart';
import 'auth_service.dart';

import 'folder_service_models.dart';

/// Classe base FolderService - Singleton Pattern e State Management
abstract class FolderServiceBase {
  // ============================================================================
  // SINGLETON PATTERN
  // ============================================================================

  static FolderServiceBase? _instance;

  // Variabili di istanza protette
  List<MockFolder> folders = [];
  List<MockPost> allPosts = [];
  bool isInitialized = false;

  // ============================================================================
  // SERVIZI E DIPENDENZE
  // ============================================================================

  final SimpleAnalyticsService analytics = SimpleAnalyticsService();
  final AdvancedAnalyticsService advancedAnalytics = AdvancedAnalyticsService();

  // Tracking timing azioni
  final Map<String, DateTime> actionStartTimes = {};

  // ============================================================================
  // STREAM CONTROLLERS PER REAL-TIME UPDATES
  // ============================================================================

  late final StreamController<List<MockFolder>> foldersStreamController;
  late final StreamController<List<MockPost>> postsStreamController;
  late final StreamController<ServiceHealthMetrics> healthStreamController;

  // ============================================================================
  // CACHE UTENTE INTELLIGENTE
  // ============================================================================

  final Map<String, List<MockFolder>> userFoldersCache = {};
  final Map<String, List<MockPost>> userPostsCache = {};
  final Map<String, DateTime> cacheTimestamps = {};
  final Duration cacheValidityDuration = Duration(minutes: 5);

  // ============================================================================
  // AUTHENTICATION STATE MANAGEMENT
  // ============================================================================

  StreamSubscription<User?>? authSubscription;
  String? currentUserId;
  bool isAuthenticated = false;

  // ============================================================================
  // HEALTH MONITORING
  // ============================================================================

  ServiceHealthMetrics currentHealth = ServiceHealthMetrics(
    status: ServiceHealthStatus.unknown,
    lastUpdate: DateTime.now(),
    metrics: {},
  );

  // ============================================================================
  // RETRY MECHANISMS
  // ============================================================================

  final int maxRetries = 3;
  final Duration retryDelay = Duration(seconds: 2);

  // ============================================================================
  // FIX POST SCOMPARSI: Configurazioni timing
  // ============================================================================

  final Duration syncDelayAfterSave = Duration(seconds: 2);
  final int maxSyncRetries = 3;
  final Duration syncRetryDelay = Duration(milliseconds: 500);

  // ============================================================================
  // SISTEMA CALLBACK OTTIMISTICO
  // ============================================================================

  DataChangeCallback? dataServiceCallback;
  bool isDataServiceCallbackRegistered = false;
  final List<VoidCallback> uiUpdateCallbacks = [];

  // ============================================================================
  // GETTERS
  // ============================================================================

  Stream<List<MockFolder>> get foldersStream => foldersStreamController.stream;
  Stream<List<MockPost>> get postsStream => postsStreamController.stream;
  Stream<ServiceHealthMetrics> get healthStream =>
      healthStreamController.stream;

  ServiceHealthMetrics get getCurrentHealth => currentHealth;
  bool get isHealthy => currentHealth.status == ServiceHealthStatus.healthy;

  // ============================================================================
  // INIZIALIZZAZIONE STREAM CONTROLLERS
  // ============================================================================

  void initializeStreamControllers() {
    foldersStreamController = StreamController<List<MockFolder>>.broadcast();
    postsStreamController = StreamController<List<MockPost>>.broadcast();
    healthStreamController = StreamController<ServiceHealthMetrics>.broadcast();

    setupOptimisticUpdateCallback();

    print('DEBUG: Stream controllers e callback ottimistici inizializzati');
  }

  // ============================================================================
  // SETUP AUTHENTICATION LISTENER
  // ============================================================================

  void setupAuthenticationListener() {
    try {
      final authService = AuthService();
      authSubscription = authService.userStream.listen((user) {
        handleAuthenticationChange(user);
      });

      print('DEBUG: Authentication listener configurato');
    } catch (e) {
      print('ERRORE: Setup authentication listener fallito: $e');
      updateHealthStatus(ServiceHealthStatus.error,
          errorMessage: 'Auth listener setup failed: $e');
    }
  }

  // ============================================================================
  // GESTIONE CAMBIO STATO AUTENTICAZIONE
  // ============================================================================

  void handleAuthenticationChange(User? user) async {
    final wasAuthenticated = isAuthenticated;
    final previousUserId = currentUserId;
    isAuthenticated = user != null;
    currentUserId = user?.id;

    print(
        'DEBUG: Cambio stato autenticazione - User: ${user?.id}, Authenticated: $isAuthenticated');

    if (isAuthenticated != wasAuthenticated) {
      if (isAuthenticated) {
        await handleUserLogin();
      } else {
        // IMPORTANTE: a questo punto AuthService().currentUser è già null
        // (viene azzerato prima di emettere l'evento di logout sullo stream),
        // quindi DataService.handleUserLogout() da solo non riesce più a
        // capire quale utente pulire dalla sua cache per-utente. Ripuliamo
        // sempre anche la cache GLOBALE di FirebaseDataService qui, altrimenti
        // il prossimo utente che fa login si ritrova le cartelle/post
        // dell'utente precedente ancora in cache.
        DataService.instance.handleUserLogout(previousUserId: previousUserId);
        await handleUserLogout();
      }
    } else if (isAuthenticated && previousUserId != currentUserId) {
      // Stesso stato (loggato), ma utente diverso: svuota e ricarica
      print('DEBUG: Cambio utente da $previousUserId a $currentUserId - forcing reload');
      DataService.instance.handleUserLogout(previousUserId: previousUserId);
      await handleUserLogout();
      await handleUserLogin();
    }

    updateHealthStatus(
      isAuthenticated
          ? ServiceHealthStatus.healthy
          : ServiceHealthStatus.authenticating,
      userContext: currentUserId,
    );
  }

  Future<void> handleUserLogin() async {
    print('DEBUG: Gestendo login utente: $currentUserId');

    try {
      // Non svuotare e ricaricare tutto qui: durante lo startup il caricamento
      // principale di FolderService parte gia' subito dopo l'auth.
      if (currentUserId != null && loadFromCache(currentUserId!)) {
        notifyDataChanged();
      }

      print('DEBUG: Login utente gestito con successo');
    } catch (e) {
      print('ERRORE: Gestione login utente fallita: $e');
      updateHealthStatus(ServiceHealthStatus.error,
          errorMessage: 'Login handling failed: $e');
    }
  }

  Future<void> handleUserLogout() async {
    print('DEBUG: Gestendo logout utente');

    try {
      clearUserCache();
      folders.clear();
      allPosts.clear();
      notifyDataChanged();

      print('DEBUG: Logout utente gestito con successo');
    } catch (e) {
      print('ERRORE: Gestione logout utente fallita: $e');
    }
  }

  // ============================================================================
  // HEALTH STATUS MANAGEMENT
  // ============================================================================

  void updateHealthStatus(ServiceHealthStatus status,
      {String? errorMessage, String? userContext}) {
    currentHealth = ServiceHealthMetrics(
      status: status,
      lastUpdate: DateTime.now(),
      errorMessage: errorMessage,
      userContext: userContext ?? currentUserId,
      metrics: {
        'folders_count': folders.length,
        'posts_count': allPosts.length,
        'cache_entries': userFoldersCache.length,
        'authenticated': isAuthenticated,
      },
    );

    if (!healthStreamController.isClosed) {
      healthStreamController.add(currentHealth);
    }

    print('DEBUG: Health status aggiornato: ${status.toString()}');
  }

  // ============================================================================
  // CALLBACK SYSTEM
  // ============================================================================

  void setupOptimisticUpdateCallback() {
    if (isDataServiceCallbackRegistered) {
      print('DEBUG: Callback DataService già registrato');
      return;
    }

    dataServiceCallback = (String changeType, Map<String, dynamic> changeData) {
      handleDataServiceCallback(changeType, changeData);
    };

    try {
      DataService.instance.registerDataChangeCallback(dataServiceCallback!);
      isDataServiceCallbackRegistered = true;
      print('DEBUG: Callback registrato con DataService');
    } catch (e) {
      print('DEBUG: Errore registrazione callback: $e');
    }
  }

  void handleDataServiceCallback(
      String changeType, Map<String, dynamic> changeData);

  void registerUIUpdateCallback(VoidCallback callback) {
    if (!uiUpdateCallbacks.contains(callback)) {
      uiUpdateCallbacks.add(callback);
      print(
          'DEBUG: UI callback registrato (${uiUpdateCallbacks.length} totali)');
    }
  }

  void unregisterUIUpdateCallback(VoidCallback callback) {
    uiUpdateCallbacks.remove(callback);
    print('DEBUG: UI callback rimosso (${uiUpdateCallbacks.length} rimasti)');
  }

  void notifyUICallbacks() {
    print('DEBUG: Notificando ${uiUpdateCallbacks.length} UI callback');

    for (final callback in uiUpdateCallbacks) {
      try {
        callback();
      } catch (e) {
        print('DEBUG: Errore callback UI: $e');
      }
    }
  }

  // ============================================================================
  // CACHE MANAGEMENT
  // ============================================================================

  bool isCacheValid(String userId) {
    final timestamp = cacheTimestamps[userId];
    if (timestamp == null) return false;

    return DateTime.now().difference(timestamp) < cacheValidityDuration;
  }

  void cacheUserData(String userId) {
    userFoldersCache[userId] = List.from(folders);
    userPostsCache[userId] = List.from(allPosts);
    cacheTimestamps[userId] = DateTime.now();

    print('DEBUG: Dati cached per utente: $userId');
  }

  bool loadFromCache(String userId) {
    if (!isCacheValid(userId)) return false;

    final cachedFolders = userFoldersCache[userId];
    final cachedPosts = userPostsCache[userId];

    if (cachedFolders != null && cachedPosts != null) {
      folders = List.from(cachedFolders);
      allPosts = List.from(cachedPosts);
      print('DEBUG: Dati caricati da cache per utente: $userId');

      // 🔥 FIX: Verifica che la gerarchia delle cartelle sia corretta
      if (!_validateFolderHierarchy()) {
        print(
            'DEBUG: ⚠️ Gerarchia cartelle non valida nella cache, forzo reload');
        folders.clear();
        allPosts.clear();
        return false;
      }

      return true;
    }

    return false;
  }

  /// Verifica che la gerarchia delle cartelle sia corretta
  bool _validateFolderHierarchy() {
    if (folders.isEmpty) {
      print('DEBUG: ⚠️ Nessuna cartella in cache');
      return false;
    }

    print(
        'DEBUG: 🔍 Validazione gerarchia - ${folders.length} cartelle totali');

    // STEP 1: Conta cartelle con level == 0 (dovrebbero essere solo root + Tutti)
    final level0Folders = folders.where((f) => f.level == 0).toList();
    final nonSpecialFolders = folders.where((f) => !f.isSpecial).toList();

    print('DEBUG: - ${level0Folders.length} cartelle level 0');
    print('DEBUG: - ${nonSpecialFolders.length} cartelle non-speciali');

    if (level0Folders.isEmpty) {
      print('DEBUG: ❌ Nessuna cartella level 0 trovata');
      return false;
    }

    // STEP 2: Verifica che ci sia la cartella "Tutti"
    if (!folders.any((f) => f.isSpecial)) {
      print('DEBUG: ❌ Cartella "Tutti" mancante');
      return false;
    }

    // STEP 3: 🔥 NUOVO - Verifica che la lista folders contenga SOLO cartelle level 0
    // Le sottocartelle dovrebbero essere solo in children[], non in folders[]
    final foldersInMainList = folders.where((f) => !f.isSpecial).toList();
    for (var folder in foldersInMainList) {
      if (folder.level != 0) {
        print(
            'DEBUG: ❌ Cartella "${folder.name}" ha level ${folder.level} ma è nella lista principale');
        return false;
      }
      if (folder.parent != null) {
        print(
            'DEBUG: ❌ Cartella "${folder.name}" ha un parent ma è nella lista principale');
        return false;
      }
    }

    // STEP 4: Verifica integrità delle relazioni parent-child
    for (var folder in nonSpecialFolders) {
      // Se ha un parent, deve avere level > parent.level
      if (folder.parent != null && folder.level <= folder.parent!.level) {
        print(
            'DEBUG: ❌ Cartella "${folder.name}" ha level errato (${folder.level} <= parent.level ${folder.parent!.level})');
        return false;
      }

      // Se ha un parent, deve avere level > 0
      if (folder.parent != null && folder.level == 0) {
        print(
            'DEBUG: ❌ Sottocartella "${folder.name}" ha level == 0 ma ha un parent');
        return false;
      }

      // Se ha level > 0, DEVE avere un parent
      if (folder.level > 0 && folder.parent == null) {
        print(
            'DEBUG: ❌ Cartella "${folder.name}" ha level ${folder.level} ma parent è null');
        return false;
      }
    }

    // STEP 5: 🔥 NUOVO - Conta ricorsivamente tutte le cartelle (incluse in children)
    int countAllFolders(MockFolder folder) {
      int count = folder.isSpecial ? 0 : 1;
      for (var child in folder.children) {
        count += countAllFolders(child);
      }
      return count;
    }

    int totalFoldersInTree = 0;
    for (var folder in folders) {
      totalFoldersInTree += countAllFolders(folder);
    }

    print(
        'DEBUG: - ${totalFoldersInTree} cartelle totali nell\'albero (incluse children)');

    // Se il numero di cartelle nella lista principale è molto diverso
    // dal numero totale nell'albero, c'è un problema di struttura
    final rootFoldersCount = folders.where((f) => !f.isSpecial).length;
    if (totalFoldersInTree > rootFoldersCount && rootFoldersCount > 1) {
      // Questo è OK - abbiamo sottocartelle nell'albero
      print('DEBUG: ✅ Struttura gerarchica rilevata correttamente');
    } else if (totalFoldersInTree == rootFoldersCount && folders.length > 3) {
      // Sospetto: troppe cartelle root senza children
      print(
          'DEBUG: ⚠️ Tutte le ${rootFoldersCount} cartelle sono root - potrebbe essere un problema');
    }

    print('DEBUG: ✅ Gerarchia cartelle valida');
    return true;
  }

  void clearUserCache() {
    if (currentUserId != null) {
      userFoldersCache.remove(currentUserId);
      userPostsCache.remove(currentUserId);
      cacheTimestamps.remove(currentUserId);
      print('DEBUG: Cache pulita per utente: $currentUserId');
    }
  }

  // ============================================================================
  // NOTIFICATION SYSTEM
  // ============================================================================

  void notifyDataChanged() {
    if (!foldersStreamController.isClosed) {
      foldersStreamController.add(List.from(folders));
    }
    if (!postsStreamController.isClosed) {
      postsStreamController.add(List.from(allPosts));
    }

    print('DEBUG: Notifica cambio dati inviata via stream');
  }

  // ============================================================================
  // RETRY MECHANISM
  // ============================================================================

  Future<T> executeWithRetry<T>(
      Future<T> Function() operation, String operationName) async {
    int attempts = 0;
    Exception? lastException;

    while (attempts < maxRetries) {
      try {
        final result = await operation();
        if (attempts > 0) {
          print(
              'DEBUG: $operationName riuscito dopo ${attempts + 1} tentativi');
        }
        return result;
      } catch (e) {
        attempts++;
        lastException = e is Exception ? e : Exception(e.toString());

        if (attempts >= maxRetries) {
          print('ERRORE: $operationName fallito dopo $attempts tentativi: $e');
          updateHealthStatus(ServiceHealthStatus.error,
              errorMessage: '$operationName failed: $e');
          break;
        }

        final delay = Duration(seconds: retryDelay.inSeconds * attempts);
        print(
            'DEBUG: $operationName tentativo $attempts fallito, retry in ${delay.inSeconds}s: $e');
        await Future.delayed(delay);
      }
    }

    throw lastException ??
        Exception('Operation failed after $maxRetries attempts');
  }

  Future<T> executeAuthenticatedOperation<T>(
      Future<T> Function() operation, String operationName) async {
    // FIX RACE CONDITION: Sincronizza esplicitamente lo stato di autenticazione
    // se risulta false, perché potrebbe essere un problema di timing dello stream
    if (!isAuthenticated || currentUserId == null) {
      final authService = AuthService();
      final user = authService.currentUser;
      if (user != null) {
        isAuthenticated = true;
        currentUserId = user.id;
        print('DEBUG: Auth sincronizzata in executeAuthenticatedOperation (userId: ${user.id})');
      }
    }

    if (!isAuthenticated || currentUserId == null) {
      updateHealthStatus(ServiceHealthStatus.authenticating,
          errorMessage: 'Authentication required');
      throw Exception('Authentication required for $operationName');
    }

    return await executeWithRetry(operation, operationName);
  }

  // ============================================================================
  // TIMING UTILITIES
  // ============================================================================

  void startActionTiming(String actionKey) {
    actionStartTimes[actionKey] = DateTime.now();
  }

  Duration? endActionTiming(String actionKey) {
    final startTime = actionStartTimes.remove(actionKey);
    if (startTime != null) {
      return DateTime.now().difference(startTime);
    }
    return null;
  }

  // ============================================================================
  // 🔥 NUOVO: METODO UTILITY CENTRALIZZATO PER RICERCA GERARCHICA
  // ============================================================================

  /// Trova la Folder reale (database) corrispondente a MockFolder (UI)
  /// seguendo la catena di parentId ricorsivamente e con fallback intelligente
  Folder? findRealFolderByMockFolder(
      List<Folder> realFolders, MockFolder mockFolder) {
    // print('DEBUG: 🔍 Cercando Folder reale per MockFolder: ${mockFolder.name}');

    // STRATEGIA 1: Ricerca esatta per path
    List<String> mockPath = [];
    MockFolder? current = mockFolder;

    while (current != null && !current.isSpecial) {
      mockPath.insert(0, current.name);
      current = current.parent;
    }

    // print('DEBUG: Path da cercare: ${mockPath.join(" › ")}');

    Folder? found;
    bool pathSearchFailed = false;

    for (int i = 0; i < mockPath.length; i++) {
      final targetName = mockPath[i];

      if (i == 0) {
        // Root level
        try {
          found = realFolders.firstWhere(
            (f) => f.name == targetName && !f.isDefault && f.parentId == null,
          );
        } catch (e) {
          pathSearchFailed = true;
          break;
        }
      } else {
        // Child level
        if (found == null) {
          pathSearchFailed = true;
          break;
        }

        final previousId = found.id;
        try {
          found = realFolders.firstWhere(
            (f) => f.name == targetName && f.parentId == previousId,
          );
        } catch (e) {
          pathSearchFailed = true;
          break;
        }
      }
    }

    if (!pathSearchFailed && found != null) {
      // print('DEBUG: ✅ Ricerca PATH completata - Folder trovata: ${found.name} (ID: ${found.id})');
      return found;
    }

    // STRATEGIA 2: Fallback intelligente
    print(
        'WARNING: ⚠️ Ricerca PATH fallita per "${mockFolder.name}", avvio fallback...');

    // Caso 1: Root folder
    if (mockFolder.parent == null || mockFolder.parent!.isSpecial) {
      try {
        final fallback = realFolders.firstWhere((f) =>
            f.name == mockFolder.name && f.parentId == null && !f.isDefault);
        print(
            'DEBUG: ✅ Fallback ROOT riuscito: ${fallback.name} (ID: ${fallback.id})');
        return fallback;
      } catch (e) {}
    }
    // Caso 2: Child folder
    else {
      // Prova a trovare il parent reale
      final parentReal =
          findRealFolderByMockFolder(realFolders, mockFolder.parent!);

      if (parentReal != null) {
        try {
          final fallback = realFolders.firstWhere(
              (f) => f.name == mockFolder.name && f.parentId == parentReal.id);
          print(
              'DEBUG: ✅ Fallback PARENT-MATCH riuscito: ${fallback.name} (ID: ${fallback.id})');
          return fallback;
        } catch (e) {}
      }

      // Ultimo tentativo: cerca per nome (escludendo root se level > 0)
      try {
        final candidates = realFolders
            .where((f) => f.name == mockFolder.name && f.parentId != null)
            .toList();

        if (candidates.length == 1) {
          print(
              'DEBUG: ✅ Fallback NAME-ONLY riuscito: ${candidates.first.name} (ID: ${candidates.first.id})');
          return candidates.first;
        } else if (candidates.isNotEmpty) {
          print(
              'DEBUG: ⚠️ Fallback NAME-ONLY ambiguo (${candidates.length} match), prendo il primo');
          return candidates.first;
        }
      } catch (e) {}
    }

    print(
        'ERRORE: ❌ Impossibile trovare cartella reale per "${mockFolder.name}"');
    return null;
  }

  /// Helper per trovare MockFolder da Folder.id
  /// Usato per convertire ID database → MockFolder UI
  MockFolder? findMockFolderByRealId(String folderId) {
    MockFolder? searchRecursive(MockFolder folder) {
      // Cerca nel folder corrente (confronta con realFolders se necessario)
      // Per ora uso il nome, ma potremmo aggiungere un mapping ID

      for (var child in folder.children) {
        final result = searchRecursive(child);
        if (result != null) return result;
      }

      return null;
    }

    for (var folder in folders) {
      if (!folder.isSpecial) {
        final result = searchRecursive(folder);
        if (result != null) return result;
      }
    }

    return null;
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================

  void cleanup() {
    print('DEBUG: Eseguendo cleanup FolderServiceBase...');

    if (isDataServiceCallbackRegistered && dataServiceCallback != null) {
      try {
        DataService.instance.unregisterDataChangeCallback(dataServiceCallback!);
        isDataServiceCallbackRegistered = false;
      } catch (e) {
        print('DEBUG: Errore rimozione callback: $e');
      }
    }

    uiUpdateCallbacks.clear();
    foldersStreamController.close();
    postsStreamController.close();
    healthStreamController.close();
    authSubscription?.cancel();

    userFoldersCache.clear();
    userPostsCache.clear();
    cacheTimestamps.clear();

    folders.clear();
    allPosts.clear();
    actionStartTimes.clear();

    isInitialized = false;
    isAuthenticated = false;
    currentUserId = null;

    print('DEBUG: Cleanup completato');
  }

  // ============================================================================
  // METODI ASTRATTI DA IMPLEMENTARE
  // ============================================================================

  Future<void> loadUserSpecificData();
}
