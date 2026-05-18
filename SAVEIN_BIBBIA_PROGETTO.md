# SaveIn! - Bibbia del progetto

Questo documento serve come memoria tecnica e di prodotto. Prima di modificare SaveIn!, leggerlo per capire filosofia, flussi principali, vincoli e piattaforme usate.

## Identita e filosofia

SaveIn! e' un'app Flutter per salvare, organizzare e ritrovare contenuti da social e web. L'obiettivo e' rendere semplice l'import da link/condivisione, salvare una scheda pulita del contenuto e organizzarla in cartelle, tag e statistiche.

Principi guida:
- L'esperienza deve essere veloce: l'utente salva prima, i lavori pesanti avvengono in background quando possibile.
- I dati importanti devono essere in cloud, ma l'app deve usare cache locale per ridurre costi, traffico e attese.
- Le anteprime immagini sono utili, ma devono essere leggere: target attuale circa 100 KB per anteprima.
- Le limitazioni Free devono essere chiare e applicate centralmente, non sparse nella UI.
- Il backend admin deve essere leggibile, pratico e pensato per gestione utenti, ruoli, accessi, costi e statistiche.

## Nome prodotto e rebrand

Nome visibile: **SaveIn!** (con punto esclamativo).

Il progetto nasceva come SaveIt. Il rebrand visibile e' stato fatto in due fasi:
1. SaveIt → SaveIn (primo rebrand)
2. SaveIn → SaveIn! (secondo rebrand, maggio 2026 — aggiunto "!" ovunque: UI, email, titoli app, stringhe visibili)

Alcuni identificativi tecnici restano volutamente invariati per non rompere Firebase/Auth/app gia configurate.

Identificativi tecnici ancora legacy:
- Firebase project ID: `saveit-app-1784d`
- Android package: `com.example.saveit`
- iOS bundle ID: `com.example.saveit`
- Firebase auth domain: `saveit-app-1784d.firebaseapp.com`
- Firebase storage bucket: `saveit-app-1784d.firebasestorage.app`

Non rinominare questi identificativi senza una migrazione pianificata.

## Piattaforme e progetti

Firebase:
- Project ID: `saveit-app-1784d`
- Project number / sender ID: `776660339631`
- Web app ID: `1:776660339631:web:57dddde13817a4af9e7d5a`
- Android app ID: `1:776660339631:android:ade29338a88973319e7d5a`
- iOS/macOS app ID: `1:776660339631:ios:016628f9f46386629e7d5a`
- Storage bucket: `saveit-app-1784d.firebasestorage.app`
- Hosting public folder: `build/web`
- Firestore rules file: `firestore.rules`

Dominio:
- Dominio previsto: `savein.eu`
- Hosting: Firebase Hosting con dominio acquistato/gestito su Aruba
- Admin panel: `https://savein.eu/admin`
- Fallback admin: `https://savein.eu/?admin=1`

Firebase Auth:
- Authorized domains da mantenere: `savein.eu`, `www.savein.eu`, piu domini Firebase standard.

Deploy web:
```powershell
flutter build web --release --base-href /; if ($LASTEXITCODE -eq 0) { firebase deploy --only hosting }
```

## Stack tecnico

Framework:
- Flutter / Dart
- App mobile + web admin nello stesso progetto

Servizi Firebase:
- Firebase Auth: login utente
- Cloud Firestore: utenti, post, cartelle, log admin, analytics sincronizzate
- Firebase Storage: backup remoto anteprime immagini
- Firebase Hosting: pubblicazione web/admin

Dipendenze importanti:
- `cloud_firestore`
- `firebase_auth`
- `firebase_storage`
- `firebase_core`
- `cached_network_image`
- `path_provider`
- `image`
- `google_mobile_ads`
- `receive_sharing_intent`
- `http`, `html`, `universal_html`

## Modello dati principale

Collezione Firestore:
- `users/{userId}`

Campi importanti utente:
- `name`
- `email`
- `username`
- `role`: ruolo app, valori `free`, `premium`, `admin`
- `dashboardRole`: ruolo accesso dashboard, valori `none`, `author`, `editor`, `admin`
- `isBlocked`
- `blockedReason`
- `blockedAt`
- `createdAt`
- `lastLogin`

