# 🚀 Guida Completa Setup - Marketing Consent con Firestore

## 📋 Checklist Implementazione

- [x] **File modificati**:
  - ✅ `auth_service.dart` - Con sync Firestore completo
  - ✅ `firestore.rules` - Regole di sicurezza
  - ✅ Cloud Functions - Query marketing users

---

## 🔧 STEP 1: Sostituisci auth_service.dart

**File**: `lib/services/auth_service.dart`

**Azione**: Sostituisci TUTTO il contenuto del file con quello dall'artifact `auth_service_complete_firestore`

**Cosa fa**:
- ✅ Salva consenso marketing su Firestore quando modificato
- ✅ Carica consenso da Firestore al login
- ✅ Sincronizza locale ↔ cloud automaticamente
- ✅ Gestisce offline-first (funziona anche senza internet)

---

## 🔥 STEP 2: Configura Firestore Security Rules

### 2.1 Apri Firebase Console

1. Vai su: https://console.firebase.google.com
2. Seleziona il tuo progetto SaveIt
3. Menu laterale → **Firestore Database**
4. Tab **Regole** (Rules)

### 2.2 Incolla le Regole

Copia il contenuto dall'artifact `firestore_security_rules` e incollalo nell'editor.

**Clicca**: "Pubblica" (Publish)

### ✅ Verifica Regole

Le regole permettono:
- ✅ Utenti possono leggere/scrivere solo il proprio documento
- ✅ Query `list` bloccate (solo via Cloud Functions)
- ✅ Validazione dati consenso marketing

---

## ☁️ STEP 3: Deploy Cloud Functions (Opzionale ma Consigliato)

### 3.1 Installa Firebase CLI

```bash
npm install -g firebase-tools
firebase login
```

### 3.2 Inizializza Functions

```bash
cd /path/to/saveit_project
firebase init functions
```

Scegli:
- **Language**: JavaScript
- **ESLint**: Sì
- **Install dependencies**: Sì

### 3.3 Copia il Codice Functions

**File**: `functions/index.js`

Copia il contenuto dall'artifact `cloud_function_marketing`

### 3.4 Deploy

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

### ✅ Functions Deployate

Dovresti vedere:
```
✔ functions[getMarketingUsers] deployed
✔ functions[getMarketingStats] deployed
✔ functions[exportMarketingEmails] deployed
✔ functions[getMarketingUsersByDate] deployed
```

---

## 👑 STEP 4: Configura Admin per Cloud Functions

### 4.1 Imposta Custom Claim "admin"

Apri Cloud Shell nella Firebase Console e esegui:

```javascript
const admin = require('firebase-admin');
admin.initializeApp();

const email = 'tuo-admin@example.com'; // ✅ Cambia con la tua email

admin.auth().getUserByEmail(email)
  .then(user => {
    return admin.auth().setCustomUserClaims(user.uid, { admin: true });
  })
  .then(() => {
    console.log('✅ Admin claim impostato!');
  });
```

### 4.2 Verifica Admin Claim

```javascript
admin.auth().getUserByEmail('tuo-admin@example.com')
  .then(user => {
    console.log(user.customClaims); // Dovrebbe mostrare { admin: true }
  });
```

---

## 🧪 STEP 5: Testa la Sincronizzazione

### Test 1: Modifica Consenso Marketing

```
1. Avvia app → Login
2. Account Page → Toggle switch Marketing
3. Verifica log console:
   DEBUG: 🌐 Sincronizzando consenso marketing su Firestore...
   DEBUG: ✅ Consenso marketing sincronizzato su Firestore

4. Vai su Firebase Console → Firestore Database
5. Collezione "users" → Il tuo UID
6. Verifica campo: consents.marketing.accepted = true/false
```

### Test 2: Cross-Device Sync

```
1. Device A: Attiva marketing consent
2. Device B: Login con stesso account
3. Verifica log:
   DEBUG: 🌐 Caricando consenso marketing da Firestore...
   DEBUG: ✅ Consenso sincronizzato da cloud a locale
4. Device B: Account Page dovrebbe mostrare switch attivo
```

---

## 📊 STEP 6: Query Utenti per Marketing

### Metodo 1: Firestore Console (Manuale)

1. Firebase Console → Firestore Database
2. Collezione `users`
3. **Filtri**:
   - Campo: `consents.marketing.accepted`
   - Operatore: `==`
   - Valore: `true`
4. Clicca **"Applica"**

**Risultato**: Lista utenti con marketing attivo

### Metodo 2: Cloud Functions (Programmativo)

#### Chiamata da Client (Flutter)

```dart
import 'package:cloud_functions/cloud_functions.dart';

Future<void> getMarketingUsersList() async {
  try {
    final functions = FirebaseFunctions.instance;
    final result = await functions.httpsCallable('getMarketingUsers').call();
    
    final users = result.data['users'] as List;
    final count = result.data['count'];
    
    print('📧 Trovati $count utenti con marketing attivo');
    
    for (var user in users) {
      print('Email: ${user['email']}, Nome: ${user['name']}');
    }
    
  } catch (e) {
    print('Errore: $e');
  }
}
```

#### Stats Marketing

```dart
Future<void> getMarketingStatistics() async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('getMarketingStats')
      .call();
  
  final stats = result.data['stats'];
  
  print('Totale utenti: ${stats['totalUsers']}');
  print('Marketing attivo: ${stats['marketingActive']}');
  print('Percentuale: ${stats['percentage']}%');
}
```

#### Esporta Email per Campagna

