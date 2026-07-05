//
//  fwitterTests.swift
//  fwitterTests
//
//  Created by Flawnson Tong on 2026-03-30.
//

import Foundation
import XCTest
@testable import fwitter

final class fwitterTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        defaultsSuiteName = "fwitterTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        if let defaultsSuiteName {
            defaults?.removePersistentDomain(forName: defaultsSuiteName)
        }

        defaults = nil
        defaultsSuiteName = nil
    }

    func testSavingDraftCreatesLocalDraft() throws {
        let store = OfflinePostStore(defaults: defaults)

        let draft = store.saveDraft(body: "An unfinished post")
        let savedDrafts = store.savedDrafts()

        XCTAssertEqual(savedDrafts.count, 1)
        XCTAssertEqual(savedDrafts.first?.id, draft.id)
        XCTAssertEqual(savedDrafts.first?.body, "An unfinished post")
    }

    func testSavingExistingDraftUpdatesItInPlace() throws {
        let store = OfflinePostStore(defaults: defaults)
        let draft = store.saveDraft(body: "First version")

        let updatedDraft = store.saveDraft(body: "Second version", id: draft.id)

        XCTAssertEqual(updatedDraft.id, draft.id)
        XCTAssertEqual(updatedDraft.body, "Second version")
        XCTAssertEqual(store.savedDrafts().map(\.id), [draft.id])
        XCTAssertEqual(store.savedDrafts().first?.body, "Second version")
    }

    func testRemovingActiveDraftClearsActiveDraftID() throws {
        let store = OfflinePostStore(defaults: defaults)
        let draft = store.saveDraft(body: "Delete me")
        store.saveActiveDraftId(draft.id)

        store.removeSavedDraft(id: draft.id)

        XCTAssertTrue(store.savedDrafts().isEmpty)
        XCTAssertNil(store.activeDraftId())
    }

    @MainActor
    func testSavingCurrentDraftTwiceKeepsSeparateDrafts() throws {
        let store = OfflinePostStore(defaults: defaults)
        let viewModel = FeedViewModel(offlineStore: store, startsNetworkMonitor: false)

        viewModel.composerText = "First draft"
        viewModel.saveCurrentDraft()
        viewModel.composerText = "Second draft"
        viewModel.saveCurrentDraft()

        let savedBodies = Set(store.savedDrafts().map(\.body))
        XCTAssertEqual(store.savedDrafts().count, 2)
        XCTAssertEqual(savedBodies, ["First draft", "Second draft"])
        XCTAssertNil(viewModel.activeDraftID)
    }

    @MainActor
    func testSavingLoadedDraftUpdatesThenDetachesComposer() throws {
        let store = OfflinePostStore(defaults: defaults)
        let draft = store.saveDraft(body: "Original draft")
        let viewModel = FeedViewModel(offlineStore: store, startsNetworkMonitor: false)

        viewModel.loadDraft(draft)
        viewModel.composerText = "Updated draft"
        viewModel.saveCurrentDraft()
        viewModel.composerText = "New draft"
        viewModel.saveCurrentDraft()

        let savedDrafts = store.savedDrafts()
        XCTAssertEqual(savedDrafts.count, 2)
        XCTAssertEqual(store.savedDraft(id: draft.id)?.body, "Updated draft")
        XCTAssertTrue(savedDrafts.contains { $0.body == "New draft" })
        XCTAssertNil(viewModel.activeDraftID)
    }

    func testSchedulingPostCreatesLocalScheduledPost() throws {
        let store = OfflinePostStore(defaults: defaults)
        let scheduledAt = Date().addingTimeInterval(3600)

        let scheduledPost = store.schedulePost(body: "Post this later", scheduledAt: scheduledAt)
        let savedScheduledPosts = store.scheduledPosts()

        XCTAssertEqual(savedScheduledPosts.count, 1)
        XCTAssertEqual(savedScheduledPosts.first?.id, scheduledPost.id)
        XCTAssertEqual(savedScheduledPosts.first?.body, "Post this later")
        XCTAssertEqual(
            try XCTUnwrap(savedScheduledPosts.first?.scheduledAt).timeIntervalSince1970,
            scheduledAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testDueScheduledPostsReturnsOnlyPostsAtOrBeforeNow() throws {
        let store = OfflinePostStore(defaults: defaults)
        let now = Date()
        let duePost = store.schedulePost(body: "Due", scheduledAt: now.addingTimeInterval(-60))
        _ = store.schedulePost(body: "Later", scheduledAt: now.addingTimeInterval(3600))

        XCTAssertEqual(store.dueScheduledPosts(now: now).map(\.id), [duePost.id])
    }

    func testMarkingScheduledPostFailedPersistsFailure() throws {
        let store = OfflinePostStore(defaults: defaults)
        let scheduledPost = store.schedulePost(
            body: "Try this later",
            scheduledAt: Date().addingTimeInterval(-60)
        )

        store.markScheduledPostFailed(id: scheduledPost.id, errorMessage: "Server error")

        XCTAssertEqual(store.scheduledPosts().first?.lastError, "Server error")
    }
}
