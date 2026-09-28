import Foundation

/// One video (or audio track) found at a link.
public struct MediaItem: Equatable, Sendable {
    public var id: String
    public var title: String
    public var uploader: String?
    public var duration: TimeInterval?
    public var thumbnailURL: URL?
    public var webpageURL: URL?
    /// The site's name as yt-dlp reports it, such as "Youtube" or "Vimeo".
    public var siteName: String?
    /// Live streams and premieres that haven't started can't be downloaded.
    public var isLiveOrUpcoming: Bool
    /// False for private, deleted or members-only entries in a playlist.
    public var isAvailable: Bool

    public init(
        id: String,
        title: String,
        uploader: String? = nil,
        duration: TimeInterval? = nil,
        thumbnailURL: URL? = nil,
        webpageURL: URL? = nil,
        siteName: String? = nil,
        isLiveOrUpcoming: Bool = false,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.uploader = uploader
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.webpageURL = webpageURL
        self.siteName = siteName
        self.isLiveOrUpcoming = isLiveOrUpcoming
        self.isAvailable = isAvailable
    }
}

/// A playlist (or any link with several videos, such as a post with more than one clip).
public struct MediaPlaylist: Equatable, Sendable {
    public var id: String
    public var title: String
    public var uploader: String?
    public var thumbnailURL: URL?
    public var entries: [MediaItem]

    public init(id: String, title: String, uploader: String? = nil, thumbnailURL: URL? = nil, entries: [MediaItem]) {
        self.id = id
        self.title = title
        self.uploader = uploader
        self.thumbnailURL = thumbnailURL
        self.entries = entries
    }

    public var availableCount: Int { entries.filter(\.isAvailable).count }
    public var unavailableCount: Int { entries.count - availableCount }
    /// The playlist's own picture, or the first video's.
    public var displayThumbnailURL: URL? { thumbnailURL ?? entries.first(where: { $0.thumbnailURL != nil })?.thumbnailURL }
}

public enum MediaInfo: Equatable, Sendable {
    case single(MediaItem)
    case playlist(MediaPlaylist)

    public var title: String {
        switch self {
        case .single(let item): item.title
        case .playlist(let playlist): playlist.title
        }
    }
}

public enum MediaInfoError: LocalizedError, Equatable {
    case unreadable
    case empty

    public var errorDescription: String? {
        switch self {
        case .unreadable: "EchoFetch couldn't read what the download engine found at this link."
        case .empty: "There's nothing to download at this link."
        }
    }
}

/// Reads the JSON that `yt-dlp --dump-single-json --flat-playlist` prints.
public enum MediaInfoParser {
    static let unavailableTitles: Set<String> = ["[Private video]", "[Deleted video]", "[Unavailable video]"]
    static let unavailableStates: Set<String> = ["private", "needs_auth", "subscriber_only", "premium_only"]

    public static func parse(_ data: Data) throws -> MediaInfo {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw MediaInfoError.unreadable
        }
        let type = string(root["_type"]) ?? "video"
        if type == "playlist" || type == "multi_video" {
            let entries = (root["entries"] as? [Any] ?? [])
                .compactMap { $0 as? [String: Any] }
                .map { item(from: $0, fallbackSite: string(root["extractor_key"])) }
            guard !entries.isEmpty else { throw MediaInfoError.empty }
            let id = string(root["id"]) ?? ""
            let title = string(root["title"]) ?? string(root["id"]) ?? "Playlist"
            return .playlist(MediaPlaylist(
                id: id,
                title: title,
                uploader: string(root["uploader"]) ?? string(root["channel"]),
                thumbnailURL: thumbnail(from: root),
                entries: entries
            ))
        }
        return .single(item(from: root, fallbackSite: nil))
    }

    static func item(from dictionary: [String: Any], fallbackSite: String?) -> MediaItem {
        let id = string(dictionary["id"]) ?? ""
        let title = string(dictionary["title"]) ?? string(dictionary["fulltitle"]) ?? id
        let liveStatus = string(dictionary["live_status"]) ?? ""
        let isLive = (dictionary["is_live"] as? Bool) == true || liveStatus == "is_live" || liveStatus == "is_upcoming"
        let availability = string(dictionary["availability"]) ?? ""
        let isAvailable = !title.isEmpty && !unavailableTitles.contains(title) && !unavailableStates.contains(availability)
        let webpage = string(dictionary["webpage_url"]) ?? string(dictionary["url"])
        return MediaItem(
            id: id,
            title: title.isEmpty ? "Untitled" : title,
            uploader: string(dictionary["uploader"]) ?? string(dictionary["channel"]),
            duration: number(dictionary["duration"]),
            thumbnailURL: thumbnail(from: dictionary),
            webpageURL: webpage.flatMap(URL.init(string:)),
            siteName: string(dictionary["extractor_key"]) ?? string(dictionary["ie_key"]) ?? fallbackSite,
            isLiveOrUpcoming: isLive,
            isAvailable: isAvailable
        )
    }

    /// The "thumbnail" field, otherwise the widest entry in "thumbnails" (the last one when no
    /// widths are given, since yt-dlp lists the best last).
    static func thumbnail(from dictionary: [String: Any]) -> URL? {
        if let direct = string(dictionary["thumbnail"]), let url = URL(string: direct) { return url }
        let thumbnails = (dictionary["thumbnails"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let candidates = thumbnails.compactMap { entry -> (url: URL, width: Double)? in
            guard let text = string(entry["url"]), let url = URL(string: text) else { return nil }
            return (url, number(entry["width"]) ?? 0)
        }
        guard let widest = candidates.max(by: { $0.width < $1.width }), widest.width > 0 else {
            return candidates.last?.url
        }
        return widest.url
    }

    static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
