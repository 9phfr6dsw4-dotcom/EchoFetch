import Darwin
import Foundation

public enum ToolSetupError: LocalizedError, Equatable {
    case missingFromApp
    case damaged(String)
    case unpackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingFromApp:
            "The download tools are missing from EchoFetch. Download EchoFetch again from its release page."
        case .damaged(let name):
            "The copy of \(name) inside EchoFetch is damaged. Download EchoFetch again from its release page."
        case .unpackFailed(let name):
            "EchoFetch couldn't set up \(name). Make sure your Mac has free disk space, then try again."
        }
    }
}

public struct ToolInstallResult: Equatable, Sendable {
    public let bundled: [ToolManifestEntry]
    public let installed: InstalledTools
}

/// Unpacks the tools shipped inside EchoFetch.app into Application Support, where yt-dlp can
/// update itself. Each tool is checked against its SHA-256, made executable, and cleared of the
/// quarantine flag the downloaded app zip carries, so macOS runs it without asking.
public struct ToolInstaller: Sendable {
    public let sourceDirectory: URL?
    public let toolsDirectory: URL

    public init(sourceDirectory: URL?, toolsDirectory: URL) {
        self.sourceDirectory = sourceDirectory
        self.toolsDirectory = toolsDirectory
    }

    public func installMissingTools() throws -> ToolInstallResult {
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
            try install(entry, from: sourceDirectory)
            installed.tools[entry.name] = InstalledTool(version: entry.version, sha256: entry.sha256)
            try installed.save(to: toolsDirectory)
        }
        return ToolInstallResult(bundled: manifest.tools, installed: installed)
    }

    private func install(_ entry: ToolManifestEntry, from source: URL) throws {
        let fileManager = FileManager.default
        let archive = source.appendingPathComponent("\(entry.name).zip", isDirectory: false)
        guard fileManager.fileExists(atPath: archive.path) else { throw ToolSetupError.missingFromApp }
        let staging = toolsDirectory.appendingPathComponent(".unpack-\(entry.name)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        guard Self.runDitto(["-x", "-k", "--noqtn", archive.path, staging.path]) else {
            throw ToolSetupError.unpackFailed(entry.name)
        }
        let unpacked = staging.appendingPathComponent(entry.name, isDirectory: false)
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
