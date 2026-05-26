// lib/widgets/post_preview_image_stub.dart
// Implementazione per web: usa solo network.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class PostPreviewImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final url = (remoteImageUrl?.trim().isNotEmpty == true)
        ? remoteImageUrl!.trim()
        : imageUrl?.trim();
    if (url == null || url.isEmpty) {
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

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
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
}



