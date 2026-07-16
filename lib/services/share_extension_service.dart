import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:savein/data_service.dart';
import 'package:savein/models.dart';
import 'package:savein/services/folder_service.dart';
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

  bool _isRefreshing = false;

  bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> refreshCatalogAndImport() async {
    if (!_isSupported || _isRefreshing) return;
    _isRefreshing = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await _channel.invokeMethod<void>('clearCatalog');
        return;
      }

      final folders = await DataService.instance.getFolders();
      if (folders.isEmpty) return;

      await _exportCatalog(user.uid, folders);
      await _importPendingShares(user.uid, folders);
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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        await _channel.invokeMethod<void>('clearCatalog');
      } on MissingPluginException {
        // Il bridge esiste solo nel Runner iOS.
      }
      return;
    }

    try {
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

  Future<void> _exportCatalog(String userId, List<Folder> folders) async {
    final foldersById = {for (final folder in folders) folder.id: folder};
    final defaultFolder = _findDefaultFolder(folders);
    if (defaultFolder == null) return;

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
          createdOrExisting ??= await DataService.instance.createFolder(
            name: newFolderName,
            color: '#BB86FC',
            parentId: parentId,
          );

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
        final queuedTags = item['tags'] is List
            ? List<dynamic>.from(item['tags'] as List)
                .map((tag) => tag.toString().trim())
                .where((tag) => tag.isNotEmpty)
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

        await _channel.invokeMethod<void>(
          'acknowledgePendingShares',
          {
            'ids': [queueId],
          },
        );
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

  Folder? _findDefaultFolder(List<Folder> folders) {
    for (final folder in folders) {
      if (folder.isDefault) return folder;
    }
    return null;
  }
}