Subcollezioni:
- `users/{userId}/posts`
- `users/{userId}/folders`
- `users/{userId}/analytics/summary`

Collezioni globali:
- `admin_logs`
- `dashboard_accesses`: accessi backend separati dagli utenti app, indicizzati per email normalizzata

Post salvato:
- `url`
- `title`
- `description`
- `imageUrl`: URL originale/metadati
- `previewStorageUrl`: URL anteprima salvata su Firebase Storage
- `tags`
- `folderId`
- `createdAt`
- `updatedAt`

Cartella:
- `name`
- `color`
- `parentId`: null per root, valorizzato per sottocartelle
- `isDefault`
- `createdAt`
- `updatedAt`

## Ruoli app

Ruoli utente dell'app:
- `Free`: limiti attivi, pubblicita, feature ridotte
- `Premium`: limiti rimossi e niente pubblicita
- `Admin`: come Premium, senza pagamento, non attivabile dall'utente

Limiti Free attuali:
- massimo 10 cartelle root
- profondita: home + 1 livello
- massimo 4 sottocartelle per cartella
- niente hashtag manuali
- annunci interstitial: prima apertura giornaliera e ogni 5 import post

Il passaggio Free/Premium e' disponibile nella pagina account. L'utente non deve potersi assegnare Admin.

## Ruoli dashboard

I ruoli dashboard sono separati dai ruoli app. Gli accessi operativi alla dashboard sono gestiti nella collezione `dashboard_accesses`, quindi possono esistere persone abilitate al backend che non sono utenti Free/Premium dell'app.

Valori:
- `none`: nessun accesso backend
- `author`: accesso sola lettura
- `editor`: puo vedere e bloccare/sbloccare utenti, ma non cambiare ruoli app o accessi dashboard
- `admin`: pieno controllo

Un utente con ruolo app `admin` ottiene dashboard role effettivo `admin`.

Record `dashboard_accesses/{normalizedEmail}`:
- `email`
- `normalizedEmail`
- `dashboardRole`
- `createdAt`
- `updatedAt`
- `updatedBy`
- `updatedByEmail`

Per accedere alla dashboard, l'email usata in Firebase Auth deve essere presente in `dashboard_accesses` con ruolo `author`, `editor` o `admin`, oppure l'utente deve essere un admin app legacy. Nella lista accessi deve esserci sempre almeno un accesso `admin`.

## Admin backend

File principale:
- `lib/pages/admin_dashboard_page.dart`

Sezioni:
- Utenti
- Dettaglio utente
- Post salvati utente
- Cartelle utente
- Piani Free/Premium
- Costi/Ricavi
- Accessi dashboard: gestisce `dashboard_accesses`, non la lista utenti app

Vincoli UI:
- Liste paginate a 20 elementi
- Tabella utenti e filtri devono occupare tutta la larghezza del contenitore
- Dettaglio utente in pagina dedicata, non pannello laterale
- Post: elenco titoli, filtro per provenienza/social/sito
- Cartelle: espandibili, con sottocartelle e post

## Import post e metadati

Servizio principale:
- `lib/url_metadata_service.dart`

Obiettivo:
- estrarre titolo, descrizione, immagine e metadati da URL social/web

Note importanti:
- Instagram puo non fornire `og:image`; sono stati aggiunti fallback su embed e filtri per evitare avatar profilo.
- TikTok puo mostrare pagina login; usare oEmbed/fallback dedicati per evitare titolo "log in tiktok" e immagini generiche.
- Le immagini esterne possono scadere, quindi quando possibile si crea una anteprima locale e un backup remoto.

## Cache anteprime immagini

File principali:
- `lib/services/post_preview_cache_io.dart`
- `lib/services/post_preview_remote_storage_io.dart`
- `lib/widgets/post_preview_image_io.dart`
- `lib/data_service.dart`

Regole attuali:
- La UI usa prima cache locale.
- Se manca cache locale, scarica da `previewStorageUrl`; se manca/fallisce, prova `imageUrl`.
- Quando salva un post, l'app prova a salvare anteprima locale e backup su Firebase Storage.
- Il backup remoto non e' limitato a Instagram.
- La compressione target e' circa 100 KB.
- Dimensione massima lunga: 512 px; fallback 384/320 px se serve.
- I download simultanei per lo stesso `postId` vengono deduplicati.
- Firebase Storage usa `Cache-Control: public,max-age=31536000`.