```dart
Future<void> exportEmailsForCampaign() async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('exportMarketingEmails')
      .call();
  
  final emails = result.data['emails'] as List;
  final csv = result.data['csv']; // Formato CSV pronto
  
  // Usa emails per invio newsletter
  for (var user in emails) {
    sendMarketingEmail(user['email'], user['name']);
  }
}
```

### Metodo 3: Script Node.js (Backend)

```javascript
const admin = require('firebase-admin');
admin.initializeApp();

async function getMarketingEmails() {
  const snapshot = await admin.firestore()
    .collection('users')
    .where('consents.marketing.accepted', '==', true)
    .get();
  
  const emails = [];
  snapshot.forEach(doc => {
    const data = doc.data();
    emails.push({
      email: data.email,
      name: data.name
    });
  });
  
  console.log(`📧 ${emails.length} utenti con marketing attivo:`);
  console.log(JSON.stringify(emails, null, 2));
  
  return emails;
}

getMarketingEmails();
```

---

## 📧 STEP 7: Integra con Servizio Email Marketing

### Opzione A: Mailchimp

```dart
Future<void> syncToMailchimp() async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('exportMarketingEmails')
      .call();
  
  final emails = result.data['emails'] as List;
  
  // Invia a Mailchimp API
  for (var user in emails) {
    await mailchimpClient.addSubscriber(
      email: user['email'],
      firstName: user['name'].split(' ')[0],
      lastName: user['name'].split(' ').last,
    );
  }
}
```

### Opzione B: SendGrid

```dart
Future<void> sendNewsletterViaSendGrid() async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('exportMarketingEmails')
      .call();
  
  final users = result.data['emails'] as List;
  
  for (var user in users) {
    await sendGridClient.send(
      to: user['email'],
      subject: 'Newsletter SaveIt',
      html: getNewsletterTemplate(user['name']),
    );
  }
}
```

### Opzione C: Custom Email Service

```dart
Future<void> sendCustomMarketing() async {
  final users = await getMarketingUsersList();
  
  for (var user in users) {
    await sendEmail(
      to: user['email'],
      subject: 'Novità SaveIt!',
      body: '''
        Ciao ${user['name']},
        
        Abbiamo novità fantastiche per te...
        
        [CONTENUTO MARKETING]
        
        Per disattivare queste email: [LINK UNSUBSCRIBE]
      ''',
    );
  }
}
```

---

## 🔍 STEP 8: Monitoring e Analytics

### Dashboard Firestore

Crea query salvate in Firestore Console:

**Query 1**: Nuovi consensi ultimi 7 giorni
```
consents.marketing.consentDate >= [7_giorni_fa]
consents.marketing.accepted == true
```

**Query 2**: Utenti che hanno revocato consenso
```
consents.marketing.accepted == false
consents.marketing.lastModified >= [30_giorni_fa]
```

### Log Analytics

```dart
void trackMarketingConsentChange(bool newValue) {
  FirebaseAnalytics.instance.logEvent(
    name: 'marketing_consent_changed',
    parameters: {
      'consent_value': newValue,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );
}
```

---

## 📊 Struttura Dati Firestore Finale

```
users/{userId}
│
├─ userId: "firebase_uid_123"
├─ email: "user@example.com"
├─ name: "Mario Rossi"
├─ username: "@mario.rossi"
├─ createdAt: Timestamp
├─ lastLogin: Timestamp
│
└─ consents/
   ├─ marketing/
   │  ├─ accepted: true
   │  ├─ consentDate: Timestamp
   │  ├─ lastModified: Timestamp
   │  ├─ modifiedBy: "user"
   │  └─ version: "1.0"
   │
   ├─ privacy/
   │  ├─ accepted: true
   │  ├─ consentDate: Timestamp
   │  └─ version: "1.0"
   │
   └─ terms/
      ├─ accepted: true
      ├─ consentDate: Timestamp
      └─ version: "1.0"
```

---

## ✅ Checklist Finale

- [ ] `auth_service.dart` sostituito con versione Firestore
- [ ] Firestore Rules pubblicato
- [ ] Cloud Functions deployate (opzionale)
- [ ] Admin claim impostato
- [ ] Test modifica consenso → Salvato su Firestore ✅
- [ ] Test cross-device sync ✅
- [ ] Query marketing users funzionante ✅

---

## 🎯 Risultati Ottenuti

### ✅ FASE 1 COMPLETATA
- Persistenza locale (SharedPreferences)
- Consenso non si perde al riavvio

### ✅ FASE 2 COMPLETATA  
- Sync cloud (Firestore)
- Cross-device sync
- Query utenti per marketing
- GDPR compliant

### 🚀 Funzionalità Disponibili

1. **Salvataggio automatico** consenso su cloud
2. **Sincronizzazione cross-device** (login su più device)
3. **Query marketing users** per campagne email
4. **Export email** in formato CSV
5. **Statistiche** utenti con consenso attivo
6. **Filtri avanzati** per data consenso
7. **Offline-first** (funziona anche senza internet)

---

## 🆘 Troubleshooting

### Problema: Consenso non si salva su Firestore

**Log**:
```
ERRORE: Sincronizzazione Firestore fallita: [permission-denied]
```

**Soluzione**: Verifica Firestore Rules pubblicate

### Problema: Cloud Functions non funzionano

**Errore**: `permission-denied`

**Soluzione**: Verifica admin claim impostato correttamente

### Problema: Query lenta

**Soluzione**: Crea indice composito in Firestore:
- Firebase Console → Firestore → Indexes
- Crea indice su: `consents.marketing.accepted` + `lastLogin`

---

## 📞 Supporto

**Documentazione**:
- Firebase Firestore: https://firebase.google.com/docs/firestore
- Cloud Functions: https://firebase.google.com/docs/functions

**Domande?** Sono qui per aiutarti! 😊
