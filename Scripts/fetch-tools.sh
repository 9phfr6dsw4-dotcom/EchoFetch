#!/usr/bin/env bash
# Downloads the command-line tools EchoFetch ships with, at pinned versions, and checks each
# download against its SHA-256 before using it. Output: .build/echofetch-tools/bin/{yt-dlp,ffmpeg,ffprobe,deno}
# plus versions.txt ("name version" per line). Safe to run again: verified downloads are reused.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT_DIR/.build/echofetch-tools"
DOWNLOADS="$OUT/downloads"
BIN="$OUT/bin"

YTDLP_VERSION="2026.08.19"
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp_macos"
YTDLP_SHA256="0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202"

FFMPEG_VERSION="6.1.1"
FFMPEG_URL="https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffmpeg-darwin-arm64"
FFMPEG_SHA256="a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584"
FFPROBE_URL="https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffprobe-darwin-arm64"
FFPROBE_SHA256="bb2db6f5d8cef919da12fbf592119a987202a8c060a886f3cab091f9cab90b64"

DENO_VERSION="2.9.7"
DENO_URL="https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-aarch64-apple-darwin.zip"
DENO_SHA256="5cd46d6268f6f78f5d88bdc7159d20bd44cdaa4b3303474839f87ec6fe7ae25c"

mkdir -p "$DOWNLOADS" "$BIN"

verified() {
    [[ -s "$1" ]] && printf '%s  %s\n' "$2" "$1" | shasum -a 256 -c --status -
}

fetch() {
    local file="$DOWNLOADS/$1" url="$2" sha="$3"
    if ! verified "$file" "$sha"; then
        rm -f "$file"
        curl -fsSL --retry 3 --retry-delay 5 -o "$file" "$url"
    fi
    if ! verified "$file" "$sha"; then
        printf 'Checksum mismatch for %s (from %s)\n' "$1" "$url" >&2
        exit 1
    fi
    printf 'Verified %s\n' "$1"
}

fetch yt-dlp_macos "$YTDLP_URL" "$YTDLP_SHA256"
fetch ffmpeg-darwin-arm64 "$FFMPEG_URL" "$FFMPEG_SHA256"
fetch ffprobe-darwin-arm64 "$FFPROBE_URL" "$FFPROBE_SHA256"
fetch deno-aarch64-apple-darwin.zip "$DENO_URL" "$DENO_SHA256"

install -m 755 "$DOWNLOADS/yt-dlp_macos" "$BIN/yt-dlp"
install -m 755 "$DOWNLOADS/ffmpeg-darwin-arm64" "$BIN/ffmpeg"
install -m 755 "$DOWNLOADS/ffprobe-darwin-arm64" "$BIN/ffprobe"
rm -rf "$OUT/deno-unzip"
ditto -x -k "$DOWNLOADS/deno-aarch64-apple-darwin.zip" "$OUT/deno-unzip"
install -m 755 "$OUT/deno-unzip/deno" "$BIN/deno"
rm -rf "$OUT/deno-unzip"

# Each tool must start and report the pinned version on this Mac.
"$BIN/yt-dlp" --ignore-config --version | grep -Fx "$YTDLP_VERSION"
"$BIN/ffmpeg" -hide_banner -version | grep -F "ffmpeg version"
"$BIN/ffprobe" -hide_banner -version | grep -F "ffprobe version"
"$BIN/deno" --version | grep -F "deno $DENO_VERSION"

printf 'yt-dlp %s\nffmpeg %s\nffprobe %s\ndeno %s\n' \
    "$YTDLP_VERSION" "$FFMPEG_VERSION" "$FFMPEG_VERSION" "$DENO_VERSION" > "$BIN/versions.txt"
printf 'Tools ready in %s\n' "$BIN"
