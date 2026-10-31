import XCTest
@testable import NagareKit

final class NagareKitTests: XCTestCase {
    func testDecodesFeedsAndEntries() throws {
        let feeds = try APIClient.decoder.decode([Feed].self, from: Data("""
        [{"id":1,"kind":"web","url":"https://example.com/news","title":"","site_url":null,"folder":"見張り",
          "added_by":"grokbot","reason":"r","selector":"#status","credential":null,"notify":1,"last_error":null,"unread":3}]
        """.utf8))
        XCTAssertEqual(feeds.first?.kind, .web)
        XCTAssertEqual(feeds.first?.addedBy, "grokbot")
        XCTAssertEqual(feeds.first?.displayTitle, "https://example.com/news")

        var entries = try APIClient.decoder.decode([Entry].self, from: Data("""
        [{"id":7,"feed_id":1,"feed_title":"F","url":null,"title":"T","author":null,"published_at":1793332858894,"read":0,"starred":1}]
        """.utf8))
        XCTAssertNil(entries[0].content)
        XCTAssertTrue(entries[0].isStarred)
        entries[0].isRead = true
        XCTAssertEqual(entries[0].read, 1)
    }

    func testEntryQuery() {
        var q = EntryQuery(selection: .folder("Tech"), unreadOnly: true)
        q.before = 10
        q.beforeId = 3
        let items = Dictionary(uniqueKeysWithValues: q.queryItems.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items, ["limit": "50", "folder": "Tech", "unread": "1", "before": "10", "before_id": "3"])
        XCTAssertEqual(EntryQuery(selection: .starred, unreadOnly: true).queryItems.map(\.name), ["limit", "starred"])
    }

    func testRequestCarriesTokenAndPath() {
        let client = APIClient(baseURL: URL(string: "https://nagare.trkw.dev")!, token: "ngr_x")
        let request = client.makeRequest("/entries/5/translate", method: "POST", query: [URLQueryItem(name: "lang", value: "ja")])
        XCTAssertEqual(request.url?.absoluteString, "https://nagare.trkw.dev/api/entries/5/translate?lang=ja")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ngr_x")
    }

    func testPlainText() {
        XCTAssertEqual(HTMLText.plain("<p>こんにちは&nbsp;<b>世界</b></p><script>x()</script><p>次</p>"), "こんにちは 世界\n次")
    }
}

final class PushTokenTests: XCTestCase {
    func testHex() {
        XCTAssertEqual(PushToken.hex(Data([0x00, 0xab, 0x10, 0xff])), "00ab10ff")
    }
}
