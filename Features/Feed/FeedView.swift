//
//  FeedView.swift
//  flitter
//
//  Created by Flawnson Tong on 2026-03-30.
//

import SwiftUI
import UIKit

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                composer
                Divider()
                content
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isComposerFocused = false
            }
            .navigationTitle("Flitter")
            .task {
                await viewModel.loadPosts()
            }
            .refreshable {
                await viewModel.loadPosts()
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New post")
                .font(.headline)

            TextEditor(text: $viewModel.composerText)
                .focused($isComposerFocused)
                .frame(minHeight: 120)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            HStack {
                Text("\(viewModel.composerText.count)/1000")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        await viewModel.submitPost()
                        isComposerFocused = false
                    }
                } label: {
                    if viewModel.isPosting {
                        ProgressView()
                    } else {
                        Text("Post")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isPosting ||
                    viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding()
    }

    private var content: some View {
        Group {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.posts.isEmpty {
                ContentUnavailableView(
                    "No posts yet",
                    systemImage: "text.bubble",
                    description: Text("Your published posts will show up here.")
                )
            } else {
                List {
                    if let lastUpdatedText = viewModel.lastUpdatedText {
                        Text(lastUpdatedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(viewModel.posts) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)

                            HStack(spacing: 8) {
                                Text(post.formattedDate)
                                    .foregroundStyle(.secondary)

                                if let pendingStatus = viewModel.pendingStatusText(for: post) {
                                    Text(pendingStatus)
                                        .foregroundStyle(viewModel.hasFailedToSync(post) ? .red : .secondary)
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Copy") {
                                UIPasteboard.general.string = post.body
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if viewModel.hasFailedToSync(post) {
                                Button {
                                    Task {
                                        await viewModel.retryPost(post)
                                        isComposerFocused = false
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }

                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deletePost(post)
                                    isComposerFocused = false
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }
}
