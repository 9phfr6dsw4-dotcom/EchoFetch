import Foundation
import XCTest
@testable import EchoFetchCore

/// Runs the real bundled yt-dlp and ffmpeg against a sample video served on this machine, so the
/// command lines and the progress lines EchoFetch relies on are checked end to end. CI sets
/// ECHOFETCH_TOOLS_DIRECTORY and ECHOFETCH_TEST_MEDIA_URL; elsewhere these tests are skipped.
final class DownloadPipelineTests: XCTestCase {
    private func setting() throws -> (tools: ToolPaths, media: String) {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["ECHOFETCH_TOOLS_DIRECTORY"], !directory.isEmpty,
              let media = environment["ECHOFETCH_TEST_MEDIA_URL"], !media.isEmpty else {
            throw XCTSkip("Set ECHOFETCH_TOOLS_DIRECTORY and ECHOFETCH_TEST_MEDIA_URL to run the real download tests.")
        }
        return (ToolPaths(directory: URL(fileURLWithPath: directory, isDirectory: true)), media)
    }

    private func makeFolders() throws -> (root: URL, destination: URL, partial: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EchoFetchPipeline-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("Downloads", isDirectory: true)
        let partial = root.appendingPathComponent("Partial", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        return (root, destination, partial)
    }

    func testPreviewReadsTheSampleVideo() async throws {
        let (tools, media) = try setting()
        let result = try await ToolProcess(
            executableURL: tools.ytDLP,
            arguments: DownloadCommand.previewArguments(link: media, wholePlaylist: false, tools: tools)
        ).run(collectOutput: true)
        XCTAssertEqual(result.exitCode, 0, result.standardError.joined(separator: "\n"))
        let info = try MediaInfoParser.parse(Data(result.standardOutput.joined(separator: "\n").utf8))
        guard case .single(let item) = info else { return XCTFail("expected a single video") }
        XCTAssertEqual(item.title, "sample")
        XCTAssertFalse(item.isLiveOrUpcoming)
    }

    func testVideoAndBothAudioFormatsDownloadAndReportTheirFiles() async throws {
        let (tools, media) = try setting()
        let cases: [(DownloadKind, AudioFormat, String)] = [(.video, .m4a, "mp4"), (.audio, .m4a, "m4a"), (.audio, .mp3, "mp3")]
        for (kind, audioFormat, fileExtension) in cases {
            let folders = try makeFolders()
            defer { try? FileManager.default.removeItem(at: folders.root) }
            let request = DownloadRequest(link: media, kind: kind, audioFormat: audioFormat, isPlaylist: false, allowsAV1: true)
            let log = DownloadEventLog()
            let events = EventBox()
            let result = try await ToolProcess(
                executableURL: tools.ytDLP,
                arguments: DownloadCommand.downloadArguments(
                    for: request,
                    destination: folders.destination,
                    temporaryDirectory: folders.partial,
                    tools: tools
                )
            ).run { line in
                guard let event = DownloadEventParser.parse(line) else { return }
                log.record(event)
                events.add(event)
            }
            XCTAssertEqual(result.exitCode, 0, "\(fileExtension): " + result.standardError.joined(separator: "\n"))
            XCTAssertEqual(log.files.count, 1, fileExtension)
            let file = try XCTUnwrap(log.files.first)
            XCTAssertEqual((file as NSString).lastPathComponent, "sample.\(fileExtension)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file), file)
            XCTAssertTrue(events.all.contains(.item(index: nil, count: nil, title: "sample")), fileExtension)
            XCTAssertTrue(events.all.contains { event in
                if case .progress(let sample) = event { return sample.status == "downloading" || sample.status == "finished" }
                return false
            }, fileExtension)
        }
    }

    func testAMissingVideoFailsWithAReadableMessage() async throws {
        let (tools, media) = try setting()
        let folders = try makeFolders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let missing = media.replacingOccurrences(of: "sample.mp4", with: "missing.mp4")
        let request = DownloadRequest(link: missing, kind: .video, audioFormat: .m4a, isPlaylist: false, allowsAV1: true)
        let log = DownloadEventLog()
        let result = try await ToolProcess(
            executableURL: tools.ytDLP,
            arguments: DownloadCommand.downloadArguments(for: request, destination: folders.destination, temporaryDirectory: folders.partial, tools: tools)
        ).run { line in
            if let event = DownloadEventParser.parse(line) { log.record(event) }
        }
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(log.files, [])
        XCTAssertEqual(
            DownloadErrorExplainer.explain(errorLines: result.standardError, exitCode: result.exitCode),
            "This video isn't available. It may have been removed, or the link may be wrong.",
            result.standardError.joined(separator: "\n")
        )
    }
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DownloadEvent] = []

    func add(_ event: DownloadEvent) {
        lock.lock()
        stored.append(event)
        lock.unlock()
    }

    var all: [DownloadEvent] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
