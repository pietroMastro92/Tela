#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
PROJECT_PATH="$PROJECT_ROOT/Tela.xcodeproj"
SCHEME="Tela"
NOTARY_PROFILE=${NOTARY_PROFILE:-TelaNotary}
SIGNING_IDENTITY=${DEVELOPER_ID_APPLICATION:-}
TEAM_ID=${DEVELOPMENT_TEAM:-}
OUTPUT_DIR=${OUTPUT_DIR:-"$PROJECT_ROOT/Distribution"}

fail() {
    print -u2 "Errore: $1"
    exit 1
}

command -v tuist >/dev/null || fail "Tuist non è installato."
command -v xcodebuild >/dev/null || fail "Xcode command line tools non disponibili."

if [[ -z "$SIGNING_IDENTITY" ]]; then
    identity_line=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n '/"Developer ID Application:/p' \
        | head -n 1)
    [[ -n "$identity_line" ]] || fail "Nessun certificato Developer ID Application valido nel portachiavi."
    SIGNING_IDENTITY=$(print -r -- "$identity_line" | sed -E 's/^[[:space:]]*[0-9]+\) [A-F0-9]+ "(.*)"$/\1/')
fi

if [[ -z "$TEAM_ID" ]]; then
    TEAM_ID=$(print -r -- "$SIGNING_IDENTITY" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')
fi
[[ -n "$TEAM_ID" ]] || fail "Imposta DEVELOPMENT_TEAM con il Team ID Apple di 10 caratteri."

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/TelaDistribution.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT INT TERM

archive_path="$temporary_root/Tela.xcarchive"
derived_data="$temporary_root/DerivedData"
notary_zip="$temporary_root/Tela-notary.zip"
dmg_stage="$temporary_root/dmg"
unsigned_dmg="$temporary_root/Tela.dmg"

cd "$PROJECT_ROOT"
tuist generate --no-open

print "Creo l'archivio universale firmato con Developer ID…"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    archive

app_path="$archive_path/Products/Applications/Tela.app"
[[ -d "$app_path" ]] || fail "L'archivio non contiene Tela.app."

codesign --verify --deep --strict --verbose=2 "$app_path"
architectures=$(lipo -archs "$app_path/Contents/MacOS/Tela")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] \
    || fail "Il binario non è universale: $architectures"

# Keep the product boundary enforceable: the public Release artifact must not
# accidentally grow the local-only Demo scene if the project is edited later.
if strings "$app_path/Contents/MacOS/Tela" | rg -q "Studio Demo|DemoSessionStore|DemoStudioView|DemoDirectorPanel"; then
    fail "La build Release contiene simboli della Demo locale."
fi

print "Invio Tela.app al servizio notarile Apple…"
ditto -c -k --keepParent "$app_path" "$notary_zip"
xcrun notarytool submit "$notary_zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")
mkdir -p "$dmg_stage" "$OUTPUT_DIR"
ditto "$app_path" "$dmg_stage/Tela.app"
ln -s /Applications "$dmg_stage/Applications"

print "Creo e notarizzo il DMG…"
hdiutil create \
    -volname "Tela" \
    -srcfolder "$dmg_stage" \
    -ov \
    -format UDZO \
    "$unsigned_dmg"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$unsigned_dmg"
xcrun notarytool submit "$unsigned_dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$unsigned_dmg"
xcrun stapler validate "$unsigned_dmg"

final_dmg="$OUTPUT_DIR/Tela-${version}-${build}.dmg"
ditto "$unsigned_dmg" "$final_dmg"
shasum -a 256 "$final_dmg" > "$final_dmg.sha256"

codesign --verify --verbose=2 "$final_dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$final_dmg"

print ""
print "Distribuzione pronta: $final_dmg"
print "Checksum: $final_dmg.sha256"
print "Architetture: $architectures"
print "Profilo notarile: $NOTARY_PROFILE"
