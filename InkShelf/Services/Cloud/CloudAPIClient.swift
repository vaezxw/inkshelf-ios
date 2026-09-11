import Foundation

struct CloudUserDTO: Codable, Sendable {
    var id: String
    var email: String
}

struct CloudOTPResponse: Codable, Sendable {
    var ok: Bool
    var message: String?
    var echoCode: String?
}

struct CloudVerifyResponse: Codable, Sendable {
    var ok: Bool
    var token: String
    var user: CloudUserDTO
}

struct CloudSyncChapterPayload: Codable, Sendable, Equatable {
    var index: Int
    var title: String
    var remoteUrl: String?
}

struct CloudSyncBookPayload: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var author: String?
    var originRaw: String
    var sourceId: String?
    var sourceName: String?
    var bookUrl: String?
    var coverUrl: String?
    var intro: String?
    var lastChapterIndex: Int
    var lastScrollOffset: Double
    var lastReadAt: String?
    var addedAt: String
    var chapterCount: Int
    var r2Key: String?
    /// Remote books only: TOC metadata (no chapter body).
    var chapters: [CloudSyncChapterPayload]?
}

struct CloudSyncBookmarkPayload: Codable, Sendable, Equatable {
    var id: String
    var bookId: String
    var chapterIndex: Int
    var title: String
    var scrollOffset: Double
    var createdAt: String
}

struct CloudSyncSourcePayload: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var sourceUrl: String
    var enabled: Bool
    var legadoRaw: String
    var groupName: String?
    var addedAt: String
}

struct CloudSyncPrefsPayload: Codable, Sendable, Equatable {
    var readMode: String
    var fontSize: Double
    var lineHeight: Double
    var themeMode: String
    var autoReadEnabled: Bool
    var autoReadSpeed: Double
    var followSystemBrightness: Bool
    var brightness: Double
}

struct CloudSyncItem<T: Codable & Sendable>: Codable, Sendable {
    var id: String
    var updatedAt: String
    var payload: T
}

struct CloudPullResponse: Codable, Sendable {
    var ok: Bool
    var serverTime: String
    var books: [CloudSyncItem<CloudSyncBookPayload>]
    var bookmarks: [CloudSyncItem<CloudSyncBookmarkPayload>]
    var sources: [CloudSyncItem<CloudSyncSourcePayload>]
    var prefs: CloudSyncItem<CloudSyncPrefsPayload>?
}

struct CloudPushBody: Codable, Sendable {
    var books: [CloudSyncItem<CloudSyncBookPayload>]
    var bookmarks: [CloudSyncItem<CloudSyncBookmarkPayload>]
    var sources: [CloudSyncItem<CloudSyncSourcePayload>]
    var prefs: CloudSyncItem<CloudSyncPrefsPayload>?
}

struct CloudPushResponse: Codable, Sendable {
    var ok: Bool
    var accepted: Int
    var serverTime: String
}

struct CloudFilePutResponse: Codable, Sendable {
    var ok: Bool
    var key: String
    var updatedAt: String
}

enum CloudAPIError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .badURL: return "API 地址无效"
        case .http(let code, let body): return "HTTP \(code)：\(body)"
        case .decoding: return "响应解析失败"
        case .notLoggedIn: return "未登录"
        }
    }
}

enum CloudAPIClient {
    private static let iso = ISO8601DateFormatter()

    static func isoString(_ date: Date) -> String {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: date)
    }

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string)
    }

    static func requestOTP(email: String) async throws -> CloudOTPResponse {
        try await post("/auth/request-otp", body: ["email": email], auth: false)
    }

    static func verifyOTP(email: String, code: String) async throws -> CloudVerifyResponse {
        try await post("/auth/verify", body: ["email": email, "code": code], auth: false)
    }

    static func me() async throws -> CloudUserDTO {
        struct Wrap: Codable { var user: CloudUserDTO }
        let wrap: Wrap = try await get("/auth/me", auth: true)
        return wrap.user
    }

    static func pull(since: Date?) async throws -> CloudPullResponse {
        let sinceStr = since.map(isoString) ?? "0"
        return try await get("/sync/pull?since=\(sinceStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sinceStr)", auth: true)
    }

    static func push(_ body: CloudPushBody) async throws -> CloudPushResponse {
        try await post("/sync/push", encodable: body, auth: true)
    }

    static func uploadTXT(bookId: String, data: Data) async throws -> CloudFilePutResponse {
        guard let token = CloudAuthStore.token else { throw CloudAPIError.notLoggedIn }
        guard let url = URL(string: CloudConfig.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/files/\(bookId)") else {
            throw CloudAPIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (respData, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: respData)
        return try JSONDecoder().decode(CloudFilePutResponse.self, from: respData)
    }

    static func downloadTXT(bookId: String) async throws -> Data {
        guard let token = CloudAuthStore.token else { throw CloudAPIError.notLoggedIn }
        guard let url = URL(string: CloudConfig.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/files/\(bookId)") else {
            throw CloudAPIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        return data
    }

    private static func get<T: Decodable>(_ path: String, auth: Bool) async throws -> T {
        let req = try makeRequest(path: path, method: "GET", auth: auth)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw CloudAPIError.decoding }
    }

    private static func post<T: Decodable>(_ path: String, body: [String: String], auth: Bool) async throws -> T {
        var req = try makeRequest(path: path, method: "POST", auth: auth)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw CloudAPIError.decoding }
    }

    private static func post<T: Decodable, B: Encodable>(_ path: String, encodable: B, auth: Bool) async throws -> T {
        var req = try makeRequest(path: path, method: "POST", auth: auth)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(encodable)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw CloudAPIError.decoding }
    }

    private static func makeRequest(path: String, method: String, auth: Bool) throws -> URLRequest {
        let base = CloudConfig.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw CloudAPIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if auth {
            guard let token = CloudAuthStore.token else { throw CloudAPIError.notLoggedIn }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private static func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CloudAPIError.http(http.statusCode, body)
        }
    }
}
