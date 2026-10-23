import Foundation
import Testing
@testable import StudyData
@testable import StudyDomain

@MainActor
@Suite("Student store: subscriptions and progress")
struct StudentStoreTests {
    let clock = TestClock()
    let userID = UUID()

    @Test func newStudentSeesRequiredWorkloadAndNoDrafts() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()

        #expect(device.store.catalog.lesson(Lessons.draft) == nil, "drafts never reach students")
        let workload = Set(device.store.dashboard.workload.map(\.lesson.id))
        #expect(workload.contains(Lessons.vectors))
        #expect(workload.contains(Lessons.logic))
        #expect(!workload.contains(Lessons.determinants), "optional lessons wait for a subscription")
        #expect(device.store.dashboard.completedLessonCount == 0)
        #expect(device.store.syncStatus == .idle)
    }

    @Test func subscribeAndUnsubscribeOptionalLessonKeepsProgress() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()

        await device.store.setSubscribed(true, lessonID: Lessons.determinants)
        #expect(device.store.membership(of: device.store.catalog.lesson(Lessons.determinants)!) == .subscribed)
        #expect(device.store.progress(for: Lessons.determinants).status == .notStarted, "subscribing doesn't complete anything")

        clock.advance(1)
        await device.store.setCompletedExercises(5, lessonID: Lessons.determinants)
        clock.advance(1)
        await device.store.setSubscribed(false, lessonID: Lessons.determinants)
        #expect(device.store.membership(of: device.store.catalog.lesson(Lessons.determinants)!) == .available)
        #expect(device.store.progress(for: Lessons.determinants).completedExercises == 5, "unsubscribing keeps progress")
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.determinants)?.completedExercises == 5)

        clock.advance(1)
        await device.store.setSubscribed(true, lessonID: Lessons.determinants)
        await device.store.sync()
        #expect(device.store.progress(for: Lessons.determinants).completedExercises == 5, "resubscribing restores it")
        #expect(device.store.pendingChangeCount == 0)
    }

    @Test func requiredLessonsCannotBeToggledOff() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()

        await device.store.setSubscribed(false, lessonID: Lessons.vectors)
        #expect(device.store.pendingChangeCount == 0, "no request is even queued")
        #expect(device.store.dashboard.workload.contains { $0.lesson.id == Lessons.vectors })

        // A tampered client calling the API directly is refused by the server too.
        await #expect(throws: BackendError.self) {
            _ = try await device.connection.setSubscription(lessonID: Lessons.vectors, active: false)
        }
    }

    @Test func repeatedSubscribeRequestsAreIdempotent() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        for _ in 0..<3 {
            _ = try? await device.connection.setSubscription(lessonID: Lessons.puzzles, active: true)
        }
        await device.store.sync()
        let rows = try? await device.connection.fetchSubscriptions()
        #expect(rows?.filter { $0.lessonID == Lessons.puzzles }.count == 1)
    }

    @Test func dashboardDistinguishesLessonAndExerciseCompletion() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()

        await device.store.setCompletedExercises(8, lessonID: Lessons.vectors)   // 8/8 → completed
        clock.advance(1)
        await device.store.setCompletedExercises(3, lessonID: Lessons.logic)     // 3/6 → in progress
        let summary = device.store.dashboard
        #expect(summary.completedLessonCount == 1)
        #expect(summary.completedExerciseCount == 11)
        #expect(summary.totalExerciseCount == 8 + 10 + 6)   // vectors + matrices + logic
        #expect(summary.requiredInProgress.map(\.lesson.id) == [Lessons.logic])
    }

    @Test func manualCompletionForLessonsWithoutExercises() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        await device.store.setSubscribed(true, lessonID: Lessons.puzzles)
        clock.advance(1)
        await device.store.setStatus(.completed, lessonID: Lessons.puzzles)
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.puzzles)?.status == .completed)
    }

    @Test func notesAreSavedPrivately() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        await device.store.setNotes("Ask about exercise 3", lessonID: Lessons.logic)
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.logic)?.notes == "Ask about exercise 3")
        #expect(device.store.progress(for: Lessons.logic).status == .notStarted, "notes alone don't start a lesson")
    }

    @Test func recentlyOpenedLessonsStayOnTheDevice() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        await device.store.markOpened(Lessons.logic)
        await device.store.markOpened(Lessons.vectors)
        await device.store.markOpened(Lessons.logic)
        #expect(device.store.recentLessons.map(\.id) == [Lessons.logic, Lessons.vectors])
    }

    @Test func joinClassUpdatesEnrollment() async throws {
        let server = await makeServer(clock: clock, students: [userID], enrolled: false)
        let admin = UUID()
        await server.addUser(admin, isAdmin: true)
        try await InMemoryConnection(server: server, userID: admin).setClassJoinCode("FOREST-2026")
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        #expect(device.store.identity?.isEnrolled == false)
        #expect(try await device.store.joinClass(code: "nope-nope") == .invalidCode)
        #expect(try await device.store.joinClass(code: "forest 2026") == .joined)
        #expect(device.store.identity?.isEnrolled == true)
    }

    @Test func exportContainsOnlyMyData() async throws {
        let other = UUID()
        let server = await makeServer(clock: clock, students: [userID, other])
        _ = try await InMemoryConnection(server: server, userID: other)
            .saveProgress(LessonProgress(lessonID: Lessons.logic, status: .inProgress, completedExercises: 1, notes: "other's secret"))
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        await device.store.setNotes("mine", lessonID: Lessons.logic)
        let export = String(decoding: try await device.store.exportMyData(), as: UTF8.self)
        #expect(export.contains("mine"))
        #expect(!export.contains("other's secret"))
    }
}

