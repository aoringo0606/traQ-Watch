import Foundation
import Combine
import UIKit

/// 一覧データとメモリキャッシュを画面の生存期間中保持する。
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var parsedContents: [String: [MessageBlock]] = [:]
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

        let visibleChannels = Set(messages.map(\.channelId))
        let visibleUsers = Set(messages.map(\.userId))
        channelPaths = channelPaths.filter { visibleChannels.contains($0.key) }
        icons = icons.filter { visibleUsers.contains($0.key) }
        var failures: [String] = []
        do {
            if users.isEmpty || messages.contains(where: { users[$0.userId] == nil }) {
                users = try await auth.fetchUsers(forceRefresh: !users.isEmpty)
            }
        } catch {
            failures.append("投稿者情報: \(error.localizedDescription)")
        }

        // 成功した結果だけをキャッシュする。失敗分は次の手動更新で再試行する。
        await withTaskGroup(of: (String, String?, String?).self) { group in
            for id in Set(messages.map(\.channelId)) where channelPaths[id] == nil {
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
        let missingUserIDs = Array(Set(messages.map(\.userId)).filter { icons[$0] == nil })
        for start in stride(from: 0, to: missingUserIDs.count, by: 3) {
            if Task.isCancelled { return }
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
        if !Task.isCancelled && !failures.isEmpty {
            errorMessage = "一部の情報を取得できませんでした\n" + Set(failures).sorted().joined(separator: "\n")
        }
    }
}
