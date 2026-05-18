# Analisi Problema Consenso Marketing - SaveIt App

## 📋 Executive Summary

**Problema**: Il consenso marketing non viene persistito. Quando l'utente attiva/disattiva il consenso in Account Page e riavvia l'app, la preferenza viene persa.

**Causa Root**: Mancanza di persistenza dei dati. Il valore viene salvato solo nello stato locale di `main.dart` e non viene mai scritto su storage permanente.

**Soluzione Proposta**: Implementare un sistema ibrido (Locale + Firebase) per garantire persistenza, sincronizzazione cross-device e possibilità di query per campagne marketing.

**Priorità**: 🔴 ALTA - Necessario per GDPR compliance e funzionalità marketing

---

## 🔍 Analisi Dettagliata del Problema

### 1. Flusso Attuale (DIFETTOSO)

```
REGISTRAZIONE
├─ User crea account con acceptedMarketing = true/false
├─ Salvato in AuthService.currentUser 
└─ Salvato in SharedPreferences come parte dell'oggetto User

MODIFICA IN ACCOUNT PAGE  
├─ onMarketingCommsChanged() viene chiamato
├─ Aggiorna solo lo stato locale di main.dart (_marketingCommsEnabled)
└─ ❌ NON salva da nessuna parte!

RIAVVIO APP
├─ main.dart inizializza _marketingCommsEnabled = false (default)
└─ ❌ Perde completamente la preferenza dell'utente
```

### 2. Cause Root Identificate

#### A. **Gestione dello Stato Frammentata**
- `main.dart` mantiene `_marketingCommsEnabled` solo in memoria
- `AuthService.currentUser.acceptedMarketing` non viene mai aggiornato dopo la registrazione
- Nessuna sincronizzazione tra i due stati

**Codice Problematico** (`main.dart`):
```dart
bool _marketingProfileEnabled = false;  // Hardcoded default
bool _marketingCommsEnabled = false;    // Hardcoded default
// ❌ Mai sincronizzato con AuthService.currentUser.acceptedMarketing
```

#### B. **Mancanza di Persistenza**
- `account_page.dart` ha solo un callback che aggiorna lo stato UI
- Non c'è nessun salvataggio in SharedPreferences quando cambia
- Non c'è nessun salvataggio su Firestore/Firebase

**Codice Problematico** (`account_page.dart`):
```dart
void _handleMarketingCommsChange(BuildContext context, bool newValue) {
  onMarketingCommsChanged(newValue);  // Solo callback al parent!
  Navigator.pushReplacement(...);     // ❌ Nessun salvataggio persistente
}
```

#### C. **Inizializzazione Errata**
Il valore iniziale è hardcoded invece di essere letto dal profilo utente esistente.

### 3. Punti di Fallimento

1. **Registrazione → Primo Login**: ✅ Funziona (salvato nel User model)
2. **Modifica in Account Page**: ❌ Non salvato permanentemente
3. **Riavvio App**: ❌ Valore perso, torna al default false
4. **Cambio Dispositivo**: ❌ Nessuna sincronizzazione cloud

---

## 💡 Soluzione Proposta: Sistema Ibrido

### Architettura Completa

```
┌─────────────────────────────────────────────────────────┐
│                    USER INTERFACE                        │
│  (account_page.dart - Marketing Switch)                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│                   AUTH SERVICE                           │
│  • updateMarketingConsent(bool consent)                 │
│  • getMarketingConsent() → bool                         │
│  • currentUser.acceptedMarketing                        │
│  • notifyListeners()                                    │
└──────────┬─────────────────────────────┬────────────────┘
           │                             │
           ↓                             ↓
┌──────────────────────┐    ┌──────────────────────────┐
│  SHARED PREFERENCES  │    │    FIRESTORE             │
│  (Cache Locale)      │    │  users/{uid}/            │
│  • Lettura veloce    │    │    ├─ acceptedMarketing  │
│  • Offline-first     │    │    ├─ marketingDate      │
│  • Backup locale     │    │    └─ lastUpdated        │
└──────────────────────┘    └──────────────────────────┘
```

