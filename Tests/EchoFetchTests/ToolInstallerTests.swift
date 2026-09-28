import Darwin
import Foundation
import XCTest
@testable import EchoFetchCore

final class ToolInstallerTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EchoFetchInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Builds an app-style Tools folder: one zip per tool plus manifest.json.
    private func makeSource(in root: URL, versions: [String: String] = [:], quarantine: Bool = false) throws -> URL {
        let source = root.appendingPathComponent("AppTools", isDirectory: true)
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        var entries: [ToolManifestEntry] = []
        for name in ToolManifest.requiredTools {
            let version = versions[name] ?? "1.0"
            let folder = root.appendingPathComponent("build-\(name)", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let executable = folder.appendingPathComponent(name)
            try Data("#!/bin/sh\necho \(name) \(version)\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            let zip = source.appendingPathComponent("\(name).zip")
            try runDitto(["-c", "-k", folder.path, zip.path])
            if quarantine {
                let status = "0083;00000000;Safari;".withCString { value in
                    setxattr(zip.path, "com.apple.quarantine", value, strlen(value), 0, 0)
                }
                XCTAssertEqual(status, 0)
            }
            entries.append(ToolManifestEntry(name: name, version: version, sha256: try FileDigest.sha256(of: executable)))
        }
        try JSONEncoder().encode(ToolManifest(tools: entries)).write(to: source.appendingPathComponent("manifest.json"))
        return source
    }

    private func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func output(of executable: URL) async throws -> String {
        let result = try await ToolProcess(executableURL: executable, arguments: []).run(collectOutput: true)
        return result.standardOutput.joined(separator: "\n")
    }

    func testInstallsEveryToolReadyToRunWithoutQuarantine() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(in: root, versions: ["yt-dlp": "2026.08.19"], quarantine: true)
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let result = try ToolInstaller(sourceDirectory: source, toolsDirectory: tools).installMissingTools()

        XCTAssertEqual(result.bundled.map(\.name), ToolManifest.requiredTools)
        XCTAssertEqual(Set(result.installed.tools.keys), Set(ToolManifest.requiredTools))
        XCTAssertEqual(result.installed.tools["yt-dlp"]?.version, "2026.08.19")
        XCTAssertEqual(InstalledTools.load(from: tools), result.installed)
        let paths = ToolPaths(directory: tools)
        for executable in [paths.ytDLP, paths.ffmpeg, paths.ffprobe, paths.deno] {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), executable.lastPathComponent)
            XCTAssertEqual(getxattr(executable.path, "com.apple.quarantine", nil, 0, 0, 0), -1, executable.lastPathComponent)
        }
        let engineOutput = try await output(of: paths.ytDLP)
        XCTAssertEqual(engineOutput, "yt-dlp 2026.08.19")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tools.path).filter { $0.hasPrefix(".unpack") }
        XCTAssertEqual(leftovers, [])
    }

    func testASecondLaunchKeepsTheInstalledTools() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(in: root)
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        _ = try ToolInstaller(sourceDirectory: source, toolsDirectory: tools).installMissingTools()
        let ffmpeg = ToolPaths(directory: tools).ffmpeg
        let marker = Data("#!/bin/sh\necho kept\n".utf8)
        try marker.write(to: ffmpeg)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)

        _ = try ToolInstaller(sourceDirectory: source, toolsDirectory: tools).installMissingTools()
        XCTAssertEqual(try Data(contentsOf: ffmpeg), marker)
    }

    func testANewerAppReplacesChangedToolsButKeepsANewerEngine() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        _ = try ToolInstaller(sourceDirectory: try makeSource(in: root, versions: ["yt-dlp": "2026.08.19"]), toolsDirectory: tools).installMissingTools()
        var installed = InstalledTools.load(from: tools)
        installed.tools["yt-dlp"] = InstalledTool(version: "2026.09.30", sha256: "")
        try installed.save(to: tools)

        let result = try ToolInstaller(
            sourceDirectory: try makeSource(in: root, versions: ["yt-dlp": "2026.09.01", "ffmpeg": "2.0"]),
            toolsDirectory: tools
        ).installMissingTools()
        XCTAssertEqual(result.installed.tools["yt-dlp"]?.version, "2026.09.30")
        XCTAssertEqual(result.installed.tools["ffmpeg"]?.version, "2.0")
        XCTAssertEqual(String(decoding: try Data(contentsOf: ToolPaths(directory: tools).ffmpeg), as: UTF8.self), "#!/bin/sh\necho ffmpeg 2.0\n")
    }

    func testDamagedOrMissingToolsAreReported() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        XCTAssertThrowsError(try ToolInstaller(sourceDirectory: nil, toolsDirectory: tools).installMissingTools()) { error in
            XCTAssertEqual(error as? ToolSetupError, .missingFromApp)
        }
        let source = try makeSource(in: root)
        var manifest = try JSONDecoder().decode(ToolManifest.self, from: Data(contentsOf: source.appendingPathComponent("manifest.json")))
        manifest.tools[1].sha256 = "0000"
        try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try ToolInstaller(sourceDirectory: source, toolsDirectory: tools).installMissingTools()) { error in
            XCTAssertEqual(error as? ToolSetupError, .damaged("ffmpeg"))
        }
        manifest.tools.removeLast()
        try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try ToolInstaller(sourceDirectory: source, toolsDirectory: tools).installMissingTools()) { error in
            XCTAssertEqual(error as? ToolSetupError, .missingFromApp)
        }
    }
}
