import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:savein/models.dart';
import 'package:savein/services/global_post_lookup_service.dart';

class UrlMetadataService {
  static const int _timeoutSeconds = 10;
  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (compatible; SaveIn!/1.0)',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive',
  };

  // Extract metadata from URL with enhanced image extraction
  static Future<UrlMetadata> extractMetadata(String url) async {
    try {
      // Ensure URL has protocol
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      // TikTok: intercetta prima dello scraping HTML perché TikTok
      // risponde sempre con la pagina di login ai bot.
      // Risolviamo il redirect (vm.tiktok.com → URL completo) e usiamo oEmbed.
      if (_isAnyTikTokUrl(url)) {
        try {
          final resolvedUrl = await _resolveTikTokUrl(url);
          final tikTokResult = await _enrichTikTokMetadata(
            resolvedUrl,
            _fallbackMetadata(resolvedUrl),
          );
          if (tikTokResult.hasValidData) return tikTokResult;
        } catch (_) {
          // Se oEmbed fallisce procedi con lo scraping normale
        }
      }

      final response = await http
          .get(Uri.parse(url), headers: _defaultHeaders)
          .timeout(Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        var metadata = _parseHtmlDocument(document, url);

        if (_isInstagramPostUrl(url) && metadata.imageUrl?.isNotEmpty != true) {
          metadata = await _enrichInstagramMetadata(url, metadata);
        }

        if (_isTikTokVideoUrl(url) &&
            (_isInvalidTikTokTitle(metadata.title) ||
                !_hasUsableTikTokImage(metadata.imageUrl))) {
          metadata = await _enrichTikTokMetadata(url, metadata);
        }

        return metadata;
      } else {
        if (_isInstagramPostUrl(url)) {
          final recoveredMetadata = await _enrichInstagramMetadata(
            url,
            _fallbackMetadata(url),
          );
          if (recoveredMetadata.hasValidData) {
            return recoveredMetadata;
          }
        }

        if (_isTikTokVideoUrl(url)) {
          final recoveredMetadata = await _enrichTikTokMetadata(
            url,
            _fallbackMetadata(url),
          );
          if (recoveredMetadata.hasValidData) {
            return recoveredMetadata;
          }
        }

        return _fallbackMetadata(url);
      }
    } catch (e) {
      print('Error extracting metadata: $e');

      if (_isInstagramPostUrl(url)) {
        try {
          final recoveredMetadata = await _enrichInstagramMetadata(
            url,
            _fallbackMetadata(url),
          );
          if (recoveredMetadata.hasValidData) {
            return recoveredMetadata;
          }
        } catch (instagramError) {
          print('Instagram fallback metadata failed: $instagramError');
        }
      }

      if (_isTikTokVideoUrl(url)) {
        try {
          final recoveredMetadata = await _enrichTikTokMetadata(
            url,
            _fallbackMetadata(url),
          );
          if (recoveredMetadata.hasValidData) {
            return recoveredMetadata;
          }
        } catch (tiktokError) {
          print('TikTok fallback metadata failed: $tiktokError');
        }
      }

      return _fallbackMetadata(url);
    }
  }

  /// Metadati per import: prima controlla `global_posts`, poi fetch social/web.
  static Future<UrlMetadata> resolveImportMetadata(String url) async {
    var normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('http://') &&
        !normalizedUrl.startsWith('https://')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    final lookup =
        await GlobalPostLookupService.instance.lookupByUrl(normalizedUrl);
    if (lookup.found && lookup.isUsableForImport) {
      print(
          'DEBUG: Metadati da DB comune global_posts (riuso, saveCount: ${lookup.saveCount})');
      return lookup.toUrlMetadata(fallbackUrl: normalizedUrl);
    }

    return extractMetadata(normalizedUrl);
  }

  static UrlMetadata _parseHtmlDocument(Document document, String url) {
    String? title;
    String? description;
    String? imageUrl;
    String? creatorName;
    String? creatorUsername;
    String? siteName;
    String? favicon;
    List<String> extractedHashtags = []; // 🆕 NUOVO: Lista hashtag estratti

    // Extract title with priority order
    title = _getMetaProperty(document, 'og:title') ??
        _getMetaProperty(document, 'twitter:title') ??
        _getMetaName(document, 'title') ??
        document.querySelector('title')?.text?.trim();

    // Extract description with priority order
    description = _getMetaProperty(document, 'og:description') ??
        _getMetaProperty(document, 'twitter:description') ??
        _getMetaName(document, 'description');

    // ENHANCED IMAGE EXTRACTION with multiple fallbacks
    imageUrl = _extractBestImage(document, url);

    // Extract creator/author when the source exposes it.
    creatorName = _extractCreatorName(document, url);
    creatorUsername = _extractCreatorUsername(document, url);

    // Extract site name
    siteName = _getMetaProperty(document, 'og:site_name') ??
        _getMetaProperty(document, 'twitter:site') ??
        _getMetaName(document, 'application-name') ??
        Uri.parse(url).host;

    // Extract favicon
    favicon = _getFavicon(document, url);

    // 🆕 NUOVO: Estrai hashtag dai metadati HTML
    extractedHashtags = _extractHashtagsFromHtml(document);

    return UrlMetadata(
      title: title?.isNotEmpty == true ? title : null,
      description: description?.isNotEmpty == true ? description : null,
      imageUrl: imageUrl?.isNotEmpty == true ? imageUrl : null,
      creatorName: creatorName?.isNotEmpty == true ? creatorName : null,
      creatorUsername:
          creatorUsername?.isNotEmpty == true ? creatorUsername : null,
      siteName: siteName?.isNotEmpty == true ? siteName : null,
      favicon: favicon?.isNotEmpty == true ? favicon : null,
      extractedHashtags: extractedHashtags, // 🆕 NUOVO: Aggiungi hashtag
    );
  }

  // 🆕 NUOVO: Estrai SOLO hashtag con simbolo # dai metadati HTML
  static List<String> _extractHashtagsFromHtml(Document document) {
    print(
      'DEBUG: 🏷️ Iniziando estrazione SOLO hashtag con # dai metadati HTML...',
    );
    Set<String> hashtagsSet = {};

    // 1. Cerca nei meta tag specifici per hashtag - SOLO con simbolo #
    List<String> hashtagSources = [
      _getMetaName(document, 'hashtags'),
      _getMetaProperty(document, 'twitter:hashtags'),
    ].where((source) => source?.isNotEmpty == true).map((s) => s!).toList();

    for (String source in hashtagSources) {
      final hashtags = _extractHashtagsFromText(source);
      hashtagsSet.addAll(hashtags);
      if (hashtags.isNotEmpty) {
        print(
          'DEBUG: 🏷️ Trovati ${hashtags.length} hashtag con # in meta: ${hashtags.take(3).join(", ")}',
        );
      }
    }

    // 2. Cerca nel title e description SOLO se contengono simbolo #
    final titleText = _getMetaProperty(document, 'og:title') ??
        document.querySelector('title')?.text ??
        '';
    if (titleText.contains('#')) {
      final titleHashtags = _extractHashtagsFromText(titleText);
      if (titleHashtags.isNotEmpty) {
        hashtagsSet.addAll(titleHashtags);
        print('DEBUG: 🏷️ Hashtag nel title: ${titleHashtags.join(", ")}');
      }
    }

    final descriptionText = _getMetaProperty(document, 'og:description') ??
        _getMetaName(document, 'description') ??
        '';
    if (descriptionText.contains('#')) {
      final descriptionHashtags = _extractHashtagsFromText(descriptionText);
      if (descriptionHashtags.isNotEmpty) {
        hashtagsSet.addAll(descriptionHashtags);
        print(
          'DEBUG: 🏷️ Hashtag nella description: ${descriptionHashtags.join(", ")}',
        );
      }
    }

    // 3. Cerca nei JSON-LD structured data SOLO con #
    final jsonLdHashtags = _extractHashtagsFromJsonLd(document);
    if (jsonLdHashtags.isNotEmpty) {
      hashtagsSet.addAll(jsonLdHashtags);
      print('DEBUG: 🏷️ Hashtag da JSON-LD: ${jsonLdHashtags.join(", ")}');
    }

    // 4. Cerca nei link/anchor SOLO con pattern #hashtag
    final linkHashtags = _extractHashtagsFromLinks(document);
    if (linkHashtags.isNotEmpty) {
      hashtagsSet.addAll(linkHashtags);
      print('DEBUG: 🏷️ Hashtag dai link: ${linkHashtags.take(3).join(", ")}');
    }

    // 5. Gestione speciale per social media - SOLO URL specifici per hashtag
    final socialHashtags = _extractSocialMediaHashtags(document);
    if (socialHashtags.isNotEmpty) {
      hashtagsSet.addAll(socialHashtags);
      print(
        'DEBUG: 🏷️ Hashtag da social media: ${socialHashtags.take(3).join(", ")}',
      );
    }

    final finalHashtags = hashtagsSet.toList();
    print(
      'DEBUG: 🏷️ Estrazione completata: ${finalHashtags.length} hashtag con # trovati',
    );
    if (finalHashtags.isNotEmpty) {
      print(
        'DEBUG: 🏷️ Hashtag finali: ${finalHashtags.take(5).join(", ")}${finalHashtags.length > 5 ? "..." : ""}',
      );
    }

    return finalHashtags;
  }

  static String? _extractCreatorName(Document document, String url) {
    final candidates = <String?>[
      _getMetaName(document, 'author'),
      _getMetaName(document, 'parsely-author'),
      _getMetaName(document, 'sailthru.author'),
      _getMetaProperty(document, 'article:author'),
      _getMetaProperty(document, 'profile:username'),
      _extractInstagramCreatorFromAlt(document),
      _extractCreatorFromTitle(document),
      _extractJsonLdAuthorName(document),
    ];

    for (final candidate in candidates) {
      final cleaned = _cleanCreatorName(candidate);
      if (cleaned != null) return cleaned;
    }

    return null;
  }

  static String? _extractCreatorUsername(
    Document document,
    String url,
  ) {
    final candidates = <String?>[
      _getMetaName(document, 'twitter:creator'),
      _getMetaProperty(document, 'twitter:creator'),
      _getMetaProperty(document, 'profile:username'),
      _extractCreatorUsernameFromTitle(document),
      _extractUsernameFromUrl(url),
    ];

    for (final candidate in candidates) {
      final username = _normalizeCreatorUsername(candidate);
      if (username != null) return username;
    }

    return null;
  }

  static String? _extractInstagramCreatorFromAlt(Document document) {
    for (final image in document.querySelectorAll('img')) {
      final alt = image.attributes['alt']?.trim();
      if (alt == null || alt.isEmpty) continue;

      final match = RegExp(
        r'instagram post shared by\s+(.+?)(?:\s+on\s+|$)',
        caseSensitive: false,
      ).firstMatch(alt);
      if (match != null) {
        return match.group(1)?.trim();
      }
    }

    return null;
  }

  static String? _extractCreatorFromTitle(Document document) {
    final title = (_getMetaProperty(document, 'og:title') ??
            _getMetaProperty(document, 'twitter:title') ??
            document.querySelector('title')?.text)
        ?.trim();
    if (title == null || title.isEmpty) return null;

    final patterns = [
      RegExp(r'^(.+?)\s+on\s+Instagram\b', caseSensitive: false),
      RegExp(r'^(.+?)\s+\(@[^)]+\)\s+on\s+TikTok\b', caseSensitive: false),
      RegExp(r'^(.+?)\s+on\s+TikTok\b', caseSensitive: false),
      RegExp(r'^(.+?)\s+\|\s+TikTok\b', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(title);
      final creator = _cleanCreatorName(match?.group(1));
      if (creator != null) return creator;
    }

    return null;
  }

  static String? _extractCreatorUsernameFromTitle(Document document) {
    final title = (_getMetaProperty(document, 'og:title') ??
            _getMetaProperty(document, 'twitter:title') ??
            document.querySelector('title')?.text)
        ?.trim();
    if (title == null || title.isEmpty) return null;

    final match = RegExp(r'@([A-Za-z0-9._-]{2,})').firstMatch(title);
    return _normalizeCreatorUsername(match?.group(1));
  }

  static String? _extractJsonLdAuthorName(Document document) {
    final jsonLdElements = document.querySelectorAll(
      'script[type="application/ld+json"]',
    );

    for (final element in jsonLdElements) {
      try {
        final jsonData = json.decode(element.text);
        final author = _findAuthorNameInJson(jsonData);
        if (author != null) return author;
      } catch (_) {
        // Ignore malformed JSON-LD.
      }
    }

    return null;
  }

  static String? _findAuthorNameInJson(dynamic obj) {
    if (obj is Map) {
      final author = obj['author'] ?? obj['creator'];
      final authorName = _authorNameFromValue(author);
      if (authorName != null) return authorName;

      for (final value in obj.values) {
        if (value is Map || value is List) {
          final nestedAuthor = _findAuthorNameInJson(value);
          if (nestedAuthor != null) return nestedAuthor;
        }
      }
    } else if (obj is List) {
      for (final item in obj) {
        final author = _findAuthorNameInJson(item);
        if (author != null) return author;
      }
    }

    return null;
  }

  static String? _authorNameFromValue(dynamic value) {
    if (value is String) return _cleanCreatorName(value);
    if (value is Map) {
      return _cleanCreatorName(value['name']?.toString()) ??
          _cleanCreatorName(value['alternateName']?.toString()) ??
          _cleanCreatorName(value['url']?.toString());
    }
    if (value is List) {
      for (final item in value) {
        final author = _authorNameFromValue(item);
        if (author != null) return author;
      }
    }
    return null;
  }

  static String? _extractUsernameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return null;

      final host = uri.host.toLowerCase();
      if (host.contains('tiktok.com') && segments.first.startsWith('@')) {
        return segments.first;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _cleanCreatorName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return _normalizeCreatorUsername(trimmed);
    }
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? _normalizeCreatorUsername(String? value) {
    var trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      try {
        final uri = Uri.parse(trimmed);
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) trimmed = segments.first;
      } catch (_) {
        return null;
      }
    }

    trimmed = trimmed
        .replaceFirst(RegExp(r'^@+'), '')
        .split(RegExp(r'\s+'))
        .first
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');

    if (trimmed.length < 2) return null;
    return '@$trimmed';
  }

  // 🆕 NUOVO: Estrai SOLO hashtag con simbolo # da testo generico
  static List<String> _extractHashtagsFromText(String text) {
    if (text.isEmpty) return [];

    // RIGOROSO: Cerca SOLO parole che iniziano con #
    final hashtagRegex = RegExp(
      r'#([a-zA-Z][a-zA-Z0-9_]{0,}(?:[a-zA-Z0-9]|[a-zA-Z]))',
      multiLine: true,
    );
    final matches = hashtagRegex.allMatches(text);

    Set<String> hashtags = {};
    for (var match in matches) {
      final hashtag = match.group(1);
      if (hashtag != null && hashtag.length > 1 && hashtag.length <= 30) {
        // Normalizza e pulisci l'hashtag
        final cleanTag = _cleanHashtag(hashtag);
        if (cleanTag.isNotEmpty) {
          hashtags.add(cleanTag);
        }
      }
    }

    // RIMOSSO: Non più fallback su keywords senza # - SOLO hashtag espliciti
    return hashtags.toList();
  }

  // 🆕 NUOVO: Estrai hashtag da JSON-LD structured data
  static List<String> _extractHashtagsFromJsonLd(Document document) {
    Set<String> hashtags = {};

    final jsonLdElements = document.querySelectorAll(
      'script[type="application/ld+json"]',
    );

    for (var element in jsonLdElements) {
      try {
        final jsonData = json.decode(element.text);
        _extractHashtagsFromJsonObject(jsonData, hashtags);
      } catch (e) {
        // Ignore malformed JSON
      }
    }

    return hashtags.toList();
  }

  // 🆕 NUOVO: Ricerca RIGOROSA negli oggetti JSON-LD - SOLO con simbolo #
  static void _extractHashtagsFromJsonObject(
    dynamic obj,
    Set<String> hashtags,
  ) {
    if (obj is Map) {
      // Campi comuni che potrebbero contenere hashtag con #
      final tagFields = [
        'hashtags',
        'mentions',
      ]; // RIMOSSO: keywords, tags, about, category

      for (String field in tagFields) {
        if (obj.containsKey(field)) {
          final value = obj[field];
          if (value is String && value.contains('#')) {
            hashtags.addAll(_extractHashtagsFromText(value));
          } else if (value is List) {
            for (var item in value) {
              if (item is String && item.contains('#')) {
                hashtags.addAll(_extractHashtagsFromText(item));
              } else if (item is Map && item.containsKey('name')) {
                final nameValue = item['name'].toString();
                if (nameValue.contains('#')) {
                  hashtags.addAll(_extractHashtagsFromText(nameValue));
                }
              }
            }
          }
        }
      }

      // Recursively check other properties but ONLY for hashtag-specific content
      for (var key in obj.keys) {
        if (key.toString().toLowerCase().contains('hashtag') ||
            key.toString().toLowerCase().contains('tag')) {
          final value = obj[key];
          if (value is Map || value is List) {
            _extractHashtagsFromJsonObject(value, hashtags);
          }
        }
      }
    } else if (obj is List) {
      for (var item in obj) {
        _extractHashtagsFromJsonObject(item, hashtags);
      }
    }
  }

  // 🆕 NUOVO: Estrai hashtag dai link - SOLO con simbolo # o URL specifici
  static List<String> _extractHashtagsFromLinks(Document document) {
    Set<String> hashtags = {};

    // Cerca link con href contenenti hashtag con simbolo #
    final links = document.querySelectorAll('a[href*="#"]');
    for (var link in links.take(20)) {
      // Limita per performance
      final href = link.attributes['href'] ?? '';
      final text = link.text.trim();

      // SOLO se contengono effettivamente il simbolo #
      if (href.contains('#') && !href.startsWith('#')) {
        // Evita anchor links
        hashtags.addAll(_extractHashtagsFromText(href));
      }
      if (text.contains('#')) {
        hashtags.addAll(_extractHashtagsFromText(text));
      }
    }

    return hashtags.toList();
  }

  // 🆕 NUOVO: Gestione RIGOROSA per social media - SOLO URL hashtag specifici
  static List<String> _extractSocialMediaHashtags(Document document) {
    Set<String> hashtags = {};

    // Instagram: SOLO link diretti ai tag
    final instagramElements = document.querySelectorAll(
      'a[href*="/explore/tags/"]',
    );
    for (var element in instagramElements.take(10)) {
      final href = element.attributes['href'] ?? '';
      final match = RegExp(r'/explore/tags/([^/\?]+)').firstMatch(href);
      if (match != null && match.group(1) != null) {
        final cleanTag = _cleanHashtag(match.group(1)!);
        if (cleanTag.isNotEmpty) {
          hashtags.add(cleanTag);
        }
      }
    }

    // LinkedIn hashtag: SOLO URL diretti
    final linkedinElements = document.querySelectorAll(
      'a[href*="/feed/hashtag/"]',
    );
    for (var element in linkedinElements.take(10)) {
      final href = element.attributes['href'] ?? '';
      final match = RegExp(r'/feed/hashtag/([^/\?]+)').firstMatch(href);
      if (match != null && match.group(1) != null) {
        final cleanTag = _cleanHashtag(match.group(1)!);
        if (cleanTag.isNotEmpty) {
          hashtags.add(cleanTag);
        }
      }
    }

    // Twitter/X: SOLO elementi con testo che contiene #
    final twitterElements = document.querySelectorAll(
      '[data-testid*="hashtag"], .hashtag, [href*="/hashtag/"]',
    );
    for (var element in twitterElements.take(10)) {
      final text = element.text.trim();
      if (text.contains('#')) {
        hashtags.addAll(_extractHashtagsFromText(text));
      }
    }

    return hashtags.toList();
  }

  // 🆕 NUOVO: Pulisce e normalizza un hashtag
  static String _cleanHashtag(String hashtag) {
    // Rimuovi caratteri non validi e normalizza
    String cleaned = hashtag
        .replaceAll(RegExp(r'[^\w]'), '') // Solo lettere, numeri, underscore
        .toLowerCase()
        .trim();

    // Filtri di validazione
    if (cleaned.isEmpty ||
        cleaned.length < 2 ||
        cleaned.length > 30 ||
        RegExp(r'^\d+$').hasMatch(cleaned) || // Solo numeri
        _isCommonWord(cleaned)) {
      return '';
    }

    return cleaned;
  }

  // 🆕 NUOVO: Verifica se è una parola comune da evitare come hashtag
  static bool _isCommonWord(String word) {
    final commonWords = {
      // Parole comuni inglesi
      'the',
      'and',
      'for',
      'are',
      'but',
      'not',
      'you',
      'all',
      'can',
      'her',
      'was',
      'one',
      'our',
      'had',
      'will',
      'there',
      'what',
      'your',
      'when',
      'him',
      'my',
      'has',
      'how',
      'did',
      'get',
      'may',
      'been',
      'this',
      'that',
      'with',
      'have',
      'from',
      'they',
      'know',
      'want',
      'been',
      'good',
      'much',
      'some',
      'time',
      'very',
      'when',
      'come',
      'here',
      'just',
      'like',
      'long',
      'make',
      'many',
      'over',
      'such',
      'take', 'than', 'them', 'well', 'were', 'work',

      // Parole comuni italiane
      'che',
      'con',
      'del',
      'della',
      'delle',
      'una',
      'alla',
      'nel',
      'nella',
      'per',
      'anche',
      'come',
      'dopo',
      'senza',
      'sono',
      'stato',
      'essere',
      'avere',
      'fare',
      'dire',
      'andare',
      'vedere',
      'sapere',
      'dare',
      'volere',
      'venire',
      'dovere',
      'potere',
      'prima',
      'ancora',
      'oggi',
      'sempre',
      'molto',
      'bene', 'dove', 'quando', 'perché', 'mentre', 'però', 'quindi', 'invece',

      // Parole generiche web
      'click',
      'here',
      'more',
      'read',
      'about',
      'page',
      'site',
      'website',
      'home',
      'news',
      'blog',
      'post',
      'article',
      'content',
      'info',
      'link',
      'visit',
      'follow',
      'share',
      'like',
      'comment',
    };

    return commonWords.contains(word.toLowerCase());
  }

  // ENHANCED: Extract best available image with multiple sources
  static String? _extractBestImage(Document document, String url) {
    List<String> candidateImages = [];

    // 1. Open Graph image (highest priority)
    String? ogImage = _getMetaProperty(document, 'og:image');
    if (ogImage != null) candidateImages.add(ogImage);

    // 2. Twitter image
    String? twitterImage = _getMetaProperty(document, 'twitter:image') ??
        _getMetaProperty(document, 'twitter:image:src');
    if (twitterImage != null) candidateImages.add(twitterImage);

    // 3. Schema.org images
    String? schemaImage = _getMetaProperty(document, 'image');
    if (schemaImage != null) candidateImages.add(schemaImage);

    // 4. Look for large images in content
    final imgElements = document.querySelectorAll('img');
    for (var img in imgElements) {
      String? src = img.attributes['src'];
      if (src != null && _isLikelyFeatureImage(src, img)) {
        candidateImages.add(src);
      }
    }

    // 5. Look for JSON-LD structured data
    final jsonLdImages = _extractJsonLdImages(document);
    candidateImages.addAll(jsonLdImages);

    // Process and validate images
    for (String imageUrl in candidateImages) {
      String? processedUrl = _makeAbsoluteUrl(imageUrl, url);
      if (processedUrl != null && _isValidImageUrl(processedUrl)) {
        return processedUrl;
      }
    }

    return null;
  }

  // Check if image is likely a feature/hero image
  static bool _isLikelyFeatureImage(String src, Element img) {
    // Check size attributes
    String? width = img.attributes['width'];
    String? height = img.attributes['height'];

    if (width != null && height != null) {
      try {
        int w = int.parse(width);
        int h = int.parse(height);
        if (w >= 300 && h >= 200) return true;
      } catch (e) {}
    }

    // Check classes and IDs for common patterns
    String? className = img.attributes['class'];
    String? id = img.attributes['id'];

    List<String> featurePatterns = [
      'featured',
      'hero',
      'main',
      'banner',
      'cover',
      'thumb',
      'preview',
      'highlight',
      'primary',
      'header',
    ];

    for (String pattern in featurePatterns) {
      if (className?.toLowerCase().contains(pattern) == true ||
          id?.toLowerCase().contains(pattern) == true ||
          src.toLowerCase().contains(pattern)) {
        return true;
      }
    }

    return false;
  }

  // Extract images from JSON-LD structured data
  static List<String> _extractJsonLdImages(Document document) {
    List<String> images = [];

    final jsonLdElements = document.querySelectorAll(
      'script[type="application/ld+json"]',
    );

    for (var element in jsonLdElements) {
      try {
        final jsonData = json.decode(element.text);
        _extractImagesFromJsonObject(jsonData, images);
      } catch (e) {
        // Ignore malformed JSON
      }
    }

    return images;
  }

  static void _extractImagesFromJsonObject(dynamic obj, List<String> images) {
    if (obj is Map) {
      if (obj.containsKey('image')) {
        dynamic imageData = obj['image'];
        if (imageData is String) {
          images.add(imageData);
        } else if (imageData is List) {
          for (var img in imageData) {
            if (img is String) images.add(img);
            if (img is Map && img.containsKey('url')) {
              images.add(img['url'].toString());
            }
          }
        } else if (imageData is Map && imageData.containsKey('url')) {
          images.add(imageData['url'].toString());
        }
      }

      // Recursively check other properties
      for (var value in obj.values) {
        if (value is Map || value is List) {
          _extractImagesFromJsonObject(value, images);
        }
      }
    } else if (obj is List) {
      for (var item in obj) {
        _extractImagesFromJsonObject(item, images);
      }
    }
  }

  static String? _getMetaProperty(Document document, String property) {
    return document
        .querySelector('meta[property="$property"]')
        ?.attributes['content']
        ?.trim();
  }

  static String? _getMetaName(Document document, String name) {
    return document
        .querySelector('meta[name="$name"]')
        ?.attributes['content']
        ?.trim();
  }

  static String? _makeAbsoluteUrl(String imageUrl, String baseUrl) {
    try {
      if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        return imageUrl;
      }

      final uri = Uri.parse(baseUrl);

      if (imageUrl.startsWith('//')) {
        return '${uri.scheme}:$imageUrl';
      } else if (imageUrl.startsWith('/')) {
        return '${uri.scheme}://${uri.host}$imageUrl';
      } else {
        return '${uri.scheme}://${uri.host}/${imageUrl}';
      }
    } catch (e) {
      return null;
    }
  }

  static bool _isValidImageUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme) return false;

      final path = uri.path.toLowerCase();
      const imageExtensions = [
        '.jpg',
        '.jpeg',
        '.png',
        '.gif',
        '.webp',
        '.bmp',
        '.svg',
        '.heic',
        '.heif',
      ];

      // Check file extension
      bool hasImageExtension = imageExtensions.any((ext) => path.endsWith(ext));

      // Check for social media image patterns
      bool isSocialImage = _isSocialMediaImage(url);

      return hasImageExtension || isSocialImage;
    } catch (e) {
      return false;
    }
  }

  static bool _isSocialMediaImage(String url) {
    final lowerUrl = url.toLowerCase();

    // Social media image patterns
    if (lowerUrl.contains('instagram.com') && lowerUrl.contains('/p/'))
      return true;
    if (lowerUrl.contains('cdninstagram.com') ||
        lowerUrl.contains('fbcdn.net')) {
      return lowerUrl.contains('/v/t') ||
          lowerUrl.contains('scontent') ||
          lowerUrl.contains('dst-jpg');
    }
    if (lowerUrl.contains('facebook.com') && lowerUrl.contains('_o.'))
      return true;
    if (lowerUrl.contains('twitter.com') || lowerUrl.contains('x.com')) {
      return lowerUrl.contains('media') || lowerUrl.contains('pbs.twimg.com');
    }
    if (lowerUrl.contains('youtube.com') || lowerUrl.contains('youtu.be')) {
      return lowerUrl.contains('maxresdefault') ||
          lowerUrl.contains('hqdefault');
    }
    if (lowerUrl.contains('tiktok.com') && lowerUrl.contains('/video/'))
      return true;
    if (lowerUrl.contains('tiktokcdn')) return true;
    if (lowerUrl.contains('linkedin.com') && lowerUrl.contains('media'))
      return true;

    return false;
  }

  static String? _getFavicon(Document document, String url) {
    // Try to find favicon link
    final faviconLink = document.querySelector('link[rel="icon"]') ??
        document.querySelector('link[rel="shortcut icon"]') ??
        document.querySelector('link[rel="apple-touch-icon"]');

    if (faviconLink != null) {
      String? href = faviconLink.attributes['href'];
      if (href != null) {
        return _makeAbsoluteUrl(href, url);
      }
    }

    // Fallback to default favicon location
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}/favicon.ico';
  }

  static UrlMetadata _fallbackMetadata(String url) {
    final uri = Uri.parse(url);
    String siteName = uri.host;

    if (siteName.startsWith('www.')) {
      siteName = siteName.substring(4);
    }

    siteName = siteName[0].toUpperCase() + siteName.substring(1);

    return UrlMetadata(
      title: siteName,
      description: url,
      siteName: siteName,
      extractedHashtags: [], // 🆕 NUOVO: Lista vuota nel fallback
    );
  }

  static Future<UrlMetadata> _enrichInstagramMetadata(
    String url,
    UrlMetadata baseMetadata,
  ) async {
    final embedUrl = _buildInstagramEmbedUrl(url);
    if (embedUrl == null) {
      return baseMetadata;
    }

    try {
      final response = await http
          .get(Uri.parse(embedUrl), headers: _defaultHeaders)
          .timeout(Duration(seconds: _timeoutSeconds));

      if (response.statusCode != 200) {
        return baseMetadata;
      }

      final document = html_parser.parse(response.body);
      final embedMetadata = _parseHtmlDocument(document, embedUrl);
      final embedImage = _extractInstagramEmbedImage(document, embedUrl);

      return baseMetadata.copyWith(
        title: baseMetadata.title ?? embedMetadata.title,
        description: baseMetadata.description ?? embedMetadata.description,
        imageUrl: baseMetadata.imageUrl ?? embedImage ?? embedMetadata.imageUrl,
        creatorName: baseMetadata.creatorName ?? embedMetadata.creatorName,
        creatorUsername:
            baseMetadata.creatorUsername ?? embedMetadata.creatorUsername,
        siteName: baseMetadata.siteName ?? embedMetadata.siteName,
        favicon: baseMetadata.favicon ?? embedMetadata.favicon,
        extractedHashtags: baseMetadata.extractedHashtags.isNotEmpty
            ? baseMetadata.extractedHashtags
            : embedMetadata.extractedHashtags,
      );
    } catch (e) {
      print('Instagram embed fallback failed: $e');
      return baseMetadata;
    }
  }

  static Future<UrlMetadata> _enrichTikTokMetadata(
    String url,
    UrlMetadata baseMetadata,
  ) async {
    final oEmbedUrl = _buildTikTokOEmbedUrl(url);
    if (oEmbedUrl == null) {
      return baseMetadata;
    }

    try {
      final response = await http
          .get(Uri.parse(oEmbedUrl), headers: _defaultHeaders)
          .timeout(Duration(seconds: _timeoutSeconds));

      if (response.statusCode != 200) {
        return baseMetadata;
      }

      final data = json.decode(response.body);
      if (data is! Map<String, dynamic>) {
        return baseMetadata;
      }

      final oEmbedTitle = (data['title'] as String?)?.trim();
      final oEmbedThumbnail = (data['thumbnail_url'] as String?)?.trim();
      final oEmbedAuthorName = (data['author_name'] as String?)?.trim();
      final oEmbedAuthorUrl = (data['author_url'] as String?)?.trim();

      final resolvedTitle = !_isInvalidTikTokTitle(oEmbedTitle)
          ? oEmbedTitle
          : (!_isInvalidTikTokTitle(baseMetadata.title)
              ? baseMetadata.title
              : null);

      final resolvedDescription =
          (baseMetadata.description?.isNotEmpty == true &&
                  !_isInvalidTikTokTitle(baseMetadata.description))
              ? baseMetadata.description
              : (!_isInvalidTikTokTitle(oEmbedTitle) ? oEmbedTitle : null);

      final resolvedImage = _hasUsableTikTokImage(oEmbedThumbnail)
          ? oEmbedThumbnail
          : (_hasUsableTikTokImage(baseMetadata.imageUrl)
              ? baseMetadata.imageUrl
              : null);

      return baseMetadata.copyWith(
        title: resolvedTitle,
        description: resolvedDescription,
        imageUrl: resolvedImage,
        creatorName: _cleanCreatorName(oEmbedAuthorName),
        creatorUsername:
            _normalizeCreatorUsername(oEmbedAuthorUrl ?? oEmbedAuthorName),
        siteName: baseMetadata.siteName ?? 'TikTok',
        extractedHashtags: baseMetadata.extractedHashtags,
      );
    } catch (e) {
      print('TikTok oEmbed fallback failed: $e');
      return baseMetadata;
    }
  }

  static bool _isInstagramPostUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (!(host.contains('instagram.com') || host.contains('instagr.am'))) {
        return false;
      }

      return _extractInstagramPostSegments(uri.pathSegments) != null;
    } catch (_) {
      final lowerUrl = url.toLowerCase();
      return (lowerUrl.contains('instagram.com') ||
              lowerUrl.contains('instagr.am')) &&
          (lowerUrl.contains('/p/') ||
              lowerUrl.contains('/reel/') ||
              lowerUrl.contains('/tv/'));
    }
  }

  static bool _isAnyTikTokUrl(String url) {
    try {
      return Uri.parse(url).host.toLowerCase().contains('tiktok.com');
    } catch (_) {
      return url.toLowerCase().contains('tiktok.com');
    }
  }

  static bool _isTikTokVideoUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (!host.contains('tiktok.com')) {
        return false;
      }

      return uri.pathSegments
          .any((segment) => segment.toLowerCase() == 'video');
    } catch (_) {
      final lowerUrl = url.toLowerCase();
      return lowerUrl.contains('tiktok.com') && lowerUrl.contains('/video/');
    }
  }

  /// Segue i redirect di un link TikTok corto (vm.tiktok.com) per ottenere
  /// l'URL completo contenente /video/. Se non riesce, restituisce l'URL originale.
  static Future<String> _resolveTikTokUrl(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: _defaultHeaders)
          .timeout(const Duration(seconds: 8));
      final finalUrl = response.request?.url.toString();
      if (finalUrl != null && finalUrl.contains('/video/')) {
        return finalUrl;
      }
      return url;
    } catch (_) {
      return url;
    }
  }

  static String? _buildTikTokOEmbedUrl(String url) {
    if (!_isAnyTikTokUrl(url)) {
      return null;
    }

    try {
      final normalizedUrl = Uri.parse(url)
          .replace(queryParameters: null, fragment: null)
          .toString();

      return Uri.https('www.tiktok.com', '/oembed', {
        'url': normalizedUrl,
      }).toString();
    } catch (_) {
      return null;
    }
  }

  static String? _buildInstagramEmbedUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final postSegments = _extractInstagramPostSegments(uri.pathSegments);
      if (postSegments == null) {
        return null;
      }

      return uri.replace(
        queryParameters: null,
        fragment: null,
        pathSegments: <String>[...postSegments, 'embed', 'captioned'],
      ).toString();
    } catch (_) {
      return null;
    }
  }

  static List<String>? _extractInstagramPostSegments(
    List<String> pathSegments,
  ) {
    if (pathSegments.isEmpty) {
      return null;
    }

    final normalizedSegments =
        pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (normalizedSegments.length < 2) {
      return null;
    }

    const supportedPrefixes = {'p', 'reel', 'reels', 'tv'};
    final prefix = normalizedSegments.first.toLowerCase();
    if (!supportedPrefixes.contains(prefix)) {
      return null;
    }

    return normalizedSegments.take(2).toList();
  }

  static String? _extractInstagramEmbedImage(
    Document document,
    String baseUrl,
  ) {
    final primaryMedia = document.querySelector('img.EmbeddedMediaImage');
    if (primaryMedia != null) {
      final candidate = _extractImageCandidateFromElement(
        primaryMedia,
        baseUrl,
        preferLargestFromSrcSet: true,
      );
      if (candidate != null &&
          _isUsableInstagramPostImage(candidate, primaryMedia)) {
        return candidate;
      }
    }

    final fallbackSelectors = <String>[
      'img[srcset]',
      'img[data-src]',
      'img[src]',
    ];

    for (final selector in fallbackSelectors) {
      for (final element in document.querySelectorAll(selector)) {
        final candidate = _extractImageCandidateFromElement(
          element,
          baseUrl,
          preferLargestFromSrcSet: true,
        );
        if (candidate != null && _isValidImageUrl(candidate)) {
          if (_isUsableInstagramPostImage(candidate, element)) {
            return candidate;
          }
        }
      }
    }

    return null;
  }

  static bool _isInvalidTikTokTitle(String? title) {
    final normalized = (title ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    return normalized == 'log in | tiktok' ||
        normalized == 'login | tiktok' ||
        normalized == 'tiktok' ||
        normalized == 'log in to tiktok';
  }

  static bool _hasUsableTikTokImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return false;
    }

    final lowerUrl = imageUrl.toLowerCase();
    if (lowerUrl.contains('tiktok_web_login') ||
        lowerUrl.contains('passport') ||
        lowerUrl.contains('login')) {
      return false;
    }

    // Le thumbnail CDN di TikTok (p16-sign.tiktokcdn-us.com, p77-sign-sg.tiktokcdn.com, ecc.)
    // usano estensioni non standard come ~noop.image o ~tplv-tiktokx-origin.image.
    // Se il dominio è un CDN TikTok, accettiamo direttamente l'URL.
    if (lowerUrl.contains('tiktokcdn')) {
      return true;
    }

    return _isValidImageUrl(imageUrl);
  }

  static String? _extractImageCandidateFromElement(
      Element element, String baseUrl,
      {bool preferLargestFromSrcSet = false}) {
    final src = element.attributes['src']?.trim();
    final dataSrc = element.attributes['data-src']?.trim();
    final srcSet = element.attributes['srcset']?.trim();

    for (final rawValue in <String?>[src, dataSrc]) {
      final absolute = _makeAbsoluteUrl(rawValue ?? '', baseUrl);
      if (absolute != null && absolute.isNotEmpty) {
        return absolute;
      }
    }

    if (srcSet != null && srcSet.isNotEmpty) {
      final srcSetEntries = srcSet.split(',');
      final orderedEntries =
          preferLargestFromSrcSet ? srcSetEntries.reversed : srcSetEntries;

      for (final entry in orderedEntries) {
        final urlPart = entry.trim().split(RegExp(r'\s+')).first;
        final absolute = _makeAbsoluteUrl(urlPart, baseUrl);
        if (absolute != null && absolute.isNotEmpty) {
          return absolute;
        }
      }
    }

    return null;
  }

  static bool _isUsableInstagramPostImage(String url, Element element) {
    if (!_isValidImageUrl(url)) {
      return false;
    }

    final lowerUrl = url.toLowerCase();
    final alt = (element.attributes['alt'] ?? '').toLowerCase();
    final className = (element.attributes['class'] ?? '').toLowerCase();

    if (className.contains('embeddedmediaimage')) {
      return true;
    }

    if (alt.contains('instagram post shared by')) {
      return true;
    }

    if (lowerUrl.contains('profile_pic') ||
        lowerUrl.contains('dst-jpg_s150x150') ||
        lowerUrl.contains('dst-jpg_s240x240')) {
      return false;
    }

    if (alt.isNotEmpty && !alt.contains('instagram post')) {
      return false;
    }

    return true;
  }

  // Validate if URL is reachable
  static Future<bool> isUrlValid(String url) async {
    try {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final response =
          await http.head(Uri.parse(url)).timeout(Duration(seconds: 5));

      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (e) {
      return false;
    }
  }

  // Extract domain from URL for display
  static String getDomainFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      String domain = uri.host;

      if (domain.startsWith('www.')) {
        domain = domain.substring(4);
      }

      return domain;
    } catch (e) {
      return url;
    }
  }

  // Check if URL is from a specific social platform
  static String? getSocialPlatform(String url) {
    final domain = getDomainFromUrl(url).toLowerCase();

    if (domain.contains('instagram.com')) return 'Instagram';
    if (domain.contains('facebook.com')) return 'Facebook';
    if (domain.contains('twitter.com') || domain.contains('x.com'))
      return 'Twitter/X';
    if (domain.contains('youtube.com') || domain.contains('youtu.be'))
      return 'YouTube';
    if (domain.contains('tiktok.com')) return 'TikTok';
    if (domain.contains('linkedin.com')) return 'LinkedIn';
    if (domain.contains('pinterest.com')) return 'Pinterest';
    if (domain.contains('reddit.com')) return 'Reddit';
    if (domain.contains('medium.com')) return 'Medium';
    if (domain.contains('github.com')) return 'GitHub';

    return null;
  }

  // Generate preview text from description
  static String generatePreviewText(
    String? description, {
    int maxLength = 150,
  }) {
    if (description == null || description.isEmpty) {
      return 'Nessuna descrizione disponibile';
    }

    if (description.length <= maxLength) {
      return description;
    }

    String truncated = description.substring(0, maxLength);
    int lastSpaceIndex = truncated.lastIndexOf(' ');

    if (lastSpaceIndex > maxLength * 0.8) {
      truncated = truncated.substring(0, lastSpaceIndex);
    }

    return '$truncated...';
  }

  // 🆕 NUOVO: Utility per combinare hashtag da più fonti eliminando duplicati
  static List<String> combineHashtags(List<List<String>> hashtagSources) {
    Set<String> combined = {};

    for (List<String> source in hashtagSources) {
      for (String hashtag in source) {
        final cleaned = _cleanHashtag(hashtag);
        if (cleaned.isNotEmpty) {
          combined.add(cleaned);
        }
      }
    }

    final result = combined.toList()..sort();
    print(
      'DEBUG: 🏷️ Hashtag combinati: ${result.length} unici da ${hashtagSources.length} fonti',
    );
    return result;
  }
}