Nota: su web il widget usa cache HTTP/browser tramite `cached_network_image`; la cache filesystem e' per piattaforme `dart:io`.

## Costi e quote

La pagina `Costi/Ricavi` e' una simulazione mensile. Usa utenti reali Free/Premium da Firestore e parametri modificabili.

Parametri:
- costi fissi mensili
- costo medio utente Free
- costo medio utente Premium
- prezzo Premium
- ricavo ads medio Free
- commissioni pagamenti/store

Calcoli principali:
- Ricavi Premium = Premium * prezzo Premium
- Ricavi ads = Free * ricavo ads medio
- Costi utenza = Free * costo Free + Premium * costo Premium
- Commissioni = Ricavi Premium * percentuale commissioni
- Guadagno = ricavi totali - costi totali
- ARPU = ricavi totali / utenti totali
- Break-even Premium = utenti Premium necessari per coprire costi fissi, costi Free e commissioni

Anteprime immagini:
- target corrente: 100 KB per immagine
- Storage Firebase gratuito considerato: 5 GB
- Download Firebase Storage considerato: 100 GB/mese
- Upload operations considerate: 5.000/mese
- Firestore writes gratuite considerate: 20.000/giorno

Esempio dinopasi:
- 638 post
- 638 immagini stimate a 100 KB
- circa 62 MB storage immagini
- circa 1,2% di 5 GB gratuiti
- costo previsto dentro quota: 0 EUR

## Sicurezza Firestore

File:
- `firestore.rules`

Regole logiche:
- Gli utenti gestiscono i propri dati.
- Dashboard viewer legge dati admin.
- Editor puo bloccare/sbloccare utenti ma non modificare ruoli.
- Admin dashboard puo gestire accessi e ruoli.
- Gli utenti non devono potersi auto-assegnare campi admin/dashboard.

Ogni modifica a ruoli/campi sensibili deve essere allineata a `firestore.rules`.

Deploy regole:
```powershell
firebase deploy --only firestore:rules
```

## Pubblicita

Servizio:
- `lib/services/interstitial_ad_service.dart`

Logica:
- Solo utenti Free.
- Annuncio a prima apertura giornaliera.
- Annuncio ogni 5 import post.
- Premium/Admin non devono vedere annunci.

Config native:
- Android: `android/app/src/main/AndroidManifest.xml`
- iOS: `ios/Runner/Info.plist`

## Analytics e statistiche

Servizi:
- `lib/services/simple_analytics_service.dart`
- `lib/advanced_analytics_service.dart`

La dashboard legge statistiche cloud e riepiloghi sincronizzati in:
- `users/{userId}/analytics/summary`

Statistiche admin utente:
- post totali/periodo
- cartelle totali/periodo
- hashtag unici
- domini/social piu salvati
- cartelle piu usate
- post per mese
- ultimi post
- analytics app sincronizzate quando disponibili

## File chiave

App:
- `lib/main.dart`
- `lib/pages/auth_wrapper.dart`
- `lib/pages/account_page.dart`
- `lib/data_service.dart`
- `lib/models.dart`

Backend/admin:
- `lib/pages/admin_dashboard_page.dart`
- `lib/services/auth_service.dart`
- `firestore.rules`

Import/contenuti:
- `lib/url_metadata_service.dart`
- `lib/services/sharing_service.dart`
- `lib/services/remote_content_service.dart`

Cartelle:
- `lib/services/folder_service_crud.dart`
- `lib/services/firebase_data_service.dart`
- `lib/pages/folder_detail_page.dart`

Anteprime:
- `lib/services/post_preview_cache_io.dart`
- `lib/services/post_preview_remote_storage_io.dart`
- `lib/widgets/post_preview_image_io.dart`

Deploy:
- `firebase.json`
- `.firebaserc`
- `FIREBASE_HOSTING_ARUBA.md`
- `ARUBA_DEPLOY_CHECKLIST.md`

## Comandi utili

Build web:
```powershell
flutter build web --release --base-href /
```

Build + deploy hosting:
```powershell
flutter build web --release --base-href /; if ($LASTEXITCODE -eq 0) { firebase deploy --only hosting }
```

Deploy solo hosting:
```powershell
firebase deploy --only hosting
```

