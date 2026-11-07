import Foundation
import XCTest
@testable import MessageCore

final class TraQAPITests: XCTestCase {
    func testHTTPSOnlyServerAndCredentialsBody() throws {
        for invalid in ["http://q.trap.jp", "https://user:pass@q.trap.jp", "https://q.trap.jp/path", "https://q.trap.jp?x=1", "https://q.trap.jp#secret", "garbage"] {
            XCTAssertNil(TraQAPI.serverURL(invalid))
        }
        XCTAssertNotNil(TraQAPI.serverURL("https://q.trap.jp/"))
        let body = try TraQAPI.loginBody(name: "user", password: "test-only-password")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["name": "user", "password": "test-only-password"])
        let session = SavedSession(server: "https://q.trap.jp", token: "test-only-token")
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: String]
        XCTAssertEqual(Set(saved.keys), Set(["server", "token"]))
    }

    func testActivitiesFractionalDatesOrderingAndLimit() throws {
        let rows: [[String: String]] = (0..<25).map { index in
            ["id": "message-\(index)", "userId": "user", "channelId": "channel", "content": "raw **text**", "createdAt": String(format: "2026-11-07T00:00:%02d.123456Z", index), "updatedAt": "2026-11-07T00:00:00Z"]
        }
        let result = try TraQAPI.activities(from: JSONSerialization.data(withJSONObject: rows))
        XCTAssertEqual(result.count, 20)
        XCTAssertEqual(result.first?.id, "message-24")
        XCTAssertEqual(result.last?.id, "message-5")
        XCTAssertEqual(result.first?.content, "raw **text**")
        XCTAssertThrowsError(try TraQAPI.activities(from: Data("[{\"createdAt\":\"bad\"}]".utf8)))
    }

    func testChannelPathAndDisplayNameContract() throws {
        XCTAssertEqual(try TraQAPI.channelPath(from: Data(#"{"path":"times/26/aorinngo"}"#.utf8)), "#times/26/aorinngo")
        let user = try JSONDecoder().decode(TraQUser.self, from: Data(#"{"id":"user","name":"login","displayName":"表示名"}"#.utf8))
        XCTAssertEqual(user.displayName, "表示名")
    }
}
