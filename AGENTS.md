# traQ Watch

SwiftUIで作るwatchOS専用のtraQアクティビティ閲覧アプリ。SwiftUIの学習も目的とするため、変更理由と重要な概念を簡潔に説明する。

- アプリコード: `traQ Watch Watch App/`。iPhoneコンパニオンアプリは作らない。
- 認証・API通信は既存の`AuthManager`を利用する。HTTPSのみ許可し、パスワードは保存しない。
- 更新は初回表示と手動操作（Pull to Refresh・右上の再読み込み・失敗時のRetry）のみ。定期更新・WebSocketは採用しない。
- チャンネルのフルパスは必ず`GET /api/v3/channels/{channelId}/path`で取得する。全チャンネルの親をたどる方式には戻さない。
- 同一ユーザーのアイコンと同一チャンネルのパスはメモリキャッシュを利用する。
- 取得処理と表示処理を分離し、SwiftUI標準機能を優先する。不要な外部ライブラリを追加しない。
- 引用カードは一段まで。引用内のスタンプは表示するが、画像・添付・次の引用は展開しない。取得失敗時は元リンクを残す（詳細は開発ガイド）。
- 最新20件を新しい順に表示。リンク・メンション・チャンネル参照はタップ不可。KaTeXは非対応で元の文字列へフォールバックする。
- マイルストーンはM2→M7の順に実装・検証する。各段階でユーザー確認を待つ必要はない。

## マイルストーン

- M0: ログイン・Keychainでのセッション復元・ログアウト。
- M1: 最新20件のアクティビティ・Pull to Refresh。
- M2: 投稿者アイコン・表示名優先・専用APIのチャンネルフルパス・本文・投稿日時。ユーザー・アイコン・パスのメモリキャッシュ。
- M3: 太字・斜体・打消し線・インラインコード・改行/段落・青い太字のリンク。解析とSwiftUI描画を分離。
- M4: 文中や装飾と混在する`!!スポイラー!!`のタップ開閉。コードブロックの等幅表示・改行/インデント保持・長いコードの横スクロール。
- M5: traQの`!{"type":"channel/user/group","raw":"…","id":"…"}`を解析し、rawを青い太字で表示。
- M6: 公式実装に基づくスタンプ解析・API画像取得・文中表示・キャッシュ。`isUnicode`の標準スタンプはSVGファイル名からUnicodeへ変換して表示する（詳細は開発ガイド）。
- M7: Markdown画像と同一traQサーバーの`/files/{UUID}`添付リンク（メタ情報で画像を判定）・画面幅に応じた表示・読込中/失敗表示・再取得抑制。外部画像はHTTPS・リダイレクト・サイズ/メモリ制限を守る。

本文は信頼できない入力。壊れた記法や未対応記法で本文全体を失わず、安全にフォールバックする。解析・メディア処理を自動テストし、実機未検証の動作を成功と報告しない。

公式仕様: https://apis.trap.jp/ 。v3定義は https://github.com/traPtitech/traQ/blob/master/docs/v3-api.yaml 。

Watchアプリ単体の署名なしビルド（実機での通信・操作検証は別途必要）:

```sh
xcodebuild -project 'traQ Watch.xcodeproj' -target 'traQ Watch Watch App' -configuration Debug -sdk watchos SYMROOT=/tmp/traq-watch-products OBJROOT=/tmp/traq-watch-intermediates CODE_SIGNING_ALLOWED=NO build
```

検証コマンド: `swift test --scratch-path /tmp/traq-message-tests`。
解析方式・メディアの制限・Simulatorのサンプル画面・実機確認項目は[開発ガイド](docs/DEVELOPMENT.md)を参照する。

TestFlightの署名・CI変更時は[配布手順](docs/TESTFLIGHT.md)を読む。Watch-onlyの配布用コンテナとWatch本体はBundle ID/署名プロファイルが異なる。アップロード用ワークフローは手動実行・内部テスト専用。
