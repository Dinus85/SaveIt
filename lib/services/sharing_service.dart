import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:receive_intent/receive_intent.dart' as receive_intent;
import '../models.dart';
import '../data_service.dart';
import '../url_metadata_service.dart';
import '../models/folder.dart';
import 'access_control_service.dart';
import 'folder_service.dart';
import 'interstitial_ad_service.dart';
import '../widgets/folder_card_selector.dart';
import '../pages/folder_detail_page.dart'; // NUOVO: Import per navigazione

class SharedContent {
  final String url;
  final String text;
  final String? platform;
  final List<String>
      extractedHashtags; // NUOVO: Hashtag estratti dal testo condiviso

  SharedContent({
    required this.url,
    required this.text,
    this.platform,
    this.extractedHashtags = const [], // NUOVO: Default lista vuota
  });
}

class SharingService {
  static SharingService? _instance;
  static SharingService get instance {
    _instance ??= SharingService._();
    return _instance!;
  }

  SharingService._();

  StreamSubscription? _intentDataStreamSubscription;
  Function(SharedContent)? _onSharedContent;

  static Function()? _onDataChanged;

  // NUOVO: Callback DataService per aggiornamento ottimistico
  DataChangeCallback? _dataServiceCallback;
  bool _isDataServiceCallbackRegistered = false;

  static void setOnDataChangedCallback(Function()? callback) {
    _onDataChanged = callback;
  }

  // CORRETTO: Initialize sharing intent listener
  void initialize({Function(SharedContent)? onSharedContent}) {
    _onSharedContent = onSharedContent;

    print('DEBUG: Inizializzando SharingService con receive_intent...');

    // NUOVO: Registra callback con DataService per sincronizzazione automatica
    _setupDataServiceCallback();

    // Listen for intents while app is running
    _intentDataStreamSubscription =
        receive_intent.ReceiveIntent.receivedIntentStream.listen(
      (receive_intent.Intent? intent) {
        if (intent != null) {
          print('DEBUG: Ricevuto intent: ${intent.action}');
          _handleReceivedIntent(intent);
        }
      },
      onError: (err) {
        print("ERRORE: Errore durante la ricezione dell'intent: $err");
      },
    );

    // Check for initial intent (when app was closed and opened by sharing)
    receive_intent.ReceiveIntent.getInitialIntent()
        .then((receive_intent.Intent? intent) {
      if (intent != null) {
        print('DEBUG: Ricevuto intent iniziale: ${intent.action}');
        _handleReceivedIntent(intent);
      } else {
        print('DEBUG: Nessun intent iniziale');
      }
    });

    print('DEBUG: SharingService inizializzato con receive_intent');
  }

  // NUOVO: Configura callback DataService per ricevere notifiche di salvataggio
  void _setupDataServiceCallback() {
    if (_isDataServiceCallbackRegistered) {
      print('DEBUG: Callback DataService giÃƒ  registrato, saltando...');
      return;
    }

    print(
        'DEBUG: ========== SETUP CALLBACK DATASERVICE IN SHARINGSERVICE ==========');

    _dataServiceCallback =
        (String changeType, Map<String, dynamic> changeData) {
      print('DEBUG: SharingService ricevuto: $changeType');

      // Gestisci specificamente le notifiche di salvataggio post
      switch (changeType) {
        case 'post_added':
          _handlePostSavedSuccessfully(changeData);
          break;
        case 'folder_added':
          _handleFolderCreatedBySharing(changeData);
          break;
        case 'cache_invalidated':
        case 'cache_reloaded':
          _handleCacheRefresh(changeData);
          break;
        default:
          // Altri tipi di notifica non ci interessano in SharingService
          break;
      }
    };

    // Registra callback con DataService
    try {
      DataService.instance.registerDataChangeCallback(_dataServiceCallback!);
      _isDataServiceCallbackRegistered = true;
      print('DEBUG: SharingService callback registrato con DataService');
    } catch (e) {
      print('DEBUG: Errore registrazione callback SharingService: $e');
    }
  }

  // NUOVO: Gestisce salvataggio post completato con successo (aggiornamento ottimistico)
  void _handlePostSavedSuccessfully(Map<String, dynamic> data) {
    print('DEBUG: Post salvato con successo tramite sharing');
    print('DEBUG: Titolo: ${data['postTitle']}, Cartella: ${data['folderId']}');

    // Notifica l'UI principale che i dati sono cambiati per aggiornamento ottimistico
    if (_onDataChanged != null) {
      print('DEBUG: Notificando UI principale di aggiornamento ottimistico...');
      _onDataChanged!();
    }
  }

  // NUOVO: Gestisce creazione cartella durante processo di sharing
  void _handleFolderCreatedBySharing(Map<String, dynamic> data) {
    print('DEBUG: Cartella creata durante sharing: ${data['folderName']}');

    // Notifica UI per mostrare la nuova cartella immediatamente
    if (_onDataChanged != null) {
      print('DEBUG: Notificando creazione cartella per aggiornamento UI...');
      _onDataChanged!();
    }
  }

  // NUOVO: Gestisce refresh cache per mantenere UI sincronizzata
  void _handleCacheRefresh(Map<String, dynamic> data) {
    print('DEBUG: Cache refreshed, sincronizzando UI...');

    if (_onDataChanged != null) {
      _onDataChanged!();
    }
  }

  void _handleReceivedIntent(receive_intent.Intent intent) {
    if (intent.action == 'android.intent.action.SEND') {
      String? sharedText;

      if (intent.extra?['android.intent.extra.TEXT'] != null) {
        sharedText = intent.extra!['android.intent.extra.TEXT'].toString();
      }

      if (sharedText != null && sharedText.isNotEmpty) {
        _handleSharedText(sharedText);
      }
    } else if (intent.action == 'android.intent.action.VIEW') {
      if (intent.data != null) {
        _handleSharedText(intent.data!);
      }
    }
  }

  // COMPLETAMENTE RISCRITTO: Gestione con estrazione automatica hashtag
  void _handleSharedText(String text) {
    print('DEBUG: ========== ANALISI TESTO CONDIVISO CON HASHTAG ==========');
    print('DEBUG: Testo ricevuto: $text');

    // STEP 1: Estrai hashtag dal testo condiviso PRIMA di processare gli URL
    final extractedHashtags = _extractHashtagsFromSharedText(text);
    print(
        'DEBUG: Hashtag estratti dal testo: ${extractedHashtags.length} trovati');
    if (extractedHashtags.isNotEmpty) {
      print('DEBUG: Hashtag: ${extractedHashtags.join(", ")}');
    }

    final urls = _extractUrlsFromText(text);
    print('DEBUG: URL estratti: $urls');

    if (urls.isNotEmpty) {
      // NUOVO: Seleziona il miglior URL filtrando quelli di condivisione
      final url = _selectBestUrl(urls);
      print('DEBUG: URL selezionato: $url');
      print('DEBUG: URL scartati: ${urls.where((u) => u != url).toList()}');

      final sharedContent = SharedContent(
        url: url,
        text: text,
        platform: UrlMetadataService.getSocialPlatform(url),
        extractedHashtags: extractedHashtags, // NUOVO: Include hashtag estratti
      );

      _onSharedContent?.call(sharedContent);
    } else {
      if (_isValidUrl(text)) {
        // NUOVO: Anche per URL singoli, estrai hashtag se presenti
        final sharedContent = SharedContent(
          url: text,
          text: text,
          platform: UrlMetadataService.getSocialPlatform(text),
          extractedHashtags:
              extractedHashtags, // NUOVO: Include hashtag estratti
        );
        _onSharedContent?.call(sharedContent);
      }
    }
  }

