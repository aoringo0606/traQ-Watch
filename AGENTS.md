# traQ Watch

SwiftUIで作るwatchOS専用のtraQアクティビティ閲覧アプリ。SwiftUIの学習も目的とするため、変更理由と重要な概念を簡潔に説明する。

- アプリコード: `traQ Watch Watch App/`。iPhoneコンパニオンアプリは作らない。
- 認証・API通信は既存の`AuthManager`を利用する。HTTPSのみ許可し、パスワードは保存しない。
- 更新は初回表示とPull to Refresh（失敗時はRetry）のみ。定期更新・WebSocketは採用しない。
- チャンネルのフルパスは必ず`GET /api/v3/channels/{channelId}/path`で取得する。全チャンネルの親をたどる方式には戻さない。
- 同一ユーザーのアイコンと同一チャンネルのパスはメモリキャッシュを利用する。
- 取得処理と表示処理を分離し、SwiftUI標準機能を優先する。不要な外部ライブラリを追加しない。
- M2は投稿者アイコン・表示名・チャンネルフルパス・raw本文・投稿日時。M2の確認が終わるまでMarkdown等のM3以降を進めない。
- 公式仕様: https://apis.trap.jp/ 。v3定義は https://github.com/traPtitech/traQ/blob/master/docs/v3-api.yaml 。

Watchアプリ単体の署名なしビルド（実機での通信・操作検証は別途必要）:

```sh
xcodebuild -project 'traQ Watch.xcodeproj' -target 'traQ Watch Watch App' -configuration Debug -sdk watchos SYMROOT=/tmp/traq-watch-products OBJROOT=/tmp/traq-watch-intermediates CODE_SIGNING_ALLOWED=NO build
```
