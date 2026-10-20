import Darwin
import Foundation

public enum ToolSetupError: LocalizedError, Equatable {
    case missingFromApp
    case damaged(String)
    case unpackFailed(String)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingFromApp:
            "EchoFetch's list of download tools is missing. Download EchoFetch again from its release page."
        case .damaged(let name):
            "The copy of \(name) that EchoFetch downloaded didn't match what it expects, so it wasn't used. Try again. If it keeps happening, download EchoFetch again from its release page."
        case .downloadFailed:
            "EchoFetch needs an internet connection the first time it opens, to download its download tools. Check your connection, then try again."
        case .unpackFailed(let name):
            "EchoFetch couldn't set up \(name). Make sure your Mac has free disk space, then try again."
        }
    }
}

public struct ToolInstallResult: Equatable, Sendable {
    public let bundled: [ToolManifestEntry]
    public let installed: InstalledTools
}

/// Fetches one file. The real one uses the network; tests hand in their own.
public protocol ToolDownloader: Sendable {
    func download(_ url: URL, to destination: URL) async throws
}

public struct NetworkToolDownloader: ToolDownloader {
    public init() {}

    public func download(_ url: URL, to destination: URL) async throws {
        guard url.scheme?.lowercased() == "https" else { throw ToolSetupError.missingFromApp }
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw ToolSetupError.downloadFailed(url.lastPathComponent)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

/// Downloads the tools listed in the app's manifest into Application Support, where yt-dlp can
/// update itself. Every download is checked against its pinned SHA-256 before it is used, then the
/// executable inside is checked again, made executable, and cleared of any quarantine flag.
public struct ToolInstaller: Sendable {
    public let sourceDirectory: URL?
    public let toolsDirectory: URL
    private let downloader: any ToolDownloader

    public init(sourceDirectory: URL?, toolsDirectory: URL, downloader: any ToolDownloader = NetworkToolDownloader()) {
        self.sourceDirectory = sourceDirectory
        self.toolsDirectory = toolsDirectory
        self.downloader = downloader
    }

    public func installMissingTools() async throws -> ToolInstallResult {
        guard let sourceDirectory,
              let data = try? Data(contentsOf: sourceDirectory.appendingPathComponent("manifest.json", isDirectory: false)),
              let manifest = try? JSONDecoder().decode(ToolManifest.self, from: data),
              Set(manifest.tools.map(\.name)).isSuperset(of: ToolManifest.requiredTools) else {
            throw ToolSetupError.missingFromApp
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        var installed = InstalledTools.load(from: toolsDirectory)
        let existing = Set(manifest.tools.map(\.name).filter {
            fileManager.isExecutableFile(atPath: toolsDirectory.appendingPathComponent($0, isDirectory: false).path)
        })
        let plan = ToolInstallPlan.toolsToInstall(bundled: manifest.tools, installed: installed, existingExecutables: existing)
        for entry in manifest.tools where plan.contains(entry.name) {
            try await install(entry)
            installed.tools[entry.name] = InstalledTool(version: entry.version, sha256: entry.sha256)
            try installed.save(to: toolsDirectory)
        }
        return ToolInstallResult(bundled: manifest.tools, installed: installed)
    }

    private func install(_ entry: ToolManifestEntry) async throws {
        let fileManager = FileManager.default
        guard let url = URL(string: entry.url) else { throw ToolSetupError.missingFromApp }
        let staging = toolsDirectory.appendingPathComponent(".unpack-\(entry.name)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let download = staging.appendingPathComponent("download", isDirectory: false)
        do {
            try await downloader.download(url, to: download)
        } catch let error as ToolSetupError {
            throw error
        } catch {
            throw ToolSetupError.downloadFailed(entry.name)
        }
        guard (try? FileDigest.sha256(of: download)) == entry.downloadSHA256 else {
            throw ToolSetupError.damaged(entry.name)
        }

        let unpacked: URL
        switch entry.archive {
        case .file:
            unpacked = download
        case .zip:
            let folder = staging.appendingPathComponent("unzipped", isDirectory: true)
            guard Self.runDitto(["-x", "-k", "--noqtn", download.path, folder.path]) else {
                throw ToolSetupError.unpackFailed(entry.name)
            }
            unpacked = folder.appendingPathComponent(entry.name, isDirectory: false)
        }
        guard fileManager.fileExists(atPath: unpacked.path),
              (try? FileDigest.sha256(of: unpacked)) == entry.sha256 else {
            throw ToolSetupError.damaged(entry.name)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unpacked.path)
        _ = removexattr(unpacked.path, "com.apple.quarantine", 0)

        let destination = toolsDirectory.appendingPathComponent(entry.name, isDirectory: false)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: unpacked, to: destination)
    }

    private static func runDitto(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
