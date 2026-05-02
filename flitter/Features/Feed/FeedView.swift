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
    @State private var isComposerCollapsed = false
    @State private var editingPost: MicroPost?
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("FlitterLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                        Text("Flitter")
                            .font(.headline)
                    }
                }
            }
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
            .sheet(item: $editingPost) { post in
                EditPostView(post: post) { body in
                    await viewModel.updatePost(post, body: body)
                }
            }
        }
    }

    private var composer: some View {
        Group {
            if isComposerCollapsed {
                collapsedComposer
            } else {
                expandedComposer
            }
        }
        .animation(.snappy, value: isComposerCollapsed)
    }

    private var collapsedComposer: some View {
        Button {
            isComposerCollapsed = false

            DispatchQueue.main.async {
                isComposerFocused = true
            }
        } label: {
            HStack {
                Text(viewModel.composerText.isEmpty ? "New post" : viewModel.composerText)
                    .lineLimit(1)
                    .foregroundStyle(viewModel.composerText.isEmpty ? .secondary : .primary)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding()
    }

    private var expandedComposer: some View {
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
                            if !viewModel.isPendingPost(post) {
                                Button("Edit") {
                                    editingPost = post
                                }
                            }

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
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            isComposerFocused = false
                            isComposerCollapsed = true
                        }
                )
            }
        }
    }
}

private struct EditPostView: View {
    let post: MicroPost
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var bodyText: String
    @State private var isSaving = false
    @FocusState private var isEditorFocused: Bool

    init(post: MicroPost, onSave: @escaping (String) async -> Bool) {
        self.post = post
        self.onSave = onSave
        _bodyText = State(initialValue: post.body)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $bodyText)
                    .focused($isEditorFocused)
                    .frame(minHeight: 180)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                Text("\(bodyText.count)/1000")
                    .font(.caption)
                    .foregroundStyle(bodyText.count > 1000 ? .red : .secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true
                            let didSave = await onSave(bodyText)
                            isSaving = false

                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(
                        isSaving ||
                        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        bodyText.count > 1000
                    )
                }
            }
            .task {
                isEditorFocused = true
            }
        }
    }
}