  // NUOVO: Estrai SOLO hashtag con simbolo # dal testo condiviso
  List<String> _extractHashtagsFromSharedText(String text) {
    print(
        'DEBUG: Iniziando estrazione SOLO hashtag con # dal testo condiviso...');

    if (text.isEmpty) return [];

    Set<String> hashtags = {};

    // Pattern RIGOROSO per hashtag con simbolo #
    final hashtagRegex = RegExp(
        r'#([a-zA-Z][a-zA-Z0-9_]{0,}(?:[a-zA-Z0-9]|[a-zA-Z]))',
        multiLine: true);
    final matches = hashtagRegex.allMatches(text);

    for (var match in matches) {
      final hashtag = match.group(1);
      if (hashtag != null && hashtag.length > 1 && hashtag.length <= 30) {
        final cleanTag = _cleanHashtag(hashtag);
        if (cleanTag.isNotEmpty) {
          hashtags.add(cleanTag);
          print('DEBUG: Hashtag trovato: #$cleanTag');
        }
      }
    }

    final result = hashtags.toList()..sort();
    print(
        'DEBUG: Estrazione completata - ${result.length} hashtag con # dal testo condiviso');
    return result;
  }

  // NUOVO: Estrai hashtag specifici per piattaforma quando non ci sono # espliciti
  List<String> _extractPlatformSpecificHashtags(String text) {
    Set<String> hashtags = {};

    // Pattern per Instagram (quando condiviso da Instagram)
    if (text.contains('instagram.com')) {
      // Cerca pattern come "Follow @username for #hashtag content"
      final instagramPattern =
          RegExp(r'\b([a-zA-Z][a-zA-Z0-9_]{2,19})\b', multiLine: true);
      final matches = instagramPattern.allMatches(text.toLowerCase());

      for (var match in matches) {
        final potential = match.group(1);
        if (potential != null &&
            potential.length > 3 &&
            potential.length <= 20 &&
            !_isCommonWord(potential) &&
            _isLikelyHashtag(potential)) {
          hashtags.add(potential);
          print('DEBUG: Hashtag Instagram inferito: $potential');
          if (hashtags.length >= 3) break; // Massimo 3 per evitare noise
        }
      }
    }

    // Pattern per Twitter/X (quando condiviso da Twitter)
    if (text.contains('twitter.com') || text.contains('x.com')) {
      // Twitter spesso include hashtag anche senza #, cercare pattern comuni
      final twitterKeywords = [
        'tech',
        'ai',
        'flutter',
        'dart',
        'mobile',
        'dev',
        'coding',
        'app',
        'news'
      ];
      for (String keyword in twitterKeywords) {
        if (text.toLowerCase().contains(keyword.toLowerCase()) &&
            keyword.length > 2) {
          hashtags.add(keyword);
          print('DEBUG: Hashtag Twitter inferito: $keyword');
        }
      }
    }

    return hashtags.toList();
  }

  // NUOVO: Verifica se una parola ha caratteristiche di hashtag
  bool _isLikelyHashtag(String word) {
    // Evita URL, email, e parole troppo comuni
    if (word.contains('.') || word.contains('@') || word.contains('/')) {
      return false;
    }

    // Preferisci parole che sembrano termini tecnici o specifici
    final techWords = [
      'tech',
      'app',
      'mobile',
      'web',
      'dev',
      'code',
      'ai',
      'ml',
      'ux',
      'ui'
    ];
    final categoryWords = [
      'food',
      'travel',
      'fitness',
      'music',
      'art',
      'photo',
      'fashion',
      'lifestyle'
    ];

    return techWords.any((tech) => word.toLowerCase().contains(tech)) ||
        categoryWords.any((cat) => word.toLowerCase().contains(cat)) ||
        word.length >=
            5; // Parole piÃƒÂ¹ lunghe hanno piÃƒÂ¹ probabilitÃƒ  di essere specifiche
  }

  // NUOVO: Metodo per selezionare il miglior URL evitando servizi di condivisione
  String _selectBestUrl(List<String> urls) {
    print('DEBUG: ========== SELEZIONE MIGLIOR URL ==========');
    print('DEBUG: URL trovati nel testo: ${urls.length}');

    // Lista completa di domini di condivisione da evitare
    final shareServiceDomains = [
      'share.google.com',
      't.co',
      'bit.ly',
      'tinyurl.com',
      'short.link',
      'ow.ly',
      'fb.me',
      'goo.gl',
      'tiny.cc',
      'is.gd',
      'buff.ly',
      'smarturl.it',
      'linktr.ee',
    ];

    // STRATEGIA 1: Cerca URL diretti (non di condivisione)
    for (String url in urls) {
      try {
        final domain = UrlMetadataService.getDomainFromUrl(url).toLowerCase();
        final isShareService = shareServiceDomains
            .any((shareDomain) => domain.contains(shareDomain));

        print('DEBUG: Analizzando URL: $url');
        print('DEBUG: Dominio: $domain');
        print('DEBUG: ÃƒË† servizio condivisione: $isShareService');

        if (!isShareService) {
          print('DEBUG: ✓ URL diretto selezionato: $url');
          return url;
        }
      } catch (e) {
        print('DEBUG: Errore analisi URL $url: $e');
        continue;
      }
    }

    // STRATEGIA 2: Se tutti sono URL di condivisione, prova a estrarre l'URL reale dai parametri
    print(
        'DEBUG: Tutti gli URL sono servizi di condivisione, cercando URL originale nei parametri...');

    for (String url in urls) {
      try {
        final uri = Uri.parse(url);

        // Per Google Share, cerca il parametro 'url'
        if (url.contains('share.google')) {
          print('DEBUG: Trovato link Google Share: $url');

          // Prova vari parametri comuni
          final possibleParams = ['url', 'u', 'link', 'target'];
          for (var param in possibleParams) {
            if (uri.queryParameters.containsKey(param)) {
              final extractedUrl = uri.queryParameters[param];
              if (extractedUrl != null &&
                  extractedUrl.isNotEmpty &&
                  extractedUrl.startsWith('http')) {
                print(
                    'DEBUG: ✓ URL estratto dal parametro "$param": $extractedUrl');
                return extractedUrl;
              }
            }
          }

          // Prova a decodificare l'intero path/query per trovare URL nascosti
          final fullUrl = url.toString();
          final urlPattern =
              RegExp(r'https?%3A%2F%2F[^&\s]+', caseSensitive: false);
          final match = urlPattern.firstMatch(fullUrl);
          if (match != null) {
            final encodedUrl = match.group(0)!;
            final decodedUrl = Uri.decodeComponent(encodedUrl);
            print('DEBUG: ✓ URL decodificato trovato: $decodedUrl');
            return decodedUrl;
          }
        }

        // Per altri servizi di shortening, cerca parametri comuni
        if (uri.queryParameters.isNotEmpty) {
          final possibleParams = ['url', 'u', 'link', 'to', 'target', 'dest'];
          for (var param in possibleParams) {
            if (uri.queryParameters.containsKey(param)) {
              final extractedUrl = uri.queryParameters[param];
              if (extractedUrl != null &&
                  extractedUrl.isNotEmpty &&
                  extractedUrl.startsWith('http')) {
                print(
                    'DEBUG: ✓ URL estratto dal parametro "$param": $extractedUrl');
                return extractedUrl;
              }
            }
          }
        }
      } catch (e) {
        print('DEBUG: Errore estrazione parametri da $url: $e');
      }
    }

    // STRATEGIA 3: Se non è stato trovato niente, prendi il piÃƒÂ¹ lungo
    print('DEBUG: Nessun URL estratto, selezionando il piÃƒÂ¹ lungo...');

    String longestUrl = urls.first;
    for (String url in urls) {
      if (url.length > longestUrl.length) {
        longestUrl = url;
      }
    }

    print(
        'DEBUG: ⚠ URL piÃƒÂ¹ lungo selezionato (potrebbe essere ancora un link di condivisione): $longestUrl');
    return longestUrl;
  }

