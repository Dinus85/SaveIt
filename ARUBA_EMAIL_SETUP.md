# Setup Email Aruba per SaveIn

Guida completa per creare le caselle email su Aruba e collegarle alle Cloud Functions di SaveIn.

---

## 1. Crea le caselle email su Aruba

Accedi al tuo pannello Aruba: https://admin.aruba.it

Vai in: **Email** → **Crea email**

Crea queste due caselle:

| Indirizzo | Scopo |
|---|---|
| `noreply@savein.eu` | Tutte le email automatiche inviate agli utenti (benvenuto, conferma, notifiche) |
| `support@savein.eu` | Riceve i messaggi di contatto degli utenti, ti risponde come mittente |

Per ognuna, scegli una password robusta. Annotale perché le userai nei passi successivi.

---

## 2. Parametri SMTP Aruba

Una volta create le caselle, i parametri SMTP da usare sono:

```
Host SMTP:     smtps.aruba.it
Porta SSL:     465  (raccomandato, connessione cifrata)
Porta STARTTLS: 587  (alternativa)
Autenticazione: richiesta
Username:      noreply@savein.eu  (la tua email completa)
Password:      la password che hai impostato su Aruba
```

---

## 3. Aggiorna il file .env delle Cloud Functions

Apri il file `functions/.env` e sostituisci il contenuto con:

```env
# Configurazione SMTP Aruba per SaveIn
EMAIL_HOST=smtps.aruba.it
EMAIL_PORT=465
EMAIL_SECURE=true

# Account mittente automatico
EMAIL_USER=noreply@savein.eu
EMAIL_PASSWORD=la_tua_password_noreply

# Nome visualizzato dagli utenti come mittente
EMAIL_FROM=SaveIn <noreply@savein.eu>

# Casella che riceve i messaggi di supporto dagli utenti
SUPPORT_EMAIL=support@savein.eu
```

**IMPORTANTE**: Il file `.env` non deve essere committato su Git. Controlla che sia nel `.gitignore`.

---

## 4. Deploy variabili ambiente su Firebase

Dopo aver aggiornato `.env`, esegui in terminale dalla cartella root del progetto:

```powershell
cd functions
firebase functions:secrets:set EMAIL_PASSWORD
# Inserisci la password quando richiesto
```

In alternativa, per tutte le variabili:

```powershell
firebase functions:config:set email.host="smtps.aruba.it" email.port="465" email.user="noreply@savein.eu" email.password="LA_TUA_PASSWORD" email.from="SaveIn <noreply@savein.eu>" support.email="support@savein.eu"
```

Poi fai il deploy delle functions:

```powershell
firebase deploy --only functions
```

---

## 5. Personalizza le email Firebase Auth (reset password)

Firebase Auth gestisce autonomamente il reset password, la verifica email e la revoca accesso.  
Puoi personalizzare i template dalla Firebase Console:

1. Vai su https://console.firebase.google.com/project/saveit-app-1784d/authentication/emails
2. Clicca su **Password reset**
3. Modifica:
   - **Da**: imposta `noreply@savein.eu`
   - **Oggetto**: `Reimposta la tua password SaveIn`
   - **Corpo**: vedi template suggerito sotto

**Per usare il dominio personalizzato** nelle email Firebase Auth:
1. In Firebase Console → Authentication → Settings
2. Scorri fino a **Email domain**
3. Aggiungi `savein.eu` come dominio verificato
4. Firebase ti mostrerà dei record DNS da aggiungere su Aruba (solitamente un record TXT o CNAME)

---

## 6. Template email suggeriti

### Reset password

```
Oggetto: Reimposta la tua password SaveIn

Ciao,

hai richiesto di reimpostare la password del tuo account SaveIn.

Clicca sul link qui sotto per scegliere una nuova password:
[LINK]

Il link è valido per 1 ora.

Se non hai richiesto tu il reset, ignora questa email. Il tuo account è al sicuro.

Il team SaveIn
support@savein.eu
```

### Benvenuto nuovo utente (gestito dalla Cloud Function)

```
Oggetto: Benvenuto in SaveIn!

Ciao [NOME],

grazie per esserti registrato su SaveIn.

Con SaveIn puoi salvare qualsiasi link da social e web, organizzarlo in cartelle e ritrovarlo facilmente.

Come iniziare:
1. Condividi un link da qualsiasi app direttamente su SaveIn
2. Organizza i tuoi salvataggi in cartelle
3. Cerca e filtra per ritrovare tutto subito

Per assistenza o domande: support@savein.eu

A presto,
Il team SaveIn
```

---

## 7. Test invio email

Dopo il deploy, testa le funzioni dalla Firebase Console:

1. Vai su https://console.firebase.google.com/project/saveit-app-1784d/functions
2. Clicca sui tre puntini della funzione `sendContactEmail`
3. Seleziona **Test function**
4. Inserisci un payload di test

Oppure dall'app in modalità debug, usa la sezione Contattaci nell'account.

---

## 8. Auto-risposta contatto

La Cloud Function `sendContactEmail` è stata aggiornata per inviare:
1. Email di notifica a `support@savein.eu` con il messaggio dell'utente
2. Email di auto-risposta all'utente che conferma la ricezione

---

## Note importanti

- Non usare la casella `noreply@savein.eu` per ricevere risposte: configurala come "nessuna risposta" su Aruba o ignora le risposte
- La casella `support@savein.eu` deve essere controllata regolarmente
- Firebase Auth invia le email dal suo sistema interno: per usare il tuo dominio Aruba serve la verifica DNS aggiuntiva descritta al punto 5
- Le password delle caselle email vanno ruotate periodicamente e aggiornate su Firebase
