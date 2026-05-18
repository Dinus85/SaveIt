// lib/services/post_preview_remote_storage_io.dart
// Implementazione dart:io: upload su Firebase Storage.

import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class PostPreviewRemoteStorage {
  const PostPreviewRemoteStorage();

  static const int _hardMaxBytes = 2 * 1024 * 1024; // 2MB (guard)
  static const int _maxDimension = 512;
  static const int _targetMaxBytes = 100 * 1024; // ~100KB

  Future<String?> uploadCachedPreview({
    required String userId,
    required String postId,
    required String localPath,
  }) async {
    if (userId.isEmpty || postId.isEmpty) return null;
    final path = localPath.trim();
    if (path.isEmpty) return null;

    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final len = await file.length();
      if (len <= 0 || len > _hardMaxBytes) return null;

      final original = await file.readAsBytes();
      final detected = _detectImageType(original);

      // Se è già "piccola", carica così com'è (niente ricompressione).
      final decoded = img.decodeImage(original);
      if (decoded != null &&
          detected.extension.isNotEmpty &&
          detected.contentType.startsWith('image/') &&
          (decoded.width > decoded.height ? decoded.width : decoded.height) <=
              _maxDimension &&
          original.length <= _targetMaxBytes) {
        return await _uploadBytes(
          userId: userId,
          postId: postId,
          bytes: original,
          ext: detected.extension,
          contentType: detected.contentType,
        );
      }

      // Altrimenti: normalizza a JPEG compresso.
      final bytes = _compressForThumbnail(original);
      return await _uploadBytes(
        userId: userId,
        postId: postId,
        bytes: bytes,
        ext: '.jpg',
        contentType: 'image/jpeg',
      );
    } catch (e) {
      debugPrint('PostPreviewRemoteStorage.uploadCachedPreview error: $e');
      return null;
    }
  }

  Future<String?> _uploadBytes({
    required String userId,
    required String postId,
    required List<int> bytes,
    required String ext,
    required String contentType,
  }) async {
    if (bytes.isEmpty) return null;
    if (bytes.length > _hardMaxBytes) return null;

    final storage = FirebaseStorage.instance;
    final objectPath = 'users/$userId/post_previews/$postId$ext';

    final ref = storage.ref(objectPath);
    final metadata = SettableMetadata(
      contentType: contentType,
      cacheControl: 'public,max-age=31536000',
      customMetadata: {
        'postId': postId,
      },
    );

    await ref.putData(Uint8List.fromList(bytes), metadata);
    return await ref.getDownloadURL();
  }

  List<int> _compressForThumbnail(List<int> input) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(input));
      if (decoded == null) return input;

      final resized = _resizeIfNeeded(decoded, _maxDimension);

      final qualities = <int>[68, 60, 52, 45, 38];
      List<int> best = img.encodeJpg(resized, quality: qualities.first);
      for (final q in qualities) {
        final out = img.encodeJpg(resized, quality: q);
        best = out;
        if (out.length <= _targetMaxBytes) break;
      }

      if (best.length > _targetMaxBytes) {
        final smaller = _resizeIfNeeded(resized, 384);
        best = img.encodeJpg(smaller, quality: 52);
      }

      if (best.length > _targetMaxBytes) {
        final smaller = _resizeIfNeeded(resized, 320);
        best = img.encodeJpg(smaller, quality: 45);
      }

      return best;
    } catch (e) {
      debugPrint('PostPreviewRemoteStorage._compressForThumbnail error: $e');
      return input;
    }
  }

  img.Image _resizeIfNeeded(img.Image image, int maxDim) {
    final w = image.width;
    final h = image.height;
    final longest = w > h ? w : h;
    if (longest <= maxDim) return image;

    final scale = maxDim / longest;
    final newW = (w * scale).round().clamp(1, maxDim);
    final newH = (h * scale).round().clamp(1, maxDim);
    return img.copyResize(image,
        width: newW, height: newH, interpolation: img.Interpolation.average);
  }

  _ImageType _detectImageType(List<int> bytes) {
    // JPEG: FF D8 FF
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return const _ImageType('.jpg', 'image/jpeg');
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return const _ImageType('.png', 'image/png');
    }

    // GIF: "GIF87a" / "GIF89a"
    if (bytes.length >= 6) {
      final sig = String.fromCharCodes(bytes.take(6));
      if (sig == 'GIF87a' || sig == 'GIF89a') {
        return const _ImageType('.gif', 'image/gif');
      }
    }

    // WebP: "RIFF"...."WEBP"
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.take(4));
      final webp = String.fromCharCodes(bytes.skip(8).take(4));
      if (riff == 'RIFF' && webp == 'WEBP') {
        return const _ImageType('.webp', 'image/webp');
      }
    }

    return const _ImageType('', 'application/octet-stream');
  }
}

class _ImageType {
  final String extension;
  final String contentType;
  const _ImageType(this.extension, this.contentType);
}
