//
//  FeedView.swift
//  fwitter
//
//  Created by Flawnson Tong on 2026-03-30.
//

import SwiftUI
import UIKit
import PhotosUI

struct FeedView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @StateObject private var viewModel = FeedViewModel()
    @State private var isComposerCollapsed = false
    @State private var editingPost: MicroPost?
    @State private var replyingTo: MicroPost?
    @State private var composerImage: UIImage?
    @State private var composerImageItem: PhotosPickerItem?
    @State private var isShowingDrafts = false
    @State private var isShowingScheduled = false
    @State private var isShowingSchedulePost = false
    @State private var scheduledAt = Date().addingTimeInterval(3600)
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
            .navigationTitle("Fwitter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("FwitterLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                        Text("Fwitter")
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
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }

                Task {
                    await viewModel.loadPosts()
                }
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
            .sheet(item: $replyingTo) { post in
                ReplyView(parentPost: post) { body, image in
                    await viewModel.submitReply(to: post, body: body, image: image)
                }
            }
            .sheet(isPresented: $isShowingDrafts) {
                DraftsView(
                    drafts: viewModel.drafts,
                    activeDraftID: viewModel.activeDraftID,
                    onSelect: { draft in
                        viewModel.loadDraft(draft)
                        isComposerCollapsed = false

                        DispatchQueue.main.async {
                            isComposerFocused = true
                        }
                    },
                    onDelete: { draft in
                        viewModel.deleteDraft(draft)
                    }
                )
            }
            .sheet(isPresented: $isShowingScheduled) {
                ScheduledPostsView(
                    scheduledPosts: viewModel.scheduledPosts,
                    onSelect: { scheduledPost in
                        viewModel.loadScheduledPost(scheduledPost)
                        isComposerCollapsed = false

                        DispatchQueue.main.async {
                            isComposerFocused = true
                        }
                    },
                    onDelete: { scheduledPost in
                        viewModel.deleteScheduledPost(scheduledPost)
                    }
                )
            }
            .sheet(isPresented: $isShowingSchedulePost) {
                SchedulePostView(
                    bodyText: viewModel.composerText,
                    defaultScheduledAt: scheduledAt,
                    onSchedule: { date in
                        viewModel.scheduleCurrentPost(at: date)
                    }
                )
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
            HStack {
                Text(viewModel.activeDraftID == nil ? "New post" : "Draft")
                    .font(.headline)

                Spacer()

                Button {
                    isShowingDrafts = true
                } label: {
                    Label(viewModel.draftsButtonTitle, systemImage: "tray")
                }
                .font(.subheadline)
                .buttonStyle(.borderless)

                Button {
                    isShowingScheduled = true
                } label: {
                    Label(viewModel.scheduledButtonTitle, systemImage: "calendar")
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
            .controlSize(.small)

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
                    .foregroundStyle(viewModel.composerText.count > 1000 ? .red : .secondary)

                if let draftStatusText = viewModel.draftStatusText {
                    Text(draftStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.syndicationChoice != .auto {
                    Label(
                        viewModel.syndicationChoice.composerStatusText,
                        systemImage: viewModel.syndicationChoice == .none ? "nosign" : "arrow.up.forward"
                    )
                    .font(.caption)
                    .foregroundStyle(viewModel.syndicationChoice == .none ? .orange : .secondary)
                }

                Spacer()

                if !viewModel.composerText.isEmpty {
                    Button {
                        viewModel.clearComposer()
                        isComposerFocused = false
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear")
                    .disabled(viewModel.isPosting)
                }
            }

            if let composerImage {
                HStack {
                    Image(uiImage: composerImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        self.composerImage = nil
                        composerImageItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }

            HStack {
                PhotosPicker(selection: $composerImageItem, matching: .images) {
                    Image(systemName: "photo")
                }
                .buttonStyle(.borderless)
                .onChange(of: composerImageItem) { item in
                    Task {
                        guard let item else { return }
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            composerImage = image
                            // Threads can't carry a photo; drop the forced choice
                            // back to Auto so we never try to route an image there.
                            if viewModel.syndicationChoice == .threads {
                                viewModel.syndicationChoice = .auto
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    viewModel.saveCurrentDraft()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(
                    viewModel.isPosting ||
                    viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button {
                    scheduledAt = Date().addingTimeInterval(3600)
                    isShowingSchedulePost = true
                    isComposerFocused = false
                } label: {
                    Label("Schedule", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                .disabled(
                    viewModel.isPosting ||
                    viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    viewModel.composerText.count > 1000
                )

                postSplitButton
            }
            .controlSize(.small)
        }
        .padding()
    }

    private var isPostDisabled: Bool {
        viewModel.isPosting ||
        viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        viewModel.composerText.count > 1000
    }

    private var postSplitButton: some View {
        HStack(spacing: 0) {
            Button {
                Task {
                    let image = composerImage
                    composerImage = nil
                    composerImageItem = nil
                    await viewModel.submitPost(image: image)
                    isComposerFocused = false
                }
            } label: {
                Group {
                    if viewModel.isPosting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Post")
                            .fontWeight(.semibold)
                    }
                }
                .frame(minWidth: 44, minHeight: 30)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            .disabled(isPostDisabled)
            .opacity(isPostDisabled && !viewModel.isPosting ? 0.55 : 1)

            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(width: 1, height: 18)

            Menu {
                Section {
                    syndicationOption(.auto)
                    syndicationOption(.none)
                }
                Section("Force a platform") {
                    syndicationOption(.x)
                    syndicationOption(.threads)
                    syndicationOption(.bluesky)
                }
            } label: {
                Image(systemName: viewModel.syndicationChoice.triggerSystemImage)
                    .font(.caption.weight(.bold))
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPosting)
            .accessibilityLabel("Syndication options")
        }
        .foregroundStyle(.white)
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .opacity(viewModel.isPosting ? 0.75 : 1)
    }

    /// One row in the routing menu. Shows a checkmark on the current choice so
    /// the flat list behaves like a single-select (radio) group. Threads is
    /// disabled while a photo is attached, since Threads syndication is
    /// text-only.
    @ViewBuilder
    private func syndicationOption(_ choice: SyndicationChoice) -> some View {
        let isDisabled = choice == .threads && composerImage != nil
        Button {
            viewModel.syndicationChoice = choice
        } label: {
            if viewModel.syndicationChoice == choice {
                Label(choice.menuLabel, systemImage: "checkmark")
            } else if isDisabled {
                Text("\(choice.menuLabel) (no photos)")
            } else {
                Text(choice.menuLabel)
            }
        }
        .disabled(isDisabled)
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

                            HStack(spacing: 6) {
                                if post.parentId != nil {
                                    Image(systemName: "arrowshape.turn.up.left")
                                }

                                Text(post.formattedDate)

                                if let pendingStatus = viewModel.pendingStatusText(for: post) {
                                    Text(pendingStatus)
                                        .foregroundStyle(viewModel.hasFailedToSync(post) ? .red : .secondary)
                                }

                                Spacer()

                                if post.hasImage {
                                    Text("Photo")
                                }

                                if let label = post.primaryPlatformLabel {
                                    Text(label)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let url = post.platformURL {
                                openURL(url)
                            }
                        }
                        .contextMenu {
                            if !viewModel.isPendingPost(post) {
                                Button("Edit") {
                                    editingPost = post
                                }
                                Button {
                                    replyingTo = post
                                } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
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

private struct SchedulePostView: View {
    let bodyText: String
    let onSchedule: (Date) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var scheduledAt: Date

    init(
        bodyText: String,
        defaultScheduledAt: Date,
        onSchedule: @escaping (Date) -> Bool
    ) {
        self.bodyText = bodyText
        self.onSchedule = onSchedule
        _scheduledAt = State(initialValue: defaultScheduledAt)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(bodyText)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    DatePicker(
                        "Post at",
                        selection: $scheduledAt,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Schedule post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        if onSchedule(scheduledAt) {
                            dismiss()
                        }
                    }
                    .disabled(scheduledAt <= Date())
                }
            }
        }
    }
}

private struct ScheduledPostsView: View {
    let scheduledPosts: [ScheduledPost]
    let onSelect: (ScheduledPost) -> Void
    let onDelete: (ScheduledPost) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if scheduledPosts.isEmpty {
                    ContentUnavailableView(
                        "No scheduled posts",
                        systemImage: "calendar",
                        description: Text("Scheduled posts will appear here.")
                    )
                } else {
                    List {
                        ForEach(scheduledPosts) { scheduledPost in
                            Button {
                                onSelect(scheduledPost)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(scheduledPost.previewText)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 8) {
                                        Text("Posts \(scheduledPost.formattedScheduledAt)")
                                            .foregroundStyle(.secondary)

                                        if scheduledPost.lastError != nil {
                                            Text("Failed")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    .font(.caption)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    onDelete(scheduledPost)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Scheduled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DraftsView: View {
    let drafts: [DraftPost]
    let activeDraftID: DraftPost.ID?
    let onSelect: (DraftPost) -> Void
    let onDelete: (DraftPost) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    ContentUnavailableView(
                        "No drafts",
                        systemImage: "doc.text",
                        description: Text("Saved drafts will appear here.")
                    )
                } else {
                    List {
                        ForEach(drafts) { draft in
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    onSelect(draft)
                                    dismiss()
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(draft.previewText)
                                                .lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                                .foregroundStyle(.primary)

                                            Text("Saved \(draft.formattedUpdatedAt)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if draft.id == activeDraftID {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    onDelete(draft)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete draft")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    onDelete(draft)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ReplyView: View {
    let parentPost: MicroPost
    let onReply: (String, UIImage?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var replyText = ""
    @State private var replyImage: UIImage?
    @State private var replyImageItem: PhotosPickerItem?
    @State private var isPosting = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Replying to")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(parentPost.body)
                        .lineLimit(5)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                TextEditor(text: $replyText)
                    .focused($isFocused)
                    .frame(minHeight: 120)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                if let replyImage {
                    HStack {
                        Image(uiImage: replyImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            self.replyImage = nil
                            replyImageItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }

                HStack {
                    PhotosPicker(selection: $replyImageItem, matching: .images) {
                        Image(systemName: "photo")
                    }
                    .buttonStyle(.borderless)
                    .onChange(of: replyImageItem) { item in
                        Task {
                            guard let item else { return }
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                replyImage = image
                            }
                        }
                    }

                    Text("\(replyText.count)/1000")
                        .font(.caption)
                        .foregroundStyle(replyText.count > 1000 ? .red : .secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPosting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isPosting = true
                            let image = replyImage
                            await onReply(replyText, image)
                            isPosting = false
                            dismiss()
                        }
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Reply")
                        }
                    }
                    .disabled(
                        isPosting ||
                        replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        replyText.count > 1000
                    )
                }
            }
            .task { isFocused = true }
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
