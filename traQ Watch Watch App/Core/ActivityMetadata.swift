//
//  ActivityMetadata.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import Foundation

nonisolated struct TraQUser: Decodable, Identifiable {
    let id: String
    let name: String
    let displayName: String
}

nonisolated struct TraQStamp: Decodable {
    let id: String
    let name: String
    let fileId: String
    let isUnicode: Bool
}
