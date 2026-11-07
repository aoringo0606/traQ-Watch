import Foundation

nonisolated struct SavedSession: Codable, Sendable {
    let server: String
    let token: String
}

nonisolated enum TraQAPI {
    static func serverURL(_ input: String) -> URL? {
        guard let components = URLComponents(string: input),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        return components.url
    }

    static func loginBody(name: String, password: String) throws -> Data {
        struct Credentials: Encodable { let name: String; let password: String }
        return try JSONEncoder().encode(Credentials(name: name, password: password))
    }

    private static func messageDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid RFC 3339 date"))
        }
        return decoder
    }

    static func message(from data: Data) throws -> ActivityMessage {
        try messageDecoder().decode(ActivityMessage.self, from: data)
    }

    static func activities(from data: Data) throws -> [ActivityMessage] {
        let messages = try messageDecoder().decode([ActivityMessage].self, from: data)
        var seen: Set<String> = []
        return Array(messages.sorted { $0.createdAt > $1.createdAt }.filter { seen.insert($0.id).inserted }.prefix(20))
    }

    static func channelPath(from data: Data) throws -> String {
        struct Response: Decodable { let path: String }
        return "#" + (try JSONDecoder().decode(Response.self, from: data).path)
    }
}
