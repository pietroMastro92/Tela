# Tela

Tela è un Pomodoro timer nativo per macOS 14+ scritto in Swift 6 e SwiftUI. Quando una sessione parte, l'opera selezionata occupa l'intera finestra e viene scoperta da una singola goccia d'inchiostro che si espande da un punto casuale stabile per quel percorso: la parte visibile è sempre nitida, senza griglie, aloni colorati o sfocature. Il focus in corso mostra un'anteprima non distruttiva del prossimo avanzamento; soltanto un focus realmente completato consolida il reveal.

## Requisiti e generazione

- macOS 14 o successivo
- Xcode 26 o successivo con Swift 6 (le API Liquid Glass sono compilate solo con il nuovo SDK e restano protette da availability check)
- Tuist 4

```sh
tuist generate --no-open
# Debug locale: include la Demo deterministica per test e registrazioni
xcodebuild -project Tela.xcodeproj -scheme Tela -configuration Debug \
  -destination 'platform=macOS' build
xcodebuild -project Tela.xcodeproj -scheme Tela -configuration Debug \
  -destination 'platform=macOS' test

# Release distribuibile: esclude completamente la Demo dal binario
xcodebuild -project Tela.xcodeproj -scheme Tela -configuration Release \
  -destination 'platform=macOS' build
```

Per creare una copia Release locale avviabile senza un certificato Developer ID:

```sh
xcodebuild -project Tela.xcodeproj -scheme Tela -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/TelaDerived \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- build
mkdir -p Build
ditto /tmp/TelaDerived/Build/Products/Release/Tela.app Build/Tela.app
open Build/Tela.app
```

Non usare `CODE_SIGNING_ALLOWED=NO` per una copia da aprire dal Finder: produce un bundle non firmato che Gatekeeper può segnalare come danneggiato. La firma ad hoc sopra è adatta all'esecuzione locale sul Mac che compila l'app; per distribuirla ad altri Mac servono Developer ID e notarizzazione.

Il progetto generato (`Tela.xcodeproj` e `Tela.xcworkspace`) è intenzionalmente ignorato da Git: `Project.swift` è la fonte di verità.

## Architettura

- `Tela/Sources/Core`: modelli persistiti, progressione delle sessioni e `TimerStore`.
- `Tela/Sources/Services`: persistenza JSON, notifiche e importazione immagini.
- `Tela/Sources/App`: ciclo di vita SwiftUI e adattatore condiviso tra finestra e menu bar.
- `Tela/Sources/Views`: dashboard, galleria, impostazioni, celebrazione e reveal.
- `Tests`: test unitari deterministici e smoke test UI.

`TimerStore` usa una deadline assoluta persistita. Al ripristino una fase focus scaduta viene chiusa una sola volta; una fase in pausa conserva invece il tempo residuo. Le fasi successive non partono automaticamente.

La UI traduce il numero di focus consolidati in un livello di rivelazione globale. Durante un focus attivo somma temporaneamente la frazione della sessione corrente, così il quadro emerge in modo continuo; se la sessione viene abbandonata, questa quota visiva scompare senza modificare il progresso consolidato. I nomi `tileCount` e `ArtworkProgress` restano nello schema esclusivamente per compatibilità con i salvataggi già creati e non corrispondono più a tessere nell'interfaccia.

Ogni fase ha un record durevole e rimane collegata al proprio ciclo focus-pausa e al percorso del quadro. “Interrompi” conserva il tempo residuo: la finestra **Attività** permette di riprendere o abbandonare le fasi sospese e distingue quadri completati con ciclo completo o percorso parziale. Terminando in seguito le pause mancanti, lo stesso record del quadro viene promosso a ciclo completo.

La finestra **Studio Demo** è disponibile soltanto nella configurazione **Debug locale**: è un ambiente effimero e deterministico per provare Tela o registrare video, con quattro focus accelerati, controlli di regia, origine del reveal selezionabile e modalità di registrazione pulita. Non usa la persistenza, le notifiche o le preferenze della sessione reale. La configurazione **Release** (e quindi il DMG prodotto dallo script di distribuzione) non compila scene, comandi o store Demo.

Per avviare rapidamente la versione locale per una registrazione:

```sh
./Scripts/run_demo.sh
```

Quando la finestra è aperta, premi `⇧⌘D` oppure il pulsante ✨ nella toolbar. La
Demo usa la stessa tela full-screen, countdown e dock dei focus reali; il
pannello **Regia Demo** aggiunge soltanto autoplay, salto fase, reset e punto
focale. Il pulsante video attiva una registrazione pulita: nasconde toolbar e
regia, lasciando quadro, inchiostro e timer/progresso minimale. `Esc`
ripristina i controlli.

## Dati locali

Lo stato versionato è salvato in `~/Library/Application Support/Tela/timer-state-v1.json`; il nome storico del file viene mantenuto per migrare automaticamente i documenti v1, mentre il contenuto corrente usa lo schema v2. Un file JSON corrotto viene spostato nello stesso percorso con suffisso `corrupt-*`, senza rimuovere le immagini importate. Le immagini JPEG, PNG, HEIC/HEIF vengono orientate, ridimensionate a un massimo di 4096 px e copiate in `~/Library/Application Support/Tela/Artwork`.

L'app non contiene account, sincronizzazione o chiamate di rete. Il sandbox concede soltanto la lettura dei file scelti esplicitamente dall'utente; Tela lavora poi sulla copia locale.

## Opere incluse

La galleria iniziale contiene 54 opere offline: 16 Klimt, 36 opere con riproduzione aperta del percorso di *Gli occhi di Monna Lisa* e i tre originali Monet, Van Gogh e Hokusai (Klimt è condiviso fra i conteggi). La galleria offre filtri dedicati e ricerca per titolo o artista.

Il romanzo cita 52 capolavori. Tela include i 36 per i quali è stata verificata una riproduzione distribuibile; le 16 opere contemporanee prive di licenza aperta verificata non vengono copiate. Il loro stato e i link ufficiali sono documentati in `Tela/Resources/MonaLisaRightsStatus.json`. Crediti, URL e licenze dei file effettivamente inclusi sono in [ARTWORKS.md](ARTWORKS.md), `Tela/Resources/ArtworkCredits.json` e `Tela/Resources/ArtworkDownloadReport.json`.

Per aggiungere un'opera inclusa:

1. verificare lo stato di pubblico dominio e i termini della riproduzione;
2. aggiungere una voce a `Scripts/public_domain_artworks.json`;
3. eseguire `python3 Scripts/fetch_public_domain_artworks.py` per generare l'imageset normalizzato;
4. controllare `Tela/Resources/ArtworkDownloadReport.json` e verificare visivamente l'immagine;
5. registrare eventuali note curatoriali o di licenza in `ARTWORKS.md`;
6. rigenerare il progetto ed eseguire build e test.

## Distribuzione

Il target usa il bundle ID `com.pietromastro.Tela`, deployment macOS 14, App Sandbox e Hardened Runtime. Per una release gratuita fuori dal Mac App Store usare `Scripts/distribute_direct.sh`: produce un DMG universale firmato con Developer ID, notarizzato e verificato con Gatekeeper. La configurazione una tantum del certificato e del profilo notarile è descritta in [DISTRIBUTION.md](DISTRIBUTION.md).

Per distribuire subito una build gratuita senza Developer ID (con autorizzazione manuale della quarantena al primo avvio) usare `./Scripts/package_free.sh`. Il pacchetto ad-hoc non contiene la Demo Studio; per registrare la Demo usare `./Scripts/run_demo.sh` in Debug.
