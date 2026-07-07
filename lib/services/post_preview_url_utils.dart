// lib/services/post_preview_url_utils.dart
// Normalizzazione URL post e validazione URL anteprima stabili (Firebase Storage).

class PostPreviewUrlUtils {
  const PostPreviewUrlUtils._();

  /// True se l'URL punta a Firebase Storage ed e' un backup anteprima permanente.
  static bool isStablePreviewStorageUrl(String? url) {
    final raw = url?.trim() ?? '';
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    if (!lower.contains('firebasestorage.googleapis.com') &&
        !lower.contains('storage.googleapis.com')) {
      return false;
    }
    return lower.contains('post_previews');
  }

  /// True se l'URL e' un CDN esterno temporaneo (es. Instagram) e non va persistito.
  static bool isTransientImageUrl(String? url) {
    final lower = (url ?? '').trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (isStablePreviewStorageUrl(lower)) return false;
    return lower.contains('cdninstagram.com') ||
        lower.contains('fbcdn.net') ||
        lower.contains('scontent-') ||
        (lower.contains('instagram.com') && !lower.contains('firebasestorage'));
  }

  /// Allineato a `normalizePostUrlForHash` in functions/index.js.
  static String normalizePostUrlForHash(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return raw.toLowerCase();

    const removableParams = {
      'fbclid',
      'gclid',
      'igsh',
      'igshid',
      'mc_cid',
      'mc_eid',
      'si',
      'utm_campaign',
      'utm_content',
      'utm_medium',
      'utm_source',
      'utm_term',
    };

    final params = Map<String, String>.from(uri.queryParameters);
    for (final param in removableParams) {
      params.remove(param);
    }

    final sortedKeys = params.keys.toList()..sort();
    final sortedQuery = sortedKeys.isEmpty
        ? null
        : sortedKeys
            .map(
              (key) =>
                  '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(params[key]!)}',
            )
            .join('&');

    var path = uri.path;
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }

    final buffer = StringBuffer()
      ..write('${uri.scheme.toLowerCase()}://')
      ..write(uri.host.toLowerCase());

    final hasExplicitPort = uri.hasPort &&
        !((uri.scheme == 'https' && uri.port == 443) ||
            (uri.scheme == 'http' && uri.port == 80));
    if (hasExplicitPort) {
      buffer.write(':${uri.port}');
    }
    buffer.write(path);
    if (sortedQuery != null && sortedQuery.isNotEmpty) {
      buffer.write('?$sortedQuery');
    }

    return buffer.toString().toLowerCase();
  }

  static String normalizeImageUrl(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return raw.toLowerCase();
    return uri.replace(fragment: '').toString().trim().toLowerCase();
  }
}