Deploy regole Firestore:
```powershell
firebase deploy --only firestore:rules
```

Format Dart:
```powershell
dart format lib
```

## Problemi risolti e lezioni apprese

### 2026-05-07 - Home vuota / buffering infinito / solo cartella "Tutti" all'avvio

Sintomi:
- All'apertura app la home restava in caricamento oppure mostrava solo la cartella `Tutti`.
- L'account aveva molti post: i log confermavano `641 posts` caricati da Firestore.
- Le cartelle comparivano subito facendo pull-to-refresh.

Indizi dai log:
- `getPosts()` completava correttamente.
- Subito dopo `getFolders()` restituiva `0 cartelle`.
- Il pull-to-refresh funzionava perche' esegue:
```dart
await DataService.instance.reloadFromDisk();
await _folderService.forceRefreshFromDataService();
```

Cause tecniche:
- In `lib/data_service.dart` la cache utente usava un solo timestamp (`_cacheTimestamps`) sia per post sia per cartelle.
- Dopo il caricamento dei post, `_updateUserCache(userId, null, posts)` aggiornava il timestamp utente.
- Alla chiamata successiva `getFolders()` vedeva il timestamp valido e usava il fallback cache, ma `_userFoldersCache[userId]` non era ancora popolata, quindi ritornava lista vuota.
- Con `0` cartelle reali e `641` post, la sincronizzazione in `FolderService` ricostruiva solo `Tutti` e poi falliva con `Bad state: No element` durante l'associazione post-cartelle.
- Problema collegato gia corretto: nei request-collapsing futures di `getPosts()`/`getFolders()`, non usare `whenComplete(() => map.remove(key))`, perche' `remove()` restituisce il future rimosso e puo creare auto-attesa. Usare blocco `void`.

Fix applicata:
- Aggiunta validazione separata della cache cartelle:
```dart
bool _isFoldersCacheValid(String userId) {
  final folders = _userFoldersCache[userId];
  if (folders == null || folders.isEmpty) return false;
  return _isUserCacheValid(userId);
}
```
- `getFolders()` ora abilita la cache solo se la cache cartelle esiste davvero:
```dart
allowCache: !forceRefresh && _isFoldersCacheValid(userId),
```
- I `whenComplete` dei future in-flight usano blocco `void`:
```dart
.whenComplete(() { _foldersInFlight.remove(requestKey); });
.whenComplete(() { _postsInFlight.remove(requestKey); });
```

Regola futura:
- Non usare un solo timestamp come prova che tutte le cache dell'utente siano valide. Ogni cache derivata (`folders`, `posts`, eventuali analytics) deve verificare anche l'esistenza del proprio payload.
- Se un flusso funziona solo dopo pull-to-refresh, confrontare sempre cosa fa il refresh rispetto allo startup: spesso la differenza e' invalidazione cache + force reload.

## Email automatiche e SMTP

Guida dettagliata setup Aruba: `ARUBA_EMAIL_SETUP.md`

Caselle email su savein.eu (create su Aruba):
- `noreply@savein.eu`: mittente di tutte le email automatiche
- `support@savein.eu`: riceve i messaggi di supporto dagli utenti

### Provider SMTP attivo: Brevo

Il provider di invio email e' **Brevo** (ex Sendinblue), scelto per l'alta deliverability verso tutti i client, incluso Hotmail/Outlook.

Motivazione del cambio da Aruba a Brevo:
- Le email da dominio `.eu` nuovo (savein.eu) tramite Aruba SMTP venivano bloccate da Hotmail/Outlook.
- Aruba e' un servizio shared SMTP: impossibile registrare gli IP su Microsoft SNDS/JMRP per sblocco IP.
- Brevo offre piano gratuito (300 email/giorno) con IP con buona reputazione e autenticazione DKIM gestita.

Configurazione Brevo in `functions/.env`:
```
EMAIL_HOST=smtp-relay.brevo.com
EMAIL_PORT=587
EMAIL_SECURE=false
EMAIL_USER=aaed1e001@smtp-brevo.com
EMAIL_PASSWORD=<SMTP key Brevo>
EMAIL_FROM=SaveIn! <noreply@savein.eu>
SUPPORT_EMAIL=support@savein.eu
```

