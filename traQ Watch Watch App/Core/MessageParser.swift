import Foundation

nonisolated struct MessageStyle: OptionSet, Equatable, Sendable {
    let rawValue: Int
    static let bold = Self(rawValue: 1)
    static let italic = Self(rawValue: 2)
    static let strike = Self(rawValue: 4)
    static let code = Self(rawValue: 8)
    static let reference = Self(rawValue: 16)
}

nonisolated struct MessageSpan: Equatable, Sendable {
    var text: String
    var style: MessageStyle = []
    var attachment: MessageAttachment? = nil
    var spoilerAction: Int? = nil
}

nonisolated indirect enum MessageAttachment: Equatable, Sendable {
    case spoiler(id: Int, children: [MessageSpan])
    case stamp(StampReference)
    case image(MessageImage)
    case file(MessageFile)
    case quote(MessageQuoteReference)
}

nonisolated enum MessageBlock: Equatable, Sendable {
    case paragraph([MessageSpan])
    case code(String)
}

/// FoundationのMarkdown解析をUIから独立させる。長すぎる入力は解析せずraw表示する。
nonisolated enum MessageParser {
    static let maximumCharacters = 32_768
    static let maximumUTF8Bytes = 65_536

    static func parse(_ source: String, server: URL? = nil) -> [MessageBlock] {
        guard source.utf8.count <= maximumUTF8Bytes, source.count <= maximumCharacters else {
            return [.paragraph([MessageSpan(text: String(String(decoding: source.utf8.prefix(maximumUTF8Bytes), as: UTF8.self).prefix(maximumCharacters)) + "\n…（本文を省略しました）")])]
        }
        var parser = InlineParser(server: server)
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MessageBlock] = []
        var paragraph: [String] = []
        var index = 0
        while index < lines.count {
            if blocks.count >= 256 {
                let rest = (paragraph + Array(lines[index...])).joined(separator: "\n")
                blocks.append(.paragraph([MessageSpan(text: rest)]))
                paragraph = []
                break
            }
            if let fence = fenceStart(lines[index]) {
                if !paragraph.isEmpty {
                    blocks.append(.paragraph(parser.parse(paragraph.joined(separator: "\n"))))
                    paragraph = []
                }
                let start = index
                index += 1
                var code: [String] = []
                while index < lines.count && !isFenceEnd(lines[index], fence: fence) {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    blocks.append(.code(code.joined(separator: "\n")))
                } else {
                    // 壊れたフェンスは装飾を解釈せず、そのまま残す。
                    blocks.append(.paragraph([MessageSpan(text: lines[start...].joined(separator: "\n"))]))
                }
            } else {
                paragraph.append(lines[index])
            }
            index += 1
        }
        if !paragraph.isEmpty { blocks.append(.paragraph(parser.parse(paragraph.joined(separator: "\n")))) }
        return blocks
    }

    private static func fenceStart(_ line: String) -> (Character, Int)? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let trimmed = line.dropFirst(indentation)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        return (marker, length)
    }

    private static func isFenceEnd(_ line: String, fence: (Character, Int)) -> Bool {
        guard let end = fenceStart(line), end.0 == fence.0, end.1 >= fence.1 else { return false }
        return line.trimmingCharacters(in: .whitespaces).allSatisfy { $0 == fence.0 }
    }

    static func inline(_ source: String, server: URL? = nil) -> [MessageSpan] {
        guard let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        ) else { return [MessageSpan(text: source)] }
        return attributed.runs.map { run in
            var style: MessageStyle = []
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { style.insert(.bold) }
            if intent.contains(.emphasized) { style.insert(.italic) }
            if intent.contains(.strikethrough) { style.insert(.strike) }
            if intent.contains(.code) { style.insert(.code) }
            if run.link != nil { style.formUnion([.bold, .reference]) }
            let text = String(attributed[run.range].characters)
            if let url = run.imageURL {
                return MessageSpan(text: text, style: style, attachment: .image(MessageImage(url: url.absoluteString, alt: text)))
            }
            if !style.contains(.code), let link = run.link, let server,
               let resolved = TraQFileLink.resolve(link.absoluteString, server: server) {
                return MessageSpan(text: text, style: style, attachment: .file(MessageFile(url: resolved.url.absoluteString, label: text)))
            }
            if !style.contains(.code), let link = run.link, let server,
               let quote = MessageQuoteLinks.reference(link.absoluteString, label: text, server: server) {
                return MessageSpan(text: text, style: style, attachment: .quote(quote))
            }
            return MessageSpan(text: text, style: style)
        }
    }
}

