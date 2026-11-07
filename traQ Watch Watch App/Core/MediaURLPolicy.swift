import Foundation

nonisolated struct ResolvedImageURL: Equatable {
    let url: URL
    let authenticated: Bool
}

nonisolated enum MediaURLPolicy {
    /// 認証を付けるのはログイン先の正規のファイルAPIだけ。
    static func resolve(_ raw: String, server: URL) throws -> ResolvedImageURL {
        guard raw.count <= 4096,
              let input = URLComponents(string: raw), input.user == nil, input.password == nil,
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ImageLoadError.invalidURL
        }
        let url: URL
        if input.scheme == nil {
            guard raw.hasPrefix("/"), !raw.hasPrefix("//"), let resolved = URL(string: raw, relativeTo: server)?.absoluteURL else {
                throw ImageLoadError.invalidURL
            }
            url = resolved
        } else {
            guard let absolute = input.url else { throw ImageLoadError.invalidURL }
            url = absolute
        }
        guard url.scheme?.lowercased() == "https", let originalHost = url.host?.lowercased(), !originalHost.isEmpty else {
            throw ImageLoadError.invalidURL
        }
        let host = originalHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let sameOrigin = host == server.host?.lowercased() && (url.port ?? 443) == (server.port ?? 443)
        let parts = url.path.split(separator: "/").map(String.init)
        let fileID: String?
        if parts.count == 2 && parts[0] == "files" { fileID = parts[1] }
        else if parts.count == 4 && Array(parts.prefix(3)) == ["api", "v3", "files"] { fileID = parts[3] }
        else { fileID = nil }
        if sameOrigin, let fileID, let uuid = UUID(uuidString: fileID), url.query == nil {
            return ResolvedImageURL(url: server.appending(path: "api/v3/files/" + uuid.uuidString.lowercased()), authenticated: true)
        }
        // 相対URLはファイルAPI以外へアクセスさせない。
        guard input.scheme != nil,
              host.contains("."), !host.contains(":"),
              host.split(separator: ".").last?.contains(where: { $0.isLetter }) == true,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              !["localhost", "local", "internal", "invalid", "test"].contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              url.port == nil || url.port == 443 else { throw ImageLoadError.invalidURL }
        return ResolvedImageURL(url: url, authenticated: false)
    }
}

nonisolated struct MessageImage: Equatable, Hashable, Sendable {
    let url: String
    let alt: String
}

nonisolated enum MessageMediaResource: Equatable, Hashable, Sendable {
    case stamp(String)
    case image(String)
    case file(String)

    var cacheKey: String {
        switch self {
        case .stamp(let name): "stamp:" + name
        case .image(let url): "image:" + url
        case .file(let url): "file:" + url
        }
    }
}
