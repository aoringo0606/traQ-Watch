import Foundation
import XCTest
@testable import MessageCore

final class MessageQuoteTests: XCTestCase {
    let server = URL(string: "https://q.trap.jp")!
    let id = "01a170b1-8dd2-7baf-bccd-9d3e0d659e79"
    var url: String { "https://q.trap.jp/messages/" + id }

    func message(id: String = "01a159af-bfae-7290-aac2-a25a63323d37", content: String) -> ActivityMessage {
        ActivityMessage(id: id, userId: "user", channelId: "channel", content: content, createdAt: Date(), updatedAt: Date())
    }

    func plan(_ source: String) -> [MessageQuoteReference] {
        let parent = message(content: source)
        return MessageQuoteLinks.plan(messages: [parent], parsed: [parent.id: MessageParser.parse(source, server: server)])[parent.id] ?? []
    }

    func testBareMarkdownAndAutolinkQuotesDeduplicate() {
        for source in [url, "before \(url) after", "[引用](\(url))", "<\(url)>", "**\(url)**", url + "\n" + url] {
            XCTAssertEqual(plan(source).map(\.id), [id], source)
        }
    }

    func testUnsafeCodeSpoilerAndMalformedURLsDoNotFetch() {
        for source in ["https://evil.example/messages/\(id)", "http://q.trap.jp/messages/\(id)", "https://user@q.trap.jp/messages/\(id)", url + "/other", url + "extra", url + "?x=1", "`\(url)`", "```\n\(url)\n```", "!!\(url)!!", "$\(url)$", "!{\"bad\":\"\(url)\"}"] {
            XCTAssertTrue(plan(source).isEmpty, source)
        }
        XCTAssertTrue(plan("https://q.trap.jp/messages/01a159af-bfae-7290-aac2-a25a63323d37").isEmpty)
    }

    func testExpandedQuoteHidesOnlyItsLinkAndFailureKeepsIt() {
        let plain = MessageParser.parse("plain  \n\n", server: server)
        XCTAssertEqual(MessageQuoteLinks.body(plain, expanded: []), plain)
        let blocks = MessageParser.parse("before\n\(url)", server: server)
        XCTAssertEqual(MessageQuoteLinks.body(blocks, expanded: []), blocks)
        guard case .paragraph(let spans) = MessageQuoteLinks.body(blocks, expanded: [id]).first else { return XCTFail() }
        XCTAssertEqual(spans.map(\.text).joined(), "before")
    }

    func testExcerptKeepsStampsButNotImagesOrSpoilerSecrets() {
        let source = "hello :tada: :custom.large: !!secret!! ![alt](https://example.com/a.png) \(url)"
        let excerpt = MessageQuotePreview(message: message(content: source), server: server).excerpt
        let text = excerpt.map(\.text).joined()
        XCTAssertFalse(text.contains("secret"))
        XCTAssertTrue(text.contains("［画像］"))
        XCTAssertTrue(text.contains("［引用メッセージ］"))
        XCTAssertEqual(MessagePresentation.resources(in: [.paragraph(excerpt)], revealed: []), [.stamp("tada"), .stamp("custom")])
        let long = MessageQuotePreview(message: message(content: String(repeating: "a", count: 10_000)), server: server)
        XCTAssertLessThanOrEqual(long.excerpt.map(\.text).joined().count, 401)
    }

    func testSingleMessageResponseDates() throws {
        let data = Data(#"{"id":"a","userId":"u","channelId":"c","content":"quote","createdAt":"2026-11-07T00:00:00.123456Z","updatedAt":"2026-11-07T00:00:00Z","stamps":[]}"#.utf8)
        XCTAssertEqual(try TraQAPI.message(from: data).content, "quote")
        XCTAssertThrowsError(try TraQAPI.message(from: Data("{}".utf8)))
    }

    func testQuoteCountLimits() {
        let source = (0..<20).map { _ in "https://q.trap.jp/messages/" + UUID().uuidString.lowercased() }.joined(separator: "\n")
        XCTAssertEqual(plan(source).count, 3)
        let parents = (0..<20).map { _ in message(id: UUID().uuidString.lowercased(), content: "https://q.trap.jp/messages/" + UUID().uuidString.lowercased()) }
        let parsed = Dictionary(uniqueKeysWithValues: parents.map { ($0.id, MessageParser.parse($0.content, server: server)) })
        let all = MessageQuoteLinks.plan(messages: parents, parsed: parsed).values.flatMap { $0 }
        XCTAssertEqual(Set(all.map(\.id)).count, 12)
    }
}

private actor QuoteFetchProbe {
    var ids: [String] = []
    var active = 0
    var maximumActive = 0
    func fetch(_ id: String) async throws -> ActivityMessage {
        ids.append(id)
        active += 1
        maximumActive = max(active, maximumActive)
        defer { active -= 1 }
        await Task.yield()
        if id.hasSuffix("0") { throw URLError(.userAuthenticationRequired) }
        return ActivityMessage(id: id, userId: "u", channelId: "c", content: "quote", createdAt: Date(), updatedAt: Date())
    }
}

extension MessageQuoteTests {
    func testLoaderDeduplicatesLimitsConcurrencyAndKeepsFailureSeparate() async {
        let ids = (1...6).map { String(format: "00000000-0000-0000-0000-%012d", $0) }
        let denied = "00000000-0000-0000-0000-000000000000"
        let refs = (ids + ids + [denied]).map { MessageQuoteReference(id: $0, url: "https://q.trap.jp/messages/" + $0, label: "quote") }
        let existing = message(id: ids[0], content: "already in timeline")
        let probe = QuoteFetchProbe()
        let result = await MessageQuoteLoader.load(references: refs, timeline: [existing], server: server) { try await probe.fetch($0) }
        XCTAssertEqual(result.count, 7)
        guard case .loaded(let cached) = result[ids[0]] else { return XCTFail() }
        XCTAssertEqual(cached.message.content, "already in timeline")
        guard case .failed = result[denied] else { return XCTFail() }
        let fetched = await probe.ids
        XCTAssertEqual(fetched.count, 6)
        XCTAssertEqual(Set(fetched).count, 6)
        let concurrency = await probe.maximumActive
        XCTAssertLessThanOrEqual(concurrency, 3)
    }
}

extension MessageQuoteTests {
    func testLoaderDoesNotFetchNestedQuotes() async {
        let ref = MessageQuoteReference(id: id, url: url, label: "引用")
        let probe = QuoteFetchProbe()
        let server = server
        let result = await MessageQuoteLoader.load(references: [ref], timeline: [], server: server) { id in
            let fetched = try await probe.fetch(id)
            return ActivityMessage(id: fetched.id, userId: fetched.userId, channelId: fetched.channelId,
                                   content: "https://q.trap.jp/messages/00000000-0000-0000-0000-000000000001",
                                   createdAt: fetched.createdAt, updatedAt: fetched.updatedAt)
        }
        guard case .loaded(let preview) = result[id] else { return XCTFail() }
        XCTAssertEqual(preview.excerpt.map(\.text).joined(), "［引用メッセージ］")
        let ids = await probe.ids
        XCTAssertEqual(ids.count, 1)
    }

    func testWrongResponseIDIsNotDisplayed() async {
        let ref = MessageQuoteReference(id: id, url: url, label: "引用")
        let wrong = message(id: "00000000-0000-0000-0000-000000000001", content: "wrong")
        let result = await MessageQuoteLoader.load(references: [ref], timeline: [], server: server) { _ in wrong }
        guard case .failed = result[id] else { return XCTFail("Mismatched response must not be shown") }
    }
}
