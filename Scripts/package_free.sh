#!/bin/zsh

set -euo pipefail

# Avoid AppleDouble sidecar files in ZIP/DMG archives while preserving the
# bundle's actual code signature and resources.
export COPYFILE_DISABLE=1

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
PROJECT_PATH="$PROJECT_ROOT/Tela.xcodeproj"
SCHEME="Tela"
OUTPUT_DIR=${OUTPUT_DIR:-"$PROJECT_ROOT/Distribution-Free"}
DERIVED_DATA=${TELA_FREE_DERIVED_DATA:-"$PROJECT_ROOT/.build/TelaFree"}

fail() {
    print -u2 "Errore: $1"
    exit 1
}

command -v tuist >/dev/null || fail "Tuist non è installato."
command -v xcodebuild >/dev/null || fail "Xcode command line tools non disponibili."
command -v hdiutil >/dev/null || fail "hdiutil non è disponibile su questo Mac."

cd "$PROJECT_ROOT"
tuist generate --no-open

print "Compilo Tela Release per la distribuzione gratuita ad-hoc…"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY=- \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

app_path="$DERIVED_DATA/Build/Products/Release/Tela.app"
[[ -d "$app_path" ]] || fail "La build non ha prodotto $app_path"
binary_path="$app_path/Contents/MacOS/Tela"

codesign --verify --deep --strict --verbose=2 "$app_path" || fail "La firma ad-hoc dell'app non è valida."
architectures=$(lipo -archs "$binary_path")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] \
    || fail "Il binario non è universale: $architectures"

# The public Release boundary must never contain the local-only Demo Studio.
if strings "$binary_path" | rg -q "Studio Demo|DemoSessionStore|DemoStudioView|DemoDirectorPanel"; then
    fail "La build Release contiene simboli della Demo locale."
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")
package_name="Tela-${version}-${build}-free"

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/TelaFree.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT INT TERM
zip_stage="$temporary_root/$package_name"
dmg_stage="$temporary_root/dmg"
mkdir -p "$zip_stage" "$dmg_stage" "$OUTPUT_DIR"

readme="$temporary_root/LEGGIMI.txt"
{
    print "Tela ${version} (${build}) — distribuzione gratuita";
    print "";
    print "Questa copia è firmata ad-hoc per distribuire Tela senza il Mac App Store.";
    print "La Demo Studio è disponibile nelle build Debug locali, non in questa Release.";
    print "";
    print "Installazione:";
    print "1. Trascina Tela.app nella cartella Applicazioni.";
    print "2. Se macOS mostra ‘app danneggiata’, apri Terminale ed esegui:";
    print "   xattr -dr com.apple.quarantine /Applications/Tela.app";
    print "3. Avvia Tela dal Finder. Il comando rimuove soltanto la quarantena del download.";
    print "";
    print "Per una distribuzione senza questo passaggio serve Developer ID + notarizzazione.";
} > "$readme"

ditto --norsrc "$app_path" "$zip_stage/Tela.app"
ditto --norsrc "$app_path" "$dmg_stage/Tela.app"
cp "$readme" "$zip_stage/LEGGIMI.txt"
cp "$readme" "$dmg_stage/LEGGIMI.txt"
ln -s /Applications "$dmg_stage/Applicazioni"

zip_path="$OUTPUT_DIR/${package_name}.zip"
dmg_path="$OUTPUT_DIR/${package_name}.dmg"
rm -f "$zip_path" "$dmg_path" "$zip_path.sha256" "$dmg_path.sha256"

print "Creo ZIP e DMG…"
ditto --norsrc -c -k --keepParent "$zip_stage" "$zip_path"
hdiutil create -volname "Tela" -srcfolder "$dmg_stage" -ov -format UDZO "$dmg_path" >/dev/null

shasum -a 256 "$zip_path" > "$zip_path.sha256"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"

print ""
print "Pacchetti gratuiti pronti:"
print "  $zip_path"
print "  $dmg_path"
print "Checksum:"
print "  $zip_path.sha256"
print "  $dmg_path.sha256"
print "Architetture: $architectures"
print "Nota: firma ad-hoc; per Gatekeeper su Mac di terzi usare Developer ID e notarizzazione."
