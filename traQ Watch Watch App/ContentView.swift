//
//  ContentView.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var auth = AuthManager()

    var body: some View {
        Group {
            if auth.isLoading && auth.username == nil {
                ProgressView("Loading...")
            } else if auth.username != nil {
                LoggedInView(auth: auth)
            } else {
                LoginView(auth: auth)
            }
        }
        .task {
            await auth.restore()
        }
    }
}


#Preview {
    ContentView()
}
