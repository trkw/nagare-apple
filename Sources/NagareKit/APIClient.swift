import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct APIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let message: String
    public var errorDescription: String? { message }
}

/// Thin client for the Nagare REST API (trkw/nagare apps/api).
public struct APIClient: Sendable {
    public let baseURL: URL
    public let token: String
    let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func makeRequest(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("api" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "HTTP \(status)"
            throw APIError(status: status, message: message)
        }
        return data
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try Self.decoder.decode(T.self, from: try await send(makeRequest(path, query: query)))
    }

    func post<T: Decodable>(_ path: String, method: String = "POST", query: [URLQueryItem] = [], json: [String: Any]? = nil) async throws -> T {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        return try Self.decoder.decode(T.self, from: try await send(makeRequest(path, method: method, query: query, body: body)))
    }

    // MARK: Endpoints

    public func me() async throws -> Me { try await get("/me") }

    public func feeds() async throws -> [Feed] { try await get("/feeds") }

    private struct FeedResult: Decodable { let feed: Feed }

    public func subscribe(url: String, folder: String? = nil) async throws -> Feed {
        var json: [String: Any] = ["url": url]
        if let folder { json["folder"] = folder }
        let result: FeedResult = try await post("/feeds", json: json)
        return result.feed
    }

    public func watchPage(url: String) async throws -> Feed {
        let result: FeedResult = try await post("/web-feeds", json: ["url": url])
        return result.feed
    }

    public func unsubscribe(feedId: Int) async throws {
        _ = try await send(makeRequest("/feeds/\(feedId)", method: "DELETE"))
    }

    public func entries(_ query: EntryQuery) async throws -> [Entry] {
        try await get("/entries", query: query.queryItems)
    }

    public func entry(id: Int) async throws -> Entry { try await get("/entries/\(id)") }

    private struct Content: Decodable { let content: String }

    public func fullText(entryId: Int) async throws -> String {
        let result: Content = try await post("/entries/\(entryId)/fulltext")
        return result.content
    }

    public func translate(entryId: Int, lang: String = "ja") async throws -> Translation {
        try await post("/entries/\(entryId)/translate", query: [URLQueryItem(name: "lang", value: lang)])
    }

    private struct Updated: Decodable { let updated: Int }

    public func setState(ids: [Int], read: Bool? = nil, starred: Bool? = nil) async throws {
        var json: [String: Any] = ["ids": ids]
        if let read { json["read"] = read }
        if let starred { json["starred"] = starred }
        let _: Updated = try await post("/entries/state", json: json)
    }

    private struct Created: Decodable { let id: Int }

    /// Turns new-entry notifications on or off for a feed.
    public func setNotify(feedId: Int, _ on: Bool) async throws -> Feed {
        try await post("/feeds/\(feedId)", method: "PATCH", json: ["notify": on])
    }

    /// Registers this device for APNs. `sandbox` is true for development builds.
    public func registerPush(apnsToken: String, name: String, sandbox: Bool) async throws {
        let _: Created = try await post("/push/targets", json: ["platform": "apns", "token": apnsToken, "name": name, "sandbox": sandbox])
    }

    public func unregisterPush(token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["token": token])
        _ = try await send(makeRequest("/push/targets", method: "DELETE", body: body))
    }

    public func handoff(entryIds: [Int], note: String, toAgent: String? = nil) async throws {
        var json: [String: Any] = ["entry_ids": entryIds, "note": note]
        if let toAgent, !toAgent.isEmpty { json["to_agent"] = toAgent }
        let _: Created = try await post("/handoffs", json: json)
    }
}