### Vantaggi della Soluzione Ibrida

| Feature | SharedPreferences | Firestore | Ibrido |
|---------|------------------|-----------|---------|
| Velocità lettura | ✅ Istantanea | ⚠️ Lenta | ✅ Istantanea |
| Cross-device sync | ❌ No | ✅ Si | ✅ Si |
| Funziona offline | ✅ Si | ❌ No | ✅ Si |
| Query marketing | ❌ No | ✅ Si | ✅ Si |
| Backup cloud | ❌ No | ✅ Si | ✅ Si |
| GDPR audit trail | ❌ Difficile | ✅ Si | ✅ Si |

---

## 🗺️ Roadmap Implementazione

### FASE 1: Persistenza Locale (CRITICO) 🔴
**Tempo stimato**: 2-4 ore  
**Priorità**: Massima

#### Modifiche a `auth_service.dart`

**1. Aggiungere metodo di aggiornamento consenso**
```dart
/// Aggiorna il consenso marketing dell'utente
Future<bool> updateMarketingConsent(bool consent) async {
  if (_currentUser == null) return false;

  try {
    print('DEBUG: Aggiornando consenso marketing: $consent');
    
    // STEP 1: Aggiorna User model
    _currentUser = _currentUser!.copyWith(
      acceptedMarketing: consent,
    );
    
    // STEP 2: Salva in SharedPreferences
    await _saveUserLocally(_currentUser!);
    
    // STEP 3: Notifica listeners (aggiorna UI)
    notifyListeners();
    
    print('DEBUG: ✅ Consenso marketing salvato localmente');
    return true;
    
  } catch (e) {
    print('ERRORE: Salvataggio consenso marketing: $e');
    return false;
  }
}

/// Legge il consenso marketing corrente
bool getMarketingConsent() {
  return _currentUser?.acceptedMarketing ?? false;
}
```

**2. Aggiornare User model con copyWith per marketing**
```dart
User copyWith({
  String? name,
  String? email,
  String? username,
  bool? acceptedTerms,
  bool? acceptedPrivacy,
  bool? acceptedMarketing,  // ✅ Già presente
}) {
  return User(
    id: this.id,
    name: name ?? this.name,
    email: email ?? this.email,
    username: username ?? this.username,
    acceptedTerms: acceptedTerms ?? this.acceptedTerms,
    acceptedPrivacy: acceptedPrivacy ?? this.acceptedPrivacy,
    acceptedMarketing: acceptedMarketing ?? this.acceptedMarketing,
    createdAt: this.createdAt,
  );
}
```

#### Modifiche a `account_page.dart`

**Sostituire `_handleMarketingCommsChange`**:
```dart
void _handleMarketingCommsChange(BuildContext context, bool newValue) async {
  print('DEBUG: Cambio consenso marketing a: $newValue');
  
  // Mostra loading
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Center(
      child: CircularProgressIndicator(),
    ),
  );
  
  try {
    // STEP 1: Salva tramite AuthService
    final success = await AuthService().updateMarketingConsent(newValue);
    
    if (success) {
      // STEP 2: Aggiorna parent callback
      onMarketingCommsChanged(newValue);
      
      // STEP 3: Chiudi loading e ricarica pagina
      if (context.mounted) {
        Navigator.pop(context); // Chiude loading dialog
        
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => AccountPage(
              isDarkTheme: isDarkTheme,
              marketingProfileEnabled: marketingProfileEnabled,
              marketingCommsEnabled: newValue,  // ✅ Valore aggiornato
              onThemeChanged: onThemeChanged,
              onMarketingProfileChanged: onMarketingProfileChanged,
              onMarketingCommsChanged: onMarketingCommsChanged,
              folders: folders,
            ),
            transitionDuration: Duration(milliseconds: 200),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
        
        // Mostra conferma
        Future.delayed(Duration(milliseconds: 300), () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Consenso marketing ${newValue ? 'attivato' : 'disattivato'}'),
                backgroundColor: newValue ? Colors.green : Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
        });
      }
      
      print('DEBUG: ✅ Consenso marketing aggiornato con successo');
      
    } else {
      throw Exception('Salvataggio fallito');
    }
    
  } catch (e) {
    print('ERRORE: Aggiornamento consenso marketing: $e');
    
    if (context.mounted) {
      Navigator.pop(context); // Chiude loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore durante il salvataggio. Riprova.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
```

