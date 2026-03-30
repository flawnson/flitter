//
//  FeedViewModel.swift
//  flitter
//
//  Created by Flawnson Tong on 2026-03-30.
//


import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [MicroPost] = []
    @Published var composerText = ""
    @Published var isLoading = false
    @Published var isPosting = false
    @Published var errorMessage: String?

    private let api = MicroblogAPI()

    func loadPosts() async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            posts = try await api.fetchPosts()
        } catch {
            errorMessage = error.localizedDescription
        }
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
            try await api.createPost(body: trimmed)
            composerText = ""
            posts = try await api.fetchPosts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func deletePost(_ post: MicroPost) async {
        errorMessage = nil

        do {
            try await api.deletePost(id: post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
