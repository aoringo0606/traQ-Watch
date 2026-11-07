import Foundation
import XCTest
@testable import MessageCore

final class FileLinkTests: XCTestCase {
    let server = URL(string: "https://q.trap.jp")!
    let id = "01a159af-bfae-7290-aac2-a25a63323d37"
    var raw: String { "https://q.trap.jp/files/" + id }
    var canonical: String { "https://q.trap.jp/api/v3/files/" + id }

    func testBareAndMarkdownAttachmentLinks() {
        for content in [raw, "before \(raw) after", "[添付](\(raw))", "<\(raw)>", "**\(raw)**"] {
            XCTAssertEqual(MessagePresentation.resources(in: MessageParser.parse(content, server: server), revealed: []), [.file(canonical)], content)
        }
    }

    func testOnlySameOriginValidFileLinksAreFetched() {
        for content in ["https://evil.example/files/\(id)", "http://q.trap.jp/files/\(id)", raw + "extra", raw + "/other", "https://q.trap.jp/files/not-a-uuid", "`\(raw)`", "```\n\(raw)\n```", "$\(raw)$", "!{\"bad\":\"\(raw)\"}"] {
            XCTAssertEqual(MessagePresentation.resources(in: MessageParser.parse(content, server: server), revealed: []), [], content)
        }
        XCTAssertEqual(MessagePresentation.resources(in: MessageParser.parse(raw), revealed: []), [])
    }

    func testHiddenAttachmentsDoNotFetchUntilRevealed() {
        let blocks = MessageParser.parse("!!\(raw)!!", server: server)
        XCTAssertEqual(MessagePresentation.resources(in: blocks, revealed: []), [])
        XCTAssertEqual(MessagePresentation.resources(in: blocks, revealed: [0]), [.file(canonical)])
    }

    func testImageAndOtherFileMetadata() throws {
        let image = try JSONDecoder().decode(TraQFileInfo.self, from: Data(#"{"mime":"image/jpeg","size":9000000,"thumbnails":[{"type":"image"}]}"#.utf8))
        XCTAssertTrue(image.isImage)
        XCTAssertTrue(image.hasImageThumbnail)
        let other = try JSONDecoder().decode(TraQFileInfo.self, from: Data(#"{"mime":"application/pdf","size":100,"thumbnail":null}"#.utf8))
        XCTAssertFalse(other.isImage)
        XCTAssertFalse(other.hasImageThumbnail)
        let legacy = try JSONDecoder().decode(TraQFileInfo.self, from: Data(#"{"mime":"image/png","size":100,"thumbnail":{"width":10}}"#.utf8))
        XCTAssertTrue(legacy.hasImageThumbnail)
    }
}
