import Foundation

/// 表示状態から可視の要素を作る。閉じたスポイラーのメディアは取得対象に含めない。
nonisolated enum MessagePresentation {
    static func visibleSpans(_ spans: [MessageSpan], revealed: Set<Int>, inherited: MessageStyle = [], action: Int? = nil) -> [MessageSpan] {
        spans.flatMap { span -> [MessageSpan] in
            let style = span.style.union(inherited)
            if case .spoiler(let id, let children) = span.attachment, revealed.contains(id) {
                return [MessageSpan(text: "［隠す］ ", style: style, spoilerAction: id)]
                    + visibleSpans(children, revealed: revealed, inherited: style)
            }
            var result = span
            result.style = style
            result.spoilerAction = action
            return [result]
        }
    }

    static func resources(in blocks: [MessageBlock], revealed: Set<Int>) -> [MessageMediaResource] {
        var result: [MessageMediaResource] = []
        var seen: Set<MessageMediaResource> = []
        for block in blocks {
            guard case .paragraph(let spans) = block else { continue }
            for span in visibleSpans(spans, revealed: revealed) {
                let resource: MessageMediaResource
                switch span.attachment {
                case .stamp(let stamp): resource = .stamp(stamp.name)
                case .image(let image): resource = .image(image.url)
                case .file(let file): resource = .file(file.url)
                default: continue
                }
                if seen.insert(resource).inserted { result.append(resource) }
            }
        }
        return result
    }
}
