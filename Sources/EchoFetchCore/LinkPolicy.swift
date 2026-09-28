import Foundation

/// Decides whether some text is a link EchoFetch can look up, and whether a YouTube video link
/// also points at a playlist that could be downloaded instead.
public enum LinkPolicy {
    static let youTubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtu.be", "www.youtu.be", "youtube-nocookie.com", "www.youtube-nocookie.com"
    ]

    /// The link in `text`, or nil when the text isn't a single web link. Surrounding spaces,
    /// quotes and angle brackets are ignored. A link without "https://" is accepted only when it
    /// has a path ("youtube.com/watch?v=…"), so ordinary text such as "e.g." is never taken for one.
    public static func link(from text: String) -> URL? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.count >= 2, let first = candidate.first, let last = candidate.last,
           (first == "<" && last == ">") || (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            candidate = String(candidate.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !candidate.isEmpty, !candidate.contains(where: { $0.isWhitespace }) else { return nil }

        let lowercased = candidate.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            guard !candidate.contains("://"), let slash = candidate.firstIndex(of: "/"),
                  candidate[candidate.index(after: slash)...].contains(where: { !$0.isWhitespace }) else { return nil }
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), isPlausibleHost(host) else { return nil }
        return url
    }

    /// True for youtube.com, youtu.be, music.youtube.com and their mobile and privacy variants.
    public static func isYouTube(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return youTubeHosts.contains(host)
    }

    /// The playlist a YouTube video link was opened from ("…watch?v=…&list=…"), when offering
    /// "download the whole playlist" makes sense. Nil for links that are already a playlist
    /// ("/playlist?list=…"), for automatic Mixes (lists starting with "RD"), and for the private
    /// Watch Later and Liked lists.
    public static func playlistOffer(for url: URL) -> String? {
        guard isYouTube(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path.lowercased() != "/playlist",
              let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
              !list.isEmpty else { return nil }
        if list.hasPrefix("RD") || ["WL", "LL", "LM"].contains(list) { return nil }
        return list
    }

    private static func isPlausibleHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts.contains(where: { $0.isEmpty }), let last = parts.last else { return false }
        return last.count >= 2 && last.allSatisfy { $0.isLetter }
    }
}
