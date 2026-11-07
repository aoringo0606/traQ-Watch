import Foundation
import Combine
import UIKit

/// 一覧データとメモリキャッシュを画面の生存期間中保持する。
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var messages: [ActivityMessage] = []
    @Published private(set) var users: [String: TraQUser] = [:]
    @Published private(set) var channelPaths: [String: String] = [:]
    @Published private(set) var icons: [String: Data] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    func load(auth: AuthManager) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            messages = try await auth.fetchActivities()
            hasLoaded = true
        } catch {
            if !Task.isCancelled {
                errorMessage = "アクティビティを取得できませんでした: \(error.localizedDescription)"
            }
            return
        }

        var failures: [String] = []
        do {
            users = try await auth.fetchUsers()
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
        await withTaskGroup(of: (String, Data?, String?).self) { group in
            for id in Set(messages.map(\.userId)) where icons[id] == nil {
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
                    if UIImage(data: data) != nil {
                        icons[id] = data
                    } else {
                        failures.append("アイコン: 画像データを読み込めませんでした")
                    }
                }
                if let error { failures.append("アイコン: \(error)") }
            }
        }
        if !Task.isCancelled && !failures.isEmpty {
            errorMessage = "一部の情報を取得できませんでした\n" + Set(failures).sorted().joined(separator: "\n")
        }
    }
}
