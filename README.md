# Nagare for Apple

[Nagare](https://github.com/trkw/nagare) の iOS・iPadOS・macOS 版です。1つの SwiftUI プロジェクトで3つのプラットフォームに対応します。

## できること

- サーバーURLとアプリ用トークンでログイン（トークンはキーチェーンに保存）
- フォルダ・フィード・記事・本文の3カラム（iPhoneでは画面遷移、iPadとMacでは横並び）
- 未読のみ表示、あとで読む、既読・未読、スワイプ操作
- 翻訳（原文と切り替え）、全文取得、日本語の読み上げ
- エージェントに送る（メモつき）、元の記事を開く、共有
- 購読の追加。フィードのないページは「このページを見張る」
- iPadのキーボードとMacでは j / k（移動）、s（あとで読む）、m（既読/未読）、v（元の記事）、⌘R（再読み込み）

## 構成

```
Sources/NagareKit   UIを持たない部分（APIクライアント、モデル、キーチェーン）
Tests/NagareKitTests
App                 SwiftUIのアプリ本体（iOS・iPadOS・macOS共通）
project.yml         XcodeGenの設定
```

対応OSは iOS / iPadOS 17、macOS 14 以降です。

## ビルド

```sh
brew install xcodegen
xcodegen            # Nagare.xcodeproj を生成
open Nagare.xcodeproj
```

Xcodeで実行先（iPhone、iPad、My Mac）を選んで実行します。実機で動かすときは Signing & Capabilities でチームを選んでください。

APIクライアントのテストは `swift test` で実行できます。

ログイン画面では、サーバーで作ったアプリ用トークンを入力します。

```sh
# trkw/nagare の apps/api で
bun run token:create --name iphone --kind app --remote
```

## 通知（APNs）

1. Apple Developer の Keys で「Apple Push Notifications service (APNs)」を有効にしたキーを作り、.p8 をダウンロードします。
2. サーバー側（trkw/nagare）に設定します。

   ```sh
   # apps/api で
   bunx wrangler secret put APNS_KEY      # .p8 の中身をそのまま貼る
   ```

   `wrangler.jsonc` の `APNS_KEY_ID`（キーID）、`APNS_TEAM_ID`（チームID）、`APNS_TOPIC`（バンドルID、`dev.trkw.nagare`）を埋めます。
3. Xcode の Signing & Capabilities に Push Notifications が出ていることを確認します（`Config/*.entitlements` で指定済み）。

アプリではサイドバーのメニューの「このデバイスで通知を受け取る」で端末を登録し、フィードの右クリック（長押し）メニューの「新着を通知する」で通知するフィードを選びます。Debugビルドは sandbox、Releaseビルドは本番のAPNsに登録されます。
