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
- Android package / Play Store package: `eu.savein.app`
- iOS bundle ID: `eu.savein.app`
- Firebase auth domain: `saveit-app-1784d.firebaseapp.com`
- Firebase storage bucket: `saveit-app-1784d.firebasestorage.app`

Non rinominare questi identificativi senza una migrazione pianificata.

## Piattaforme e progetti

Firebase:
- Project ID: `saveit-app-1784d`
- Project number / sender ID: `776660339631`
- Web app ID: `1:776660339631:web:57dddde13817a4af9e7d5a`
- Android app ID: `1:776660339631:android:ade29338a88973319e7d5a`
- iOS app ID: `1:776660339631:ios:ac36b2aba03689b49e7d5a`
- macOS app ID legacy: `1:776660339631:ios:016628f9f46386629e7d5a`
- Storage bucket: `saveit-app-1784d.firebasestorage.app`
- Hosting public folder: `build/web`
- Firestore rules file: `firestore.rules`

Dominio:
- Dominio previsto: `savein.eu`
- Hosting: Firebase Hosting con dominio acquistato/gestito su Aruba
- Admin panel: `https://savein.eu/admin`
- Fallback admin: `https://savein.eu/?admin=1`
- **Pagine statiche App Store Connect (lug 2026)**: pubblicate su Firebase Hosting in `web/` e incluse nel build Flutter web:
  - **Assistenza**: https://savein.eu/support.html — email `support@savein.eu`, FAQ base
  - **Marketing**: https://savein.eu/marketing.html — presentazione app + link Play Store (`eu.savein.app`)
  - I file in `web/` vengono copiati in `build/web` e serviti prima del rewrite catch-all su `index.html`

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
- `premiumUntil`: scadenza Premium opzionale. Se `role=premium` e la data e' futura, l'utente e' Premium; se manca, Premium e' senza scadenza; se e' passata, l'app lo considera Free.
- `premiumSource`: origine Premium (`admin_dashboard`, `new_signup_promo`, `cross_promo_*`, ecc.)
- `dashboardRole`: ruolo accesso dashboard, valori `none`, `author`, `editor`, `admin`
- `birthDate`: data di nascita (Timestamp), usata per sconti e regali
- `gender`: sesso (maschio, femmina, preferisco non dirlo)
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
- `global_posts/{urlHash}`: **DB comune metadati post** per deduplicazione cross-utente (vedi sezione Import)

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
- `isShared`: `true` per post importati da condivisione SaveIn o da share intent social
- `globalPostId`: ID documento in `global_posts` (uguale a `urlHash`)
- `urlHash`: SHA-256 dell'URL normalizzato
- `normalizedUrl`: URL canonico usato per il dedup

Cartella:
- `name`
- `color`
- `parentId`: null per root, valorizzato per sottocartelle
- `isDefault`
- `createdAt`
- `updatedAt`

## Ruoli app

Ruoli utente dell'app:
- `Free`: limiti e feature configurati dalla dashboard, pubblicita, feature ridotte
- `Premium`: limiti e feature configurati dalla dashboard per il tier Premium, niente pubblicita
- `Admin`: come Premium, senza pagamento, non attivabile dall'utente

I limiti non devono essere hardcoded come fonte di verita': la pagina `Limiti Funzioni` della dashboard comanda sempre su Firestore `config/plan_limits.featureRules`, sia per Free sia per Premium.

Feature rule principali:
- `root_folders`: numero massimo di cartelle nella Home.
- `child_folders`: numero massimo di sottocartelle dirette per cartella.
- `folder_levels`: profondita massima della gerarchia cartelle.
- `manual_tags`: abilita/disabilita tag manuali.
- `share_folder`: abilita e limita condivisione cartelle.
- `share_post`: abilita e limita condivisione post.
- `import_shared`: abilita e limita import di contenuti condivisi.

Regole importanti:
- `limit <= 0` significa illimitato per quel tier.
- `enabled=false` disabilita la funzione per quel tier e deve mostrare popup/upsell coerente, non errore generico.
- Admin non ha limiti di utilizzo.
- Free e Premium leggono sempre la rispettiva colonna dalla dashboard. Non assumere che Premium sia sempre illimitato: se la dashboard imposta un limite Premium, l'app deve applicarlo.
- `PlanLimitsService` deve aggiornare il profilo utente da Firestore prima di scegliere il tier, cosi un cambio Free/Premium fatto dalla dashboard viene capito dall'app anche se era gia aperta.
- `AuthService` mantiene un listener live su `users/{uid}`: `role`, `premiumUntil` e `premiumSource` devono restare sincronizzati con Firestore. Non usare la cache locale come fonte di verita per i limiti.
- Per `root_folders` il controllo deve usare il conteggio reale delle cartelle Home, non un contatore `feature_usage`.
- Annunci interstitial: prima apertura giornaliera, ogni 5 import post, prima di impostare un reminder e prima di aprire un reminder da notifica/popup per utenti Free. Premium/Admin non vedono pubblicita.

Il passaggio Free/Premium e' disponibile nella pagina account. L'utente non deve potersi assegnare Admin.

### Comportamento al cambio piano Premium/Free

Quando un utente Premium torna al piano Free mantiene la piena visibilita' di tutte le cartelle create in precedenza (incluse quelle piu' profonde o in numero superiore ai limiti Free). Non viene eliminato nulla.

Quando un utente passa da Free a Premium dalla dashboard, l'app deve aggiornare il profilo locale da Firestore e usare immediatamente le regole Premium di `config/plan_limits`. Se continua a usare le regole Free, controllare `AuthService.reloadCurrentUserFromFirestore()`, il listener su `users/{uid}` e `_currentTier()` in `PlanLimitsService`.

Tuttavia non puo' piu' eseguire operazioni che superino i limiti Free:

- **Creare** nuove cartelle root oltre il limite di 10 o sottocartelle oltre il livello 1 → bloccato da `AppAccessService` in `folder_service_crud.dart`
- **Salvare/importare** un nuovo post in una cartella di livello > 1 → bloccato da `validateFolderDestination` in `sharing_service.dart`
- **Spostare** un post esistente in una cartella di livello > 1 → bloccato da `validateFolderDestination` all'inizio di `movePost` in `folder_service_crud.dart`

