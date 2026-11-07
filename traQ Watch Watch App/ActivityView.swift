//
//  ActivityView.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import SwiftUI

struct ActivityView: View {
    @ObservedObject var auth: AuthManager

    @State private var messages: [ActivityMessage] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading && messages.isEmpty {
                    ProgressView("Loading...")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)

                    Button("Retry") {
                        Task {
                            await loadActivities()
                        }
                    }
                }

                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.content)
                            .font(.body)

                        Text(message.createdAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if messages.isEmpty &&
                    !isLoading &&
                    errorMessage == nil {
                    Text("No activities")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadActivities()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .refreshable {
                await loadActivities()
            }
            .task {
                await loadActivities()
            }
        }
    }

    @MainActor
    private func loadActivities() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            messages = try await auth.fetchActivities()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
