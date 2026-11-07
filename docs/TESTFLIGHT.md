# GitHub ActionsでTestFlightへ配布

`.github/workflows/testflight.yml`を手動実行すると、Coreテスト → 配布設定テスト → 署名付きArchive → IPA生成/検証 → App Store Connectへのアップロードを行う。`../FirstApp`で成功している証明書・プロファイル・`altool`の方式を基に、Watch-onlyアプリの2ターゲットに対応している。

このワークフローは**TestFlightの内部テスト専用**。Export設定の`testFlightInternalTestingOnly`がtrueなので、このビルドを外部テストやApp Store公開へ流用することはできない。アップロード後のApple側の処理完了や、内部テストグループへのビルド追加はApp Store Connectで確認する。内部テスターはそのアプリにアクセスできるApp Store Connectユーザーである必要がある。

## App IDとプロファイル

このプロジェクトは次の2ターゲットを署名する。

| 用途 | Bundle ID | GitHub Secret |
|---|---|---|
| 配布用コンテナ | `jp.trap.traQ-Watch` | `APPLE_PROVISIONING_PROFILE_BASE64` |
| Watchアプリ本体 | `jp.trap.traQ-Watch.watchkitapp` | `APPLE_WATCH_PROVISIONING_PROFILE_BASE64` |

コンテナはXcodeのWatch-onlyテンプレートが作る配布用ターゲットで、iPhone向け画面やコンパニオン機能は追加していない。Archive先は`generic/platform=watchOS`だが、コンテナ自身はiphoneos SDKで構築される。

Apple Developerで両方の明示的App IDを登録し、各ID用のApp Store Connect配布プロファイルを作成する。両方とも同じTeamと使用するApple Distribution証明書に対応させる。FirstApp用のプロファイルはBundle IDが異なるため流用できない。

App Store Connectで新規アプリを作成するとき、プラットフォームは **iOS** を選ぶ（Watch-onlyアプリもApp Store Connect上ではiOSに分類される）。親のBundle ID **`jp.trap.traQ-Watch`** を選ぶ。watchkitapp側のIDを親アプリのレコードに指定しない。

## GitHub Secrets

このリポジトリの **Settings → Secrets and variables → Actions → Repository secrets** に登録する。

| Secret | 内容 |
|---|---|
| `APPLE_TEAM_ID` | Apple Developerの10文字のTeam ID |
| `APPLE_CERTIFICATE_BASE64` | 秘密鍵を含むApple Distribution証明書の`.p12`をBase64化した文字列 |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12`の書き出し時パスワード。パスワードなしの場合は空のままでよい |
| `APPLE_PROVISIONING_PROFILE_BASE64` | コンテナ用App Store Connect配布プロファイルのBase64 |
| `APPLE_WATCH_PROVISIONING_PROFILE_BASE64` | Watchアプリ用App Store Connect配布プロファイルのBase64 |
| `APPSTORE_API_KEY_ID` | App Store ConnectチームAPIキーのKey ID |
| `APPSTORE_API_ISSUER_ID` | そのAPIキーのIssuer ID |
| `APPSTORE_API_PRIVATE_KEY` | `AuthKey_XXXXXXXXXX.p8`の全文。Base64化せず改行込みで登録 |

Team・証明書・APIキーは、同じTeamならFirstAppで使ったものを再利用できる。APIキーには対象アプリへのアップロード権限が必要。別リポジトリのRepository secretsは自動共有されないため、こちらにも登録するか、対象リポジトリに許可したOrganization secretsを使用する。秘密情報はコミットしない。

`.p12`やプロファイルはMacで次のようにBase64化し、値をターミナルのログへ出さずコピーできる。

```sh
base64 -i distribution.p12 | pbcopy
base64 -i container.mobileprovision | pbcopy
base64 -i watch.mobileprovision | pbcopy
```

証明書は秘密鍵ごと`.p12`で書き出す。`.cer`だけでは署名できない。

## 実行

1. ワークフローをデフォルトブランチへpushする。
2. GitHubの **Actions → Upload traQ Watch to TestFlight → Run workflow** を開く。
3. 通常は`build_number`を空にして実行する。
4. App Store ConnectのTestFlightタブで処理結果を確認する。輸出コンプライアンスの回答を求められた場合は回答し、内部テストグループへ追加する。自動配布を設定しているグループでは、その設定に従う。

ビルド番号は`GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT`を両ターゲットに共通設定する。再実行時も番号が変わる。既に手元から大きな番号のビルドをアップロードしている場合は、入力欄でそれより大きい番号（例:`100`）を指定する。その後の実行でもApple側の既存番号を下回らない値にする。マーケティングバージョンは両ターゲットの`MARKETING_VERSION`で管理する。

Runnerは`macos-26`、Xcodeはローカルと同系列の26.3を明示選択している。RunnerからそのXcodeが廃止された場合は、公式Runnerイメージの収録一覧を確認して`DEVELOPER_DIR`を更新する。

## 署名と検証

- 共有Schemeは`traQ Watch.xcodeproj/xcshareddata/xcschemes/traQ Watch Watch App.xcscheme`。
- `scripts/testflight.py`がTeam・Bundle ID・有効期限・配布形式を検証し、SDK別の署名設定とExportOptionsを一時生成する。異なるターゲットへ同じプロファイルを一括指定しない。
- Archive/IPAにコンテナとWatchアプリが含まれ、Watch-only設定・両方のバージョン・WatchのAppIconが正しいことを検証してから送信する。
- 配布用の秘密鍵とプロファイルはRunner上で復元し、終了時に削除する。

ローカル検証:

```sh
swift test --scratch-path /tmp/traq-message-tests
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
xcodebuild archive \
  -project 'traQ Watch.xcodeproj' -scheme 'traQ Watch Watch App' \
  -configuration Release -destination 'generic/platform=watchOS' \
  -archivePath /tmp/traq-watch-ci.xcarchive -derivedDataPath /tmp/traq-watch-ci-derived \
  CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION=1.1
python3 scripts/testflight.py verify \
  '/tmp/traq-watch-ci.xcarchive/Products/Applications/traQ Watch.app' 1.1
```

署名なしArchiveの成功は、証明書を使う署名・IPAエクスポート・Appleへのアップロード成功を保証しない。Secrets設定後のGitHub Actionsで最終確認する。

参照:

- [新規アプリの作成とWatch-onlyのプラットフォーム](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Watch-onlyアプリの配布](https://help.apple.com/xcode/mac/current/en.lproj/devaba4602fd.html)
- [GitHub Actionsへの署名アセット導入](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [macOS 26 RunnerのXcode一覧](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
