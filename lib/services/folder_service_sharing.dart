// File: lib/services/folder_service_sharing.dart
// Sharing service con ricerca corretta usando parentId

import 'package:flutter/material.dart';
import 'package:savein/models/folder.dart';
import 'package:savein/data_service.dart';
import '../advanced_analytics_models.dart';
import 'package:savein/models.dart';

import 'folder_service_models.dart';
import 'folder_service_base.dart';

/// Mixin per funzionalità sharing con supporto parentId
mixin FolderServiceSharing on FolderServiceBase {
  // ============================================================================
  // DATI PER POPUP SHARING
  // ============================================================================

  List<Map<String, dynamic>> getFoldersForPopupSelection() {
    List<Map<String, dynamic>> folderOptions = [];

    if (folders.isEmpty) {
      print('ERRORE: folders vuoto');
      folderOptions.add({
        'id': 'tutti',
        'name': 'Tutti',
        'displayName': '📁 Tutti (default)',
        'path': '',
        'isDefault': true,
        'color': Colors.purple.shade200.value,
        'description': 'Salva senza cartella specifica',
      });
      return folderOptions;
    }

    final tuttiFolder = folders.firstWhere(
      (f) => f.isSpecial,
      orElse: () => MockFolder(
        name: 'Tutti',
        count: '0 Post',
        color: Colors.purple.shade200,
        level: 0,
        isSpecial: true,
      ),
    );

    folderOptions.add({
      'id': 'tutti',
      'name': 'Tutti',
      'displayName': '📁 Tutti (default)',
      'path': '',
      'isDefault': true,
      'color': tuttiFolder.color.value,
      'description': 'Salva senza cartella specifica',
    });

    void addFolderRecursively(MockFolder folder, String parentPath, int level) {
      if (folder.isSpecial) return;

      final currentPath =
          parentPath.isEmpty ? folder.name : '$parentPath › ${folder.name}';
      final indent = '  ' * level;

      // Usa un ID univoco basato sul path completo
      final uniqueId =
          currentPath.toLowerCase().replaceAll(' ', '_').replaceAll('›', '_');

      folderOptions.add({
        'id': uniqueId,
        'name': folder.name,
        'displayName': '$indent📂 ${folder.name}',
        'path': currentPath, // Path completo per identificazione
        'fullPath': currentPath,
        'level': level,
        'isDefault': false,
        'color': folder.color.value,
        'description': folder.count,
        'hasChildren': folder.children.isNotEmpty,
      });

      for (var child in folder.children) {
        addFolderRecursively(child, currentPath, level + 1);
      }
    }

    for (var folder in folders) {
      if (!folder.isSpecial) {
        addFolderRecursively(folder, '', 0);
      }
    }

    return folderOptions;
  }

  Map<String, dynamic> getCompleteDataForSharingPopupUltraFast() {
    try {
      if (folders.isEmpty) {
        return {
          'folders': [
            {
              'id': 'tutti',
              'name': 'Tutti',
              'displayName': '📁 Tutti (default)',
              'path': '',
              'isDefault': true,
              'color': Colors.purple.shade200.value,
            }
          ],
          'stats': {
            'tutti': {'postCount': 0, 'displayText': 'Nessun post'}
          },
          'defaultFolderId': 'tutti',
          'totalFolders': 0,
          'totalPosts': 0,
          'isUltraFast': true,
          'isEmergencyMode': true,
        };
      }

      List<Map<String, dynamic>> folderOptions = [];

      folderOptions.add({
        'id': 'tutti',
        'name': 'Tutti',
        'displayName': '📁 Tutti (default)',
        'path': '',
        'isDefault': true,
        'color': Colors.purple.shade200.value,
        'description': 'Salva senza cartella specifica',
      });

      for (var folder in folders) {
        if (!folder.isSpecial) {
          folderOptions.add({
            'id': folder.name.toLowerCase().replaceAll(' ', '_'),
            'name': folder.name,
            'displayName': '📂 ${folder.name}',
            'path': folder.name,
            'isDefault': false,
            'color': folder.color.value,
            'description': folder.count,
          });
        }
      }

      return {
        'folders': folderOptions,
        'stats': {
          'tutti': {
            'postCount': allPosts.length,
            'displayText': '${allPosts.length} post'
          }
        },
        'defaultFolderId': 'tutti',
        'totalFolders': folderOptions.length - 1,
        'totalPosts': allPosts.length,
        'isUltraFast': true,
      };
    } catch (e) {
      return {
        'folders': [
          {
            'id': 'tutti',
            'name': 'Tutti',
            'displayName': '📁 Tutti (default)',
            'path': '',
            'isDefault': true,
            'color': Colors.purple.shade200.value,
          }
        ],
        'stats': {
          'tutti': {'postCount': 0, 'displayText': 'Nessun post'}
        },
        'defaultFolderId': 'tutti',
        'isUltraFast': true,
        'isEmergencyMode': true,
      };
    }
  }

  Future<Map<String, dynamic>> getCompleteDataForSharingPopup() async {
    try {
      if (folders.isEmpty) {
        try {
          await syncWithDataService();
        } catch (syncError) {
          print('ERRORE: Sync emergenza fallita: $syncError');
        }

        if (folders.isEmpty) {
          return getCompleteDataForSharingPopupUltraFast();
        }
      }

      final foldersData = getFoldersForPopupSelection();
      final statsData = getFolderStatsForPopup();

      syncInBackground();

      return {
        'folders': foldersData,
        'stats': statsData,
        'defaultFolderId': 'tutti',
        'totalFolders': folders.length - 1,
        'totalPosts': allPosts.length,
        'isOptimized': true,
      };
    } catch (e) {
      return getCompleteDataForSharingPopupUltraFast();
    }
  }

  void syncInBackground() {
    Future.microtask(() async {
      try {
        await syncWithDataService();
      } catch (e) {
        updateHealthStatus(ServiceHealthStatus.degraded,
            errorMessage: 'Background sync failed: $e');
      }
    });
  }

  Map<String, dynamic> getFolderStatsForPopup() {
    final stats = <String, dynamic>{};

    stats['tutti'] = {
      'postCount': allPosts.length,
      'displayText': '${allPosts.length} post totali',
    };

    if (folders.isEmpty) return stats;

    void addStatsRecursively(MockFolder folder, String parentPath) {
      if (folder.isSpecial) return;

      final currentPath =
          parentPath.isEmpty ? folder.name : '$parentPath › ${folder.name}';
      final postCount = getPostsForFolder(folder).length;
      final folderId =
          currentPath.toLowerCase().replaceAll(' ', '_').replaceAll('›', '_');

      stats[folderId] = {
        'postCount': postCount,
        'displayText': postCount == 0 ? 'Vuota' : '$postCount post',
      };

      for (var child in folder.children) {
        addStatsRecursively(child, currentPath);
      }
    }

    for (var folder in folders) {
      if (!folder.isSpecial) {
        addStatsRecursively(folder, '');
      }
    }

    return stats;
  }

  // ============================================================================
  // SALVATAGGIO POST CONDIVISI - FIX PRINCIPALE
  // ============================================================================

  Future<SharedPostSaveResult> saveSharedPostWithOptionalFolder({
    required String url,
    required String title,
    required String description,
    String? imageUrl,
    String? previewStorageUrl,
    String? creatorName,
    String? creatorUsername,
    List<String> tags = const [],
    String? selectedFolderId,
    String? selectedFolderPath, // Path completo es. "A › B"
    bool markAsImported = true,
  }) async {
    startActionTiming('save_shared_post');

    try {
      return await executeAuthenticatedOperation(() async {
        if (folders.isEmpty) {
          await syncWithDataService();

          if (folders.isEmpty) {
            throw Exception('Impossibile caricare cartelle');
          }
        }

        advancedAnalytics.detectDuplicateContent(url, title);

        final realFolders = await DataService.instance.getFolders();

        String realFolderId;
        String targetFolderDisplayName;
        MockFolder? targetMockFolder;

        print('DEBUG: ========== SALVATAGGIO POST CONDIVISO ==========');
        print('DEBUG: selectedFolderPath: $selectedFolderPath');
        print('DEBUG: selectedFolderId: $selectedFolderId');

        if (selectedFolderId != null && selectedFolderId.isNotEmpty) {
          final matchingFolders =
              realFolders.where((folder) => folder.id == selectedFolderId);
          final selectedRealFolder =
              matchingFolders.isEmpty ? null : matchingFolders.first;

          if (selectedRealFolder == null) {
            print(
                'WARNING: Folder ID $selectedFolderId non trovata, usando Tutti');
            final defaultFolder =
                realFolders.firstWhere((folder) => folder.isDefault);
            realFolderId = defaultFolder.id;
            targetFolderDisplayName = 'Tutti';
            targetMockFolder = folders.firstWhere((folder) => folder.isSpecial);
          } else {
            realFolderId = selectedRealFolder.id;
            targetFolderDisplayName = selectedRealFolder.isDefault
                ? 'Tutti'
                : (selectedFolderPath?.isNotEmpty == true
                    ? selectedFolderPath!
                    : selectedRealFolder.name);
            targetMockFolder = findMockFolderByRealId(selectedRealFolder.id);
            if (selectedRealFolder.isDefault && targetMockFolder == null) {
              targetMockFolder =
                  folders.firstWhere((folder) => folder.isSpecial);
            }
            print(
                'DEBUG: Trovata cartella tramite ID: ${selectedRealFolder.name} (${selectedRealFolder.id})');
          }
        } else if (selectedFolderPath == null ||
            selectedFolderPath.isEmpty ||
            selectedFolderPath == 'Tutti') {
          // Salva in "Tutti"
          final defaultFolder = realFolders.firstWhere(
            (f) => f.isDefault,
            orElse: () => throw Exception('Cartella Tutti non trovata'),
          );
          realFolderId = defaultFolder.id;
          targetFolderDisplayName = 'Tutti';
          targetMockFolder = folders.firstWhere((f) => f.isSpecial);

          print('DEBUG: Salvando in Tutti');
        } else {
          // Cerca la cartella usando il path completo
          print('DEBUG: Cercando cartella con path: $selectedFolderPath');

          // NUOVO: Trova MockFolder usando il path
          targetMockFolder = findMockFolderByPath(selectedFolderPath);

          if (targetMockFolder == null) {
            print(
                'WARNING: MockFolder non trovata per path $selectedFolderPath, usando Tutti');
            final defaultFolder = realFolders.firstWhere((f) => f.isDefault);
            realFolderId = defaultFolder.id;
            targetFolderDisplayName = 'Tutti';
            targetMockFolder = folders.firstWhere((f) => f.isSpecial);
          } else {
            // NUOVO: Trova Folder reale usando parentId
            final realFolder =
                findRealFolderByMockFolder(realFolders, targetMockFolder);

            if (realFolder == null) {
              print('WARNING: Folder reale non trovata, usando Tutti');
              final defaultFolder = realFolders.firstWhere((f) => f.isDefault);
              realFolderId = defaultFolder.id;
              targetFolderDisplayName = 'Tutti';
            } else {
              realFolderId = realFolder.id;
              targetFolderDisplayName = selectedFolderPath;
              print(
                  'DEBUG: Trovata cartella reale: ${realFolder.name} (ID: ${realFolder.id})');
            }
          }
        }

        print('DEBUG: realFolderId finale: $realFolderId');
        print('DEBUG: targetFolderDisplayName: $targetFolderDisplayName');

        // Salva il post
        final savedPost = await DataService.instance.createPost(
          url: url,
          title: title,
          description: description,
          imageUrl: imageUrl,
          previewStorageUrl: previewStorageUrl,
          creatorName: creatorName,
          creatorUsername: creatorUsername,
          tags: tags,
          folderId: realFolderId,
          isShared: markAsImported,
        );

        print('DEBUG: Post salvato con ID: ${savedPost.id}');

        upsertMockPostFromSavedPost(
          savedPost,
          sourceFolder: targetMockFolder,
        );

        final duration = endActionTiming('save_shared_post');
        final socialNetwork = extractSocialNetwork(url);

        advancedAnalytics.trackAdvancedEvent(
          AdvancedEventType.actionPerformed,
          properties: {
            'action': 'shared_post_saved',
            'post_id': savedPost.id,
            'target_folder': targetFolderDisplayName,
            'target_folder_id': realFolderId,
            'social_network': socialNetwork,
            'save_time_ms': duration?.inMilliseconds,
            'global_post_reused': savedPost.globalPostId != null,
            'url_hash': savedPost.urlHash,
          },
          actionDuration: duration,
        );

        // Sync con ritardo
        syncWithDelayAndRetry();

        return SharedPostSaveResult(
          folderDisplayName: targetFolderDisplayName,
          savedPost: savedPost,
        );
      }, 'save_shared_post');
    } catch (e) {
      print('ERRORE: Salvataggio post condiviso fallito: $e');
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.actionPerformed,
        properties: {
          'action': 'shared_post_save_error',
          'error': e.toString(),
        },
      );

      throw Exception('Impossibile salvare il post: ${e.toString()}');
    }
  }

  // ============================================================================
  // HELPER METHODS PER TROVARE CARTELLE
  // ============================================================================

  /// Trova MockFolder usando path completo (es. "A › B")
  MockFolder? findMockFolderByPath(String path) {
    if (path.isEmpty) return null;

    // Rimuovi "Home › " se presente
    String cleanPath = path;
    if (cleanPath.startsWith('Home › ')) {
      cleanPath = cleanPath.substring(7);
    }

    final pathParts = cleanPath.split(' › ');
    print('DEBUG: Path parts: ${pathParts.join(", ")}');

    // Cerca la cartella root
    MockFolder? current = folders.firstWhere(
      (f) => !f.isSpecial && f.name == pathParts.first,
      orElse: () =>
          MockFolder(name: '', count: '', color: Colors.grey, level: -1),
    );

    if (current == null || current.level == -1) {
      print('DEBUG: Root folder "${pathParts.first}" non trovata');
      return null;
    }

    print('DEBUG: Root folder trovata: ${current.name}');

    // Naviga i children
    for (int i = 1; i < pathParts.length; i++) {
      final targetName = pathParts[i];
      print('DEBUG: Cercando child: $targetName');

      MockFolder? found;
      for (var child in current!.children) {
        if (child.name == targetName) {
          found = child;
          break;
        }
      }

      if (found == null) {
        print('DEBUG: Child "$targetName" non trovato');
        return null;
      }

      print('DEBUG: Child trovato: ${found.name}');
      current = found;
    }

    print('DEBUG: MockFolder finale trovata: ${current!.name}');
    return current;
  }

  /// Trova Folder reale (database) da MockFolder usando parentId
  Folder? findRealFolderByMockFolder(
      List<Folder> realFolders, MockFolder mockFolder) {
    // Costruisci catena di nomi dalla root
    List<String> mockPath = [];
    MockFolder? current = mockFolder;

    while (current != null && !current.isSpecial) {
      mockPath.insert(0, current.name);
      current = current.parent;
    }

    print('DEBUG: Cercando folder reale con path: ${mockPath.join(" › ")}');

    // Cerca seguendo la catena di parentId
    Folder? found;

    for (int i = 0; i < mockPath.length; i++) {
      final targetName = mockPath[i];

      if (i == 0) {
        // Root level - cerca senza parent (CASE INSENSITIVE)
        found = realFolders.firstWhere(
          (f) =>
              f.name.toLowerCase() == targetName.toLowerCase() &&
              !f.isDefault &&
              f.parentId == null,
          orElse: () => Folder(
            id: 'not_found',
            name: 'Not Found',
            color: '#000000',
            createdAt: DateTime.now(),
          ),
        );

        if (found.id == 'not_found') {
          print('DEBUG: Root folder "$targetName" non trovata');
          return null;
        }

        print('DEBUG: Root folder trovata: ${found.name} (ID: ${found.id})');
      } else {
        // Child level - cerca con parentId del previous (CASE INSENSITIVE)
        if (found == null) return null;

        final previousId = found.id;
        found = realFolders.firstWhere(
          (f) =>
              f.name.toLowerCase() == targetName.toLowerCase() &&
              f.parentId == previousId,
          orElse: () => Folder(
            id: 'not_found',
            name: 'Not Found',
            color: '#000000',
            createdAt: DateTime.now(),
          ),
        );

        if (found.id == 'not_found') {
          print(
              'DEBUG: Child folder "$targetName" con parent $previousId non trovata');
          return null;
        }

        print(
            'DEBUG: Child folder trovata: ${found.name} (ID: ${found.id}, parentId: ${found.parentId})');
      }
    }

    return found;
  }

  // ============================================================================
  // METODI LEGACY
  // ============================================================================

  Future<void> createFolderFromSharing(
      String folderName, String? parentPath) async {
    try {
      await executeAuthenticatedOperation(() async {
        if (parentPath != null && parentPath.isNotEmpty) {
          MockFolder? parentFolder = findMockFolderByPath(parentPath);

          if (parentFolder == null) {
            throw Exception('Cartella parent non trovata: $parentPath');
          }

          await createSubfolderInFolder(parentFolder, folderName);
        } else {
          await createPersistentFolder(folderName);
        }

        final verification = await verifyDataIntegrity();
        if (!verification['isConsistent']) {
          await syncWithDataService();
        }
      }, 'create_folder_from_sharing');
    } catch (e) {
      throw Exception('Impossibile creare la cartella: ${e.toString()}');
    }
  }

  Future<void> savePostFromSharing({
    required String url,
    required String title,
    required String description,
    String? imageUrl,
    String? creatorName,
    String? creatorUsername,
    required List<String> tags,
    required String folderPath,
  }) async {
    try {
      await saveSharedPostWithOptionalFolder(
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        creatorName: creatorName,
        creatorUsername: creatorUsername,
        tags: tags,
        selectedFolderPath: folderPath,
      );
    } catch (e) {
      throw e;
    }
  }

  Future<void> saveSharedPost({
    required String url,
    required String title,
    required String description,
    String? imageUrl,
    String? creatorName,
    String? creatorUsername,
    required List<String> tags,
    required String folderName,
  }) async {
    try {
      await saveSharedPostWithOptionalFolder(
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        creatorName: creatorName,
        creatorUsername: creatorUsername,
        tags: tags,
        selectedFolderPath: folderName,
      );
    } catch (e) {
      throw e;
    }
  }

  // ============================================================================
  // METODI UTILITY
  // ============================================================================

  bool isValidFolderId(String? folderId) {
    if (folderId == null || folderId.isEmpty || folderId == 'tutti') {
      return true;
    }

    return folders.any((folder) =>
        !folder.isSpecial &&
        folder.name.toLowerCase().replaceAll(' ', '_') == folderId);
  }

  String getFolderNameFromId(String? folderId) {
    if (folderId == null || folderId.isEmpty || folderId == 'tutti') {
      return 'Tutti';
    }

    final folder = folders.firstWhere(
      (f) =>
          !f.isSpecial && f.name.toLowerCase().replaceAll(' ', '_') == folderId,
      orElse: () => folders.first,
    );

    return folder.name;
  }

  // Metodi astratti da implementare
  List<MockPost> getPostsForFolder(MockFolder folder);
  Future<void> createSubfolderInFolder(MockFolder parentFolder, String name);
  Future<void> createPersistentFolder(String name);
  Future<void> syncWithDataService();
  Future<void> syncWithDelayAndRetry();
  Future<Map<String, dynamic>> verifyDataIntegrity();
  String? extractSocialNetwork(String url);
  void upsertMockPostFromSavedPost(
    SavedPost savedPost, {
    MockFolder? sourceFolder,
  });
}