  List<String> _extractUrlsFromText(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"]+|www\.[^\s<>"]+',
      caseSensitive: false,
    );

    final matches =
        urlRegex.allMatches(text).map((match) => match.group(0)!).toList();
    return matches;
  }

  bool _isValidUrl(String text) {
    try {
      final uri = Uri.parse(text);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  // NUOVO: Metodo simulateSharedContent richiesto da main.dart
  void simulateSharedContent(String url, String text) {
    print('DEBUG: Simulando contenuto condiviso - URL: $url, Testo: $text');

    // NUOVO: Estrai hashtag anche per contenuto simulato
    final extractedHashtags = _extractHashtagsFromSharedText(text);

    final sharedContent = SharedContent(
      url: url,
      text: text,
      platform: UrlMetadataService.getSocialPlatform(url),
      extractedHashtags: extractedHashtags, // NUOVO: Include hashtag estratti
    );

    print('DEBUG: Chiamando callback condivisione simulato...');
    _onSharedContent?.call(sharedContent);
  }

  // Ã°Å¸Å¡â‚¬ MODIFICATO: Show dialog VELOCE con hashtag automatici E NAVIGAZIONE AUTOMATICA
  static Future<Map<String, String>?> showSaveDialog(
    BuildContext context,
    SharedContent sharedContent, {
    bool isDarkTheme = true,
  }) async {
    print(
        'DEBUG: ========== APERTURA DIALOG CON NAVIGAZIONE AUTOMATICA ==========');
    print('DEBUG: URL: ${sharedContent.url}');
    print(
        'DEBUG: Hashtag dal testo: ${sharedContent.extractedHashtags.length}');

    // STEP 1: Inizializza FolderService se necessario (non blocking)
    final folderService = FolderService();

    // Inizializza in background se non giÃƒ  fatto
    if (!folderService.folders.any((f) => !f.isSpecial)) {
      print('DEBUG: FolderService non inizializzato, inizializzando...');
      folderService.initializeFolders().catchError((e) {
        print('ERRORE: Inizializzazione FolderService fallita: $e');
      });
    }

    // STEP 2: Carica metadata in background (non blocking) - ORA INCLUDE HASHTAG
    Future<UrlMetadata> metadataFuture =
        UrlMetadataService.extractMetadata(sharedContent.url);

    // STEP 3: Mostra dialog IMMEDIATAMENTE con dati di base
    return showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false, // Evita chiusura accidentale
      builder: (BuildContext dialogContext) => FutureBuilder<UrlMetadata>(
        future: metadataFuture,
        builder: (context, snapshot) {
          // Usa metadata placeholder mentre carica
          final metadata = snapshot.data ??
              UrlMetadata(
                title: UrlMetadataService.getDomainFromUrl(sharedContent.url),
                description: 'Caricamento informazioni...',
                imageUrl: null,
                extractedHashtags: [], // Lista vuota durante il loading
              );

          // NUOVO: Combina hashtag da testo condiviso e metadati web
          final combinedHashtags = UrlMetadataService.combineHashtags([
            sharedContent.extractedHashtags, // Da testo condiviso
            metadata.extractedHashtags, // Da metadati web
          ]);

          print('DEBUG: Hashtag combinati: ${combinedHashtags.length}');
          if (combinedHashtags.isNotEmpty) {
            print('DEBUG: Lista finale: ${combinedHashtags.join(", ")}');
          }

          return SaveSharedContentDialog(
            sharedContent: sharedContent,
            metadata: metadata,
            isDarkTheme: isDarkTheme,
            isLoadingMetadata: !snapshot.hasData,
            prefilledHashtags:
                combinedHashtags, // NUOVO: Passa hashtag pre-compilati
          );
        },
      ),
    );
  }

  // Ã°Å¸Å¡â‚¬ NUOVO: Metodo per navigazione automatica alla cartella
  static void _navigateToSavedPostFolder(
      BuildContext context, String folderPath, String postId) async {
    try {
      // Verifica che il context sia ancora valido
      if (!context.mounted) {
        print('DEBUG: Context non piÃƒÂ¹ valido, saltando navigazione');
        return;
      }

      print('DEBUG: Navigando alla cartella: $folderPath');

      final folderService = FolderService();
      await folderService.syncWithDataService();

      MockFolder? targetFolder;

      if (folderPath == 'Tutti' || folderPath.isEmpty) {
        targetFolder = folderService.folders.firstWhere((f) => f.isSpecial,
            orElse: () => folderService.folders.first);
      } else {
        targetFolder = folderService.findFolderByPath(folderPath);
      }

      if (targetFolder != null && context.mounted) {
        // Naviga alla cartella specifica
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => FolderDetailPage(
              folder: targetFolder!,
              isDarkTheme: true,
              allFolders: folderService.folders,
              onFolderUpdated: () {},
              onThemeChanged: (isDark) {},
            ),
          ),
        );

        print(
            'DEBUG: Navigazione completata alla cartella: ${targetFolder.name}');

        // SOLO se context ÃƒÂ¨ ancora valido
        if (context.mounted) {}
      } else {
        print('ERRORE: Cartella non trovata: $folderPath');
      }
    } catch (e) {
      print('ERRORE: Navigazione fallita: $e');
      // Non tentare di mostrare SnackBar se context ÃƒÂ¨ deactivated
    }
  }

  static Future<void> openPostDirectly(BuildContext context, String url) async {
    try {
      final Uri uri = Uri.parse(url);

      print('DEBUG: Tentativo apertura URL: $url');

      // ✅ Prova direttamente ad aprire - Android gestirà l'app corretta
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );

      print('DEBUG: URL aperto con successo');

      if (context.mounted) {}
    } catch (e) {
      print('ERRORE: Apertura URL fallita: $e');

      if (context.mounted) {}
    }
  }

  // NUOVO: Funzioni helper per pulizia hashtag (condivise con UrlMetadataService)
  String _cleanHashtag(String hashtag) {
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

  // NUOVO: Verifica se ÃƒÂ¨ una parola comune da evitare come hashtag
  bool _isCommonWord(String word) {
    final commonWords = {
      // Parole comuni inglesi
      'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'can', 'her',
      'was', 'one', 'our', 'had',
      'will', 'there', 'what', 'your', 'when', 'him', 'my', 'has', 'how', 'did',
      'get', 'may', 'been',
      'this', 'that', 'with', 'have', 'from', 'they', 'know', 'want', 'been',
      'good', 'much', 'some',
      'time', 'very', 'when', 'come', 'here', 'just', 'like', 'long', 'make',
      'many', 'over', 'such',
      'take', 'than', 'them', 'well', 'were', 'work',

      // Parole comuni italiane
      'che', 'con', 'del', 'della', 'delle', 'una', 'alla', 'nel', 'nella',
      'per', 'anche', 'come',
      'dopo', 'senza', 'sono', 'stato', 'essere', 'avere', 'fare', 'dire',
      'andare', 'vedere', 'sapere',
      'dare', 'volere', 'venire', 'dovere', 'potere', 'prima', 'ancora', 'oggi',
      'sempre', 'molto',
      'bene', 'dove', 'quando', 'perchÃƒÂ©', 'mentre', 'perÃƒÂ²', 'quindi',
      'invece',

      // Parole generiche web
      'click', 'here', 'more', 'read', 'about', 'page', 'site', 'website',
      'home', 'news', 'blog',
      'post', 'article', 'content', 'info', 'link', 'visit', 'follow', 'share',
      'like', 'comment',
    };

    return commonWords.contains(word.toLowerCase());
  }

  // NUOVO: Cleanup con rimozione callback DataService
  void dispose() {
    print('DEBUG: ========== DISPOSE SHARINGSERVICE ==========');

    _intentDataStreamSubscription?.cancel();

    // NUOVO: Rimuovi callback DataService durante dispose
    if (_isDataServiceCallbackRegistered && _dataServiceCallback != null) {
      try {
        DataService.instance
            .unregisterDataChangeCallback(_dataServiceCallback!);
        _isDataServiceCallbackRegistered = false;
        print('DEBUG: Callback DataService rimosso da SharingService');
      } catch (e) {
        print('DEBUG: Errore rimozione callback DataService: $e');
      }
    }

    print('DEBUG: SharingService dispose completato');
  }
}

