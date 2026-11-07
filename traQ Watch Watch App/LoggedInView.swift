//
//  LoggedInView.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import SwiftUI

struct LoggedInView: View {
    @ObservedObject var auth: AuthManager

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title)

                Text("Logged in")
                    .font(.headline)

                Text("@\(auth.username ?? "")")
                    .font(.caption)

                Button("Log out") {
                    Task {
                        await auth.logout()
                    }
                }
                .tint(.red)
            }
        }
    }
}
