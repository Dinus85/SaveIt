// lib/services/post_preview_cache.dart
// Cache persistente delle immagini di anteprima dei post.
//
// - Su mobile/desktop (dart:io): scarica l'immagine e la salva su filesystem, indicizzata per postId.
// - Su web: no-op (si usa la preview via network come prima).

export 'post_preview_cache_stub.dart'
    if (dart.library.io) 'post_preview_cache_io.dart';



