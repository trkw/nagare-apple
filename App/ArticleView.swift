import NagareKit
import SwiftUI

struct ArticleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let entry: Entry

    @State private var translation: Translation?
    @State private var showTranslation = false
    @State private var busy: Busy?
    @State private var speech = Speech()
    @State private var handoff = false

    enum Busy { case translate, fullText }

    private var shown: (title: String, content: String) {
        if showTranslation, let translation { return (translation.title, translation.content) }
        return (entry.displayTitle, entry.content ?? "")
    }

    private var byline: String {
        var parts = [entry.feedTitle]
        if let author = entry.author, !author.isEmpty { parts.append(author) }
        parts.append(entry.publishedDate.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(byline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(shown.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
            }
            .padding(.horizontal)
            .padding(.top)
            if entry.content == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HTMLView(html: shown.content, baseURL: entry.url.flatMap(URL.init(string:)))
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .toolbar { toolbar }
        .sheet(isPresented: $handoff) { HandoffSheet(entry: entry) }
        .onDisappear { speech.stop() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.setStarred(entry, !entry.isStarred) } label: {
                Label("あとで読む", systemImage: entry.isStarred ? "star.fill" : "star")
            }
            Button { model.setRead(entry, !entry.isRead) } label: {
                Label(entry.isRead ? "未読にする" : "既読にする", systemImage: entry.isRead ? "circle" : "checkmark.circle")
            }
            Button(action: toggleTranslation) {
                Label(showTranslation ? "原文" : "翻訳", systemImage: busy == .translate ? "hourglass" : "character.bubble")
            }
            .disabled(busy != nil)
            Button(action: toggleSpeech) {
                Label(speech.speaking ? "停止" : "読み上げ", systemImage: speech.speaking ? "stop.fill" : "speaker.wave.2")
            }
            Menu {
                if entry.url != nil {
                    Button("全文を取得", systemImage: "doc.text.magnifyingglass", action: loadFullText).disabled(busy != nil)
                }
                Button("エージェントに送る", systemImage: "paperplane") { handoff = true }
                if let url = entry.url.flatMap(URL.init(string:)) {
                    Button("元の記事を開く", systemImage: "safari") { openURL(url) }
                    ShareLink(item: url)
                }
            } label: {
                Label("その他", systemImage: "ellipsis.circle")
            }
        }
    }

    private func toggleTranslation() {
        if showTranslation { showTranslation = false; return }
        if translation != nil { showTranslation = true; return }
        guard let client = model.client else { return }
        busy = .translate
        Task {
            defer { busy = nil }
            do {
                translation = try await client.translate(entryId: entry.id)
                showTranslation = true
            } catch {
                model.report(error)
            }
        }
    }

    private func loadFullText() {
        guard let client = model.client else { return }
        busy = .fullText
        Task {
            defer { busy = nil }
            do {
                let content = try await client.fullText(entryId: entry.id)
                model.patch(entry.id) { $0.content = content }
                translation = nil
                showTranslation = false
            } catch {
                model.report(error)
            }
        }
    }

    private func toggleSpeech() {
        if speech.speaking { speech.stop(); return }
        speech.speak("\(shown.title)。\(HTMLText.plain(shown.content))")
    }
}

struct HandoffSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    @State private var note = ""
    @State private var agent = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("メモ") {
                    TextField("気づいたこと、調べてほしいことなど", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    TextField("送り先（空ならどのエージェントでも）", text: $agent)
                        .autocorrectionDisabled()
                } footer: {
                    Text("エージェントが次に get_handoffs で確認したときに受け取ります。")
                }
            }
            .navigationTitle("エージェントに送る")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送る") {
                        sending = true
                        Task {
                            defer { sending = false }
                            do {
                                try await model.client?.handoff(entryIds: [entry.id], note: note, toAgent: agent)
                                dismiss()
                            } catch {
                                model.report(error)
                            }
                        }
                    }
                    .disabled(sending)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
    }
}
