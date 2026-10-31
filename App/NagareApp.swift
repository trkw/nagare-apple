import SwiftUI

@main
struct NagareApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .commands { ReaderCommands(model: model) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.client == nil {
                LoginView()
            } else {
                ReaderView()
            }
        }
        .alert("エラー", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }
}

/// Menu commands. Single-key shortcuts (j / k / s / m) live in ReaderView so they never fire while typing.
struct ReaderCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("記事") {
            Button("再読み込み") { Task { await model.reload() } }.keyboardShortcut("r", modifiers: .command)
        }
    }
}
