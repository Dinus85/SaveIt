# Setup Email di Contatto - SaveIt

Questa guida spiega come configurare l'invio automatico di email dalla pagina Contatti.

## 📋 Prerequisiti

- Account Gmail o Hotmail/Outlook
- Progetto Firebase configurato
- Firebase CLI installato

## 🔧 Configurazione

### 1. Installa le dipendenze


cd functions
npm install


### 2. Configura l'email mittente

> 🔄 Dal 2026 Firebase dismetterà `functions.config()`. Usa ora le variabili
> ambiente per evitare problemi di deploy.

1. **Crea** nella cartella `functions/` un file `.env` (non committarlo) e copia
   al suo interno questo modello:

   ```bash
   EMAIL_SERVICE=gmail
   EMAIL_USER=pasidino@hotmail.it
   EMAIL_PASSWORD=INSERISCI_PASSWORD_APP
   EMAIL_FROM=pasidino@hotmail.it
   SUPPORT_EMAIL=pasidino@hotmail.it
   ```

   - `EMAIL_SERVICE`: `gmail`, `hotmail`, `outlook`, ecc.
   - `EMAIL_USER`: account utilizzato da Nodemailer per autenticarsi.
   - `EMAIL_PASSWORD`: password per le app generata dal provider.
   - `EMAIL_FROM`: mittente visualizzato (default = `EMAIL_USER`).
   - `SUPPORT_EMAIL`: destinatario dei messaggi (default = `EMAIL_USER`).

2. **Proteggi il file**: `.env` è già ignorato da Git. Condividi solo un
   `.env.example` senza i secret reali.

Ora scegli il provider email:

#### **Opzione A: Gmail (Raccomandato)**

1. Vai su [Google Account Security](https://myaccount.google.com/security)
2. Abilita **2-Step Verification**
3. Apri **App passwords** (Password per le app)
4. Genera una nuova password per "Mail"
5. Copia la password generata (16 caratteri)
6. Inseriscila come `EMAIL_PASSWORD` nel file `.env`

#### **Opzione B: Hotmail/Outlook**

1. Vai su [Microsoft Account Security](https://account.microsoft.com/security)
2. Abilita **2-Step Verification**
3. Genera una **App Password** per Outlook
4. Nel file `.env` imposta `EMAIL_SERVICE=hotmail` (o `outlook`) e aggiorna
   `EMAIL_PASSWORD`

#### **(Opzionale) Usa i Firebase Secrets**

Per tenere la password solo lato server:

```bash
firebase functions:secrets:set EMAIL_PASSWORD
```

Nel codice `EMAIL_PASSWORD` viene letto automaticamente da `process.env`. Puoi
combinare secret Firebase + `.env` (per sviluppo locale) senza modifiche.

### 3. Deploy delle Cloud Functions

```bash
firebase deploy --only functions
```

### 4. Aggiungi la dipendenza Flutter

```bash
cd ..
flutter pub get
```

### 5. Testa l'app

```bash
flutter run
```

## 📧 Come Funziona

1. L'utente compila il form di contatto nell'app
2. L'app chiama la Cloud Function `sendContactEmail`
3. La Cloud Function invia l'email a `pasidino@hotmail.it`
4. L'email include:
   - **Da**: Email dell'utente (per reply)
   - **Oggetto**: `[SaveIt Support] {oggetto dell'utente}`
   - **Corpo**: Messaggio formattato HTML
5. Il messaggio viene salvato anche su Firestore (`support_messages`)

## 🎨 Esempio Email Ricevuta

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Nuovo messaggio di supporto
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Da: user@example.com
Oggetto: Problema con login
Data: 30/10/2025, 23:30

Messaggio:
Non riesco ad accedere con il mio account...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Nota: Per rispondere, clicca su "Rispondi" 
e l'email verrà inviata direttamente a 
user@example.com
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 📊 Storico Messaggi

Tutti i messaggi vengono salvati in Firestore:

**Collection**: `support_messages`

**Campi**:
- `userId`: ID utente
- `userEmail`: Email utente
- `subject`: Oggetto
- `message`: Messaggio
- `timestamp`: Data/ora
- `status`: "sent"

## 🔍 Test Locale (Opzionale)

Per testare in locale senza deploy:

```bash
cd functions
npm run serve
```

Poi nell'app, configura l'emulator (in `main.dart`):

```dart
FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
```

## ⚠️ Troubleshooting

### "Errore autenticazione email"

- Verifica che la password app sia corretta
- Controlla che 2FA sia abilitato
- Prova a rigenerare la password app

### "Cloud Function non trovata"

```bash
firebase deploy --only functions
```

### "Permission denied"

Verifica le regole Firestore per `support_messages`:

```javascript
match /support_messages/{messageId} {
  allow read: if request.auth != null && request.auth.uid == resource.data.userId;
  allow create: if request.auth != null;
}
```

## 🎯 Limiti e Costi

- **Gmail**: 500 email/giorno (account gratuito)
- **Outlook**: 300 email/giorno (account gratuito)
- **Firebase Functions**: Piano Blaze richiesto (gratuito fino a 2M invocazioni/mese)

## 📝 Note

- La password NON viene mai committata su Git
- Usa sempre App Passwords, mai la password principale
- I messaggi vengono salvati per storico/analytics
- Puoi rispondere direttamente all'email dell'utente

## 🚀 Produzione

Prima del deploy in produzione:

1. ✅ Testa con email di test
2. ✅ Verifica limiti giornalieri
3. ✅ Configura monitoring Firebase
4. ✅ Aggiungi regole Firestore per `support_messages`
5. ✅ Considera un servizio email dedicato (SendGrid, AWS SES) per volumi alti



