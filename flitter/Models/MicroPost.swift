//
//  MicroPost.swift
//  flitter
//
//  Created by Flawnson Tong on 2026-03-30.
//

import Foundation

/// How a post should be syndicated to the social platforms. `auto` lets the
/// backend's AI router pick the best platform; `none` keeps the post on the blog
/// only; the platform cases force exactly that one platform. The `wireValue` is
/// what gets sent to the API in the `syndication` field.
enum SyndicationChoice: String, Codable, CaseIterable, Identifiable, Equatable {
    case auto
    case none
    case x
    case threads
    case bluesky

    var id: String { rawValue }

    var wireValue: String { rawValue }

    /// Decodes a stored/persisted value, tolerating anything unexpected by
    /// falling back to `.auto` (e.g. older queued posts saved before this field
    /// existed, or a value from a future build).
    static func from(_ raw: String?) -> SyndicationChoice {
        guard let raw, let choice = SyndicationChoice(rawValue: raw) else { return .auto }
        return choice
    }

    /// Full label shown in the routing menu.
    var menuLabel: String {
        switch self {
        case .auto:    return "Auto (let AI pick)"
        case .none:    return "Don't syndicate"
        case .x:       return "X"
        case .threads: return "Threads"
        case .bluesky: return "Bluesky"
        }
    }

    /// Short, glanceable status shown in the composer when not `.auto`.
    var composerStatusText: String {
        switch self {
        case .auto:    return ""
        case .none:    return "Won't syndicate"
        case .x:       return "Only on X"
        case .threads: return "Only on Threads"
        case .bluesky: return "Only on Bluesky"
        }
    }

    /// Icon for the split-button menu trigger; reflects the current state.
    var triggerSystemImage: String {
        switch self {
        case .auto:    return "chevron.down"
        case .none:    return "nosign"
        default:       return "arrow.up.forward"
        }
    }
}

struct PlatformPostIds: Codable, Equatable {
    let x: XPostId?
    let threads: ThreadsPostId?
    let bluesky: BlueskyPostId?
}

struct XPostId: Codable, Equatable {
    let postId: String

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
    }
}

struct ThreadsPostId: Codable, Equatable {
    let postId: String
    let url: String?

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case url
    }
}

struct BlueskyPostId: Codable, Equatable {
    let uri: String
    let cid: String
}

struct MicroPost: Codable, Identifiable, Equatable {
    let id: Int
    let body: String
    let createdAt: String
    let parentId: Int?
    let syndicatedPlatforms: [String]?
    let platformPostIds: PlatformPostIds?
    let hasImage: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
        case parentId = "parent_id"
        case syndicatedPlatforms = "syndicated_platforms"
        case platformPostIds = "platform_post_ids"
        case hasImage = "has_image"
    }

    init(id: Int, body: String, createdAt: String, parentId: Int?, syndicatedPlatforms: [String]?, platformPostIds: PlatformPostIds?, hasImage: Bool = false) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.parentId = parentId
        self.syndicatedPlatforms = syndicatedPlatforms
        self.platformPostIds = platformPostIds
        self.hasImage = hasImage
    }

    var createdDate: Date? {
        Self.serverDateFormatter.date(from: createdAt)
    }

    var formattedDate: String {
        guard let createdDate else { return createdAt }
        return Self.displayFormatter.string(from: createdDate)
    }

    var primaryPlatformLabel: String? {
        guard let platform = syndicatedPlatforms?.first else { return nil }
        switch platform {
        case "x":       return "X"
        case "threads": return "Threads"
        case "bluesky": return "Bluesky"
        default:        return platform.capitalized
        }
    }

    var platformURL: URL? {
        guard let platform = syndicatedPlatforms?.first,
              let ids = platformPostIds else { return nil }

        switch platform {
        case "x":
            guard let postId = ids.x?.postId else { return nil }
            return URL(string: "https://x.com/i/web/status/\(postId)")

        case "threads":
            guard let urlString = ids.threads?.url else { return nil }
            return URL(string: urlString)

        case "bluesky":
            guard let uri = ids.bluesky?.uri else { return nil }
            let withoutScheme = uri.replacingOccurrences(of: "at://", with: "")
            let parts = withoutScheme.split(separator: "/")
            guard parts.count >= 3 else { return nil }
            let did = String(parts[0])
            let rkey = String(parts[parts.count - 1])
            return URL(string: "https://bsky.app/profile/\(did)/post/\(rkey)")

        default:
            return nil
        }
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