class SaveSharedContentDialog extends StatefulWidget {
  final SharedContent sharedContent;
  final UrlMetadata metadata;
  final bool isDarkTheme;
  final bool isLoadingMetadata;
  final List<String> prefilledHashtags;
  // RIMUOVI questa riga:
  // final Function(String folderPath, String postId)? onSaveComplete;

  const SaveSharedContentDialog({
    Key? key,
    required this.sharedContent,
    required this.metadata,
    this.isDarkTheme = true,
    this.isLoadingMetadata = false,
    this.prefilledHashtags = const [],
  }) : super(key: key);

  @override
  _SaveSharedContentDialogState createState() =>
      _SaveSharedContentDialogState();
}

class _SaveSharedContentDialogState extends State<SaveSharedContentDialog> {
  final AppAccessService _accessService = AppAccessService();
  final InterstitialAdService _adService = InterstitialAdService.instance;
  late TextEditingController _titleController;
  late TextEditingController
      _tagInputController; // NUOVO: Controller per input singolo tag

  String? _selectedFolderPath = '';
  bool _isLoading = false;
  bool _hasInitializedTitle = false;

  Map<String, dynamic>? _folderData;
  bool _isFolderDataLoaded = false;

  List<Map<String, dynamic>> _temporaryFolders = [];
  List<String> _foldersToCreate = [];

  Map<String, String> _selectorTemporaryFolders = {};

  // NUOVO: Lista per gestire i tag come chips
  List<String> _currentTags = [];

  bool get _canManageManualTags => _accessService.canManageManualTags;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController();
    _tagInputController =
        TextEditingController(); // NUOVO: Inizializza controller tag

    // NUOVO: Pre-popola con hashtag estratti automaticamente
    _initializePrefilledTags();

    // Inizializza il titolo se giÃƒ  disponibile
    _updateTitleIfNeeded();

