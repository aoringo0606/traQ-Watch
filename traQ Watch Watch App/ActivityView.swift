//
//  ActivityView.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import SwiftUI
import UIKit

struct ActivityView: View {
    @ObservedObject var auth: AuthManager

    @StateObject private var store = ActivityStore()
    @StateObject private var media: MessageMediaStore

    init(auth: AuthManager) {
        self.auth = auth
        _media = StateObject(wrappedValue: MessageMediaStore(auth: auth))
    }

    var body: some View {
        NavigationStack {
            List {
                if store.isLoading && store.messages.isEmpty {
                    ProgressView("Loading...")
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)

                    Button("Retry") {
                        Task {
                            media.retryFailures()
                            await store.load(auth: auth)
                        }
                    }
                }

                ForEach(store.messages) { message in
                    activityRow(message)
                }

                if store.messages.isEmpty &&
                    !store.isLoading &&
                    store.errorMessage == nil {
                    Text("No activities")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right") {
                        Task { await auth.logout() }
                    }
                    .disabled(store.isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("再読み込み", systemImage: "arrow.clockwise") {
                        Task {
                            media.retryFailures()
                            await store.load(auth: auth)
                        }
                    }
                    .disabled(store.isLoading)
                }
            }
            .refreshable {
                media.retryFailures()
                await store.load(auth: auth)
            }
            .onDisappear { media.cancel() }
            .task {
                guard !store.hasLoaded else { return }
                await store.load(auth: auth)
            }
        }
    }

    private func activityRow(
        _ message: ActivityMessage
    ) -> some View {
        let user = store.users[message.userId]
        let path = store.channelPaths[message.channelId]
        let references = store.quoteReferences[message.id] ?? []
        let expanded = Set(references.compactMap { ref -> String? in
            if case .loaded = store.quotes[ref.id] { return ref.id }; return nil
        })

        return HStack(alignment: .top, spacing: 8) {
            userIcon(message.userId)

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    user.map { $0.displayName.isEmpty ? $0.name : $0.displayName } ?? "Unknown"
                )
                .font(.headline)

                Text(path ?? "#unknown")
                    .font(.caption2)
                    .foregroundStyle(.blue)

                MessageContentView(blocks: MessageQuoteLinks.body(store.parsedContents[message.id] ?? [], expanded: expanded), media: media)
                    .id(message.updatedAt)
                    .font(.body)

                ForEach(references) { reference in
                    switch store.quotes[reference.id] {
                    case .loaded(let preview):
                        QuoteCardView(preview: preview,
                                      user: store.users[preview.message.userId],
                                      icon: store.icons[preview.message.userId],
                                      channelPath: store.channelPaths[preview.message.channelId],
                                      media: media)
                    case .loading:
                        ProgressView("引用を読み込み中")
                            .font(.caption2)
                    case .failed, nil:
                        Text("引用を取得できませんでした")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(message.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func userIcon(_ userId: String) -> some View {
        Group {
            if let image = store.icons[userId] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("投稿者のアイコン")
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
    }

}
