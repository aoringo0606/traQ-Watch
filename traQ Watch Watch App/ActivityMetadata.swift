//
//  ActivityMetadata.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import Foundation

struct TraQUser: Decodable, Identifiable {
    let id: String
    let name: String
    let displayName: String
}
