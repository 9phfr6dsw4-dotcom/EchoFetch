import Foundation
import XCTest
@testable import EchoFetchCore

final class MediaInfoParserTests: XCTestCase {
    func testReadsASingleVideo() throws {
        let json = """
        {"id": "dQw4w9WgXcQ", "title": "Never Gonna Give You Up", "uploader": "Rick Astley",
         "channel": "Rick Astley Channel", "duration": 213, "extractor_key": "Youtube",
         "thumbnail": "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
         "webpage_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "is_live": false,
         "live_status": "not_live", "_type": "video", "formats": [{"format_id": "18"}]}
        """
        let info = try MediaInfoParser.parse(Data(json.utf8))
        XCTAssertEqual(info, .single(MediaItem(
            id: "dQw4w9WgXcQ",
            title: "Never Gonna Give You Up",
            uploader: "Rick Astley",
            duration: 213,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"),
            webpageURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            siteName: "Youtube",
            isLiveOrUpcoming: false,
            isAvailable: true
        )))
        XCTAssertEqual(info.title, "Never Gonna Give You Up")
    }

    func testMarksLiveAndUpcomingVideosAndFallsBackForMissingFields() throws {
        let live = try MediaInfoParser.parse(Data(#"{"id": "x1", "title": "Live now", "is_live": true, "duration": null}"#.utf8))
        guard case .single(let liveItem) = live else { return XCTFail("expected a single video") }
        XCTAssertTrue(liveItem.isLiveOrUpcoming)
        XCTAssertNil(liveItem.duration)

        let upcoming = try MediaInfoParser.parse(Data(#"{"id": "x2", "title": "Soon", "live_status": "is_upcoming"}"#.utf8))
        guard case .single(let upcomingItem) = upcoming else { return XCTFail("expected a single video") }
        XCTAssertTrue(upcomingItem.isLiveOrUpcoming)

        let bare = try MediaInfoParser.parse(Data(#"{"id": "clip", "duration": 12.5, "thumbnails": [{"url": "https://a/1.jpg", "width": 120}, {"url": "https://a/2.jpg", "width": 1280}, {"url": "https://a/3.jpg", "width": 640}]}"#.utf8))
        guard case .single(let bareItem) = bare else { return XCTFail("expected a single video") }
        XCTAssertEqual(bareItem.title, "clip")
        XCTAssertEqual(bareItem.duration, 12.5)
        XCTAssertEqual(bareItem.thumbnailURL, URL(string: "https://a/2.jpg"))
    }

    func testReadsAFlatPlaylistWithUnavailableEntries() throws {
        let json = """
        {"_type": "playlist", "id": "PL123", "title": "Road Trip Mix", "uploader": "Sam",
         "extractor_key": "YoutubeTab",
         "thumbnails": [{"url": "https://i.ytimg.com/pl/1.jpg"}, {"url": "https://i.ytimg.com/pl/2.jpg"}],
         "entries": [
           {"_type": "url", "ie_key": "Youtube", "id": "a1", "title": "First Song", "duration": 185.0,
            "url": "https://www.youtube.com/watch?v=a1", "channel": "Band",
            "thumbnails": [{"url": "https://i.ytimg.com/vi/a1/hq.jpg", "width": 480, "height": 270}]},
           {"_type": "url", "ie_key": "Youtube", "id": "a2", "title": "[Private video]", "duration": null,
            "url": "https://www.youtube.com/watch?v=a2"},
           {"_type": "url", "ie_key": "Youtube", "id": "a3", "title": "Members Song", "availability": "subscriber_only",
            "url": "https://www.youtube.com/watch?v=a3"}
         ]}
        """
        let info = try MediaInfoParser.parse(Data(json.utf8))
        guard case .playlist(let playlist) = info else { return XCTFail("expected a playlist") }
        XCTAssertEqual(playlist.id, "PL123")
        XCTAssertEqual(playlist.title, "Road Trip Mix")
        XCTAssertEqual(playlist.uploader, "Sam")
        XCTAssertEqual(playlist.thumbnailURL, URL(string: "https://i.ytimg.com/pl/2.jpg"))
        XCTAssertEqual(playlist.entries.map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(playlist.entries.map(\.isAvailable), [true, false, false])
        XCTAssertEqual(playlist.availableCount, 1)
        XCTAssertEqual(playlist.unavailableCount, 2)
        XCTAssertEqual(playlist.entries[0].uploader, "Band")
        XCTAssertEqual(playlist.entries[0].duration, 185)
        XCTAssertEqual(playlist.entries[0].siteName, "Youtube")
        XCTAssertEqual(playlist.entries[0].webpageURL, URL(string: "https://www.youtube.com/watch?v=a1"))
        XCTAssertEqual(playlist.entries[0].thumbnailURL, URL(string: "https://i.ytimg.com/vi/a1/hq.jpg"))
        XCTAssertEqual(info.title, "Road Trip Mix")
    }

    func testAPostWithSeveralClipsIsTreatedAsAPlaylist() throws {
        let json = #"{"_type": "multi_video", "id": "post9", "entries": [{"id": "c1", "title": "Clip one"}, {"id": "c2", "title": "Clip two", "thumbnail": "https://x/2.jpg"}]}"#
        guard case .playlist(let playlist) = try MediaInfoParser.parse(Data(json.utf8)) else {
            return XCTFail("expected a playlist")
        }
        XCTAssertEqual(playlist.title, "post9")
        XCTAssertEqual(playlist.entries.count, 2)
        XCTAssertNil(playlist.thumbnailURL)
        XCTAssertEqual(playlist.displayThumbnailURL, URL(string: "https://x/2.jpg"))
    }

    func testRejectsUnreadableOrEmptyResults() {
        XCTAssertThrowsError(try MediaInfoParser.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? MediaInfoError, .unreadable)
        }
        XCTAssertThrowsError(try MediaInfoParser.parse(Data("[1, 2]".utf8))) { error in
            XCTAssertEqual(error as? MediaInfoError, .unreadable)
        }
        XCTAssertThrowsError(try MediaInfoParser.parse(Data(#"{"_type": "playlist", "id": "p", "entries": []}"#.utf8))) { error in
            XCTAssertEqual(error as? MediaInfoError, .empty)
        }
    }
}
