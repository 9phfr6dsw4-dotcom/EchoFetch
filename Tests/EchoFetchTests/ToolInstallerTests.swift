import Darwin
import Foundation
import XCTest
@testable import EchoFetchCore

/// Serves files from a folder by address, like the network would.
private final class StubDownloader: ToolDownloader, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: URL]
    private var requested: [String] = []

    init(files: [String: URL] = [:]) {
        self.files = files
    }

    var requests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    func download(_ url: URL, to destination: URL) async throws {
        lock.lock()
        requested.append(url.absoluteString)
        let source = files[url.absoluteString]
        lock.unlock()
        guard let source else { throw URLError(.notConnectedToInternet) }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

final class ToolInstallerTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EchoFetchInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Builds what the app carries (just manifest.json) and a stand-in for the network that
    /// serves each tool. Deno is a zip, the rest are plain files, like the real releases.
    private func makeSource(in root: URL, versions: [String: String] = [:]) throws -> (source: URL, downloader: StubDownloader) {
        let source = root.appendingPathComponent("AppTools", isDirectory: true)
        let server = root.appendingPathComponent("server", isDirectory: true)
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: server, withIntermediateDirectories: true)
        var entries: [ToolManifestEntry] = []
        var served: [String: URL] = [:]
        for name in ToolManifest.requiredTools {
            let version = versions[name] ?? "1.0"
            let folder = root.appendingPathComponent("build-\(name)-\(version)", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let executable = folder.appendingPathComponent(name)
            try Data("#!/bin/sh\necho \(name) \(version)\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

            let isZip = name == "deno"
            let download = server.appendingPathComponent("\(name)-\(version)\(isZip ? ".zip" : "")")
            if isZip {
                try runDitto(["-c", "-k", folder.path, download.path])
            } else {
                try FileManager.default.copyItem(at: executable, to: download)
            }
            let address = "https://tools.example/\(download.lastPathComponent)"
            served[address] = download
            entries.append(ToolManifestEntry(
                name: name,
                version: version,
                sha256: try FileDigest.sha256(of: executable),
                url: address,
                archive: isZip ? .zip : .file,
                downloadSHA256: try FileDigest.sha256(of: download)
            ))
        }
        try JSONEncoder().encode(ToolManifest(tools: entries)).write(to: source.appendingPathComponent("manifest.json"))
        return (source, StubDownloader(files: served))
    }

    private func installer(_ source: URL?, _ tools: URL, _ downloader: StubDownloader) -> ToolInstaller {
        ToolInstaller(sourceDirectory: source, toolsDirectory: tools, downloader: downloader)
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

    func testDownloadsEveryToolReadyToRunWithoutQuarantine() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (source, downloader) = try makeSource(in: root, versions: ["yt-dlp": "2026.08.19"])
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let result = try await installer(source, tools, downloader).installMissingTools()

        XCTAssertEqual(result.bundled.map(\.name), ToolManifest.requiredTools)
        XCTAssertEqual(Set(result.installed.tools.keys), Set(ToolManifest.requiredTools))
        XCTAssertEqual(result.installed.tools["yt-dlp"]?.version, "2026.08.19")
        XCTAssertEqual(InstalledTools.load(from: tools), result.installed)
        XCTAssertEqual(downloader.requests.count, 4)
        let paths = ToolPaths(directory: tools)
        for executable in [paths.ytDLP, paths.ffmpeg, paths.ffprobe, paths.deno] {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), executable.lastPathComponent)
            XCTAssertEqual(getxattr(executable.path, "com.apple.quarantine", nil, 0, 0, 0), -1, executable.lastPathComponent)
        }
        let engineOutput = try await output(of: paths.ytDLP)
        XCTAssertEqual(engineOutput, "yt-dlp 2026.08.19")
        let denoOutput = try await output(of: paths.deno)
        XCTAssertEqual(denoOutput, "deno 1.0")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tools.path).filter { $0.hasPrefix(".unpack") }
        XCTAssertEqual(leftovers, [])
    }

    func testASecondLaunchKeepsTheInstalledToolsAndDownloadsNothing() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (source, downloader) = try makeSource(in: root)
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        _ = try await installer(source, tools, downloader).installMissingTools()
        let ffmpeg = ToolPaths(directory: tools).ffmpeg
        let marker = Data("#!/bin/sh\necho kept\n".utf8)
        try marker.write(to: ffmpeg)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)

        let offline = StubDownloader()
        _ = try await installer(source, tools, offline).installMissingTools()
        XCTAssertEqual(try Data(contentsOf: ffmpeg), marker)
        XCTAssertEqual(offline.requests, [])
    }

    func testANewerAppReplacesChangedToolsButKeepsANewerEngine() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let first = try makeSource(in: root, versions: ["yt-dlp": "2026.08.19"])
        _ = try await installer(first.source, tools, first.downloader).installMissingTools()
        var installed = InstalledTools.load(from: tools)
        installed.tools["yt-dlp"] = InstalledTool(version: "2026.09.30", sha256: "")
        try installed.save(to: tools)

        let second = try makeSource(in: root, versions: ["yt-dlp": "2026.09.01", "ffmpeg": "2.0"])
        let result = try await installer(second.source, tools, second.downloader).installMissingTools()
        XCTAssertEqual(result.installed.tools["yt-dlp"]?.version, "2026.09.30")
        XCTAssertEqual(result.installed.tools["ffmpeg"]?.version, "2.0")
        XCTAssertEqual(String(decoding: try Data(contentsOf: ToolPaths(directory: tools).ffmpeg), as: UTF8.self), "#!/bin/sh\necho ffmpeg 2.0\n")
        XCTAssertEqual(second.downloader.requests.count, 1)
    }

    func testMissingManifestAndAnIncompleteListAreReported() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        await assertSetupError(.missingFromApp) {
            _ = try await self.installer(nil, tools, StubDownloader()).installMissingTools()
        }
        let (source, downloader) = try makeSource(in: root)
        var manifest = try JSONDecoder().decode(ToolManifest.self, from: Data(contentsOf: source.appendingPathComponent("manifest.json")))
        manifest.tools.removeLast()
        try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("manifest.json"))
        await assertSetupError(.missingFromApp) {
            _ = try await self.installer(source, tools, downloader).installMissingTools()
        }
    }

    func testADownloadThatDoesNotMatchItsChecksumIsNeverUsed() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let (source, downloader) = try makeSource(in: root)
        var manifest = try JSONDecoder().decode(ToolManifest.self, from: Data(contentsOf: source.appendingPathComponent("manifest.json")))
        manifest.tools[1].downloadSHA256 = "0000"
        try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("manifest.json"))
        await assertSetupError(.damaged("ffmpeg")) {
            _ = try await self.installer(source, tools, downloader).installMissingTools()
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: ToolPaths(directory: tools).ffmpeg.path))

        manifest.tools[1].downloadSHA256 = try FileDigest.sha256(of: root.appendingPathComponent("server/ffmpeg-1.0"))
        manifest.tools[1].sha256 = "0000"
        try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("manifest.json"))
        await assertSetupError(.damaged("ffmpeg")) {
            _ = try await self.installer(source, tools, downloader).installMissingTools()
        }
    }

    func testBeingOfflineIsExplained() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let (source, _) = try makeSource(in: root)
        await assertSetupError(.downloadFailed("yt-dlp")) {
            _ = try await self.installer(source, tools, StubDownloader()).installMissingTools()
        }
        XCTAssertTrue(ToolSetupError.downloadFailed("yt-dlp").localizedDescription.contains("internet"))
    }

    private func assertSetupError(_ expected: ToolSetupError, _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ToolSetupError, expected, file: file, line: line)
        }
    }
}
