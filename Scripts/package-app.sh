#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="EchoFetch"
APP_BUNDLE="dist/${APP_NAME}.app"
ZIP_PATH="dist/${APP_NAME}.zip"
VERIFY_DIR="dist/verify-extracted"
ICONSET_DIR="dist/AppIcon.iconset"
TOOL_STAGE="dist/tool-stage"
TOOLS_BIN=".build/echofetch-tools/bin"
BUNDLE_TOOLS="$APP_BUNDLE/Contents/Resources/Tools"
SIGNING_REPORT="dist/signing.txt"
SIGN_MODE="${SIGN_MODE:-adhoc}"
export SIGN_MODE

rm -rf "$APP_BUNDLE" "$ZIP_PATH" "$ZIP_PATH.sha256" "$VERIFY_DIR" "$ICONSET_DIR" "$TOOL_STAGE" "$SIGNING_REPORT" "dist/notarize"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks" "$BUNDLE_TOOLS" "dist"

swift build --configuration release --product EchoFetchApp
install -m 755 ".build/release/EchoFetchApp" "$APP_BUNDLE/Contents/MacOS/EchoFetch"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "Resources/Acknowledgements.txt" "$APP_BUNDLE/Contents/Resources/Acknowledgements.txt"
test -x "$APP_BUNDLE/Contents/MacOS/EchoFetch"

# Sparkle comes from the exact version SwiftPM resolved and checksummed.
SPARKLE_FRAMEWORKS=()
while IFS= read -r framework; do
    SPARKLE_FRAMEWORKS+=("$framework")
done < <(find .build/artifacts -type d -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -prune)
if [[ "${#SPARKLE_FRAMEWORKS[@]}" -ne 1 ]]; then
    printf 'Expected one Sparkle.framework in .build/artifacts, found %s.\n' "${#SPARKLE_FRAMEWORKS[@]}" >&2
    exit 1
fi
ditto "${SPARKLE_FRAMEWORKS[0]}" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Resources/Info.plist" | grep -Fx '2.10.0'
test -x "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
test -x "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
otool -L "$APP_BUNDLE/Contents/MacOS/EchoFetch" | grep -F '@rpath/Sparkle.framework/Versions/B/Sparkle'
otool -l "$APP_BUNDLE/Contents/MacOS/EchoFetch" | grep -F 'path @executable_path/../Frameworks'
grep -F 'Sparkle 2.10.0' "$APP_BUNDLE/Contents/Resources/Acknowledgements.txt"

# The download tools travel inside the app as one zip each, plus a manifest with the SHA-256 of
# every executable. On first launch EchoFetch unpacks them into Application Support.
bash Scripts/fetch-tools.sh
manifest_entries=()
while read -r name version; do
    [[ -n "$name" ]] || continue
    sha="$(shasum -a 256 "$TOOLS_BIN/$name" | awk '{print $1}')"
    mkdir -p "$TOOL_STAGE/$name"
    install -m 755 "$TOOLS_BIN/$name" "$TOOL_STAGE/$name/$name"
    ditto -c -k "$TOOL_STAGE/$name" "$BUNDLE_TOOLS/$name.zip"
    rm -rf "$TOOL_STAGE/check-$name"
    ditto -x -k "$BUNDLE_TOOLS/$name.zip" "$TOOL_STAGE/check-$name"
    test "$(shasum -a 256 "$TOOL_STAGE/check-$name/$name" | awk '{print $1}')" = "$sha"
    test -x "$TOOL_STAGE/check-$name/$name"
    manifest_entries+=("{\"name\":\"$name\",\"version\":\"$version\",\"sha256\":\"$sha\"}")
done < "$TOOLS_BIN/versions.txt"
test "${#manifest_entries[@]}" -eq 4
printf '{"tools":[%s]}\n' "$(IFS=,; printf '%s' "${manifest_entries[*]}")" > "$BUNDLE_TOOLS/manifest.json"
python3 -m json.tool "$BUNDLE_TOOLS/manifest.json" > /dev/null
cat "$BUNDLE_TOOLS/manifest.json"
for tool in yt-dlp ffmpeg ffprobe deno; do
    test -s "$BUNDLE_TOOLS/$tool.zip"
    grep -F "\"name\":\"$tool\"" "$BUNDLE_TOOLS/manifest.json" > /dev/null
done
rm -rf "$TOOL_STAGE"

swift Scripts/create-app-icon.swift "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
test -s "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx 'com.echofetch.app'
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP_BUNDLE/Contents/Info.plist" | grep -E '^https://'
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_BUNDLE/Contents/Info.plist" | grep -E '^[A-Za-z0-9+/]{43}=$'
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx '0.2.3'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx '5'

# Signing is the last change to the app; everything after only zips, checks and hashes it.
bash Scripts/sign-app.sh "$APP_BUNDLE"

NOTARIZED="no"
if [[ "$SIGN_MODE" == "developer-id" ]]; then
    bash Scripts/notarize.sh "$APP_BUNDLE"
    NOTARIZED="yes"
fi

mkdir -p "$VERIFY_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/${APP_NAME}.app"
test -x "$EXTRACTED_APP/Contents/MacOS/EchoFetch"
test -x "$EXTRACTED_APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
test -L "$EXTRACTED_APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx 'EchoFetch'
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx '0.2.3'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx '5'
codesign --verify --deep --strict "$EXTRACTED_APP"
if [[ "$NOTARIZED" == "yes" ]]; then
    xcrun stapler validate "$EXTRACTED_APP"
    spctl --assess --type execute --verbose=2 "$EXTRACTED_APP"
fi
test -s "$EXTRACTED_APP/Contents/Resources/Tools/manifest.json"
test -s "$EXTRACTED_APP/Contents/Resources/Tools/yt-dlp.zip"
(
    cd "$(dirname "$ZIP_PATH")"
    shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256"
    shasum -a 256 -c "$(basename "$ZIP_PATH").sha256"
)
{
    printf 'mode=%s\n' "$SIGN_MODE"
    printf 'notarized=%s\n' "$NOTARIZED"
    codesign --display --requirements - "$EXTRACTED_APP" 2>/dev/null | sed -n 's/^designated => /requirement=/p'
} > "$SIGNING_REPORT"
cat "$SIGNING_REPORT"
du -sh "$APP_BUNDLE" "$ZIP_PATH"
printf 'Packaged and verified: %s\n' "$ZIP_PATH"
