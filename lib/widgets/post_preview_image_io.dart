// lib/widgets/post_preview_image_io.dart
// Implementazione mobile/desktop: prova file locale (cache persistente), fallback network.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/post_preview_cache.dart';
import '../services/post_preview_remote_storage.dart';

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
  late Future<String?> _localPathFuture;
  bool _remoteBackupStarted = false;

  @override
  void initState() {
    super.initState();
    _localPathFuture = _initAndGetPath();
  }

  Future<String?> _initAndGetPath() async {
    try {
      final existing = await _cache.getCachedPreviewPath(widget.postId);
      if (existing != null) return existing;

      final remoteUrl = widget.remoteImageUrl?.trim();
      final originalUrl = widget.imageUrl?.trim();

      await _cache.ensureCachedPreview(
        postId: widget.postId,
        // Se esiste il backup remoto, la cache locale viene ricostruita SOLO da li.
        // L'URL originale serve solo per creare la prima cache prima del backup remoto.
        imageUrl: remoteUrl?.isNotEmpty == true ? remoteUrl : originalUrl,
        fallbackImageUrl: remoteUrl?.isNotEmpty == true ? null : originalUrl,
      );
    } catch (_) {}

    final localPath = await _cache.getCachedPreviewPath(widget.postId);
    if (localPath != null) {
      _backupLocalPreviewToRemoteIfNeeded(localPath);
    }
    return localPath;
  }

  @override
  void didUpdateWidget(covariant PostPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId ||
        oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.remoteImageUrl != widget.remoteImageUrl) {
      _remoteBackupStarted = false;
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
    if (_remoteBackupStarted ||
        widget.postId.isEmpty ||
        widget.remoteImageUrl?.trim().isNotEmpty == true) {
      return;
    }
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) return;

    _remoteBackupStarted = true;
    Future.microtask(() async {
      try {
        final downloadUrl =
            await const PostPreviewRemoteStorage().uploadCachedPreview(
          userId: userId,
          postId: widget.postId,
          localPath: localPath,
          sourceUrl: widget.postUrl,
        );
        if (downloadUrl == null || downloadUrl.trim().isEmpty) return;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('posts')
            .doc(widget.postId)
            .set({
          'previewStorageUrl': downloadUrl.trim(),
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

        return _buildBrokenImage();
      },
    );
  }
}
