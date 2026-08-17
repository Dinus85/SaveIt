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

  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7',
    // Bypass the EU consent interstitial so Maps HTML (name + static map) is returned.
    'Cookie': 'CONSENT=YES+',
  };

  // Extract metadata from URL with enhanced image extraction
  static Future<UrlMetadata> extractMetadata(
    String url, {
    String? sharedText,
  }) async {
    try {
      // Ensure URL has protocol
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      if (isGoogleMapsOrSearchUrl(url)) {
        try {
          return await _extractGooglePlaceMetadata(
            url,
            sharedText: sharedText,
          );
        } catch (e) {
          print('DEBUG: Google place metadata failed: $e');
          return UrlMetadata(
            title: placeNameFromSharedText(sharedText, url) ??
                placeNameFromGoogleUrl(url) ??
                'Luogo su Google Maps',
            description: _descriptionFromSharedText(sharedText, url),
            siteName: 'Google Maps',
          );
        }
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

      final headers =
          isGoogleMapsOrSearchUrl(url) ? _browserHeaders : _defaultHeaders;
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 200) {
        final finalUrl = response.request?.url.toString() ?? url;
        final document = html_parser.parse(response.body);
        var metadata = _parseHtmlDocument(document, finalUrl);
        metadata = _enrichGooglePlaceMetadata(
          originalUrl: url,
          finalUrl: finalUrl,
          document: document,
          metadata: metadata,
        );

        if (_isInstagramPostUrl(finalUrl) &&
            metadata.imageUrl?.isNotEmpty != true) {
          metadata = await _enrichInstagramMetadata(finalUrl, metadata);
        }

        if (_isTikTokVideoUrl(finalUrl) &&
            (_isInvalidTikTokTitle(metadata.title) ||
                !_hasUsableTikTokImage(metadata.imageUrl))) {
          metadata = await _enrichTikTokMetadata(finalUrl, metadata);
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

      if (isGoogleMapsOrSearchUrl(url)) {
        return UrlMetadata(
          title: placeNameFromSharedText(sharedText, url) ??
              placeNameFromGoogleUrl(url) ??
              'Luogo su Google Maps',
          description: _descriptionFromSharedText(sharedText, url),
          siteName: 'Google Maps',
        );
      }

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
  static Future<UrlMetadata> resolveImportMetadata(
    String url, {
    String? sharedText,
  }) async {
    var normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('http://') &&
        !normalizedUrl.startsWith('https://')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    final lookup =
        await GlobalPostLookupService.instance.lookupByUrl(normalizedUrl);
    if (lookup.found &&
        lookup.isUsableForImport &&
        !isGenericImportTitle(lookup.title)) {
      print(
          'DEBUG: Metadati da DB comune global_posts (riuso, saveCount: ${lookup.saveCount})');
      return _applySharedTextFallback(
        lookup.toUrlMetadata(fallbackUrl: normalizedUrl),
        normalizedUrl,
        sharedText,
      );
    }

    final scraped = await extractMetadata(
      normalizedUrl,
      sharedText: sharedText,
    );
    return _applySharedTextFallback(scraped, normalizedUrl, sharedText);
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
      if (processedUrl != null &&
          _isValidImageUrl(processedUrl) &&
          !_isGenericGoogleImage(processedUrl)) {
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
      if (obj.containsKey('image') || obj.containsKey('photo')) {
        dynamic imageData = obj['image'] ?? obj['photo'];
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
      imageUrl = imageUrl.replaceAll('&amp;', '&').trim();
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
    if (lowerUrl.contains('googleusercontent.com') ||
        lowerUrl.contains('ggpht.com') ||
        lowerUrl.contains('google.com/maps') ||
        lowerUrl.contains('encrypted-tbn') ||
        lowerUrl.contains('gstatic.com')) {
      return !_isGenericGoogleImage(lowerUrl);
    }

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
    if (isGoogleMapsOrSearchUrl(url)) {
      return UrlMetadata(
        title: placeNameFromGoogleUrl(url) ?? 'Luogo su Google Maps',
        description: url,
        siteName: 'Google Maps',
        extractedHashtags: [],
      );
    }

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

  static Future<UrlMetadata> _extractGooglePlaceMetadata(
    String url, {
    String? sharedText,
  }) async {
    final unfurled = await _unfurlGoogleShare(url);
    final resolved = unfurled.url;
    final html = unfurled.html;
    final name = placeNameFromSharedText(sharedText, resolved) ??
        placeNameFromGoogleUrl(resolved) ??
        placeNameFromGoogleUrl(url) ??
        (html == null ? null : _placeNameFromGoogleHtml(html));
    var imageUrl = html == null ? null : _imageFromGoogleHtml(html, resolved);
    imageUrl ??= await _fetchGooglePlacePhoto(
      resolvedUrl: resolved,
      placeName: name,
    );
    final description = _descriptionFromSharedText(sharedText, resolved);
    return UrlMetadata(
      title: name ??
          placeNameFromSharedText(sharedText, url) ??
          'Luogo su Google Maps',
      description: description,
      imageUrl: imageUrl,
      siteName: 'Google Maps',
    );
  }

  static String? _descriptionFromSharedText(String? sharedText, String url) {
    if (sharedText == null) return null;
    final text = sharedText.trim();
    if (text.isEmpty || text == url) return null;
    return text;
  }

  static Future<String?> _fetchGooglePlacePhoto({
    required String resolvedUrl,
    required String? placeName,
  }) async {
    final query = (placeName ?? placeNameFromGoogleUrl(resolvedUrl) ?? '')
        .trim();
    if (query.isEmpty || isGenericImportTitle(query)) {
      return null;
    }

    try {
      final tbmUrl =
          'https://www.google.com/search?tbm=map&hl=it&gl=it&q=${Uri.encodeComponent(query)}';
      final response = await http
          .get(Uri.parse(tbmUrl), headers: _browserHeaders)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final fromCard = _firstUsableGooglePlacePhoto(response.body);
        if (fromCard != null) return fromCard;
        final website = _websiteFromGoogleLocalCard(response.body);
        if (website != null) {
          final fromSite = await _fetchWebsitePreviewImage(website);
          if (fromSite != null) return fromSite;
        }
      }
    } catch (e) {
      print('DEBUG: Google place photo fetch failed: $e');
    }
    return null;
  }

  static String? _firstUsableGooglePlacePhoto(String text) {
    for (final candidate in _googlePhotoUrlsInText(text)) {
      if (_isUsableGooglePlacePhoto(candidate)) return candidate;
    }
    return null;
  }

  static Iterable<String> _googlePhotoUrlsInText(String text) {
    final decoded = text
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u003d', '=')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&');
    final matches = RegExp(
      r'https://(?:lh[0-9]\.)?(?:googleusercontent|ggpht)\.com/[^"\s\\<>]+',
      caseSensitive: false,
    ).allMatches(decoded);
    final seen = <String>{};
    final urls = <String>[];
    for (final match in matches) {
      var url = match.group(0)!;
      url = url.replaceAll(RegExp(r'[\\),;\]]+$'), '');
      if (url.endsWith('\\')) url = url.substring(0, url.length - 1);
      if (seen.add(url)) urls.add(url);
    }
    return urls;
  }

  static String? _websiteFromGoogleLocalCard(String text) {
    final decoded = text.replaceAll(r'\/', '/').replaceAll(r'\u003d', '=');
    final matches = RegExp(
      r'"(https://[^"]+)"\s*,\s*"[^"]+\.[^"]+"',
    ).allMatches(decoded);
    for (final match in matches) {
      final url = match.group(1)!;
      if (_isLikelyPlaceWebsite(url)) return url;
    }
    return null;
  }

  static bool _isLikelyPlaceWebsite(String url) {
    final lower = url.toLowerCase();
    if (!lower.startsWith('http')) return false;
    const blocked = [
      'gstatic.com',
      'googleapis.com',
      'google.com/maps',
      'google.com/local',
      'google.com/search',
      'google.com/url',
      'business.google.com',
      'support.google.com',
      'play.google.com',
      'consent.google',
      'accounts.google',
    ];
    return blocked.every((item) => !lower.contains(item));
  }

  static Future<String?> _fetchWebsitePreviewImage(String website) async {
    try {
      final response = await http
          .get(Uri.parse(website), headers: _browserHeaders)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final finalUrl = response.request?.url.toString() ?? website;
      final document = html_parser.parse(response.body);
      final image = _extractBestImage(document, finalUrl);
      if (image == null) return null;
      if (_isGenericGoogleImage(image) ||
          image.toLowerCase().contains('staticmap') ||
          image.toLowerCase().contains('aaaaaaaaaai')) {
        return null;
      }
      return image;
    } catch (e) {
      print('DEBUG: Place website image fetch failed: $e');
    }
    return null;
  }

  static bool _isUsableGooglePlacePhoto(String url) {
    final lower = url.toLowerCase();
    if (_isGenericGoogleImage(url)) return false;
    if (lower.contains('aaaaaaaaaai')) return false;
    if (lower.contains('/ogw/default')) return false;
    if (lower.contains('s44-') ||
        lower.contains('=s44') ||
        lower.contains('/s44')) {
      return false;
    }
    if (lower.contains('material/system') ||
        lower.contains('local/placeinfo') ||
        lower.contains('staticmap')) {
      return false;
    }
    return lower.contains('googleusercontent.com') ||
        lower.contains('ggpht.com') ||
        lower.contains('encrypted-tbn') ||
        lower.contains('/p/') ||
        lower.contains('gps-cs-s') ||
        lower.contains('sitesv') ||
        lower.contains('docsubipk');
  }

  /// Espande i link corti da cellulare (share.google / maps.app.goo.gl).
  ///
  /// Da telefono Google risponde spesso `intent://` (Android) o una pagina
  /// consenso: il client HTTP non li segue da solo, quindi i redirect si
  /// gestiscono hop-by-hop. Lo User-Agent desktop è solo per lo scraping,
  /// l'utente continua a condividere dal cellulare.
  static Future<String> resolveGoogleImportUrl(String url) async {
    final unfurled = await _unfurlGoogleShare(url);
    return unfurled.url;
  }

  static Future<({String url, String? html})> _unfurlGoogleShare(
    String url,
  ) async {
    var current = url.trim();
    if (current.isEmpty) return (url: url, html: null);
    String? lastHtml;
    final client = http.Client();
    try {
      for (var i = 0; i < 8; i++) {
        if (_hasNamedMapsPlace(current) && lastHtml != null) {
          return (url: current, html: lastHtml);
        }

        final request = http.Request('GET', Uri.parse(current))
          ..followRedirects = false
          ..headers.addAll(_browserHeaders);
        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 12));
        final status = streamed.statusCode;
        final location = streamed.headers['location'];

        if (status >= 300 &&
            status < 400 &&
            location != null &&
            location.isNotEmpty) {
          await streamed.stream.drain();
          final next = _resolveGoogleRedirect(current, location);
          if (next != null && next != current) {
            current = next;
            continue;
          }
          // Consent 302 unwraps to the same Maps URL. Cookie lets a
          // following GET return the real HTML instead of looping.
          if (location.toLowerCase().contains('consent.google')) {
            final followed = await client
                .get(Uri.parse(current), headers: _browserHeaders)
                .timeout(const Duration(seconds: 15));
            current = followed.request?.url.toString() ?? current;
            lastHtml = followed.body.length > 400000
                ? followed.body.substring(0, 400000)
                : followed.body;
            if (current.toLowerCase().contains('consent.google')) {
              current = _unwrapConsentContinue(current) ?? current;
            }
            if (_hasNamedMapsPlace(current) ||
                (lastHtml.isNotEmpty &&
                    _imageFromGoogleHtml(lastHtml, current) != null)) {
              return (url: current, html: lastHtml);
            }
          }
          break;
        }

        final body = await streamed.stream.bytesToString();
        lastHtml = body.length > 400000 ? body.substring(0, 400000) : body;

        if (_hasNamedMapsPlace(current)) {
          return (url: current, html: lastHtml);
        }

        final consentNext = _continueFromConsent(current, lastHtml);
        if (consentNext != null && consentNext != current) {
          current = consentNext;
          continue;
        }

        final namedFromHtml = _namedMapsUrlFromHtml(lastHtml);
        if (namedFromHtml != null && namedFromHtml != current) {
          current = namedFromHtml;
          if (_hasNamedMapsPlace(current)) {
            return (url: current, html: lastHtml);
          }
          continue;
        }

        final dest = _extractGoogleDestinationFromHtml(lastHtml);
        if (dest != null && dest != current) {
          current = dest;
          continue;
        }
        return (url: current, html: lastHtml);
      }
    } catch (e) {
      print('DEBUG: Google unfurl failed: $e');
    } finally {
      client.close();
    }
    return (url: current, html: lastHtml);
  }

  static bool _hasNamedMapsPlace(String url) {
    return url.toLowerCase().contains('/maps/place/') &&
        placeNameFromGoogleUrl(url) != null;
  }

  static String? _resolveGoogleRedirect(String current, String location) {
    var loc = location.trim();
    if (loc.toLowerCase().startsWith('intent:')) {
      loc = _parseAndroidIntentMapsUrl(loc) ?? '';
      if (loc.isEmpty) return null;
    }
    if (loc.startsWith('/')) {
      try {
        loc = Uri.parse(current).resolve(loc).toString();
      } catch (_) {
        return null;
      }
    }
    loc = _unwrapConsentContinue(loc) ?? loc;
    if (!loc.startsWith('http://') && !loc.startsWith('https://')) {
      return null;
    }
    return loc;
  }

  static String? _parseAndroidIntentMapsUrl(String location) {
    var current = location;
    for (var i = 0; i < 4; i++) {
      try {
        current = Uri.decodeComponent(current);
      } catch (_) {
        break;
      }
    }

    final fallback = RegExp(
      r'S\.browser_fallback_url=([^;]+)',
      caseSensitive: false,
    ).firstMatch(current);
    if (fallback != null) {
      var fallbackUrl = fallback.group(1)!;
      for (var i = 0; i < 3; i++) {
        try {
          fallbackUrl = Uri.decodeComponent(fallbackUrl);
        } catch (_) {
          break;
        }
      }
      final nested = RegExp(
        r'(?:^|[?&])url=(https?://[^&;]+)',
        caseSensitive: false,
      ).firstMatch(fallbackUrl);
      if (nested != null) {
        try {
          return Uri.decodeComponent(nested.group(1)!);
        } catch (_) {
          return nested.group(1);
        }
      }
      if (fallbackUrl.startsWith('http')) {
        return fallbackUrl.split(';').first;
      }
    }

    final maps = RegExp(
      r'https://(?:www\.)?google\.[a-z.]+/maps/[^\s;]+',
      caseSensitive: false,
    ).firstMatch(current);
    if (maps == null) return null;
    return maps.group(0)!.replaceAll(RegExp(r'[;]+$'), '');
  }

  static String? _unwrapConsentContinue(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.host.toLowerCase().contains('consent.google')) return url;
      final cont = uri.queryParameters['continue'];
      if (cont != null &&
          (cont.startsWith('http://') || cont.startsWith('https://'))) {
        return cont;
      }
    } catch (_) {}
    return url;
  }

  static String? _continueFromConsent(String url, String html) {
    final fromUrl = _unwrapConsentContinue(url);
    if (fromUrl != null && fromUrl != url) return fromUrl;
    if (!url.toLowerCase().contains('consent.google')) return null;
    final match = RegExp(
      'continue=(https?[^&"\']+)',
      caseSensitive: false,
    ).firstMatch(html.replaceAll('&amp;', '&'));
    if (match == null) return null;
    try {
      return Uri.decodeComponent(match.group(1)!);
    } catch (_) {
      return match.group(1);
    }
  }

  static String? _namedMapsUrlFromHtml(String html) {
    final decoded = html.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
    final match = RegExp(
      r'https://(?:www\.)?google\.[a-z.]+/maps/place/[^/@?&"\s<>\\]+',
      caseSensitive: false,
    ).firstMatch(decoded);
    if (match == null) return null;
    final found = match.group(0)!.replaceAll(RegExp(r'[.,);]+$'), '');
    if (_hasNamedMapsPlace(found)) return found;
    return null;
  }

  static String? _placeNameFromGoogleHtml(String html) {
    final decoded = html.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
    final patterns = [
      RegExp('/maps/place/([^/@?&"\']+)'),
      RegExp('/maps/preview/place\\?[^"\']*[?&]q=([^&"\']+)'),
      RegExp('[?&]q=([^&"\']+)'),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(decoded)) {
        final name = _decodePlaceName(match.group(1)!);
        if (name != null) return name;
      }
    }
    return null;
  }

  static String? _imageFromGoogleHtml(String html, String baseUrl) {
    final photo = _firstUsableGooglePlacePhoto(html);
    if (photo == null) return null;
    return _makeAbsoluteUrl(photo, baseUrl) ?? photo;
  }

  static String? _extractGoogleDestinationFromHtml(String html) {
    final decoded = html.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
    final patterns = [
      RegExp(
        r'https://(?:www\.)?google\.[a-z.]+/maps/place/[^"\s<>\\]+',
        caseSensitive: false,
      ),
      RegExp(
        r'https://maps\.google\.[a-z.]+/maps/place/[^"\s<>\\]+',
        caseSensitive: false,
      ),
      RegExp(
        r'https://(?:www\.)?google\.[a-z.]+/maps/search/\?[^"\s<>\\]+',
        caseSensitive: false,
      ),
      RegExp(
        r'https://(?:www\.)?google\.[a-z.]+/search\?[^"\s<>\\]*q=[^"\s<>\\]+',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(decoded);
      if (match == null) continue;
      var found = match.group(0)!;
      found = found.replaceAll(RegExp(r'[.,);]+$'), '');
      try {
        found = Uri.decodeFull(found);
      } catch (_) {}
      return found;
    }
    return null;
  }

  static bool isGoogleMapsOrSearchUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('share.google') ||
        lower.contains('maps.app.goo.gl') ||
        lower.contains('goo.gl/maps') ||
        lower.contains('maps.google.') ||
        lower.contains('google.com/maps') ||
        lower.contains('google.it/maps') ||
        lower.contains('google.com/search') ||
        lower.contains('google.it/search') ||
        lower.contains('google.com/url') ||
        lower.contains('google.it/url');
  }

  static bool isGenericImportTitle(String? title) {
    if (title == null) return true;
    final value = title.trim().toLowerCase();
    if (value.isEmpty) return true;
    const generic = {
      'google',
      'google search',
      'google maps',
      'google maps - ricerca',
      'ricerca google',
      'search',
      'maps',
      'google.com',
      'google.it',
      'www.google.com',
      'www.google.it',
      'share.google',
      'share.google.com',
      'maps.app.goo.gl',
      'goo.gl',
      'post salvato',
      'luogo su google maps',
    };
    if (generic.contains(value)) return true;
    if (value.startsWith('google search')) return true;
    if (value.contains('share.google')) return true;
    if (value.contains('maps.app.goo.gl')) return true;
    return false;
  }

  static String? _cleanGoogleTitle(String? title) {
    if (title == null) return null;
    var value = title.trim();
    if (value.isEmpty) return null;
    value = value.replaceAll(
      RegExp(r'\s*[-|–]\s*Google Maps$', caseSensitive: false),
      '',
    );
    value = value.replaceAll(
      RegExp(r'\s*[-|–]\s*Google Search$', caseSensitive: false),
      '',
    );
    value = value.replaceAll(
      RegExp(r'\s*[-|–]\s*Ricerca Google$', caseSensitive: false),
      '',
    );
    value = value.replaceAll(
      RegExp(r'\s*[-|–]\s*Google$', caseSensitive: false),
      '',
    );
    value = value.trim();
    if (isGenericImportTitle(value)) return null;
    return value;
  }

  static String? placeNameFromGoogleUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final placeMatch = RegExp(r'/maps/place/([^/@]+)').firstMatch(uri.path);
      if (placeMatch != null) {
        final name = _decodePlaceName(placeMatch.group(1)!);
        if (name != null) return name;
      }
      final query = uri.queryParameters['q'] ??
          uri.queryParameters['query'] ??
          uri.queryParameters['destination'];
      if (query != null &&
          query.trim().isNotEmpty &&
          !query.startsWith('http') &&
          !RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+').hasMatch(query.trim())) {
        return _decodePlaceName(query);
      }
    } catch (_) {}
    return null;
  }

  static String? _decodePlaceName(String raw) {
    var name = raw.replaceAll('+', ' ');
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {}
    name = name.split(RegExp(r'\s*[|·•]\s*')).first.trim();
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.toLowerCase().startsWith('data=')) return null;
    if (name.startsWith('@')) return null;
    if (RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+').hasMatch(name)) return null;
    if (name.length < 2 || isGenericImportTitle(name)) return null;
    return name;
  }

  static String? placeNameFromSharedText(String? text, String url) {
    if (text == null) return null;
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    for (final line in lines) {
      var candidate =
          line.replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '').trim();
      candidate = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
      final lower = candidate.toLowerCase();
      if (candidate.isEmpty) continue;
      if (lower.contains('maps.app.goo.gl') || lower.contains('share.google')) {
        continue;
      }
      if (RegExp(r'^[★☆⭐\s·.•\d.,/]+$').hasMatch(candidate)) continue;
      if (RegExp(r'^\d+(\.\d+)?\s*(stars?|stelle)', caseSensitive: false)
          .hasMatch(candidate)) {
        continue;
      }
      if (lower.contains('google maps') && candidate.length < 48) continue;
      final name = candidate.split(' · ').first.trim();
      if (name.length >= 2 &&
          name.length <= 120 &&
          !isGenericImportTitle(name)) {
        return name;
      }
    }
    return placeNameFromGoogleUrl(url);
  }

  static UrlMetadata _applySharedTextFallback(
    UrlMetadata metadata,
    String url,
    String? sharedText,
  ) {
    final fromShare = placeNameFromSharedText(sharedText, url);
    final title = fromShare ??
        _cleanGoogleTitle(metadata.title) ??
        placeNameFromGoogleUrl(url);
    var description = metadata.description?.trim();
    if (description != null &&
        (isGenericImportTitle(description) ||
            description.toLowerCase().contains('cerca su google') ||
            description.toLowerCase().contains('search the world') ||
            description.toLowerCase().contains('google search'))) {
      description = null;
    }
    if ((description == null || description.isEmpty) &&
        sharedText != null &&
        sharedText.trim().isNotEmpty &&
        sharedText.trim() != url) {
      description = sharedText.trim();
    }
    return metadata.copyWith(
      title: title ?? metadata.title,
      description: description ?? metadata.description,
    );
  }

  static UrlMetadata _enrichGooglePlaceMetadata({
    required String originalUrl,
    required String finalUrl,
    required Document document,
    required UrlMetadata metadata,
  }) {
    if (!isGoogleMapsOrSearchUrl(originalUrl) &&
        !isGoogleMapsOrSearchUrl(finalUrl) &&
        !isGenericImportTitle(metadata.title)) {
      return metadata;
    }

    final jsonLdName = _extractJsonLdPlaceName(document);
    final canonicalHref = document
        .querySelector('link[rel="canonical"]')
        ?.attributes['href']
        ?.trim();
    final title = _cleanGoogleTitle(metadata.title) ??
        jsonLdName ??
        placeNameFromGoogleUrl(finalUrl) ??
        placeNameFromGoogleUrl(originalUrl) ??
        (canonicalHref == null ? null : placeNameFromGoogleUrl(canonicalHref));

    var imageUrl = metadata.imageUrl;
    if (imageUrl != null && _isGenericGoogleImage(imageUrl)) {
      imageUrl = null;
    }
    if (imageUrl == null || imageUrl.isEmpty) {
      final jsonLdImages = _extractJsonLdImages(document);
      for (final candidate in jsonLdImages) {
        final absolute = _makeAbsoluteUrl(candidate, finalUrl);
        if (absolute != null &&
            _isValidImageUrl(absolute) &&
            !_isGenericGoogleImage(absolute)) {
          imageUrl = absolute;
          break;
        }
      }
    }

    return metadata.copyWith(
      title: title ?? metadata.title,
      imageUrl: imageUrl ?? metadata.imageUrl,
      siteName: 'Google Maps',
    );
  }

  static String? _extractJsonLdPlaceName(Document document) {
    final jsonLdElements = document.querySelectorAll(
      'script[type="application/ld+json"]',
    );
    for (final element in jsonLdElements) {
      try {
        final jsonData = json.decode(element.text);
        final name = _findPlaceNameInJson(jsonData);
        if (name != null) return name;
      } catch (_) {}
    }
    return null;
  }

  static String? _findPlaceNameInJson(dynamic obj) {
    if (obj is Map) {
      final type = obj['@type']?.toString().toLowerCase() ?? '';
      const placeHints = [
        'restaurant',
        'localbusiness',
        'foodestablishment',
        'place',
        'cafe',
        'barorpub',
        'lodgingbusiness',
        'touristattraction',
      ];
      final looksLikePlace = placeHints.any(type.contains) ||
          obj.containsKey('address') ||
          obj.containsKey('geo') ||
          obj.containsKey('servescuisine');
      final name = obj['name']?.toString().trim();
      if (looksLikePlace &&
          name != null &&
          name.isNotEmpty &&
          !isGenericImportTitle(name)) {
        return name;
      }
      for (final value in obj.values) {
        if (value is Map || value is List) {
          final nested = _findPlaceNameInJson(value);
          if (nested != null) return nested;
        }
      }
    } else if (obj is List) {
      for (final item in obj) {
        final nested = _findPlaceNameInJson(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static bool _isGenericGoogleImage(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/images/branding') ||
        lower.contains('googlelogo') ||
        lower.contains('maps.gstatic.com/mapfiles') ||
        lower.contains('maps/about/images') ||
        lower.contains('maps_512dp') ||
        lower.contains('staticmap') ||
        lower.contains('favicon') ||
        lower.contains('google.com/images/branding');
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
