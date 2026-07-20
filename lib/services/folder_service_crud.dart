// File: lib/services/folder_service_crud.dart
// Operazioni CRUD con supporto parentId

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:savein/models/folder.dart';
import 'package:savein/models.dart';
import 'package:savein/data_service.dart';
import '../utils/folder_management.dart';
import '../advanced_analytics_models.dart';
import 'access_control_service.dart';

import 'folder_service_models.dart';
import 'folder_service_base.dart';
import 'auth_service.dart';

/// Mixin per operazioni CRUD con supporto parentId
mixin FolderServiceCRUD on FolderServiceBase {
  final AppAccessService _accessService = AppAccessService();

  /// FIX 03/07/2026: allinea isAuthenticated/currentUserId con AuthService se
  /// risultano non ancora sincronizzati. Stesso pattern già usato in
  /// [executeAuthenticatedOperation] (folder_service_base.dart), applicato
  /// anche qui perché createPersistentFolder/createSubfolderInFolder
  /// controllano questi campi direttamente senza passare da quel metodo.
  /// Corregge i falsi "User not authenticated" osservati su alcuni
  /// dispositivi subito dopo login/registrazione (lo stream di stato di
  /// FolderService non ha ancora ricevuto l'evento di AuthService).
  void _resyncAuthStateIfNeeded() {
    if (isAuthenticated && currentUserId != null) return;
    final user = AuthService().currentUser;
    if (user != null) {
      isAuthenticated = true;
      currentUserId = user.id;
      print(
          'DEBUG: Auth sincronizzata in FolderServiceCRUD (userId: ${user.id})');
    }
  }

  // ============================================================================
  // VALIDAZIONE
  // ============================================================================

  String? validateFolderName(String name,
      {MockFolder? parent, MockFolder? excludeFolder}) {
    if (name.trim().isEmpty) {
      return 'Il nome della cartella non può essere vuoto';
    }
    if (name.contains('/')) {
      return 'Il nome non può contenere il carattere /';
    }
    if (name.contains('›')) {
      return 'Il nome non può contenere il carattere ›';
    }
    if (name.length > 50) {
      return 'Il nome è troppo lungo (max 50 caratteri)';
    }

    // Controlla se esiste già una cartella con quel nome NELLO STESSO LIVELLO
    if (parent == null) {
      // Root level
      final exists = folders.any((f) =>
          !f.isSpecial &&
          f.parent == null &&
          f.name.toLowerCase() == name.trim().toLowerCase() &&
          // 🔥 FIX: Escludi la cartella corrente (per permettere cambio maiuscole/minuscole)
          (excludeFolder == null ||
              f.name != excludeFolder.name ||
              f.level != excludeFolder.level));

      if (exists) {
        return 'Esiste già una cartella con questo nome a livello root';
      }
    } else {
      // Sottocartella
      final exists = parent.children.any((child) =>
          child.name.toLowerCase() == name.trim().toLowerCase() &&
          // 🔥 FIX: Escludi la cartella corrente (per permettere cambio maiuscole/minuscole)
          (excludeFolder == null ||
              child.name != excludeFolder.name ||
              child.level != excludeFolder.level));

      if (exists) {
        return 'Esiste già una sottocartella con questo nome';
      }
    }

    return null;
  }

  // ============================================================================
  // 🔥 NUOVO: CREAZIONE GERARCHICA CENTRALIZZATA PER POPUP
  // ============================================================================

  /// Crea una gerarchia completa di cartelle da un path e ritorna l'ID finale
  ///
  /// Questo metodo gestisce TUTTA la logica di creazione gerarchica con:
  /// - Invalidazione cache tra ogni creazione
  /// - Ricerca gerarchica corretta usando parentId
  /// - Retry con delay dinamico
  /// - Verifica esistenza prima di creare
  /// - Sincronizzazione completa finale
  ///
  /// Esempio:
  /// ```dart
  /// final id = await createFolderHierarchyFromPath("Tre › Quattro");
  /// // Crea "Tre" (root), poi "Quattro" (child di Tre)
  /// // Ritorna l'ID Firebase di "Quattro"
  /// ```
  Future<String> createFolderHierarchyFromPath(
    String fullPath, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 300),
  }) async {
    print('DEBUG: 🎯 ========== CREAZIONE GERARCHIA DA PATH ==========');
    print('DEBUG: Path completo: $fullPath');
    print(
        'DEBUG: Max retry: $maxRetries, Delay base: ${retryDelay.inMilliseconds}ms');

    startActionTiming('create_hierarchy_from_path');

    try {
      // STEP 1: Parse del path
      String cleanPath = fullPath.trim();
      if (cleanPath.startsWith('Home › ')) {
        cleanPath = cleanPath.substring(7);
      }

      final pathParts = cleanPath
          .split(' › ')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();

      if (pathParts.isEmpty) {
        throw Exception('Path vuoto o non valido');
      }

      print(
          'DEBUG: Path parts: ${pathParts.join(" → ")} (${pathParts.length} livelli)');

      final depthValidation = await _accessService
          .validateHierarchyDepthForCreationAsync(pathParts.length);
      if (depthValidation != null) {
        throw Exception(depthValidation);
      }

      // STEP 2: Inizializza tracking
      String? currentParentId; // null = root level
      String? currentFolderId;

      // STEP 3: Loop per ogni livello della gerarchia
      for (int i = 0; i < pathParts.length; i++) {
        final folderName = pathParts[i];
        final isRoot = i == 0;

        print(
            'DEBUG: --- Livello $i: "$folderName" (${isRoot ? "ROOT" : "CHILD"}) ---');

        // A. Invalida cache PRIMA di ogni lettura
        print('DEBUG: Invalidando cache folders...');
        DataService.instance.invalidateCache(
            folders: true,
            posts: true); // ⭐ Anche posts per mantenere sincronizzazione

        // B. Forza reload completo da Firebase per ripopolare la cache
        print('DEBUG: Forzando reload da Firebase...');
        await DataService.instance.reloadFromDisk();

        // C. Carica folders FRESH da database (ora la cache è popolata)
        print('DEBUG: Caricando folders fresh da database...');
        final realFolders = await DataService.instance.getFolders();
        print('DEBUG: Caricate ${realFolders.length} cartelle da DB');

        // Debug: mostra struttura corrente
        if (realFolders.length <= 10) {
          for (var f in realFolders) {
            print('  - ${f.name} (ID: ${f.id}, parentId: ${f.parentId})');
          }
        }

        // C. Cerca cartella corrente
        Folder? existingFolder;

        if (isRoot) {
          // Root level: cerca con parentId == null
          try {
            existingFolder = realFolders.firstWhere(
              (f) => f.name == folderName && !f.isDefault && f.parentId == null,
            );
            print(
                'DEBUG: ✅ Root folder "$folderName" già esistente (ID: ${existingFolder.id})');
          } catch (e) {
            print('DEBUG: ℹ️ Root folder "$folderName" non esiste');
          }
        } else {
          // Child level: cerca con parentId specifico
          if (currentParentId == null) {
            throw Exception('Parent ID null per child folder "$folderName"');
          }

          try {
            existingFolder = realFolders.firstWhere(
              (f) => f.name == folderName && f.parentId == currentParentId,
            );
            print(
                'DEBUG: ✅ Child folder "$folderName" già esistente (ID: ${existingFolder.id}, parentId: ${existingFolder.parentId})');
          } catch (e) {
            print(
                'DEBUG: ℹ️ Child folder "$folderName" non esiste sotto parent $currentParentId');
          }
        }

        // D. Se esiste, passa al prossimo livello
        if (existingFolder != null) {
          currentFolderId = existingFolder.id;
          currentParentId = existingFolder.id;
          print(
              'DEBUG: ➡️ Cartella già presente, passando al livello successivo');
          continue;
        }

        // E. Se NON esiste, crea con RETRY
        print('DEBUG: 🔨 Creando cartella "$folderName"...');

        if (isRoot) {
          final rootCount = realFolders
              .where((folder) => !folder.isDefault && folder.parentId == null)
              .length;
          final rootValidation = await _accessService
              .validateRootFolderCreationWithCountAsync(rootCount);
          if (rootValidation != null) {
            throw Exception(rootValidation);
          }
        } else {
          final childCount = realFolders
              .where((folder) => folder.parentId == currentParentId)
              .length;
          final depthValidation = await _accessService
              .validateHierarchyDepthForCreationAsync(i + 1);
          if (depthValidation != null) {
            throw Exception(depthValidation);
          }
          final childValidation = await _accessService
              .validateChildFolderCountForCreationAsync(childCount);
          if (childValidation != null) {
            throw Exception(childValidation);
          }
        }

        if (isRoot) {
          // Crea root folder
          await createPersistentFolder(folderName);
          print('DEBUG: Root folder creation triggered');
        } else {
          // Crea child folder
          // Trova MockFolder parent per chiamare createSubfolderInFolder
          await _createChildFolderWithParentId(currentParentId!, folderName);
          print('DEBUG: Child folder creation triggered');
        }

        // F. RETRY LOOP: verifica che la cartella sia stata creata
        bool creationConfirmed = false;
        Folder? createdFolder;

        for (int retry = 0; retry < maxRetries; retry++) {
          final delayMs = retryDelay.inMilliseconds;
          print(
              'DEBUG: ⏳ Retry $retry/${maxRetries - 1}: attendendo ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));

          // Invalida e ricarica completamente
          DataService.instance
              .invalidateCache(folders: true, posts: true); // ⭐ Anche posts
          await DataService.instance.reloadFromDisk();

          final verifyFolders = await DataService.instance.getFolders();
          print('DEBUG: Verifica: ${verifyFolders.length} cartelle in DB');

          // Cerca la cartella appena creata
          try {
            if (isRoot) {
              createdFolder = verifyFolders.firstWhere(
                (f) =>
                    f.name == folderName && !f.isDefault && f.parentId == null,
              );
            } else {
              createdFolder = verifyFolders.firstWhere(
                (f) => f.name == folderName && f.parentId == currentParentId,
              );
            }

            print('DEBUG: ✅ Creazione confermata! ID: ${createdFolder.id}');
            creationConfirmed = true;
            currentFolderId = createdFolder.id;
            currentParentId = createdFolder.id;
            break;
          } catch (e) {
            print('DEBUG: ⚠️ Retry $retry: cartella non ancora disponibile');

            if (retry == maxRetries - 1) {
              // Ultimo tentativo fallito
              print(
                  'DEBUG: ❌ Cartella "$folderName" non confermata dopo $maxRetries retry');

              // Fallback: cerca qualsiasi cartella con quel nome
              try {
                createdFolder = verifyFolders.firstWhere(
                  (f) => f.name == folderName && !f.isDefault,
                );
                print(
                    'DEBUG: ⚠️ Trovata cartella con nome corretto ma potrebbe avere parentId sbagliato');
                print(
                    'DEBUG: Usando ID: ${createdFolder.id} (parentId: ${createdFolder.parentId})');
                currentFolderId = createdFolder.id;
                currentParentId = createdFolder.id;
                creationConfirmed = true;
                break;
              } catch (fallbackError) {
                throw Exception(
                    'Impossibile confermare creazione di "$folderName" dopo $maxRetries tentativi. '
                    'La cartella potrebbe essere stata creata ma non è ancora visibile nel database.');
              }
            }
          }
        }

        if (!creationConfirmed) {
          throw Exception('Creazione cartella "$folderName" fallita');
        }

        print('DEBUG: ✅ Livello $i completato');
      }

      // STEP 4: Sincronizzazione finale COMPLETA
      print('DEBUG: 🔄 Sincronizzazione finale...');

      // FIX ANTEPRIME: Invalida anche posts per mantenere sincronizzazione
      DataService.instance.invalidateCache(folders: true, posts: true);

      // FIX: Delay ridotto per velocizzare
      await Future.delayed(Duration(milliseconds: 300));

      // Ricarica completa da Firebase
      await DataService.instance.reloadFromDisk();

      // FIX: Assicurati che la cache posts sia valida prima della sync
      try {
        await DataService.instance.getPosts();
        print('DEBUG: Cache posts verificata e valida');
      } catch (e) {
        print('DEBUG: Warning - posts cache reload: $e');
      }

      // Sync FolderService
      await syncWithDataService();

      print('DEBUG: ✅ Sincronizzazione completata');

      // STEP 5: Verifica finale
      if (currentFolderId == null) {
        throw Exception('ID finale nullo dopo creazione gerarchia');
      }

      final duration = endActionTiming('create_hierarchy_from_path');

      // Track analytics
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.folderStructureChanged,
        properties: {
          'action': 'hierarchy_created_from_path',
          'full_path': fullPath,
          'levels_created': pathParts.length,
          'final_folder_id': currentFolderId,
          'creation_time_ms': duration?.inMilliseconds,
          'retry_used': true,
        },
        actionDuration: duration,
      );

      print('DEBUG: ✅ ========== GERARCHIA CREATA CON SUCCESSO ==========');
      print('DEBUG: Path: $fullPath');
      print('DEBUG: ID finale: $currentFolderId');
      print('DEBUG: Tempo totale: ${duration?.inMilliseconds}ms');

      return currentFolderId;
    } catch (e, stackTrace) {
      print('DEBUG: ❌ ========== ERRORE CREAZIONE GERARCHIA ==========');
      print('DEBUG: Path: $fullPath');
      print('DEBUG: Errore: $e');
      print('DEBUG: Stack trace: $stackTrace');

      // Sync di emergenza
      try {
        await syncWithDataService();
      } catch (syncError) {
        print('DEBUG: Anche sync di emergenza fallito: $syncError');
      }

      rethrow;
    }
  }

  /// Helper privato per creare child folder con parentId
  Future<void> _createChildFolderWithParentId(
      String parentId, String folderName) async {
    print('DEBUG: Creando child folder "$folderName" con parentId: $parentId');

    // Accesso diretto a Firebase
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw Exception('Firebase user è null');
    }

    final firestore = FirebaseFirestore.instance;
    final foldersCollection = firestore
        .collection('users')
        .doc(firebaseUser.uid)
        .collection('folders');

    final folderData = {
      'name': folderName.trim(),
      'color':
          '#${FolderManagement.getRandomColor().value.toRadixString(16).substring(2)}',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDefault': false,
      'parentId': parentId,
    };

    final docRef = await foldersCollection.add(folderData);
    print(
        'DEBUG: Child folder creata con ID: ${docRef.id}, parentId: $parentId');
  }

  // ============================================================================
  // CREAZIONE CARTELLE (METODI ESISTENTI)
  // ============================================================================

  Future<void> createPersistentFolder(String name) async {
    startActionTiming('create_folder');

    try {
      print('DEBUG: ========== CREAZIONE CARTELLA ROOT ==========');
      print('DEBUG: Nome: $name');

      _resyncAuthStateIfNeeded();
      if (!isAuthenticated || currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final rootCount = folders
          .where((folder) => !folder.isSpecial && folder.level == 0)
          .length;
      final rootValidation = await _accessService
          .validateRootFolderCreationWithCountAsync(rootCount);
      if (rootValidation != null) {
        throw Exception(rootValidation);
      }

      // Refresh token
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.getIdToken(true);
        print('DEBUG: Token refreshato');
      } else {
        throw Exception('Firebase user is null');
      }

      // Accesso diretto Firestore
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('Firebase user is null');
      }

      final firestore = FirebaseFirestore.instance;
      final foldersCollection = firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('folders');

      // Prepara dati SENZA concatenazione gerarchica
      final folderData = {
        'name': name.trim(), // SOLO il nome, NON "A › B"
        'color':
            '#${FolderManagement.getRandomColor().value.toRadixString(16).substring(2)}',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isDefault': false,
        'parentId': null, // root folder ha parentId null
        'isShared': false, // 🆕 NUOVO
      };

      // Creazione diretta
      final docRef = await foldersCollection.add(folderData);
      print('DEBUG: Cartella ROOT creata con ID: ${docRef.id}');

      // Aggiorna memoria
      final newFolder = MockFolder(
        id: docRef.id,
        name: name.trim(),
        count: 'Vuota',
        color: FolderManagement.getRandomColor(),
        level: 0,
        parent: null,
        isShared: false, // 🆕 NUOVO
      );

      folders = List.from(folders)..add(newFolder);
      updateTuttiCount();

      if (currentUserId != null) {
        cacheUserData(currentUserId!);
      }
      notifyDataChanged();

      // Track
      final duration = endActionTiming('create_folder');
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.folderStructureChanged,
        properties: {
          'action': 'folder_created',
          'folder_name': name,
          'creation_time_ms': duration?.inMilliseconds,
          'is_root': true,
        },
        actionDuration: duration,
      );
    } catch (e) {
      print('ERRORE: Creazione cartella fallita: $e');
      throw Exception('Impossibile creare la cartella: ${e.toString()}');
    }
  }

  Future<void> createSubfolderInFolder(
      MockFolder parentFolder, String name) async {
    final subfolderValidation =
        await _accessService.validateSubfolderCreationAsync(parentFolder);
    if (subfolderValidation != null) {
      throw Exception(subfolderValidation);
    }

    startActionTiming('create_subfolder');

    try {
      print('DEBUG: ========== CREAZIONE SOTTOCARTELLA ==========');
      print('DEBUG: Parent: ${parentFolder.name}');
      print('DEBUG: Child: $name');

      _resyncAuthStateIfNeeded();
      if (!isAuthenticated || currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final normalizedName = FolderManagement.capitalizeFirst(name.trim());

      // 🔥 FIX 1: Verifica se la sottocartella esiste già localmente
      final existingChild = parentFolder.children.firstWhere(
        (child) => child.name.toLowerCase() == normalizedName.toLowerCase(),
        orElse: () =>
            MockFolder(name: '', count: '', color: Colors.grey, level: -1),
      );

      if (existingChild.level != -1) {
        print(
            'DEBUG: ⚠️ Sottocartella "$normalizedName" esiste già localmente');
        throw Exception('Una cartella con questo nome esiste già');
      }

      // Refresh token
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.getIdToken(true);
      }

      // IMPORTANTE: NON invalidare cache per forzare reload dal database per ogni operazione
      // DataService.instance.invalidateCache(folders: true, posts: true);

      // Trova l'ID della cartella parent
      String? parentId = parentFolder.id;

      // Se l'ID non è presente nel MockFolder, prova a trovarlo nei dati in memoria
      if (parentId == null) {
        print(
            'DEBUG: ID parent non trovato nel MockFolder, cerco nel database...');
        try {
          // Usa cache se disponibile, altrimenti rete (ma non forza refresh)
          final realFolders = await DataService.instance.getFolders();
          final realParent =
              findRealFolderByMockFolder(realFolders, parentFolder);
          parentId = realParent?.id;
        } catch (e) {
          print('WARNING: Errore ricerca parent nel database: $e');
        }
      } else {
        print('DEBUG: Usando parentId dal MockFolder: $parentId');
      }

      if (parentId == null) {
        throw Exception(
            'Cartella parent non trovata nel database (ID mancante)');
      }

      // Controllo duplicati ottimizzato (usa dati in memoria se possibile)
      // Nota: validateFolderName ha già fatto un controllo locale

      // Crea sottocartella con parentId
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser!;
      final firestore = FirebaseFirestore.instance;
      final foldersCollection = firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('folders');

      final folderData = {
        'name': normalizedName,
        'color':
            '#${FolderManagement.getRandomColor().value.toRadixString(16).substring(2)}',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isDefault': false,
        'parentId': parentId,
        'isShared': false, // 🆕 NUOVO
      };

      // AGGIORNAMENTO OTTIMISTICO UI IMMEDIATO
      final newMockFolder = MockFolder(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}', // ID temporaneo
        name: normalizedName,
        count: 'Vuota',
        color: FolderManagement
            .getRandomColor(), // Colore temporaneo, sarà sovrascritto dal DB
        level: parentFolder.level + 1,
        parent: parentFolder,
        children: [],
        isShared: false, // 🆕 NUOVO
      );

      parentFolder.children.add(newMockFolder);
      updateTuttiCount();
      notifyDataChanged(); // Aggiorna UI subito!

      // ESEGUI CHIAMATA NETWORK ASINCRONA
      final docRef = await foldersCollection.add(folderData);
      print(
          'DEBUG: Sottocartella creata con ID: ${docRef.id}, parentId: $parentId');

      // Aggiorna l'ID reale nel MockFolder
      newMockFolder.id = docRef.id;

      // Sync silenzioso in background per assicurare consistenza
      _backgroundSyncAfterChange('folder_created');

      final duration = endActionTiming('create_subfolder');
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.folderStructureChanged,
        properties: {
          'action': 'subfolder_created',
          'folder_name': normalizedName,
          'parent_name': parentFolder.name,
          'level': parentFolder.level + 1,
          'creation_time_ms': duration?.inMilliseconds,
        },
        actionDuration: duration,
      );

      analytics.trackFolderCreated(normalizedName);
    } catch (e) {
      print('ERRORE: Creazione sottocartella fallita: $e');

      // Revert ottimistico se necessario (opzionale, per ora sync di emergenza)
      try {
        await syncWithDataService();
      } catch (syncError) {
        print('DEBUG: Sync di emergenza fallito: $syncError');
      }

      rethrow;
    }
  }

  // Helper per sync background
  void _backgroundSyncAfterChange(String reason) {
    Future.delayed(Duration(seconds: 1), () async {
      try {
        print('DEBUG: Eseguendo sync background per: $reason');
        DataService.instance.invalidateCache(folders: true);
        await syncWithDataService();
      } catch (e) {
        print('DEBUG: Sync background fallito: $e');
      }
    });
  }

  // ============================================================================
  // HELPER METHODS PER TROVARE CARTELLE
  // ============================================================================

  /// Costruisce il path completo di una cartella per identificarla
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

  // NOTA: findRealFolderByMockFolder() è ora in folder_service_base.dart

  // ============================================================================
  // ELIMINAZIONE CARTELLE
  // ============================================================================

  Future<void> deleteFolder(MockFolder folder) async {
    if (folder.isSpecial) return;

    startActionTiming('delete_folder');

    try {
      await executeAuthenticatedOperation(() async {
        final impactAnalysis = await analyzeDeletionImpact(folder);

        // OPTIMIZATION: Non forzare refresh completi prima dell'operazione
        // await DataService.instance.initializeDefaultData();
        // DataService.instance.invalidateCache(folders: true, posts: true);

        String? folderId = folder.id;

        // Se ID mancante nel MockFolder, cercalo nella cache
        if (folderId == null) {
          print(
              'DEBUG: ID folder mancante nel MockFolder, cerco nella cache...');
          final realFolders =
              await DataService.instance.getFolders(forceRefresh: false);
          final realFolder = findRealFolderByMockFolder(realFolders, folder);
          folderId = realFolder?.id;
        }

        if (folderId == null) {
          print(
              'ERRORE CRITICO: Cartella "${folder.name}" non trovata (ID mancante)');
          throw Exception('Cartella "${folder.name}" non trovata. '
              'Potrebbe essere un problema di sincronizzazione. '
              'Prova a ricaricare la pagina.');
        }

        print('DEBUG: Eliminando cartella: ${folder.name} (ID: $folderId)');

        // ELIMINAZIONE ASINCRONA
        await DataService.instance.deleteFolder(folderId);

        analytics.trackFolderDeleted(folder.name);

        final duration = endActionTiming('delete_folder');
        advancedAnalytics.trackAdvancedEvent(
          AdvancedEventType.folderStructureChanged,
          properties: {
            'action': 'folder_deleted',
            'folder_name': folder.name,
            'posts_affected': impactAnalysis['postsAffected'],
            'deletion_time_ms': duration?.inMilliseconds,
          },
          actionDuration: duration,
        );

        // AGGIORNAMENTO UI OTTIMISTICO
        folders = List.from(folders)..removeWhere((f) => f == folder);
        removeFromAllParents(folder);
        updateTuttiCount();

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }
        notifyDataChanged();

        // Sync silenzioso in background
        _backgroundSyncAfterChange('folder_deleted');
      }, 'delete_folder');
    } catch (e) {
      print('ERRORE: Eliminazione fallita: $e');
      await syncWithDataService();
      throw Exception('Impossibile eliminare la cartella: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> analyzeDeletionImpact(MockFolder folder) async {
    int postsAffected = 0;
    int subfoldersAffected = 0;

    postsAffected +=
        allPosts.where((post) => post.sourceFolder == folder).length;

    void countRecursively(MockFolder currentFolder) {
      subfoldersAffected += currentFolder.children.length;

      for (final child in currentFolder.children) {
        postsAffected +=
            allPosts.where((post) => post.sourceFolder == child).length;
        countRecursively(child);
      }
    }

    countRecursively(folder);

    return {
      'postsAffected': postsAffected,
      'subfoldersAffected': subfoldersAffected,
      'message': postsAffected > 0
          ? 'I $postsAffected post rimarranno accessibili in "Tutti"'
          : 'Nessun post verrà spostato',
    };
  }

  void removeFromAllParents(MockFolder folderToRemove) {
    for (var folder in folders) {
      removeFromChildren(folder, folderToRemove);
    }
  }

  void removeFromChildren(MockFolder parent, MockFolder folderToRemove) {
    if (parent.children.contains(folderToRemove)) {
      parent.children = List.from(parent.children)..remove(folderToRemove);
    }
    for (var child in parent.children) {
      removeFromChildren(child, folderToRemove);
    }
  }

  // ============================================================================
  // MODIFICA CARTELLE
  // ============================================================================

  Future<void> renameFolder(MockFolder folder, String newName) async {
    print('DEBUG: ========== RINOMINA CARTELLA ==========');
    print('DEBUG: Nome vecchio: ${folder.name}');
    print('DEBUG: Nome nuovo: $newName');

    if (folder.isSpecial) {
      throw Exception('Impossibile rinominare la cartella speciale "Tutti"');
    }

    final capitalizedName = FolderManagement.capitalizeFirst(newName);

    // 🔥 FIX: Validazione nome escludendo la cartella corrente per permettere cambio maiuscole/minuscole
    final validationError = validateFolderName(capitalizedName,
        parent: folder.parent, excludeFolder: folder);
    if (validationError != null) {
      throw Exception(validationError);
    }

    try {
      // STEP 1: Salva il nome vecchio
      final oldName = folder.name;

      // STEP 2: Trova il Folder reale su Firebase PRIMA di cambiare il nome
      final realFolders = await DataService.instance.getFolders();
      final realFolder = findRealFolderByMockFolder(realFolders, folder);

      if (realFolder == null) {
        throw Exception('Cartella non trovata su Firebase');
      }

      print(
          'DEBUG: Cartella reale trovata: ${realFolder.name} (${realFolder.id})');

      // STEP 3: Aggiorna in memoria (ottimistico)
      folder.name = capitalizedName;
      updateTuttiCount();
      notifyDataChanged();

      print(
          'DEBUG: Nome aggiornato in memoria: ${oldName} → ${capitalizedName}');

      // STEP 4: Aggiorna su Firebase
      final updatedFolder = realFolder.copyWith(
        name: capitalizedName,
        updatedAt: DateTime.now(),
      );

      await DataService.instance.saveFolder(updatedFolder);

      print('DEBUG: Cartella aggiornata su Firebase');

      // STEP 5: Aggiorna cache con i nuovi dati invece di invalidarla
      if (currentUserId != null) {
        cacheUserData(currentUserId!);
        print('DEBUG: Cache aggiornata con nuovo nome');
      }

      print('DEBUG: ✅ Rinomina completata con successo');
    } catch (e) {
      print('DEBUG: ❌ Errore rinomina: $e');

      // Rollback in caso di errore
      await syncWithDataService();

      rethrow;
    }
  }

  Future<void> moveFolder(
      MockFolder folderToMove, MockFolder? destination) async {
    if (folderToMove.isSpecial) return;

    // 🔥 FIX: Trova l'istanza "viva" in memoria per preservare i link ai post
    MockFolder folderToUse = _findAliveFolder(folderToMove) ?? folderToMove;

    MockFolder? destinationToUse = destination;
    if (destination != null) {
      destinationToUse = _findAliveFolder(destination) ?? destination;
    }

    if (!FolderManagement.canMoveFolder(folderToUse, destinationToUse)) return;

    startActionTiming('move_folder');

    try {
      print(
          'DEBUG: Spostamento cartella "${folderToUse.name}" verso "${destinationToUse?.name ?? "Home"}"');

      // 1. Aggiornamento Ottimistico UI (In Memoria)
      bool removed = false;

      if (folderToUse.parent != null) {
        final oldParent = folderToUse.parent!;
        oldParent.children = List.from(oldParent.children)..remove(folderToUse);
        removed = true;
      } else {
        folders = List.from(folders)..remove(folderToUse);
        removed = true;
      }

      if (!removed) {
        print(
            'WARNING: Impossibile trovare la cartella da rimuovere nella struttura locale');
      }

      folderToUse.parent = destinationToUse;

      if (destinationToUse != null) {
        folderToUse.level = destinationToUse.level + 1;
        destinationToUse.children = List.from(destinationToUse.children)
          ..add(folderToUse);
      } else {
        folderToUse.level = 0;
        folders = List.from(folders)..add(folderToUse);
      }

      FolderManagement.updateSubfolderLevels(folderToUse);
      updateTuttiCount();
      notifyDataChanged();

      // 2. Persistenza su Firebase
      await executeAuthenticatedOperation(() async {
        // Ricarica cartelle fresche per avere ID corretti
        final realFolders = await DataService.instance.getFolders();

        // Tenta di trovare la cartella sorgente
        Folder? realFolderToMove =
            findRealFolderByMockFolder(realFolders, folderToUse);

        // Fallback: Se non trovata per path esatto, cerca per nome (case-insensitive)
        if (realFolderToMove == null) {
          print(
              'WARNING: Cartella sorgente non trovata per path, tento ricerca per nome...');
          try {
            realFolderToMove = realFolders.firstWhere((f) =>
                f.name.toLowerCase() == folderToUse.name.toLowerCase() &&
                !f.isDefault);
            print(
                'DEBUG: Fallback riuscito: trovata cartella ${realFolderToMove.name} (${realFolderToMove.id})');
          } catch (_) {
            // Fallito anche il fallback
          }
        }

        if (realFolderToMove == null) {
          // Ultimo tentativo disperato: refresh cache forzato
          print(
              'WARNING: Fallback fallito. Provo reload forzato cache e riprovo...');
          DataService.instance.invalidateCache(folders: true, posts: true);
          final freshFolders = await DataService.instance.getFolders();

          try {
            realFolderToMove = freshFolders.firstWhere((f) =>
                f.name.toLowerCase() == folderToUse.name.toLowerCase() &&
                !f.isDefault);
          } catch (_) {}

          if (realFolderToMove == null) {
            throw Exception(
                'Cartella sorgente "${folderToUse.name}" non trovata nel database');
          }
        }

        String? newParentId;
        if (destinationToUse != null) {
          Folder? realDestination =
              findRealFolderByMockFolder(realFolders, destinationToUse);

          // Fallback anche per destinazione
          if (realDestination == null) {
            print(
                'WARNING: Cartella destinazione non trovata per path, tento ricerca per nome...');
            try {
              realDestination = realFolders.firstWhere((f) =>
                  f.name.toLowerCase() ==
                      destinationToUse!.name.toLowerCase() &&
                  !f.isDefault);
            } catch (_) {}
          }

          if (realDestination == null) {
            throw Exception(
                'Cartella destinazione "${destinationToUse.name}" non trovata nel database');
          }
          newParentId = realDestination.id;
        }

        print(
            'DEBUG: Aggiornamento DB - FolderID: ${realFolderToMove.id}, NewParentID: $newParentId');

        final updatedFolder = realFolderToMove.copyWith(
          parentId: newParentId,
          updatedAt: DateTime.now(),
        );

        await DataService.instance.saveFolder(updatedFolder);

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }
      }, 'move_folder');

      final duration = endActionTiming('move_folder');
      print('DEBUG: ✅ Spostamento completato e salvato');
    } catch (e) {
      print('ERRORE: Spostamento fallito: $e');
      // Rollback stato in caso di errore (ricarica tutto)
      await syncWithDataService();
      rethrow;
    }
  }

  /// Helper per trovare l'istanza viva di una cartella nella struttura in memoria corrente
  MockFolder? _findAliveFolder(MockFolder target) {
    // 1. Cerca per uguaglianza diretta (se è già l'oggetto giusto)
    if (folders.contains(target)) return target;

    // 2. Cerca per path
    final path = buildFullPathForFolder(target);
    final parts = path.split(' › ');
    if (parts.isEmpty) return null;

    // Normalizza nomi (rimuovi Home se presente)
    if (parts[0] == 'Home') parts.removeAt(0);
    if (parts.isEmpty) return null;

    MockFolder? current;

    // Cerca nella root
    try {
      current = folders.firstWhere((f) => !f.isSpecial && f.name == parts[0],
          orElse: () =>
              MockFolder(name: '', count: '', color: Colors.grey, level: -1));
    } catch (_) {}

    if (current == null || current.level == -1) return null;

    // Cerca nei figli
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

  // ============================================================================
  // OPERAZIONI POST
  // ============================================================================

  Future<void> movePost(MockPost post, MockFolder? newFolder) async {
    if (newFolder != null && !newFolder.isSpecial) {
      final destinationError =
          await _accessService.validateFolderDestinationAsync(newFolder);
      if (destinationError != null) {
        throw Exception(destinationError);
      }
    }

    try {
      await executeAuthenticatedOperation(() async {
        final postIndex = allPosts.indexWhere((p) => p.id == post.id);
        if (postIndex == -1) return;

        final updatedPost = MockPost(
          id: post.id,
          title: post.title,
          url: post.url,
          description: post.description,
          savedDate: post.savedDate,
          sourceFolder: newFolder,
          tags: List.from(post.tags),
          imageUrl: post.imageUrl,
        );

        allPosts[postIndex] = updatedPost;
        updateTuttiCount();

        // Trova folder ID reale
        final realFolders = await DataService.instance.getFolders();
        String targetFolderId;

        if (newFolder == null || newFolder.isSpecial) {
          targetFolderId = realFolders.firstWhere((f) => f.isDefault).id;
        } else {
          final realFolder = findRealFolderByMockFolder(realFolders, newFolder);
          if (realFolder != null) {
            targetFolderId = realFolder.id;
          } else {
            targetFolderId = realFolders.firstWhere((f) => f.isDefault).id;
          }
        }

        // Aggiorna database
        final realPosts = await DataService.instance.getPosts();
        final realPost = realPosts.firstWhere((p) => p.id == post.id);

        final updatedRealPost = realPost.copyWith(
          folderId: targetFolderId,
          updatedAt: DateTime.now(),
        );

        await DataService.instance.savePost(updatedRealPost);

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }
        notifyDataChanged();
      }, 'move_post');
    } catch (e) {
      print('ERRORE: Spostamento post fallito: $e');
      await syncWithDataService();
      throw Exception('Impossibile spostare il post: ${e.toString()}');
    }
  }

  Future<void> deletePost(String postId) async {
    try {
      await executeAuthenticatedOperation(() async {
        final postIndex = allPosts.indexWhere((post) => post.id == postId);
        if (postIndex == -1) {
          throw Exception('Post non trovato');
        }

        await DataService.instance.deletePost(postId);

        allPosts.removeAt(postIndex);
        updateTuttiCount();

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }
        notifyDataChanged();

        // Verifica
        final verification = await DataService.instance.getPosts();
        final stillExists = verification.any((p) => p.id == postId);

        if (stillExists) {
          throw Exception('Verifica fallita');
        }
      }, 'delete_post');
    } catch (e) {
      print('ERRORE: Eliminazione post fallita: $e');
      await syncWithDataService();
      throw Exception('Impossibile eliminare il post: ${e.toString()}');
    }
  }

  Future<void> updatePostTags(String postId, List<String> newTags) async {
    if (!_accessService.canManageManualTags) {
      throw Exception('I tag manuali non sono disponibili per il tuo piano');
    }

    try {
      await executeAuthenticatedOperation(() async {
        final postIndex = allPosts.indexWhere((post) => post.id == postId);
        if (postIndex == -1) {
          throw Exception('Post non trovato');
        }

        // Aggiorna in memoria locale
        allPosts[postIndex].tags.clear();
        allPosts[postIndex].tags.addAll(newTags);

        // 🔥 FIX CRITICO: Salva nel database
        final realPosts = await DataService.instance.getPosts();
        final realPost = realPosts.firstWhere((p) => p.id == postId);

        final updatedRealPost = realPost.copyWith(
          tags: newTags,
          updatedAt: DateTime.now(),
        );

        await DataService.instance.savePost(updatedRealPost);

        if (currentUserId != null) {
          cacheUserData(currentUserId!);
        }
        notifyDataChanged();

        print(
            'DEBUG: Hashtag aggiornati per post $postId: ${newTags.join(", ")}');
      }, 'update_post_tags');
    } catch (e) {
      print('ERRORE: Aggiornamento hashtag fallito: $e');
      await syncWithDataService();
      throw Exception('Impossibile aggiornare gli hashtag: ${e.toString()}');
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

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

  List<MockPost> getPostsForFolder(MockFolder folder) {
    if (folder.isSpecial) {
      final posts = List<MockPost>.from(allPosts);
      posts.sort((a, b) => b.savedDate.compareTo(a.savedDate));
      return posts;
    }

    final targetPath = buildFullPathForFolder(folder);

    // 🔥 FIX: Confronto robusto basato sul path completo per evitare ambiguità
    // Questo risolve il problema di cartelle con lo stesso nome in sottocartelle diverse
    final posts = allPosts.where((post) {
      // 1. Prova confronto referenziale (veloce)
      if (post.sourceFolder == folder) return true;

      // 2. Se fallisce, prova confronto per path completo (case-insensitive)
      if (post.sourceFolder != null) {
        final sourcePath = buildFullPathForFolder(post.sourceFolder!);
        return sourcePath.toLowerCase() == targetPath.toLowerCase();
      }
      return false;
    }).toList();

    posts.sort((a, b) => b.savedDate.compareTo(a.savedDate));
    return posts;
  }

  List<MockPost> getAllPostsInFolderRecursive(MockFolder folder) {
    if (folder.isSpecial) {
      final posts = List<MockPost>.from(allPosts);
      posts.sort((a, b) => b.savedDate.compareTo(a.savedDate));
      return posts;
    }

    List<MockPost> allPostsInHierarchy = [];

    void collectPostsRecursively(MockFolder currentFolder) {
      final targetPath = buildFullPathForFolder(currentFolder);
      allPostsInHierarchy.addAll(allPosts.where((post) {
        if (post.sourceFolder == currentFolder) return true;
        if (post.sourceFolder?.id != null && currentFolder.id != null) {
          if (post.sourceFolder!.id == currentFolder.id) return true;
        }
        if (post.sourceFolder != null) {
          final sourcePath = buildFullPathForFolder(post.sourceFolder!);
          return sourcePath.toLowerCase() == targetPath.toLowerCase();
        }
        return false;
      }));

      for (var child in currentFolder.children) {
        collectPostsRecursively(child);
      }
    }

    collectPostsRecursively(folder);
    allPostsInHierarchy.sort((a, b) => b.savedDate.compareTo(a.savedDate));

    return allPostsInHierarchy;
  }

  // Metodi astratti da sincronizzazione
  void updateTuttiCount();
  Future<void> syncWithDataService();
}
