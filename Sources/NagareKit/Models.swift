import Foundation

public struct Feed: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case rss, web, agent }

    public let id: Int
    public let kind: Kind
    public let url: String
    public let title: String
    public let siteUrl: String?
    public let folder: String?
    public let addedBy: String?
    public let reason: String?
    public let selector: String?
    public let credential: String?
    public let notify: Int
    public var unread: Int
    public let lastError: String?

    public var displayTitle: String { title.isEmpty ? url : title }
}

public struct Entry: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let feedId: Int
    public let feedTitle: String
    public let url: String?
    public let title: String
    public let author: String?
    public var content: String?
    /// Unix milliseconds.
    public let publishedAt: Int64
    public var read: Int
    public var starred: Int

    public var isRead: Bool {
        get { read != 0 }
        set { read = newValue ? 1 : 0 }
    }

    public var isStarred: Bool {
        get { starred != 0 }
        set { starred = newValue ? 1 : 0 }
    }

    public var publishedDate: Date { Date(timeIntervalSince1970: TimeInterval(publishedAt) / 1000) }
    public var displayTitle: String { title.isEmpty ? "（タイトルなし）" : title }
}

public struct Me: Codable, Sendable {
    public let name: String
    public let kind: String
    public let scopes: [String]
}

public struct Translation: Codable, Sendable {
    public let title: String
    public let content: String
    public let engine: String
    public let cached: Bool
}

/// What the entry list shows.
public enum Selection: Hashable, Sendable {
    case all
    case starred
    case folder(String)
    case feed(Int)
}

public struct EntryQuery: Sendable {
    public var feed: Int?
    public var folder: String?
    public var unread = false
    public var starred = false
    public var search: String?
    public var before: Int64?
    public var beforeId: Int?
    public var limit = 50

    public init(selection: Selection, unreadOnly: Bool) {
        switch selection {
        case .all: unread = unreadOnly
        case .starred: starred = true
        case .folder(let name): folder = name; unread = unreadOnly
        case .feed(let id): feed = id; unread = unreadOnly
        }
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let feed { items.append(URLQueryItem(name: "feed", value: String(feed))) }
        if let folder { items.append(URLQueryItem(name: "folder", value: folder)) }
        if unread { items.append(URLQueryItem(name: "unread", value: "1")) }
        if starred { items.append(URLQueryItem(name: "starred", value: "1")) }
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "q", value: search)) }
        if let before { items.append(URLQueryItem(name: "before", value: String(before))) }
        if let beforeId { items.append(URLQueryItem(name: "before_id", value: String(beforeId))) }
        return items
    }
}