#### Modifiche a `main.dart`

**Inizializzazione corretta**:
```dart
class _SaveItAppState extends State<SaveItApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _marketingProfileEnabled = false;
  bool _marketingCommsEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _loadUserPreferences();  // ✅ NUOVO: Carica preferenze
  }
  
  /// ✅ NUOVO: Carica preferenze utente all'avvio
  Future<void> _loadUserPreferences() async {
    try {
      // Attendi che AuthService sia inizializzato
      await Future.delayed(Duration(milliseconds: 100));
      
      final currentUser = AuthService().currentUser;
      if (currentUser != null) {
        setState(() {
          _marketingCommsEnabled = currentUser.acceptedMarketing;
          _marketingProfileEnabled = currentUser.acceptedMarketing;
        });
        
        print('DEBUG: ✅ Preferenze marketing caricate: $_marketingCommsEnabled');
      }
    } catch (e) {
      print('DEBUG: Errore caricamento preferenze: $e');
    }
  }
  
  void _toggleMarketingComms(bool enabled) {
    setState(() {
      _marketingCommsEnabled = enabled;
    });
    // Il salvataggio effettivo è gestito da account_page.dart
  }
}
```

### FASE 2: Sincronizzazione Firestore (IMPORTANTE) 🟡
**Tempo stimato**: 4-6 ore  
**Priorità**: Alta

#### Struttura Dati Firestore

```javascript
// Collezione: users
{
  "userId": "firebase_uid_12345",
  
  // Dati profilo base
  "email": "user@example.com",
  "name": "Mario Rossi",
  "username": "@mario.rossi",
  "createdAt": Timestamp,
  
  // Consensi GDPR
  "consents": {
    "marketing": {
      "accepted": true,
      "consentDate": Timestamp,      // Quando ha dato il consenso
      "lastModified": Timestamp,     // Ultima modifica
      "modifiedBy": "user",          // chi ha modificato (user/admin/system)
      "ipAddress": "192.168.1.1",    // IP al momento del consenso (opzionale)
      "userAgent": "Mozilla/5.0...", // Browser/device (opzionale)
    },
    "terms": {
      "accepted": true,
      "consentDate": Timestamp,
      "version": "1.0"                // Versione dei termini accettati
    },
    "privacy": {
      "accepted": true,
      "consentDate": Timestamp,
      "version": "1.0"
    }
  },
  
  // Metadati
  "lastLogin": Timestamp,
  "deviceTokens": ["fcm_token_1", "fcm_token_2"],  // Per notifiche push
}
```

