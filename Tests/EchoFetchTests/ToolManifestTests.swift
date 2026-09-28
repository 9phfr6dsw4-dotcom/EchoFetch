import Foundation
import XCTest
@testable import EchoFetchCore

final class ToolManifestTests: XCTestCase {
    private let bundled = [
        ToolManifestEntry(name: "yt-dlp", version: "2026.08.19", sha256: "y1"),
        ToolManifestEntry(name: "ffmpeg", version: "6.1.1", sha256: "f1"),
        ToolManifestEntry(name: "ffprobe", version: "6.1.1", sha256: "p1"),
        ToolManifestEntry(name: "deno", version: "2.9.7", sha256: "d1")
    ]
    private let all: Set<String> = ["yt-dlp", "ffmpeg", "ffprobe", "deno"]

    func testFirstLaunchInstallsEverything() {
        XCTAssertEqual(
            ToolInstallPlan.toolsToInstall(bundled: bundled, installed: InstalledTools(), existingExecutables: []),
            ["yt-dlp", "ffmpeg", "ffprobe", "deno"]
        )
    }

    func testNothingIsReinstalledWhenUpToDate() {
        let installed = InstalledTools(tools: [
            "yt-dlp": InstalledTool(version: "2026.08.19", sha256: "y1"),
            "ffmpeg": InstalledTool(version: "6.1.1", sha256: "f1"),
            "ffprobe": InstalledTool(version: "6.1.1", sha256: "p1"),
            "deno": InstalledTool(version: "2.9.7", sha256: "d1")
        ])
        XCTAssertEqual(ToolInstallPlan.toolsToInstall(bundled: bundled, installed: installed, existingExecutables: all), [])
    }

    func testASelfUpdatedEngineIsKeptButOtherToolsFollowTheApp() {
        let installed = InstalledTools(tools: [
            "yt-dlp": InstalledTool(version: "2026.09.25", sha256: ""),
            "ffmpeg": InstalledTool(version: "6.1.0", sha256: "old"),
            "ffprobe": InstalledTool(version: "6.1.1", sha256: "p1"),
            "deno": InstalledTool(version: "2.9.7", sha256: "d1")
        ])
        XCTAssertEqual(ToolInstallPlan.toolsToInstall(bundled: bundled, installed: installed, existingExecutables: all), ["ffmpeg"])
    }

    func testAnOlderEngineOrAMissingFileIsReplaced() {
        let installed = InstalledTools(tools: [
            "yt-dlp": InstalledTool(version: "2026.07.04", sha256: ""),
            "ffmpeg": InstalledTool(version: "6.1.1", sha256: "f1"),
            "ffprobe": InstalledTool(version: "6.1.1", sha256: "p1"),
            "deno": InstalledTool(version: "2.9.7", sha256: "d1")
        ])
        XCTAssertEqual(
            ToolInstallPlan.toolsToInstall(bundled: bundled, installed: installed, existingExecutables: ["yt-dlp", "ffmpeg", "ffprobe"]),
            ["yt-dlp", "deno"]
        )
    }

    func testEngineVersionsCompareAsDates() {
        XCTAssertTrue(EngineVersion.isNewer("2026.09.01", than: "2026.08.19"))
        XCTAssertTrue(EngineVersion.isNewer("2026.08.19.123456", than: "2026.08.19"))
        XCTAssertTrue(EngineVersion.isNewer("2026.10.01", than: "2026.9.30"))
        XCTAssertFalse(EngineVersion.isNewer("2026.08.19", than: "2026.08.19"))
        XCTAssertFalse(EngineVersion.isNewer("2025.12.31", than: "2026.01.01"))
        XCTAssertFalse(EngineVersion.isNewer("stable@2026.08.19", than: "2026.08.19"))
    }

    func testEngineChecksHappenAtMostOnceADay() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        XCTAssertTrue(EngineUpdatePolicy.isCheckDue(lastCheck: nil, now: now))
        XCTAssertFalse(EngineUpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(EngineUpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-86_400), now: now))
        XCTAssertTrue(EngineUpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(3_600), now: now))
    }

    func testInstalledToolsRoundTripAndMissingFileIsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EchoFetchInstalledTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(InstalledTools.load(from: root), InstalledTools())
        let installed = InstalledTools(tools: ["deno": InstalledTool(version: "2.9.7", sha256: "d1")])
        try installed.save(to: root)
        XCTAssertEqual(InstalledTools.load(from: root), installed)
    }

    func testManifestDecodesThePackagedFormat() throws {
        let json = #"{"tools":[{"name":"yt-dlp","version":"2026.08.19","sha256":"abc"},{"name":"deno","version":"2.9.7","sha256":"def"}]}"#
        let manifest = try JSONDecoder().decode(ToolManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.tools, [
            ToolManifestEntry(name: "yt-dlp", version: "2026.08.19", sha256: "abc"),
            ToolManifestEntry(name: "deno", version: "2.9.7", sha256: "def")
        ])
    }

    func testFileDigestMatchesKnownSHA256() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("EchoFetchDigest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try FileDigest.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data().write(to: file)
        XCTAssertEqual(try FileDigest.sha256(of: file), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testDisplayFormats() {
        XCTAssertEqual(DisplayFormat.duration(42), "0:42")
        XCTAssertEqual(DisplayFormat.duration(245), "4:05")
        XCTAssertEqual(DisplayFormat.duration(3_723), "1:02:03")
        XCTAssertEqual(DisplayFormat.duration(-5), "0:00")
        XCTAssertEqual(DisplayFormat.timeLeft(65), "1:05 left")
        XCTAssertEqual(DisplayFormat.percent(0.4299), "42%")
        XCTAssertEqual(DisplayFormat.percent(1.2), "100%")
        XCTAssertEqual(DisplayFormat.progressLine(fraction: nil, speed: nil, eta: nil), "")
        XCTAssertEqual(DisplayFormat.progressLine(fraction: 0.5, speed: 0, eta: 65), "50% · 1:05 left")
        XCTAssertTrue(DisplayFormat.speed(4_200_000).hasSuffix("/s"))
    }
}
