import NagareKit
import SwiftUI

struct ReaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            EntryListView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let entry = model.selectedEntry {
                ArticleView(entry: entry)
                    .id(entry.id)
            } else {
                ContentUnavailableView("記事を選んでください", systemImage: "doc.text", description: Text("j / k で移動"))
            }
        }
        .task(id: model.listKey) { await model.loadEntries() }
        .onChange(of: model.selectedEntryID) { _, id in
            if let id { Task { await model.open(id) } }
        }
        // Same keys as the web version, for iPad keyboards and the Mac.
        .onKeyPress(characters: CharacterSet(charactersIn: "jkmsv"), phases: .down) { press in
            switch press.characters {
            case "j": model.move(by: 1)
            case "k": model.move(by: -1)
            case "s": model.toggleStar()
            case "m": model.toggleRead()
            case "v":
                guard let url = model.selectedEntry?.url.flatMap(URL.init(string:)) else { return .ignored }
                openURL(url)
            default: return .ignored
            }
            return .handled
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var subscribing = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                Label("すべて", systemImage: "tray.full")
                    .badge(model.totalUnread)
                    .tag(Selection.all)
                Label("あとで読む", systemImage: "star")
                    .tag(Selection.starred)
            }
            ForEach(model.folders, id: \.name) { group in
                Section(group.name ?? "フォルダなし") {
                    if let name = group.name {
                        Label("\(name) のすべて", systemImage: "folder")
                            .tag(Selection.folder(name))
                    }
                    ForEach(group.feeds) { feed in
                        FeedRow(feed: feed, me: model.me?.name)
                            .tag(Selection.feed(feed.id))
                            .contextMenu {
                                Button("購読をやめる", role: .destructive) { Task { await model.unsubscribe(feed) } }
                            }
                    }
                }
            }
        }
        .navigationTitle("Nagare")
        .refreshable { await model.reload() }
        .toolbar {
            ToolbarItem {
                Button { subscribing = true } label: { Label("購読", systemImage: "plus") }
            }
            ToolbarItem {
                Menu {
                    Button("ログアウト", role: .destructive) { model.logout() }
                } label: {
                    Label("その他", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $subscribing) { SubscribeSheet() }
    }
}

struct FeedRow: View {
    let feed: Feed
    let me: String?

    var body: some View {
        HStack {
            Text(feed.displayTitle)
                .lineLimit(1)
                .foregroundStyle(feed.lastError == nil ? Color.primary : Color.red)
            Spacer()
            if let by = feed.addedBy, by != me {
                Text(by)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Capsule().stroke(.secondary.opacity(0.5)))
                    .foregroundStyle(.secondary)
            }
            if feed.unread > 0 {
                Text("\(feed.unread)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .help(feed.lastError.map { "取得エラー: \($0)" } ?? feed.reason ?? "")
    }
}

struct EntryListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedEntryID) {
            if let reason = currentFeed?.reason {
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.entries) { entry in
                EntryRow(entry: entry)
                    .tag(entry.id)
                    .swipeActions(edge: .leading) {
                        Button { model.setStarred(entry, !entry.isStarred) } label: {
                            Label("あとで読む", systemImage: entry.isStarred ? "star.slash" : "star")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button { model.setRead(entry, !entry.isRead) } label: {
                            Label(entry.isRead ? "未読" : "既読", systemImage: entry.isRead ? "circle" : "checkmark.circle")
                        }
                    }
            }
            if model.hasMore {
                Button("さらに読み込む") { Task { await model.loadEntries(more: true) } }
                    .disabled(model.loading)
            }
        }
        .overlay {
            if !model.loading && model.entries.isEmpty {
                ContentUnavailableView("記事はありません", systemImage: "tray")
            }
        }
        .navigationTitle(model.title)
        .refreshable { await model.reload() }
        .toolbar {
            if model.selection != .starred {
                ToolbarItem {
                    Toggle(isOn: $model.unreadOnly) { Label("未読のみ", systemImage: "line.3.horizontal.decrease.circle") }
                }
            }
        }
    }

    private var currentFeed: Feed? {
        if case .feed(let id) = model.selection { return model.feeds.first { $0.id == id } }
        return nil
    }
}

struct EntryRow: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.feedTitle).lineLimit(1)
                Spacer()
                Text(entry.publishedDate, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if entry.isStarred { Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange) }
                Text(entry.displayTitle)
                    .font(.body.weight(entry.isRead ? .regular : .semibold))
                    .foregroundStyle(entry.isRead ? .secondary : .primary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SubscribeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var busy = false
    @State private var noFeed = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("サイトかフィードのURL", text: $url)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onChange(of: url) { noFeed = false }
                if noFeed {
                    Section {
                        Text("フィードが見つかりませんでした。ページの更新を見張ることもできます。")
                            .foregroundStyle(.secondary)
                        Button("このページを見張る") { run { await model.watchPage(url: url) } }
                    }
                }
            }
            .navigationTitle("購読")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "探しています…" : "購読") {
                        run {
                            switch await model.subscribe(url: url) {
                            case .subscribed: return true
                            case .noFeed: noFeed = true; return false
                            case .failed: return false
                            }
                        }
                    }
                    .disabled(busy || url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 200)
        #endif
    }

    private func run(_ action: @escaping () async -> Bool) {
        busy = true
        Task {
            let done = await action()
            busy = false
            if done { dismiss() }
        }
    }
}
