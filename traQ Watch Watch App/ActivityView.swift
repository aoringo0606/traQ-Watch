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
            .refreshable {
                await store.load(auth: auth)
            }
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

                Text(message.content)
                    .font(.body)

                Text(message.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func userIcon(_ userId: String) -> some View {
        Group {
            if let data = store.icons[userId],
               let image = UIImage(data: data) {
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
