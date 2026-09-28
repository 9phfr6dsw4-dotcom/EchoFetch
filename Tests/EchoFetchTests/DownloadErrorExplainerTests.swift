import Foundation
import XCTest
@testable import EchoFetchCore

final class DownloadErrorExplainerTests: XCTestCase {
    private func explain(_ lines: [String], code: Int32 = 1) -> String {
        DownloadErrorExplainer.explain(errorLines: lines, exitCode: code)
    }

    func testCommonProblemsGetPlainSentences() {
        XCTAssertEqual(
            explain(["ERROR: [youtube] abc: Sign in to confirm you’re not a bot. Use --cookies-from-browser or --cookies for the authentication."]),
            "YouTube wants to check that you're not a bot. Wait a few minutes and try again. If it keeps happening, check for an engine update in Settings."
        )
        XCTAssertEqual(
            explain(["ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users."]),
            "This video is age-restricted. Downloading it needs a signed-in browser, which EchoFetch doesn't support yet."
        )
        XCTAssertEqual(explain(["ERROR: [youtube] abc: Private video. Sign in if you've been granted access to this video"]), "This video is private.")
        XCTAssertEqual(
            explain(["ERROR: [youtube] abc: Join this channel to get access to members-only content like this video, and other exclusive perks."]),
            "This video is only for the channel's members."
        )
        XCTAssertEqual(
            explain(["ERROR: [youtube] abc: Video unavailable. This video has been removed by the uploader"]),
            "This video isn't available. It may have been removed, or the link may be wrong."
        )
        XCTAssertEqual(explain(["ERROR: Unsupported URL: https://example.com/page"]), "EchoFetch can't download from this link.")
        XCTAssertEqual(
            explain(["ERROR: [generic] Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided, or not known> (caused by TransportError)"]),
            "EchoFetch couldn't connect. Check your internet connection and try again."
        )
        XCTAssertEqual(
            explain(["ERROR: [generic] Unable to download webpage: HTTP Error 404: Not Found (caused by <HTTPError 404: Not Found>)"]),
            "This video isn't available. It may have been removed, or the link may be wrong."
        )
        XCTAssertEqual(
            explain(["ERROR: [youtube] abc: Requested format is not available. Use --list-formats for a list of available formats"]),
            "This video doesn't offer a format EchoFetch can save. Try Download Audio, or check for an engine update in Settings."
        )
        XCTAssertEqual(
            explain(["ERROR: unable to open for writing: [Errno 28] No space left on device"]),
            "Your Mac is out of disk space. Free up some space and try again."
        )
        XCTAssertEqual(
            explain(["ERROR: [youtube] abc: This live event will begin in 3 hours."]),
            "This video hasn't started yet. Try again once it has finished streaming."
        )
    }

    func testOtherErrorsShowTheirOwnMessageWithoutThePrefixes() {
        XCTAssertEqual(
            explain(["WARNING: minor", "ERROR: [vimeo] 12345: Something odd happened"]),
            "Something odd happened"
        )
        XCTAssertEqual(explain(["ERROR: postprocessing: Conversion failed!"]), "Postprocessing: Conversion failed!")
        XCTAssertEqual(explain(["Traceback (most recent call last):", "RuntimeError: boom"]), "RuntimeError: boom")
        XCTAssertEqual(explain([], code: 2), "The download stopped unexpectedly (code 2).")
        XCTAssertEqual(explain(["WARNING: only a warning"], code: 1), "The download stopped unexpectedly (code 1).")
    }

    func testUpdateFailures() {
        XCTAssertEqual(
            DownloadErrorExplainer.explainUpdateFailure(errorLines: ["ERROR: Unable to write to /x/yt-dlp; try running as administrator"]),
            "EchoFetch couldn't replace the download engine. Try again, or reinstall EchoFetch."
        )
        XCTAssertEqual(
            DownloadErrorExplainer.explainUpdateFailure(errorLines: ["ERROR: Unable to obtain version info (<urlopen error timed out>)"]),
            "EchoFetch couldn't check for a new download engine. It will try again the next time it opens."
        )
    }
}
