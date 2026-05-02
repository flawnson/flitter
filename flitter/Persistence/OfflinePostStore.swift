//
//  OfflinePostStore.swift
//  flitter
//
//  Created by OpenAI on 2026-05-01.
//

import Foundation

struct PendingCreatePost: Codable, Identifiable, Equatable {
    let localId: Int
    let body: String
    let createdAt: String
    var lastError: String?

    var id: Int {
        localId
    }

    var post: MicroPost {
        MicroPost(id: localId, body: body, createdAt: createdAt)
    }
}

final class OfflinePostStore {
    private enum Keys {
        static let cachedPosts = "offline.cachedPosts"
        static let pendingCreates = "offline.pendingCreates"
        static let composerDraft = "offline.composerDraft"
        static let lastUpdatedAt = "offline.lastUpdatedAt"
    }

    private let defaults: UserDefaults
    private let postLimit: Int

    init(defaults: UserDefaults = .standard, postLimit: Int = 20) {
        self.defaults = defaults
        self.postLimit = postLimit
    }

    func displayPosts() -> [MicroPost] {
        let pendingPosts = pendingCreates().map(\.post)
        let serverPosts = cachedPosts().filter { post in
            !pendingPosts.contains { $0.body == post.body && $0.createdAt == post.createdAt }
        }

        return Array((pendingPosts + serverPosts)
            .sorted(by: sortNewestFirst)
            .prefix(postLimit))
    }

    func cachedPosts() -> [MicroPost] {
        decode([MicroPost].self, forKey: Keys.cachedPosts) ?? []
    }

    func pendingCreates() -> [PendingCreatePost] {
        decode([PendingCreatePost].self, forKey: Keys.pendingCreates) ?? []
    }

    func pendingCreate(localId: Int) -> PendingCreatePost? {
        pendingCreates().first { $0.localId == localId }
    }

    func composerDraft() -> String {
        defaults.string(forKey: Keys.composerDraft) ?? ""
    }

    func saveComposerDraft(_ draft: String) {
        defaults.set(draft, forKey: Keys.composerDraft)
    }

    func lastUpdatedAt() -> Date? {
        defaults.object(forKey: Keys.lastUpdatedAt) as? Date
    }

    func cacheFetchedPosts(_ posts: [MicroPost]) {
        encode(Array(posts.prefix(postLimit)), forKey: Keys.cachedPosts)
        defaults.set(Date(), forKey: Keys.lastUpdatedAt)
    }

    func enqueueCreate(body: String) -> MicroPost {
        let pendingPost = PendingCreatePost(
            localId: nextLocalId(existingPosts: pendingCreates()),
            body: body,
            createdAt: Self.serverDateFormatter.string(from: Date()),
            lastError: nil
        )

        var pending = pendingCreates()
        pending.append(pendingPost)
        encode(pending, forKey: Keys.pendingCreates)

        return pendingPost.post
    }

    func markPendingCreateFailed(localId: Int, errorMessage: String?) {
        var pending = pendingCreates()

        guard let index = pending.firstIndex(where: { $0.localId == localId }) else { return }
        pending[index].lastError = errorMessage
        encode(pending, forKey: Keys.pendingCreates)
    }

    func clearPendingCreateFailure(localId: Int) {
        markPendingCreateFailed(localId: localId, errorMessage: nil)
    }

    func removePendingCreate(localId: Int) {
        let pending = pendingCreates().filter { $0.localId != localId }
        encode(pending, forKey: Keys.pendingCreates)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func sortNewestFirst(_ lhs: MicroPost, _ rhs: MicroPost) -> Bool {
        switch (lhs.createdDate, rhs.createdDate) {
        case let (lhsDate?, rhsDate?):
            return lhsDate > rhsDate
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return lhs.id > rhs.id
        }
    }

    private func nextLocalId(existingPosts: [PendingCreatePost]) -> Int {
        var localId = -Int(Date().timeIntervalSince1970 * 1000)
        let existingIds = Set(existingPosts.map(\.localId))

        while existingIds.contains(localId) {
            localId -= 1
        }

        return localId
    }

    private static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
