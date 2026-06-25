import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:savein/data_service.dart';
import 'package:savein/models.dart';
import 'package:savein/services/plan_limits_service.dart';

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

  Future<void> _ensureShareFeatureEnabled(
    String feature,
    String featureName,
  ) async {
    await PlanLimitsService.consumeOrThrow(feature, featureName: featureName);
  }

  Future<String> createPostShareLink(SavedPost post) async {
    await _ensureShareFeatureEnabled('share_post', 'Condivisione Post');

    final callable = _functions.httpsCallable('createShareLink');
    final response = await callable.call(<String, dynamic>{
      'type': 'post',
      'payload': _postPayload(post),
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['url'] as String;
  }

  Future<String> createFolderShareLink(Folder folder) async {
    await _ensureShareFeatureEnabled('share_folder', 'Condivisione Cartella');

    final callable = _functions.httpsCallable('createShareLink');
    final response = await callable.call(<String, dynamic>{
      'type': 'folder',
      'payload': {
        'rootId': folder.id,
        'name': folder.name,
        'color': folder.color,
        'parentId': folder.parentId,
      },
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
    await DataService.instance.importSharedLinkFromSource(
      link.token,
      targetFolderId: targetFolderId,
    );
  }

  Future<void> importFolder(SaveInShareLink link) async {
    await DataService.instance.importSharedLinkFromSource(link.token);
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
}
