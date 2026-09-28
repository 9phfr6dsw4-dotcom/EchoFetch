import Foundation

/// One tool shipped inside EchoFetch.app (Contents/Resources/Tools/<name>.zip).
public struct ToolManifestEntry: Codable, Equatable, Sendable {
    public var name: String
    public var version: String
    /// SHA-256 of the executable inside the zip.
    public var sha256: String

    public init(name: String, version: String, sha256: String) {
        self.name = name
        self.version = version
        self.sha256 = sha256
    }
}

/// Contents/Resources/Tools/manifest.json, written by Scripts/package-app.sh.
public struct ToolManifest: Codable, Equatable, Sendable {
    public var tools: [ToolManifestEntry]

    public init(tools: [ToolManifestEntry]) {
        self.tools = tools
    }

    public static let requiredTools = ["yt-dlp", "ffmpeg", "ffprobe", "deno"]
}

public struct InstalledTool: Codable, Equatable, Sendable {
    public var version: String
    /// Empty for a yt-dlp that updated itself.
    public var sha256: String

    public init(version: String, sha256: String) {
        self.version = version
        self.sha256 = sha256
    }
}

/// What EchoFetch has put in ~/Library/Application Support/EchoFetch/Tools (installed.json).
public struct InstalledTools: Codable, Equatable, Sendable {
    public static let fileName = "installed.json"

    public var tools: [String: InstalledTool]

    public init(tools: [String: InstalledTool] = [:]) {
        self.tools = tools
    }

    public static func load(from directory: URL) -> InstalledTools {
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let installed = try? JSONDecoder().decode(InstalledTools.self, from: data) else { return InstalledTools() }
        return installed
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.fileName, isDirectory: false), options: .atomic)
    }
}

public enum ToolInstallPlan {
    /// The tools to unpack from the app. ffmpeg, ffprobe and Deno are replaced whenever the app
    /// ships a different build. yt-dlp updates itself, so the app's copy is used only when none is
    /// installed yet or when the app ships a newer version than the installed one.
    public static func toolsToInstall(
        bundled: [ToolManifestEntry],
        installed: InstalledTools,
        existingExecutables: Set<String>
    ) -> [String] {
        bundled.compactMap { entry -> String? in
            guard existingExecutables.contains(entry.name), let current = installed.tools[entry.name] else {
                return entry.name
            }
            if entry.name == "yt-dlp" {
                return EngineVersion.isNewer(entry.version, than: current.version) ? entry.name : nil
            }
            return current.sha256 == entry.sha256 ? nil : entry.name
        }
    }
}

/// yt-dlp versions are dates such as "2026.08.19" (nightly builds add a fourth number).
public enum EngineVersion {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(candidate)
        let right = components(current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func components(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
    }
}

public enum EngineUpdatePolicy {
    /// EchoFetch looks for a new engine at most once a day.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    public static func isCheckDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock that moved backwards also counts as due.
        return now.timeIntervalSince(lastCheck) >= checkInterval || now < lastCheck
    }
}
