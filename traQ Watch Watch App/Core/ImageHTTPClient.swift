import Foundation

/// 自動転送を止め、取得ループで転送先と認証ヘッダーを検証する。
nonisolated final class ImageRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated enum ImageLoadError: LocalizedError {
    case invalidURL, invalidResponse, tooLarge, unsupportedImage, invalidRedirect, tooManyRedirects
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRedirect: "画像の転送先が不正です"
        case .tooManyRedirects: "画像の転送回数が上限を超えました"
        case .invalidURL: "許可されていない画像URLです"
        case .invalidResponse: "画像の応答が不正です"
        case .tooLarge: "画像サイズが上限を超えています"
        case .unsupportedImage: "対応していない画像形式です"
        case .http(let status): "画像の取得に失敗しました（HTTP \(status)）"
        }
    }
}

nonisolated struct ImageHTTPClient: Sendable {
    private let session: URLSession
    static let maximumBytes = 2 * 1024 * 1024

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: ImageRedirectDelegate(), delegateQueue: nil)
    }

    @concurrent
    func data(for request: URLRequest) async throws -> Data {
        var current = request
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        for hop in 0...5 {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            let remaining = ContinuousClock.now.duration(to: deadline).components
            current.timeoutInterval = min(20, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
            let (bytes, response) = try await session.bytes(for: current)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw ImageLoadError.invalidResponse }
            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                guard hop < 5 else { throw ImageLoadError.tooManyRedirects }
                guard let location = http.value(forHTTPHeaderField: "Location") else { throw ImageLoadError.invalidRedirect }
                current = try ImageRedirectPolicy.request(location: location, from: current)
                continue
            }
            guard http.statusCode == 200 else { throw ImageLoadError.http(http.statusCode) }
            guard http.mimeType?.hasPrefix("image/") == true else { throw ImageLoadError.unsupportedImage }
            guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw ImageLoadError.tooLarge }
            var data = Data()
            for try await byte in bytes {
                if data.count >= Self.maximumBytes { throw ImageLoadError.tooLarge }
                data.append(byte)
                if data.count % 16384 == 0 {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
                }
            }
            try Task.checkCancellation()
            return data
        }
        throw ImageLoadError.tooManyRedirects
    }
}

nonisolated enum ImageRedirectPolicy {
    static func request(location: String, from previous: URLRequest) throws -> URLRequest {
        guard !location.isEmpty, location.count <= 4096,
              !location.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let source = previous.url,
              let target = URL(string: location, relativeTo: source)?.absoluteURL else {
            throw ImageLoadError.invalidRedirect
        }
        // URLポリシーは検証にだけ使い、署名付きURLや転送先のパスを改変しない。
        _ = try MediaURLPolicy.resolve(target.absoluteString, server: source)
        var next = URLRequest(url: target)
        let sameOrigin = source.scheme?.lowercased() == target.scheme?.lowercased()
            && source.host?.lowercased() == target.host?.lowercased()
            && (source.port ?? 443) == (target.port ?? 443)
        if sameOrigin {
            for header in ["Cookie", "Authorization"] {
                if let value = previous.value(forHTTPHeaderField: header) { next.setValue(value, forHTTPHeaderField: header) }
            }
        }
        // 外部へ移った時点で認証は失われ、元のホストへ戻っても復元しない。
        return next
    }
}
