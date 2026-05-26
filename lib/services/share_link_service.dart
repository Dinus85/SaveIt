import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data_service.dart';
import '../models.dart';

class SaveInShareLink {
  final String token;
  final String type;
  final String title;
  final String ownerName;
  final Map<String, dynamic> payload;

  const SaveInShareLink({
    required this.token,
    required this.type,
    required this.title,
    required this.ownerName,
    required this.payload,
  });

  bool get isPost => type == 'post';
  bool get isFolder => type == 'folder';

  factory SaveInShareLink.fromMap(Map<String, dynamic> map) {
    return SaveInShareLink(
      token: (map['token'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'post',
      title: (map['title'] as String?) ?? 'Contenuto SaveIn',
      ownerName: (map['ownerName'] as String?) ?? 'Utente SaveIn',
      payload: Map<String, dynamic>.from((map['payload'] as Map?) ?? const {}),
    );
  }
}

class ShareLinkService {
  ShareLinkService._();
  static final ShareLinkService instance = ShareLinkService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<String> createPostShareLink(SavedPost post) async {
    final callable = _functions.httpsCallable('createShareLink');
    final response = await callable.call(<String, dynamic>{
      'type': 'post',
      'payload': _postPayload(post),
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['url'] as String;
  }

  Future<String> createFolderShareLink(Folder folder) async {
    final folders = await DataService.instance.getFolders(forceRefresh: true);
    final posts = await DataService.instance.getPosts();
    final payload = _folderPayload(folder, folders, posts);
    final callable = _functions.httpsCallable('createShareLink');
    final response = await callable.call(<String, dynamic>{
      'type': 'folder',
      'payload': payload,
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['url'] as String;
  }

  Future<SaveInShareLink> fetchShareLink(String token) async {
    final callable = _functions.httpsCallable('getShareLink');
    final response = await callable.call(<String, dynamic>{'token': token});
    return SaveInShareLink.fromMap(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> trackImport(String token) async {
    if (token.isEmpty) return;
    final callable = _functions.httpsCallable('trackShareLinkImport');
    await callable.call(<String, dynamic>{'token': token});
  }

  Future<void> importPost(SaveInShareLink link,
      {String? targetFolderId}) async {
    final payload = link.payload;
    final folderId = await _targetFolderId(targetFolderId);
    await DataService.instance.createPost(
      url: (payload['url'] as String?) ?? '',
      title:
          '[Condiviso da ${link.ownerName}] ${(payload['title'] as String?) ?? link.title}',
      description: (payload['description'] as String?) ?? '',
      imageUrl: payload['imageUrl'] as String?,
      previewStorageUrl: payload['previewStorageUrl'] as String?,
      creatorName: payload['creatorName'] as String?,
      creatorUsername: payload['creatorUsername'] as String?,
      tags: List<String>.from(payload['tags'] ?? const [])..add('condiviso'),
      folderId: folderId,
      isShared: true,
    );
    await trackImport(link.token);
  }

  Future<void> importFolder(SaveInShareLink link) async {
    final payload = link.payload;
    final folders =
        List<Map<String, dynamic>>.from(payload['folders'] ?? const []);
    final posts = List<Map<String, dynamic>>.from(payload['posts'] ?? const []);
    final rootId = (payload['rootId'] as String?) ?? '';
    final idMap = <String, String>{};
    folders.sort(
        (a, b) => _folderDepth(a, folders).compareTo(_folderDepth(b, folders)));

    for (final folder in folders) {
      final sourceId = (folder['id'] as String?) ?? '';
      final sourceParentId = folder['parentId'] as String?;
      final newParentId = sourceParentId == null ? null : idMap[sourceParentId];
      final isRoot = sourceId == rootId;
      final created = await DataService.instance.createFolder(
        name: isRoot
            ? '[Condivisa da ${link.ownerName}] ${(folder['name'] as String?) ?? link.title}'
            : (folder['name'] as String?) ?? 'Cartella condivisa',
        color: (folder['color'] as String?) ?? '#BB86FC',
        parentId: newParentId,
        isShared: true,
      );
      if (sourceId.isNotEmpty) {
        idMap[sourceId] = created.id;
      }
    }

    for (final post in posts) {
      final sourceFolderId = post['folderId'] as String?;
      final targetFolderId =
          idMap[sourceFolderId] ?? await _targetFolderId(null);
      await DataService.instance.createPost(
        url: (post['url'] as String?) ?? '',
        title: (post['title'] as String?) ?? 'Post condiviso',
        description: (post['description'] as String?) ?? '',
        imageUrl: post['imageUrl'] as String?,
        previewStorageUrl: post['previewStorageUrl'] as String?,
        creatorName: post['creatorName'] as String?,
        creatorUsername: post['creatorUsername'] as String?,
        tags: List<String>.from(post['tags'] ?? const [])..add('condiviso'),
        folderId: targetFolderId,
        isShared: true,
      );
    }

    await trackImport(link.token);
  }

  Future<void> openOriginalPost(SaveInShareLink link) async {
    final url = link.payload['url'] as String?;
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Map<String, dynamic> _postPayload(SavedPost post) {
    return {
      'id': post.id,
      'url': post.url,
      'title': post.title,
      'description': post.description,
      'imageUrl': post.imageUrl,
      'previewStorageUrl': post.previewStorageUrl,
      'creatorName': post.creatorName,
      'creatorUsername': post.creatorUsername,
      'tags': post.tags,
      'folderId': post.folderId,
    };
  }

  Map<String, dynamic> _folderPayload(
    Folder root,
    List<Folder> allFolders,
    List<SavedPost> allPosts,
  ) {
    final includedIds = <String>{root.id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in allFolders) {
        if (folder.parentId != null &&
            includedIds.contains(folder.parentId) &&
            includedIds.add(folder.id)) {
          changed = true;
        }
      }
    }

    final folders = allFolders
        .where((folder) => includedIds.contains(folder.id))
        .map((folder) => {
              'id': folder.id,
              'name': folder.name,
              'color': folder.color,
              'parentId': folder.parentId,
            })
        .toList();
    final posts = allPosts
        .where((post) => includedIds.contains(post.folderId))
        .map(_postPayload)
        .toList();

    return {
      'rootId': root.id,
      'name': root.name,
      'color': root.color,
      'folders': folders,
      'posts': posts,
    };
  }

  Future<String> _targetFolderId(String? targetFolderId) async {
    if (targetFolderId != null &&
        targetFolderId.isNotEmpty &&
        targetFolderId != 'all_folder') {
      return targetFolderId;
    }
    final folders = await DataService.instance.getFolders();
    return folders.firstWhere((folder) => folder.isDefault).id;
  }

  int _folderDepth(
      Map<String, dynamic> folder, List<Map<String, dynamic>> folders) {
    var depth = 0;
    var parentId = folder['parentId'] as String?;
    while (parentId != null && depth < 20) {
      depth++;
      Map<String, dynamic>? parent;
      for (final candidate in folders) {
        if (candidate['id'] == parentId) {
          parent = candidate;
          break;
        }
      }
      parentId = parent?['parentId'] as String?;
    }
    return depth;
  }
}