#### Regole Firestore Security

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Regole per collezione users
    match /users/{userId} {
      // Lettura: solo il proprio profilo
      allow read: if request.auth != null && request.auth.uid == userId;
      
      // Scrittura: solo il proprio profilo
      allow write: if request.auth != null && request.auth.uid == userId;
      
      // Validazione dati per update consenso marketing
      allow update: if request.auth != null 
                    && request.auth.uid == userId
                    && request.resource.data.consents.marketing.accepted is bool
                    && request.resource.data.consents.marketing.lastModified is timestamp;
    }
    
    // Query per marketing (solo admin/server)
    match /users/{userId} {
      allow list: if false; // Blocca query da client
      // Le query devono essere fatte via Cloud Functions con privilegi admin
    }
  }
}
```

#### Modifiche a `auth_service.dart` per Firestore

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService extends ChangeNotifier {
  // ... codice esistente ...
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Aggiorna il consenso marketing (con sincronizzazione Firestore)
  Future<bool> updateMarketingConsent(bool consent) async {
    if (_currentUser == null) return false;

    try {
      print('DEBUG: Aggiornando consenso marketing: $consent');
      
      // STEP 1: Aggiorna User model
      _currentUser = _currentUser!.copyWith(
        acceptedMarketing: consent,
      );
      
      // STEP 2: Salva in SharedPreferences (cache locale)
      await _saveUserLocally(_currentUser!);
      
      // STEP 3: Salva su Firestore (cloud sync)
      await _updateMarketingConsentFirestore(consent);
      
      // STEP 4: Notifica listeners (aggiorna UI)
      notifyListeners();
      
      print('DEBUG: ✅ Consenso marketing salvato localmente e su cloud');
      return true;
      
    } catch (e) {
      print('ERRORE: Salvataggio consenso marketing: $e');
      return false;
    }
  }
  
  /// Salva il consenso marketing su Firestore
  Future<void> _updateMarketingConsentFirestore(bool consent) async {
    if (_firebaseAuth.currentUser == null) {
      throw Exception('Utente non autenticato');
    }
    
    final userId = _firebaseAuth.currentUser!.uid;
    final now = FieldValue.serverTimestamp();
    
    try {
      await _firestore.collection('users').doc(userId).set({
        'consents': {
          'marketing': {
            'accepted': consent,
            'lastModified': now,
            'modifiedBy': 'user',
          }
        }
      }, SetOptions(merge: true));
      
      print('DEBUG: ✅ Consenso marketing sincronizzato su Firestore');
      
    } catch (e) {
      print('ERRORE: Sincronizzazione Firestore: $e');
      // Non rilanciare l'errore - il salvataggio locale è già avvenuto
      // L'app continua a funzionare anche senza sync cloud
    }
  }
  
  /// Carica i consensi da Firestore (all'avvio o dopo login)
  Future<void> _loadMarketingConsentFromFirestore() async {
    if (_firebaseAuth.currentUser == null) return;
    
    final userId = _firebaseAuth.currentUser!.uid;
    
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        
        // Leggi il consenso marketing da Firestore
        final marketingConsent = data['consents']?['marketing']?['accepted'] ?? false;
        
        // Se diverso dal valore locale, aggiorna
        if (_currentUser != null && _currentUser!.acceptedMarketing != marketingConsent) {
          print('DEBUG: Consenso marketing da Firestore diverso, sincronizzando...');
          
          _currentUser = _currentUser!.copyWith(
            acceptedMarketing: marketingConsent,
          );
          
          await _saveUserLocally(_currentUser!);
          notifyListeners();
          
          print('DEBUG: ✅ Consenso marketing sincronizzato da cloud');
        }
      }
      
    } catch (e) {
      print('DEBUG: Errore caricamento consenso da Firestore: $e');
      // Continua con il valore locale in caso di errore
    }
  }
  
  /// Modifica _loadUserData per includere sync Firestore
  Future<void> _loadUserData(firebase_auth.User firebaseUser) async {
    try {
      print('DEBUG: 🔧 Caricamento dati utente: ${firebaseUser.email}');
      
      // Carica da SharedPreferences (esistente)
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_${firebaseUser.uid}');
      
      if (userData != null) {
        _currentUser = User.fromJson(jsonDecode(userData));
        print('DEBUG: ✅ Dati utente caricati da storage locale');
      } else {
        // Crea nuovo profilo locale
        _currentUser = User(
          id: firebaseUser.uid,
          name: firebaseUser.displayName ?? 'Utente',
          email: firebaseUser.email ?? '',
          username: '@${(firebaseUser.displayName ?? 'utente').toLowerCase().replaceAll(' ', '.')}',
          acceptedTerms: true,
          acceptedPrivacy: true,
          acceptedMarketing: false,
          createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
        );
        
        await _saveUserLocally(_currentUser!);
        print('DEBUG: ✅ Nuovo profilo locale creato');
      }
      
      // ✅ NUOVO: Sincronizza con Firestore in background
      _loadMarketingConsentFromFirestore();
      
    } catch (e) {
      print('ERRORE caricamento dati utente: $e');
      // Fallback esistente...
    }
  }
}
```

