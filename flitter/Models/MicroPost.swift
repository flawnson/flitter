//
//  MicroPost.swift
//  flitter
//
//  Created by Flawnson Tong on 2026-03-30.
//


import Foundation

struct MicroPost: Codable, Identifiable, Equatable {
    let id: Int
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
    }

    var createdDate: Date? {
        Self.serverDateFormatter.date(from: createdAt)
    }

    var formattedDate: String {
        guard let createdDate else { return createdAt }
        return Self.displayFormatter.string(from: createdDate)
    }

    private static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct MicroPostsResponse: Codable {
    let posts: [MicroPost]
}

struct CreatePostResponse: Codable {
    let ok: Bool
    let id: Int
}

struct DeletePostResponse: Codable {
    let ok: Bool
    let deleted: Bool
}

struct UpdatePostResponse: Codable {
    let ok: Bool
    let updated: Bool
}
