// lib/services/post_preview_cache_io.dart
// Implementazione filesystem (mobile/desktop) per cache persistente anteprime post.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class PostPreviewCache {
  const PostPreviewCache();

  // Target "thumbnail" per UI: piccola ma dignitosa.
  static const int _maxDimension = 512;
  static const int _targetMaxBytes = 100 * 1024; // ~100KB
  static const int _downloadHardMaxBytes = 2 * 1024 * 1024; // 2MB (guard)

  static Future<Directory>? _dirFuture;
  static final Map<String, Future<void>> _inFlightDownloads =
      <String, Future<void>>{};

  static Future<Directory> _getBaseDir() {
    _dirFuture ??= () async {
      final base = await getApplicationSupportDirectory();
      final dir =
          Directory('${base.path}${Platform.pathSeparator}post_previews');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }();
    return _dirFuture!;
  }

  static Future<File> _getFileForPost(String postId) async {
    final dir = await _getBaseDir();
    return File('${dir.path}${Platform.pathSeparator}$postId.img');
  }

  Future<String?> getCachedPreviewPath(String postId) async {
    if (postId.isEmpty) return null;
    try {
      final file = await _getFileForPost(postId);
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) return file.path;
      }
      return null;
    } catch (e) {
      debugPrint('PostPreviewCache.getCachedPreviewPath error: $e');
      return null;
    }
  }

  Future<void> deleteCachedPreview(String postId) async {
    if (postId.isEmpty) return;
    try {
      final file = await _getFileForPost(postId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('PostPreviewCache.deleteCachedPreview error: $e');
    }
  }

  Future<void> ensureCachedPreview({
    required String postId,
    required String? imageUrl,
    String? fallbackImageUrl,
  }) async {
    if (postId.isEmpty) return;
    final existing = await getCachedPreviewPath(postId);
    if (existing != null) return;

    final running = _inFlightDownloads[postId];
    if (running != null) {
      await running;
      return;
    }

    final future = _downloadAndStorePreview(
      postId: postId,
      imageUrl: imageUrl,
      fallbackImageUrl: fallbackImageUrl,
    );
    _inFlightDownloads[postId] = future;

    try {
      await future;
    } finally {
      _inFlightDownloads.remove(postId);
    }
  }

  Future<void> _downloadAndStorePreview({
    required String postId,
    required String? imageUrl,
    String? fallbackImageUrl,
  }) async {
    final candidateUrls = <String>[
      if (imageUrl?.trim().isNotEmpty == true) imageUrl!.trim(),
      if (fallbackImageUrl?.trim().isNotEmpty == true &&
          fallbackImageUrl!.trim() != imageUrl?.trim())
        fallbackImageUrl.trim(),
    ];
    if (candidateUrls.isEmpty) return;

    try {
      for (final url in candidateUrls) {
        final uri = Uri.tryParse(url);
        if (uri == null) continue;

        final resp = await http.get(uri).timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) continue;

        final contentType = resp.headers['content-type'] ?? '';
        if (contentType.isNotEmpty &&
            !contentType.toLowerCase().startsWith('image/')) {
          continue;
        }

        final original = resp.bodyBytes;
        if (original.isEmpty) continue;
        if (original.length > _downloadHardMaxBytes) continue;

        final bytes = _compressForThumbnail(original);
        if (bytes.isEmpty) continue;

        final file = await _getFileForPost(postId);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(file.path);
        return;
      }
    } catch (e) {
      debugPrint('PostPreviewCache.ensureCachedPreview error: $e');
    }
  }

  List<int> _compressForThumbnail(List<int> input) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(input));
      if (decoded == null) {
        // Se non decodifica, salva bytes originali (ma già limitati in download).
        return input;
      }

      // Se è già abbastanza piccola (dimensioni e peso), non ricomprimere (evita perdita qualità).
      final longest =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longest <= _maxDimension && input.length <= _targetMaxBytes) {
        return input;
      }

      final resized = _resizeIfNeeded(decoded, _maxDimension);

      // Tentativi con qualità decrescente per rientrare nel target.
      final qualities = <int>[68, 60, 52, 45, 38];
      List<int> best = img.encodeJpg(resized, quality: qualities.first);

      for (final q in qualities) {
        final out = img.encodeJpg(resized, quality: q);
        best = out;
        if (out.length <= _targetMaxBytes) break;
      }

      // Se ancora troppo grande, riduci un po' la dimensione e ritenta.
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
      debugPrint('PostPreviewCache._compressForThumbnail error: $e');
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
}
