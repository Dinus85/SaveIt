import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Apre un post salvato nell'app social (Instagram, TikTok, YouTube)
/// sul contenuto cliccato, non sul primo reel del feed.
class SocialDeepLinkOpener {
  SocialDeepLinkOpener._();

  static const _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  static Future<void> open(String rawUrl) async {
    final url = _ensureHttp(rawUrl.trim());
    if (url.isEmpty) return;

    final candidates = await _buildCandidates(url);
    for (final uri in candidates) {
      if (await _tryLaunch(uri, LaunchMode.externalNonBrowserApplication)) {
        return;
      }
    }
    for (final uri in candidates) {
      if (await _tryLaunch(uri, LaunchMode.externalApplication)) {
        return;
      }
    }

    await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
  }

  static Future<bool> _tryLaunch(Uri uri, LaunchMode mode) async {
    try {
      return await launchUrl(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }

  static Future<List<Uri>> _buildCandidates(String url) async {
    var working = _unwrapRedirector(url);
    if (_needsResolve(working)) {
      working = await _followRedirects(working);
    }

    final uris = <Uri>[];
    void add(Uri? uri) {
      if (uri == null) return;
      if (uris.any((existing) => existing.toString() == uri.toString())) {
        return;
      }
      uris.add(uri);
    }

    final instagram = _parseInstagram(working);
    if (instagram != null) {
      if (!kIsWeb &&
          instagram.shortcode.length >= 8 &&
          instagram.shortcode.length <= 15) {
        final mediaId = _instagramShortcodeToMediaId(instagram.shortcode);
        if (mediaId != null) {
          add(Uri.parse('instagram://media?id=$mediaId'));
        }
        if (instagram.isReel) {
          add(Uri.parse('instagram://reel?id=${instagram.shortcode}'));
        }
      }
      // /p/ apre il media anche per i reel; /reel/ a freddo spesso va al Reels tab.
      add(Uri.parse('https://www.instagram.com/p/${instagram.shortcode}/'));
      if (instagram.isReel) {
        add(Uri.parse(
            'https://www.instagram.com/reel/${instagram.shortcode}/'));
      }
    }

    final tiktokVideoId = _parseTikTokVideoId(working);
    if (tiktokVideoId != null) {
      if (!kIsWeb) {
        add(Uri.parse('snssdk1233://aweme/detail/$tiktokVideoId'));
        add(Uri.parse('tiktok://aweme/detail/$tiktokVideoId'));
      }
      add(_stripTracking(working));
    }

    final youtube = _parseYouTubeId(working);
    if (youtube != null) {
      if (!kIsWeb) {
        add(Uri.parse('vnd.youtube:$youtube'));
        add(Uri.parse('youtube://watch?v=$youtube'));
      }
      add(Uri.parse('https://www.youtube.com/watch?v=$youtube'));
    }

    add(_stripTracking(working));
    add(Uri.parse(_ensureHttp(url)));
    return uris;
  }

  static bool _needsResolve(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host.contains('vm.tiktok.com') ||
          host.contains('vt.tiktok.com') ||
          host.contains('l.instagram.com')) {
        return true;
      }
      if (host.contains('tiktok.com') &&
          uri.pathSegments.any((s) => s.toLowerCase() == 't')) {
        return true;
      }
      if (host.contains('instagram.com') &&
          uri.pathSegments.any((s) => s.toLowerCase() == 'share')) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _followRedirects(String url) async {
    final client = http.Client();
    try {
      var current = Uri.parse(url);
      for (var i = 0; i < 8; i++) {
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll(_browserHeaders);
        final response =
            await client.send(request).timeout(const Duration(seconds: 6));
        try {
          if (response.statusCode >= 300 && response.statusCode < 400) {
            final location = response.headers['location'];
            if (location == null || location.isEmpty) break;
            current = current.resolve(location);
            continue;
          }
          break;
        } finally {
          await response.stream.listen((_) {}).cancel();
        }
      }
      return current.toString();
    } catch (_) {
      return url;
    } finally {
      client.close();
    }
  }

  static String _unwrapRedirector(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host.contains('l.instagram.com') || host.contains('l.facebook.com')) {
        final nested = uri.queryParameters['u'];
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    } catch (_) {}
    return url;
  }

  static _InstagramTarget? _parseInstagram(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (!(host.contains('instagram.com') || host.contains('instagr.am'))) {
        return null;
      }

      final segments = uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      if (segments.length < 2) return null;

      const kinds = {'p', 'reel', 'reels', 'tv'};
      var start = 0;
      if (segments.first.toLowerCase() == 'share' && segments.length >= 3) {
        start = 1;
      }

      String? kind;
      String? shortcode;
      if (start < segments.length &&
          kinds.contains(segments[start].toLowerCase()) &&
          start + 1 < segments.length) {
        kind = segments[start].toLowerCase();
        shortcode = segments[start + 1];
      } else if (start + 2 < segments.length &&
          kinds.contains(segments[start + 1].toLowerCase())) {
        kind = segments[start + 1].toLowerCase();
        shortcode = segments[start + 2];
      }

      if (kind == null || shortcode == null) return null;
      if (shortcode.toLowerCase() == 'embed') return null;
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(shortcode)) return null;

      return _InstagramTarget(
        shortcode: shortcode,
        isReel: kind == 'reel' || kind == 'reels',
      );
    } catch (_) {
      return null;
    }
  }

  /// Instagram shortcode → media id numerico per `instagram://media?id=`.
  static String? _instagramShortcodeToMediaId(String shortcode) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    var id = BigInt.zero;
    final base = BigInt.from(64);
    for (final unit in shortcode.codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(unit));
      if (index < 0) return null;
      id = id * base + BigInt.from(index);
    }
    if (id == BigInt.zero) return null;
    return id.toString();
  }

  static String? _parseTikTokVideoId(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.host.toLowerCase().contains('tiktok.com')) return null;
      final segments = uri.pathSegments;
      for (var i = 0; i < segments.length - 1; i++) {
        final kind = segments[i].toLowerCase();
        if (kind == 'video' || kind == 'photo') {
          final id = segments[i + 1];
          if (RegExp(r'^\d+$').hasMatch(id)) return id;
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _parseYouTubeId(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (!(host.contains('youtube.com') || host.contains('youtu.be'))) {
        return null;
      }
      if (host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      final watchId = uri.queryParameters['v'];
      if (watchId != null && watchId.isNotEmpty) return watchId;
      final segments = uri.pathSegments;
      for (var i = 0; i < segments.length - 1; i++) {
        if (segments[i].toLowerCase() == 'shorts' ||
            segments[i].toLowerCase() == 'embed') {
          return segments[i + 1];
        }
      }
    } catch (_) {}
    return null;
  }

  static Uri _stripTracking(String url) {
    final uri = Uri.parse(_ensureHttp(url));
    final cleaned = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) {
        final lower = key.toLowerCase();
        return lower.startsWith('utm_') ||
            lower == 'igsh' ||
            lower == 'igshid' ||
            lower == 'si' ||
            lower == 'fbclid' ||
            lower == 'feature';
      });
    return uri.replace(
      queryParameters: cleaned.isEmpty ? null : cleaned,
      fragment: '',
    );
  }

  static String _ensureHttp(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.contains('://')) return url;
    return 'https://$url';
  }
}

class _InstagramTarget {
  final String shortcode;
  final bool isReel;

  const _InstagramTarget({
    required this.shortcode,
    required this.isReel,
  });
}