#### Cloud Function per Query Marketing (Opzionale)

```javascript
// Firebase Cloud Function
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.getMarketingUsers = functions.https.onCall(async (data, context) => {
  // Verifica che sia chiamata da un admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Solo gli admin possono accedere a questa funzione'
    );
  }
  
  try {
    const snapshot = await admin.firestore()
      .collection('users')
      .where('consents.marketing.accepted', '==', true)
      .get();
    
    const users = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      users.push({
        userId: doc.id,
        email: data.email,
        name: data.name,
        consentDate: data.consents.marketing.consentDate,
      });
    });
    
    return { users, count: users.length };
    
  } catch (error) {
    throw new functions.https.HttpsError('internal', error.message);
  }
});
```

### FASE 3: GDPR Compliance (CONSIGLIATO) 🟢
**Tempo stimato**: 3-5 ore  
**Priorità**: Media-Alta

#### Audit Log per Consensi

```dart
// Nuovo model: ConsentAuditLog
class ConsentAuditLog {
  final String userId;
  final String consentType; // 'marketing', 'terms', 'privacy'
  final bool value;
  final DateTime timestamp;
  final String action; // 'granted', 'revoked', 'modified'
  final String source; // 'registration', 'settings', 'admin'
  final String? ipAddress;
  final String? userAgent;
  
  ConsentAuditLog({
    required this.userId,
    required this.consentType,
    required this.value,
    required this.timestamp,
    required this.action,
    required this.source,
    this.ipAddress,
    this.userAgent,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'consentType': consentType,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'action': action,
      'source': source,
      'ipAddress': ipAddress,
      'userAgent': userAgent,
    };
  }
}
```

#### Firestore Structure per Audit Log

```javascript
// Collezione: consent_audit_log
{
  "logId": "auto_generated_id",
  "userId": "firebase_uid_12345",
  "consentType": "marketing",
  "value": true,
  "timestamp": Timestamp,
  "action": "granted",
  "source": "settings",
  "ipAddress": "192.168.1.1",
  "userAgent": "Mozilla/5.0...",
  "metadata": {
    "appVersion": "1.0.0",
    "platform": "android",
    "deviceId": "device_xyz"
  }
}
```

#### Metodo per Salvare Audit Log

```dart
/// Salva log audit per consensi GDPR
Future<void> _saveConsentAuditLog({
  required String consentType,
  required bool value,
  required String action,
}) async {
  if (_firebaseAuth.currentUser == null) return;
  
  try {
    final log = {
      'userId': _firebaseAuth.currentUser!.uid,
      'consentType': consentType,
      'value': value,
      'timestamp': FieldValue.serverTimestamp(),
      'action': action,
      'source': 'user_settings',
      'metadata': {
        'appVersion': '1.0.0',
        'platform': defaultTargetPlatform.toString(),
      }
    };
    
    await _firestore.collection('consent_audit_log').add(log);
    
    print('DEBUG: ✅ Audit log salvato per $consentType');
    
  } catch (e) {
    print('ERRORE: Salvataggio audit log: $e');
    // Non bloccare l'operazione principale
  }
}

/// Aggiorna updateMarketingConsent per includere audit log
Future<bool> updateMarketingConsent(bool consent) async {
  if (_currentUser == null) return false;

  try {
    final previousValue = _currentUser!.acceptedMarketing;
    
    // Salva valore
    _currentUser = _currentUser!.copyWith(acceptedMarketing: consent);
    await _saveUserLocally(_currentUser!);
    await _updateMarketingConsentFirestore(consent);
    
    // ✅ NUOVO: Salva audit log
    await _saveConsentAuditLog(
      consentType: 'marketing',
      value: consent,
      action: consent ? 'granted' : 'revoked',
    );
    
    notifyListeners();
    return true;
    
  } catch (e) {
    print('ERRORE: Aggiornamento consenso marketing: $e');
    return false;
  }
}
```

