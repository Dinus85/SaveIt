// lib/services/post_preview_cache_stub.dart
// Implementazione no-op per piattaforme senza dart:io (es. web).

class PostPreviewCache {
  const PostPreviewCache();

  Future<void> ensureCachedPreview({
    required String postId,
    required String? imageUrl,
    String? fallbackImageUrl,
  }) async {}

  Future<void> deleteCachedPreview(String postId) async {}

  Future<String?> getCachedPreviewPath(String postId) async => null;
}