Variabili ambiente in `functions/.env`:
- `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_SECURE`
- `EMAIL_USER`, `EMAIL_PASSWORD`, `EMAIL_FROM`
- `SUPPORT_EMAIL`
- `APP_BASE_URL`: URL base dell'app usato nel template email per i loghi e i link del footer (default: `https://savein.eu`)

Cloud Functions email disponibili (`functions/index.js`):
- `sendContactEmail`: riceve messaggio utente → invia a support@savein.eu + auto-risposta all'utente. Usa `onCall` v2 con `request.auth`.
- `sendWelcomeEmail`: triggered su Firebase Auth `onCreate` (v1 trigger) → invia email di benvenuto al nuovo iscritto e notifica a support.
- `sendPasswordResetEmail`: callable pubblica → genera link reset via `admin.auth().generatePasswordResetLink()` + invia email brandizzata.
- `sendBulkEmail`: callable admin → invia email personalizzata a lista utenti selezionati dalla dashboard.

Firebase Auth password reset:
- NON usare `FirebaseAuth.sendPasswordResetEmail()` direttamente: non usa il dominio savein.eu.
- Usare la Cloud Function `sendPasswordResetEmail` (us-central1) che:
  1. Genera il link tramite `admin.auth().generatePasswordResetLink()`
  2. Invia l'email da `noreply@savein.eu` via Brevo SMTP con template brandizzato SaveIn!
- In Flutter: `AuthService().sendPasswordResetEmail(email)` chiama gia la Cloud Function
- Chiamata nel login: `login_page.dart` → `_showForgotPasswordDialog()` → pulsante "Invia"
- La Cloud Function `sendPasswordResetEmail` richiede accesso pubblico non autenticato (configurato manualmente in Google Cloud Console → Cloud Run → Security → "Consenti accesso pubblico")

Risposta automatica Aruba (lato server mailbox):
- Su Aruba e' configurata risposta automatica su `support@savein.eu` per tutti i messaggi in arrivo
- Tutte le caselle Aruba inoltrano a `support@savein.eu`

Deploy functions dopo modifiche `.env`:
```powershell
firebase deploy --only functions
```

### Template email unificato

Tutte le email usano un unico template HTML branded definito in `buildEmailHtml()` dentro `functions/index.js`.