@MainActor
@Suite("Student store: offline, retries and sync between devices")
struct SyncTests {
    let clock = TestClock()
    let userID = UUID()

    @Test func offlineChangesAreQueuedPersistedAndSentOnReconnect() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()

        device.network.isOnline = false
        await device.store.setCompletedExercises(2, lessonID: Lessons.logic)
        clock.advance(1)
        await device.store.setSubscribed(true, lessonID: Lessons.determinants)
        #expect(device.store.syncStatus == .offline)
        #expect(device.store.pendingChangeCount == 2)
        #expect(device.store.progress(for: Lessons.logic).completedExercises == 2, "optimistic update shows at once")
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.logic) == nil)

        device.network.isOnline = true
        await device.store.sync()
        #expect(device.store.pendingChangeCount == 0)
        #expect(device.store.syncStatus == .idle)
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.logic)?.completedExercises == 2)
    }

    @Test func queuedChangesSurviveAnAppRestart() async {
        let server = await makeServer(clock: clock, students: [userID])
        let cache = temporaryDirectory()
        let first = Device(server: server, userID: userID, clock: clock, cacheDirectory: cache)
        await first.store.start()
        first.network.isOnline = false
        await first.store.setNotes("written on the train", lessonID: Lessons.vectors)
        first.store.stop()

        // "Relaunch": a new store reading the same cache directory.
        let relaunched = Device(server: server, userID: userID, clock: clock, cacheDirectory: cache)
        await relaunched.store.loadCache()
        #expect(relaunched.store.pendingChangeCount == 1)
        #expect(relaunched.store.progress(for: Lessons.vectors).notes == "written on the train")
        #expect(relaunched.store.catalog.lesson(Lessons.vectors) != nil, "the catalog is available offline")

        await relaunched.store.sync()
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.vectors)?.notes == "written on the train")
    }

    @Test func manyOfflineEditsCollapseIntoOneRequestPerLesson() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        device.network.isOnline = false
        for count in 1...6 {
            clock.advance(1)
            await device.store.setCompletedExercises(count, lessonID: Lessons.logic)
        }
        #expect(device.store.pendingChangeCount == 1)
        let writesBefore = await server.writeCount
        device.network.isOnline = true
        await device.store.sync()
        #expect(await server.writeCount == writesBefore + 1)
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.logic)?.status == .completed)
    }

    @Test func transientServerErrorsKeepTheChangeForRetry() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()

        device.network.failNext(.server("HTTP 503"))
        await device.store.setCompletedExercises(1, lessonID: Lessons.vectors)
        #expect(device.store.pendingChangeCount == 1)
        #expect(device.store.syncStatus == .failed("HTTP 503"))

        await device.store.sync()   // the retry
        #expect(device.store.pendingChangeCount == 0)
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.vectors)?.completedExercises == 1)
    }

    @Test func retryingAfterALostResponseDoesNotDuplicate() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        let change = LessonProgress(lessonID: Lessons.logic, status: .inProgress, completedExercises: 2, clientModifiedAt: clock.now)
        // The request reached the server but the response was lost, so the app sends it again.
        _ = try? await device.connection.saveProgress(change)
        _ = try? await device.connection.saveProgress(change)
        let rows = (try? await device.connection.fetchProgress()) ?? []
        #expect(rows.filter { $0.lessonID == Lessons.logic }.count == 1)
        #expect(rows.first { $0.lessonID == Lessons.logic }?.completedExercises == 2)
    }

    @Test func aRejectedChangeIsDroppedAndExplained() async {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        device.network.failNext(.rejected("completed_exercises (9) exceeds the lesson's 8 exercises"))
        await device.store.setCompletedExercises(3, lessonID: Lessons.vectors)
        #expect(device.store.pendingChangeCount == 0)
        #expect(device.store.notice == .changeRejected("completed_exercises (9) exceeds the lesson's 8 exercises"))
        #expect(device.store.progress(for: Lessons.vectors).completedExercises == 0, "the server's state replaces the dropped change")
    }

    @Test func twoDevicesConvergeAndTheNewestChangeWins() async {
        let server = await makeServer(clock: clock, students: [userID])
        let iPhone = Device(server: server, userID: userID, clock: clock)
        let iPad = Device(server: server, userID: userID, clock: clock)
        await iPhone.store.start()
        await iPad.store.start()

        // iPhone edits offline first…
        iPhone.network.isOnline = false
        await iPhone.store.setNotes("old idea (iPhone)", lessonID: Lessons.logic)
        // …then the iPad makes a newer edit online.
        clock.advance(60)
        await iPad.store.setNotes("final answer (iPad)", lessonID: Lessons.logic)
        await iPad.store.setSubscribed(true, lessonID: Lessons.determinants)

        // iPhone reconnects: its older edit must not overwrite the iPad's.
        iPhone.network.isOnline = true
        await iPhone.store.sync()
        #expect(iPhone.store.progress(for: Lessons.logic).notes == "final answer (iPad)")
        #expect(iPhone.store.subscriptions[Lessons.determinants]?.isActive == true, "subscriptions sync too")
        #expect(await server.storedProgress(userID: userID, lessonID: Lessons.logic)?.notes == "final answer (iPad)")

        await iPad.store.sync()
        #expect(iPad.store.progress(for: Lessons.logic) == iPhone.store.progress(for: Lessons.logic))
    }

    @Test func expiredSessionAsksTheAppToReauthenticate() async {
        let server = await makeServer(clock: clock, students: [])   // the user no longer exists → 401
        let calls = Recorder<Int>()
        let device = Device(server: server, userID: userID, clock: clock, onUnauthorized: { calls.append(1) })
        await device.store.start()
        #expect(calls.values.count == 1)
    }

    @Test func contentChangesNeverResetProgress() async throws {
        let admin = UUID()
        let server = await makeServer(clock: clock, students: [userID], admins: [admin])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        await device.store.setCompletedExercises(4, lessonID: Lessons.vectors)
        await device.store.setNotes("keep me", lessonID: Lessons.vectors)

        let adminAPI = InMemoryConnection(server: server, userID: admin)
        var draft = LessonDraft(lesson: device.store.catalog.lesson(Lessons.vectors)!)
        draft.title = "Vectors (revised)"
        draft.exerciseCount = 9
        _ = try await adminAPI.saveLesson(draft)
        let pdf = try #require(device.store.catalog.attachments(for: Lessons.vectors).first)
        _ = try await adminAPI.uploadAttachment(AttachmentUpload(
            lessonID: Lessons.vectors, attachmentID: pdf.id, replacingVersion: pdf.version, title: pdf.title,
            visibility: pdf.visibility, fileName: "v2.pdf", data: SamplePDF.make(title: "v2", lines: [])))
        _ = try await adminAPI.setLessonStatus(Lessons.vectors, status: .archived)
        _ = try await adminAPI.setLessonStatus(Lessons.vectors, status: .published)

        await device.store.sync()
        #expect(device.store.progress(for: Lessons.vectors).completedExercises == 4)
        #expect(device.store.progress(for: Lessons.vectors).notes == "keep me")
        #expect(device.store.catalog.lessons.filter { $0.id == Lessons.vectors }.count == 1)
        #expect(device.store.catalog.attachments(for: Lessons.vectors).first { $0.id == pdf.id }?.version == pdf.version + 1)
    }

    @Test func categoryChangesKeepStartedWorkInTheWorkload() async throws {
        let server = await makeServer(clock: clock, students: [userID])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        await device.store.setCompletedExercises(2, lessonID: Lessons.logic)

        await server.setLessonCategory(Lessons.logic, .optional)          // required → optional
        await device.store.sync()
        #expect(device.store.dashboard.workload.contains { $0.lesson.id == Lessons.logic }, "auto-subscribed")
        #expect(device.store.progress(for: Lessons.logic).completedExercises == 2)

        await server.setLessonCategory(Lessons.logic, .required)          // and back
        await device.store.sync()
        #expect(device.store.membership(of: device.store.catalog.lesson(Lessons.logic)!) == .required)
        #expect(device.store.progress(for: Lessons.logic).completedExercises == 2)
    }

    @Test func archivedLessonsMoveToHistoryWithTheirProgress() async throws {
        let admin = UUID()
        let server = await makeServer(clock: clock, students: [userID], admins: [admin])
        let device = Device(server: server, userID: userID, clock: clock)
        await device.store.start()
        await device.store.setStatus(.completed, lessonID: Lessons.logic)
        _ = try await InMemoryConnection(server: server, userID: admin).setLessonStatus(Lessons.logic, status: .archived)
        await device.store.sync()
        #expect(!device.store.dashboard.workload.contains { $0.lesson.id == Lessons.logic })
        #expect(device.store.history.first { $0.lessonID == Lessons.logic }?.reason == .archived)
        #expect(device.store.history.first { $0.lessonID == Lessons.logic }?.progress.status == .completed)
    }
}
