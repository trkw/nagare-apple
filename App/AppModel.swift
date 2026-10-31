import Foundation
import NagareKit
import Observation

@MainActor
@Observable
final class AppModel {
    var client: APIClient?
    var me: Me?
    var feeds: [Feed] = []
    // The views reload the list when selection or unreadOnly change, and open the entry
    // when selectedEntryID changes (see ReaderView).
    var selection: Selection? = .all
    var unreadOnly = true
    var entries: [Entry] = []
    var selectedEntryID: Entry.ID?
    var hasMore = false
    var loading = false
    var error: String?

    /// Bumped per list request so a slow response for an old query is dropped.
    private var requestSeq = 0
    /// Bumped on login and logout so responses from a previous account or server are dropped.
    private var session = 0
    private let pageSize = 50

    init() {
        if let server = Credentials.server, let token = Credentials.token {
            client = APIClient(baseURL: server, token: token)
            Task { await start() }
        }
    }

    var selectedEntry: Entry? {
        guard let id = selectedEntryID else { return nil }
        return entries.first { $0.id == id }
    }

    var folders: [(name: String?, feeds: [Feed])] {
        let grouped = Dictionary(grouping: feeds, by: \.folder)
        return grouped.keys
            .sorted { a, b in
                switch (a, b) {
                case (nil, _): return false
                case (_, nil): return true
                case let (a?, b?): return a.localizedStandardCompare(b) == .orderedAscending
                }
            }
            .map { (name: $0, feeds: grouped[$0]!.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }) }
    }

    var totalUnread: Int { feeds.reduce(0) { $0 + $1.unread } }

    var title: String {
        switch selection {
        case .all, nil: return "すべて"
        case .starred: return "あとで読む"
        case .folder(let name): return name
        case .feed(let id): return feeds.first { $0.id == id }?.displayTitle ?? ""
        }
    }

    // MARK: Session

    func login(server: String, token: String) async {
        var text = server.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else {
            error = "サーバーのURLが正しくありません"
            return
        }
        let candidate = APIClient(baseURL: url, token: token.trimmingCharacters(in: .whitespaces))
        do {
            me = try await candidate.me()
            Credentials.server = url
            Credentials.token = candidate.token
            session += 1
            client = candidate
            await start()
            if PushManager.shared.enabled { _ = await PushManager.shared.enable() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() {
        // The device stops getting this account's notifications.
        if PushManager.shared.enabled { Task { await PushManager.shared.disable() } }
        session += 1
        requestSeq += 1
        Credentials.token = nil
        client = nil
        me = nil
        feeds = []
        entries = []
        selectedEntryID = nil
    }

    private func start() async {
        await refreshFeeds()
    }

    func reload() async {
        await refreshFeeds()
        await loadEntries()
    }

    func refreshFeeds() async {
        guard let client else { return }
        let current = session
        do {
            let result = try await client.feeds()
            if current == session { feeds = result }
        } catch {
            if current == session { report(error) }
        }
    }

    // MARK: Entries

    func loadEntries(more: Bool = false) async {
        guard let client else { return }
        requestSeq += 1
        let seq = requestSeq
        loading = true
        defer { if seq == requestSeq { loading = false } }
        var query = EntryQuery(selection: selection ?? .all, unreadOnly: unreadOnly)
        query.limit = pageSize
        if more, let last = entries.last {
            query.before = last.publishedAt
            query.beforeId = last.id
        }
        do {
            let page = try await client.entries(query)
            guard seq == requestSeq else { return }
            if more {
                entries += page
            } else {
                entries = page
                selectedEntryID = nil
            }
            hasMore = page.count == pageSize
        } catch {
            if seq == requestSeq { report(error) }
        }
    }

    struct ListKey: Hashable {
        let selection: Selection?
        let unreadOnly: Bool
        let signedIn: Bool
    }

    var listKey: ListKey { ListKey(selection: selection, unreadOnly: unreadOnly, signedIn: client != nil) }

    func open(_ id: Entry.ID) async {
        guard let client, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let current = session
        if entries[index].content == nil {
            do {
                let full = try await client.entry(id: id)
                guard current == session else { return }
                if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].content = full.content ?? "" }
            } catch {
                if current == session { report(error) }
                return
            }
        }
        if let entry = entries.first(where: { $0.id == id }), !entry.isRead { setRead(entry, true) }
    }

    /// Opens an entry that may not be in the current list, e.g. from a notification.
    func openEntry(id: Int) async {
        guard let client else { return }
        if !entries.contains(where: { $0.id == id }) {
            let current = session
            do {
                let entry = try await client.entry(id: id)
                guard current == session else { return }
                entries.insert(entry, at: 0)
            } catch {
                report(error)
                return
            }
        }
        selectedEntryID = id
    }

    func setNotify(_ feed: Feed, _ on: Bool) async {
        guard let client else { return }
        do {
            let updated = try await client.setNotify(feedId: feed.id, on)
            if let i = feeds.firstIndex(where: { $0.id == feed.id }) { feeds[i] = updated }
        } catch {
            report(error)
        }
    }

    func patch(_ id: Entry.ID, _ change: (inout Entry) -> Void) {
        if let i = entries.firstIndex(where: { $0.id == id }) { change(&entries[i]) }
    }

    func setRead(_ entry: Entry, _ read: Bool) {
        patch(entry.id) { $0.isRead = read }
        adjustUnread(feedId: entry.feedId, by: read ? -1 : 1)
        Task {
            do {
                try await client?.setState(ids: [entry.id], read: read)
            } catch {
                patch(entry.id) { $0.isRead = !read }
                adjustUnread(feedId: entry.feedId, by: read ? 1 : -1)
                report(error)
            }
        }
    }

    func setStarred(_ entry: Entry, _ starred: Bool) {
        patch(entry.id) { $0.isStarred = starred }
        Task {
            do {
                try await client?.setState(ids: [entry.id], starred: starred)
            } catch {
                patch(entry.id) { $0.isStarred = !starred }
                report(error)
            }
        }
    }

    func toggleStar() {
        if let entry = selectedEntry { setStarred(entry, !entry.isStarred) }
    }

    func toggleRead() {
        if let entry = selectedEntry { setRead(entry, !entry.isRead) }
    }

    func move(by offset: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedEntryID.flatMap { id in entries.firstIndex { $0.id == id } }
        let next = current.map { $0 + offset } ?? 0
        guard entries.indices.contains(next) else { return }
        selectedEntryID = entries[next].id
    }

    private func adjustUnread(feedId: Int, by delta: Int) {
        guard let i = feeds.firstIndex(where: { $0.id == feedId }) else { return }
        feeds[i].unread = max(0, feeds[i].unread + delta)
    }

    // MARK: Feeds

    /// Subscribes, or reports that the URL has no feed so the caller can offer to watch the page.
    func subscribe(url: String) async -> SubscribeOutcome {
        guard let client else { return .failed }
        do {
            let feed = try await client.subscribe(url: url)
            await refreshFeeds()
            selection = .feed(feed.id)
            return .subscribed
        } catch let e as APIError where e.message.hasPrefix("no feed found") {
            return .noFeed
        } catch {
            report(error)
            return .failed
        }
    }

    func watchPage(url: String) async -> Bool {
        guard let client else { return false }
        do {
            let feed = try await client.watchPage(url: url)
            await refreshFeeds()
            selection = .feed(feed.id)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func unsubscribe(_ feed: Feed) async {
        do {
            try await client?.unsubscribe(feedId: feed.id)
            if selection == .feed(feed.id) { selection = .all }
            await refreshFeeds()
        } catch {
            report(error)
        }
    }

    func report(_ error: Error) {
        if (error as? URLError)?.code == .cancelled { return }
        self.error = error.localizedDescription
    }
}

enum SubscribeOutcome {
    case subscribed, noFeed, failed
}