Struttura del template:
- **Header**: sfondo bianco con logo `SaveIn!_old.png` centrato a larghezza piena (`web/email-assets/logo-full.png`)
- **Body**: sfondo bianco, titolo + contenuto
- **Footer**: sfondo grigio chiaro con:
  - "Hai ricevuto questa email perché sei registrato su SaveIn!"
  - Link assistenza `support@savein.eu`
  - Link "Gestisci le preferenze" → `APP_BASE_URL/account` (Account > Notifiche nell'app)
  - Link a savein.eu · Supporto · Privacy · Termini
  - Copyright © anno corrente SaveIn!

Asset logo email:
- `web/email-assets/logo-full.png` → copia di `assets/icon/SaveIn!_old.png`
- `web/email-assets/icon.png` → copia di `assets/icon/SaveIt - icon .png` (non più usato nell'header attuale)
- `web/email-assets/name.png` → copia di `assets/icon/SaveIn!.png` (non più usato nell'header attuale)

Per aggiornare il logo nelle email:
1. Sostituire `web/email-assets/logo-full.png` con la nuova immagine
2. `flutter build web --release`
3. `firebase deploy --only hosting`

Per aggiornare il template testo/stile:
1. Modificare `buildEmailHtml()` in `functions/index.js`
2. `firebase deploy --only functions`

Microsoft (Outlook/Hotmail) adotta dal 5 maggio 2025 gli stessi standard DKIM/DMARC di Gmail/Yahoo. Il dominio `savein.eu` è già autenticato su Brevo con tutti i record richiesti.

> **Stato attuale (maggio 2026): tutto funzionante e testato.**
> - Reset password: email arriva in inbox (anche Hotmail) ✅
> - Modulo contatti: messaggio arriva a support@savein.eu + auto-risposta all'utente ✅
> - Welcome email: inviata a ogni nuovo iscritto ✅
> - Dominio `savein.eu` autenticato su Brevo (DKIM + SPF + DMARC) ✅
> - Template email unificato con logo e footer branded ✅

### 2026-05-08 - Ruolo Admin mostrava limitazioni Free (tag manuali bloccati)

Sintomi:
- Un utente con ruolo `admin` assegnato tramite dashboard vedeva le limitazioni Free nell'app (es. tag manuali disabilitati durante l'import).
- La pagina Account mostrava correttamente "Admin" ma `AppAccessService.canManageManualTags` restituiva `false`.

Causa:
- `_loadMarketingConsentFromFirestore()` in `auth_service.dart` era commentata (`// TEST: Disabilitato temporaneamente`) in due punti: `_loadUserData()` e `reloadCurrentUserFromFirestore()`.
- Questa funzione è l'unica che sincronizza il ruolo da Firestore a SharedPreferences locale.
- Quando un admin assegna un ruolo ad altro utente (`_assignRoleToUserDocument`), aggiorna Firestore ma salva in locale SOLO se `userId == _currentUser!.id` (stesso dispositivo). Il dispositivo del target non veniva mai aggiornato.
- Senza sync, il dispositivo leggeva `role: free` dalla cache locale → `isFree = true` → `canManageManualTags = false`.

Fix applicata:
- Riabilitato `await _loadMarketingConsentFromFirestore()` in `_loadUserData()` (chiamato durante `initialize()` all'avvio app).
- Riabilitato `await _loadMarketingConsentFromFirestore(forceRefresh: true)` in `reloadCurrentUserFromFirestore()`.
- Il ruolo viene ora sempre sincronizzato da Firestore prima che qualsiasi UI venga mostrata.

Regola futura:
- Non commentare mai `_loadMarketingConsentFromFirestore()`: è il meccanismo di sincronizzazione del ruolo cross-device. Se causa lentezza all'avvio, ottimizzare il timeout Firestore, non disabilitarlo.

---

### 2026-05-08 - Anteprima TikTok: titolo corretto ma immagine non mostrata

Sintomi:
- Dopo il fix oEmbed, il titolo TikTok arrivava correttamente ma l'immagine di anteprima non compariva.

Causa:
- Le thumbnail CDN TikTok (es. `p16-sign.tiktokcdn-us.com`, `p77-sign-sg.tiktokcdn.com`) usano estensioni non standard come `~noop.image` o `~tplv-tiktokx-origin.image`.
- `_isValidImageUrl()` in `url_metadata_service.dart` rifiutava questi URL perché l'estensione non era in lista e il dominio non conteneva `tiktok.com/video/`.
- Di conseguenza `_hasUsableTikTokImage()` restituiva `false` e l'immagine veniva scartata.

Fix applicata:
- In `_hasUsableTikTokImage()`: se l'URL contiene `tiktokcdn`, accettato direttamente senza passare da `_isValidImageUrl()`.
- In `_isSocialMediaImage()`: aggiunta regola `if (lowerUrl.contains('tiktokcdn')) return true`.

---

### 2026-05-07 - Overflow UI pagina account (4px)

Sintomi:
- `RenderFlex overflowed by 4.0 pixels on the right` nella pagina account su mobile.

Fix applicata:
- In `lib/pages/account_page.dart`, il `Row` nel `trailing` del `ListTile` e' stato avvolto in `SizedBox(width: 96)` con margini interni aggiustati.

---

### 2026-05-07 - Overflow UI dialog "Password Dimenticata" (22px)

Sintomi:
- `RenderFlex overflowed by 22 pixels on the right` nel titolo del dialog password dimenticata in `login_page.dart`.

Fix applicata:
- Il widget `Text` nel titolo `Row` del dialog e' stato avvolto in `Expanded` sia nel dialog "Password Dimenticata" che in quello "Email Inviata!".

---

### 2026-05-07 - Pulsante invio bianco durante caricamento

Sintomi:
- In `contact_page.dart` e `login_page.dart`, durante il caricamento il pulsante diventava bianco con testo bianco illeggibile.

Fix applicata:
- Aggiunto `disabledBackgroundColor: Colors.blue.withOpacity(0.6)` e `disabledForegroundColor: Colors.black` su `ElevatedButton.styleFrom`.
- `CircularProgressIndicator` impostato a `color: Colors.black`.

---

### 2026-05-07 - sendContactEmail restituiva "devi essere autenticato" anche da loggato

Causa:
- `sendContactEmail` usava l'API v1 (`functions.https.onCall`) che legge `context.auth`.
- Il progetto usa Firebase Functions v2 nel resto del codice; la chiamata Flutter passava il token ma il contesto v1 non lo leggeva correttamente.

Fix applicata:
- Convertito `sendContactEmail` in `functions/index.js` da `functions.https.onCall` (v1) a `onCall` (v2).
- Autenticazione letta da `request.auth` invece di `context.auth`.
- `HttpsError` importato da `firebase-functions/v2/https`.

---

### 2026-05-07 - Email reset password bloccate da Hotmail/Outlook

Causa:
- Dominio `savein.eu` nuovo, nessuna reputazione di invio.
- Aruba usa IP condivisi: impossibile registrarli su Microsoft SNDS/JMRP perche' il richiedente deve possedere gli IP.
- Gmail riceveva correttamente, Hotmail bloccava silenziosamente.

Fix applicata:
- Migrazione SMTP da Aruba a **Brevo**: IP con buona reputazione, autenticazione gestita, piano gratuito 300 email/giorno.
- Aggiornato `functions/.env` con credenziali Brevo (`smtp-relay.brevo.com`, porta 587).
- Aggiunto record DMARC su Aruba DNS: `v=DMARC1; p=none; rua=mailto:support@savein.eu`.

---

### 2026-05-07 - Cloud Function sendPasswordResetEmail: "The request was not authenticated"

Causa:
- Le Cloud Functions v2 richiedono autenticazione Firebase per default.
- La chiamata da Flutter avviene prima del login (utente non autenticato).

Fix applicata:
- Aggiunto `{ invoker: "public" }` nella definizione della funzione in `functions/index.js`.
- Configurato manualmente in Google Cloud Console: Cloud Run → servizio `sendpasswordresetemail` → Security → "Consenti accesso pubblico" (Allure Users).
- Nota: la configurazione via codice con `invoker: "public"` non sempre si propaga automaticamente al primo deploy; il passaggio manuale da Console e' spesso necessario.

---

### 2026-05-07 - sendWelcomeEmail: TypeError "Cannot read properties of undefined (reading 'user')"

Causa:
- `sendWelcomeEmail` usava `functions.auth.user().onCreate(...)` dove `functions` era importato da `firebase-functions/v2`.
- Il trigger Auth `.auth.user().onCreate` esiste solo nell'API v1.

Fix applicata:
- Aggiunto import esplicito v1:
```js
const functionsV1 = require("firebase-functions/v1");
```
- Il trigger ora usa `functionsV1.auth.user().onCreate(...)`.
- Le altre funzioni callable (`sendContactEmail`, `sendPasswordResetEmail`, `sendBulkEmail`) restano su v2.

---

## Play Store e distribuzione Android

### Configurazione firma app

Keystore release creato in `android/savein-release.jks`:
- Alias: `savein`
- Validità: 10.000 giorni
- Algoritmo: RSA 2048 / SHA256withRSA

Credenziali in `android/key.properties` (escluso da git tramite `.gitignore`):
```
storePassword=<password>
keyPassword=<password>
keyAlias=savein
storeFile=../savein-release.jks
```

Il file `android/app/build.gradle` usa `signingConfigs.release` per i build release.

> **IMPORTANTE: non perdere mai `savein-release.jks` e la sua password. Senza di essi è impossibile pubblicare aggiornamenti su Play Store.**

### Identificatori app

- **applicationId**: `eu.savein.app` (cambiato da `com.example.saveit` perché già occupato su Play Store)
- **Package Play Store**: `eu.savein.app`
- Il `google-services.json` è stato aggiornato su Firebase Console con il nuovo package name

### Build release Android

```powershell
flutter build appbundle --release
```
Output: `build\app\outputs\bundle\release\app-release.aab`

### Play Store — stato attuale (maggio 2026)

- App creata su Play Console: `SaveIn!` — package `eu.savein.app`
- Release di test interno: pubblicata ✅
- Configurazione app: in corso (scheda store, classificazione, privacy)
- Test chiuso: da completare (richiede 12 tester per 14 giorni)
- Produzione: da richiedere dopo test chiuso

Per arrivare in produzione Google richiede:
1. Completare configurazione scheda store
2. Test chiuso con almeno 12 tester per 14 giorni
3. Richiedere accesso alla produzione

### Privacy Policy

La Privacy Policy è pubblicata come pagina HTML su GitHub Pages:
- **URL pubblico**: `https://dinus85.github.io/saveit-legal-content/privacy.html`
- **Repository**: `github.com/Dinus85/saveit-legal-content`
- **File sorgente**: `privacy.html` nella root del repo
- Aggiornare il file su GitHub per modificare la policy (GitHub Pages si aggiorna automaticamente)

Il file HTML locale di riferimento è `privacy.html` nella root del progetto Flutter.

### Google AdMob

- **App ID Android**: `ca-app-pub-1397392558961350~2159050629`
- **Interstitial Android**: `ca-app-pub-1397392558961350/5839880574`
- **Banner Android**: `ca-app-pub-1397392558961350/4746290759`
- iOS: usa ancora gli ID di test Google — da aggiornare quando si crea l'app iOS su AdMob

Configurazione nei file:
- App ID → `android/app/src/main/AndroidManifest.xml`
- Ad Unit IDs → `lib/services/interstitial_ad_service.dart`

Logica ads:
- Solo utenti Free (`AppAccessService().hasAds`)
- **Interstitial**: mostrato prima di apertura post remindato e ogni 5 import
- **Banner**: mostrato nella home ogni 4 cartelle (dopo la 4ª, 8ª, 12ª...) tramite `BannerAdWidget` in `lib/widgets/banner_ad_widget.dart`

L'account AdMob è in attesa di approvazione Google (fino a 24h, dipende dalla pubblicazione su Play Store).

---

## Avvertenze per modifiche future

- Non cambiare project ID Firebase, package Android o bundle iOS senza piano di migrazione.
- Non duplicare logiche ruoli: usare `AuthService` e funzioni esistenti.
- Non bypassare `AppAccessService` per limiti Free/Premium.
- Non caricare immagini grandi: mantenere target anteprime leggero.
- Non fare query Firestore troppo pesanti nelle schermate frequenti dell'app utente.
- La dashboard admin puo fare query piu ampie, ma deve restare paginata e leggibile.
- Dopo modifiche admin/web, fare sempre build web prima del deploy.
- Il nome visibile dell'app e' **SaveIn!** (con "!"): non usare "SaveIn" senza punto esclamativo in stringhe visibili, email, titoli, UI. Gli identificativi tecnici (package, bundle, project ID) restano invariati.
- Non sostituire Brevo con Aruba SMTP per l'invio email: Aruba su domini `.eu` nuovi viene bloccato da Hotmail/Outlook.
- Le Cloud Functions callable che devono essere chiamate da utenti non autenticati (es. reset password) richiedono `{ invoker: "public" }` nel codice + configurazione manuale "Consenti accesso pubblico" in Google Cloud Console → Cloud Run.
- I trigger Firebase Auth (es. `sendWelcomeEmail`) devono usare `firebase-functions/v1`, non v2.
- Non commentare `_loadMarketingConsentFromFirestore()` in `auth_service.dart`: è il meccanismo di sync ruolo da Firestore. Senza di essa, utenti il cui ruolo è cambiato dall'admin dashboard vedranno il ruolo vecchio dalla cache locale.
- Il logo nelle email è `web/email-assets/logo-full.png` (servito da Firebase Hosting). Per aggiornarlo: sostituire il file, `flutter build web --release`, `firebase deploy --only hosting`. Non modificare `buildEmailHtml` solo per cambiare l'immagine.
- `assets/images/` deve esistere anche se vuota: è referenziata in `pubspec.yaml`. Non eliminarla.
- L'`applicationId` Android è `eu.savein.app` — non cambiarlo, è registrato su Play Store e Firebase. Cambiarlo richiederebbe una nuova app su Play Store.
- Non perdere `android/savein-release.jks` e la sua password: senza di essi è impossibile pubblicare aggiornamenti su Play Store.
- La Privacy Policy pubblica è su GitHub Pages (`dinus85.github.io/saveit-legal-content/privacy.html`). Per aggiornarla modificare `privacy.html` nel repo `Dinus85/saveit-legal-content`.
- Per aggiornare gli ID AdMob iOS, creare l'app su AdMob per iOS e sostituire gli ID di test in `interstitial_ad_service.dart` e `ios/Runner/Info.plist`.