// lib/widgets/post_preview_image_io.dart
// Implementazione mobile/desktop: prova file locale (cache persistente), fallback network.

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/post_preview_cache.dart';

class PostPreviewImage extends StatefulWidget {
  final String postId;
  final String? imageUrl;
  final String? remoteImageUrl;
  final BoxFit fit;

  const PostPreviewImage({
    super.key,
    required this.postId,
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
  bool _allowNetworkFallback = false;

  @override
  void initState() {
    super.initState();
    _localPathFuture = _initAndGetPath();
  }

  Future<String?> _initAndGetPath() async {
    try {
      final existing = await _cache.getCachedPreviewPath(widget.postId);
      if (existing != null) return existing;

      await _cache.ensureCachedPreview(
        postId: widget.postId,
        imageUrl: widget.remoteImageUrl,
        fallbackImageUrl: widget.imageUrl,
      );
    } catch (_) {}

    final localPath = await _cache.getCachedPreviewPath(widget.postId);
    if (localPath == null && mounted) {
      setState(() {
        _allowNetworkFallback = true;
      });
    }
    return localPath;
  }

  @override
  void didUpdateWidget(covariant PostPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId ||
        oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.remoteImageUrl != widget.remoteImageUrl) {
      _allowNetworkFallback = false;
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

  Widget _buildNetwork(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      alignment: Alignment.center,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, _) => Container(
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
      ),
      errorWidget: (context, _, __) => Container(
        color: Colors.grey.shade200,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.grey.shade400,
            size: 24,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = (widget.remoteImageUrl?.trim().isNotEmpty == true)
        ? widget.remoteImageUrl!.trim()
        : widget.imageUrl?.trim();

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
              if (url != null && url.isNotEmpty) return _buildNetwork(url);
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
            },
          );
        }

        if (_allowNetworkFallback && url != null && url.isNotEmpty) {
          return _buildNetwork(url);
        }

        if (snap.connectionState == ConnectionState.waiting &&
            url != null &&
            url.isNotEmpty) {
          return _buildPlaceholder();
        }

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
      },
    );
  }
}
