import Foundation

public enum DownloadKind: String, Codable, CaseIterable, Sendable {
    case video
    case audio
}

public enum AudioFormat: String, Codable, CaseIterable, Sendable {
    /// YouTube's own AAC audio, saved without re-encoding.
    case m4a
    /// Converted at high quality (VBR V0) for older players.
    case mp3
}

/// Where the command-line tools live once EchoFetch has installed them.
public struct ToolPaths: Equatable, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var ytDLP: URL { directory.appendingPathComponent("yt-dlp", isDirectory: false) }
    public var ffmpeg: URL { directory.appendingPathComponent("ffmpeg", isDirectory: false) }
    public var ffprobe: URL { directory.appendingPathComponent("ffprobe", isDirectory: false) }
    public var deno: URL { directory.appendingPathComponent("deno", isDirectory: false) }
}

public struct DownloadRequest: Equatable, Sendable {
    public var link: String
    public var kind: DownloadKind
    public var audioFormat: AudioFormat
    /// Downloads every video in the playlist into its own folder.
    public var isPlaylist: Bool
    /// True on Macs that decode AV1 in hardware (M3 and later), where QuickTime plays it.
    public var allowsAV1: Bool

    public init(link: String, kind: DownloadKind, audioFormat: AudioFormat, isPlaylist: Bool, allowsAV1: Bool) {
        self.link = link
        self.kind = kind
        self.audioFormat = audioFormat
        self.isPlaylist = isPlaylist
        self.allowsAV1 = allowsAV1
    }
}

/// Builds the yt-dlp command lines EchoFetch runs. Every command ignores yt-dlp config files on
/// this Mac, so the results never depend on settings made for other tools.
public enum DownloadCommand {
    public static let progressMarker = "ECHOFETCH_PROGRESS "
    public static let itemMarker = "ECHOFETCH_ITEM "
    public static let fileMarker = "ECHOFETCH_FILE "

    public static let singleOutputTemplate = "%(title).180B.%(ext)s"
    public static let playlistOutputTemplate = "%(playlist_title,playlist_id).120B/%(playlist_index)03d - %(title).150B.%(ext)s"

    /// Looks up a link without downloading it. Playlists are listed without opening every video.
    public static func previewArguments(link: String, wholePlaylist: Bool, tools: ToolPaths) -> [String] {
        sharedArguments(tools: tools) + [
            "--dump-single-json",
            "--flat-playlist",
            wholePlaylist ? "--yes-playlist" : "--no-playlist",
            "--no-warnings",
            "--",
            link
        ]
    }

    public static func downloadArguments(
        for request: DownloadRequest,
        destination: URL,
        temporaryDirectory: URL,
        tools: ToolPaths
    ) -> [String] {
        var arguments = sharedArguments(tools: tools)
        arguments += [
            "--newline",
            "--progress",
            "--progress-delta", "0.5",
            "--progress-template", "download:" + progressMarker + progressFields,
            "--print", "before_dl:" + itemMarker + "%(playlist_index)s|%(n_entries)s|%(title)s",
            "--print", "after_move:" + fileMarker + "%(filepath)s",
            "--no-simulate",
            "--no-mtime",
            "--paths", "home:" + destination.path,
            "--paths", "temp:" + temporaryDirectory.path,
            "--output", request.isPlaylist ? playlistOutputTemplate : singleOutputTemplate
        ]
        arguments += request.isPlaylist ? ["--yes-playlist", "--ignore-errors"] : ["--no-playlist"]
        arguments += formatArguments(kind: request.kind, audioFormat: request.audioFormat, allowsAV1: request.allowsAV1)
        arguments += ["--", request.link]
        return arguments
    }

    /// Updates yt-dlp in place from its official GitHub releases (checksum-verified by yt-dlp).
    public static func updateArguments() -> [String] {
        ["--ignore-config", "--color", "no_color", "--update"]
    }

    public static func versionArguments() -> [String] {
        ["--ignore-config", "--version"]
    }

    /// The best video QuickTime can play: AV1 (on Macs that decode it) or H.264, with AAC audio,
    /// in an MP4. VP9 is skipped because QuickTime can't open it.
    public static func videoFormatSelector(allowsAV1: Bool) -> String {
        let codecs = allowsAV1 ? "[vcodec~='^(av01|avc1)']" : "[vcodec^=avc1]"
        return "bv*\(codecs)+ba[ext=m4a]/bv*\(codecs)+ba/b[ext=mp4]/bv*+ba/b"
    }

    static func formatArguments(kind: DownloadKind, audioFormat: AudioFormat, allowsAV1: Bool) -> [String] {
        switch (kind, audioFormat) {
        case (.video, _):
            return ["--format", videoFormatSelector(allowsAV1: allowsAV1), "--merge-output-format", "mp4"]
        case (.audio, .m4a):
            return ["--format", "ba[ext=m4a]/ba[acodec^=mp4a]/ba/b", "--extract-audio", "--audio-format", "m4a"]
        case (.audio, .mp3):
            return ["--format", "ba/b", "--extract-audio", "--audio-format", "mp3", "--audio-quality", "0"]
        }
    }

    static let progressFields = [
        "%(progress.status)s",
        "%(progress.downloaded_bytes)s",
        "%(progress.total_bytes)s",
        "%(progress.total_bytes_estimate)s",
        "%(progress.speed)s",
        "%(progress.eta)s",
        "%(info.vcodec)s"
    ].joined(separator: "|")

    static func sharedArguments(tools: ToolPaths) -> [String] {
        [
            "--ignore-config",
            "--color", "no_color",
            "--no-js-runtimes",
            "--js-runtimes", "deno:" + tools.deno.path,
            "--ffmpeg-location", tools.directory.path
        ]
    }
}
