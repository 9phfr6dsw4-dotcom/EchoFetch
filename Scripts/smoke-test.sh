#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGED_APP="$ROOT_DIR/dist/verify-extracted/EchoFetch.app"
BUILD_DIR="$ROOT_DIR/.build"
BUILD_BACKUP="$ROOT_DIR/.build-smoke-test-backup.$$"
SMOKE_PARENT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
TOOLS_DIR="$HOME/Library/Application Support/EchoFetch/Tools"

if [[ ! -d "$PACKAGED_APP" ]]; then
    printf 'Extracted packaged app does not exist: %s\n' "$PACKAGED_APP" >&2
    exit 1
fi
test -x "$PACKAGED_APP/Contents/MacOS/EchoFetch"
test -s "$PACKAGED_APP/Contents/Resources/Tools/manifest.json"

mkdir -p "$SMOKE_PARENT"
SMOKE_DIR="$(mktemp -d "$SMOKE_PARENT/echofetch-smoke.XXXXXX")"
SMOKE_APP="$SMOKE_DIR/EchoFetch.app"

echo 'Copying the extracted release app to a clean temporary location.'
ditto "$PACKAGED_APP" "$SMOKE_APP"

cleanup() {
    status=$?
    trap - EXIT
    pkill -x EchoFetch >/dev/null 2>&1 || true
    if [[ -d "$BUILD_BACKUP" ]]; then
        rm -rf "$BUILD_DIR"
        mv "$BUILD_BACKUP" "$BUILD_DIR"
    fi
    rm -rf "$SMOKE_DIR"
    exit "$status"
}
trap cleanup EXIT

if [[ -e "$BUILD_BACKUP" ]]; then
    printf 'Refusing to overwrite stale build backup: %s\n' "$BUILD_BACKUP" >&2
    exit 1
fi
if [[ -e "$BUILD_DIR" ]]; then
    mv "$BUILD_DIR" "$BUILD_BACKUP"
fi
if [[ -e "$BUILD_DIR" ]]; then
    printf 'Build directory is still present; refusing an unisolated launch test.\n' >&2
    exit 1
fi

# Start from a Mac that has never run EchoFetch, so the first-launch tool setup is tested.
rm -rf "$HOME/Library/Application Support/EchoFetch"

printf 'Build directory is unavailable; launching extracted app from %s\n' "$SMOKE_APP"
open -n -g "$SMOKE_APP"

running=0
for _ in {1..10}; do
    if pgrep -x EchoFetch >/dev/null 2>&1; then
        sleep 3
        if pgrep -x EchoFetch >/dev/null 2>&1; then
            running=1
            break
        fi
    fi
    sleep 1
done
if [[ "$running" != 1 ]]; then
    printf 'EchoFetch did not remain running after launch without its SwiftPM build directory.\n' >&2
    exit 1
fi
printf 'Clean-location launch smoke test passed; EchoFetch remained running.\n'

# EchoFetch unpacks its tools into Application Support on first launch.
ready=0
for _ in {1..60}; do
    if [[ -s "$TOOLS_DIR/installed.json" ]] \
        && [[ -x "$TOOLS_DIR/yt-dlp" && -x "$TOOLS_DIR/ffmpeg" && -x "$TOOLS_DIR/ffprobe" && -x "$TOOLS_DIR/deno" ]] \
        && grep -F '"deno"' "$TOOLS_DIR/installed.json" >/dev/null \
        && grep -F '"ffprobe"' "$TOOLS_DIR/installed.json" >/dev/null; then
        ready=1
        break
    fi
    sleep 1
done
if [[ "$ready" != 1 ]]; then
    printf 'EchoFetch did not set up its download tools in %s\n' "$TOOLS_DIR" >&2
    ls -la "$TOOLS_DIR" >&2 || true
    exit 1
fi
cat "$TOOLS_DIR/installed.json"
"$TOOLS_DIR/yt-dlp" --ignore-config --version
"$TOOLS_DIR/ffmpeg" -hide_banner -version | grep -F "ffmpeg version"
"$TOOLS_DIR/ffprobe" -hide_banner -version | grep -F "ffprobe version"
"$TOOLS_DIR/deno" --version | grep -F "deno "
printf 'First-launch tool setup passed.\n'
