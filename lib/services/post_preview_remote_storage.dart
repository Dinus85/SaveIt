// lib/services/post_preview_remote_storage.dart
// Upload (best-effort) delle anteprime salvate localmente su storage remoto.
//
// - Su mobile/desktop (dart:io): carica il file su Firebase Storage e restituisce downloadURL.
// - Su web: no-op.

export 'post_preview_remote_storage_stub.dart'
    if (dart.library.io) 'post_preview_remote_storage_io.dart';

