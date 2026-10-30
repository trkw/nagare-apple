import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var server = "nagare.trkw.dev"
    @State private var token = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nagare").font(.largeTitle.weight(.semibold))
            Text("サーバーで作ったアプリ用トークン（bun run token:create --kind app）を入力してください。")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("サーバー", text: $server)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            SecureField("トークン（ngr_...）", text: $token)
            Button {
                busy = true
                Task {
                    await model.login(server: server, token: token)
                    busy = false
                }
            } label: {
                Text(busy ? "確認中…" : "ログイン").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || token.isEmpty || server.isEmpty)
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 360)
        .padding(24)
    }
}
