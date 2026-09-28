import Foundation

/// Short texts for sizes, speeds and times.
public enum DisplayFormat {
    /// "0:42", "4:05", "1:02:03".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return "\(hours):\(pad(minutes)):\(pad(secs))" }
        return "\(minutes):\(pad(secs))"
    }

    /// "1:05 left".
    public static func timeLeft(_ seconds: TimeInterval) -> String {
        "\(duration(seconds)) left"
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%"
    }

    /// "245.3 MB".
    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, count), countStyle: .file)
    }

    /// "4.2 MB/s".
    public static func speed(_ bytesPerSecond: Double) -> String {
        bytes(Int64(max(0, bytesPerSecond).rounded())) + "/s"
    }

    /// "42% · 4.2 MB/s · 1:05 left", leaving out anything unknown.
    public static func progressLine(fraction: Double?, speed: Double?, eta: Double?) -> String {
        var parts: [String] = []
        if let fraction { parts.append(percent(fraction)) }
        if let speed, speed > 0 { parts.append(self.speed(speed)) }
        if let eta, eta >= 0 { parts.append(timeLeft(eta)) }
        return parts.joined(separator: " · ")
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}
