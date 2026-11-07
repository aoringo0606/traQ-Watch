#if DEBUG
import SwiftUI
import UIKit

/// `--message-preview=basic`などで起動する、認証・通信不要のSimulator検証画面。
struct RenderingPreviewView: View {
    @StateObject private var media: MessageMediaStore
    let mode: String
    private let blocks: [MessageBlock]

    init(mode: String) {
        self.mode = mode
        let media = MessageMediaStore(auth: AuthManager())
        media.installPreviewFixtures()
        _media = StateObject(wrappedValue: media)
        let samples: [String: String] = [
            "basic": "**太字** *斜体* ~~打消し~~ `code`\n[リンク](https://example.com)\n\n段落と改行を保持します。",
            "spoiler": "文中の **!!*秘密の文章*!!** です。\n!!画像も隠せます ![サンプル](https://example.com/sample.png)!!",
            "revealed": "文中の **!!*秘密の文章*!!** です。",
            "code": "コードの前\n```swift\n  let message = \"**raw**\"\n  // !!spoiler!! :sample:\n  print(message, message, message)\n```\nコードの後",
            "reference": #"!{"type":"user","raw":"@aorinngo_dev","id":"01a170b1-8dd2-7baf-bccd-9d3e0d659e79"} と **通常の文章**"#,
            "stamp": "文章中の :sample: スタンプ\n大きめ :sample.large: 小さめ :sample.small:\n未知の :unknown:",
            "image": "画像の前\n![サンプル](https://example.com/sample.png)\n画像の後",
            "failure": "![取得失敗のサンプル](https://example.com/missing.png)",
            "loading": "![読込中のサンプル](https://example.com/pending.png)",
            "fallback": #"KaTeXはそのまま: $\frac{a}{b}$ と !{"bad":true}"#
        ]
        blocks = MessageParser.parse(samples[mode] ?? samples["basic"]!)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                MessageContentView(blocks: blocks, media: media, revealed: mode == "revealed" ? [0] : [])
                    .padding(.horizontal, 8)
            }
            .navigationTitle("検証: \(mode)")
        }
    }
}

extension MessageMediaStore {
    func installPreviewFixtures() {
        let width = 160, height = 96
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(red: 0.1, green: 0.65, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 100, y: 50, width: 28, height: 28))
        context.setFillColor(CGColor(red: 0.25, green: 0.2, blue: 0.55, alpha: 1))
        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: 60, y: 70))
        context.addLine(to: CGPoint(x: 130, y: 0))
        context.fillPath()
        guard let cgImage = context.makeImage() else { return }
        installPreviewImage(UIImage(cgImage: cgImage), for: .image("https://example.com/sample.png"))
        installPreviewImage(UIImage(cgImage: cgImage), for: .stamp("sample"))
        installPreviewFailure("テスト用のHTTP 404", for: .image("https://example.com/missing.png"))
        installPreviewLoading(for: .image("https://example.com/pending.png"))
        installPreviewFailure("未知のスタンプ", for: .stamp("unknown"))
    }
}
#endif
