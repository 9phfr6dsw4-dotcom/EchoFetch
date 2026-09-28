import Foundation
import XCTest
@testable import EchoFetchCore

final class ToolProcessTests: XCTestCase {
    func testDeliversOutputLinesErrorsAndExitCode() async throws {
        let process = ToolProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'one\\ntwo\\r\\ncaf\\303\\251\\nlast'; echo 'bad news' >&2; exit 3"]
        )
        let seen = LineBox()
        let result = try await process.run(collectOutput: true) { seen.add($0) }
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(result.standardOutput, ["one", "two", "café", "last"])
        XCTAssertEqual(seen.lines, ["one", "two", "café", "last"])
        XCTAssertEqual(result.standardError, ["bad news"])
    }

    func testLargeOutputOnBothStreamsDoesNotStall() async throws {
        let process = ToolProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do echo \"out $i\"; echo \"err $i\" >&2; i=$((i+1)); done"]
        )
        let seen = LineBox()
        let result = try await process.run { seen.add($0) }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, [])
        XCTAssertEqual(seen.lines.count, 20_000)
        XCTAssertEqual(seen.lines.last, "out 19999")
        XCTAssertEqual(result.standardError.count, 20_000)
    }

    func testCancelStopsALongRunningTool() async throws {
        let process = ToolProcess(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        let started = Date()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            process.cancel()
        }
        let result = try await process.run()
        XCTAssertTrue(result.wasCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testCancelBeforeStartingNeverRunsTheTool() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("EchoFetchNeverRan-\(UUID().uuidString)")
        let process = ToolProcess(executableURL: URL(fileURLWithPath: "/usr/bin/touch"), arguments: [marker.path])
        process.cancel()
        let result = try await process.run()
        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testAMissingToolThrows() async {
        let process = ToolProcess(executableURL: URL(fileURLWithPath: "/nonexistent/echofetch-tool"), arguments: [])
        do {
            _ = try await process.run()
            XCTFail("expected an error")
        } catch {
            // Expected.
        }
    }
}

final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func add(_ line: String) {
        lock.lock()
        stored.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
