# SaveIn: checklist deploy Aruba

## Rebrand tecnico applicato nel progetto
- Nome package Dart aggiornato a `savein`
- Root widget rinominato in `SaveInApp`
- Meta description web aggiornata
- Placeholder email contenuti legali aggiornati a `@savein.app`
- File `.htaccess` pronto per SPA Flutter su hosting Apache/Aruba

## Build web pronta per Aruba
Esegui dalla root del progetto:

```bash
flutter build web --release --base-href /
```

Poi copia il file `.htaccess` della root dentro `build/web/` prima dell'upload, se il processo di pubblicazione non lo include automaticamente.

## Cosa caricare su Aruba
Carica tutto il contenuto della cartella `build/web/` nella root del dominio o sottodominio Aruba.

## Firebase: cosa NON ho rinominato apposta
Per non rompere login, Firestore e storage, ho lasciato invariati questi identificatori:
- Firebase project id: `saveit-app-1784d`
- Android application id: `com.example.saveit`
- iOS bundle id: `com.example.saveit`

Questi valori compaiono ancora in:
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `android/app/build.gradle`
- `ios/Runner.xcodeproj/project.pbxproj`
- `.firebaserc`
- `firebase.json`

## Quando vuoi completare anche gli identificatori Firebase/mobile
Serve questo passaggio esterno, non solo codice:

1. Decidere i nuovi id finali, ad esempio `com.example.savein` o il tuo namespace definitivo.
2. Registrare in Firebase le nuove app Android/iOS/Web.
3. Scaricare i nuovi file di configurazione Firebase.
4. Rigenerare `lib/firebase_options.dart` con FlutterFire.
5. Aggiornare eventuali SHA, URL autorizzate Google Sign-In e configurazioni Apple/Android.

Comando tipico dopo aver creato le nuove app su Firebase:

```bash
flutterfire configure --project=<nuovo-project-id> --platforms=android,ios,web,macos
```

## Verifica rapida post-deploy
1. Apri il dominio Aruba.
2. Ricarica una route interna direttamente dal browser per verificare il rewrite SPA.
3. Prova login, import post, immagini preview e pagina admin.
4. Se usi un sottopercorso invece della root, ricostruisci con `--base-href /nomecartella/`.
