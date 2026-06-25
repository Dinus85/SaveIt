// lib/services/remote_content_service.dart
// VERSIONE DEV-FRIENDLY - Aggiornamenti più frequenti durante sviluppo

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RemoteContent {
  final String title;
  final String content;
  final String lastUpdated;
  final String version;

  RemoteContent({
    required this.title,
    required this.content,
    required this.lastUpdated,
    required this.version,
  });

  factory RemoteContent.fromJson(Map<String, dynamic> json) {
    return RemoteContent(
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      lastUpdated: json['lastUpdated'] ?? '',
      version: json['version'] ?? '1.0',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'lastUpdated': lastUpdated,
        'version': version,
      };
}

class RemoteContentService {
  static final RemoteContentService _instance =
      RemoteContentService._internal();
  factory RemoteContentService() => _instance;
  RemoteContentService._internal();

  // URLs GitHub
  static const String _baseGitHubUrl =
      'https://raw.githubusercontent.com/Dinus85/saveit-legal-content/main';

  static const Map<String, String> _contentUrls = {
    'privacy_policy': '$_baseGitHubUrl/privacy_policy.json',
    'terms_conditions': '$_baseGitHubUrl/terms_conditions.json',
    'marketing_communications': '$_baseGitHubUrl/marketing_communications.json',
    'help_center': '$_baseGitHubUrl/help_center.json',
  };

  // Cache in memoria
  final Map<String, RemoteContent> _memoryCache = {};

  // Timeout
  static const Duration _timeout = Duration(seconds: 15);

  // ⚡ MODALITÀ SVILUPPO - Controllo più frequente
  static const bool _isDevelopmentMode =
      true; // ← CAMBIA A false per produzione
  static const Duration _minCheckInterval = Duration(
      minutes: _isDevelopmentMode ? 1 : 5 // 1 min in dev, 5 min in prod
      );

  /// Metodo principale per caricare contenuto
  Future<RemoteContent> loadContent(String contentType,
      {bool forceRefresh = false}) async {
    try {
      print(
          'DEBUG_SERVICE: Caricando contenuto: $contentType (forceRefresh: $forceRefresh, devMode: $_isDevelopmentMode)');

      // 1. Se forceRefresh, salta tutto e vai diretto al remoto
      if (forceRefresh) {
        print('DEBUG_SERVICE: Force refresh - caricamento diretto da remoto');
        final remoteContent = await _loadFromRemoteWithRetry(contentType);
        if (remoteContent != null) {
          _memoryCache[contentType] = remoteContent;
          await _saveToLocalStorage(contentType, remoteContent);
          await _updateLastCheckTime(contentType);
          return remoteContent;
        }
      }

      // 2. In modalità sviluppo, controlla sempre remoto al primo accesso della sessione
      if (_isDevelopmentMode && !_memoryCache.containsKey(contentType)) {
        print(
            'DEBUG_SERVICE: Development mode - primo accesso, controllo remoto');
        final remoteContent = await _loadFromRemoteWithRetry(contentType);
        if (remoteContent != null) {
          _memoryCache[contentType] = remoteContent;
          await _saveToLocalStorage(contentType, remoteContent);
          await _updateLastCheckTime(contentType);
          return remoteContent;
        }
      }

      // 3. Controlla se abbiamo bisogno di aggiornare
      final shouldCheckRemote = await _shouldCheckRemote(contentType);
      print('DEBUG_SERVICE: Dovrebbe controllare remoto: $shouldCheckRemote');

      if (shouldCheckRemote) {
        // 4. Prova caricamento remoto
        print('DEBUG_SERVICE: Tentativo caricamento remoto con retry...');
        final remoteContent = await _loadFromRemoteWithRetry(contentType);

        if (remoteContent != null) {
          // Controlla se è una versione più nuova
          final localContent = await _loadFromLocalStorage(contentType);

          if (localContent == null ||
              _isNewerVersion(remoteContent, localContent)) {
            print(
                'DEBUG_SERVICE: Nuova versione trovata: ${remoteContent.version}');
            _memoryCache[contentType] = remoteContent;
            await _saveToLocalStorage(contentType, remoteContent);
            await _updateLastCheckTime(contentType);
            return remoteContent;
          } else {
            print('DEBUG_SERVICE: Versione remota non più recente, uso locale');
            _memoryCache[contentType] = localContent;
            await _updateLastCheckTime(contentType);
            return localContent;
          }
        } else {
          print('DEBUG_SERVICE: Caricamento remoto fallito, provo cache');
        }
      }

      // 5. Usa cache in memoria se disponibile
      if (_memoryCache.containsKey(contentType)) {
        print('DEBUG_SERVICE: Usando cache in memoria');
        return _memoryCache[contentType]!;
      }

      // 6. Carica da storage locale
      final localContent = await _loadFromLocalStorage(contentType);
      if (localContent != null) {
        print('DEBUG_SERVICE: Caricato da storage locale');
        _memoryCache[contentType] = localContent;
        return localContent;
      }

      // 7. Fallback a contenuto di default
      print('DEBUG_SERVICE: Usando contenuto di fallback');
      final defaultContent = _getDefaultContent(contentType);
      _memoryCache[contentType] = defaultContent;
      return defaultContent;
    } catch (e) {
      print('ERRORE_SERVICE: Caricamento contenuto $contentType: $e');

      // Fallback intelligente
      if (_memoryCache.containsKey(contentType)) {
        return _memoryCache[contentType]!;
      }

      final localContent = await _loadFromLocalStorage(contentType);
      if (localContent != null) {
        _memoryCache[contentType] = localContent;
        return localContent;
      }

      return _getDefaultContent(contentType);
    }
  }

  /// 🔄 METODO PER SVILUPPO - Refresh rapido
  Future<RemoteContent> quickRefresh(String contentType) async {
    print('DEBUG_SERVICE: Quick refresh for development');
    _memoryCache.remove(contentType);

    // Resetta il timestamp per forzare il controllo
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remote_check_${contentType}_time');

    return await loadContent(contentType);
  }

  /// 🔄 CLEAR DEVELOPMENT CACHE - Per test rapidi
  Future<void> clearDevelopmentCache() async {
    if (_isDevelopmentMode) {
      _memoryCache.clear();
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith('remote_check_'))
          .toList();

      for (final key in keys) {
        await prefs.remove(key);
      }

      print(
          'DEBUG_SERVICE: Development cache cleared - prossimo accesso controllerà remoto');
    }
  }

  /// Metodo di test per connettività
  Future<Map<String, dynamic>> testConnectivity(String contentType) async {
    final url = _contentUrls[contentType];
    if (url == null) return {'error': 'URL non trovato per $contentType'};

    try {
      print('DEBUG_TEST: Testing connectivity...');

      final urlWithCacheBust =
          '$url?test=${DateTime.now().millisecondsSinceEpoch}';
      print('DEBUG_TEST: URL: $urlWithCacheBust');

      final response = await http.get(
        Uri.parse(urlWithCacheBust),
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
          'User-Agent': 'SaveIn-Flutter-App/1.0',
        },
      ).timeout(Duration(seconds: 15));

      return {
        'success': true,
        'statusCode': response.statusCode,
        'headers': response.headers.toString(),
        'bodyLength': response.body.length,
        'isValidJson': _isValidJson(response.body),
        'url': urlWithCacheBust,
        'body': response.body.length > 200
            ? response.body.substring(0, 200) + '...'
            : response.body,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'errorType': e.runtimeType.toString(),
        'url': url,
      };
    }
  }

  bool _isValidJson(String str) {
    try {
      jsonDecode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Caricamento remoto con retry multipli
  Future<RemoteContent?> _loadFromRemoteWithRetry(String contentType,
      {int maxRetries = 3}) async {
    final url = _contentUrls[contentType];
    if (url == null) {
      print('ERRORE_SERVICE: URL non trovato per $contentType');
      return null;
    }

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('DEBUG_SERVICE: Tentativo $attempt/$maxRetries per $contentType');

        String urlToUse;
        Map<String, String> headers = {
          'Accept': 'application/json',
          'User-Agent': 'SaveIn-Flutter-App/1.0',
        };

        switch (attempt) {
          case 1:
            urlToUse = url;
            break;
          case 2:
            urlToUse = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
            headers['Cache-Control'] = 'no-cache';
            break;
          default:
            urlToUse =
                '$url?retry=$attempt&t=${DateTime.now().millisecondsSinceEpoch}';
            headers.addAll({
              'Cache-Control': 'no-cache, no-store, must-revalidate',
              'Pragma': 'no-cache',
              'Expires': '0',
            });
            break;
        }

        print('DEBUG_SERVICE: URL tentativo $attempt: $urlToUse');

        final response = await http
            .get(
              Uri.parse(urlToUse),
              headers: headers,
            )
            .timeout(Duration(seconds: 10 + (attempt * 3)));

        print(
            'DEBUG_SERVICE: Tentativo $attempt - Status: ${response.statusCode}, Body length: ${response.body.length}');

        if (response.statusCode == 200 && response.body.isNotEmpty) {
          try {
            final jsonData = jsonDecode(response.body);
            final content = RemoteContent.fromJson(jsonData);
            print(
                'DEBUG_SERVICE: Successo al tentativo $attempt - Versione: ${content.version}');
            return content;
          } catch (e) {
            print(
                'ERRORE_SERVICE: JSON parse fallito al tentativo $attempt: $e');
            if (attempt == maxRetries) {
              print('ERRORE_SERVICE: JSON parse fallito su tutti i tentativi');
            }
          }
        } else {
          print(
              'DEBUG_SERVICE: Tentativo $attempt fallito - HTTP ${response.statusCode}');
          if (response.statusCode == 404) {
            print('ERRORE_SERVICE: File non trovato');
            break;
          }
        }
      } catch (e) {
        print('ERRORE_SERVICE: Tentativo $attempt per $contentType: $e');
        if (attempt == maxRetries) {
          print('ERRORE_SERVICE: Tutti i tentativi esauriti');
          return null;
        }

        await Future.delayed(Duration(seconds: attempt));
      }
    }

    return null;
  }

  /// Determina se dobbiamo controllare il contenuto remoto
  Future<bool> _shouldCheckRemote(String contentType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckString =
          prefs.getString('remote_check_${contentType}_time');

      if (lastCheckString == null) {
        print('DEBUG_SERVICE: Primo caricamento, controlla remoto');
        return true;
      }

      final lastCheck = DateTime.parse(lastCheckString);
      final timeSinceLastCheck = DateTime.now().difference(lastCheck);

      if (timeSinceLastCheck > _minCheckInterval) {
        print(
            'DEBUG_SERVICE: Ultimo controllo ${timeSinceLastCheck.inMinutes} minuti fa, controlla remoto');
        return true;
      } else {
        print(
            'DEBUG_SERVICE: Controllo recente (${timeSinceLastCheck.inMinutes} min fa), usa locale');
        return false;
      }
    } catch (e) {
      print('DEBUG_SERVICE: Errore controllo timing: $e, controlla remoto');
      return true;
    }
  }

  Future<void> _updateLastCheckTime(String contentType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'remote_check_${contentType}_time', DateTime.now().toIso8601String());
    } catch (e) {
      print('DEBUG_SERVICE: Errore salvataggio timestamp: $e');
    }
  }

  bool _isNewerVersion(RemoteContent remote, RemoteContent local) {
    if (remote.version != local.version) {
      try {
        final remoteVersionParts =
            remote.version.split('.').map(int.parse).toList();
        final localVersionParts =
            local.version.split('.').map(int.parse).toList();

        for (int i = 0;
            i < remoteVersionParts.length && i < localVersionParts.length;
            i++) {
          if (remoteVersionParts[i] > localVersionParts[i]) {
            return true;
          } else if (remoteVersionParts[i] < localVersionParts[i]) {
            return false;
          }
        }

        return remoteVersionParts.length > localVersionParts.length;
      } catch (e) {
        print('DEBUG_SERVICE: Errore parsing versione: $e');
      }
    }

    try {
      final remoteDate = DateTime.parse(remote.lastUpdated);
      final localDate = DateTime.parse(local.lastUpdated);
      return remoteDate.isAfter(localDate);
    } catch (e) {
      print('DEBUG_SERVICE: Errore parsing date: $e');
      return false;
    }
  }

  Future<RemoteContent?> _loadFromLocalStorage(String contentType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('remote_content_$contentType');

      if (cachedJson != null) {
        final jsonData = jsonDecode(cachedJson);
        return RemoteContent.fromJson(jsonData);
      }

      return null;
    } catch (e) {
      print('ERRORE_SERVICE: Caricamento locale $contentType: $e');
      return null;
    }
  }

  Future<void> _saveToLocalStorage(
      String contentType, RemoteContent content) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(content.toJson());
      await prefs.setString('remote_content_$contentType', jsonString);

      print(
          'DEBUG_SERVICE: Contenuto $contentType salvato in cache locale, versione: ${content.version}');
    } catch (e) {
      print('ERRORE_SERVICE: Salvataggio locale $contentType: $e');
    }
  }

  Future<RemoteContent> forceRefresh(String contentType) async {
    print('DEBUG_SERVICE: Force refresh richiesto per $contentType');
    _memoryCache.remove(contentType);
    return await loadContent(contentType, forceRefresh: true);
  }

  Future<void> refreshAllContent() async {
    print('DEBUG_SERVICE: Force refresh di tutti i contenuti');

    final futures = _contentUrls.keys.map((contentType) async {
      try {
        await forceRefresh(contentType);
      } catch (e) {
        print('ERRORE_SERVICE: Refresh $contentType: $e');
      }
    });

    await Future.wait(futures);
    print('DEBUG_SERVICE: Refresh di tutti i contenuti completato');
  }

  Future<bool> hasUpdate(String contentType) async {
    try {
      final localContent = await _loadFromLocalStorage(contentType);
      if (localContent == null) return true;

      final remoteContent = await _loadFromRemoteWithRetry(contentType);
      if (remoteContent == null) return false;

      return _isNewerVersion(remoteContent, localContent);
    } catch (e) {
      return false;
    }
  }

  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) =>
              key.startsWith('remote_content_') ||
              key.startsWith('remote_check_'))
          .toList();

      for (final key in keys) {
        await prefs.remove(key);
      }

      _memoryCache.clear();
      print('DEBUG_SERVICE: Cache contenuti remoti cancellata completamente');
    } catch (e) {
      print('ERRORE_SERVICE: Cancellazione cache: $e');
    }
  }

  Future<Map<String, dynamic>> getCacheInfo() async {
    final info = <String, dynamic>{};

    for (final contentType in _contentUrls.keys) {
      try {
        final cached = await _loadFromLocalStorage(contentType);
        final prefs = await SharedPreferences.getInstance();
        final lastCheck = prefs.getString('remote_check_${contentType}_time');

        info[contentType] = {
          'cached': cached != null,
          'version': cached?.version ?? 'none',
          'lastUpdated': cached?.lastUpdated ?? 'never',
          'lastCheck': lastCheck ?? 'never',
          'inMemory': _memoryCache.containsKey(contentType),
          'url': _contentUrls[contentType],
          'devMode': _isDevelopmentMode,
          'checkInterval': '${_minCheckInterval.inMinutes} min',
        };
      } catch (e) {
        info[contentType] = {'error': e.toString()};
      }
    }

    return info;
  }

  RemoteContent _getDefaultContent(String contentType) {
    final defaultContents = {
      'privacy_policy': RemoteContent(
        title: 'Privacy Policy',
        content: '''# Privacy Policy di SaveIn

**Ultimo aggiornamento:** 25/06/2026

## Introduzione
SaveIn! rispetta la tua privacy e protegge i tuoi dati personali. Questa informativa spiega come trattiamo dati account, contenuti salvati, cartelle, condivisioni, notifiche, promo, statistiche e funzioni Free/Premium.

## Dati Raccolti
- **Account**: nome, email, username, provider di accesso, ruolo Free/Premium/Admin, data scadenza Premium e consensi.
- **Contenuti**: link, post, note, tag, cartelle, sottocartelle, immagini/anteprime, URL e metadati necessari a salvare, cercare e organizzare i contenuti.
- **Condivisioni e import**: inviti, link condivisi, email destinatario, contenuti/cartelle importate, riferimenti tecnici usati dal backend per copiare in modo coerente cartelle, sottocartelle e post.
- **Statistiche e analytics**: eventi d'uso, statistiche semplici/avanzate, aperture, ricerche, tag e nomi cartelle più usati, uso funzioni Free/Premium e dati aggregati visibili in dashboard.
- **Notifiche e promo**: token FCM, notifiche in-app/push, banner promo mostrati o chiusi, eventuali promo nuovi iscritti o cross-app.
- **Preferenze**: tema, impostazioni locali, cache tecniche, stato tutorial e preferenze di marketing/notifiche.

## Uso dei Dati
I tuoi dati vengono utilizzati esclusivamente per:
- Fornire salvataggio, ricerca, cartelle, condivisione e import contenuti.
- Sincronizzare i tuoi dati tra dispositivi e mantenere coerenza tra Firebase e cache locale.
- Gestire piani Free/Premium, limiti funzione, rewarded ads e storico dei cambi piano.
- Mostrare notifiche di servizio, promo e comunicazioni marketing solo dove consentito.
- Migliorare affidabilità, sicurezza, statistiche generali e dashboard amministrativa.

## Archiviazione
- **Locale**: SaveIn! può usare cache e SharedPreferences per rendere l'app veloce e disponibile.
- **Cloud**: Firebase Auth, Firestore, Cloud Functions e Storage vengono usati per account, contenuti, condivisioni, anteprime e pulizia dati.
- **Cache tecniche**: alcune anteprime o contenuti deduplicati possono essere conservati in forma tecnica per evitare duplicazioni e migliorare il servizio, senza vendere dati personali.

## I Tuoi Diritti
- Accesso ai tuoi dati
- Correzione di informazioni errate
- Cancellazione del tuo account e dei dati personali associati
- Esportazione dei tuoi contenuti
- Revoca del consenso marketing e gestione notifiche

## Sicurezza
Utilizziamo Firebase Authentication, regole Firestore, Cloud Functions, controlli lato backend e comunicazioni HTTPS. Quando elimini l'account, l'app pulisce anche dati locali e il backend elimina i dati collegati all'utente nei limiti tecnici previsti dal servizio.

## Contatti
Per domande sulla privacy: privacy@savein.app

---
*Contenuto locale di fallback - Verifica connessione internet*''',
        lastUpdated: DateTime.now().toIso8601String(),
        version: '1.0-fallback',
      ),
      'terms_conditions': RemoteContent(
        title: 'Termini e Condizioni',
        content: '''# Termini e Condizioni di SaveIn

**Ultimo aggiornamento:** 25/06/2026

## Accettazione dei Termini
Utilizzando SaveIn! accetti questi termini e condizioni. Se non li accetti, non utilizzare l'app.

## Descrizione del Servizio
SaveIn! è un'app per salvare, organizzare, cercare, condividere e importare link, post, cartelle e contenuti personali. Il servizio include funzioni locali e cloud basate su Firebase, dashboard amministrativa, notifiche, promo e piani Free/Premium con limiti configurabili.

## Account Utente
- Sei responsabile della sicurezza del tuo account
- Fornisci informazioni accurate durante la registrazione
- Non condividere le tue credenziali
- Se usi Google Sign-In, l'accesso dipende anche dai servizi Google/Firebase

## Piani Free e Premium
- La versione Free può includere limiti su contenuti, import, condivisioni, statistiche, pubblicità e funzioni avanzate.
- La versione Premium offre limiti più ampi o accesso senza pubblicità commerciale secondo quanto mostrato nell'app.
- I limiti possono essere modificati dalla configurazione backend per sostenibilità tecnica, economica e anti-abuso.
- Le scadenze Premium, promo e cambi piano possono essere registrati nello storico account.

## Uso Consentito
- Salva contenuti per uso personale
- Rispetta i diritti d'autore dei contenuti salvati
- Non utilizzare l'app per scopi illegali
- Non tentare di aggirare limiti Free/Premium, sicurezza, condivisioni, import, pubblicità premiate o controlli backend

## Condivisione e Import
Quando condividi o importi cartelle/post, il backend può copiare i dati necessari direttamente da Firebase per mantenere struttura, sottocartelle, riferimenti e URL. Sei responsabile di condividere solo contenuti che hai diritto di condividere. SaveIn! non garantisce disponibilità o accuratezza dei siti terzi collegati.

## Limitazioni
- L'app è fornita "così com'è"
- Non garantiamo disponibilità 100%
- Backup regolari dei tuoi dati sono consigliati
- Anteprime, metadata, immagini esterne e URL possono cambiare o non essere più disponibili per cause esterne

## Modifiche ai Termini
Ci riserviamo il diritto di modificare questi termini con preavviso.

## Legge Applicabile
Questi termini sono regolati dalla legge italiana.

## Contatti
Per domande sui termini: legal@savein.app

---
*Contenuto locale di fallback - Verifica connessione internet*''',
        lastUpdated: DateTime.now().toIso8601String(),
        version: '1.0-fallback',
      ),
      'marketing_communications': RemoteContent(
        title: 'Comunicazioni Marketing',
        content: '''# Consenso Comunicazioni Marketing

**Ultimo aggiornamento:** 25/06/2026

## Cosa Sono le Comunicazioni Marketing?
Le comunicazioni marketing includono:
- Newsletter con aggiornamenti dell'app SaveIn!
- Consigli per utilizzare meglio SaveIn
- Annunci di nuove funzionalità
- Offerte speciali, promo Premium, promo nuovi iscritti o cross-app con SmartChef (se disponibili)
- Sondaggi per migliorare l'app

## Frequenza
- Frequenza ragionevole e proporzionata
- Solo per aggiornamenti, promo o contenuti pertinenti
- Mai spam o contenuti irrilevanti

## I Tuoi Diritti
- ✅ **Consenso libero**: Puoi sempre dire no
- ✅ **Revoca facile**: Disiscriviti quando vuoi
- ✅ **Controllo completo**: Gestisci preferenze in app
- ✅ **Servizio separato**: Le notifiche necessarie ad account, sicurezza, condivisioni, promo attivate o abbonamento possono restare comunicazioni di servizio

## Come Disiscriverti
1. **In app**: Account → Marketing → Disattiva
2. **Email**: Click su "Unsubscribe" in ogni email
3. **Contatto diretto**: marketing@savein.app

## Cosa NON Facciamo
- ❌ Non vendiamo i tuoi dati
- ❌ Non inviamo spam
- ❌ Non condividiamo email con terzi
- ❌ Non ti bombardiamo di messaggi

## Contenuti Marketing
Le nostre comunicazioni includono solo:
- Aggiornamenti funzionalità SaveIn
- Tips per organizzare meglio i contenuti
- Novità e miglioramenti
- Feedback requests
- Promo Premium, banner in-app, offerte account e comunicazioni sull'ecosistema SaveIn!/SmartChef quando pertinenti

**Il consenso è sempre facoltativo e revocabile.**

---
*Contenuto locale di fallback*''',
        lastUpdated: DateTime.now().toIso8601String(),
        version: '1.0-fallback',
      ),
      'help_center': RemoteContent(
        title: 'Centro Assistenza',
        content: '''# Centro Assistenza SaveIn

## 🔧 Domande Frequenti

### Come creo una nuova cartella?
Premi il pulsante **+** nella home e seleziona "Nuova Cartella".

### Come sposto una cartella?
Premi sui **tre puntini** sulla cartella → **Sposta** → Scegli destinazione.

### Come salvo un link da altre app?
**Condividi** il link da qualsiasi app → Seleziona **SaveIn** → Scegli cartella.

### Come cerco i miei contenuti?
Usa la **barra di ricerca** in alto. Puoi cercare per:
- Nome cartella
- Titolo del contenuto
- #hashtags

### Come cambio tema?
**Account** → **Tema Scuro** → Attiva/Disattiva

### Come esporto i miei dati?
**Account** → **Statistiche** → Menu → **Esporta Dati**

## 🆘 Problemi Comuni

### L'app si blocca
1. Chiudi e riapri l'app
2. Riavvia il dispositivo
3. Se persiste, contattaci

### Non riesco a salvare contenuti
1. Verifica connessione internet
2. Controlla permessi app
3. Prova a riavviare l'app

### Ho perso i miei dati
I tuoi dati sono salvati localmente. Se hai abilitato il backup cloud, puoi ripristinarli.

## 📞 Contatti

**Email Support**: help@savein.app
**Response Time**: 24-48 ore
**Linguaggi**: Italiano, Inglese

**Bug Reports**: bugs@savein.app
**Feature Requests**: feedback@savein.app

---
*Contenuto locale di fallback*''',
        lastUpdated: DateTime.now().toIso8601String(),
        version: '1.0-fallback',
      ),
    };

    return defaultContents[contentType] ??
        RemoteContent(
          title: 'Contenuto Non Disponibile',
          content:
              'Questo contenuto non è attualmente disponibile. Verifica la connessione internet e riprova più tardi.',
          lastUpdated: DateTime.now().toIso8601String(),
          version: '1.0-fallback',
        );
  }
}
