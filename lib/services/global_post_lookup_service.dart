import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:savein/models.dart';
import 'package:savein/services/post_preview_url_utils.dart';

/// Risultato lookup su `global_posts` (DB comune tra utenti).
class GlobalPostLookupResult {
  final bool found;
  final bool reused;
  final String? globalPostId;
  final String? urlHash;
  final String? normalizedUrl;
  final int? saveCount;
  final String? url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? previewStorageUrl;
  final String? creatorName;
  final String? creatorUsername;

  const GlobalPostLookupResult({
    required this.found,
    this.reused = false,
    this.globalPostId,
    this.urlHash,
    this.normalizedUrl,
    this.saveCount,
    this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.previewStorageUrl,
    this.creatorName,
    this.creatorUsername,
  });

  factory GlobalPostLookupResult.fromMap(Map<String, dynamic> data) {
    String? text(String key) {
      final value = data[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    final canonical = data['canonical'] is Map
        ? Map<String, dynamic>.from(data['canonical'] as Map)
        : <String, dynamic>{};

    return GlobalPostLookupResult(
      found: data['found'] == true,
      reused: data['reused'] == true,
      globalPostId: text('globalPostId'),
      urlHash: text('urlHash'),
      normalizedUrl: text('normalizedUrl'),
      saveCount: (data['saveCount'] as num?)?.toInt(),
      url: text('url') ?? textFromMap(canonical, 'url'),
      title: textFromMap(canonical, 'title'),
      description: textFromMap(canonical, 'description'),
      imageUrl: textFromMap(canonical, 'imageUrl'),
      previewStorageUrl: textFromMap(canonical, 'previewStorageUrl'),
      creatorName: textFromMap(canonical, 'creatorName'),
      creatorUsername: textFromMap(canonical, 'creatorUsername'),
    );
  }

  static String? textFromMap(Map<String, dynamic> map, String key) {
    final value = map[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Metadati sufficienti per saltare un nuovo fetch (Social Vault / scraping).
  bool get isUsableForImport {
    final hasTitle = title?.isNotEmpty == true &&
        title!.toLowerCase() != 'post salvato';
    final hasPreview = imageUrl?.isNotEmpty == true ||
        previewStorageUrl?.isNotEmpty == true;
    final hasDescription = description?.isNotEmpty == true;
    return hasTitle && (hasPreview || hasDescription);
  }

  UrlMetadata toUrlMetadata({required String fallbackUrl}) {
    return UrlMetadata(
      title: title,
      description: description,
      imageUrl: imageUrl,
      previewStorageUrl: previewStorageUrl,
      creatorName: creatorName,
      creatorUsername: creatorUsername,
      siteName: _siteNameFromUrl(url ?? normalizedUrl ?? fallbackUrl),
      fromGlobalCache: true,
    );
  }

  static String? _siteNameFromUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      return Uri.parse(value).host;
    } catch (_) {
      return null;
    }
  }
}

/// Lookup read-only su global_posts prima di import costosi.
class GlobalPostLookupService {
  GlobalPostLookupService._();
  static final GlobalPostLookupService instance = GlobalPostLookupService._();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<GlobalPostLookupResult> lookupByUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const GlobalPostLookupResult(found: false);
    }

    try {
      final callable = _functions.httpsCallable('getGlobalPostByUrl');
      final result = await callable.call<Map<String, dynamic>>({
        'url': trimmed,
      });
      final data = Map<String, dynamic>.from(result.data);
      final lookup = GlobalPostLookupResult.fromMap(data);
      if (kDebugMode && lookup.found) {
        print(
            'DEBUG: GlobalPostLookup - cache hit (saveCount: ${lookup.saveCount})');
      }
      return lookup;
    } catch (e) {
      if (kDebugMode) {
        print('DEBUG: GlobalPostLookup - lookup fallito: $e');
      }
      return const GlobalPostLookupResult(found: false);
    }
  }

  /// Normalizza l'URL come il backend prima del lookup.
  String normalizeUrl(String url) {
    var value = url.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    return PostPreviewUrlUtils.normalizePostUrlForHash(value);
  }
}
