# Mediation AdMob (AppLovin + Meta) — da fare in console

**Dove sta questo file:** root del repo SaveIn, accanto a `pubspec.yaml`.
Percorso: `ADS_MEDIATION_SETUP.md` (stesso nome anche in SmartChef).

Il codice è pronto. Senza questi passaggi i pin nativi e AppLovin/Meta non riempiono (resta Google).

## AdMob
1. Crea ad unit **Native** Android + iOS per SaveIn e SmartChef.
2. Crea ad unit **Rewarded** Android + iOS per SaveIn (SmartChef le ha già).
3. Incolla gli ID in:
   - SaveIn: `lib/services/ads_ids.dart`
   - SmartChef: `lib/services/ads_ids.dart` (solo native)
4. Mediation group: bidding **Google + AppLovin + Meta** sulle unit Native, Interstitial, Rewarded, Banner.

## AppLovin
1. Account, SDK key, sblocca le app.
2. Mappa le zone sulle ad unit AdMob.

## Meta Audience Network
1. Facebook app + Audience Network, placement native.
2. App ID e Client Token in AndroidManifest / Info.plist quando li hai (non mettere valori finti: il SDK Meta può crashare).
3. Review Meta se richiesta.

## app-ads.txt
Su `savein.eu` e `smartchef-app.com` aggiungi le righe reali Meta/AppLovin al posto dei commenti in `web/app-ads.txt`, poi ridistribuisci Hosting.

Finché gli ID native di produzione sono vuoti: in debug si usano le unit test Google; in release il pin fa fallback al banner.
