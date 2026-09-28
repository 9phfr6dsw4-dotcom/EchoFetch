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

rm -rf "$APP_BUNDLE" "$ZIP_PATH" "$ZIP_PATH.sha256" "$VERIFY_DIR" "$ICONSET_DIR" "$TOOL_STAGE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$BUNDLE_TOOLS" "dist"

swift build --configuration release --product EchoFetchApp
install -m 755 ".build/release/EchoFetchApp" "$APP_BUNDLE/Contents/MacOS/EchoFetch"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
test -x "$APP_BUNDLE/Contents/MacOS/EchoFetch"

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

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx 'EchoFetch'
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx '0.1.0'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist" | grep -Fx '1'

mkdir -p "$VERIFY_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/${APP_NAME}.app"
test -x "$EXTRACTED_APP/Contents/MacOS/EchoFetch"
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx 'EchoFetch'
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx 'EchoFetch'
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx '0.1.0'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTRACTED_APP/Contents/Info.plist" | grep -Fx '1'
codesign --verify --deep --strict "$EXTRACTED_APP"
test -s "$EXTRACTED_APP/Contents/Resources/Tools/manifest.json"
test -s "$EXTRACTED_APP/Contents/Resources/Tools/yt-dlp.zip"
(
    cd "$(dirname "$ZIP_PATH")"
    shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256"
    shasum -a 256 -c "$(basename "$ZIP_PATH").sha256"
)
du -sh "$APP_BUNDLE" "$ZIP_PATH"
printf 'Packaged and verified: %s\n' "$ZIP_PATH"