---

## 📊 Testing Plan

### Test Case 1: Primo Login dopo Registrazione
```
DATO: Nuovo utente registrato con acceptedMarketing = true
QUANDO: Completa registrazione e accede all'app
ALLORA: 
  ✅ Account Page mostra switch Marketing attivo
  ✅ SharedPreferences contiene acceptedMarketing = true
  ✅ Firestore users/{uid}/consents/marketing/accepted = true
```

### Test Case 2: Modifica Consenso da Account Page
```
DATO: Utente loggato con acceptedMarketing = true
QUANDO: Va in Account Page e disattiva il consenso marketing
ALLORA:
  ✅ Switch si disattiva immediatamente
  ✅ Mostra SnackBar "Consenso marketing disattivato"
  ✅ SharedPreferences aggiornato con acceptedMarketing = false
  ✅ Firestore sincronizzato con accepted = false
  ✅ AuthService.currentUser.acceptedMarketing = false
  ✅ Audit log creato con action = 'revoked'
```

### Test Case 3: Riavvio App dopo Modifica
```
DATO: Utente ha disattivato marketing e chiuso l'app
QUANDO: Riapre l'app dopo qualche ora
ALLORA:
  ✅ Account Page mostra switch Marketing disattivo
  ✅ main.dart._marketingCommsEnabled = false
  ✅ AuthService.currentUser.acceptedMarketing = false
  ✅ Valore persistito correttamente
```

### Test Case 4: Cambio Dispositivo (Cross-Device Sync)
```
DATO: Utente con marketing attivo su Device A
QUANDO: Fa login su Device B
ALLORA:
  ✅ Device B carica acceptedMarketing = true da Firestore
  ✅ Account Page mostra switch attivo
  ✅ Sincronizzazione cloud funzionante
```

### Test Case 5: Funzionamento Offline
```
DATO: Utente offline (nessuna connessione)
QUANDO: Modifica il consenso marketing in Account Page
ALLORA:
  ✅ Modifica salvata in SharedPreferences
  ⚠️ Firestore sync fallisce silenziosamente
  ✅ App continua a funzionare
  ✅ Al ripristino connessione, sync automatico (opzionale)
```

### Test Case 6: Query Marketing per Campagne
```
DATO: 100 utenti, 60 con marketing attivo
QUANDO: Admin chiama Cloud Function getMarketingUsers()
ALLORA:
  ✅ Ritorna 60 utenti
  ✅ Ogni utente ha email, nome, data consenso
  ✅ Query non accessibile da client
```

### Test Case 7: Audit Log GDPR
```
DATO: Utente modifica consenso marketing 3 volte
QUANDO: Admin controlla audit log per questo utente
ALLORA:
  ✅ 3 record in consent_audit_log
  ✅ Ogni record ha timestamp, action, value
  ✅ History completa delle modifiche
```

---

## 📈 Metriche e Monitoring

### KPI da Tracciare

1. **Consenso Marketing Rate**
   - % utenti con marketing attivo
   - Trend nel tempo
   - Per segmento utente (Google vs Email)

2. **Revoke Rate**
   - % utenti che revocano il consenso
   - Tempo medio prima della revoca
   - Motivi di revoca (se disponibili)

3. **Sync Success Rate**
   - % sync Firestore riuscite
   - Latency media sync
   - Errori di sincronizzazione

4. **Audit Log Completeness**
   - % azioni loggata
   - Gap temporali nei log

### Dashboard Monitoring (Firestore Queries)

