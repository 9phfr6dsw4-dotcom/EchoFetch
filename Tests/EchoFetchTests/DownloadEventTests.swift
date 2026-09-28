import Foundation
import XCTest
@testable import EchoFetchCore

final class DownloadEventTests: XCTestCase {
    func testParsesProgressLines() {
        XCTAssertEqual(
            DownloadEventParser.parse("ECHOFETCH_PROGRESS downloading|1048576|4194304|NA|524288.5|6|avc1.640028"),
            .progress(ProgressSample(status: "downloading", downloadedBytes: 1_048_576, totalBytes: 4_194_304, speed: 524_288.5, eta: 6, isAudioOnly: false))
        )
        guard case .progress(let estimated) = DownloadEventParser.parse("ECHOFETCH_PROGRESS downloading|500|NA|2000.0|NA|NA|none") else {
            return XCTFail("expected progress")
        }
        XCTAssertEqual(estimated.totalBytes, 2000)
        XCTAssertEqual(estimated.fraction, 0.25)
        XCTAssertNil(estimated.speed)
        XCTAssertNil(estimated.eta)
        XCTAssertTrue(estimated.isAudioOnly)

        guard case .progress(let unknown) = DownloadEventParser.parse("ECHOFETCH_PROGRESS downloading|500|NA|NA|NA|NA|NA") else {
            return XCTFail("expected progress")
        }
        XCTAssertNil(unknown.fraction)
        XCTAssertFalse(unknown.isAudioOnly)
        XCTAssertNil(DownloadEventParser.parse("ECHOFETCH_PROGRESS downloading|1|2"))
    }

    func testParsesItemAndFileLines() {
        XCTAssertEqual(
            DownloadEventParser.parse("ECHOFETCH_ITEM 3|12|Song | Live at the Hall"),
            .item(index: 3, count: 12, title: "Song | Live at the Hall")
        )
        XCTAssertEqual(DownloadEventParser.parse("ECHOFETCH_ITEM NA|NA|One video"), .item(index: nil, count: nil, title: "One video"))
        XCTAssertEqual(DownloadEventParser.parse("ECHOFETCH_ITEM NA|NA|NA"), .item(index: nil, count: nil, title: ""))
        XCTAssertEqual(
            DownloadEventParser.parse("ECHOFETCH_FILE /Users/me/Downloads/My Video.mp4"),
            .file("/Users/me/Downloads/My Video.mp4")
        )
        XCTAssertNil(DownloadEventParser.parse("ECHOFETCH_FILE NA"))
        XCTAssertNil(DownloadEventParser.parse("[download] Destination: x.mp4"))
        XCTAssertNil(DownloadEventParser.parse(""))
    }

    func testProgressStateFollowsAVideoThenItsAudioThenTheMerge() {
        var state = DownloadProgressState()
        XCTAssertEqual(state.phase, .starting)
        state.apply(.item(index: nil, count: nil, title: "Clip"))
        XCTAssertEqual(state.itemTitle, "Clip")
        state.apply(.progress(ProgressSample(status: "downloading", downloadedBytes: 50, totalBytes: 100, speed: 10, eta: 5, isAudioOnly: false)))
        XCTAssertEqual(state.phase, .downloading)
        XCTAssertEqual(state.fraction, 0.5)
        XCTAssertFalse(state.isAudioPart)
        state.apply(.progress(ProgressSample(status: "finished", downloadedBytes: 100, totalBytes: 100, speed: nil, eta: nil, isAudioOnly: false)))
        XCTAssertEqual(state.phase, .finishing)
        state.apply(.progress(ProgressSample(status: "downloading", downloadedBytes: 1, totalBytes: 4, speed: 2, eta: 1, isAudioOnly: true)))
        XCTAssertEqual(state.phase, .downloading)
        XCTAssertTrue(state.isAudioPart)
        XCTAssertEqual(state.fraction, 0.25)
        state.apply(.file("/tmp/Clip.mp4"))
        state.apply(.file("/tmp/Clip.mp4"))
        XCTAssertEqual(state.phase, .finishing)
        XCTAssertEqual(state.savedFiles, ["/tmp/Clip.mp4"])
        XCTAssertNil(state.speed)
        XCTAssertNil(state.playlistFraction)
    }

    func testPlaylistFractionCountsFinishedVideos() {
        var state = DownloadProgressState()
        state.apply(.item(index: 3, count: 4, title: "Third"))
        XCTAssertEqual(state.playlistFraction, 0.5)
        state.apply(.progress(ProgressSample(status: "downloading", downloadedBytes: 1, totalBytes: 2, speed: nil, eta: nil, isAudioOnly: false)))
        XCTAssertEqual(state.playlistFraction, 0.625)
        state.apply(.file("/tmp/p/003 - Third.mp4"))
        XCTAssertEqual(state.playlistFraction, 0.75)
        state.apply(.item(index: 4, count: nil, title: "Fourth"))
        XCTAssertEqual(state.itemCount, 4)
        XCTAssertEqual(state.playlistFraction, 0.75)
        XCTAssertNil(state.fraction)
    }

    func testEventLogKeepsEachFileOnce() {
        let log = DownloadEventLog()
        log.record(.file("/a.mp4"))
        log.record(.progress(ProgressSample(status: "finished", downloadedBytes: nil, totalBytes: nil, speed: nil, eta: nil, isAudioOnly: false)))
        log.record(.file("/b.mp4"))
        log.record(.file("/a.mp4"))
        XCTAssertEqual(log.files, ["/a.mp4", "/b.mp4"])
    }

    func testOutcomePointsAtTheFileOrThePlaylistFolder() {
        XCTAssertNil(DownloadOutcome.savedLocation(files: [], isPlaylist: false))
        let single = DownloadOutcome.savedLocation(files: ["/Users/me/Downloads/A.mp4"], isPlaylist: false)
        XCTAssertEqual(single?.path, "/Users/me/Downloads/A.mp4")
        XCTAssertEqual(single?.isFolder, false)
        let playlist = DownloadOutcome.savedLocation(files: ["/Users/me/Downloads/Mix/001 - A.m4a", "/Users/me/Downloads/Mix/002 - B.m4a"], isPlaylist: true)
        XCTAssertEqual(playlist?.path, "/Users/me/Downloads/Mix")
        XCTAssertEqual(playlist?.isFolder, true)
        XCTAssertEqual(DownloadOutcome.failedItemCount(in: [
            "WARNING: something minor",
            "ERROR: [youtube] a2: Private video. Sign in if you've been granted access to this video",
            "ERROR: [youtube] a3: Video unavailable"
        ]), 2)
    }
}
