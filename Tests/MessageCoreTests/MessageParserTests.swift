import XCTest
@testable import MessageCore

final class MessageParserTests: XCTestCase {
    func spans(_ source: String) -> [MessageSpan] {
        guard case .paragraph(let spans) = MessageParser.parse(source).first else { return [] }
        return spans
    }

    func testPlainAndMultiline() {
        for source in ["", "普通の本文", "一行目\n二行目\n\n段落", "  space  "] {
            XCTAssertEqual(spans(source).map(\.text).joined(), source)
        }
    }

    func testNestedFormattingAndCode() {
        let result = spans("**bold *nested*** ~~strike~~ `**raw**`")
        XCTAssertTrue(result.contains { $0.text == "nested" && $0.style.isSuperset(of: [.bold, .italic]) })
        XCTAssertTrue(result.contains { $0.text == "strike" && $0.style.contains(.strike) })
        XCTAssertTrue(result.contains { $0.text == "**raw**" && $0.style == .code })
    }

    func testLinkBecomesNonInteractiveStyle() {
        XCTAssertEqual(spans("[link](https://example.com)"), [MessageSpan(text: "link", style: [.bold, .reference])])
    }

    func testLongInputHasBoundedFallback() {
        let result = spans(String(repeating: "a", count: 100_000))
        XCTAssertLessThan(result.map(\.text).joined().count, 33_000)
        XCTAssertTrue(result[0].style.isEmpty)
    }
}

extension MessageParserTests {
    func testInlineSpoilerAndSurroundingStyle() {
        let result = spans("before **!!*secret*!!** after")
        guard let spoiler = result.first(where: { $0.attachment != nil }),
              case .spoiler(let id, let children) = spoiler.attachment else { return XCTFail("Missing spoiler") }
        XCTAssertEqual(id, 0)
        XCTAssertTrue(spoiler.style.contains(.bold))
        XCTAssertEqual(children, [MessageSpan(text: "secret", style: .italic)])
        XCTAssertEqual(result.first?.text, "before ")
        XCTAssertEqual(result.last?.text, " after")
        var state = SpoilerState()
        state.toggle(id)
        XCTAssertTrue(state.revealed.contains(id))
        state.toggle(id)
        XCTAssertFalse(state.revealed.contains(id))
    }

