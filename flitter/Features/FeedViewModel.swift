//
//  FeedViewModel.swift
//  flitter
//
//  Created by Flawnson Tong on 2026-03-30.
//


import Foundation
import Combine
import Network

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [MicroPost] = []
    @Published var composerText = "" {
        didSet {
            offlineStore.saveComposerDraft(composerText)
            autosaveActiveDraft()
        }
    }
    @Published var drafts: [DraftPost] = []
    @Published var activeDraftID: DraftPost.ID? {
        didSet {
            offlineStore.saveActiveDraftId(activeDraftID)
        }
    }
    @Published var scheduledPosts: [ScheduledPost] = []
    @Published var isLoading = false
    @Published var isPosting = false
    @Published var errorMessage: String?
    @Published var lastUpdatedText: String?

    private let api = MicroblogAPI()
    private let offlineStore = OfflinePostStore()
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "FeedViewModel.NetworkMonitor")
    private var isSyncing = false
    private var isLoadingDraft = false
    private var scheduledPostTimer: Timer?

    var draftsButtonTitle: String {
        guard !drafts.isEmpty else { return "Drafts" }
        return "Drafts (\(drafts.count))"
    }

    var draftStatusText: String? {
        if activeDraftID != nil {
            return "Saved draft"
        }

        guard !drafts.isEmpty else { return nil }
        return "\(drafts.count) saved"
    }

    var scheduledButtonTitle: String {
        guard !scheduledPosts.isEmpty else { return "Scheduled" }
        return "Scheduled (\(scheduledPosts.count))"
    }

    init() {
        drafts = offlineStore.savedDrafts()
        scheduledPosts = offlineStore.scheduledPosts()
        scheduleNextScheduledPostTimer()

        if
            let savedActiveDraftID = offlineStore.activeDraftId(),
            drafts.contains(where: { $0.id == savedActiveDraftID })
        {
            activeDraftID = savedActiveDraftID
        } else {
            offlineStore.saveActiveDraftId(nil)
        }

        composerText = offlineStore.composerDraft()
        updateLastUpdatedText()

        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }

            Task { @MainActor in
                await self?.syncAndRefreshPosts(showError: false)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    deinit {
        networkMonitor.cancel()
        scheduledPostTimer?.invalidate()
    }

    func loadPosts() async {
        isLoading = true
        errorMessage = nil
        posts = offlineStore.displayPosts()
        refreshScheduledPosts()

        defer {
            isLoading = false
        }

        await syncAndRefreshPosts(showError: posts.isEmpty)
    }
    
    func submitPost() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.count <= 1000 else {
            errorMessage = "Post is too long."
            return
        }

        isPosting = true
        errorMessage = nil

        defer {
            isPosting = false
        }

        do {
            _ = try await api.createPost(body: trimmed)
            clearComposerAfterPost()
            await syncAndRefreshPosts(showError: true)
        } catch {
            guard error.isOfflineError else {
                errorMessage = error.localizedDescription
                return
            }

            _ = offlineStore.enqueueCreate(body: trimmed)
            clearComposerAfterPost()
            posts = offlineStore.displayPosts()
        }
    }

    func saveCurrentDraft() {
        guard !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        errorMessage = nil
        let draft = offlineStore.saveDraft(body: composerText, id: activeDraftID)
        activeDraftID = draft.id
        refreshDrafts()
    }

    func loadDraft(_ draft: DraftPost) {
        if
            activeDraftID == nil,
            !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            composerText != draft.body
        {
            _ = offlineStore.saveDraft(body: composerText)
        }

        isLoadingDraft = true
        activeDraftID = draft.id
        composerText = draft.body
        isLoadingDraft = false
        refreshDrafts()
    }

    func deleteDraft(_ draft: DraftPost) {
        offlineStore.removeSavedDraft(id: draft.id)

        if activeDraftID == draft.id {
            activeDraftID = nil
        }

        refreshDrafts()
    }

    func clearComposer() {
        activeDraftID = nil
        composerText = ""
    }

    func scheduleCurrentPost(at scheduledAt: Date) -> Bool {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 1000 else {
            errorMessage = "Post is too long."
            return false
        }
        guard scheduledAt > Date() else {
            errorMessage = "Schedule time must be in the future."
            return false
        }

        errorMessage = nil
        _ = offlineStore.schedulePost(body: trimmed, scheduledAt: scheduledAt)
        clearComposerAfterScheduling()
        refreshScheduledPosts()
        return true
    }

    func loadScheduledPost(_ scheduledPost: ScheduledPost) {
        if
            activeDraftID == nil,
            !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            composerText != scheduledPost.body
        {
            _ = offlineStore.saveDraft(body: composerText)
            refreshDrafts()
        }

        offlineStore.removeScheduledPost(id: scheduledPost.id)
        refreshScheduledPosts()
        activeDraftID = nil
        composerText = scheduledPost.body
    }

    func deleteScheduledPost(_ scheduledPost: ScheduledPost) {
        offlineStore.removeScheduledPost(id: scheduledPost.id)
        refreshScheduledPosts()
    }
    
    func deletePost(_ post: MicroPost) async {
        errorMessage = nil

        guard !isPendingPost(post) else {
            offlineStore.removePendingCreate(localId: post.id)
            posts = offlineStore.displayPosts()
            return
        }

        do {
            try await api.deletePost(id: post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryPost(_ post: MicroPost) async {
        guard isPendingPost(post) else { return }
        await syncAndRefreshPosts(showError: true)
    }

    func updatePost(_ post: MicroPost, body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPendingPost(post) else { return false }
        guard !trimmed.isEmpty else {
            errorMessage = "Post is required."
            return false
        }
        guard trimmed.count <= 1000 else {
            errorMessage = "Post is too long."
            return false
        }

        errorMessage = nil

        do {
            _ = try await api.updatePost(id: post.id, body: trimmed)
            replacePost(post, body: trimmed)
            offlineStore.updateCachedPost(id: post.id, body: trimmed)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func isPendingPost(_ post: MicroPost) -> Bool {
        offlineStore.pendingCreate(localId: post.id) != nil
    }

    func pendingStatusText(for post: MicroPost) -> String? {
        guard let pendingPost = offlineStore.pendingCreate(localId: post.id) else { return nil }

        if pendingPost.lastError != nil {
            return "Failed"
        }

        return "Pending"
    }

    func hasFailedToSync(_ post: MicroPost) -> Bool {
        offlineStore.pendingCreate(localId: post.id)?.lastError != nil
    }

    private func syncAndRefreshPosts(showError: Bool) async {
        guard !isSyncing else { return }
        isSyncing = true

        defer {
            isSyncing = false
        }

        do {
            try await syncDueScheduledPosts()
            try await syncPendingCreates()
            let fetchedPosts = try await api.fetchPosts(limit: 20)
            offlineStore.cacheFetchedPosts(fetchedPosts)
            updateLastUpdatedText()
            posts = offlineStore.displayPosts()
            refreshScheduledPosts()
        } catch {
            posts = offlineStore.displayPosts()
            refreshScheduledPosts()

            if showError && posts.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func syncPendingCreates() async throws {
        for pendingPost in offlineStore.pendingCreates() {
            do {
                offlineStore.clearPendingCreateFailure(localId: pendingPost.localId)
                _ = try await api.createPost(body: pendingPost.body)
                offlineStore.removePendingCreate(localId: pendingPost.localId)
            } catch {
                if !error.isOfflineError {
                    offlineStore.markPendingCreateFailed(
                        localId: pendingPost.localId,
                        errorMessage: error.localizedDescription
                    )
                }

                throw error
            }
        }
    }

    private func syncDueScheduledPosts() async throws {
        for scheduledPost in offlineStore.dueScheduledPosts() {
            do {
                offlineStore.clearScheduledPostFailure(id: scheduledPost.id)
                _ = try await api.createPost(body: scheduledPost.body)
                offlineStore.removeScheduledPost(id: scheduledPost.id)
            } catch {
                if error.isOfflineError {
                    throw error
                }

                offlineStore.markScheduledPostFailed(
                    id: scheduledPost.id,
                    errorMessage: error.localizedDescription
                )
            }
        }

        refreshScheduledPosts()
    }

    private func replacePost(_ post: MicroPost, body: String) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index] = MicroPost(id: post.id, body: body, createdAt: post.createdAt)
    }

    private func autosaveActiveDraft() {
        guard !isLoadingDraft, let activeDraftID else { return }
        guard offlineStore.savedDraft(id: activeDraftID) != nil else {
            self.activeDraftID = nil
            refreshDrafts()
            return
        }

        offlineStore.updateSavedDraft(id: activeDraftID, body: composerText)
        refreshDrafts()
    }

    private func clearComposerAfterPost() {
        if let activeDraftID {
            offlineStore.removeSavedDraft(id: activeDraftID)
            self.activeDraftID = nil
            refreshDrafts()
        }

        composerText = ""
    }

    private func clearComposerAfterScheduling() {
        if let activeDraftID {
            offlineStore.removeSavedDraft(id: activeDraftID)
            self.activeDraftID = nil
            refreshDrafts()
        }

        composerText = ""
    }

    private func refreshDrafts() {
        drafts = offlineStore.savedDrafts()
    }

    private func refreshScheduledPosts() {
        scheduledPosts = offlineStore.scheduledPosts()
        scheduleNextScheduledPostTimer()
    }

    private func scheduleNextScheduledPostTimer() {
        scheduledPostTimer?.invalidate()
        scheduledPostTimer = nil

        let now = Date()
        guard let nextScheduledPost = scheduledPosts.first(where: { $0.scheduledAt > now }) else { return }
        let delay = max(nextScheduledPost.scheduledAt.timeIntervalSince(now), 1)

        scheduledPostTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAndRefreshPosts(showError: false)
            }
        }
    }

    private func updateLastUpdatedText() {
        guard let lastUpdatedAt = offlineStore.lastUpdatedAt() else {
            lastUpdatedText = nil
            return
        }

        lastUpdatedText = "Updated \(Self.lastUpdatedFormatter.string(from: lastUpdatedAt))"
    }

    private static let lastUpdatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension Error {
    var isOfflineError: Bool {
        guard let urlError = self as? URLError else { return false }

        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .timedOut,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}
