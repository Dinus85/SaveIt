import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:savein/data_service.dart';
import 'package:savein/models.dart';
import 'package:savein/services/folder_service.dart';
import 'package:savein/services/plan_limits_service.dart';
import 'package:savein/url_metadata_service.dart';

/// Sincronizza cartelle e import differiti con la Share Extension iOS.
///
/// L'extension non accede a Firebase: legge un catalogo locale nell'App Group
/// e accoda un file JSON. L'app principale importa la coda quando è attiva.
class ShareExtensionService {
  ShareExtensionService._();

  static final ShareExtensionService instance = ShareExtensionService._();

  static const MethodChannel _channel =
      MethodChannel('eu.savein.app/share_extension');
  static const String _saveEndpoint =
      'https://us-central1-saveit-app-1784d.cloudfunctions.net/savePostFromShare';

  bool _isRefreshing = false;
  StreamSubscription<User?>? _tokenSubscription;

  bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> refreshCatalogAndImport() async {
    if (!_isSupported || _isRefreshing) return;
    _ensureTokenSync();
    _isRefreshing = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await _clearSharedSession();
        return;
      }

      await _exportAuthSession(user);
      final folders = await DataService.instance.getFolders();
      if (folders.isEmpty) return;

      await _exportCatalog(user.uid, folders);
      await _importPendingShares(user.uid, folders);
      await _consumeDirectShareResult();
    } on MissingPluginException {
      // Il bridge esiste solo nel Runner iOS.
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Share Extension bridge non disponibile: ${error.message}',
        );
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Errore sincronizzazione Share Extension: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> exportCatalog() async {
    if (!_isSupported) return;
    _ensureTokenSync();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        await _clearSharedSession();
      } on MissingPluginException {
        // Il bridge esiste solo nel Runner iOS.
      }
      return;
    }

    try {
      await _exportAuthSession(user);
      final folders = await DataService.instance.getFolders();
      if (folders.isNotEmpty) {
        await _exportCatalog(user.uid, folders);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Errore export cartelle Share Extension: $error');
      }
    }
  }

  void _ensureTokenSync() {
    _tokenSubscription ??=
        FirebaseAuth.instance.idTokenChanges().listen((user) async {
      if (!_isSupported) return;
      try {
        if (user == null) {
          await _clearSharedSession();
        } else {
          await _exportAuthSession(user);
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Sync token Share Extension fallita: $error');
        }
      }
    });
  }

  Future<void> _exportAuthSession(User user) async {
    var tokenResult = await user.getIdTokenResult();
    final expiration = tokenResult.expirationTime;
    if (expiration == null ||
        expiration.difference(DateTime.now()) < const Duration(minutes: 5)) {
      tokenResult = await user.getIdTokenResult(true);
    }
    final token = tokenResult.token;
    final expiresAt = tokenResult.expirationTime;
    if (token == null || token.isEmpty || expiresAt == null) return;

    await _channel.invokeMethod<void>('exportAuthSession', {
      'schemaVersion': 1,
      'userId': user.uid,
      'idToken': token,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'saveEndpoint': _saveEndpoint,
    });
  }

  Future<void> _clearSharedSession() async {
    await _channel.invokeMethod<void>('clearCatalog');
    await _channel.invokeMethod<void>('clearAuthSession');
  }

  Future<void> _consumeDirectShareResult() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'consumeLastShareResult',
    );
    if (raw == null || raw.isEmpty) return;

    final destination = raw['destinationPath']?.toString() ?? 'cartella';
    final url = raw['url']?.toString() ?? '';
    final postId = raw['postId']?.toString() ?? '';
    if (kDebugMode) {
      debugPrint(
        'Share Extension: salvataggio diretto rilevato '
        '($postId) in $destination'
        '${url.isEmpty ? '' : ' → $url'}',
      );
    }

    if (postId.isNotEmpty && url.isNotEmpty) {
      await _enrichDirectSharePost(postId: postId, url: url);
    }

    DataService.instance.invalidateCache(folders: true, posts: true);
    await FolderService().forceRefreshFromDataService();
  }

  Future<void> _enrichDirectSharePost({
    required String postId,
    required String url,
  }) async {
    try {
      final posts = await DataService.instance.getPosts(forceRefresh: true);
      SavedPost? existing;
      for (final post in posts) {
        if (post.id == postId) {
          existing = post;
          break;
        }
      }
      if (existing == null) return;

      final needsTitle = existing.title.trim().isEmpty ||
          existing.title.toLowerCase() == 'post salvato' ||
          existing.title.toLowerCase() ==
              (Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '') ??
                  '');
      final needsDescription = existing.description.trim().isEmpty;
      final needsImage = (existing.imageUrl == null ||
              existing.imageUrl!.trim().isEmpty) &&
          (existing.previewStorageUrl == null ||
              existing.previewStorageUrl!.trim().isEmpty);
      if (!needsTitle && !needsDescription && !needsImage) return;

      final metadata = await UrlMetadataService.resolveImportMetadata(url);
      final updated = existing.copyWith(
        title: needsTitle && (metadata.title?.trim().isNotEmpty ?? false)
            ? metadata.title!.trim()
            : existing.title,
        description: needsDescription &&
                (metadata.description?.trim().isNotEmpty ?? false)
            ? metadata.description!.trim()
            : existing.description,
        imageUrl: needsImage && (metadata.imageUrl?.trim().isNotEmpty ?? false)
            ? metadata.imageUrl
            : existing.imageUrl,
        previewStorageUrl: needsImage &&
                (metadata.previewStorageUrl?.trim().isNotEmpty ?? false)
            ? metadata.previewStorageUrl
            : existing.previewStorageUrl,
        creatorName: existing.creatorName ?? metadata.creatorName,
        creatorUsername: existing.creatorUsername ?? metadata.creatorUsername,
        updatedAt: DateTime.now(),
      );
      await DataService.instance.savePost(updated);
      if (kDebugMode) {
        debugPrint(
          'Share Extension: metadati arricchiti per $postId '
          '(${updated.title})',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Share Extension: enrich metadati fallito: $error');
      }
    }
  }

  Future<void> _exportCatalog(String userId, List<Folder> folders) async {
    final foldersById = {for (final folder in folders) folder.id: folder};
    final defaultFolder = _findDefaultFolder(folders);
    if (defaultFolder == null) return;
    final rootRule = await PlanLimitsService.getRule(
      'root_folders',
      forceRefresh: true,
    );
    final childRule = await PlanLimitsService.getRule(
      'child_folders',
      forceRefresh: false,
    );
    final levelRule = await PlanLimitsService.getRule(
      'folder_levels',
      forceRefresh: false,
    );
    final manualTagsRule = await PlanLimitsService.getRule(
      'manual_tags',
      forceRefresh: false,
    );
    final manualTagsAllowed = manualTagsRule.enabled &&
        await PlanLimitsService.canUseFeature('manual_tags');

    String displayPathFor(Folder folder) {
      if (folder.isDefault) return 'Tutti';

      final path = <String>[folder.name];
      final visited = <String>{folder.id};
      var parentId = folder.parentId;

      while (parentId != null && visited.add(parentId)) {
        final parent = foldersById[parentId];
        if (parent == null || parent.isDefault) break;
        path.insert(0, parent.name);
        parentId = parent.parentId;
      }
      return path.join(' › ');
    }

    int levelFor(Folder folder) {
      if (folder.isDefault) return 0;

      var level = 0;
      var parentId = folder.parentId;
      final visited = <String>{folder.id};
      while (parentId != null && visited.add(parentId)) {
        final parent = foldersById[parentId];
        if (parent == null || parent.isDefault) break;
        level++;
        parentId = parent.parentId;
      }
      return level;
    }

    await _channel.invokeMethod<void>('exportCatalog', {
      'schemaVersion': 1,
      'userId': userId,
      'defaultFolderId': defaultFolder.id,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'limits': {
        'rootFoldersEnabled': rootRule.enabled,
        'rootFolderLimit': rootRule.limit,
        'childFoldersEnabled': childRule.enabled,
        'childFolderLimit': childRule.limit,
        'folderLevelsEnabled': levelRule.enabled,
        'folderLevelLimit': levelRule.limit,
        'manualTagsEnabled': manualTagsAllowed,
      },
      'folders': folders
          .map(
            (folder) => {
              'id': folder.id,
              'name': folder.name,
              'parentId': folder.parentId,
              'color': folder.color,
              'isDefault': folder.isDefault,
              'displayPath': displayPathFor(folder),
              'level': levelFor(folder),
            },
          )
          .toList(growable: false),
    });
  }

  Future<void> _importPendingShares(
    String userId,
    List<Folder> folders,
  ) async {
    final rawItems =
        await _channel.invokeListMethod<dynamic>('readPendingShares') ??
            const <dynamic>[];
    if (rawItems.isEmpty) return;
    if (kDebugMode) {
      debugPrint(
        'Share Extension: ${rawItems.length} richieste in coda.',
      );
    }

    final workingFolders = List<Folder>.from(folders);
    final foldersById = {
      for (final folder in workingFolders) folder.id: folder,
    };
    final defaultFolder = _findDefaultFolder(workingFolders);
    if (defaultFolder == null) return;

    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final queueId = item['id']?.toString();
      final queuedUserId = item['userId']?.toString();
      final url = item['url']?.toString().trim();

      if (queueId == null ||
          queueId.isEmpty ||
          queuedUserId != userId ||
          url == null ||
          !_isWebURL(url)) {
        continue;
      }

      try {
        final requestedFolderId = item['folderId']?.toString();
        var targetFolder = foldersById[requestedFolderId] ?? defaultFolder;
        final queuedPath = item['folderDisplayPath']?.toString().trim();
        var folderPath = targetFolder.isDefault
            ? 'Tutti'
            : (queuedPath == null || queuedPath.isEmpty
                ? targetFolder.name
                : queuedPath);

        final newFolderName = item['newFolderName']?.toString().trim();
        if (newFolderName != null && newFolderName.isNotEmpty) {
          final requestedParentId =
              item['newFolderParentId']?.toString().trim();
          final parentFolder = foldersById[requestedParentId];
          final parentId = parentFolder == null || parentFolder.isDefault
              ? null
              : parentFolder.id;

          Folder? createdOrExisting;
          for (final folder in workingFolders) {
            if (!folder.isDefault &&
                folder.parentId == parentId &&
                folder.name.toLowerCase() == newFolderName.toLowerCase()) {
              createdOrExisting = folder;
              break;
            }
          }
          if (createdOrExisting == null) {
            await _validateNewFolderCreation(
              parentFolder: parentFolder,
              folders: workingFolders,
            );
            createdOrExisting = await DataService.instance.createFolder(
              name: newFolderName,
              color: '#BB86FC',
              parentId: parentId,
            );
            if (kDebugMode) {
              debugPrint(
                'Share Extension: cartella creata ${createdOrExisting.id}.',
              );
            }
          }

          targetFolder = createdOrExisting;
          if (!foldersById.containsKey(createdOrExisting.id)) {
            workingFolders.add(createdOrExisting);
            foldersById[createdOrExisting.id] = createdOrExisting;
          }

          final parentPath = item['newFolderParentPath']?.toString().trim();
          folderPath =
              parentId == null || parentPath == null || parentPath.isEmpty
                  ? createdOrExisting.name
                  : '$parentPath › ${createdOrExisting.name}';
        }

        final metadata = await UrlMetadataService.resolveImportMetadata(url);
        final title = metadata.title?.trim();
        final requestedManualTags = item['tags'] is List
            ? List<dynamic>.from(item['tags'] as List)
                .map((tag) => tag.toString().trim())
                .where((tag) => tag.isNotEmpty)
            : const Iterable<String>.empty();
        final manualTagsAllowed = requestedManualTags.isEmpty ||
            await PlanLimitsService.canUseFeature('manual_tags');
        final queuedTags = manualTagsAllowed
            ? requestedManualTags
            : const Iterable<String>.empty();
        final tags = <String>[];
        final normalizedTags = <String>{};
        for (final tag in [
          ...metadata.extractedHashtags,
          ...queuedTags,
        ]) {
          if (normalizedTags.add(tag.toLowerCase())) {
            tags.add(tag);
          }
        }

        await FolderService().saveSharedPostWithOptionalFolder(
          url: url,
          title: title == null || title.isEmpty
              ? (Uri.tryParse(url)?.host ?? url)
              : title,
          description:
              metadata.description ?? item['sharedText']?.toString() ?? '',
          imageUrl: metadata.imageUrl,
          previewStorageUrl: metadata.previewStorageUrl,
          creatorName: metadata.creatorName,
          creatorUsername: metadata.creatorUsername,
          tags: tags,
          selectedFolderId: targetFolder.id,
          selectedFolderPath: folderPath,
          markAsImported: false,
        );
        if (kDebugMode) {
          debugPrint(
            'Share Extension: post importato in ${targetFolder.id} '
            'con ${tags.length} tag.',
          );
        }

        await _channel.invokeMethod<void>(
          'acknowledgePendingShares',
          {
            'ids': [queueId],
          },
        );
        if (queuedTags.isNotEmpty) {
          try {
            await PlanLimitsService.recordFeatureSuccess('manual_tags');
          } catch (error) {
            if (kDebugMode) {
              debugPrint(
                'Conteggio tag manuali non aggiornato: $error',
              );
            }
          }
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Import Share Extension $queueId non riuscito: $error');
        }
      }
    }
  }

  bool _isWebURL(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _validateNewFolderCreation({
    required Folder? parentFolder,
    required List<Folder> folders,
  }) async {
    if (parentFolder == null || parentFolder.isDefault) {
      final rule = await PlanLimitsService.getRule(
        'root_folders',
        forceRefresh: true,
      );
      final rootCount = folders
          .where((folder) => !folder.isDefault && folder.parentId == null)
          .length;
      if (!rule.enabled) {
        throw Exception(
          'La creazione di cartelle principali è disabilitata.',
        );
      }
      if (rule.limit > 0 && rootCount >= rule.limit) {
        throw Exception('Limite cartelle principali raggiunto.');
      }
      return;
    }

    final childRule = await PlanLimitsService.getRule(
      'child_folders',
      forceRefresh: true,
    );
    final levelRule = await PlanLimitsService.getRule(
      'folder_levels',
      forceRefresh: false,
    );
    if (!childRule.enabled || !levelRule.enabled) {
      throw Exception('La creazione di sottocartelle è disabilitata.');
    }

    final directChildren = folders
        .where(
          (folder) => !folder.isDefault && folder.parentId == parentFolder.id,
        )
        .length;
    if (childRule.limit > 0 && directChildren >= childRule.limit) {
      throw Exception('Limite sottocartelle raggiunto.');
    }

    final foldersById = {for (final folder in folders) folder.id: folder};
    var parentLevel = 0;
    var ancestorId = parentFolder.parentId;
    final visited = <String>{parentFolder.id};
    while (ancestorId != null && visited.add(ancestorId)) {
      final ancestor = foldersById[ancestorId];
      if (ancestor == null || ancestor.isDefault) break;
      parentLevel++;
      ancestorId = ancestor.parentId;
    }
    if (levelRule.limit > 0 && parentLevel >= levelRule.limit - 1) {
      throw Exception('Limite livelli cartelle raggiunto.');
    }
  }

  Folder? _findDefaultFolder(List<Folder> folders) {
    for (final folder in folders) {
      if (folder.isDefault) return folder;
    }
    return null;
  }
}