    // MODIFICATO: Carica dati con sincronizzazione forzata
    _loadFolderDataWithForcedSync();
  }

  // NUOVO: Inizializza tag pre-compilati
  void _initializePrefilledTags() {
    if (widget.prefilledHashtags.isNotEmpty) {
      _currentTags = List.from(widget.prefilledHashtags);
      print(
          'DEBUG: Pre-popolato con ${_currentTags.length} hashtag: ${_currentTags.join(", ")}');

      // Mostra feedback visivo che gli hashtag sono stati trovati automaticamente
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentTags.isNotEmpty) {}
      });
    }
  }

  // FIX: Metodo corretto che non blocca gli aggiornamenti
  void _updateTitleIfNeeded() {
    // AGGIORNA SEMPRE quando arrivano metadati reali, anche se giÃƒ  inizializzato
    if (widget.metadata.title?.isNotEmpty == true &&
        !widget.isLoadingMetadata) {
      // CORRETTO: Usa il titolo dai metadati reali se disponibile
      _titleController.text = widget.metadata.title!;
      _hasInitializedTitle = true;
      print(
          'DEBUG: Titolo aggiornato con metadati reali: ${widget.metadata.title}');
    } else if (!_hasInitializedTitle && !widget.isLoadingMetadata) {
      // FALLBACK: Solo se non abbiamo mai inizializzato E non stiamo caricando
      final fallbackTitle =
          UrlMetadataService.getDomainFromUrl(widget.sharedContent.url);
      _titleController.text = fallbackTitle;
      _hasInitializedTitle = true;
      print('DEBUG: Titolo impostato con fallback: $fallbackTitle');
    }
    // AGGIUNTO: Debug per troubleshooting
    else if (widget.isLoadingMetadata) {
      print('DEBUG: Ancora in caricamento metadati, aspettando...');
    }
  }

  // COMPLETAMENTE RISCRITTO: Caricamento dati con sincronizzazione FORZATA
  Future<void> _loadFolderDataWithForcedSync() async {
    print(
        'DEBUG: ========== CARICAMENTO DATI CARTELLE CON SYNC FORZATA ==========');

    try {
      final folderService = FolderService();

      // STEP 1: FORZA SINCRONIZZAZIONE CON DATABASE PRIMA DI CARICARE
      print(
          'DEBUG: Forzando sincronizzazione con database prima del caricamento...');
      await folderService.syncWithDataService();
      print('DEBUG: Sincronizzazione completata');

      // STEP 2: ORA carica i dati sincronizzati
      _folderData = folderService.getCompleteDataForSharingPopupUltraFast();

      print('DEBUG: Dati cartelle caricati dopo sincronizzazione');
      print(
          'DEBUG: Totale cartelle disponibili: ${_folderData!['folders']?.length ?? 0}');

      // STEP 3: Verifica che i dati siano aggiornati
      final folderCount = _folderData!['folders']?.length ?? 0;
      if (folderCount <= 1) {
        print(
            'DEBUG: Attenzione: Solo ${folderCount} cartelle caricate (potrebbe indicare un problema)');
      }

      setState(() {
        _isFolderDataLoaded = true;
      });

      // STEP 4: Debug: Lista le cartelle caricate
      final folders =
          _folderData!['folders'] as List<Map<String, dynamic>>? ?? [];
      print('DEBUG: Cartelle caricate nel popup:');
      for (var folder in folders) {
        print(
            '  - ${folder['name']} (${folder['isDefault'] ? 'Default' : 'Utente'})');
      }

      print('DEBUG: Dati cartelle sincronizzati e caricati correttamente');
    } catch (e) {
      print('ERRORE: Caricamento dati cartelle con sync fallito: $e');

      // FALLBACK: Prova caricamento di emergenza
      try {
        final folderService = FolderService();
        _folderData = {
          'folders': [
            {
              'id': 'tutti',
              'name': 'Tutti',
              'displayName': 'Tutti (default)',
              'path': '',
              'isDefault': true,
              'color': Colors.purple.shade200.value,
              'description': 'Salva senza cartella specifica',
            }
          ],
          'isEmergency': true,
        };

        setState(() {
          _isFolderDataLoaded = true;
        });

        print('DEBUG: Caricamento di emergenza completato');
      } catch (emergencyError) {
        print(
            'ERRORE: Anche caricamento di emergenza fallito: $emergencyError');
      }
    }
  }

  void _onTemporaryFolderCreatedFromSelector(
      String folderName, String? parentPath) {
    setState(() {
      _selectorTemporaryFolders[folderName] = parentPath ?? '';

      final fullPath = (parentPath?.isEmpty ?? true)
          ? folderName
          : '$parentPath Ã¢â‚¬Âº $folderName';

      if (!_foldersToCreate.contains(fullPath)) {
        _foldersToCreate.add(fullPath);
      }
    });
  }

  Future<void> _createTemporaryFolder(
      String folderName, String? parentPath) async {
    try {
      final folderService = FolderService();

      final validationError = folderService.validateFolderName(folderName);
      if (validationError != null) {
        return;
      }

      final newPath = parentPath != null && parentPath.isNotEmpty
          ? '$parentPath Ã¢â‚¬Âº $folderName'
          : folderName;

      final temporaryFolder = {
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
        'name': folderName,
        'displayName': 'Ã°Å¸â€œÂ $folderName',
        'path': newPath,
        'fullPath': newPath,
        'isDefault': false,
        'isTemporary': true,
        'parentPath': parentPath,
        'color': Colors.blue.value,
        'description': 'Nuova cartella (temporanea)',
        'source': 'dialog',
      };

      setState(() {
        _temporaryFolders.add(temporaryFolder);
        _selectedFolderPath = newPath;

        if (!_foldersToCreate.contains(newPath)) {
          _foldersToCreate.add(newPath);
        }
      });
    } catch (e) {}
  }

  void _cleanupTemporaryFolders() {
    final totalTemporaryFolders =
        _temporaryFolders.length + _selectorTemporaryFolders.length;

    if (totalTemporaryFolders > 0) {
      _temporaryFolders.clear();
      _selectorTemporaryFolders.clear();
      _foldersToCreate.clear();
    }
  }

  // NUOVO: Metodo per aggiungere un tag
  void _addTag(String tagText) {
    if (!_canManageManualTags) return;
    if (tagText.trim().isEmpty) return;

    final newTag = tagText.replaceAll('#', '').trim().toLowerCase();

    if (!_currentTags.contains(newTag) &&
        newTag.isNotEmpty &&
        newTag.length <= 30) {
      setState(() {
        _currentTags.add(newTag);
        _tagInputController.clear();
      });
    }
  }

  // NUOVO: Metodo per rimuovere un tag
  void _removeTag(String tag) {
    setState(() {
      _currentTags.remove(tag);
    });
  }

  void _showFeedback(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  @override
  void didUpdateWidget(SaveSharedContentDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    // FIX PRINCIPALE: Se i metadati sono cambiati da loading a loaded, aggiorna il titolo
    if (oldWidget.isLoadingMetadata && !widget.isLoadingMetadata) {
      print('DEBUG: Metadati caricati, aggiornando titolo...');
      print('DEBUG: Nuovo titolo dai metadati: ${widget.metadata.title}');

      // FORZA aggiornamento con i metadati reali
      if (widget.metadata.title?.isNotEmpty == true) {
        _titleController.text = widget.metadata.title!;
        _hasInitializedTitle = true;
        print(
            'DEBUG: Titolo aggiornato con successo: ${widget.metadata.title}');
      }

      // NUOVO: Aggiorna anche i tag se sono stati caricati nuovi hashtag dai metadati
      if (!oldWidget.metadata.hasExtractedHashtags &&
          widget.metadata.hasExtractedHashtags) {
        print('DEBUG: Nuovi hashtag dai metadati, aggiornando...');
        final newHashtags = UrlMetadataService.combineHashtags([
          widget.sharedContent.extractedHashtags,
          widget.metadata.extractedHashtags,
        ]);

        // Aggiunge solo hashtag nuovi che non sono giÃƒ  presenti
        final additionalTags =
            newHashtags.where((tag) => !_currentTags.contains(tag)).toList();
        if (additionalTags.isNotEmpty) {
          setState(() {
            _currentTags.addAll(additionalTags);
          });
          print(
              'DEBUG: Aggiunti ${additionalTags.length} hashtag dai metadati: ${additionalTags.join(", ")}');
        }
      }
    }

    // Aggiorna il titolo se necessario (chiamata originale mantenuta)
    _updateTitleIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    // RIMOSSO: Non chiamare _updateTitleIfNeeded() qui per evitare interferenze

    final backgroundColor =
        widget.isDarkTheme ? Colors.grey[900] : Colors.white;
    final textColor = widget.isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = widget.isDarkTheme ? Colors.white70 : Colors.black54;
    final cardColor = widget.isDarkTheme ? Colors.grey[800] : Colors.grey[100];
    final canManageManualTags = _canManageManualTags;

    return AlertDialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.bookmark_add, color: Colors.green),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Salva contenuto condiviso',
              style: TextStyle(color: textColor, fontSize: 18),
            ),
          ),
          if (widget.isLoadingMetadata)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.green,
              ),
            ),
          // NUOVO: Badge per indicare hashtag automatici
          if (_currentTags.isNotEmpty)
            Container(
              margin: EdgeInsets.only(left: 8),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tag, color: Colors.blue, size: 12),
                  SizedBox(width: 4),
                  Text(
                    '${_currentTags.length}',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview card con loading state
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.isDarkTheme
                        ? Colors.grey[700]!
                        : Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.metadata.imageUrl != null &&
                        !widget.isLoadingMetadata) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          widget.metadata.imageUrl!,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 120,
                              color: Colors.grey[300],
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.green,
                                  value: loadingProgress.expectedTotalBytes !=
                                          null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 120,
                              color: Colors.grey[700],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.image_not_supported,
                                      color: Colors.grey[400], size: 32),
                                  SizedBox(height: 4),
                                  Text('Immagine non disponibile',
                                      style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.metadata.title ?? 'Titolo non disponibile',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.isLoadingMetadata)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.blue,
                            ),
                          ),
                      ],
                    ),
                    if (widget.metadata.description != null &&
                        !widget.isLoadingMetadata) ...[
                      SizedBox(height: 4),
                      Text(
                        UrlMetadataService.generatePreviewText(
                            widget.metadata.description,
                            maxLength: 100),
                        style: TextStyle(color: subtitleColor, fontSize: 12),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (!widget.isLoadingMetadata &&
                        (widget.metadata.creatorName?.isNotEmpty == true ||
                            widget.metadata.creatorUsername?.isNotEmpty ==
                                true)) ...[
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person, color: subtitleColor, size: 12),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [
                                widget.metadata.creatorName,
                                widget.metadata.creatorUsername,
                              ]
                                  .where((value) =>
                                      value?.trim().isNotEmpty == true)
                                  .join(' '),
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.link, color: subtitleColor, size: 12),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            UrlMetadataService.getDomainFromUrl(
                                widget.sharedContent.url),
                            style:
                                TextStyle(color: subtitleColor, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.sharedContent.platform != null) ...[
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              widget.sharedContent.platform!,
                              style:
                                  TextStyle(color: Colors.blue, fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Title field
              Text('Titolo',
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              TextField(
                controller: _titleController,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'Modifica il titolo...',
                  hintStyle: TextStyle(color: subtitleColor),
                  filled: true,
                  fillColor: cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 2,
              ),

              SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Text('Cartella di destinazione',
                        style: TextStyle(
                            color: textColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              SizedBox(height: 8),

              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isFolderDataLoaded
                      ? () => _showCardFolderSelector()
                      : null,
                  child: _isFolderDataLoaded
                      ? Text(
                          _selectedFolderPath!.isEmpty
                              ? 'Tutti (nessuna cartella specifica)'
                              : '$_selectedFolderPath',
                          style: TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: widget.isDarkTheme
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Sincronizzando cartelle...',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isDarkTheme
                        ? Colors.grey[700]
                        : Colors.grey[200],
                    foregroundColor:
                        widget.isDarkTheme ? Colors.white : Colors.black87,
                    padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),

              SizedBox(height: 12),

              // NUOVO: Sezione Tags con CHIPS e indicazione automatica
              Row(
                children: [
                  Text('Tags',
                      style: TextStyle(
                          color: textColor, fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  if (_currentTags.isNotEmpty) ...[
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_currentTags.length}',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 4),
                    if (widget.prefilledHashtags.isNotEmpty)
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome,
                                color: Colors.green, size: 10),
                            SizedBox(width: 2),
                            Text(
                              'auto',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
              SizedBox(height: 8),

              // NUOVO: Mostra chips dei tag esistenti
              if (_currentTags.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _currentTags.map((tag) {
                      final isAutoTag = widget.prefilledHashtags.contains(tag);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _removeTag(tag),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isAutoTag
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isAutoTag
                                      ? Colors.green.withOpacity(0.3)
                                      : Colors.blue.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAutoTag) ...[
                                  Icon(
                                    Icons.auto_awesome,
                                    color: Colors.green.shade700,
                                    size: 12,
                                  ),
                                  SizedBox(width: 4),
                                ],
                                Text(
                                  '#$tag',
                                  style: TextStyle(
                                    color:
                                        isAutoTag ? Colors.green : Colors.blue,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  Icons.close,
                                  color: isAutoTag
                                      ? Colors.green.shade700
                                      : Colors.blue.shade700,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                SizedBox(height: 8),
              ],

              // NUOVO: Campo per aggiungere nuovi tag (uno alla volta)
              if (canManageManualTags)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagInputController,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _currentTags.isEmpty
                              ? 'Aggiungi un tag...'
                              : 'Aggiungi altro tag...',
                          hintStyle:
                              TextStyle(color: subtitleColor, fontSize: 14),
                          filled: true,
                          fillColor: cardColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon:
                              Icon(Icons.tag, color: Colors.blue, size: 18),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        onSubmitted: (value) => _addTag(value),
                      ),
                    ),
                    SizedBox(width: 8),
                    Material(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _addTag(_tagInputController.text),
                        child: Container(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.25)),
                  ),
                  child: Text(
                    'Versione Free: i tag manuali sono disattivati. Restano disponibili solo quelli trovati automaticamente.',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                ),

              // NUOVO: Helper text dinamico
              SizedBox(height: 4),
              Text(
                !_canManageManualTags
                    ? 'I tag automatici restano modificabili singolarmente.'
                    : _currentTags.isEmpty
                        ? 'I tag aiutano a organizzare e trovare i tuoi post'
                        : widget.prefilledHashtags.isNotEmpty
                            ? 'Tag con Ã¢Å“Â¨ sono stati rilevati automaticamente. Clicca per rimuovere.'
                            : 'Clicca su un tag per rimuoverlo',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
                  _cleanupTemporaryFolders();
                  Navigator.of(context).pop();
                },
          child: Text('Annulla', style: TextStyle(color: subtitleColor)),
        ),
        ElevatedButton(
          onPressed: _isLoading || !_isFolderDataLoaded ? null : _saveContent,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.save, size: 16),
                    SizedBox(width: 6),
                    Text('Salva Post'),
                  ],
                ),
        ),
      ],
    );
  }

  void _showCardFolderSelector() {
    if (!_isFolderDataLoaded) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => FolderCardSelector(
        isDarkTheme: widget.isDarkTheme,
        initialSelection: _selectedFolderPath,
        onFolderSelected: (String selectedPath) {
          setState(() {
            _selectedFolderPath = selectedPath;
          });
        },
        onCreateFolder: (String folderName, String? parentPath) async {
          await _createTemporaryFolder(folderName, parentPath);
        },
        onTemporaryFolderCreated: _onTemporaryFolderCreatedFromSelector,
      ),
    );
  }

  // Ã°Å¸Å¡â‚¬ COMPLETAMENTE RISCRITTO: Salvataggio con NAVIGAZIONE AUTOMATICA
// 🔥 COMPLETAMENTE RISCRITTO: Salvataggio con NAVIGAZIONE AUTOMATICA E SYNC COMPLETO
  // Sostituisci TUTTO il metodo _saveContent() in sharing_service.dart con questo

  Future<void> _saveContent() async {
    if (_titleController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final folderService = FolderService();
      final canProceedAfterAd = await _adService.showImportAdIfRequired();
      if (!canProceedAfterAd) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        _showFeedback(
          'Pubblicità non disponibile al momento. Riprova tra poco per completare il salvataggio.',
          backgroundColor: Colors.orange,
        );
        return;
      }

      // ============================================================================
      // 🔥 NUOVA IMPLEMENTAZIONE: USA IL METODO CENTRALIZZATO
      // ============================================================================

      String? actualFolderIdToUse;
      bool hasTemporaryFolders = _foldersToCreate.isNotEmpty;
      bool isNewFolderCreated = hasTemporaryFolders;

      if (hasTemporaryFolders) {
        print(
            'DEBUG: ========== CREAZIONE GERARCHIA CON METODO CENTRALIZZATO ==========');
        print('DEBUG: Path da creare: $_selectedFolderPath');
        print('DEBUG: Cartelle temporanee: ${_foldersToCreate.length}');

        try {
          // 🎯 CHIAMATA AL NUOVO METODO CENTRALIZZATO
          // Sostituisce ~120 righe di logica complessa con una singola chiamata!
          actualFolderIdToUse =
              await folderService.createFolderHierarchyFromPath(
            _selectedFolderPath!,
            maxRetries: 3,
            retryDelay: Duration(milliseconds: 300),
          );

          print('DEBUG: ✅ Gerarchia creata con successo!');
          print('DEBUG: ID cartella finale: $actualFolderIdToUse');
        } catch (hierarchyError) {
          print(
              'DEBUG: ❌ Errore sync durante creazione gerarchia: $hierarchyError');

          // FIX: Tentativo di recupero - la cartella potrebbe essere stata creata anche se sync è fallito
          print('DEBUG: 🔄 Tentativo recupero cartella appena creata...');

          bool recovered = false;

          try {
            // Attendi un momento per la propagazione
            await Future.delayed(Duration(milliseconds: 500));

            // Sincronizza FolderService
            await folderService.syncWithDataService();

            // Cerca la cartella appena creata
            final mockFolder =
                folderService.findFolderByPath(_selectedFolderPath!);

            if (mockFolder != null && !mockFolder.isSpecial) {
              print('DEBUG: MockFolder trovata: ${mockFolder.name}');

              final folders = await DataService.instance.getFolders();
              final realFolder =
                  folderService.findRealFolderByMockFolder(folders, mockFolder);

              if (realFolder != null) {
                actualFolderIdToUse = realFolder.id;
                recovered = true;
                print(
                    'DEBUG: ✅ Cartella recuperata con successo: ${realFolder.name} (${realFolder.id})');
              } else {
                print(
                    'DEBUG: ⚠️ MockFolder trovata ma RealFolder non corrisponde');
              }
            } else {
              print(
                  'DEBUG: ⚠️ MockFolder non trovata per path: $_selectedFolderPath');
            }
          } catch (recoveryError) {
            print('DEBUG: ❌ Recupero fallito: $recoveryError');
          }

          // Se recupero fallito, usa fallback a cartella default
          if (!recovered) {
            print('DEBUG: ⚠️ Usando cartella default come fallback...');

            DataService.instance
                .invalidateCache(folders: true, posts: true); // ⭐ Anche posts
            await DataService.instance.reloadFromDisk();

            final foldersAfterError = await DataService.instance.getFolders();
            final defaultFolder = foldersAfterError.firstWhere(
              (f) => f.isDefault,
              orElse: () => throw Exception('Cartella default non trovata'),
            );

            actualFolderIdToUse = defaultFolder.id;
            print(
                'DEBUG: ⚠️ Fallback a cartella default: ${defaultFolder.name} (${defaultFolder.id})');

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Errore creazione cartella. Post salvato in "Tutti".'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        }
      } else {
        // Nessuna cartella temporanea, usa cartella esistente
        print('DEBUG: Nessuna cartella da creare, usando selezione esistente');

        if (_selectedFolderPath!.isEmpty || _selectedFolderPath == 'Tutti') {
          // Salva in "Tutti"
          final folders = await DataService.instance.getFolders();
          final defaultFolder = folders.firstWhere((f) => f.isDefault);
          actualFolderIdToUse = defaultFolder.id;
          print('DEBUG: Salvando in Tutti (${defaultFolder.id})');
        } else {
          // Cerca cartella esistente
          print('DEBUG: Cercando cartella esistente: $_selectedFolderPath');

          await folderService.syncWithDataService();
          final folders = await DataService.instance.getFolders();

          // Usa findRealFolderByMockFolder per ricerca corretta
          final mockFolder =
              folderService.findFolderByPath(_selectedFolderPath!);

          if (mockFolder != null && !mockFolder.isSpecial) {
            final destinationValidation =
                _accessService.validateFolderDestination(mockFolder);
            if (destinationValidation != null) {
              throw Exception(destinationValidation);
            }
            final realFolder =
                folderService.findRealFolderByMockFolder(folders, mockFolder);
            if (realFolder != null) {
              actualFolderIdToUse = realFolder.id;
              print(
                  'DEBUG: Cartella trovata: ${realFolder.name} (${realFolder.id})');
            }
          }

          // Fallback se non trovata
          if (actualFolderIdToUse == null) {
            final defaultFolder = folders.firstWhere((f) => f.isDefault);
            actualFolderIdToUse = defaultFolder.id;
            print('DEBUG: Cartella non trovata, usando default');
          }
        }
      }

      // ============================================================================
      // SALVATAGGIO POST (invariato)
      // ============================================================================

      final tags = List<String>.from(_currentTags);

      print('DEBUG: Salvando post nella cartella ID: $actualFolderIdToUse');

      // NUOVO: Risolvi l'URL originale se è un link di condivisione Google
      String finalUrl = widget.sharedContent.url;
      print('DEBUG: URL originale ricevuto: $finalUrl');

      if (finalUrl.contains('share.google')) {
        print(
            'DEBUG: Trovato link di condivisione Google, risolvendo URL originale...');
        try {
          final resolvedUrl = await _resolveGoogleShareUrl(finalUrl);
          print('DEBUG: Risultato risoluzione: $resolvedUrl');

          if (resolvedUrl != null &&
              resolvedUrl.isNotEmpty &&
              resolvedUrl != finalUrl) {
            print('DEBUG: URL originale risolto: $resolvedUrl');
            finalUrl = resolvedUrl;
          } else {
            // Fallback: prova a usare il dominio ricavato dall'immagine (che di solito è del sito originale)
            final fallbackFromImage =
                _guessSiteUrlFromImage(widget.metadata.imageUrl);
            if (fallbackFromImage != null) {
              print('DEBUG: Fallback da imageUrl -> $fallbackFromImage');
              finalUrl = fallbackFromImage;
            } else {
              print(
                  'DEBUG: Impossibile risolvere URL originale e nessun fallback da imageUrl, usando URL originale');
            }
          }
        } catch (e) {
          print('DEBUG: Errore risoluzione URL: $e');
        }
      } else {
        print(
            'DEBUG: URL non è un link di condivisione Google, usando URL originale');
      }

      print('DEBUG: URL finale che verrà salvato: $finalUrl');

      final savedToFolder =
          await folderService.saveSharedPostWithOptionalFolder(
        url: finalUrl,
        title: _titleController.text.trim(),
        description: widget.metadata.description ?? '',
        imageUrl: widget.metadata.imageUrl,
        creatorName: widget.metadata.creatorName,
        creatorUsername: widget.metadata.creatorUsername,
        tags: tags,
        selectedFolderId: actualFolderIdToUse ?? 'tutti',
        selectedFolderPath:
            _selectedFolderPath!.isEmpty ? null : _selectedFolderPath,
      );

      print('DEBUG: Post salvato con successo in: $savedToFolder');
      print('DEBUG: Con ${tags.length} tag: ${tags.join(", ")}');
      await _adService.recordSuccessfulImport();

      // 🔥 Ottimizzazione: niente attese/blocchi. Sincronizza in background se serve
      if (isNewFolderCreated) {
        try {
          folderService.syncWithDataService();
        } catch (_) {}
      }

      final postId = 'post_${DateTime.now().millisecondsSinceEpoch}';

      final Map<String, String> result = {
        'folderPath':
            _selectedFolderPath!.isEmpty ? 'Tutti' : _selectedFolderPath!,
        'postId': postId,
      };

      print('DEBUG: ✅ TUTTO SINCRONIZZATO - Restituendo result: $result');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
        print('DEBUG: ✅ Dialog chiuso, result restituito');
      }

      await Future.delayed(Duration(milliseconds: 200));

      if (mounted) {
        final tagInfo = tags.isNotEmpty ? ' con ${tags.length} tag' : '';
      }
    } catch (e, stackTrace) {
      print('ERRORE: Salvataggio fallito: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      if (mounted) {}

      await Future.delayed(Duration(milliseconds: 100));
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  // Risolve l'URL originale dai link di condivisione di Google
  Future<String?> _resolveGoogleShareUrl(String url) async {
    print('DEBUG: _resolveGoogleShareUrl chiamato con URL: $url');
    try {
      final uri = Uri.parse(url);

      // METODO 1: Prova prima a estrarre l'URL dal parametro query
      print('DEBUG: Parametri query disponibili: ${uri.queryParameters}');

      // Prova vari parametri comuni usati dai servizi di condivisione
      final possibleParams = [
        'url',
        'u',
        'link',
        'target',
        'to',
        'dest',
        'redirect'
      ];
      for (var param in possibleParams) {
        if (uri.queryParameters.containsKey(param)) {
          final extractedUrl = uri.queryParameters[param];
          if (extractedUrl != null &&
              extractedUrl.isNotEmpty &&
              extractedUrl.startsWith('http')) {
            print('DEBUG: ✓ URL estratto da parametro "$param": $extractedUrl');
            return extractedUrl;
          }
        }
      }

      // METODO 2: Cerca URL encoded nell'intero URL
      print('DEBUG: Cercando URL encoded nell\'URL completo...');
      final fullUrl = url.toString();
      final urlEncodedPattern =
          RegExp(r'https?%3A%2F%2F[^&\s]+', caseSensitive: false);
      final encodedMatch = urlEncodedPattern.firstMatch(fullUrl);
      if (encodedMatch != null) {
        try {
          final encodedUrl = encodedMatch.group(0)!;
          final decodedUrl = Uri.decodeComponent(encodedUrl);
          print('DEBUG: ✓ URL decodificato: $decodedUrl');
          return decodedUrl;
        } catch (e) {
          print('DEBUG: Errore decodifica URL: $e');
        }
      }

      print('DEBUG: Nessun parametro URL trovato, provando richiesta HTTP...');

      // METODO 3: Segui il redirect HTTP (con timeout più lungo)
      try {
        print('DEBUG: Tentativo richiesta HTTP a: $url');
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7',
          },
        ).timeout(Duration(seconds: 8)); // Aumentato timeout a 8 secondi

        print('DEBUG: Risposta HTTP ricevuta, status: ${response.statusCode}');
        print('DEBUG: URL finale della richiesta: ${response.request?.url}');

        // Controlla se c'è stato un redirect
        if (response.request?.url != null) {
          final finalUrl = response.request!.url.toString();
          print('DEBUG: URL finale dopo redirect: $finalUrl');
          if (finalUrl != url && !finalUrl.contains('share.google')) {
            print('DEBUG: ✓ URL risolto tramite redirect: $finalUrl');
            return finalUrl;
          }
        }

        // METODO 4: Cerca nell'HTML con pattern più completi
        if (response.statusCode == 200) {
          final html = response.body;
          print('DEBUG: Analizzando HTML, lunghezza: ${html.length} caratteri');

          // Pattern aggiornati e più completi (usando stringhe normali per evitare problemi con apici)
          // AGGIORNATO: Fix regex per parsing HTML corretto
          final patterns = [
            // Meta refresh
            RegExp('url=(https?://[^\\s<>"]+)', caseSensitive: false),

            // JavaScript redirects (solo doppi apici)
            RegExp('window\\.location\\.href\\s*=\\s*"(https?://[^\\s<>"]+)"',
                caseSensitive: false),
            RegExp('window\\.location\\s*=\\s*"(https?://[^\\s<>"]+)"',
                caseSensitive: false),
            RegExp('location\\.href\\s*=\\s*"(https?://[^\\s<>"]+)"',
                caseSensitive: false),
            RegExp('location\\.replace\\s*\\(\\s*"(https?://[^\\s<>"]+)"',
                caseSensitive: false),
            RegExp('window\\.open\\s*\\(\\s*"(https?://[^\\s<>"]+)"',
                caseSensitive: false),

            // JavaScript redirects (solo apici singoli)
            RegExp("window\\.location\\.href\\s*=\\s*'(https?://[^\\s<>\"]+)'",
                caseSensitive: false),
            RegExp("window\\.location\\s*=\\s*'(https?://[^\\s<>\"]+)'",
                caseSensitive: false),
            RegExp("location\\.href\\s*=\\s*'(https?://[^\\s<>\"]+)'",
                caseSensitive: false),
            RegExp("location\\.replace\\s*\\(\\s*'(https?://[^\\s<>\"]+)'",
                caseSensitive: false),
            RegExp("window\\.open\\s*\\(\\s*'(https?://[^\\s<>\"]+)'",
                caseSensitive: false),

            // Canonical URL
            RegExp('<link[^>]*rel="canonical"[^>]*href="(https?://[^\\s<>"]+)"',
                caseSensitive: false),
            RegExp(
                "<link[^>]*rel='canonical'[^>]*href='(https?://[^\\s<>\"]+)'",
                caseSensitive: false),

            // Open Graph URL
            RegExp(
                '<meta[^>]*property="og:url"[^>]*content="(https?://[^\\s<>"]+)"',
                caseSensitive: false),
            RegExp(
                "<meta[^>]*property='og:url'[^>]*content='(https?://[^\\s<>\"]+)'",
                caseSensitive: false),
          ];

          for (int i = 0; i < patterns.length; i++) {
            final pattern = patterns[i];
            final match = pattern.firstMatch(html);
            if (match != null && match.group(1) != null) {
              final foundUrl = match.group(1)!;
              print('DEBUG: URL trovato con pattern ${i + 1}: $foundUrl');
              if (!foundUrl.contains('share.google') &&
                  !foundUrl.contains('google.com/url')) {
                print('DEBUG: ✓ URL valido trovato nell\'HTML: $foundUrl');
                return foundUrl;
              }
            }
          }

          print('DEBUG: Nessun URL valido trovato nei pattern HTML');
        }
      } catch (e) {
        print('DEBUG: Errore nella richiesta HTTP: $e');
      }
    } catch (e) {
      print('DEBUG: Errore generale risoluzione URL: $e');
    }

    print('DEBUG: ⚠ Impossibile risolvere l\'URL originale');
    return null;
  }

  // Ricava un URL base a partire dall'imageUrl (es. https://www.giallozafferano.it/images/.. -> https://www.giallozafferano.it)
  String? _guessSiteUrlFromImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(imageUrl);
      if (uri.host.isEmpty) return null;
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'https';
      final base = '$scheme://${uri.host}';
      return base;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagInputController.dispose(); // NUOVO: Dispose del controller tag
    super.dispose();
  }
}
