import Foundation
import XCTest
@testable import EchoFetchCore

final class DownloadHistoryStoreTests: XCTestCase {
    private func record(_ title: String, secondsAgo: TimeInterval, now: Date) -> DownloadRecord {
        DownloadRecord(
            title: title,
            uploader: "Someone",
            sourceURL: "https://youtu.be/\(title)",
            thumbnailURL: nil,
            kind: .video,
            fileExtension: "mp4",
            path: "/Users/me/Downloads/\(title).mp4",
            isFolder: false,
            itemCount: 1,
            byteCount: 1_000,
            createdAt: now.addingTimeInterval(-secondsAgo)
        )
    }

    func testSavesAndLoadsNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EchoFetchHistoryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadHistoryStore(directory: root)
        XCTAssertEqual(store.load(), [])

        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let older = record("older", secondsAgo: 600, now: now)
        let newer = record("newer", secondsAgo: 60, now: now)
        var records = DownloadHistoryStore.adding(older, to: [])
        records = DownloadHistoryStore.adding(newer, to: records)
        XCTAssertEqual(records.map(\.title), ["newer", "older"])
        try store.save(records)
        XCTAssertEqual(store.load(), [newer, older])

        let other = root.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: other)
        try store.save([])
        XCTAssertEqual(store.load(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    func testKeepsOnlyTheNewestFiveHundred() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var records: [DownloadRecord] = []
        for index in 0..<505 {
            records = DownloadHistoryStore.adding(record("r\(index)", secondsAgo: TimeInterval(1_000 - index), now: now), to: records)
        }
        XCTAssertEqual(records.count, DownloadHistoryStore.maximumRecords)
        XCTAssertEqual(records.first?.title, "r504")
        XCTAssertEqual(records.last?.title, "r5")
    }

    func testAddingTheSameRecordAgainReplacesIt() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var first = record("one", secondsAgo: 10, now: now)
        var records = DownloadHistoryStore.adding(first, to: [])
        first.title = "renamed"
        records = DownloadHistoryStore.adding(first, to: records)
        XCTAssertEqual(records.map(\.title), ["renamed"])
    }

    func testUnreadableHistoryStartsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EchoFetchHistoryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: root.appendingPathComponent(DownloadHistoryStore.fileName))
        XCTAssertEqual(DownloadHistoryStore(directory: root).load(), [])
    }

    func testStandardLocationsLiveInEchoFetchFolders() {
        XCTAssertEqual(AppSupportDirectory.url.lastPathComponent, "EchoFetch")
        XCTAssertEqual(AppSupportDirectory.tools.lastPathComponent, "Tools")
        XCTAssertEqual(AppSupportDirectory.tools.deletingLastPathComponent().lastPathComponent, "EchoFetch")
        XCTAssertTrue(AppSupportDirectory.partialDownloads.path.hasSuffix("Caches/EchoFetch/Partial"))
        XCTAssertEqual(DownloadHistoryStore.standard().fileURL.lastPathComponent, "history.json")
    }
}
