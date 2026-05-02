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
        }
    }
    @Published var isLoading = false
    @Published var isPosting = false
    @Published var errorMessage: String?
    @Published var lastUpdatedText: String?

    private let api = MicroblogAPI()
    private let offlineStore = OfflinePostStore()
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "FeedViewModel.NetworkMonitor")
    private var isSyncing = false

    init() {
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
    }

    func loadPosts() async {
        isLoading = true
        errorMessage = nil
        posts = offlineStore.displayPosts()

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
            composerText = ""
            await syncAndRefreshPosts(showError: true)
        } catch {
            guard error.isOfflineError else {
                errorMessage = error.localizedDescription
                return
            }

            _ = offlineStore.enqueueCreate(body: trimmed)
            composerText = ""
            posts = offlineStore.displayPosts()
        }
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
            try await syncPendingCreates()
            let fetchedPosts = try await api.fetchPosts(limit: 20)
            offlineStore.cacheFetchedPosts(fetchedPosts)
            updateLastUpdatedText()
            posts = offlineStore.displayPosts()
        } catch {
            posts = offlineStore.displayPosts()

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