```javascript
// Query 1: Totale utenti con marketing attivo
db.collection('users')
  .where('consents.marketing.accepted', '==', true)
  .get()
  .then(snapshot => console.log('Marketing Active:', snapshot.size));

// Query 2: Consensi ultimi 7 giorni
const sevenDaysAgo = new Date();
sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

db.collection('consent_audit_log')
  .where('consentType', '==', 'marketing')
  .where('timestamp', '>=', sevenDaysAgo)
  .where('action', '==', 'granted')
  .get()
  .then(snapshot => console.log('New consents this week:', snapshot.size));

// Query 3: Revoke ultimi 30 giorni
const thirtyDaysAgo = new Date();
thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

db.collection('consent_audit_log')
  .where('consentType', '==', 'marketing')
  .where('timestamp', '>=', thirtyDaysAgo)
  .where('action', '==', 'revoked')
  .get()
  .then(snapshot => console.log('Revokes this month:', snapshot.size));
```

---

## 🚀 Rollout Strategy

### Piano di Rilascio Graduale

#### Week 1: Alpha Testing (5% utenti)
- Deploy FASE 1 (Solo SharedPreferences)
- Test con 5% utenti beta
- Monitor errori e crash
- Verifica persistenza funzionante

#### Week 2: Beta Testing (25% utenti)
- Deploy FASE 2 (+ Firestore sync)
- Rollout a 25% utenti
- Monitor performance Firestore
- Test cross-device sync
- Verifica regole security

#### Week 3: Gradual Rollout (50% → 100%)
- Rollout progressivo 50% → 75% → 100%
- Monitor KPI marketing consent
- Deploy FASE 3 (Audit log) se tutto ok
- Training team marketing su query

#### Week 4: Monitoring e Ottimizzazione
- Analisi metriche complete
- Fix bug eventuali
- Ottimizzazione performance
- Documentazione finale

### Rollback Plan

**Se si verificano problemi critici**:
1. Disabilita sync Firestore (mantieni solo SharedPreferences)
2. Rollback versione precedente per utenti impattati
3. Analisi root cause
4. Fix e re-deploy graduale

---

## 📝 Checklist Implementazione

### FASE 1: SharedPreferences (CRITICO)
- [ ] Aggiungere `updateMarketingConsent()` in `auth_service.dart`
- [ ] Aggiungere `getMarketingConsent()` in `auth_service.dart`
- [ ] Modificare `_handleMarketingCommsChange()` in `account_page.dart`
- [ ] Aggiungere `_loadUserPreferences()` in `main.dart`
- [ ] Test manuale: modifica e riavvio app
- [ ] Test manuale: funzionamento offline
- [ ] Code review
- [ ] Deploy alpha (5% utenti)

### FASE 2: Firestore Sync (IMPORTANTE)
- [ ] Definire struttura dati Firestore `users/{uid}/consents`
- [ ] Configurare regole Firestore security
- [ ] Aggiungere `_updateMarketingConsentFirestore()` in `auth_service.dart`
- [ ] Aggiungere `_loadMarketingConsentFromFirestore()` in `auth_service.dart`
- [ ] Modificare `_loadUserData()` per includere sync
- [ ] Test manuale: sync cross-device
- [ ] Test manuale: gestione errori rete
- [ ] Load testing Firestore
- [ ] Code review
- [ ] Deploy beta (25% utenti)

### FASE 3: Audit Log GDPR (CONSIGLIATO)
- [ ] Creare model `ConsentAuditLog`
- [ ] Definire struttura Firestore `consent_audit_log`
- [ ] Aggiungere `_saveConsentAuditLog()` in `auth_service.dart`
- [ ] Integrare audit log in `updateMarketingConsent()`
- [ ] Creare Cloud Function `getMarketingUsers()` (opzionale)
- [ ] Dashboard monitoring Firebase Console
- [ ] Test query audit log
- [ ] Documentazione GDPR compliance
- [ ] Code review
- [ ] Deploy production (100% utenti)

