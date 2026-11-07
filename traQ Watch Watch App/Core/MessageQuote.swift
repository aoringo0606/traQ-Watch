import Foundation

nonisolated struct MessageQuoteReference: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let url: String
    let label: String
}

nonisolated enum MessageQuoteLinks {
    static let maximumPerMessage = 3
    static let maximumPerRefresh = 12

    static func reference(_ raw: String, label: String, server: URL) -> MessageQuoteReference? {
        guard raw.count <= 4096, let parts = URLComponents(string: raw),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.host?.lowercased() == server.host?.lowercased(),
              (parts.port ?? 443) == (server.port ?? 443), parts.query == nil, parts.fragment == nil else { return nil }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 3, path[0].isEmpty, path[1] == "messages",
              let uuid = UUID(uuidString: String(path[2])) else { return nil }
        let id = uuid.uuidString.lowercased()
        return MessageQuoteReference(id: id, url: server.appending(path: "messages/" + id).absoluteString, label: label)
    }

    static func expand(_ span: MessageSpan, server: URL?) -> [MessageSpan] {
        guard let server, span.attachment == nil, !span.style.contains(.code),
              let regex = try? NSRegularExpression(pattern: #"https://[A-Za-z0-9.:-]+/messages/[0-9a-fA-F-]{36}"#) else { return [span] }
        var result: [MessageSpan] = []
        var cursor = span.text.startIndex
        for match in regex.matches(in: span.text, range: NSRange(span.text.startIndex..., in: span.text)).prefix(64) {
            guard let range = Range(match.range, in: span.text) else { continue }
            if range.lowerBound > span.text.startIndex {
                let before = span.text[span.text.index(before: range.lowerBound)]
                if before.isASCII && (before.isLetter || before.isNumber || "/_".contains(before)) { continue }
            }
            if range.upperBound < span.text.endIndex {
                let after = span.text[range.upperBound]
                if after.isASCII && (after.isLetter || after.isNumber || "/_?%#-".contains(after)) { continue }
            }
            let raw = String(span.text[range])
            guard let ref = reference(raw, label: raw, server: server) else { continue }
            if cursor < range.lowerBound { result.append(MessageSpan(text: String(span.text[cursor..<range.lowerBound]), style: span.style)) }
            result.append(MessageSpan(text: raw, style: span.style.union([.bold, .reference]), attachment: .quote(ref)))
            cursor = range.upperBound
        }
        if cursor == span.text.startIndex { return [span] }
        if cursor < span.text.endIndex { result.append(MessageSpan(text: String(span.text[cursor...]), style: span.style)) }
        return result
    }

    /// 親メッセージだけを走査する。スポイラーや引用元を再帰的に取得しない。
    static func plan(messages: [ActivityMessage], parsed: [String: [MessageBlock]]) -> [String: [MessageQuoteReference]] {
        var result: [String: [MessageQuoteReference]] = [:]
        var scheduled: Set<String> = []
        for message in messages {
            var seen: Set<String> = []
            var refs: [MessageQuoteReference] = []
            for block in parsed[message.id] ?? [] {
                guard case .paragraph(let spans) = block else { continue }
                for span in spans {
                    guard case .quote(let ref) = span.attachment, ref.id != message.id.lowercased(),
                          !seen.contains(ref.id), refs.count < maximumPerMessage,
                          scheduled.contains(ref.id) || scheduled.count < maximumPerRefresh else { continue }
                    seen.insert(ref.id)
                    scheduled.insert(ref.id)
                    refs.append(ref)
                }
            }
            result[message.id] = refs
        }
        return result
    }

    static func body(_ blocks: [MessageBlock], expanded: Set<String>) -> [MessageBlock] {
        blocks.map { block in
            guard case .paragraph(let spans) = block else { return block }
            guard spans.contains(where: { span in
                if case .quote(let ref) = span.attachment { return expanded.contains(ref.id) }; return false
            }) else { return block }
            var visible = spans.filter { span in
                if case .quote(let ref) = span.attachment { return !expanded.contains(ref.id) }
                return true
            }
            while let last = visible.last, last.attachment == nil {
                let trimmed = last.text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
                if trimmed.isEmpty { visible.removeLast() }
                else { visible[visible.count - 1].text = trimmed; break }
            }
            return .paragraph(visible)
        }
    }
}

nonisolated struct MessageQuotePreview: Sendable {
    let message: ActivityMessage
    let excerpt: [MessageSpan]

    init(message: ActivityMessage, server: URL?) {
        self.message = message
        excerpt = Self.excerpt(from: MessageParser.parse(message.content, server: server))
    }

    static func excerpt(from blocks: [MessageBlock]) -> [MessageSpan] {
        var result: [MessageSpan] = []
        var remaining = 400
        for block in blocks {
            if !result.isEmpty { result.append(MessageSpan(text: "\n")); remaining -= 1 }
            let spans: [MessageSpan]
            switch block {
            case .paragraph(let text): spans = text
            case .code(let code): spans = [MessageSpan(text: code, style: .code)]
            }
            for original in spans {
                guard remaining > 0 else { break }
                var span = original
                switch span.attachment {
                case .spoiler: span = MessageSpan(text: "［スポイラー］")
                case .image: span = MessageSpan(text: "［画像］")
                case .file: span = MessageSpan(text: "［添付ファイル］")
                case .quote: span = MessageSpan(text: "［引用メッセージ］", style: [.bold, .reference])
                case .stamp, nil: break
                }
                if span.text.count > remaining {
                    span = MessageSpan(text: String(span.text.prefix(remaining)) + "…", style: span.style)
                }
                remaining -= span.text.count
                result.append(span)
            }
            if remaining <= 0 { break }
        }
        return result
    }
}

nonisolated enum MessageQuoteState: Sendable {
    case loading
    case loaded(MessageQuotePreview)
    case failed
}

nonisolated enum MessageQuoteLoader {
    /// 同一IDは一度だけ取得し、通信は最大3件。最新一覧に含まれる投稿は再取得しない。
    static func load(references: [MessageQuoteReference], timeline: [ActivityMessage], server: URL?,
                     fetch: @escaping @Sendable (String) async throws -> ActivityMessage) async -> [String: MessageQuoteState] {
        var seen: Set<String> = []
        let ids = references.map(\.id).filter { seen.insert($0).inserted }.prefix(MessageQuoteLinks.maximumPerRefresh)
        let known = Dictionary(timeline.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { _, last in last })
        var result: [String: MessageQuoteState] = [:]
        let all = Array(ids)
        for start in stride(from: 0, to: all.count, by: 3) {
            if Task.isCancelled { break }
            await withTaskGroup(of: (String, MessageQuoteState).self) { group in
                for id in all[start..<min(start + 3, all.count)] {
                    group.addTask {
                        do {
                            let message: ActivityMessage
                            if let existing = known[id] { message = existing }
                            else { message = try await fetch(id) }
                            guard message.id.lowercased() == id else { return (id, .failed) }
                            try Task.checkCancellation()
                            return (id, .loaded(MessageQuotePreview(message: message, server: server)))
                        } catch { return (id, .failed) }
                    }
                }
                for await (id, state) in group { result[id] = state }
            }
        }
        return result
    }
}
