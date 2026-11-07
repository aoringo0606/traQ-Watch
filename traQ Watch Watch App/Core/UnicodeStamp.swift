import Foundation

/// traQのTwemojiインストーラーは`1f389.svg`等のコードポイント名で保存する。
/// SVGを実行・描画せず、Unicodeスタンプだけをシステム絵文字へ変換する。
nonisolated enum UnicodeStamp {
    static func emoji(filename: String) -> String? {
        guard filename.count <= 256, filename.lowercased().hasSuffix(".svg"),
              !filename.contains("/"), !filename.contains("\\") else { return nil }
        let components = filename.dropLast(4).split(separator: "-", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 16 else { return nil }
        var scalars = String.UnicodeScalarView()
        for component in components {
            guard (1...6).contains(component.count),
                  component.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  let code = UInt32(component, radix: 16), let scalar = UnicodeScalar(code),
                  scalar.properties.isEmoji || scalar.properties.isEmojiModifier
                    || code == 0x200D || code == 0xFE0F || code == 0x20E3
                    || (0xE0020...0xE007F).contains(code) else { return nil }
            scalars.append(scalar)
        }
        guard scalars.contains(where: { $0.properties.isEmoji && ($0.value > 0x2000 || $0.properties.isEmojiPresentation) })
                || scalars.contains(where: { $0.value == 0x20E3 }) else { return nil }
        if scalars.count == 1, let scalar = scalars.first, !scalar.properties.isEmojiPresentation {
            scalars.append("\u{FE0F}")
        }
        let result = String(scalars)
        guard result.count == 1 else { return nil }
        return result
    }
}
