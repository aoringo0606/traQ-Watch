//
//  LoginView.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var auth: AuthManager

    @State private var server = "https://q.trap.jp"
    @State private var name = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("traQ Login")
                    .font(.headline)

                TextField("Server URL", text: $server)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Username", text: $name)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)

                if let error = auth.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption2)
                }

                Button("Log in") {
                    Task {
                        await auth.login(
                            server: server,
                            name: name,
                            password: password
                        )

                        if auth.username != nil {
                            password = ""
                        }
                    }
                }
                .disabled(
                    auth.isLoading ||
                    name.isEmpty ||
                    password.isEmpty
                )

                if auth.isLoading {
                    ProgressView()
                }
            }
        }
    }
}
