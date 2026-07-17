// lib/widgets/post_preview_image_io.dart
// Implementazione mobile/desktop: cache locale persistente + cache remota globale.

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/post_preview_cache.dart';
import '../services/post_preview_remote_storage.dart';
import '../services/post_preview_repair_tracker.dart';
import '../services/post_preview_url_utils.dart';

class PostPreviewImage extends StatefulWidget {
  final String postId;
  final String? postUrl;
  final String? imageUrl;
  final String? remoteImageUrl;
  final BoxFit fit;

  const PostPreviewImage({
    super.key,
    required this.postId,
    this.postUrl,
    required this.imageUrl,
    this.remoteImageUrl,
    required this.fit,
  });

  @override
  State<PostPreviewImage> createState() => _PostPreviewImageState();
}

class _PostPreviewImageState extends State<PostPreviewImage> {
  final _cache = const PostPreviewCache();
  final _remote = const PostPreviewRemoteStorage();
  late Future<String?> _localPathFuture;
  String? _networkDisplayUrl;
  bool _remoteBackupStarted = false;
  bool _previewUnavailable = false;

  @override
  void initState() {
    super.initState();
    _localPathFuture = _initAndGetPath();
  }

  String? _stableRemoteFromField() {
    final remote = widget.remoteImageUrl?.trim();
    if (PostPreviewUrlUtils.isStablePreviewStorageUrl(remote)) {
      return remote;
    }
    return null;
  }

  Future<String?> _initAndGetPath() async {
    try {
      final existing = await _cache.getCachedPreviewPath(widget.postId);
      if (existing != null) {
        _networkDisplayUrl = _stableRemoteFromField();
        return existing;
      }

      final stableField = _stableRemoteFromField();
      final originalUrl = widget.imageUrl?.trim();
      final hasUsableSource = stableField != null ||
          (originalUrl != null && originalUrl.isNotEmpty);

      if (stableField != null) {
        _networkDisplayUrl = stableField;
        await _cache.ensureCachedPreview(
          postId: widget.postId,
          imageUrl: stableField,
        );
        final cached = await _cache.getCachedPreviewPath(widget.postId);
        if (cached != null) return cached;
      }

      // Se non c'è ancora un'immagine (es. post Share Extension appena
      // sincronizzato), non bruciare il tentativo: arriverà dopo il sync.
      if (!hasUsableSource) {
        return null;
      }

      if (PostPreviewRepairTracker.instance.wasAttempted(widget.postId)) {
        // Fonte disponibile ma download già fallito in questa sessione.
        _previewUnavailable = true;
        return null;
      }

      PostPreviewRepairTracker.instance.markAttempted(widget.postId);

      final stableUrl = await _remote.resolveExistingPreviewUrl(
        sourceUrl: widget.postUrl,
        imageUrl: widget.imageUrl,
      );

      _networkDisplayUrl = stableUrl ?? originalUrl;

      await _cache.ensureCachedPreview(
        postId: widget.postId,
        imageUrl: stableUrl,
        fallbackImageUrl: stableUrl == null ? originalUrl : null,
      );
    } catch (_) {}

    final localPath = await _cache.getCachedPreviewPath(widget.postId);
    if (localPath != null) {
      _backupLocalPreviewToRemoteIfNeeded(localPath);
      return localPath;
    }

    if (_networkDisplayUrl != null && _networkDisplayUrl!.trim().isNotEmpty) {
      // Mostra comunque l'URL di rete finché la cache locale non è pronta.
      return null;
    }

    _previewUnavailable = true;
    return null;
  }

  @override
  void didUpdateWidget(covariant PostPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId ||
        oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.remoteImageUrl != widget.remoteImageUrl ||
        oldWidget.postUrl != widget.postUrl) {
      final hadNoImage =
          (oldWidget.imageUrl == null || oldWidget.imageUrl!.trim().isEmpty) &&
              (oldWidget.remoteImageUrl == null ||
                  oldWidget.remoteImageUrl!.trim().isEmpty);
      final hasImageNow =
          (widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty) ||
              (widget.remoteImageUrl != null &&
                  widget.remoteImageUrl!.trim().isNotEmpty);
      if (hadNoImage && hasImageNow) {
        PostPreviewRepairTracker.instance.clearAttempt(widget.postId);
      }
      _remoteBackupStarted = false;
      _networkDisplayUrl = null;
      _previewUnavailable = false;
      _localPathFuture = _initAndGetPath();
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400),
          ),
        ),
      ),
    );
  }

  void _backupLocalPreviewToRemoteIfNeeded(String localPath) {
    if (_remoteBackupStarted || widget.postId.isEmpty) return;
    if (PostPreviewUrlUtils.isStablePreviewStorageUrl(widget.remoteImageUrl)) {
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) return;

    _remoteBackupStarted = true;
    Future.microtask(() async {
      try {
        final downloadUrl = await _remote.uploadCachedPreview(
          userId: userId,
          postId: widget.postId,
          localPath: localPath,
          sourceUrl: widget.postUrl,
          imageUrl: widget.imageUrl,
        );
        if (!PostPreviewUrlUtils.isStablePreviewStorageUrl(downloadUrl)) return;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('posts')
            .doc(widget.postId)
            .set({
          'previewStorageUrl': downloadUrl!.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // La UI non deve dipendere dal backup remoto.
      }
    });
  }

  Widget _buildBrokenImage() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.grey.shade400,
          size: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_previewUnavailable) {
      return _buildBrokenImage();
    }

    return FutureBuilder<String?>(
      future: _localPathFuture,
      builder: (context, snap) {
        final localPath = snap.data;
        if (localPath != null && localPath.isNotEmpty) {
          final file = File(localPath);
          return Image.file(
            file,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, _, __) {
              return _buildBrokenImage();
            },
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return _buildPlaceholder();
        }

        final stableField = _stableRemoteFromField();
        final networkUrl = _networkDisplayUrl?.trim().isNotEmpty == true
            ? _networkDisplayUrl!.trim()
            : (stableField ?? widget.imageUrl?.trim());
        if (networkUrl != null && networkUrl.isNotEmpty) {
          return CachedNetworkImage(
            imageUrl: networkUrl,
            fit: widget.fit,
            alignment: Alignment.center,
            width: double.infinity,
            height: double.infinity,
            placeholder: (context, _) => _buildPlaceholder(),
            errorWidget: (context, _, __) => _buildBrokenImage(),
          );
        }

        // Metadati ancora in arrivo (es. sync Share Extension).
        if (!_previewUnavailable) {
          return _buildPlaceholder();
        }

        return _buildBrokenImage();
      },
    );
  }
}
