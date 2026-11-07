# 開発・検証

## 構成

- `traQ Watch Watch App/Core/`: UIや認証状態に依存しないモデル・本文解析・表示要素の組み立て・URLポリシー・画像取得/縮小。アプリの既定MainActorから明示的に分離している。
- `AuthManager`: 認証、APIリクエスト、ログイン先の正規ファイルAPIへのCookie付与。外部画像にCookieは付けない。
- `ActivityStore`: 最新20件と投稿者情報、パス、アイコン、解析済み本文を保持。本文解析は取得時にバックグラウンドで行う。
- `MessageContentView`: 解析結果をSwiftUIで描画し、スポイラーの開閉状態を保持。
- `MessageMediaStore`: スタンプ・本文画像の取得待ち行列、同一リソースの重複排除、メモリキャッシュ。失敗結果も保持し、Pull to Refresh・右上の再読み込み・Retry時に再試行する。

## 本文の解析と描画

Foundationの`AttributedString(markdown:options:)`を`inlineOnlyPreservingWhitespace`で利用し、装飾・改行を解析する。外部ライブラリは使用しない。解析結果からURLの操作属性を取り除き、リンクは青い太字で描画する。スポイラーは標準`Button`で開閉する。スポイラーを含む短い段落だけ`InlineFlowLayout`で折り返し、通常の段落は標準`Text`の組版を利用する。大量の要素になる段落は縦配置へフォールバックする。

コードフェンスは標準Markdown解析へ渡さず、等幅・横スクロールで表示する。スポイラー、traQ参照、スタンプ、画像は保護トークンを介して周囲の装飾を引き継ぐ。閉じたスポイラー内の画像・スタンプは取得しない。

traQへの画像アップロードはMarkdown画像ではなく`https://サーバー/files/{UUID}`の通常リンクとして本文に入る場合がある。公式クライアントと同様、ログイン先と同一オリジンのファイルリンクを添付として扱い、`GET /files/{fileId}/meta`のMIMEで画像かどうかを判定する。画像は利用可能な画像サムネイルを優先し、なければサイズ制限内の原画像を取得する。画像以外は操作不可のリンク表示を残す。コード・KaTeX・不正な独自記法内のURLは取得しない。

画像は段落内の元の順序で独立した行へ展開し、スタンプは`Text`内の画像として表示する。同じスタンプのサイズ違いも取得した画像を共用する。

標準絵文字も`/stamps`に含まれるが、公式サーバーはTwemojiのSVGを保存している。`isUnicode`がtrueのスタンプは`fileId`からファイルメタ情報を取得し、`1f389.svg`等のファイル名を検証してUnicodeへ変換し、システム絵文字として表示する。名前の手書き対応表やSVG描画ライブラリは使わない。変換結果はスタンプ名で保持し、サイズ違いでも再取得しない。

## 意図的な制限

- KaTeX、見出し/リスト/表などのブロック装飾は対象外。KaTeXは元の記法を残す。
- スポイラーは`!!…!!`。同じ区切り文字での曖昧なネストは対応しない。基本装飾・インラインコードとの混在は対応する。
- 通常スタンプと`:@user:`に対応する。既知のサイズ効果を反映し、アニメーション効果は静止画へ縮退する。色スタンプ・Webhookアイコン記法は対象外。
- GIF等は先頭フレームのみ。標準Unicodeスタンプは上記の方法で表示する。独自SVGなどImageIOで扱えない形式は失敗表示/元のスタンプ記法にフォールバックする。標準絵文字の見た目と収録範囲はwatchOSのシステムフォントに依存する。
- 外部画像はHTTPSのみ。301/302/303/307/308の転送は各転送先を検証して最大5回まで追跡する。別オリジンへ移る際はCookie・Authorizationを除去し、元のホストへ戻っても復元しない。HTTPへのダウングレードは拒否する。資格情報付きURL、IPアドレス・ローカルホスト名、標準外ポートは拒否する。ログイン先の`/files/{UUID}`は正規の`/api/v3/files/{UUID}`へ変換する。
- 圧縮画像は2MiBまで。画素寸法は各辺8192以下・合計4000万画素以下。本文画像は最大480px、スタンプは最大120px、投稿者アイコンは最大96pxへ縮小する。
- 本文は32768文字/65536 UTF-8バイトを超えると、省略を明示してraw表示する。解析の走査量・特殊トークン数・ブロック数にも上限を設ける。
- 本文メディアは同時3件、待ち行列64件。キャッシュはNSCacheの8MiB/64件を目安とし、OSによる破棄後は必要時に再取得する。投稿者アイコンとパスは表示中の最新20件分を保持する。
- ユーザー一覧はログイン中にキャッシュし、未取得ユーザーが登場した場合に再取得する。表示名や既存アイコンの編集は直ちには反映しない。

