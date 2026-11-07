import SwiftUI
import UIKit

/// 引用は一段だけ表示し、カード内の本文から画像や次の引用を取得しない。
struct QuoteCardView: View {
    let preview: MessageQuotePreview
    let user: TraQUser?
    let icon: UIImage?
    let channelPath: String?
    @ObservedObject var media: MessageMediaStore

    private var stamps: [StampReference] {
        preview.excerpt.compactMap { span in
            if case .stamp(let stamp) = span.attachment { return stamp }; return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.blue)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Group {
                        if let icon { Image(uiImage: icon).resizable().scaledToFill() }
                        else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                    Text(verbatim: user.map { $0.displayName.isEmpty ? $0.name : $0.displayName } ?? "Unknown")
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                Text(verbatim: channelPath ?? "#unknown")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                excerpt
                    .font(.caption)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(preview.message.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityHint("引用メッセージ")
        .task(id: stamps) {
            for stamp in stamps { media.request(.stamp(stamp.name)) }
        }
    }

    private var excerpt: Text {
        preview.excerpt.reduce(Text("")) { result, span in
            var text = Text(verbatim: span.text)
            if case .stamp(let stamp) = span.attachment {
                // 大きなサイズ効果は引用カードの3行を圧迫しないサイズに収める。
                let size = min(stamp.pointSize, 20)
                if let emoji = media.unicodeEmoji(for: stamp) {
                    text = Text(verbatim: emoji).font(.system(size: size))
                } else if let image = media.stampImage(StampReference(name: stamp.name, effects: ["small"], raw: stamp.raw)) {
                    text = Text(Image(uiImage: image)).baselineOffset(-3)
                }
            } else {
                if span.style.contains(.bold) { text = text.bold() }
                if span.style.contains(.italic) { text = text.italic() }
                if span.style.contains(.strike) { text = text.strikethrough() }
                if span.style.contains(.code) { text = text.font(.system(.caption, design: .monospaced)) }
                if span.style.contains(.reference) { text = text.foregroundColor(.blue) }
            }
            return Text("\(result)\(text)")
        }
    }
}
