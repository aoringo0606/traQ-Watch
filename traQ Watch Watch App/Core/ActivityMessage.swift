//
//  ActivityMessage.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import Foundation

nonisolated struct ActivityMessage: Identifiable, Decodable, Sendable {
    let id: String
    let userId: String
    let channelId: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
}
