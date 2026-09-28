import Foundation
import XCTest
@testable import EchoFetchCore

final class LinkPolicyTests: XCTestCase {
    func testAcceptsWebLinksAndTidiesThem() {
        XCTAssertEqual(
            LinkPolicy.link(from: "  https://www.youtube.com/watch?v=dQw4w9WgXcQ \n")?.absoluteString,
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )
        XCTAssertEqual(LinkPolicy.link(from: "<https://youtu.be/abc123>")?.absoluteString, "https://youtu.be/abc123")
        XCTAssertEqual(LinkPolicy.link(from: "\"https://vimeo.com/76979871\"")?.absoluteString, "https://vimeo.com/76979871")
        XCTAssertEqual(LinkPolicy.link(from: "youtube.com/watch?v=abc")?.absoluteString, "https://youtube.com/watch?v=abc")
        XCTAssertEqual(LinkPolicy.link(from: "HTTP://Example.com/video")?.scheme?.lowercased(), "http")
    }

    func testRejectsTextThatIsNotASingleWebLink() {
        XCTAssertNil(LinkPolicy.link(from: ""))
        XCTAssertNil(LinkPolicy.link(from: "   "))
        XCTAssertNil(LinkPolicy.link(from: "e.g."))
        XCTAssertNil(LinkPolicy.link(from: "hello world"))
        XCTAssertNil(LinkPolicy.link(from: "look at https://youtu.be/abc please"))
        XCTAssertNil(LinkPolicy.link(from: "ftp://example.com/file"))
        XCTAssertNil(LinkPolicy.link(from: "file:///Users/me/video.mp4"))
        XCTAssertNil(LinkPolicy.link(from: "https://localhost/video"))
        XCTAssertNil(LinkPolicy.link(from: "youtube.com"))
        XCTAssertNil(LinkPolicy.link(from: "youtube.com/"))
        XCTAssertNil(LinkPolicy.link(from: "https://example.c0m/video"))
    }

    func testRecognizesYouTubeHosts() throws {
        for text in ["https://www.youtube.com/watch?v=a", "https://youtu.be/a", "https://music.youtube.com/watch?v=a", "https://m.youtube.com/shorts/a"] {
            XCTAssertTrue(LinkPolicy.isYouTube(try XCTUnwrap(URL(string: text))), text)
        }
        XCTAssertFalse(LinkPolicy.isYouTube(try XCTUnwrap(URL(string: "https://vimeo.com/1"))))
        XCTAssertFalse(LinkPolicy.isYouTube(try XCTUnwrap(URL(string: "https://notyoutube.com/watch?v=a"))))
    }

    func testOffersTheWholePlaylistOnlyForRealPlaylistsOpenedFromAVideo() throws {
        func offer(_ text: String) throws -> String? {
            LinkPolicy.playlistOffer(for: try XCTUnwrap(URL(string: text)))
        }
        XCTAssertEqual(try offer("https://www.youtube.com/watch?v=abc&list=PLx1y2z3&index=4"), "PLx1y2z3")
        XCTAssertEqual(try offer("https://youtu.be/abc?list=OLAK5uy_abc"), "OLAK5uy_abc")
        XCTAssertNil(try offer("https://www.youtube.com/playlist?list=PLx1y2z3"))
        XCTAssertNil(try offer("https://www.youtube.com/watch?v=abc"))
        XCTAssertNil(try offer("https://www.youtube.com/watch?v=abc&list=RDabc&start_radio=1"))
        XCTAssertNil(try offer("https://www.youtube.com/watch?v=abc&list=WL"))
        XCTAssertNil(try offer("https://www.youtube.com/watch?v=abc&list=LL"))
        XCTAssertNil(try offer("https://www.youtube.com/watch?v=abc&list="))
        XCTAssertNil(try offer("https://vimeo.com/1?list=PLx"))
    }
}
