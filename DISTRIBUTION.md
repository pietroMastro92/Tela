# Distribuzione diretta di Tela

Tela può essere distribuita gratuitamente agli utenti senza pubblicarla sul Mac App Store. Per evitare l’avviso “app danneggiata” o il blocco di Gatekeeper, il file pubblico deve però essere firmato con **Developer ID Application**, inviato al servizio notarile Apple e accompagnato dal ticket notarile.

L’app può rimanere gratuita. Il certificato Developer ID richiede che il proprietario aderisca all’Apple Developer Program; non è sufficiente il solo account Apple gratuito.

## Pacchetto gratuito senza Developer ID (anteprima)

Se vuoi distribuire subito una copia gratuita senza acquistare il programma Apple, puoi creare un pacchetto universale firmato ad-hoc:

```sh
./Scripts/package_free.sh
```

Lo script genera `Distribution-Free/Tela-VERSION-BUILD-free.zip` e `.dmg`, con checksum SHA-256 e istruzioni incluse. Questa modalità è adatta a test, collaboratori e primi video/promozioni, ma non è una release Gatekeeper-ready: su un Mac che scarica il file dal browser può essere necessario autorizzare l’app dal Finder oppure rimuovere la quarantena con:

```sh
xattr -dr com.apple.quarantine /Applications/Tela.app
```

Il comando agisce solo sulla copia scaricata. Per utenti finali senza questo passaggio, continua con la procedura Developer ID e notarizzazione seguente.

## Preparazione una tantum

1. Iscriversi all’Apple Developer Program e aggiungere l’account in Xcode.
2. In Xcode aprire **Settings → Accounts → Manage Certificates** e creare o scaricare un certificato **Developer ID Application**.
3. Salvare le credenziali notarili nel Portachiavi, senza inserirle nel repository:

   ```sh
   xcrun notarytool store-credentials TelaNotary \
     --apple-id "APPLE_ID" \
     --team-id "TEAM_ID" \
     --password "PASSWORD_SPECIFICA_PER_APP"
   ```

   In alternativa `notarytool` accetta una chiave API di App Store Connect. Il profilo `TelaNotary` conserva le credenziali nel Portachiavi di macOS.

4. Verificare che il certificato sia disponibile:

   ```sh
   security find-identity -v -p codesigning
   ```

## Creazione del DMG pubblico

Da questa cartella eseguire:

```sh
./Scripts/distribute_direct.sh
```

Lo script usa sempre la configurazione **Release**. La Demo è una funzione
esclusivamente locale di sviluppo e registrazione: il DMG distribuito non
contiene la finestra, i comandi o il codice dello Studio Demo. Per provarla,
eseguire invece una build **Debug** dal progetto Xcode o dalla riga di comando.
Il comando più semplice è `./Scripts/run_demo.sh`; apre direttamente la build
Debug firmata ad hoc e indica il tasto `⇧⌘D` per la finestra Demo.

Lo script:

- rigenera il progetto Tuist;
- crea un archivio Release universale `arm64 + x86_64`;
- abilita Hardened Runtime e timestamp sicuro;
- firma con Developer ID Application;
- notarizza e pinza il ticket su `Tela.app`;
- crea un DMG con collegamento alla cartella Applicazioni;
- notarizza il DMG e verifica il risultato con Gatekeeper.

Il risultato viene scritto in `Distribution/Tela-VERSION-BUILD.dmg`, insieme al relativo checksum SHA-256.

Se esistono più identità o il profilo ha un altro nome:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Nome (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
NOTARY_PROFILE="NomeProfilo" \
./Scripts/distribute_direct.sh
```

## Controlli prima della pubblicazione

Prima di caricare il DMG sul proprio sito o su GitHub Releases:

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Tela.app
spctl --assess --type execute --verbose=4 /Applications/Tela.app
xcrun stapler validate /Applications/Tela.app
```

Provare anche l’installazione su un secondo Mac o su un account pulito, scaricando realmente il DMG dal browser affinché macOS applichi la quarantena. La firma Developer ID e la notarizzazione non comportano pubblicazione o revisione sul Mac App Store.

## Aggiornamenti

Ogni release deve incrementare `CFBundleShortVersionString` e `CFBundleVersion` in `Project.swift`, quindi essere nuovamente firmata e notarizzata. Tela al momento non contiene un sistema di aggiornamento automatico: gli utenti sostituiscono manualmente la vecchia app nella cartella Applicazioni.
