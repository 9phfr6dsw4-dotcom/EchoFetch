import Foundation

/// Turns yt-dlp's error output into one plain sentence.
public enum DownloadErrorExplainer {
    private static let rules: [(needles: [String], message: String)] = [
        (["not a bot"],
         "YouTube wants to check that you're not a bot. Wait a few minutes and try again. If it keeps happening, check for an engine update in Settings."),
        (["sign in to confirm your age", "age-restricted", "inappropriate for some users"],
         "This video is age-restricted. Downloading it needs a signed-in browser, which EchoFetch doesn't support yet."),
        (["members-only", "join this channel", "available to this channel's members"],
         "This video is only for the channel's members."),
        (["private video", "video is private"],
         "This video is private."),
        (["premieres in", "live event will begin", "this live event", "is_upcoming"],
         "This video hasn't started yet. Try again once it has finished streaming."),
        (["not available in your country", "blocked it in your country", "geo restrict", "geo-restrict"],
         "This video is blocked in your country."),
        (["video unavailable", "has been removed", "no longer available", "this video is not available", "404: not found", "http error 404"],
         "This video isn't available. It may have been removed, or the link may be wrong."),
        (["unsupported url"],
         "EchoFetch can't download from this link."),
        (["requested format is not available", "no video formats found"],
         "This video doesn't offer a format EchoFetch can save. Try Download Audio, or check for an engine update in Settings."),
        (["no space left on device"],
         "Your Mac is out of disk space. Free up some space and try again."),
        (["permission denied", "operation not permitted", "unable to create directory", "read-only file system"],
         "EchoFetch couldn't save to your download folder. Choose another folder in Settings, or allow access in System Settings → Privacy & Security → Files and Folders."),
        (["unable to download webpage", "failed to resolve", "nodename nor servname", "timed out", "connection refused",
          "network is unreachable", "connection reset", "temporary failure in name resolution", "internet connection"],
         "EchoFetch couldn't connect. Check your internet connection and try again."),
        (["http error 429", "too many requests"],
         "The site is asking EchoFetch to slow down. Wait a few minutes and try again.")
    ]

    public static func explain(errorLines: [String], exitCode: Int32) -> String {
        let errors = errorLines.filter { $0.hasPrefix("ERROR:") }
        let haystack = (errors.isEmpty ? errorLines : errors).joined(separator: "\n").lowercased()
        for rule in rules where rule.needles.contains(where: { haystack.contains($0) }) {
            return rule.message
        }
        if let last = errors.last {
            return cleaned(last)
        }
        if let last = errorLines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("WARNING:") }) {
            return cleaned(last)
        }
        return "The download stopped unexpectedly (code \(exitCode))."
    }

    /// Why an engine update check failed.
    public static func explainUpdateFailure(errorLines: [String]) -> String {
        let text = errorLines.joined(separator: "\n").lowercased()
        if text.contains("unable to write") || text.contains("permission") {
            return "EchoFetch couldn't replace the download engine. Try again, or reinstall EchoFetch."
        }
        return "EchoFetch couldn't check for a new download engine. It will try again the next time it opens."
    }

    /// "ERROR: [youtube] abc123: Some message" becomes "Some message".
    static func cleaned(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("ERROR:") { text = String(text.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces) }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if let colon = text.range(of: ": "), !text[..<colon.lowerBound].contains(" ") {
                text = String(text[colon.upperBound...])
            }
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "The download stopped unexpectedly." }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
