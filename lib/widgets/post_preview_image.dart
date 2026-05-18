// lib/widgets/post_preview_image.dart
// Widget unificato per mostrare anteprima post:
// - su mobile/desktop: prima file locale (cache persistente), poi network
// - su web: solo network

export 'post_preview_image_stub.dart'
    if (dart.library.io) 'post_preview_image_io.dart';