    func testCodeFencePreservesContentAndIndentation() {
        let blocks = MessageParser.parse("before\n```swift\n  **bold**\n\t!!secret!!\n```\nafter")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1], .code("  **bold**\n\t!!secret!!"))
        XCTAssertEqual(MessageParser.parse("~~~\nraw\n~~~"), [.code("raw")])
        XCTAssertEqual(spans("```unclosed\n**raw**").first?.text, "```unclosed\n**raw**")
    }

    func testInlineCodeAndEscapedSpoilersStayLiteral() {
        XCTAssertTrue(spans("`!!secret!!`").allSatisfy { $0.attachment == nil })
        XCTAssertTrue(spans(#"\!!literal!!"#).allSatisfy { $0.attachment == nil })
        XCTAssertTrue(spans("!!unclosed").allSatisfy { $0.attachment == nil })
    }
}

extension MessageParserTests {
    func testTraQReferenceMixedWithMarkdown() {
        let source = ##"**hello !{"type":"channel","raw":"#times/26/aorinngo","id":"01a159af-bfae-7290-aac2-a25a63323d37"}**"##
        let result = spans(source)
        XCTAssertEqual(result.map(\.text).joined(), "hello #times/26/aorinngo")
        XCTAssertTrue(result.contains { $0.text == "#times/26/aorinngo" && $0.style.isSuperset(of: [.bold, .reference]) })
        let user = #"!{"type":"user","raw":"@a}b\"c","id":"01a170b1-8dd2-7baf-bccd-9d3e0d659e79"}"#
        XCTAssertEqual(spans(user).first?.text, "@a}b\"c")
    }

    func testMalformedReferencesAreLiteralAndCodeIsProtected() {
        for raw in [#"!{"type":"user","raw":"**raw**","id":"bad"}"#, #"!{"bad":true}"#, #"!{"type":"user""#] {
            XCTAssertEqual(spans(raw).map(\.text).joined(), raw)
        }
        let raw = #"!{"type":"user","raw":"@user","id":"01a170b1-8dd2-7baf-bccd-9d3e0d659e79"}"#
        XCTAssertEqual(spans("`" + raw + "`").first?.text, raw)
        XCTAssertEqual(MessageParser.parse("```\n" + raw + "\n```"), [.code(raw)])
    }
}

extension MessageParserTests {
    func testStampsMixedWithTextAndCode() {
        let result = spans("hello :stamp.large.rotate: world :@user:")
        XCTAssertEqual(result.map(\.text).joined(), "hello :stamp.large.rotate: world :@user:")
        XCTAssertEqual(result.filter { if case .stamp = $0.attachment { return true }; return false }.count, 2)
        XCTAssertNil(StampReference.parse(":stamp.unknown:"))
        XCTAssertEqual(StampReference.parse(":stamp.large:")?.pointSize, 32)
        XCTAssertTrue(spans("`:stamp:`").allSatisfy { $0.attachment == nil })
        XCTAssertNil(StampReference.parse(":stamp.rotate.rotate.rotate.rotate.rotate.rotate:"))
    }
}

extension MessageParserTests {
    func testKaTeXAndCombiningCharacterLimits() {
        for raw in [#"$**x**_{i}$"#, #"$$\frac{a}{b}$$"#, #"\(x * y\)"#, #"\[**x**\]"#] {
            XCTAssertEqual(spans(raw), [MessageSpan(text: raw)])
        }
        let combining = "a" + String(repeating: "\u{0301}", count: 100_000)
        let output = spans(combining).map(\.text).joined()
        XCTAssertLessThan(output.utf8.count, 66_000)
    }

    func testSpoilerIgnoresDelimitersInsideCode() {
        let result = spans("before !!secret `!!literal!!` *italic*!! after")
        guard case .spoiler(_, let children) = result.first(where: { $0.attachment != nil })?.attachment else { return XCTFail() }
        XCTAssertTrue(children.contains { $0.text == "!!literal!!" && $0.style.contains(.code) })
        XCTAssertTrue(children.contains { $0.text == "italic" && $0.style.contains(.italic) })
        XCTAssertEqual(result.last?.text, " after")
    }

    func testHiddenMediaIsNotRequestedAndSharedImagesDeduplicate() {
        let blocks = MessageParser.parse("!!![secret](https://example.com/secret.png) :stamp:!! :stamp.large: :stamp.small:")
        XCTAssertEqual(MessagePresentation.resources(in: blocks, revealed: []), [.stamp("stamp")])
        XCTAssertEqual(Set(MessagePresentation.resources(in: blocks, revealed: [0])), Set([.image("https://example.com/secret.png"), .stamp("stamp")]))
    }

    func testMalformedAndAdversarialInputIsBounded() {
        for source in [String(repeating: "`!!\\!{", count: 3000), String(repeating: "!!x!!", count: 5000), "\u{E000}0\u{E001}", "![broken](", "**unclosed"] {
            XCTAssertFalse(MessageParser.parse(source).isEmpty)
        }
        XCTAssertLessThanOrEqual(MessageParser.parse(String(repeating: "```\nx\n```\n", count: 2000)).count, 257)
    }
}

extension MessageParserTests {
    func testGroupMentionUsesRawTextAndPreservesSurroundingStyle() {
        let raw = #"!{"type":"group","raw":"@developers","id":"01a170b1-8dd2-7baf-bccd-9d3e0d659e79"}"#
        XCTAssertEqual(spans(raw), [MessageSpan(text: "@developers", style: [.bold, .reference])])
        let mixed = spans("before *" + raw + "* after")
        XCTAssertEqual(mixed.map(\.text).joined(), "before @developers after")
        XCTAssertTrue(mixed.contains { $0.text == "@developers" && $0.style.isSuperset(of: [.bold, .reference, .italic]) })
        guard case .spoiler(_, let children) = spans("!!" + raw + "!!").first?.attachment else { return XCTFail("Missing spoiler") }
        XCTAssertEqual(children, [MessageSpan(text: "@developers", style: [.bold, .reference])])
    }

    func testGroupMentionInsideCodeAndInvalidGroupRemainLiteral() {
        let raw = #"!{"type":"group","raw":"@developers","id":"01a170b1-8dd2-7baf-bccd-9d3e0d659e79"}"#
        XCTAssertEqual(spans("`" + raw + "`"), [MessageSpan(text: raw, style: .code)])
        XCTAssertEqual(MessageParser.parse("```\n" + raw + "\n```"), [.code(raw)])
        let invalid = #"!{"type":"group","raw":"@developers","id":"invalid"}"#
        XCTAssertEqual(spans(invalid), [MessageSpan(text: invalid)])
    }
}
