import Foundation
import XCTest
@testable import MessageCore

final class UnicodeStampTests: XCTestCase {
    func testStandardEmojiAndSequences() {
        XCTAssertEqual(UnicodeStamp.emoji(filename: "1f389.svg"), "🎉")
        XCTAssertEqual(UnicodeStamp.emoji(filename: "2764.svg"), "❤️")
        XCTAssertEqual(UnicodeStamp.emoji(filename: "1f44d-1f3fd.svg"), "👍🏽")
        XCTAssertEqual(UnicodeStamp.emoji(filename: "1f1ef-1f1f5.svg"), "🇯🇵")
        XCTAssertEqual(UnicodeStamp.emoji(filename: "31-fe0f-20e3.svg"), "1️⃣")
        XCTAssertEqual(UnicodeStamp.emoji(filename: "1f469-200d-1f4bb.svg"), "👩‍💻")
    }

    func testMalformedOrNonEmojiFilenamesAreRejected() {
        for filename in ["tada.svg", "1f389.png", "../1f389.svg", "1f389/evil.svg", "000a.svg", "0061.svg", "31.svg", "d800.svg", "110000.svg", "1f389--1f389.svg", "1f389-1f389.svg", String(repeating: "a", count: 300) + ".svg"] {
            XCTAssertNil(UnicodeStamp.emoji(filename: filename), filename)
        }
    }

    func testCatalogDistinguishesUnicodeAndCustomStamps() throws {
        let json = #"[{"id":"one","name":"tada","fileId":"file-one","isUnicode":true},{"id":"two","name":"custom","fileId":"file-two","isUnicode":false}]"#
        let catalog = try JSONDecoder().decode([TraQStamp].self, from: Data(json.utf8))
        XCTAssertTrue(catalog[0].isUnicode)
        XCTAssertFalse(catalog[1].isUnicode)
        XCTAssertEqual(StampReference.parse(":tada.large:")?.pointSize, 32)
        guard case .paragraph(let spans) = MessageParser.parse("おめでとう :tada:").first else { return XCTFail() }
        XCTAssertTrue(spans.contains { if case .stamp(let ref) = $0.attachment { return ref.name == "tada" }; return false })
    }
}
