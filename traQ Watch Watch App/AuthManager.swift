//
//  AuthManager.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import Foundation
import SwiftUI
import Combine

enum AuthError: LocalizedError {
    case invalidServer
    case invalidResponse
    case invalidCredentials
    case forbidden
    case missingCookie
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidServer:
            "HTTPSのサーバーURLを入力してください"
        case .invalidResponse:
            "サーバーから不正な応答がありました"
        case .invalidCredentials:
            "ユーザー名またはパスワードが違います"
        case .forbidden:
            "このアカウントではログインできません"
        case .missingCookie:
            "セッションCookieを取得できませんでした"
        case .http(let status):
            "HTTPエラー: \(status)"
        }
    }
}

// ログイン時のリダイレクトを拒否
final class NoRedirectDelegate: NSObject,
    URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
final class AuthManager: ObservableObject {
    @Published var username: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var currentServerURL: URL? { savedSession.flatMap { TraQAPI.serverURL($0.server) } }
    private var savedSession: SavedSession?
    private let imageClient = ImageHTTPClient()
    private var userCache: [String: TraQUser]?

    private let client: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        return URLSession(
            configuration: config,
            delegate: NoRedirectDelegate(),
            delegateQueue: nil
        )
    }()

    private func baseURL(_ input: String) throws -> URL {
        guard let url = TraQAPI.serverURL(input) else { throw AuthError.invalidServer }
        return url
    }

    private func endpoint(
        _ path: String,
        server: String
    ) throws -> URL {
        let base = try baseURL(server)
        return base.appending(path: "api/v3/" + path)
    }

    private func validate(
        _ response: URLResponse,
        expected: Int
    ) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        switch http.statusCode {
        case expected:
            return http
        case 401:
            throw AuthError.invalidCredentials
        case 403:
            throw AuthError.forbidden
        default:
            throw AuthError.http(http.statusCode)
        }
    }

    private func request(
        _ path: String,
        method: String = "GET",
        session: SavedSession
    ) throws -> URLRequest {
        let url = try endpoint(path, server: session.server)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "r_session=\(session.token)",
            forHTTPHeaderField: "Cookie"
        )
        return request
    }

    private func fetchUsername(
        session: SavedSession
    ) async throws -> String {
        let req = try request(
            "users/me",
            session: session
        )
        let (data, response) = try await client.data(for: req)
        _ = try validate(response, expected: 200)

        struct Me: Decodable {
            let name: String
        }

        return try JSONDecoder()
            .decode(Me.self, from: data).name
    }

    func login(
        server: String,
        name: String,
        password: String
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let serverURL = try baseURL(server)
            let url = try endpoint(
                "login",
                server: serverURL.absoluteString
            )

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )

            req.httpBody = try TraQAPI.loginBody(name: name, password: password)

            let (_, response) = try await client.data(for: req)
            let http = try validate(response, expected: 204)

            let headers = http.allHeaderFields.reduce(
                into: [String: String]()
            ) { result, entry in
                if let key = entry.key as? String,
                   let value = entry.value as? String {
                    result[key] = value
                }
            }

            let cookies = HTTPCookie.cookies(
                withResponseHeaderFields: headers,
                for: url
            )

            guard let token = cookies.first(
                where: { $0.name == "r_session" }
            )?.value else {
                throw AuthError.missingCookie
            }

            let session = SavedSession(
                server: serverURL.absoluteString,
                token: token
            )

            let verifiedName = try await fetchUsername(
                session: session
            )

            try KeychainStore.save(session)

            savedSession = session
            username = verifiedName

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        guard savedSession == nil, let session = KeychainStore.load() else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let name = try await fetchUsername(
                session: session
            )
            savedSession = session
            username = name
        } catch {
            // 認証切れの場合だけ保存情報を削除
            if case AuthError.invalidCredentials = error {
                KeychainStore.delete()
            }
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        if let session = savedSession {
            do {
                let req = try request(
                    "logout",
                    method: "POST",
                    session: session
                )
                let (_, response) = try await client.data(for: req)
                _ = try validate(response, expected: 204)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        KeychainStore.delete()
        savedSession = nil
        userCache = nil
        username = nil
    }

    func fetchActivities() async throws -> [ActivityMessage] {
        guard let session = savedSession else {
            throw AuthError.invalidCredentials
        }

        var req = try request(
            "activity/timeline",
            session: session
        )

        guard let url = req.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidResponse
        }

        components.queryItems = [
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "all", value: "true")
        ]

        guard let timelineURL = components.url else { throw AuthError.invalidResponse }
        req.url = timelineURL

        let (data, response) = try await client.data(for: req)
        _ = try validate(response, expected: 200)

        return try TraQAPI.activities(from: data)
    }

    private func get(
        _ path: String,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        guard let session = savedSession else {
            throw AuthError.invalidCredentials
        }

        var req = try request(
            path,
            session: session
        )
        if let timeout { req.timeoutInterval = timeout }

        let (data, response) = try await client.data(for: req)
        _ = try validate(response, expected: 200)

        return data
    }

    func fetchUsers(forceRefresh: Bool = false) async throws -> [String: TraQUser] {
        if !forceRefresh, let userCache { return userCache }
        let data = try await get("users")
        let users = try JSONDecoder().decode(
            [TraQUser].self,
            from: data
        )

        let mapped = Dictionary(users.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        userCache = mapped
        return mapped
    }

    func fetchUserIcon(userId: String) async throws -> Data {
        // UUIDの形式を確認してパスに埋め込む
        guard let id = UUID(uuidString: userId) else {
            throw AuthError.invalidResponse
        }

        guard let session = savedSession else { throw AuthError.invalidCredentials }
        let req = try request("users/\(id.uuidString.lowercased())/icon", session: session)
        return try await imageClient.data(for: req)
    }

    func fetchChannelPath(channelId: String) async throws -> String {
        guard let id = UUID(uuidString: channelId) else {
            throw AuthError.invalidResponse
        }

        let data = try await get(
            "channels/\(id.uuidString.lowercased())/path"
        )

        return try TraQAPI.channelPath(from: data)
    }

    func fetchStamps() async throws -> [String: TraQStamp] {
        let data = try await get("stamps")
        let stamps = try JSONDecoder().decode([TraQStamp].self, from: data)
        return Dictionary(stamps.map { ($0.name, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func stampImageRequest(id: String, userIcon: Bool = false) throws -> URLRequest {
        guard let session = savedSession else { throw AuthError.invalidCredentials }
        guard let uuid = UUID(uuidString: id) else { throw AuthError.invalidResponse }
        let id = uuid.uuidString.lowercased()
        return try request(userIcon ? "users/\(id)/icon" : "stamps/\(id)/image", session: session)
    }

    func messageImageRequest(_ raw: String) throws -> URLRequest {
        guard let session = savedSession else { throw AuthError.invalidCredentials }
        let resolved = try MediaURLPolicy.resolve(raw, server: baseURL(session.server))
        var req = URLRequest(url: resolved.url)
        if resolved.authenticated {
            req.setValue("r_session=\(session.token)", forHTTPHeaderField: "Cookie")
        }
        return req
    }

    func attachedImageRequest(_ raw: String) async throws -> URLRequest? {
        guard let session = savedSession, let server = currentServerURL,
              let resolved = TraQFileLink.resolve(raw, server: server) else { throw ImageLoadError.invalidURL }
        let id = resolved.url.lastPathComponent
        let data = try await get("files/\(id)/meta")
        let meta = try JSONDecoder().decode(TraQFileInfo.self, from: data)
        guard meta.isImage else { return nil }
        if meta.hasImageThumbnail { return try request("files/\(id)/thumbnail", session: session) }
        guard meta.size >= 0, meta.size <= Int64(ImageHTTPClient.maximumBytes) else { throw ImageLoadError.tooLarge }
        return try request("files/\(id)", session: session)
    }


    func unicodeEmoji(for stamp: TraQStamp) async throws -> String? {
        guard stamp.isUnicode, let fileID = UUID(uuidString: stamp.fileId) else { return nil }
        let data = try await get("files/\(fileID.uuidString.lowercased())/meta")
        struct Meta: Decodable { let name: String }
        let filename = try JSONDecoder().decode(Meta.self, from: data).name
        return UnicodeStamp.emoji(filename: filename)
    }


    func fetchMessage(id: String) async throws -> ActivityMessage {
        guard let uuid = UUID(uuidString: id) else { throw AuthError.invalidResponse }
        let data = try await get("messages/\(uuid.uuidString.lowercased())", timeout: 10)
        return try TraQAPI.message(from: data)
    }

}
