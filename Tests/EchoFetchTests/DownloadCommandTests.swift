import Foundation
import XCTest
@testable import EchoFetchCore

final class DownloadCommandTests: XCTestCase {
    private let tools = ToolPaths(directory: URL(fileURLWithPath: "/Users/me/Library/Application Support/EchoFetch/Tools", isDirectory: true))
    private let shared = [
        "--ignore-config",
        "--color", "no_color",
        "--no-js-runtimes",
        "--js-runtimes", "deno:/Users/me/Library/Application Support/EchoFetch/Tools/deno",
        "--ffmpeg-location", "/Users/me/Library/Application Support/EchoFetch/Tools"
    ]
    private let progressTemplate = "download:ECHOFETCH_PROGRESS %(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(info.vcodec)s"

    func testToolPathsPointInsideTheToolsFolder() {
        XCTAssertEqual(tools.ytDLP.path, "/Users/me/Library/Application Support/EchoFetch/Tools/yt-dlp")
        XCTAssertEqual(tools.ffmpeg.lastPathComponent, "ffmpeg")
        XCTAssertEqual(tools.ffprobe.lastPathComponent, "ffprobe")
        XCTAssertEqual(tools.deno.lastPathComponent, "deno")
    }

    func testPreviewLooksUpWithoutDownloading() {
        XCTAssertEqual(
            DownloadCommand.previewArguments(link: "https://youtu.be/a?list=PL1", wholePlaylist: false, tools: tools),
            shared + ["--dump-single-json", "--flat-playlist", "--no-playlist", "--no-warnings", "--", "https://youtu.be/a?list=PL1"]
        )
        XCTAssertEqual(
            DownloadCommand.previewArguments(link: "https://youtu.be/a?list=PL1", wholePlaylist: true, tools: tools).suffix(5),
            ["--flat-playlist", "--yes-playlist", "--no-warnings", "--", "https://youtu.be/a?list=PL1"]
        )
    }

    func testSingleVideoDownloadAsksForAQuickTimeFriendlyMP4() {
        let request = DownloadRequest(link: "https://www.youtube.com/watch?v=a", kind: .video, audioFormat: .m4a, isPlaylist: false, allowsAV1: true)
        let arguments = DownloadCommand.downloadArguments(
            for: request,
            destination: URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true),
            temporaryDirectory: URL(fileURLWithPath: "/Users/me/Library/Caches/EchoFetch/Partial/job", isDirectory: true),
            tools: tools
        )
        XCTAssertEqual(arguments, shared + [
            "--newline",
            "--progress",
            "--progress-delta", "0.5",
            "--progress-template", progressTemplate,
            "--print", "before_dl:ECHOFETCH_ITEM %(playlist_index)s|%(n_entries)s|%(title)s",
            "--print", "after_move:ECHOFETCH_FILE %(filepath)s",
            "--no-simulate",
            "--no-mtime",
            "--paths", "home:/Users/me/Downloads",
            "--paths", "temp:/Users/me/Library/Caches/EchoFetch/Partial/job",
            "--output", "%(title).180B.%(ext)s",
            "--no-playlist",
            "--format", "bv*[vcodec~='^(av01|avc1)']+ba[ext=m4a]/bv*[vcodec~='^(av01|avc1)']+ba/b[ext=mp4]/bv*+ba/b",
            "--merge-output-format", "mp4",
            "--", "https://www.youtube.com/watch?v=a"
        ])
    }

    func testMacsWithoutAV1GetH264() {
        XCTAssertEqual(
            DownloadCommand.videoFormatSelector(allowsAV1: false),
            "bv*[vcodec^=avc1]+ba[ext=m4a]/bv*[vcodec^=avc1]+ba/b[ext=mp4]/bv*+ba/b"
        )
    }

    func testAudioFormatsAndPlaylists() {
        let destination = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        let temporary = URL(fileURLWithPath: "/tmp/partial", isDirectory: true)
        let m4a = DownloadCommand.downloadArguments(
            for: DownloadRequest(link: "https://x.com/v", kind: .audio, audioFormat: .m4a, isPlaylist: false, allowsAV1: true),
            destination: destination, temporaryDirectory: temporary, tools: tools
        )
        XCTAssertEqual(Array(m4a.suffix(8)), [
            "--no-playlist",
            "--format", "ba[ext=m4a]/ba[acodec^=mp4a]/ba/b", "--extract-audio", "--audio-format", "m4a",
            "--", "https://x.com/v"
        ])

        let mp3Playlist = DownloadCommand.downloadArguments(
            for: DownloadRequest(link: "https://www.youtube.com/playlist?list=PL1", kind: .audio, audioFormat: .mp3, isPlaylist: true, allowsAV1: false),
            destination: destination, temporaryDirectory: temporary, tools: tools
        )
        XCTAssertEqual(Array(mp3Playlist.suffix(13)), [
            "--output", "%(playlist_title,playlist_id).120B/%(playlist_index)03d - %(title).150B.%(ext)s",
            "--yes-playlist", "--ignore-errors",
            "--format", "ba/b", "--extract-audio", "--audio-format", "mp3", "--audio-quality", "0",
            "--", "https://www.youtube.com/playlist?list=PL1"
        ])
        XCTAssertFalse(mp3Playlist.contains("--no-playlist"))
    }

    func testUpdateAndVersionCommandsIgnoreConfigFiles() {
        XCTAssertEqual(DownloadCommand.updateArguments(), ["--ignore-config", "--color", "no_color", "--update"])
        XCTAssertEqual(DownloadCommand.versionArguments(), ["--ignore-config", "--version"])
    }
}