## 自動検証

Xcode 26系とSwift 6.2以上を利用する。ルートのSwift PackageはアプリのCoreを直接テストするためのもので、アプリに依存パッケージを追加するものではない。

```sh
swift test --scratch-path /tmp/traq-message-tests
```

署名なしのWatch単体ビルドはルートの`AGENTS.md`を参照。Simulator向けは`-sdk watchsimulator`を使い、`SYMROOT`と`OBJROOT`を実機向けと別にする。Release構成でもビルドし、DEBUG専用画面が本番構成に入らないことを確認する。

## Simulatorでの表示確認

DEBUG構成で、起動引数`--message-preview=basic`を指定すると、ログインも外部通信も行わないサンプル画面を表示する。値は`basic`、`spoiler`、`revealed`、`code`、`reference`、`stamp`、`image`、`failure`、`loading`、`fallback`。

```sh
xcrun simctl install booted '/tmp/traq-watch-sim-products/Debug-watchsimulator/traQ Watch Watch App.app'
xcrun simctl launch booted jp.trap.traQ-Watch.watchkitapp --message-preview=basic
```

`revealed`は初期状態でスポイラーが開いた表示を確認するためのもの。実際のタップ操作の検証とは区別する。`failure`と`loading`も固定状態のサンプルであり、実サーバーの通信確認を代替しない。

## 実機で確認する項目

- 実サーバーへのログイン、再起動後のKeychain復元、ログアウト、セッション失効。
- 投稿者の表示名・アイコン、`#times/26/aorinngo`形式のパス。
- Pull to Refresh、取得失敗後のRetry、成功済みデータ/キャッシュの保持。
- 文中スポイラーをタップして開く/閉じる操作。コードの横スクロールと縦スクロールの共存。
- 実サーバーのスタンプ画像と認証が必要な添付画像、外部HTTPS画像、通信切断時の表示。
- 小さい画面サイズでの折り返し・VoiceOver・多数の画像のメモリ使用量。

## 参照仕様

- traQ v3 API: https://github.com/traPtitech/traQ/blob/master/docs/v3-api.yaml
- 公式Unicodeスタンプ導入処理: https://github.com/traPtitech/traQ/blob/master/utils/twemoji/installer.go
- 公式スタンプ実装: https://github.com/traPtitech/traq-markdown-it/blob/master/src/stamp.ts
- 公式の添付URL抽出: https://github.com/traPtitech/traq-markdown-it/blob/master/src/embeddingExtractor.ts
- 公式の添付画像表示: https://github.com/traPtitech/traQ_S-UI/blob/master/src/components/Main/MainView/MessageElement/Embeddings/MessageFileListImage.vue
- 公式エフェクト名: https://github.com/traPtitech/traq-markdown-it/blob/master/src/data/stampEffects.ts
- Appleの空白保持オプション: https://developer.apple.com/documentation/foundation/attributedstring/markdownparsingoptions/interpretedsyntax-swift.enum/inlineonlypreservingwhitespace
- AppleのLayoutプロトコル: https://developer.apple.com/documentation/swiftui/layout

## 入力とツールバー

URL・ユーザー名は適切な`textContentType`を設定し、自動大文字化・自動補正を無効にする。watchOSではアプリからキーボード配列や入力言語を強制できないため、QWERTYの利用にはWatch側の英語キーボード選択が必要な場合がある。

アクティビティ画面は左上がログアウト、右上が再読み込み。再読み込みはPull to Refreshと同じ取得処理を使用し、通信中は重複操作を無効にする。
