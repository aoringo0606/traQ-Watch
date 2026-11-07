//
//  ContentView.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import SwiftUI

struct ContentView: View {
    let messages = [
        "こんにちは!",
        "**太字**のテスト",
        "!!スポイラー!!",
        "#geeneral で話しましょう"
    ]
    
    var body: some View {
        NavigationStack {
            List(messages, id: \.self) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text("aorinngo")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    
                    Text(message)
                        .font(.body)
                }
            }
            .navigationTitle("Activity")
        }
    }
}

#Preview {
    ContentView()
}
