//
//  OfflinePostStore.swift
//  fwitter
//
//  Created by OpenAI on 2026-05-01.
//

import Foundation

struct PendingCreatePost: Codable, Identifiable, Equatable {
    let localId: Int
    let body: String
    let createdAt: String
    var lastError: String?
    let replyToId: Int?
    // Optional so posts queued before this field existed still decode (they
    // simply fall back to `.auto`). Ignored for replies, which inherit the
    // parent's routing server-side.
    let syndication: String?

    var id: Int {
        localId
    }

    var syndicationChoice: SyndicationChoice {
        SyndicationChoice.from(syndication)
    }

    var post: MicroPost {
        MicroPost(
            id: localId,
            body: body,
            createdAt: createdAt,
            parentId: replyToId,
            syndicatedPlatforms: nil,
            platformPostIds: nil,
            hasImage: false
        )
    }
}

struct DraftPost: Codable, Identifiable, Equatable {
    let id: UUID
    var body: String
    let createdAt: Date
    var updatedAt: Date

    var previewText: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty draft" : trimmed
    }

    var formattedUpdatedAt: String {
        Self.updatedAtFormatter.string(from: updatedAt)
    }

    private static let updatedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ScheduledPost: Codable, Identifiable, Equatable {
    let id: UUID
    var body: String
    var scheduledAt: Date
    let createdAt: Date
    var lastError: String?
    // Optional for back-compat with posts scheduled before this field existed.
    var syndication: String?

    var syndicationChoice: SyndicationChoice {
        SyndicationChoice.from(syndication)
    }

    var previewText: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty scheduled post" : trimmed
    }

    var formattedScheduledAt: String {
        Self.scheduledAtFormatter.string(from: scheduledAt)
    }

    private static let scheduledAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

final class OfflinePostStore {
    private enum Keys {
        static let cachedPosts = "offline.cachedPosts"
        static let pendingCreates = "offline.pendingCreates"
        static let composerDraft = "offline.composerDraft"
        static let savedDrafts = "offline.savedDrafts"
        static let activeDraftId = "offline.activeDraftId"
        static let syndicationChoice = "offline.syndicationChoice"
        static let scheduledPosts = "offline.scheduledPosts"
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

    func savedDrafts() -> [DraftPost] {
        sortedDrafts(decode([DraftPost].self, forKey: Keys.savedDrafts) ?? [])
    }

    func savedDraft(id: DraftPost.ID) -> DraftPost? {
        savedDrafts().first { $0.id == id }
    }

    func activeDraftId() -> DraftPost.ID? {
        guard let rawId = defaults.string(forKey: Keys.activeDraftId) else { return nil }
        return UUID(uuidString: rawId)
    }

    func saveActiveDraftId(_ id: DraftPost.ID?) {
        if let id {
            defaults.set(id.uuidString, forKey: Keys.activeDraftId)
        } else {
            defaults.removeObject(forKey: Keys.activeDraftId)
        }
    }

    func syndicationChoice() -> SyndicationChoice {
        SyndicationChoice.from(defaults.string(forKey: Keys.syndicationChoice))
    }

    func saveSyndicationChoice(_ choice: SyndicationChoice) {
        defaults.set(choice.wireValue, forKey: Keys.syndicationChoice)
    }

    func saveDraft(body: String, id: DraftPost.ID? = nil) -> DraftPost {
        let now = Date()
        var drafts = savedDrafts()

        if let id, let index = drafts.firstIndex(where: { $0.id == id }) {
            drafts[index].body = body
            drafts[index].updatedAt = now
            encode(sortedDrafts(drafts), forKey: Keys.savedDrafts)
            return drafts[index]
        }

        let draft = DraftPost(
            id: UUID(),
            body: body,
            createdAt: now,
            updatedAt: now
        )

        drafts.append(draft)
        encode(sortedDrafts(drafts), forKey: Keys.savedDrafts)
        return draft
    }

    func updateSavedDraft(id: DraftPost.ID, body: String) {
        var drafts = savedDrafts()

        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].body = body
        drafts[index].updatedAt = Date()
        encode(sortedDrafts(drafts), forKey: Keys.savedDrafts)
    }

    func removeSavedDraft(id: DraftPost.ID) {
        let drafts = savedDrafts().filter { $0.id != id }
        encode(drafts, forKey: Keys.savedDrafts)

        if activeDraftId() == id {
            saveActiveDraftId(nil)
        }
    }

    func scheduledPosts() -> [ScheduledPost] {
        sortedScheduledPosts(decode([ScheduledPost].self, forKey: Keys.scheduledPosts) ?? [])
    }

    func dueScheduledPosts(now: Date = Date()) -> [ScheduledPost] {
        scheduledPosts().filter { $0.scheduledAt <= now }
    }

    func schedulePost(body: String, scheduledAt: Date, syndication: SyndicationChoice = .auto) -> ScheduledPost {
        let now = Date()
        let scheduledPost = ScheduledPost(
            id: UUID(),
            body: body,
            scheduledAt: scheduledAt,
            createdAt: now,
            lastError: nil,
            syndication: syndication.wireValue
        )

        var posts = scheduledPosts()
        posts.append(scheduledPost)
        encode(sortedScheduledPosts(posts), forKey: Keys.scheduledPosts)
        return scheduledPost
    }

    func removeScheduledPost(id: ScheduledPost.ID) {
        let posts = scheduledPosts().filter { $0.id != id }
        encode(posts, forKey: Keys.scheduledPosts)
    }

    func markScheduledPostFailed(id: ScheduledPost.ID, errorMessage: String?) {
        var posts = scheduledPosts()

        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[index].lastError = errorMessage
        encode(sortedScheduledPosts(posts), forKey: Keys.scheduledPosts)
    }

    func clearScheduledPostFailure(id: ScheduledPost.ID) {
        markScheduledPostFailed(id: id, errorMessage: nil)
    }

    func lastUpdatedAt() -> Date? {
        defaults.object(forKey: Keys.lastUpdatedAt) as? Date
    }

    func cacheFetchedPosts(_ posts: [MicroPost]) {
        encode(Array(posts.prefix(postLimit)), forKey: Keys.cachedPosts)
        defaults.set(Date(), forKey: Keys.lastUpdatedAt)
    }

    func updateCachedPost(id: Int, body: String) {
        let updatedPosts = cachedPosts().map { post in
            guard post.id == id else { return post }
            return MicroPost(
                id: post.id,
                body: body,
                createdAt: post.createdAt,
                parentId: post.parentId,
                syndicatedPlatforms: post.syndicatedPlatforms,
                platformPostIds: post.platformPostIds,
                hasImage: post.hasImage
            )
        }

        encode(updatedPosts, forKey: Keys.cachedPosts)
    }

    func enqueueCreate(body: String, replyToId: Int? = nil, syndication: SyndicationChoice = .auto) -> MicroPost {
        let pendingPost = PendingCreatePost(
            localId: nextLocalId(existingPosts: pendingCreates()),
            body: body,
            createdAt: Self.serverDateFormatter.string(from: Date()),
            lastError: nil,
            replyToId: replyToId,
            syndication: syndication.wireValue
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

    private func sortedDrafts(_ drafts: [DraftPost]) -> [DraftPost] {
        drafts.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func sortedScheduledPosts(_ scheduledPosts: [ScheduledPost]) -> [ScheduledPost] {
        scheduledPosts.sorted { lhs, rhs in
            if lhs.scheduledAt == rhs.scheduledAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.scheduledAt < rhs.scheduledAt
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