/// 特殊記法を一時的なトークンに置き換え、周囲の標準Markdown装飾を引き継ぐ。
private nonisolated struct InlineParser {
    private let server: URL?
    init(server: URL?) { self.server = server }
    private var nextID = 0
    private var budget = 1_000_000

    mutating func parse(_ source: String, depth: Int = 0) -> [MessageSpan] {
        guard depth < 8, !source.contains("\u{E000}") else { return [MessageSpan(text: source)] }
        let chars = Array(source)
        var protected = ""
        var tokens: [MessageSpan] = []
        var i = 0
        func slice(_ start: Int, _ end: Int) -> String { String(chars[start..<end]) }
        func marker(_ token: Int) -> String { "\u{E000}\(token)\u{E001}" }
        while i < chars.count {
            budget -= 1
            if budget <= 0 || tokens.count >= 256 {
                // 未解析部分はトークンにして、Foundationにも解釈させない。
                protected += marker(tokens.count)
                tokens.append(MessageSpan(text: slice(i, chars.count)))
                break
            }
            // KaTeXはレンダリングせず、内部のMarkdownも含めてそのまま残す。
            let mathDelimiter: String?
            if chars[i] == "$" {
                mathDelimiter = i + 1 < chars.count && chars[i + 1] == "$" ? "$$" : "$"
            } else if i + 1 < chars.count && chars[i] == "\\" && (chars[i + 1] == "(" || chars[i + 1] == "[") {
                mathDelimiter = slice(i, i + 2)
            } else { mathDelimiter = nil }
            if let delimiter = mathDelimiter {
                let closing = delimiter == "\\(" ? "\\)" : delimiter == "\\[" ? "\\]" : delimiter
                let closingChars = Array(closing)
                var end = i + delimiter.count
                while end + closingChars.count <= chars.count && budget > 0 {
                    budget -= 1
                    if chars[end..<(end + closingChars.count)].elementsEqual(closingChars) { break }
                    end += 1
                }
                if budget > 0 && end + closingChars.count <= chars.count {
                    end += closingChars.count
                    protected += marker(tokens.count)
                    tokens.append(MessageSpan(text: slice(i, end)))
                    i = end
                    continue
                }
            }
            if chars[i] == "\\", i + 1 < chars.count {
                protected += slice(i, i + 2)
                i += 2
                continue
            }
            if chars[i] == "`" {
                var end = i
                while end < chars.count && chars[end] == "`" { end += 1 }
                let count = end - i
                var close = end
                var found = false
                while close < chars.count && budget > 0 {
                    budget -= 1
                    if chars[close] == "`" {
                        var runEnd = close
                        while runEnd < chars.count && chars[runEnd] == "`" { runEnd += 1 }
                        if runEnd - close == count {
                            protected += slice(i, runEnd)
                            i = runEnd
                            found = true
                            break
                        }
                        close = runEnd
                    } else { close += 1 }
                }
                if found { continue }
                protected += slice(i, end)
                i = end
                continue
            }
            // 画像全体を先に保護する。alt内の装飾で画像が分割されたり、
            // URL内の`:name:`がスタンプとして置き換わることを防ぐ。
            if i + 1 < chars.count && chars[i] == "!" && chars[i + 1] == "[" {
                var end = i + 2
                var brackets = 1
                while end < chars.count && end - i <= 4096 && brackets > 0 {
                    if chars[end] == "\\" { end += 2; continue }
                    if chars[end] == "[" { brackets += 1 }
                    if chars[end] == "]" { brackets -= 1 }
                    end += 1
                }
                if brackets == 0 && end < chars.count && chars[end] == "(" {
                    var parentheses = 1
                    end += 1
                    while end < chars.count && end - i <= 4096 && parentheses > 0 {
                        if chars[end] == "\\" { end += 2; continue }
                        if chars[end] == "(" { parentheses += 1 }
                        if chars[end] == ")" { parentheses -= 1 }
                        end += 1
                    }
                    if parentheses == 0 && end <= chars.count {
                        let parsed = MessageParser.inline(slice(i, end))
                        if let image = parsed.compactMap({ span -> MessageImage? in
                            if case .image(let image) = span.attachment { return image }; return nil
                        }).first {
                            let alt = parsed.map(\.text).joined().replacingOccurrences(of: "\u{FFFC}", with: "")
                            protected += marker(tokens.count)
                            tokens.append(MessageSpan(text: alt, attachment: .image(MessageImage(url: image.url, alt: alt))))
                            i = end
                            continue
                        }
                    }
                }
            }
            if chars[i] == ":" {
                var end = i + 1
                while end < chars.count && end - i <= 180 && chars[end] != ":" && !chars[end].isWhitespace { end += 1 }
                if end < chars.count && chars[end] == ":", let stamp = StampReference.parse(slice(i, end + 1)) {
                    protected += marker(tokens.count)
                    tokens.append(MessageSpan(text: stamp.raw, attachment: .stamp(stamp)))
                    i = end + 1
                    continue
                }
            }
            if i + 1 < chars.count && chars[i] == "!" && chars[i + 1] == "{" {
                var end = i + 1
                var braces = 0
                var quoted = false
                var escaped = false
                while end < chars.count && end - i <= 4096 && budget > 0 {
                    budget -= 1
                    let c = chars[end]
                    if quoted {
                        if escaped { escaped = false }
                        else if c == "\\" { escaped = true }
                        else if c == "\"" { quoted = false }
                    } else if c == "\"" { quoted = true }
                    else if c == "{" { braces += 1 }
                    else if c == "}" {
                        braces -= 1
                        if braces == 0 { end += 1; break }
                    }
                    end += 1
                }
                let raw = slice(i, end)
                struct Reference: Decodable { let type: String; let raw: String; let id: String }
                let reference = try? JSONDecoder().decode(Reference.self, from: Data(raw.dropFirst().utf8))
                protected += marker(tokens.count)
                if let reference, ["user", "channel", "group"].contains(reference.type), UUID(uuidString: reference.id) != nil {
                    tokens.append(MessageSpan(text: reference.raw, style: [.bold, .reference]))
                } else {
                    tokens.append(MessageSpan(text: raw))
                }
                i = end
                continue
            }
            if i + 1 < chars.count && chars[i] == "!" && chars[i + 1] == "!" {
                var end = i + 2
                while end + 1 < chars.count && budget > 0 {
                    budget -= 1
                    if chars[end] == "\\" { end += 2; continue }
                    if chars[end] == "`" {
                        var openingEnd = end
                        while openingEnd < chars.count && chars[openingEnd] == "`" { openingEnd += 1 }
                        var position = openingEnd
                        var codeEnd: Int?
                        while position < chars.count && budget > 0 {
                            budget -= 1
                            if chars[position] == "`" {
                                var runEnd = position
                                while runEnd < chars.count && chars[runEnd] == "`" { runEnd += 1 }
                                if runEnd - position == openingEnd - end { codeEnd = runEnd; break }
                                position = runEnd
                            } else { position += 1 }
                        }
                        if let codeEnd { end = codeEnd; continue }
                    }
                    if chars[end] == "!" && chars[end + 1] == "!" { break }
                    end += 1
                }
                if end + 1 < chars.count && end > i + 2 && budget > 0 {
                    let id = nextID
                    nextID += 1
                    let children = parse(slice(i + 2, end), depth: depth + 1)
                    protected += marker(tokens.count)
                    tokens.append(MessageSpan(text: slice(i, end + 2), attachment: .spoiler(id: id, children: children)))
                    i = end + 2
                    continue
                }
            }
            protected.append(chars[i])
            i += 1
        }
        var result: [MessageSpan] = []
        for span in MessageParser.inline(protected, server: server) {
            if span.attachment != nil { result.append(span); continue }
            var remaining = span.text[...]
            while let start = remaining.firstIndex(of: "\u{E000}"),
                  let end = remaining[start...].firstIndex(of: "\u{E001}"),
                  let index = Int(remaining[remaining.index(after: start)..<end]), tokens.indices.contains(index) {
                if start > remaining.startIndex {
                    result.append(contentsOf: TraQFileLink.expand(MessageSpan(text: String(remaining[..<start]), style: span.style), server: server).flatMap { MessageQuoteLinks.expand($0, server: server) })
                }
                var token = tokens[index]
                token.style.formUnion(span.style)
                result.append(token)
                remaining = remaining[remaining.index(after: end)...]
            }
            if !remaining.isEmpty { result.append(contentsOf: TraQFileLink.expand(MessageSpan(text: String(remaining), style: span.style), server: server).flatMap { MessageQuoteLinks.expand($0, server: server) }) }
        }
        return result
    }
}

nonisolated struct SpoilerState: Equatable {
    private(set) var revealed: Set<Int> = []

    mutating func toggle(_ id: Int) {
        if !revealed.insert(id).inserted { revealed.remove(id) }
    }
}
