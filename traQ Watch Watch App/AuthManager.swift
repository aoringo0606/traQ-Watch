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

    private var savedSession: SavedSession?

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
        guard let components = URLComponents(string: input),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty ||
                components.path == "/" else {
            throw AuthError.invalidServer
        }

        guard let url = components.url else {
            throw AuthError.invalidServer
        }

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

            struct Credentials: Encodable {
                let name: String
                let password: String
            }

            req.httpBody = try JSONEncoder().encode(
                Credentials(name: name, password: password)
            )

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
        guard let session = KeychainStore.load() else {
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

        var components = URLComponents(
            url: req.url!,
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "all", value: "true")
        ]

        req.url = components.url!

        let (data, response) = try await client.data(for: req)
        _ = try validate(response, expected: 200)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            [ActivityMessage].self,
            from: data
        )
    }
}
