import SwiftUI

struct MessageContentView: View {
    private let blocks: [MessageBlock]
    @ObservedObject var media: MessageMediaStore
    @State private var spoilers = SpoilerState()

    init(blocks: [MessageBlock], media: MessageMediaStore, revealed: Set<Int> = []) {
        self.media = media
        self.blocks = blocks
        _spoilers = State(initialValue: SpoilerState(revealed: revealed))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let spans):
                    paragraph(spans)
                case .code(let code):
                    ScrollView(.horizontal) {
                        Text(verbatim: code)
                            .font(.system(.caption, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(6)
                    }
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("コードブロック")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: requestedMedia) {
            for resource in requestedMedia { media.request(resource) }
        }
    }

    private enum Piece {
        case text([MessageSpan])
        case image(MessageImage)
        case file(MessageFile)
    }

    private func pieces(_ spans: [MessageSpan]) -> [Piece] {
        var result: [Piece] = []
        var text: [MessageSpan] = []
        for span in MessagePresentation.visibleSpans(spans, revealed: spoilers.revealed) {
            if case .image(let image) = span.attachment {
                if !text.isEmpty { result.append(.text(text)); text = [] }
                result.append(.image(image))
            } else if case .file(let file) = span.attachment {
                if !text.isEmpty { result.append(.text(text)); text = [] }
                result.append(.file(file))
            } else { text.append(span) }
        }
        if !text.isEmpty { result.append(.text(text)) }
        return result
    }

    @ViewBuilder
    private func paragraph(_ spans: [MessageSpan]) -> some View {
        ForEach(Array(pieces(spans).enumerated()), id: \.offset) { _, piece in
            switch piece {
            case .text(let text): textParagraph(text)
            case .image(let image): imageView(image)
            case .file(let file):
                if case .notImage = media.phases[.file(file.url)] {
                    Text(verbatim: file.label).bold().foregroundStyle(.blue)
                } else {
                    imageView(MessageImage(url: file.url, alt: file.label), resource: .file(file.url))
                }
            }
        }
    }

    private enum FlowElement {
        case text(MessageSpan)
        case stamp(StampReference)
        case toggle(Int, String)
        case newline
    }

    private func flowElements(_ spans: [MessageSpan]) -> [FlowElement] {
        var result: [FlowElement] = []
        for span in spans {
            if case .spoiler(let id, _) = span.attachment {
                result.append(.toggle(id, "［表示］"))
            } else if let id = span.spoilerAction {
                result.append(.toggle(id, "［隠す］"))
            } else if case .stamp(let stamp) = span.attachment {
                result.append(.stamp(stamp))
            } else {
                var word = ""
                func flush() {
                    if !word.isEmpty { result.append(.text(MessageSpan(text: word, style: span.style))); word = "" }
                }
                for character in span.text {
                    if character == "\n" { flush(); result.append(.newline) }
                    else if character.isWhitespace || character.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) {
                        flush()
                        result.append(.text(MessageSpan(text: String(character), style: span.style)))
                    } else {
                        word.append(character)
                        if word.count >= 12 { flush() }
                    }
                    if result.count > 2048 { return result }
                }
                flush()
            }
            // 大量の子Viewを作らず、長い段落は下の縦配置にフォールバックする。
            if result.count > 2048 { return result }
        }
        return result
    }

    @ViewBuilder
    private func textParagraph(_ spans: [MessageSpan]) -> some View {
        if spans.contains(where: { if case .spoiler = $0.attachment { return true }; return $0.spoilerAction != nil }) {
            let elements = flowElements(spans)
            if elements.count <= 2048 {
                InlineFlowLayout {
                    ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                        switch element {
                        case .text(let span): styledText(span)
                        case .stamp(let stamp): stampView(stamp)
                        case .toggle(let id, let label): spoilerButton(id: id, label: label)
                        case .newline: FlowLineBreak()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                        if case .spoiler(let id, _) = span.attachment {
                            spoilerButton(id: id, label: "スポイラーを表示")
                        } else if let id = span.spoilerAction {
                            spoilerButton(id: id, label: "スポイラーを隠す")
                        } else { inlineText([span]) }
                    }
                }
            }
        } else {
            inlineText(spans)
        }
    }

    private func spoilerButton(id: Int, label: String) -> some View {
        Button { spoilers.toggle(id) } label: {
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.horizontal, 2)
                .frame(minHeight: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoilers.revealed.contains(id) ? "スポイラーを隠す" : "スポイラーを表示")
    }

    @ViewBuilder
    private func stampView(_ stamp: StampReference) -> some View {
        if let emoji = media.unicodeEmoji(for: stamp) {
            Text(verbatim: emoji)
                .font(.system(size: stamp.pointSize))
                .accessibilityLabel(stamp.name)
        } else if let image = media.stampImage(stamp) {
            Image(uiImage: image)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions.height - 4 }
                .accessibilityLabel(stamp.name)
        } else { Text(verbatim: stamp.raw) }
    }

    private func inlineText(_ spans: [MessageSpan]) -> Text {
        spans.reduce(Text("")) { result, span in
            let piece: Text
            switch span.attachment {
            case .spoiler(let id, _):
                piece = styledText(MessageSpan(text: "［スポイラーを表示］", style: span.style, spoilerAction: id))
            case .stamp(let stamp):
                if let emoji = media.unicodeEmoji(for: stamp) {
                    piece = Text(verbatim: emoji).font(.system(size: stamp.pointSize))
                } else if let image = media.stampImage(stamp) {
                    piece = Text(Image(uiImage: image)).baselineOffset(-4)
                } else {
                    // 未知の名前・失敗時も本文を消さず元の記法を残す。
                    piece = styledText(span)
                }
            case .image(let image):
                piece = Text(verbatim: image.alt)
            case .file(let file):
                piece = Text(verbatim: file.label).bold().foregroundColor(.blue)
            case .quote(let quote):
                piece = Text(verbatim: quote.label).bold().foregroundColor(.blue)
            case nil:
                piece = styledText(span)
            }
            return Text("\(result)\(piece)")
        }
    }

    @ViewBuilder
    private func imageView(_ image: MessageImage, resource explicitResource: MessageMediaResource? = nil) -> some View {
        let resource = explicitResource ?? MessageMediaResource.image(image.url)
        if let decoded = media.image(for: resource) {
            Image(uiImage: decoded)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(image.alt.isEmpty ? "本文画像" : image.alt)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if case .failed(let reason) = media.phases[resource] {
                    Label("画像を表示できません", systemImage: "photo.badge.exclamationmark")
                    Text(verbatim: reason).foregroundStyle(.secondary)
                } else {
                    ProgressView("画像を読み込み中")
                }
                if !image.alt.isEmpty { Text(verbatim: image.alt) }
            }
            .font(.caption2)
        }
    }

    private var requestedMedia: [MessageMediaResource] {
        MessagePresentation.resources(in: blocks, revealed: spoilers.revealed)
    }

    private func styledText(_ span: MessageSpan) -> Text {
        var text = Text(verbatim: span.text)
        if span.style.contains(.bold) { text = text.bold() }
        if span.style.contains(.italic) { text = text.italic() }
        if span.style.contains(.strike) { text = text.strikethrough() }
        if span.style.contains(.code) { text = text.font(.system(.body, design: .monospaced)) }
        if span.style.contains(.reference) { text = text.foregroundColor(.blue) }
        return text
    }
}