Nel `FolderCardSelector` (picker cartella durante l'import da share intent):

- Le cartelle oltre il limite Free sono grigie (opacita' 45%) con badge **"Premium"** e non selezionabili; tap → SnackBar upgrade.
- **Durante l'import post** (`showFolderLimitInfo: false`): **non** mostrare in basso conteggio/limiti livelli cartelle (banner "Livello X/Y", testo "Limite 5 livelli raggiunto"). I limiti restano applicati in background.
- **Tap su cartella con figli**: 1 tap → entra e seleziona quella cartella.
- **Tap su cartella foglia (senza figli)**: 1 tap → seleziona, **dialog resta aperto** (l'utente puo' ancora usare "Crea Nuova Cartella" e poi "Conferma Selezione").
- File: `lib/widgets/folder_card_selector.dart`, invocato da `SharingService._showCardFolderSelector()`.

Le vecchie costanti Free in `lib/services/access_control_service.dart` sono solo fallback se Firestore non risponde. Non devono essere usate come regola primaria.

## Reminder post e cartelle

SaveIn! consente di impostare reminder su post e cartelle.

### File principali

- `lib/widgets/reminder_dialog.dart`: dialog di creazione/gestione reminder.
- `lib/services/reminder_service.dart`: persistenza Firestore, scheduling notifiche locali e gestione tap notifica.
- `lib/pages/folder_detail_page.dart`: reminder sui post e sottocartelle, apertura/evidenziazione target con scroll preciso.
- `lib/widgets/folder_card.dart`: reminder sulle cartelle.
- `lib/services/interstitial_ad_service.dart`: gate ADV per utenti Free.
- `lib/main.dart`: funzione `openReminderTargetInApp`, `homeHighlightFolderNotifier`, e logica di navigazione per cartelle root.

### Dati Firestore

- I reminder sono salvati in `users/{userId}/reminders`.
- Campi principali: `targetType` (`post` o `folder`), `postId`, `postTitle`, `postUrl`, `folderId`, `folderName`, `reminderDay`, `reminderMonth`, `reminderHour`, `reminderMinute`, `isYearly`, `notificationId`, `isActive`, `createdAt`, `lastTriggeredAt`.

### Regole prodotto

- I reminder sono disponibili anche agli utenti Free.
- Utenti Free: prima di impostare o aprire un reminder deve comparire un passaggio pubblicitario. Se AdMob non carica, viene mostrato un popup fallback obbligatorio `Annuncio` con pulsante `Continua`.
- Utenti Premium/Admin: nessuna pubblicita sui reminder.
- L'apertura di una notifica reminder non apre direttamente l'URL del post: entra in SaveIn! e naviga al target.
- Reminder non annuali: dopo tap/apertura vengono eliminati e spariscono dalla UI.
- Reminder annuali: restano attivi e vengono rischedulati, aggiornando `lastTriggeredAt`.
- I reminder scaduti non annuali vengono rimossi automaticamente quando si leggono le liste reminder.
- Se l'app viene aperta da notifica a freddo (app terminata), `ReminderService` legge `getNotificationAppLaunchDetails()` e riprocessa il payload dopo l'inizializzazione.

### Navigazione alla notifica

La funzione `openReminderTargetInApp` in `lib/main.dart` determina la destinazione in base al tipo di reminder:

**Reminder su post:**
- Apre `FolderDetailPage` della cartella che contiene il post.
- Passa `highlightPostId` per evidenziare il post target.
- Lo scroll porta il post esattamente al centro del viewport.

**Reminder su sottocartella (ha un parent):**
- Apre `FolderDetailPage` del parent della sottocartella.
- Passa `highlightFolderId` per evidenziare la sottocartella nella griglia.
- Lo scroll porta la card della sottocartella al centro del viewport.

**Reminder su cartella root (livello 0, in Home, parent == null):**
- NON apre `FolderDetailPage`: fa `popUntil(isFirst)` per tornare alla Home.
- Imposta `homeHighlightFolderNotifier.value = folderId` (ValueNotifier globale).
- `_WebHomePageState` ascolta il notifier e triggera highlight + scroll sulla griglia Home.

### Scroll centrato: meccanismo a due passi

Lo scroll verso il target usa **posizione reale da `GlobalKey`** (non stima fissa):

**Prima passa:** se l'elemento non è ancora nel viewport, `SliverList`/`SliverGrid` non lo ha ancora costruito (lazy rendering). Si fa uno scroll approssimativo (stima offset) per portarlo in vista.

**Seconda passa:** dopo il render, il `GlobalKey` è collegato al widget reale. Si calcola la posizione esatta:
```dart
final box = key.currentContext!.findRenderObject() as RenderBox;
final itemOffset = box.localToGlobal(Offset.zero, ancestor: scrollableBox);
final centeredOffset = currentScrollOffset + itemOffset.dy - (viewportHeight - itemHeight) / 2;
```
Il risultato porta il **centro dell'elemento** esattamente al **centro del viewport**.

Chiavi usate:
- `_highlightedPostKey` (`GlobalKey`) in `_FolderDetailPageState`: assegnata al Container del post evidenziato in `_buildPostCard`.
- `_highlightedFolderKey` (`GlobalKey`) in `_FolderDetailPageState`: assegnata all'`AnimatedBuilder` della sottocartella evidenziata nel `SliverGrid`.
- `_highlightedHomeFolderKey` (`GlobalKey`) in `_WebHomePageState`: assegnata all'`AnimatedBuilder` della card root evidenziata nella griglia Home.

### Highlight animato (effetto pulse)

Ogni elemento evidenziato usa un `AnimationController` con `repeat(reverse: true)` a 700ms per creare un effetto pulsante per 5 secondi:
- Sfondo arancione: opacità da 0.18 a 0.40.
- Bordo arancione: spessore da 2.5px a 4px.
- Ombra esterna arancione: `blurRadius` da 10 a 22, `spreadRadius` da 1 a 4.

L'`AnimationController` è in `_FolderDetailPageState` (per post/subfolder) e in `_WebHomePageState` (per root folder in Home), con `SingleTickerProviderStateMixin`.

### Comunicazione Home ↔ openReminderTargetInApp

Per le cartelle root viene usato un `ValueNotifier<String?>` globale:
```dart
final ValueNotifier<String?> homeHighlightFolderNotifier = ValueNotifier(null);
```
Definito in `lib/main.dart`. `_WebHomePageState` si registra con `addListener` in `initState` e rimuove il listener in `dispose`. Quando il notifier cambia, triggera `setState` con il nuovo `_highlightRootFolderId` e avvia scroll + animazione pulse.

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
- Limiti Funzioni
- Statistiche globali
- Costi/Ricavi
- Notifiche
- Banner promo
- Accessi dashboard: gestisce `dashboard_accesses`, non la lista utenti app

Vincoli UI:
- Liste paginate a 20 elementi
- Tabella utenti e filtri devono occupare tutta la larghezza del contenitore
- Dettaglio utente in pagina dedicata, non pannello laterale
- Post: elenco titoli, filtro per provenienza/social/sito
- Cartelle: espandibili, con sottocartelle e post
- Nel dettaglio del singolo utente deve esserci `Storico account e piano`: mostra registrazione, passaggi Free/Premium/Admin, modifiche scadenza Premium, promo compleanno, promo/banner, promo benvenuto e cross-promo.
- Lo storico permanente nuovo viene scritto in `users/{uid}/account_history`. La vista dashboard integra anche fonti storiche gia presenti: `admin_logs`, `promotion_redemptions`, `new_signup_premium_promo_claims`, `cross_app_promos` e il campo utente `birthdayOffer`.
- Quando si azzerano dati di test cross-promo o redemption, non cancellare `users/{uid}/account_history`.
- Tutte le sezioni principali della dashboard web devono usare la stessa larghezza della Home dashboard: `BoxConstraints(maxWidth: 1400)`. Non introdurre pagine interne a `1100`/`1200`, altrimenti risultano visivamente piu strette.
- I controlli cliccabili custom (`_AdminNavButton`, tab Notifica/Email, select promo, righe link) devono usare `MouseRegion(cursor: SystemMouseCursors.click)` quando sono interattivi, cosi su web compare la manina.
- La pagina Notifiche usa due schede evidenti e colorate: `Notifica Push / In-App` e `Email Marketing`. Devono sembrare pulsanti selezionabili, non semplici label.
- La Home dashboard contiene una barra `Invia Promo/Banner` sopra la tabella utenti: permette di scegliere promo/banner preparati e inviarli agli utenti selezionati senza entrare nella pagina Notifiche.
- Le notifiche dashboard SaveIn! passano sempre dalla Cloud Function `sendDashboardNotification`, anche quando si seleziona solo `In-app`: la Function crea `notification_campaigns/{campaignId}` e, se richiesto, `users/{uid}/notifications/{notificationId}`.
- Nella finestra di composizione Notifiche/Email c'e' il flag `Questa comunicazione deve arrivare sempre perche e' di sistema`. Se attivo, la dashboard passa `systemCommunication=true` alle Cloud Functions e l'invio bypassa il blocco marketing/comunicazioni per gli utenti selezionati.
- Se il flag sistema non e' attivo, `sendDashboardNotification` e `sendBulkEmail` rispettano `consents.marketing.accepted`/`acceptedMarketing`: gli utenti senza consenso vengono saltati e la risposta include `skippedConsentCount`.
- Prima dell'invio, se tra gli utenti selezionati ci sono persone con comunicazioni `NO` e il flag sistema non e' attivo, la dashboard deve mostrare un avviso: la notifica/email non sara inviata a quegli utenti. L'admin puo annullare oppure continuare saltandoli.
- Le push dashboard usano FCM con `type=dashboard_notification`, `campaignId`, `title` e `body` nel payload data. Quando l'utente tocca la push, l'app deve aprirsi e mostrare un popup con lo stesso titolo/testo. Se titolo/testo non sono nel payload, l'app recupera `notification_campaigns/{campaignId}`.
- Android richiede in `android/app/src/main/AndroidManifest.xml` l'intent-filter `FLUTTER_NOTIFICATION_CLICK` sulla `MainActivity`, coerente con `android.notification.clickAction` inviato dalla Cloud Function. Senza questo filtro la notifica puo comparire nella barra ma il tap non apre l'app.
- `AppNotificationService` conserva in memoria i payload push aperti prima che la UI sia montata: quando `AppNotificationListener` parte, svuota la coda e mostra il popup. Questo copre il caso app chiusa/avvio a freddo.
- Le notifiche in-app vengono ascoltate da `AppNotificationListener` su `users/{uid}/notifications`, filtrando lato app i documenti con `readAt == null`. Dopo la chiusura del popup viene scritto `readAt`.

## Promo incrociate e banner dinamici

SaveIn! supporta banner promozionali configurabili dal punto centrale SmartChef/SaveIn e promo incrociate con SmartChef.

Collezioni Firestore:
- `promotion_banners`: configurazione banner. Campi principali: `active`, `app`, `apps`, `type`, `title`, `message`, `ctaLabel`, `secondaryCtaLabel`, `action`, `actionUrl`, `imageUrl`, `saveinImageUrl`, `smartchefImageUrl`, `priority`, `oncePerUser`, `direction`.
- `promotion_banner_events`: statistiche aggregate per banner (`view`, `click`) con `promotionId`, `eventType`, `placement`, `count`.
- `promotion_redemptions`: riscatti promo, usato per nascondere banner `oncePerUser` e mostrare statistiche utilizzi.
- `cross_app_promos`: stato promo SaveIn! ↔ SmartChef, con direzioni `savein_to_smartchef` e `smartchef_to_savein`.
- `app_config/new_signup_premium_promo`: configurazione promo benvenuto nuovi iscritti SaveIn (`active`, `app`, `durationDays`, `priceAfterTrial`, `startsAt`, `endsAt`). E' il documento reale letto dalle Cloud Functions SaveIn.
- `new_signup_premium_promo_claims`: storico permanente per email delle promo benvenuto gia usate. Campi principali: `email`, `normalizedEmail`, `firstUserId`, `lastUserId`, `startedAt`, `premiumUntil`, `durationDays`, `status`.

Dashboard:
- La voce `Banner promo` e' subito vicino a `Home dashboard` per non restare nascosta nello scroll orizzontale.
- La pagina SaveIn e' ora un monitor locale: mostra i banner sincronizzati nel progetto SaveIn, ma creazione/modifica/attivazione/disattivazione/eliminazione avvengono dalla gestione centrale `/admin/promo-banners` del backend SmartChef.
- Il centro promo garantisce una sola promo attiva globale alla volta e sincronizza su SaveIn le promo `app=savein` o `app=both` tramite endpoint protetto.
- La Home dashboard SaveIn mostra anche promo/banner `active: false` se sono `app=savein` o `app=both`: `active` indica se il banner appare automaticamente nell'app, non se e' inviabile manualmente agli utenti selezionati.
- Nella barra `Invia Promo/Banner`, le promo non attive nell'app devono comparire con badge/testo `non attivo in app`, ma restano selezionabili per invio manuale.
- La tendina `Invia Promo/Banner` deve essere una select visibile, non testo semplice: campo bianco con bordo, freccia, larghezza controllata (circa 430 px), menu con intestazioni `Offerte Compleanno` e `Banner SaveIn`.
- Per `generic_promo` si usa solo `imageUrl`; nel form SaveIn non vanno mostrati i campi dei pulsanti (`ctaLabel`/`secondaryCtaLabel`) perche' il banner generico e' gestito come immagine/link.
- Per `cross_promo` si usano immagini dedicate: `saveinImageUrl` per SaveIn! e `smartchefImageUrl` per SmartChef. `imageUrl` resta fallback/generic.
- Il pulsante `Carica immagine banner` carica immagini PNG/JPG/WEBP su Firebase Storage tramite Cloud Function admin-only.
- Il pulsante `Scegli dallo storico` mostra tutte le immagini presenti in Storage sotto `promotion_banners/`, consente di riutilizzarle e di eliminarle definitivamente. Eliminare un'immagine usata da un banner rompe la visualizzazione di quel banner finche' non si sostituisce `imageUrl`.
- La sezione `Promo nuovi iscritti` abilita/disabilita il mese Premium gratuito di benvenuto. Sotto mostra lo storico delle ultime email che hanno gia usato la promo con inizio, fine e stato.
- Il centro promo SmartChef mostra la tab SaveIn leggendo la config live da SaveIn tramite `syncCentralNewSignupPremiumPromo` in `GET` protetto. Questo evita disallineamenti tra copia locale SmartChef e documento reale SaveIn.

Cloud Functions:
- `syncCentralPromotionBanner`: endpoint HTTP protetto da `X-Cross-Promo-Secret` usato dal centro promo SmartChef per creare/aggiornare/eliminare banner SaveIn sincronizzati.
- `syncCentralNewSignupPremiumPromo`: endpoint HTTP protetto da `X-Cross-Promo-Secret` usato dal centro promo SmartChef. In `POST` aggiorna `app_config/new_signup_premium_promo` di SaveIn; in `GET` restituisce la config live per farla comparire nella dashboard SmartChef.
- `getActivePromotionBanner`: restituisce il banner attivo piu' prioritario per utente/app, rispettando `active`, finestra temporale, `oncePerUser` e riscatti gia' presenti.
- `recordPromotionBannerEvent`: registra view/click.
- `uploadPromotionBannerImage`: carica file banner su Storage, solo admin dashboard.
- `listPromotionBannerImages`: elenca storico immagini banner da Storage, solo admin dashboard.
- `deletePromotionBannerImage`: elimina definitivamente un file banner da Storage, solo admin dashboard.
- `activateSmartChefLaunchPromo`, `confirmSmartChefCrossPromo`, `receiveSmartChefLaunchPromo`, `claimPendingSmartChefLaunchPromo`: gestiscono la promo incrociata account-based tramite email.
- `getNewSignupPremiumPromoEligibility`: controlla lato server se la mail puo vedere/attivare la promo benvenuto. Se la mail ha gia una promo ancora valida, ripristina Premium sul nuovo account fino alla scadenza originale.
- `activateNewSignupPremiumPromo`: attiva la promo benvenuto e scrive lo storico permanente in `new_signup_premium_promo_claims`. Se la mail ha gia usato la promo e la scadenza e' passata, blocca il riutilizzo.

Configurazione SmartChef necessaria per la sync SaveIn:
- Il servizio Cloud Run SmartChef `smart-chef-backend` deve avere queste env vars separate, non concatenate in un unico valore:
  - `CROSS_PROMO_SECRET`
  - `SAVEIN_PROMOTION_BANNER_SYNC_URL=https://us-central1-saveit-app-1784d.cloudfunctions.net/syncCentralPromotionBanner`
  - `SAVEIN_NEW_SIGNUP_PROMO_SYNC_URL=https://us-central1-saveit-app-1784d.cloudfunctions.net/syncCentralNewSignupPremiumPromo`
  - `SAVEIN_CROSS_PROMO_CONFIRM_URL=https://us-central1-saveit-app-1784d.cloudfunctions.net/confirmSmartChefCrossPromo`
  - `SAVEIN_CROSS_PROMO_PENDING_URL=https://us-central1-saveit-app-1784d.cloudfunctions.net/receiveSmartChefLaunchPromo`
- Per evitare problemi PowerShell con virgole/virgolette, preferire `gcloud run services update ... --env-vars-file smartchef_cloudrun_env.yaml`.
- SmartChef ha una rotta admin `POST /admin/promo-banners/sync-savein` per risincronizzare su SaveIn i banner centrali gia esistenti.

UI utente:
- Home SaveIn!: banner sotto la barra di ricerca.
- Pagina Account: banner anche nella sezione account/piano.
- Se `imageUrl` e' valorizzato, l'immagine viene mostrata in alto nel banner; titolo, messaggio e CTA restano sotto.
- Le view vengono deduplicate localmente per evitare conteggi ripetuti nella stessa sessione.
- Pagina Account:
  - Se l'utente e' Free e la promo benvenuto e' attiva, compare un avviso sopra la tipologia account.
  - Cliccando l'avviso si apre una dialog a slide stile tutorial SmartChef/SaveIn, formato verticale 9:16, testi scuri espliciti e illustrazioni.
  - Le slide promo benvenuto sono 4: mese Premium gratis, cartelle, tag/ricerca, niente pubblicita e uso piu fluido. L'ultima slide contiene un solo pulsante `Prova Premium gratis`.
  - L'esempio visuale della slide cartelle usa `Viaggi` con sottocartelle `Giappone`, `Francia`, `India`; dentro `Giappone`: `Ristoranti`, `Monumenti`, `Esperienze`.
  - Il popup automatico della promo benvenuto viene proposto al massimo una volta al giorno per utente, al primo ingresso utile. Premere `Non ora` non blocca la promo per sempre: la ripropone dal giorno successivo se l'utente resta idoneo.
  - Il bottone `Vedi differenze Free/Premium` e' full-width blu per maggiore visibilita. Il confronto piani non include piu la slide statistiche.
  - Se un Premium temporaneo clicca `Passa a Free`, non viene interrotto subito: l'app avvisa che restera Premium fino alla data prevista e poi tornera Free automaticamente.

Regole anti-abuso promo benvenuto:
- Non basarsi solo sul documento `users/{uid}`: l'utente puo eliminarlo insieme all'account.
- La fonte di verita e' `new_signup_premium_promo_claims/{normalizedEmail}` scritta solo da Cloud Function.
- Se una mail ha gia usato la promo:
  - se `premiumUntil` e' futura, un nuovo account con stessa mail riparte Premium fino alla scadenza originale;
  - se `premiumUntil` e' passata, la promo non viene piu proposta e non puo essere riattivata.
- Le regole Firestore permettono lettura dashboard dello storico ma vietano scritture client su `new_signup_premium_promo_claims`.

Deploy:
```powershell
flutter build web --release; if ($LASTEXITCODE -eq 0) { $env:FUNCTIONS_DISCOVERY_TIMEOUT='120000'; firebase deploy --only functions,hosting }
```

Build mobile:
- Versione mobile corrente in repo: `pubspec.yaml` **`1.0.0+40`**. Prossima release prevista: **`1.0.0+41`** (fix import/cartelle/global_posts, lug 2026).
- **Fix SHA Android App Links (giu 2026)**: aggiornato solo Firebase/Hosting — **non** richiede nuova `.aab` né nuovo build iOS. Dopo il deploy Firebase: reinstallare SaveIn! dal link test interno Play e ritestare `https://savein.eu/s/test`. **Verificato OK** su test interno Play (lug 2026).

## Condivisione link pubblici (share links)

### Panoramica

SaveIn! supporta la condivisione di post singoli e cartelle (con tutto il contenuto) tramite link pubblici nel formato `https://savein.eu/s/<token>`. Il link funziona su qualsiasi piattaforma di messaggistica.

- **Se l'app è installata**: Android App Links intercetta il link e apre direttamente `SharedLinkPage` nell'app.
- **Se l'app non è installata**: Firebase Hosting fa rewrite su `openShareLink` (Cloud Function HTTP) che mostra una landing page invitante con pulsante Play Store e messaggio contestuale.
- **Dopo l'installazione**: l'utente può riaprire lo stesso link dalla chat per importare il contenuto.

### Cloud Functions (SaveIn — `functions/index.js`)

| Funzione | Tipo | Scopo |
|---|---|---|
| `createShareLink` | `onCall` | Crea un documento in `shared_links` con token univoco e snapshot del payload; restituisce `{ token, url, type, title }` |
| `getShareLink` | `onCall` | Legge il documento per token, verifica scadenza/status, incrementa `openCount`, restituisce payload |
| `trackShareLinkImport` | `onCall` | Incrementa `importCount` dopo che l'utente importa il contenuto |
| `openShareLink` | `onRequest` | Serve la landing page HTML con messaggio contestuale, link Play Store e redirect automatico allo store dopo 1,4 s |
| `assetLinks` | `onRequest` | Serve `/.well-known/assetlinks.json` per la verifica Android App Links |
| `sendDashboardNotification` | `onCall` | Invia notifiche dashboard a utenti selezionati: crea campagna, eventuali documenti in-app e push FCM con payload apribile dall'app |
| `ensureGlobalPost` | `onCall` | Crea o aggiorna `global_posts/{urlHash}`; merge metadati canonici; incrementa `saveCount` |
| `getGlobalPostByUrl` | `onCall` | Lookup **read-only** su `global_posts` per URL normalizzato; **non** incrementa `saveCount`; usato prima del fetch metadati |

### Collezione Firestore: `global_posts`

Documento indicizzato da `urlHash` (= SHA-256 di URL normalizzato, stesse regole di `normalizePostUrlForHash` in `functions/index.js` e `post_preview_url_utils.dart`):

| Campo | Tipo | Note |
|---|---|---|
| `urlHash` / ID doc | string | Chiave dedup |
| `normalizedUrl` | string | URL canonico |
| `url`, `title`, `description` | string | Metadati condivisi |
| `imageUrl`, `previewStorageUrl` | string | Anteprima (Storage URL preferito se presente) |
| `creatorName`, `creatorUsername` | string | Autore social se disponibile |
| `metadataProvider` | string | Origine fetch, es. `client_scrape` (default); futuro `sociavault` |
| `firstOwnerId` | string | UID primo utente che ha creato il record |
| `saveCount` | number | Quanti utenti hanno salvato lo stesso URL |
| `createdAt` / `updatedAt` | timestamp | |

**Flusso dedup cross-utente (lug 2026)**:
1. Utente condivide URL → app chiama `getGlobalPostByUrl` **prima** di scraping.
2. Se `found=true` e metadati usabili → `UrlMetadataService.resolveImportMetadata()` salta HTTP/oEmbed; riusa canonical da `global_posts`.
3. Al salvataggio → `ensureGlobalPost` aggiorna/crea record e collega `globalPostId`/`urlHash` al post utente.
4. Ogni utente ha comunque il **proprio** documento in `users/{uid}/posts`; condivide solo i metadati/anteprima.

**Nota SociaVault**: SaveIn **non** usa SociaVault (a differenza di SmartChef). L'import social usa scraping client-side (`UrlMetadataService`). SociaVault e' candidato per integrazione futura lato Cloud Function, con stesso pattern `global_posts` per non consumare crediti su URL gia' risolti.

### Collezione Firestore: `shared_links`

Documento indicizzato da `token` (ID documento):

| Campo | Tipo | Note |
|---|---|---|
| `token` | string | Uguale all'ID documento; 18 byte base64url |
| `type` | string | `"post"` o `"folder"` |
| `title` | string | Titolo visibile nella landing page |
| `payload` | map | Snapshot del post o della struttura cartella |
| `ownerId` | string | UID Firebase dell'autore |
| `ownerEmail` | string | |
| `ownerName` | string | |
| `status` | string | `"active"` (unico valore attuale) |
| `expiresAt` | timestamp | +90 giorni dalla creazione |
| `viewCount` | number | Incrementato da `openShareLink` |
| `openCount` | number | Incrementato da `getShareLink` |
| `importCount` | number | Incrementato da `trackShareLinkImport` |
| `createdAt` / `updatedAt` | timestamp | |

Payload post: `{ id, url, title, description, imageUrl, previewStorageUrl, creatorName, creatorUsername, tags, folderId }`.

Payload cartella: `{ rootId, name, color, folders: [...], posts: [...] }`. La struttura include tutte le sottocartelle dell'albero e i post al loro interno.

### Variabili d'ambiente Cloud Functions (SaveIn)

| Variabile | Default | Descrizione |
|---|---|---|
| `SHARE_LINK_BASE_URL` | `https://savein.eu` | Dominio base link pubblici |
| `PLAY_STORE_URL` | `https://play.google.com/store/apps/details?id=eu.savein.app` | Link Play Store |
| `APP_STORE_URL` | `""` | Link App Store (opzionale, se vuoto il pulsante iOS non compare) |

### SHA-256 Android App Links (`ASSET_LINKS` in `functions/index.js`)

Package: `eu.savein.app`. Fingerprint configurati in produzione (giu 2026):

| Certificato Play Console | SHA-256 | Uso |
|---|---|---|
| **App signing key** (Certificato della chiave di firma dell'app) | `88:71:25:D3:62:D3:2D:B6:FE:69:67:68:F8:02:BB:04:53:90:30:90:58:0C:69:5E:C6:12:9F:55:FD:95:4C:BD` | Installazioni da Play Store / test interno |
| **Upload key** (Certificato della chiave di caricamento) | `89:09:D4:4A:58:D6:7C:FC:53:0B:1B:F7:7E:4D:85:36:14:BD:CA:4F:BB:0F:48:46:31:4A:3E:30:FC:A8:64:D2` | Build release firmate in locale con `savein-release.jks` |

File da tenere allineati:
- `functions/index.js` → costante `ASSET_LINKS`
- `web/.well-known/assetlinks.json` → fallback nel repo
- `build/web/.well-known/assetlinks.json` → ridistribuito su Firebase Hosting (priorità sul rewrite Function se presente come file statico)

> **Attenzione:** il vecchio SHA `48:39:0D:...` non corrispondeva a nessun certificato SaveIn su Play Console e impediva l'apertura diretta dell'app dopo install da Play.

Recupero fingerprint in Play Console:
- **Protetto con Play** → **Firma dell'app** (URL diretto: `https://play.google.com/console/developers/app/keymanagement`)
- Sezione **Certificato della chiave di firma dell'app** → SHA-256 (o copiare il JSON **Digital Asset Links**)

### Firebase Hosting rewrites (SaveIn — `firebase.json`)

```json
{ "source": "/.well-known/assetlinks.json", "function": { "functionId": "assetLinks" } },
{ "source": "/s/**", "function": { "functionId": "openShareLink" } }
```

### Android App Links (`AndroidManifest.xml`)

```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <category android:name="android.intent.category.BROWSABLE"/>
  <data android:scheme="https" android:host="savein.eu" android:pathPrefix="/s"/>
</intent-filter>
```

### Verifica post-release Android App Links

Da ricordare dopo ogni nuova release Play/test interno:
1. Installare SaveIn! dal link Play Console/test interno, non da APK locale.
2. Tab **Tester** → **Copia link** opt-in → **Diventa tester** → installare **da Play Store**.
3. Aprire sul telefono un link `https://savein.eu/s/test`.
4. Se apre direttamente SaveIn!, gli App Links sono verificati.
5. Se apre browser o chiede "Apri con", recuperare lo SHA-256 del **App signing key certificate** (non l'upload key):
   - Play Console → **Protetto con Play** → **Firma dell'app**
   - Copiare **Fingerprint del certificato SHA-256** in **Certificato della chiave di firma dell'app**
6. Aggiornare `ASSET_LINKS` in `functions/index.js` e `web/.well-known/assetlinks.json`; copiare anche in `build/web/.well-known/assetlinks.json` se si fa deploy Hosting.
7. Deploy Firebase (senza nuova build mobile):
   ```powershell
   cd C:\Users\dinop\saveit
   firebase deploy --only functions:assetLinks,hosting
   ```
8. **Non serve** ricaricare `.aab`/TestFlight solo per SHA/assetlinks. Reinstallare dal Play test interno se l'app era già installata prima del fix.
9. In `firebase.json` Hosting **non** ignorare la cartella `.well-known` (`**/.*` va evitato negli ignore): un file statico obsoleto su Hosting ha priorità sul rewrite verso la Function.

### File Flutter principali

| File | Ruolo |
|---|---|
| `lib/services/share_link_service.dart` | `ShareLinkService.instance` — crea link, legge token, importa post/cartelle, tiene conto della gerarchia sottocartelle |
| `lib/pages/shared_link_page.dart` | Schermata di apertura link: mostra anteprima del contenuto, pulsanti "Apri contenuto originale" (post) e "Salva / Importa" |
| `lib/main.dart` — `_initAppLinks` | Ascolta deep link con `app_links`; estrae token da `savein.eu/s/<token>` e apre `SharedLinkPage` |
| `lib/utils/dialog_helpers.dart` — `showShareItemDialog` | Parametro `systemShareContentBuilder` (async) che mostra "Creo il link…" durante la creazione e poi apre il foglio di condivisione di sistema |
| `lib/pages/folder_detail_page.dart` — `_sharePost` | Genera link SaveIn per il post e costruisce il messaggio di condivisione |
| `lib/widgets/folder_card.dart` — `_shareFolder` | Genera link SaveIn per la cartella (con tutto il contenuto) e costruisce il messaggio |

### Messaggi condivisi

- **Post**: `"C'è un contenuto SaveIn che ti aspetta: <titolo>\n\n<link>\n\nAprilo con SaveIn per salvarlo e ritrovarlo quando vuoi."`
- **Cartella**: `"Hai ricevuto una cartella SaveIn: <nome>\n\n<link>\n\nAprila con SaveIn per importarla all'istante nella tua raccolta."`

### Landing page fallback (messaggi utenti senza app)

- **Post**: "C'è un contenuto SaveIn che ti aspetta! Scarica l'app gratis per aprirlo e salvarlo. Organizza le tue idee in un clic."
- **Cartella**: "Hai ricevuto una cartella SaveIn! Scarica l'app gratis per importarla all'istante e avere tutte le nuove idee organizzate in un clic."

### Dipendenza Flutter aggiunta

- `app_links: ^6.4.1` — gestione deep link `https://`

### Evidenziazione visiva del contenuto importato

Post e cartelle importati da un link SaveIn altrui vengono salvati con `isShared: true` (campo Firestore). Questo campo guida la UI per distinguerli visivamente dal contenuto creato dall'utente.

**Cartella importata (`lib/widgets/folder_card.dart`)**:
- Sfondo `Colors.blue.withOpacity(0.2)` e bordo blu (già presenti)
- Banner turchese-blu in fondo alla card (`Colors.blue.shade700`, bordi arrotondati solo in basso) con icona `download_rounded` e testo "cartella importata" (10 sp, bold)

**Post importato (`lib/pages/folder_detail_page.dart` — `_buildPostCard`)**:
- Sfondo e bordo blu tenue (già presenti)
- Chip pill blu chiaro con bordo (`Colors.blue.shade400`) e testo "post importato" (10 sp, bold), mostrato sotto la riga del dominio sorgente

Il campo `isShared` viene impostato a `true` da `ShareLinkService.importPost` e `ShareLinkService.importFolder` in `lib/services/share_link_service.dart`.

---

## Registrazione e Profilo Utente

SaveIn! raccoglie informazioni di base per personalizzare l'esperienza e offrire vantaggi.

- **Dati raccolti**: Nome, Email, Password, Data di Nascita e Sesso.
- **Data di Nascita**: Viene chiesta esplicitamente per offrire sconti e regali speciali (es. compleanno). Un avviso nel form spiega questa finalità.
- **Sesso**: Opzioni: "Maschio", "Femmina", "Preferisco non dirlo".
- **Modifica Profilo**: Gli utenti possono aggiornare Data di Nascita e Sesso dalla pagina "Modifica Profilo" nell'area Account.
- **Sync Firestore**: Tutti i dati sono sincronizzati in tempo reale con la collezione `users` tramite `AuthService`.

---

## Import post e metadati

### SaveIn vs SmartChef (SociaVault)

| | SaveIn | SmartChef |
|---|---|---|
| Estrazione metadati social | **Client-side** (`UrlMetadataService` nell'app) | **Server-side** (SociaVault + yt-dlp + Whisper + Gemini) |
| Costo API SociaVault | Nessuno (oggi) | ~0,01–0,02 €/chiamata |
| Obiettivo | Segnalibro + anteprima + tag | Ricetta strutturata da video |

SaveIn **non** integra SociaVault al 13/07/2026. L'estrazione avviene cosi:

1. Share intent → `SharingService.showSaveDialog()`
2. **`resolveImportMetadata(url)`** (`lib/url_metadata_service.dart`):
   - prima: `getGlobalPostByUrl` (Cloud Function) → cache `global_posts`
   - se miss: **`extractMetadata(url)`** — HTTP GET pagina + Open Graph + fallback embed/oEmbed
3. Instagram: pagina embed se manca `og:image`
4. TikTok: redirect `vm.tiktok.com` + oEmbed pubblico
5. Hashtag: testo condiviso + parsing HTML
6. Salvataggio → `ensureGlobalPost` + cache anteprima locale/remota

Servizi principali:
- `lib/url_metadata_service.dart` — `extractMetadata`, `resolveImportMetadata`
- `lib/services/global_post_lookup_service.dart` — client lookup `global_posts`
- `lib/services/sharing_service.dart` — dialog import, navigazione post-salvataggio
- `lib/services/folder_service_sharing.dart` — `saveSharedPostWithOptionalFolder` (`isShared: true`, passa `previewStorageUrl`)
- `functions/index.js` — `ensureGlobalPost`, `getGlobalPostByUrl`

Modello `UrlMetadata` (`lib/models.dart`, lug 2026):
- `previewStorageUrl`, `fromGlobalCache`, getter `displayImageUrl` (preferisce Storage condiviso)

Note importanti:
- Instagram puo non fornire `og:image`; fallback embed; spesso fragile vs API dedicate.
- TikTok puo mostrare pagina login ai bot; oEmbed mitiga ma non sempre basta.
- Le immagini CDN social scadono → cache locale + backup `post_previews/by_url/{hash}` su Firebase Storage.
- **Anteprima dopo import (fix lug 2026)**: post salvato con ID reale; upsert immediato in `FolderService.allPosts`; refresh UI cartella con `highlightPostId`; preservazione anteprime durante sync.

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
- Le statistiche globali della dashboard usano `collectionGroup('posts')` e `collectionGroup('folders')`: le rules devono includere match dedicati `/{path=**}/posts/{postId}` e `/{path=**}/folders/{folderId}` con `allow read: if isDashboardViewer();`, altrimenti appare `permission-denied`.

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
- Gate ADV prima di impostare un reminder (`showReminderSetupGate`).
- Gate ADV prima di aprire un reminder da notifica o popup interno (`showReminderOpenGate`).
- Se AdMob non carica, i gate reminder mostrano un popup fallback obbligatorio `Annuncio` per non saltare il passaggio pubblicitario.
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
- `collectionGroup('posts')` per statistiche globali su provenienze/creator e conteggi post
- `collectionGroup('folders')` per statistiche globali sui nomi cartella

Statistiche admin utente:
- post totali/periodo
- cartelle totali/periodo
- hashtag unici
- domini/social piu salvati
- cartelle piu usate
- post per mese
- ultimi post
- analytics app sincronizzate quando disponibili

Statistiche globali dashboard:
- La sezione `Statistiche globali` mostra post analizzati, cartelle analizzate, top provenienze, cartelle piu comuni e top creator importati.
- Richiede deploy delle Firestore rules oltre al deploy hosting se si modifica la logica di lettura.

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
- `lib/services/global_post_lookup_service.dart`
- `lib/services/sharing_service.dart`
- `lib/services/folder_service_sharing.dart`
- `lib/services/folder_service_sync.dart` — `upsertMockPostFromSavedPost`, merge anteprime in sync
- `lib/widgets/folder_card_selector.dart`
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
  - Link pagina assistenza pubblica: `https://savein.eu/support.html`
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

### Play Store — stato attuale (giugno 2026)

- App creata su Play Console: `SaveIn!` — package `eu.savein.app`
- Release di test interno: build **`1.0.0+14`** — fix buffering cartelle, tutorial/notifiche post-login, sync startup cartelle
- **Android App Links**: SHA Play App Signing allineato su Firebase (giu 2026); verificato live su `https://savein.eu/.well-known/assetlinks.json`; **test link OK** da install Play (lug 2026)
- Configurazione app: in corso (scheda store, classificazione, privacy)
- Test chiuso: da completare (richiede 12 tester per 14 giorni)
- Produzione: da richiedere dopo test chiuso

#### Quando serve una nuova release app vs solo deploy server

| Modifica | Nuova `.aab` Android | Nuovo build iOS | Deploy Firebase | Deploy backend SaveIn |
|---|---|---|---|---|
| SHA-256 / `assetlinks.json` | **No** | **No** | **Sì** (`functions:assetLinks`, `hosting`) | No |
| Fix Cloud Functions share link / email / **global_posts** | No | No | **Sì** (`functions:getGlobalPostByUrl`, `functions:ensureGlobalPost`, eventualmente `hosting`) | No |
| Fix Flutter/Android/iOS, version bump | Sì | Sì | No* | No |

\*Dashboard web SaveIn: `flutter build web --release` + `firebase deploy --only hosting`.

#### Procedura test interno Play (Android)

1. `flutter build appbundle --release`
2. Play Console → **Test interni** → crea/pubblica release con `.aab`
3. Tab **Tester** → lista email → **Copia link** opt-in
4. Sul telefono: opt-in → installa da Play → prova `https://savein.eu/s/test`
5. Dopo test ok → test chiuso → produzione

Per arrivare in produzione Google richiede:
1. Completare configurazione scheda store
2. Test chiuso con almeno 12 tester per 14 giorni
3. Richiedere accesso alla produzione

### iOS / App Store — prossimi step

Build iOS via **Codemagic** (workflow già funzionante; bundle `eu.savein.app`). Per pubblicazione App Store:
1. Verificare Team Apple Developer, bundle ID `eu.savein.app`, display name `SaveIn!`, icone e `ios/Runner/GoogleService-Info.plist`.
2. App su App Store Connect con lo stesso bundle ID.
3. ~~Configurare gli ID AdMob iOS reali e sostituire gli ID test in `ios/Runner/Info.plist` e nei servizi ads Flutter.~~ **FATTO 03/07/2026** (vedi sezione "Google AdMob" sotto) — serve pero' ancora una nuova build iOS per renderlo effettivo sui dispositivi.
4. Build release Codemagic → TestFlight → test → submit review.
5. Completare privacy, scheda App Store, screenshot, classificazione età, tracking/privacy nutrition labels.
6. **App Store Connect — metadata URL (lug 2026)**:
   - URL assistenza: `https://savein.eu/support.html`
   - URL marketing: `https://savein.eu/marketing.html`
   - Email assistenza ufficiale: `support@savein.eu` (casella Aruba, stessa di `SUPPORT_EMAIL` in `functions/.env`)
7. **App Store Connect — revisione Apple**: fornire account demo **email/password** o Sign in with Apple (preferibile email/password per i revisori). Note consigliate: app in italiano, funzioni da testare (salva link, cartelle, tag, condivisione), connessione internet richiesta.
8. Deep link iOS: Associated Domains + `apple-app-site-association` su `savein.eu` (indipendenti da `assetlinks.json` Android).

Alternativa con Mac: aprire `ios/Runner.xcworkspace` con Xcode e caricare con Organizer/Transporter.

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
- **App ID iOS**: `ca-app-pub-1397392558961350~4643419177` (in `ios/Runner/Info.plist`)
- **Interstitial iOS (reale, dal 03/07/2026)**: `ca-app-pub-1397392558961350/9950660131`
- **Banner iOS (reale, dal 03/07/2026)**: `ca-app-pub-1397392558961350/4315988838`

Configurazione nei file:
- App ID → `android/app/src/main/AndroidManifest.xml` (Android) e `ios/Runner/Info.plist` (iOS)
- Ad Unit IDs → `lib/services/interstitial_ad_service.dart`

Logica ads:
- Solo utenti Free (`AppAccessService().hasAds`)
- **Interstitial**: mostrato prima di apertura post remindato e ogni 5 import
- **Banner**: mostrato nella home ogni 4 cartelle (dopo la 4ª, 8ª, 12ª...) tramite `BannerAdWidget` in `lib/widgets/banner_ad_widget.dart`
- **IMPORTANTE (verificato 03/07/2026)**: sia `InterstitialAdService._shouldUseAds` sia `BannerAdWidget` hanno un controllo esplicito `defaultTargetPlatform == TargetPlatform.iOS` che **disattiva completamente gli ads su iOS**, indipendentemente dagli ID configurati (vedi nota "App Store rejection fix" build `1.0.0+20`, introdotto perche' Apple review aveva contestato gli interstitial). Quindi ora che gli ID iOS reali sono stati creati e inseriti nel codice, gli ads su iOS **restano comunque disattivati** finche' questo blocco non viene rimosso deliberatamente — non e' un bug, e' una scelta di design da rivalutare in futuro se si vuole monetizzare anche su iOS.

L'account AdMob è in attesa di approvazione Google (fino a 24h, dipende dalla pubblicazione su Play Store).

**Stato collegamento store in AdMob (03/07/2026)**: tentativo di collegare l'app Android SaveIn in AdMob non riuscito — AdMob non trova app che non siano ancora pubblicate pubblicamente su Play Store (SaveIn Android e' ancora in test chiuso). Da riprovare dopo la pubblicazione in produzione. Stesso discorso per iOS, disponibile solo dopo pubblicazione live su App Store. Finche' il collegamento store non e' fatto, AdMob applica il limite "Pubblicazione annunci limitata".

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
- Dopo fix SHA Android App Links, aggiornare `ASSET_LINKS`, `web/.well-known/assetlinks.json` e ridistribuire su Firebase Hosting; non ignorare `.well-known` negli ignore di `firebase.json`.
- La Privacy Policy pubblica è su GitHub Pages (`dinus85.github.io/saveit-legal-content/privacy.html`). Per aggiornarla modificare `privacy.html` nel repo `Dinus85/saveit-legal-content`.
- Gli ID AdMob iOS reali sono gia' stati creati e inseriti in `interstitial_ad_service.dart` (03/07/2026); ricordarsi pero' che gli ads restano disattivati su iOS lato codice (`_shouldUseAds`/`BannerAdWidget`) finche' non si decide di riattivarli.
- Le immagini banner promo stanno in Firebase Storage sotto `promotion_banners/` e sono gestite da funzioni admin-only. Non aprire regole Storage pubbliche in scrittura per gestire questi upload.
- La promo benvenuto nuovi iscritti deve passare sempre dalle Cloud Functions `getNewSignupPremiumPromoEligibility` e `activateNewSignupPremiumPromo`. Non riattivarla con scritture dirette client su `users/{uid}`: serve lo storico permanente per email in `new_signup_premium_promo_claims`.
- Quando si modifica la promo benvenuto deployare sia Functions sia regole Firestore: `firebase deploy --only functions,firestore:rules`. Per la dashboard web serve anche build/deploy hosting.
- Dopo eliminazione account, `AuthService.deleteAccount()` deve pulire subito sessione locale e impedire che `_loadUserData` ricrei un profilo fallback mentre Firebase Auth notifica il logout.

## Aggiornamenti 15/06/2026

- Dashboard SaveIn: tutte le pagine interne sono state uniformate alla larghezza della Home dashboard (`maxWidth: 1400`).
- Dashboard SaveIn: aggiunta pagina `Limiti Funzioni` con valori default dalla Bibbia, modifica dinamica Free/Premium, descrizioni feature e salvataggio su `config/plan_limits`.
- Dashboard SaveIn: pagina `Notifiche` rifinita con tab evidenti `Notifica Push / In-App` e `Email Marketing`; i tab devono mostrare cursore a manina su web.
- Dashboard SaveIn: Home dashboard contiene la barra `Invia Promo/Banner` per inviare promo/banner preparati agli utenti selezionati. La select deve mostrare anche banner non attivi in app, perche' l'invio manuale e' separato dalla visibilita automatica in app.
- Dashboard SaveIn: la tendina `Invia Promo/Banner` e' stata resa un vero campo select con bordo, freccia, larghezza controllata e menu ordinato per sezioni.
- Dashboard SaveIn: statistiche globali abilitate tramite rules per `collectionGroup('posts')` e `collectionGroup('folders')`.
- Dashboard SaveIn: cursore web a manina sui controlli custom cliccabili (`_AdminNavButton`, tab notifiche/email, select promo, righe link).
- SmartChef backend: aggiunta pagina dedicata `/admin/notifications` per inviare push, messaggi in-app ed email.
- SmartChef backend: pagina notifiche allineata alla larghezza delle altre pagine admin (`max-width: 1600px`).
- SmartChef backend: configurate env vars Cloud Run per sincronizzare promo/banner centrali verso SaveIn; usare preferibilmente `--env-vars-file` per evitare errori PowerShell.
- SmartChef backend: aggiunta rotta admin `POST /admin/promo-banners/sync-savein` per risincronizzare su SaveIn banner centrali gia esistenti.

Deploy SaveIn web:
```powershell
cd C:\Users\dinop\saveit
flutter build web --release --base-href / --no-wasm-dry-run
firebase deploy --only hosting --project saveit-app-1784d
```

Deploy SaveIn rules quando cambiano permessi/statistiche:
```powershell
cd C:\Users\dinop\saveit
firebase deploy --only firestore:rules --project saveit-app-1784d
```

Deploy SmartChef backend:
```powershell
cd C:\Users\dinop\smart_chef_sm\backend
gcloud run deploy smart-chef-backend --source . --region europe-west1 --project smartchef-82bc8
```

## Aggiornamenti 30/06/2026

- **Android App Links SaveIn**: corretti SHA-256 Play App Signing (`88:71:25:...`) e Upload key (`89:09:D4:...`) in `functions/index.js`, `web/.well-known/assetlinks.json` e Firebase Hosting; rimosso SHA errato `48:39:0D:...`. Deploy: `firebase deploy --only functions:assetLinks,hosting`.
- **`firebase.json` Hosting SaveIn**: rimosso `**/.*` dagli ignore così `.well-known/assetlinks.json` può essere ridistribuito correttamente.
- Dopo fix SHA: reinstallare SaveIn! dal link test interno Play e verificare `https://savein.eu/s/test`.

Deploy rapido solo assetlinks:
```powershell
cd C:\Users\dinop\saveit
New-Item -ItemType Directory -Force -Path build\web\.well-known | Out-Null
Copy-Item web\.well-known\assetlinks.json build\web\.well-known\assetlinks.json -Force
firebase deploy --only functions:assetLinks,hosting --project saveit-app-1784d
```

## Aggiornamenti 01/07/2026

- **Fix avvio SaveIn Android (build `1.0.0+10`)**:
  - `AuthService.initialize`: profilo da cache locale subito; Firestore in background con timeout 8s (evita blocco splash).
  - `WebHomePage`: loading cartelle fin dal primo frame; sync cache prima, refresh server in background.
  - **Splash Android**: logo HD dedicato (`drawable/splash_logo.png`) al posto di `ic_launcher` adattivo sfocato.
- Dopo install da Play test interno: disinstallare versione precedente, reinstallare dal link opt-in.

## Aggiornamenti 02/07/2026

- **Fix startup SaveIn (build `1.0.0+14`)** — richiede nuova `.aab`/`.ipa`:
  - `WebHomePage`: rimosso bug `if (_isInitializing) return` che bloccava `_initializeFolderService()` → buffering infinito e cartelle vuote.
  - `initializeHybridData()` usa `syncStartupWithDataService()` (cartelle subito, post in background).
  - `FolderServiceSync`: sync auth esplicita da `AuthService`/`FirebaseAuth` prima del caricamento dati.
  - Tutorial e permessi notifiche reminder **solo post-login** (`SaveInFirstLaunchTutorial.showIfNeeded`, `AppNotificationListener`).
  - Timer di sicurezza 30s per uscire dal loading anche se sync lento.
- **Dashboard web SaveIn**: ripristinato deploy Flutter web completo su Firebase Hosting (prima era online solo uno stub HTML da 103 byte). Link: `https://savein.eu/dashboard`, `https://savein.eu/?admin=1`, `https://saveit-app-1784d.web.app/dashboard`.
- **Android App Links SaveIn**: test `https://savein.eu/s/test` **OK** da install Play test interno (lug 2026).
- **AdMob iOS SaveIn**: App ID iOS in `Info.plist` ok; ad unit interstitial/banner iOS reali create e inserite in `interstitial_ad_service.dart` il 03/07/2026 (vedi sezione "Google AdMob" e aggiornamento 03/07/2026 sotto). Ricordare che restano comunque disattivate su iOS lato codice.

### App Store review, login e abbonamenti (build `1.0.0+20`)

- **App Store rejection fix**:
  - Aggiunto **Sign in with Apple** su iOS/macOS (`sign_in_with_apple`, `AuthService.loginWithApple`, `Runner.entitlements`).
  - Login social separati per piattaforma: Apple su iOS/macOS, Google su Android/Web; email/password resta disponibile.
  - Fix crash Google Sign-In iOS aggiungendo `GIDClientID` e URL scheme corretti in `ios/Runner/Info.plist`.
  - Interstitial forzati disabilitati su iOS in `InterstitialAdService`; su testi Premium usare "annunci" generico, non "interstitial".
  - Paywall Premium con disclosure obbligatoria: rinnovo automatico, prezzo, Privacy Policy, Termini di utilizzo/EULA.

- **Legal pages pubbliche SaveIn**:
  - `https://savein.eu/privacy` e `https://savein.eu/terms` sono servite da Cloud Functions pubbliche (`renderPrivacyPage`, `renderTermsPage`) via Firebase Hosting rewrite.
  - La sorgente e' il repo GitHub legal content (`privacy_policy.json`, `terms_conditions.json`), non una pagina protetta dell'app.
  - File backend: `functions/legal_content_page.js`; registrazione in `functions/index.js`; rewrites in `firebase.json`.

- **Premium iOS / App Store**:
  - Product ID in codice e backend: `savein_premium_monthly`.
  - `BillingService` usa `in_app_purchase` e verifica iOS tramite callable `verifyAppStorePurchase`.
  - Backend App Store in `functions/app_store_billing.js`: verifica transazioni e webhook App Store Server Notifications v2.
  - App Store Connect deve avere auto-renewable subscription mensile a 1,99 EUR e URL webhook configurato.
  - Il rinnovo automatico non puo essere gestito con checkbox interno: l'app deve rimandare alla gestione ufficiale abbonamenti Apple.

- **Premium Android / Google Play Billing**:
  - Product ID Google Play: `savein_premium_monthly`.
  - Base plan Google Play: `monthly`, tipo rinnovo automatico, periodo ogni mese, prezzo impostato (1,99 EUR base; prezzi locali generati da Play).
  - Finche' il base plan non e' attivo e prezzato, `BillingService.loadProduct()` restituisce `null` e l'app mostra "Abbonamento non ancora disponibile su questo store".
  - Callable deployata: `verifyGooglePlayPurchase` in `functions/google_play_billing.js`.
  - Dipendenza backend: `googleapis`.
  - La funzione aggiorna `users/{uid}` con `role=premium`, `premiumUntil`, `premiumSource=google_play` e `googleSubscription`; scrive storico in `account_history`.
  - **ATTENZIONE (corretto 02/07/2026)**: il service account reale che esegue le Cloud Functions Gen2 di questo progetto e' `776660339631-compute@developer.gserviceaccount.com` (default compute, verificato con `gcloud functions describe ... --format="value(serviceConfig.serviceAccountEmail)"`), **non** `saveit-app-1784d@appspot.gserviceaccount.com` come scritto qui in precedenza. E' questo l'account da autorizzare in Play Console → Impostazioni → Accesso API, con permessi su ordini/abbonamenti (e dati finanziari se richiesti). Nessuna funzione imposta un service account custom (verificato in `functions/index.js`, nessun `setGlobalOptions`/opzione `serviceAccount`).
  - **Prerequisito GCP separato dal service account**: l'API "Google Play Android Developer" (`androidpublisher.googleapis.com`) deve essere abilitata sul progetto GCP `saveit-app-1784d`, altrimenti `verifyGooglePlayPurchase` fallisce con 403 "API has not been used in project ... or it is disabled" **prima ancora** di arrivare al controllo permessi Play Console. Verifica: `gcloud services list --enabled --project saveit-app-1784d | Select-String androidpublisher`. Abilitazione: `gcloud services enable androidpublisher.googleapis.com --project saveit-app-1784d` (nessun deploy/build richiesto, effetto immediato lato server).

- **Google Sign-In Android da Play Store**:
  - Firebase Android app corretta: `eu.savein.app`.
  - Aggiunti in Firebase gli SHA Play App Signing:
    - SHA-1: `84:7D:B1:D6:ED:63:D9:4D:E0:E3:33:D0:51:43:77:91:6F:95:B1:27`
    - SHA-256: `88:71:25:D3:62:D3:2D:B6:FE:69:67:68:F8:02:BB:04:53:90:30:90:58:0C:69:5E:C6:12:9F:55:FD:95:4C:BD`
  - Dopo aggiunta SHA, scaricare e sostituire `android/app/google-services.json`.
  - Serve nuova `.aab` per incorporare `google-services.json`; non serve deploy Firebase.

- **Account page / Premium UI**:
  - Utenti Free: pulsante diretto `Diventa Premium` in Account.
  - Dialog Free/Premium: se il prodotto store e' disponibile mostra il bottone acquisto con prezzo e `Ripristina acquisti`.
  - Utenti Premium/Admin: mostra `Scadenza Premium`; per Premium store mostra box "Rinnovo automatico gestito dallo store" con pulsante `Gestisci rinnovo automatico`.
  - Link gestione abbonamenti:
    - iOS: `itms-apps://apps.apple.com/account/subscriptions`
    - Android: `https://play.google.com/store/account/subscriptions?package=eu.savein.app&sku=savein_premium_monthly`
  - Popup `Versione corrente`: usa `package_info_plus` per mostrare versione/build reali e testo non deve andare in overflow.

- **Logout**:
  - `AuthService.logout()` pulisce subito `_currentUser`, listener profilo e cache locale prima di attendere `FirebaseAuth.signOut()`.
  - `AccountPage` dopo logout torna al root navigator (`AuthWrapper`) invece di creare manualmente una nuova `LoginPage`.
  - Fix build successivo: nei dialog usare `builder: (dialogContext)` se si chiama `Navigator.pop(dialogContext)`.

- **Release/build**:
  - Versione mobile aggiornata a `1.0.0+20` (poi progressivamente a `1.0.0+27`, vedi sezione fix logout/login/cache sotto).
  - Qualsiasi modifica Flutter (`lib/...`, `pubspec.yaml`, `google-services.json`) richiede nuova build/release app.
  - Modifiche solo Play Console su prezzo/base plan abbonamento non richiedono build ne' deploy.
  - Deploy Firebase necessario solo per Functions/Hosting/Firestore rules modificati; non necessario per cambio `google-services.json`, prezzo Play o fix Flutter gia committato.

### Fix logout/login/cache post-review (build `1.0.0+21` → `1.0.0+27`)

- **Logout bloccato in home vuota**: `AuthWrapper` convertito da `StatelessWidget` a `StatefulWidget` (stream `AuthService().userStream` cachato una volta in `initState`). Logout (`AccountPage`, `LogoutButton`) usa sempre `navigatorKey.currentState.popUntil((route) => route.isFirst)`, mai `pushAndRemoveUntil` che distruggerebbe l'`AuthWrapper` reattivo.
- **Login email non navigava subito alla home**: `AuthWrapper` ora usa anche un `AnimatedBuilder` su `AuthService` (che e' un `ChangeNotifier`) oltre allo `StreamBuilder`; da' priorita' a `authService.isLoggedIn`/`authService.currentUser` come fonte di verita', perche' `notifyListeners()` e' sincrono mentre `authStateChanges()` puo' arrivare in ritardo. Login Google/Apple/email non fanno piu' navigazione manuale: si affidano tutti alla reattivita' di `AuthWrapper`.
- **Dati utente precedente visibili dopo cambio account**: `DataService.handleUserLogout()` ora accetta `previousUserId` e pulisce sempre tutte le cache multi-utente (`_userFoldersCache`, `_userPostsCache`, `_cacheTimestamps`) piu' la cache globale di `FirebaseDataService` (`clearCache()`), non solo quella dell'utente noto. `FolderServiceBase.handleAuthenticationChange()` chiama `DataService.instance.handleUserLogout()` anche nel logout normale, non solo nel cambio tra due utenti autenticati.
- **Regressione logout Google (restava in home)**: aggiunta rete di sicurezza in `WebHomePage` (`main.dart`): se resta visibile 400ms dopo che `AuthService().isLoggedIn` e' gia' `false`, forza `pushAndRemoveUntil` con un `AuthWrapper` nuovo.
- **Splash screen Android con logo tagliato**: rigenerato `android/app/src/main/res/drawable-xxxhdpi/splash_logo.png` con sfondo trasparente e padding sufficiente per non farlo tagliare dalla maschera adattiva Android.

### Bug Premium Android non attivato dopo acquisto riuscito (02/07/2026)

- **Sintomo**: utente completa pagamento su Google Play (esito positivo lato store), ma l'app resta "Free"; `AuthService().reloadCurrentUserFromFirestore()` non trova mai `role=premium` perche' non e' mai stato scritto.
- **Causa reale (da `firebase functions:log --only verifyGooglePlayPurchase`)**: l'API **"Google Play Android Developer"** (`androidpublisher.googleapis.com`) non era abilitata sul progetto GCP `saveit-app-1784d` → la funzione falliva con 403 *"Google Play Android Developer API has not been used in project ... or it is disabled"* prima di poter verificare il token e scrivere su Firestore.
- **Fix applicato**: `gcloud services enable androidpublisher.googleapis.com --project saveit-app-1784d`. E' una impostazione di progetto, non serve deploy funzioni ne' nuova build app; effetto immediato (Google consiglia di attendere pochi minuti per la propagazione).
- **Verifica service account reale**: `776660339631-compute@developer.gserviceaccount.com` (default compute Gen2, confermato con `gcloud functions describe verifyGooglePlayPurchase --format="value(serviceConfig.serviceAccountEmail)"`), **non** `saveit-app-1784d@appspot.gserviceaccount.com`.
- **CONFERMATO 02/07/2026 con test reale**: impersonando quel service account (`gcloud auth print-access-token --impersonate-service-account=... --scopes=androidpublisher`) e chiamando direttamente `androidpublisher.googleapis.com/.../subscriptionsv2/tokens/...`, la prima risposta era `401 permissionDenied: "The current user has insufficient permissions to perform the requested operation"`. Causa: in Play Console era autorizzato solo `saveit-app-1784d@appspot.gserviceaccount.com` (il vecchio riferimento errato di questa bibbia), non il service account reale.
  - **IMPORTANTE**: nel 2026 Play Console **non ha piu' la pagina "Accesso API"** (deprecata/rimossa). La gestione dei service account passa ora da **Utenti e autorizzazioni** → **Invita nuovi utenti** → inserire l'email del service account (`776660339631-compute@developer.gserviceaccount.com`) → tab **Autorizzazioni app** → **Aggiungi applicazione** → selezionare SaveIn! (`eu.savein.app`) → spuntare almeno **"Visualizza dati finanziari, ordini e risposte ai sondaggi sulle cancellazioni"** e **"Gestisci ordini e abbonamenti"** → Salva. Il service account compare subito in elenco (senza accettazione invito), ma se non gli si assegnano anche le **Autorizzazioni app** specifiche per SaveIn (sezione separata, va aggiunta esplicitamente con "Aggiungi applicazione"), l'accesso API resta comunque negato.
  - **RISOLTO E RI-VERIFICATO 02/07/2026**: dopo aver aggiunto `776660339631-compute@developer.gserviceaccount.com` in Utenti e autorizzazioni con autorizzazioni app su SaveIn! (finanza/ordini + gestione ordini e abbonamenti), lo stesso test di impersonazione ora restituisce `400 "Invalid Value"` (perche' il token usato per il test era fittizio) invece di `401 permissionDenied` — la classe di errore e' cambiata da "non autorizzato" a "richiesta malformata", il che conferma che l'autorizzazione Play Console ora funziona. `verifyGooglePlayPurchase` dovrebbe quindi funzionare correttamente con un vero acquisto/token.
  - Nota: se in futuro serve rifare questo test diagnostico, ricordarsi di ripulire il ruolo IAM temporaneo `roles/iam.serviceAccountTokenCreator` dato a se stessi per l'impersonazione (va rimosso subito dopo il test con `gcloud iam service-accounts remove-iam-policy-binding`).
  - **Equivalente su iOS?** No: `verifyAppStorePurchase`/`appStoreWebhook` (`functions/app_store_billing.js`) non passano da un'API Google Cloud da abilitare, usano l'App Store Server API di Apple autenticata con chiave privata (`APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` in `functions/.env`). Verificato che questi valori sono gia' presenti e deployati sulla funzione live (`gcloud functions describe verifyAppStorePurchase --format="value(serviceConfig.environmentVariables)"`). Questo specifico bug non puo' quindi ripetersi su iOS; l'unico rischio analogo sarebbe una chiave App Store Connect API revocata/rigenerata in futuro, da aggiornare in `functions/.env` e ridistribuire con `firebase deploy --only functions`.
  - **Test reale credenziali Apple (02/07/2026)**: chiamata diretta a `client.requestTestNotification()` (metodo ufficiale della libreria `@apple/app-store-server-library` per validare le credenziali) con le stesse `APPLE_ISSUER_ID`/`APPLE_KEY_ID`/`APPLE_PRIVATE_KEY` in uso:
    - **SANDBOX → OK**, token di test ricevuto correttamente: le credenziali/chiave sono valide e ben configurate.
    - **PRODUCTION → 401**: comportamento **atteso e documentato da Apple** (confermato da staff Apple sui forum e issue ufficiali delle librerie `app-store-server-library`), non un errore di configurazione: Apple nega l'accesso alle API Production di App Store Server finche' l'app non ha **almeno una versione pubblicata/live sull'App Store**. Non appena SaveIn viene approvata e pubblicata per la prima volta, l'endpoint Production iniziera' a funzionare automaticamente, senza bisogno di modificare `.env` o rideployare nulla.
    - Quindi: nessuna azione da fare ora lato Apple/codice; da ricontrollare solo dopo la prima pubblicazione live su App Store (se dopo il rilascio un acquisto reale in produzione dovesse ancora fallire con 401, allora si' da approfondire).

### Fix dashboard: utente Premium scaduto mostrato ancora "Premium" (02/07/2026)

- **Sintomo**: nella dashboard admin, un utente con `premiumUntil` gia' passato veniva mostrato con badge ruolo "Premium" (blu) mentre la colonna scadenza lo segnalava gia' in rosso come scaduto.
- **Causa**: `_AdminUserRecord` (modello usato solo da `admin_dashboard_page.dart`) non aveva un equivalente di `User.effectiveRole` (gia' presente lato app in `auth_service.dart`): i badge leggevano il campo grezzo `role` di Firestore senza controllare la scadenza.
- **Fix**: aggiunto `_AdminUserRecord.effectiveRole` (stessa logica di `User.effectiveRole`: premium valido solo se `premiumUntil` e' oggi o futuro). Applicato ai 3 badge ruolo (tabella utenti, tabella storico/marketing, vista dettaglio) e al `Filtro ruolo` della ricerca. Il dropdown di modifica manuale del ruolo continua a mostrare `user.role` grezzo (e' il campo che si sta effettivamente editando).
- **Deploy**: solo web, nessuna build mobile richiesta. `flutter build web --release` + `firebase deploy --only hosting`, gia' pubblicato su `https://savein.eu/dashboard`.

## Aggiornamenti 03/07/2026

- **AdMob iOS SaveIn — ID reali creati**: sostituiti gli ID di test Google in `lib/services/interstitial_ad_service.dart` con gli ID reali creati su AdMob:
  - Interstitial iOS: `ca-app-pub-1397392558961350/9950660131`
  - Banner iOS: `ca-app-pub-1397392558961350/4315988838`
  - **Nota**: gli ads restano comunque disattivati lato codice su iOS (`_shouldUseAds` in `InterstitialAdService`, controllo `TargetPlatform.iOS` in `BannerAdWidget`), scelta presa per l'App Store rejection fix build `1.0.0+20`. Con gli ID reali pronti, riattivarli su iOS e' ora solo questione di rimuovere quei controlli quando si decide di farlo.
  - Serve una **nuova build iOS** (bump versione, Codemagic → TestFlight) perche' il cambio ID sia effettivo; finche' non si fa una nuova build i dispositivi iOS gia' installati continuano a usare il binario con gli ID vecchi (anche se comunque gli ads iOS sono disattivati lato codice, quindi impatto pratico nullo finche' restano disattivati).
- **Tentativo collegamento store in AdMob**: provato a collegare l'app Android SaveIn in AdMob per rimuovere il limite "Pubblicazione annunci limitata" — AdMob non trova l'app perche' SaveIn Android e' ancora in test chiuso su Play Store, non pubblicata pubblicamente. Da riprovare dopo il rilascio in produzione. Rimandato dall'utente, nessuna azione ulteriore per ora.
- **SmartChef**: nella stessa sessione sono stati creati e inseriti anche gli ID AdMob iOS reali per SmartChef (progetto separato, vedi `SMART_CHEF_BIBLE.md` e `SMART_CHEF_ADS_SETUP_TODO.md` nella root di `smart_chef_sm`).
- **App Store Connect — sopralluogo distribuzione (03/07/2026)**:
  - **Webhook produzione**: gia' configurato correttamente, `https://us-central1-saveit-app-1784d.cloudfunctions.net/appStoreWebhook?secret=webhookSTOREerotskoohbew` (il secret corrisponde a `APP_STORE_WEBHOOK_SECRET` in `functions/.env`).
  - **Webhook sandbox**: confermato configurato il 03/07/2026, stesso URL/secret della produzione.
  - **Esenzione crittografia**: aggiunta `ITSAppUsesNonExemptEncryption = false` in `ios/Runner/Info.plist` per evitare di dover confermare manualmente la documentazione crittografia ad ogni caricamento build (l'app usa solo HTTPS/TLS standard, nessuna crittografia proprietaria).
  - **Stato "1.0 Respinta"**: la prima build/versione risulta ancora segnata come respinta da Apple in App Store Connect (rejection precedente, probabilmente la stessa gia' risolta col fix build `1.0.0+20`: Sign in with Apple, interstitial iOS). Prima di ripresentare la prossima build, ricontrollare il testo esatto del rifiuto in "Verifica dell'app" per conferma che sia tutto coperto.
  - **Normativa sui servizi digitali (Digital Services Act UE)**: risultava "non si identifica come operatore commerciale" — completata dall'utente il 03/07/2026 (dati Azienda/Contratti in App Store Connect: "Dino Pasi", contratto app gratuite e app a pagamento entrambi Attivi). Dopo il caricamento del documento d'identita' per conferma nome, lo stato e' passato a **"Verifica in corso"** (revisione manuale Apple, nessuna azione richiesta, attendere).
  - **DAC7 (Direttiva sulla cooperazione amministrativa – 7° emendamento)**: completata il 03/07/2026, stato **Attivo**. Alla domanda "Qualcuna delle tue app fornisce servizi personali in qualche paese o regione?" risposto **No** (SaveIn vende solo abbonamento/contenuto digitale, non servizi personali tipo trasporto/consegne/lavori freelance).
  - Non necessari per SaveIn: numero ICP Cina, licenza gioco Vietnam, dispositivi medici regolamentati, chiave condivisa specifica dell'app (quest'ultima e' per la verifica ricevute legacy StoreKit 1; il backend usa l'App Store Server API con chiave privata).

### 2026-07-03 - Elimina account: perdita dati se serve riautenticazione ("requires-recent-login")

- **Sintomo**: dopo "Elimina account" dall'app, l'utente veniva riportato alla Home **vuota** invece che al Login.
- **Causa**: `AuthService.deleteAccount()` cancellava **prima tutti i dati Firestore** (`_deleteCurrentUserData`: cartelle, post, ecc.) e **solo dopo** provava a eliminare l'account Firebase Auth (`firebaseUser.delete()`). Firebase richiede una sessione "recente" per operazioni sensibili come `delete()`: se l'utente non aveva fatto login di recente, questa chiamata falliva con `requires-recent-login`. A quel punto i dati erano gia' spariti ma `_currentUser` non veniva mai azzerato (si azzerava solo nel percorso di successo), quindi l'utente restava tecnicamente loggato → tornava alla Home, ormai svuotata. Non c'era nessun passaggio di riautenticazione prima di eliminare (il dialog di conferma aveva gia' un avviso "Potrebbe essere richiesta la riautenticazione", ma non era mai stato implementato).
- **Fix** (`lib/services/auth_service.dart`, `lib/pages/account_page.dart`):
  - Aggiunto `AuthService._reauthenticateForDeletion()`: riautentica l'utente **prima** di toccare qualunque dato, in base al provider (`google.com` → nuovo `_googleSignIn.signIn()`; `apple.com` → nuovo flusso Sign in with Apple; `password` → richiede la password attuale). Se la riautenticazione fallisce o viene annullata, l'eliminazione si interrompe subito e **nessun dato viene toccato**.
  - `AuthService.currentAccountUsesPassword` (nuovo getter pubblico): la UI lo usa per capire se mostrare il campo password nel dialog di conferma eliminazione (`_showDeleteAccountDialog` in `account_page.dart`), che ora ha un `TextField` password quando l'account e' email/password.
  - `deleteAccount({String? currentPassword})`: nuovo parametro opzionale per passare la password quando serve.
  - Difesa aggiuntiva: se anche dopo la riautenticazione `firebaseUser.delete()` fallisse per un motivo imprevisto (i dati Firestore sono gia' stati cancellati a quel punto), l'utente viene comunque disconnesso localmente (`_forceLocalSignOutAfterPartialDeletion`) invece di restare "loggato" con un account svuotato — cosi' l'app torna sempre al Login e mai a una Home vuota.
- **Verifica**: `flutter analyze` pulito sui file modificati (nessun errore nuovo, solo warning/info preesistenti). Da testare manualmente: eliminazione account Google/Apple/password su un account con sessione non recente.

### 2026-07-03 - Registrazione Google su dispositivo reale: cartella "Tutti" non visibile subito + errore creando una cartella

- **Segnalazione**: su un Samsung S22, appena registrato un nuovo account con Google (utente di test `riccardogregori84@gmail.com`), la cartella "Tutti" non appariva subito e il primo tentativo di creare una cartella non dava alcun feedback ("non ha fatto nulla").
- **Analisi effettuata prima di intervenire** (vedi anche verifica diretta su Firestore/Firebase Auth per l'account di test): sia la cartella di default "Tutti" sia una cartella creata manualmente ("Cibo") **risultavano presenti e corrette su Firestore**, create rispettivamente ~1s e ~43s dopo la registrazione — quindi non c'e' stata perdita o corruzione di dati, il problema e' un **problema di tempismo lato client** subito dopo un login/registrazione fresca su un dispositivo reale.
- **Causa individuata**: `FolderServiceCRUD.createPersistentFolder()` (usata dal pulsante "+" per creare cartelle) controllava `isAuthenticated`/`currentUserId` — campi **cache locali** del mixin `FolderServiceBase`, aggiornati in modo reattivo quando `AuthService` notifica un cambio di stato — e lanciava subito `Exception('User not authenticated')` se non erano ancora sincronizzati, senza nessun ritentativo. Un pattern di "resync" per questa stessa race condition esisteva gia' altrove nel codice (`executeAuthenticatedOperation` e `_syncAuthFromAuthServiceIfNeeded` in `folder_service_sync.dart`, entrambi con commenti "FIX RACE CONDITION") ma **non era applicato** ai metodi di creazione cartelle.
- **Fix**:
  - `lib/services/folder_service_crud.dart`: aggiunto `_resyncAuthStateIfNeeded()` (stesso pattern gia' usato altrove: se `isAuthenticated`/`currentUserId` non sono allineati, li risincronizza da `AuthService().currentUser` prima di controllare), applicato sia in `createPersistentFolder()` sia nella creazione sottocartelle.
  - `lib/data_service.dart`: aggiunto `_ensureAuthReadyForOperation()`, richiamato all'inizio di `_executeWithOptimizedCache` (usato da `createFolder`, `getFolders`, ecc.): se Firebase Auth ha gia' una sessione valida ma `AuthService` non e' ancora sincronizzato, attende fino a ~1.5s (poll ogni 150ms) prima di considerare l'operazione non autenticata, invece di fallire all'istante. Non ha alcun impatto quando l'utente e' davvero disconnesso (`FirebaseAuth.instance.currentUser == null` → nessuna attesa).
- **Nota**: non e' stato possibile catturare il messaggio di errore esatto dal dispositivo (l'app non ha Crashlytics configurato), quindi questo e' un fix preventivo basato sull'evidenza Firestore (i dati arrivano sempre, solo con un breve ritardo) e su un gap di codice concreto e gia' pattern-matchato altrove nel progetto. Se il problema si ripresentasse, andrebbe considerato aggiungere Crashlytics per avere log precisi da dispositivi reali.

### 2026-07-03 (continua) - Il fix sopra NON ha risolto: "Tutti" ancora invisibile, creazione cartella "non fa nulla"

- **Retest dell'utente sulla build 31**: l'eliminazione account (fix precedente) ora funziona, ma su Samsung S22 "Tutti" continua a non apparire e creare una cartella "non accade nulla" — quindi il fix di resync auth (`_resyncAuthStateIfNeeded`/`_ensureAuthReadyForOperation`) non era la causa reale, o non e' l'unica.
- **Causa individuata analizzando `_buildFoldersGrid()` in `lib/main.dart`**: quando `_getSortedFolders()` ritorna una lista vuota (cioe' `_folderService.folders` e' vuoto — la sincronizzazione cartelle non e' mai riuscita, non solo "in ritardo"), la Home mostrava **solo** il testo "Trascina verso il basso per aggiornare le cartelle", **senza nessuna cartella "Tutti" ne' alcun messaggio d'errore reale**. Un fallimento persistente di `initializeHybridData()`/`syncStartupWithDataService()` (es. errore di rete/permessi specifico del dispositivo) restava quindi completamente invisibile: l'utente vedeva solo un generico invito a fare pull-to-refresh, senza sapere che qualcosa era effettivamente fallito ne' perche'.
- **Perche' "creare una cartella" sembrava non fare nulla**: non abbiamo evidenza diretta (l'utente non ha notato un dialog di errore), ma se la sincronizzazione cartelle fallisce in modo persistente per lo stesso motivo di fondo (es. problema di rete/permessi ricorrente su quel dispositivo), e' plausibile che anche la scrittura Firestore in `createPersistentFolder` fallisca allo stesso modo — il codice ha gia' un `try/catch` che dovrebbe mostrare un dialog con l'errore (`_showRetryDialog`), ma non avendo il messaggio esatto non possiamo confermare al 100% dove si perde.
- **Fix implementato** (per rendere visibile l'errore reale al prossimo test, invece di continuare a indovinare "alla cieca"):
  - `lib/main.dart`: nuovo `_buildEmptyFoldersState()` che legge `FolderService().currentHealth` (gia' popolato con `status`/`errorMessage` dai punti di sync esistenti in `folder_service_sync.dart`, es. `'Startup sync failed: $e'`). Se lo stato e' `error`/`degraded`/`offline`, mostra l'errore reale + un pulsante **"Riprova"** esplicito (richiama `_initializeFolderService()`); altrimenti resta il messaggio generico "Trascina per aggiornare".
  - `_onPullToRefresh()`: un fallimento ora mostra uno `SnackBar` rosso con il testo dell'eccezione, invece di solo un `print` in debug.
- **Prossimo passo**: al prossimo test su un dispositivo che riproduce il problema, il messaggio d'errore mostrato in Home (o nello SnackBar del pull-to-refresh) dara' finalmente l'informazione mancante per identificare la causa esatta (es. `PERMISSION_DENIED`, timeout di rete, errore specifico Firestore, ecc.). Se il problema si ripresenta ancora, sarebbe il momento di aggiungere Crashlytics per avere log strutturati da dispositivi reali invece di doversi basare sul testo mostrato a schermo.
- **UI aggiuntiva**: su richiesta, centrati titolo e sottotitolo della pagina di Login ("Accedi al tuo account" / "Accedi per gestire i tuoi contenuti salvati", e la variante "Bentornato!" per coerenza) in `lib/pages/login_page.dart`.
- Versione bumpata a **1.0.0+32**.

### 2026-07-03 (continua) - Verifica Firestore: le cartelle vengono create, ma la Home non le renderizza

- **Retest utente dopo il fix `+32`**: nessun errore mostrato, "Tutti" ancora invisibile e nuova cartella apparentemente non creata.
- **Verifica server-side effettuata su Firebase Auth + Firestore**:
  - L'account `riccardogregori84@gmail.com` ha cambiato UID dopo la nuova registrazione: vecchio UID `LUpx0NJdebQbX3lmu57hNG9RuUY2`, nuovo UID `bkKGRI6pVWZbM21CZ62ku6P9Yq42`.
  - Nel nuovo UID Firestore, sotto `users/bkKGRI6pVWZbM21CZ62ku6P9Yq42/folders`, esistono gia':
    - cartella default **"Tutti"** (`isDefault=true`, creata subito dopo registrazione);
    - cartella utente **"Cibo"** (`isDefault=false`, creata dopo il tap su "Crea").
  - Conclusione: **la scrittura funziona e Firestore contiene i dati corretti**. Il problema e' la Home Flutter che resta su lista locale/cache vuota e non renderizza i dati server-side.
- **Stato del fix**:
  - Il tentativo di listener diretto Firestore sulla Home e' stato rimosso: peggiorava il flusso login su alcuni dispositivi e non va mantenuto.
  - `lib/services/folder_service_sync.dart`: corretto `updateTuttiCount()`. Prima aggiungeva "Tutti" solo se `folders.isEmpty`; se la lista locale conteneva una cartella utente ma mancava la speciale "Tutti", usava per errore `folders.first` come fallback. Ora, se non trova nessuna `isSpecial`, inserisce "Tutti" in testa anche quando ci sono gia' altre cartelle.
  - `lib/main.dart`: resta disponibile un reload one-shot da Firestore (`_reloadHomeFoldersFromFirestoreOnce`) per evitare listener invasivi e poter forzare caricamenti mirati se necessario.
- Versione bumpata a **1.0.0+33**.

### 2026-07-04 - Promo benvenuto: errore `already-exists` e chiarimento Google/iOS

- **Sintomo**: attivando la promo benvenuto dall'app, veniva mostrato un riquadro rosso con stack tecnico Flutter e errore `[firebase_functions/already-exists] Hai gia utilizzato questa promo.`
- **Causa**: il backend funzionava correttamente: la promo benvenuto e' **una tantum per email** e viene tracciata in `new_signup_premium_promo_claims/{normalizedEmail}`. Se la stessa email ha gia usato la promo e la scadenza e' passata, `activateNewSignupPremiumPromo` blocca il riutilizzo con `already-exists`. Esempio verificato: `pasidino@gmail.com` aveva una vecchia claim del 24/06/2026 gia scaduta.
- **Chiarimento Google Play / iOS**: questa promo **non passa dagli acquisti in-app** e non richiede configurazioni specifiche su Google Play o App Store. E' un grant server-side: Cloud Function scrive `role=premium`, `premiumUntil`, `premiumSource=new_signup_promo` su Firestore. Gli store servono solo per gli abbonamenti pagati (`savein_premium_monthly`), non per il mese gratuito di benvenuto gestito da backend.
- **Configurazione server verificata**: `app_config/new_signup_premium_promo` e' attiva, `durationDays=30`, `priceAfterTrial=1.99`, `app=savein`.
- **Fix client**:
  - `AuthService.activateNewSignupPremiumPromo()` ora chiama prima `getNewSignupPremiumPromoEligibility()` e, se `canClaim=false`, blocca localmente con un messaggio pulito invece di chiamare comunque la funzione di attivazione.
  - Gestione esplicita di `FirebaseFunctionsException` (`already-exists`, `failed-precondition`, `unauthenticated`) con messaggi utente leggibili.
  - `AccountPage._buildNewSignupPromoAccountNotice()` ora usa l'eligibility reale: il riquadro promo non appare piu se la promo non e' riscattabile.
  - Popup automatico Home e pagina Account puliscono il messaggio di errore, evitando stack trace tecnici in UI.
- **Fix anti-abuso account deletion**:
  - `AuthService._deleteCurrentUserData()` non cancella piu `new_signup_premium_promo_claims` quando l'utente elimina l'account.
  - Anche i cleanup backend (`functions/index.js`, `functions/cleanup_orphan_users.js`) preservano `new_signup_premium_promo_claims`.
  - Motivo: la claim e' storico permanente per email; deve sopravvivere alla cancellazione account per impedire "uso promo → cancello account → mi registro di nuovo → riuso promo".
- **Nota test**: per ritestare la promo con la stessa email serve cancellare manualmente la claim in `new_signup_premium_promo_claims` (solo per test controllati) oppure usare un'email nuova mai premiata.
- **Cleanup utenti cancellati**:
  - La funzione `cleanupUserDataOnDelete` e' stata ridistribuita il 04/07/2026 su `saveit-app-1784d`.
  - Quando un utente viene eliminato da Firebase Auth, il backend pulisce ricorsivamente i dati Firestore collegati all'utente, evitando documenti utente vuoti/orfani nella console.
  - Le claim in `new_signup_premium_promo_claims` restano escluse dalla pulizia per mantenere lo storico permanente anti-abuso della promo benvenuto.

### 2026-07-06 - Tutorial automatico e consenso notifiche

- **Tutorial automatico dopo reinstall/login**:
  - `SaveInFirstLaunchTutorial.showIfNeeded()` non si basa piu solo su `SharedPreferences`, perche' dopo disinstall/reinstall la preferenza locale sparisce.
  - Prima di mostrare il tutorial automatico, controlla i dati reali dell'utente tramite `DataService`: se esiste almeno una cartella diversa da `Tutti` oppure almeno un post salvato, il tutorial viene marcato come gia visto e non compare.
  - Il tutorial resta sempre apribile manualmente dalla pagina Account tramite `Rivedi tutorial`, che chiama `SaveInFirstLaunchTutorial.show()` e non passa da `showIfNeeded()`.
- **Consenso notifiche**:
  - `AppNotificationService.initializeForUser()` non chiede piu subito il permesso push all'avvio/login; inizializza listener e token senza mostrare il popup di sistema.
  - `ReminderService.initialize()` su iOS non richiede piu permessi automaticamente (`DarwinInitializationSettings` con `requestAlertPermission/requestBadgePermission/requestSoundPermission=false`).
  - La richiesta consenso notifiche viene attivata da `main.dart` solo dopo la creazione riuscita della prima cartella utente reale (nome diverso da `Tutti`) e solo se prima non esistevano gia cartelle reali.
  - La richiesta viene tracciata con chiave locale per utente (`notification_consent_requested_after_first_folder_{uid}`) per non riproporla a ogni nuova cartella.

### 2026-07-06 - Reminder collegati ai limiti piani dashboard

- Aggiunta la funzione `reminders` in **Configurazione Limiti Piani** (dashboard Flutter e pagina web `/dashboard/limits`).
- Configurabile per Free/Premium come le altre funzioni: abilitato, limite, periodo reset, richiede pubblicità.
- Default: Free abilitato con pubblicità richiesta; Premium abilitato senza pubblicità; limite 0 (illimitato) su entrambi.
- L'app rispetta le regole su: apertura dialog reminder, salvataggio nuovo reminder, banner reminder del giorno e gate pubblicità configurabile da dashboard.
- Versione locale corrente: **1.0.0+40**.

## Aggiornamenti 08/07/2026

- **Pagine web assistenza/marketing per App Store Connect**:
  - Aggiunti `web/support.html` e `web/marketing.html` (stile SaveIn!, colori `#1a1a2e` / `#e0f2fe`).
  - **Assistenza**: email `support@savein.eu`, FAQ (accesso, contenuti, salvataggio link, eliminazione account, Contattaci in app).
  - **Marketing**: funzioni principali (salva da social, cartelle, tag, condivisione, reminder) + pulsante Google Play `eu.savein.app`.
  - **Nota**: non usare `help@savein.app` nelle pagine pubbliche — e' un placeholder legacy in `remote_content_service.dart`; l'email operativa e' **`support@savein.eu`**.
- **Deploy hosting (08/07/2026)**:
  ```powershell
  cd C:\Users\dinop\saveit
  flutter build web --release --base-href /
  firebase deploy --only hosting --project saveit-app-1784d
  ```
  - Pagine live: https://savein.eu/support.html e https://savein.eu/marketing.html
  - **Non richiede** nuova `.aab` ne' build iOS: solo deploy Firebase Hosting.
- **App Store Connect SaveIn!**: usare gli URL sopra nei campi **URL di assistenza** e **URL di marketing** della scheda iOS.
- **SmartChef (stessa sessione)**: create anche `web/support.html` e `web/marketing.html` su `smartchef-app.com` + fix icona iOS + `AppSessionService` tutorial/promo — vedi `SMART_CHEF_BIBLE.md`.

## Aggiornamenti 13/07/2026

**Release target**: `1.0.0+41` — richiede **nuova `.aab` Android**, **nuovo build iOS** (Codemagic/TestFlight) **e** deploy Cloud Functions.

### Fix UX import e cartelle

| Area | File | Modifica |
|---|---|---|
| Dialog Premium scroll | `lib/pages/account_page.dart` | CTA acquisto + disclosure legali **dentro** lo scroll dell'ultima slide |
| Selettore cartelle import | `lib/widgets/folder_card_selector.dart` | 1 tap apre+seleziona; foglia seleziona senza chiudere dialog; `showFolderLimitInfo: false` in import |
| Separatore path corrotto | `lib/services/sharing_service.dart` | Path cartelle con `›` corretto (fix mojibake) |
| Anteprima post post-import | `sharing_service`, `folder_service_sharing`, `folder_service_sync`, `folder_detail_page`, `main.dart` | ID post reale; upsert mock post; refresh UI con `highlightPostId`; merge `previewStorageUrl` in sync |
| Limiti cartelle in import | `folder_card_selector.dart` | Nascosto conteggio limiti livelli in basso durante scelta cartella |

### DB comune `global_posts` e dedup cross-utente

- Nuova Cloud Function **`getGlobalPostByUrl`**: lookup read-only, no incremento `saveCount`.
- Client: `GlobalPostLookupService` + `UrlMetadataService.resolveImportMetadata()` — controlla cache globale **prima** dello scraping.
- Al salvataggio: `ensureGlobalPost` collega post utente a metadati condivisi.
- Campo `metadataProvider` su nuovi record globali (`client_scrape` default; preparato per futuro SociaVault).
- **SaveIn non usa SociaVault** — dedup evita re-scrape quando un altro utente ha gia' importato lo stesso URL.

### Ordine release consigliato (13/07/2026)

**1. Codice e versione**
```powershell
cd C:\Users\dinop\saveit
# pubspec.yaml → version: 1.0.0+41
flutter analyze
```

**2. Deploy Firebase Functions (obbligatorio per dedup)**
```powershell
cd C:\Users\dinop\saveit\functions
# index.js e' pesante (~7–11s load): alza timeout discovery altrimenti deploy fallisce a 10s
$env:FUNCTIONS_DISCOVERY_TIMEOUT="120000"
firebase deploy --only functions:getGlobalPostByUrl,functions:ensureGlobalPost --project saveit-app-1784d
```
Errore tipico senza timeout: `User code failed to load. Cannot determine backend specification. Timeout after 10000`.

**3. Build Android**
```powershell
cd C:\Users\dinop\saveit
flutter clean
flutter pub get
flutter build appbundle --release
```
Output: `build\app\outputs\bundle\release\app-release.aab`

**4. Play Console** — Test interni → carica `.aab` `1.0.0+41` → note release → tester opt-in.

**5. Build iOS** — Codemagic → TestFlight (stesso build number).

**6. Dashboard web** (solo se modificata): `flutter build web --release --base-href /` + `firebase deploy --only hosting`.

**7. Verifica post-release** — import social; anteprima subito in cartella; stesso URL su secondo account → metadati da `global_posts`; selettore cartelle senza banner limiti.

## Aggiornamenti 16/07/2026 — Share Extension nativa isolata (build `1.0.0+44`)

Le implementazioni sperimentali delle build 45–50 descritte sopra sono state
annullate. La nuova implementazione riparte dalla build stabile 42 senza
`receive_sharing_intent` sul target iOS.

### Architettura validata

- Target nativo `ShareExtension` (`eu.savein.app.ShareExtension`), senza Flutter
  né plugin CocoaPods.
- App Group condiviso: `group.eu.savein.app.share`.
- Il Runner esporta nell'App Group un catalogo JSON delle cartelle, inclusi
  ID, gerarchia e percorso completo.
- La Share Extension mostra il selettore cartelle nativo, riceve URL o testo
  contenente un URL e accoda atomicamente la richiesta di salvataggio.
- Il Runner importa la coda al successivo avvio/rientro in primo piano,
  recupera i metadati e salva il post tramite il flusso Firebase esistente.
- Se una cartella è stata eliminata, l'import usa `Tutti`; una richiesta
  appartenente a un altro account non viene importata.
- `tool/validate_ios_share_bundle.py` resta il controllo obbligatorio
  dell'artefatto `.app`/`.app.zip` prodotto da Codemagic.

### Sequenza test build 44

1. Aprire SaveIn! ed effettuare il login, così il catalogo cartelle viene
   esportato.
2. Safari → Condividi → SaveIn!.
3. Verificare URL, elenco gerarchico delle cartelle, selezione e pulsante
   `Salva`.
4. Riaprire SaveIn! e verificare che il post compaia nella cartella scelta.
5. Ripetere con un post social che fornisce un URL o testo contenente un URL.

### Build `1.0.0+46` — selettore gerarchico, cartelle e tag

- Il selettore della Share Extension mostra inizialmente solo le cartelle root;
  `▸`/`▾` apre e chiude le sottocartelle.
- `+ Nuova cartella` accoda la creazione alla radice (se è selezionato `Tutti`)
  o dentro la cartella selezionata; il Runner la crea su Firebase prima del post.
- Campo tag opzionale: massimo 20 tag separati da virgola, uniti senza duplicati
  agli hashtag estratti dai metadati.
- I post provenienti dalla nuova extension iOS non mostrano il badge
  `post importato`; Android mantiene il comportamento esistente.

### Build `1.0.0+47` — azioni contestuali e limiti dashboard

- Il pulsante `+` è accanto a ogni cartella: su `Tutti` crea una root, sulle
  altre crea una sottocartella.
- I nomi root non ripetono più lo stesso percorso nella seconda riga.
- I tag manuali sono presentati dall'azione evidente `Aggiungi tag al post`,
  con riepilogo dei tag selezionati.
- Il Runner esporta nell'App Group i limiti correnti di `root_folders`,
  `child_folders`, `folder_levels` e `manual_tags`, letti da
  `PlanLimitsService`/dashboard.
- L'importazione ricontrolla i limiti correnti prima di creare la cartella o
  applicare tag manuali; i tag automatici estratti dai metadati restano
  indipendenti.
- Creazione Firebase e applicazione dei tag avvengono quando SaveIn! torna in
  primo piano e importa la coda, non al semplice tocco del `+` nell'extension.

### Build `1.0.0+49` — salvataggio immediato e cartelle temporanee

- Le cartelle create con `+` restano **temporanee in memoria** (etichetta
  `Temporanea`): annulla/chiudi le scarta; cambiare destinazione scarta i
  draft fuori dal percorso selezionato. Niente Firebase finché non si salva.
- `Salva` chiama l'endpoint HTTP `savePostFromShare` (Bearer ID token) e crea
  gerarchia + post subito, senza riaprire l'app. Rollback delle cartelle vuote
  se il salvataggio post fallisce. Idempotenza via `clientRequestId`.
- Il Runner esporta nell'App Group la sessione auth (`idToken`, scadenza,
  endpoint) oltre al catalogo cartelle/limiti. Serve aver aperto SaveIn!
  loggato almeno una volta prima di condividere.
- Evidenziazione riga selezionata + checkmark; `+` sempre visibile accanto a
  ogni cartella. Tag manuali restano soggetti a `manual_tags` del piano.
- La coda App Group resta come fallback per eventuali request legacy; il
  percorso primario è il salvataggio diretto dall'extension.
- Deploy obbligatorio: `firebase deploy --only functions:savePostFromShare`.

### Build `1.0.0+50` — refresh post-salvataggio e feedback UI

- Il salvataggio diretto dalla Share Extension **funzionava già** (HTTP 200),
  ma l'app non invalidava la cache al rientro: i post nuovi non comparivano.
- Dopo `Salva`, l'extension scrive `last_share_result.json` nell'App Group;
  al resume il Runner lo consuma, invalida cache cartelle/post e forza sync.
- Spinner + messaggio "può richiedere alcuni secondi" durante il salvataggio;
  conferma "Riapri SaveIn! per vederlo".
