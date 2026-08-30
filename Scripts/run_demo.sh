#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
PROJECT_PATH="$PROJECT_ROOT/Tela.xcodeproj"
DERIVED_DATA=${TELA_DEMO_DERIVED_DATA:-"$PROJECT_ROOT/.build/TelaDemo"}

command -v tuist >/dev/null || {
    print -u2 "Errore: Tuist non è installato."
    exit 1
}
command -v xcodebuild >/dev/null || {
    print -u2 "Errore: Xcode command line tools non disponibili."
    exit 1
}

cd "$PROJECT_ROOT"
tuist generate --no-open

print "Compilo la build Debug locale con Studio Demo…"
xcodebuild \
    -quiet \
    -project "$PROJECT_PATH" \
    -scheme Tela \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY=- \
    build

app_path="$DERIVED_DATA/Build/Products/Debug/Tela.app"
[[ -d "$app_path" ]] || {
    print -u2 "Errore: la build non ha prodotto $app_path"
    exit 1
}

print "Studio Demo pronto: premi ⇧⌘D nella finestra Tela (oppure usa l'icona ✨ nella toolbar)."
print "La build è locale e non modifica dati, timer o cronologia reali."
open "$app_path"