### POST-DEPLOYMENT
- [ ] Monitoring attivo per 1 settimana
- [ ] Analisi metriche KPI
- [ ] Training team marketing
- [ ] Documentazione utente
- [ ] Post-mortem e lessons learned

---

## ⚖️ GDPR Compliance Checklist

### Requisiti Legali Soddisfatti

- [x] **Consenso Esplicito**: L'utente deve attivare manualmente lo switch
- [x] **Facile Revoca**: Switch in Account Page accessibile sempre
- [x] **Timestamp Consenso**: Salvato in Firestore `consentDate`
- [x] **Audit Trail**: Log di tutte le modifiche
- [x] **Granularità**: Consenso marketing separato da altri consensi
- [x] **Portabilità**: Dati esportabili (via Firestore export)
- [ ] **Right to Be Forgotten**: Implementare delete completo account
- [ ] **Data Retention**: Policy di cancellazione dati dopo X anni
- [ ] **Privacy Policy Aggiornata**: Includere uso dati marketing
- [ ] **Email Unsubscribe**: Link di disiscrizione in ogni email marketing

### Documenti da Aggiornare

1. **Privacy Policy**: Aggiungere sezione marketing consent
2. **Terms & Conditions**: Specificare uso email marketing
3. **Cookie Policy**: Se si traccia via cookies
4. **Data Processing Agreement**: Per team marketing

---

## 🔧 Troubleshooting

### Problema: Consenso non si salva
**Sintomi**: Modifica lo switch ma al riavvio torna al valore precedente  
**Causa**: Fallimento salvataggio SharedPreferences o Firestore  
**Fix**: Controllare log `ERRORE: Salvataggio consenso marketing`

### Problema: Sync Firestore lento
**Sintomi**: Delay di diversi secondi dopo modifica switch  
**Causa**: Latency rete o regole Firestore complesse  
**Fix**: Implementare loading indicator, ottimizzare regole security

### Problema: Dati non sincronizzati tra dispositivi
**Sintomi**: Device A ha marketing attivo, Device B no  
**Causa**: `_loadMarketingConsentFromFirestore()` non chiamato  
**Fix**: Verificare che sia chiamato in `_loadUserData()`

### Problema: Query marketing lenta
**Sintomi**: Cloud Function timeout  
**Causa**: Troppi documenti, indice Firestore mancante  
**Fix**: Creare indice composito su `consents.marketing.accepted`

---

## 📚 Risorse Aggiuntive

### Documentazione Ufficiale
- [Firebase Auth - Manage Users](https://firebase.google.com/docs/auth/flutter/manage-users)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [SharedPreferences Flutter](https://pub.dev/packages/shared_preferences)
- [GDPR Compliance Guide](https://gdpr.eu/checklist/)

### Best Practices
- [Flutter State Management](https://docs.flutter.dev/development/data-and-backend/state-mgmt/intro)
- [Firebase Performance](https://firebase.google.com/docs/perf-mon)
- [Offline-First Architecture](https://developer.android.com/topic/architecture/data-layer/offline-first)

---

## 👥 Team e Responsabilità

| Ruolo | Responsabilità | Owner |
|-------|---------------|-------|
| **Flutter Developer** | Implementazione FASE 1-2 | TBD |
| **Backend Developer** | Cloud Functions, Firestore rules | TBD |
| **QA Engineer** | Testing plan, automation | TBD |
| **Product Manager** | Priorità features, rollout strategy | TBD |
| **Legal/Compliance** | GDPR review, privacy policy | TBD |
| **Marketing** | Query utenti, campagne | TBD |

---

## 📞 Contatti e Supporto

Per domande o supporto sull'implementazione:
- **Tech Lead**: [email]
- **Firebase Console**: [link]
- **Documentazione Interna**: [wiki link]
- **Slack Channel**: #saveit-marketing-consent

---

**Documento creato**: 2025-01-14  
**Versione**: 1.0  
**Ultima modifica**: 2025-01-14  
**Autore**: AI Technical Analysis  
**Status**: ✅ Ready for Implementation