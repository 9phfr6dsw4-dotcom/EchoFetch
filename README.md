<h1 align="center">EchoFetch</h1>

<p align="center">A native Mac app that saves videos and audio from a link. Copy, switch to EchoFetch, download.</p>

<p align="center"><a href="https://github.com/9phfr6dsw4-dotcom/EchoFetch/releases/latest"><strong>Download the latest release</strong></a> · macOS 26+ · Apple Silicon</p>

<p align="center">
  <a href="https://github.com/9phfr6dsw4-dotcom/EchoFetch/releases/latest"><img src="https://img.shields.io/github/v/release/9phfr6dsw4-dotcom/EchoFetch?display_name=tag" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 or later">
  <a href="https://github.com/9phfr6dsw4-dotcom/EchoFetch/actions/workflows/macos-ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/9phfr6dsw4-dotcom/EchoFetch/macos-ci.yml?branch=main&amp;label=macOS%20CI" alt="macOS CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

## Features

- Copy a YouTube (or other) link anywhere, switch to EchoFetch, and it's filled in and looked up for you, with the title, thumbnail and length.
- **Download Video** saves an MP4 in the best quality QuickTime plays on your Mac: up to 4K and 8K on M3 and later.
- **Download Audio** saves M4A (YouTube's original audio, not re-encoded) or MP3.
- Download whole playlists into their own folder. Videos that can't be downloaded are skipped.
- History of everything you've downloaded, with Show in Finder.
- The download engine ([yt-dlp](https://github.com/yt-dlp/yt-dlp)) updates itself once a day, so YouTube changes are picked up without a new EchoFetch release.

## Install

1. Download `EchoFetch.zip` from the [latest release](https://github.com/9phfr6dsw4-dotcom/EchoFetch/releases/latest), unzip it, and move EchoFetch into Applications.
2. Open it. The builds aren't notarized, so the first time macOS says it can't check the app: open **System Settings → Privacy & Security** and choose **Open Anyway**.
3. The first launch takes a few seconds while EchoFetch sets up its download tools.

## How it works

EchoFetch is a SwiftUI app that runs the command-line tools it ships with. There's no server and no API:

- **yt-dlp** finds and downloads the media. It lives in `~/Library/Application Support/EchoFetch/Tools`, where it can update itself (checksum-verified by yt-dlp).
- **ffmpeg** and **ffprobe** join video and audio into one MP4 and convert audio to MP3.
- **Deno** runs the JavaScript YouTube requires.

Each tool is downloaded at a pinned version and checked against its SHA-256 when the app is built (`Scripts/fetch-tools.sh`), and checked again when EchoFetch unpacks it.

## Building

GitHub Actions builds, tests and packages the app on macOS 26 (`.github/workflows/macos-ci.yml`). Locally, with Xcode 26:

```sh
bash Scripts/fetch-tools.sh
swift test
bash Scripts/package-app.sh   # creates dist/EchoFetch.zip
```

## Please use it responsibly

Only download videos you have the right to save, and respect each site's terms.

## License

EchoFetch is under the MIT License. The bundled tools keep their own licenses: yt-dlp (Unlicense), ffmpeg (GPL build from [ffmpeg-static](https://github.com/eugeneware/ffmpeg-static)) and Deno (MIT).
