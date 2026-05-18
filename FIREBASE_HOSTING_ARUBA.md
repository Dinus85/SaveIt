# SaveIn su Firebase Hosting con dominio Aruba

## 1. Abilita Hosting nel progetto Firebase
Da terminale, nella root del progetto:

```bash
firebase login
firebase use saveit-app-1784d
flutter build web --release --base-href /
firebase deploy --only hosting
```

La configurazione Hosting e' gia' pronta in `firebase.json` e pubblica `build/web`.

## 2. Collega il dominio `savein.eu`
Apri la Firebase Console:

1. `Hosting`
2. `Add custom domain`
3. inserisci `savein.eu`
4. aggiungi anche `www.savein.eu`

Firebase ti mostrera' i record DNS da creare. I valori esatti li genera Firebase, quindi copia **quelli mostrati nel tuo pannello Firebase**.

## 3. Configura DNS su Aruba
Nel pannello Aruba vai nella gestione DNS del dominio e crea i record richiesti da Firebase.

In genere Firebase richiede una combinazione di questi record:
- `TXT` per verifica dominio
- `A` record per dominio root `@`
- eventualmente `AAAA`
- `CNAME` per `www`

Importante:
- se Aruba ha record `A`, `AAAA`, `CNAME` o redirect gia' presenti su `savein.eu` / `www`, rimuovi quelli in conflitto
- lascia attivi solo quelli richiesti da Firebase per il sito

## 4. Attendi verifica SSL
Dopo aver salvato i DNS su Aruba, torna in Firebase Hosting e attendi:
- verifica dominio
- provisioning certificato SSL

Questo step puo' richiedere da pochi minuti fino a qualche ora.

## 5. Abilita il dominio in Firebase Auth
Per poter fare login dal dominio personalizzato:

1. apri `Firebase Console -> Authentication`
2. vai in `Settings`
3. aggiungi tra gli `Authorized domains`:
   - `savein.eu`
   - `www.savein.eu`

## 6. URL da usare
Una volta propagato tutto:
- sito principale: `https://savein.eu`
- admin panel: `https://savein.eu/admin`
- fallback admin: `https://savein.eu/?admin=1`

## 7. Redeploy quando fai modifiche
Ogni volta che aggiorni il frontend web:

```bash
flutter build web --release --base-href /
firebase deploy --only hosting
```

## 8. Verifica finale
Controlla questi punti:

1. `https://savein.eu` si apre
2. refresh manuale su `https://savein.eu/admin` funziona
3. login Firebase funziona dal dominio personalizzato
4. un utente admin vede la dashboard admin
5. un utente non admin vede schermata non autorizzata

## 9. Nota importante
Il dominio personalizzato non richiede di cambiare subito:
- `projectId`
- `applicationId` Android
- `bundleId` iOS

Quindi puoi pubblicare il backend web anche mantenendo l'attuale progetto Firebase `saveit-app-1784d`.
