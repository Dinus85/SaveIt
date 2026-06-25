// lib/services/post_preview_remote_storage_stub.dart
// No-op per piattaforme senza dart:io (es. web).

class PostPreviewRemoteStorage {
  const PostPreviewRemoteStorage();

  Future<String?> resolveExistingPreviewUrl({
    String? sourceUrl,
    String? imageUrl,
  }) async {
    return null;
  }

  Future<String?> uploadCachedPreview({
    required String userId,
    required String postId,
    required String localPath,
    String? sourceUrl,
    String? imageUrl,
  }) async {
    return null;
  }
}
