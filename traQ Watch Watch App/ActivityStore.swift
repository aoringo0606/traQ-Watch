import Foundation
import Combine
import UIKit

/// 一覧データとメモリキャッシュを画面の生存期間中保持する。
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var parsedContents: [String: [MessageBlock]] = [:]
    @Published private(set) var quoteReferences: [String: [MessageQuoteReference]] = [:]
    @Published private(set) var quotes: [String: MessageQuoteState] = [:]
    @Published private(set) var messages: [ActivityMessage] = []
    @Published private(set) var users: [String: TraQUser] = [:]
    @Published private(set) var channelPaths: [String: String] = [:]
    @Published private(set) var icons: [String: UIImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    func load(auth: AuthManager) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await auth.fetchActivities()
            let server = auth.currentServerURL
            let parsed = await Task.detached(priority: .userInitiated) {
                Dictionary(loaded.map { ($0.id, MessageParser.parse($0.content, server: server)) }, uniquingKeysWith: { _, latest in latest })
            }.value
            try Task.checkCancellation()
            parsedContents = parsed
            messages = loaded
            hasLoaded = true
        } catch {
            if !Task.isCancelled {
                errorMessage = "アクティビティを取得できませんでした: \(error.localizedDescription)"
            }
            return
        }

        async let quoteLoading: Void = loadQuotes(auth: auth)
        var failures = await loadMetadata(for: messages, auth: auth)
        await quoteLoading
        guard !Task.isCancelled else { return }
        let quotedMessages = quotes.values.compactMap { state -> ActivityMessage? in
            if case .loaded(let preview) = state { return preview.message }; return nil
        }
        failures += await loadMetadata(for: quotedMessages, auth: auth)
        let metadataMessages = messages + quotedMessages
        let visibleChannels = Set(metadataMessages.map(\.channelId))
        let visibleUsers = Set(metadataMessages.map(\.userId))
        channelPaths = channelPaths.filter { visibleChannels.contains($0.key) }
        icons = icons.filter { visibleUsers.contains($0.key) }
        if !Task.isCancelled && !failures.isEmpty {
            errorMessage = "一部の情報を取得できませんでした\n" + Set(failures).sorted().joined(separator: "\n")
        }
    }

    private func loadMetadata(for metadataMessages: [ActivityMessage], auth: AuthManager) async -> [String] {
        guard !metadataMessages.isEmpty else { return [] }
        let visibleChannels = Set(metadataMessages.map(\.channelId))
        let visibleUsers = Set(metadataMessages.map(\.userId))
        var failures: [String] = []
        do {
            if users.isEmpty || metadataMessages.contains(where: { users[$0.userId] == nil }) {
                users = try await auth.fetchUsers(forceRefresh: !users.isEmpty)
            }
        } catch {
            failures.append("投稿者情報: \(error.localizedDescription)")
        }

        // 成功した結果だけをキャッシュする。失敗分は次の手動更新で再試行する。
        await withTaskGroup(of: (String, String?, String?).self) { group in
            for id in visibleChannels where channelPaths[id] == nil {
                group.addTask {
                    do {
                        return (id, try await auth.fetchChannelPath(channelId: id), nil)
                    } catch {
                        return (id, nil, error.localizedDescription)
                    }
                }
            }
            for await (id, path, error) in group {
                if let path { channelPaths[id] = path }
                if let error { failures.append("チャンネルパス: \(error)") }
            }
        }
        let missingUserIDs = Array(visibleUsers.filter { icons[$0] == nil })
        for start in stride(from: 0, to: missingUserIDs.count, by: 3) {
            if Task.isCancelled { return failures }
            await withTaskGroup(of: (String, Data?, String?).self) { group in
                for id in missingUserIDs[start..<min(start + 3, missingUserIDs.count)] {
                    group.addTask {
                        do {
                            let data = try await auth.fetchUserIcon(userId: id)
                            return (id, data, nil)
                        } catch {
                            return (id, nil, error.localizedDescription)
                        }
                    }
                }
                for await (id, data, error) in group {
                    if let data {
                        do {
                            icons[id] = try await Task.detached(priority: .utility) {
                                try ImageDecoder.decode(data, maximumPixels: 96)
                            }.value
                        } catch {
                            failures.append("アイコン: 画像データを読み込めませんでした")
                        }
                    }
                    if let error { failures.append("アイコン: \(error)") }
                }
            }
        }
        return failures
    }

    private func loadQuotes(auth: AuthManager) async {
        guard let server = auth.currentServerURL else { quoteReferences = [:]; quotes = [:]; return }
        let planned = MessageQuoteLinks.plan(messages: messages, parsed: parsedContents)
        quoteReferences = planned
        let refs = messages.flatMap { planned[$0.id] ?? [] }
        quotes = Dictionary(refs.map { ($0.id, MessageQuoteState.loading) }, uniquingKeysWith: { first, _ in first })
        let loaded = await MessageQuoteLoader.load(references: refs, timeline: messages, server: server) { id in
            try await auth.fetchMessage(id: id)
        }
        if Task.isCancelled {
            quotes = Dictionary(refs.map { ($0.id, MessageQuoteState.failed) }, uniquingKeysWith: { first, _ in first })
        } else { quotes = loaded }
    }

}
