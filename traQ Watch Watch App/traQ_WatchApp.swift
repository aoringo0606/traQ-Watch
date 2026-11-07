//
//  traQ_WatchApp.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import SwiftUI

@main
struct traQ_Watch_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let flag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--message-preview=") }) {
                RenderingPreviewView(mode: String(flag.dropFirst("--message-preview=".count)))
            } else {
                ContentView()
            }
#else
            ContentView()
#endif
        }
    }
}
