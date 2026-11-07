import Foundation

nonisolated struct MessageFile: Equatable, Hashable, Sendable {
    let url: String
    let label: String
}

nonisolated enum TraQFileLink {
    static func resolve(_ raw: String, server: URL) -> ResolvedImageURL? {
        guard let resolved = try? MediaURLPolicy.resolve(raw, server: server), resolved.authenticated else { return nil }
        return resolved
    }

    /// Markdownの処理後のテキストだけを走査する。コード・画像・リンク先は再走査しない。
    static func expand(_ span: MessageSpan, server: URL?) -> [MessageSpan] {
        guard let server, span.attachment == nil, !span.style.contains(.code),
              let regex = try? NSRegularExpression(pattern: #"https://[A-Za-z0-9.:-]+/(?:api/v3/)?files/[0-9a-fA-F-]{36}"#) else { return [span] }
        var result: [MessageSpan] = []
        var cursor = span.text.startIndex
        for match in regex.matches(in: span.text, range: NSRange(span.text.startIndex..., in: span.text)).prefix(64) {
            guard let range = Range(match.range, in: span.text) else { continue }
            if range.lowerBound > span.text.startIndex {
                let preceding = span.text[span.text.index(before: range.lowerBound)]
                if preceding.isASCII && (preceding.isLetter || preceding.isNumber || "/_".contains(preceding)) { continue }
            }
            if range.upperBound < span.text.endIndex {
                let following = span.text[range.upperBound]
                if following.isASCII && (following.isLetter || following.isNumber || "/_?%#-".contains(following)) { continue }
            }
            let raw = String(span.text[range])
            guard let resolved = resolve(raw, server: server) else { continue }
            if cursor < range.lowerBound { result.append(MessageSpan(text: String(span.text[cursor..<range.lowerBound]), style: span.style)) }
            result.append(MessageSpan(text: raw, style: span.style.union([.bold, .reference]), attachment: .file(MessageFile(url: resolved.url.absoluteString, label: raw))))
            cursor = range.upperBound
        }
        if cursor == span.text.startIndex { return [span] }
        if cursor < span.text.endIndex { result.append(MessageSpan(text: String(span.text[cursor...]), style: span.style)) }
        return result
    }
}

nonisolated struct TraQFileInfo: Decodable {
    let mime: String
    let size: Int64
    let thumbnails: [Thumbnail]?
    let thumbnail: LegacyThumbnail?
    struct Thumbnail: Decodable { let type: String }
    struct LegacyThumbnail: Decodable {}

    var isImage: Bool { mime.lowercased().hasPrefix("image/") }
    var hasImageThumbnail: Bool { thumbnails?.contains(where: { $0.type == "image" }) == true || thumbnail != nil }
}
