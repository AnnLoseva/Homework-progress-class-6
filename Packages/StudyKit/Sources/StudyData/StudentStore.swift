import Foundation
import Observation
import StudyDomain

public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    /// The last attempt couldn't reach the server; cached data is shown and changes are queued.
    case offline
    case failed(String)
}

/// A message for the student about something that didn't go as expected.
public enum StudentNotice: Equatable, Sendable, Identifiable {
    case changeRejected(String)
    case syncFailed(String)

    public var id: String {
        switch self {
        case .changeRejected(let m): "rejected:\(m)"
        case .syncFailed(let m): "sync:\(m)"
        }
    }
}

/// The student's data on this device: cached catalog, subscriptions and progress, an
/// outbox of unconfirmed changes, and sync with the server.
///
/// Changes are applied locally at once (optimistic), persisted with the outbox, then sent.
/// Transient failures keep them queued and retry with backoff; a server rejection drops the
/// change, tells the student, and reloads the server's version.
@MainActor
@Observable
public final class StudentStore {
    public let userID: UUID

    public private(set) var identity: UserIdentity?
    public private(set) var catalog: Catalog = .empty
    public private(set) var subscriptions: [UUID: LessonSubscription] = [:]
    public private(set) var progress: [UUID: LessonProgress] = [:]
    public private(set) var recentLessonIDs: [UUID] = []
    public private(set) var catalogLastSeenAt: Date?
    public private(set) var lastSyncedAt: Date?
    public private(set) var syncStatus: SyncStatus = .idle
    public private(set) var hasLoadedCache = false
    public var notice: StudentNotice?

    public var pendingChangeCount: Int { outbox.count }

    @ObservationIgnored private var outbox: [PendingChange] = []
    @ObservationIgnored private let backend: any StudentBackend
    @ObservationIgnored private let snapshots: SnapshotStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let onUnauthorized: @MainActor () async -> Void
    @ObservationIgnored private let automaticRetry: Bool
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var consecutiveFailures = 0

    public init(userID: UUID,
                backend: any StudentBackend,
                snapshots: SnapshotStore,
                automaticRetry: Bool = true,
                now: @escaping @Sendable () -> Date = { Date() },
                onUnauthorized: @escaping @MainActor () async -> Void = {}) {
        self.userID = userID
        self.backend = backend
        self.snapshots = snapshots
        self.automaticRetry = automaticRetry
        self.now = now
        self.onUnauthorized = onUnauthorized
    }

    // MARK: - Lifecycle

    /// Shows cached data immediately, then syncs.
    public func start() async {
        await loadCache()
        await sync()
    }

    public func loadCache() async {
        if let snapshot = await snapshots.load(userID: userID) {
            identity = snapshot.identity
            catalog = snapshot.catalog
            subscriptions = snapshot.subscriptions
            progress = snapshot.progress
            outbox = snapshot.outbox
            lastSyncedAt = snapshot.lastSyncedAt
            recentLessonIDs = snapshot.recentLessonIDs
            catalogLastSeenAt = snapshot.catalogLastSeenAt
        }
        hasLoadedCache = true
    }

    /// Sends queued changes, then pulls the latest state. Concurrent calls share one run.
    public func sync() async {
        if let syncTask {
            await syncTask.value
            return
        }
        let task = Task { await performSync() }
        syncTask = task
        await task.value
        syncTask = nil
    }

    public func stop() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func performSync() async {
        retryTask?.cancel()
        syncStatus = .syncing

        switch await flushOutbox() {
        case .unauthorized:
            syncStatus = .idle
            await onUnauthorized()
            return
        case .transient(let error):
            handleTransient(error)
            return
        case .done:
            break
        }

        do {
            async let identity = backend.fetchIdentity()
            async let catalog = backend.fetchCatalog()
            async let subscriptions = backend.fetchSubscriptions()
            async let progress = backend.fetchProgress()
            let (i, c, s, p) = try await (identity, catalog, subscriptions, progress)
            applyServerState(identity: i, catalog: c, subscriptions: s, progress: p)
            lastSyncedAt = now()
            consecutiveFailures = 0
            syncStatus = .idle
            await persist()
        } catch let error as BackendError {
            if error == .unauthorized {
                syncStatus = .idle
                await onUnauthorized()
            } else if error.isTransient {
                handleTransient(error)
            } else {
                syncStatus = .failed(Self.describe(error))
            }
        } catch {
            handleTransient(.server(error.localizedDescription))
        }
    }

    private func handleTransient(_ error: BackendError) {
        consecutiveFailures += 1
        syncStatus = error == .offline ? .offline : .failed(Self.describe(error))
        guard automaticRetry else { return }
        let delay = RetryPolicy.delay(afterAttempt: consecutiveFailures)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Server rows replace cached ones, except where this device still has an unsent change.
    private func applyServerState(identity: UserIdentity, catalog: Catalog,
                                  subscriptions: [LessonSubscription], progress: [LessonProgress]) {
        let pendingProgress = Set(outbox.filter(\.isProgress).map(\.lessonID))
        let pendingSubscriptions = Set(outbox.filter { !$0.isProgress }.map(\.lessonID))

        self.identity = identity
        self.catalog = catalog

        var mergedSubscriptions = Dictionary(subscriptions.map { ($0.lessonID, $0) }, uniquingKeysWith: { $1 })
        for id in pendingSubscriptions { mergedSubscriptions[id] = self.subscriptions[id] }
        self.subscriptions = mergedSubscriptions

        var mergedProgress = Dictionary(progress.map { ($0.lessonID, $0) }, uniquingKeysWith: { $1 })
        for id in pendingProgress { mergedProgress[id] = self.progress[id] }
        self.progress = mergedProgress
    }

    // MARK: - Outbox

    private enum FlushOutcome { case done, transient(BackendError), unauthorized }

    private func flushOutbox() async -> FlushOutcome {
        while let change = outbox.first {
            do {
                switch change.kind {
                case .progress(let local):
                    let stored = try await backend.saveProgress(local)
                    outbox.removeFirst()
                    // The server may have kept a newer row from another device.
                    if !outbox.contains(where: { $0.isProgress && $0.lessonID == stored.lessonID }) {
                        progress[stored.lessonID] = stored
                    }
                case .subscription(let lessonID, let active):
                    let stored = try await backend.setSubscription(lessonID: lessonID, active: active)
                    outbox.removeFirst()
                    if !outbox.contains(where: { !$0.isProgress && $0.lessonID == lessonID }) {
                        subscriptions[lessonID] = stored
                    }
                }
                await persist()
            } catch let error as BackendError {
                switch error {
                case .unauthorized:
                    return .unauthorized
                case .offline, .server:
                    if !outbox.isEmpty { outbox[0].attempts += 1 }
                    await persist()
                    return .transient(error)
                case .forbidden(let message), .rejected(let message):
                    outbox.removeFirst()
                    notice = .changeRejected(message)
                    await persist()
                case .notFound:
                    outbox.removeFirst()
                    notice = .changeRejected(String(localized: "This lesson is no longer available."))
                    await persist()
                }
            } catch {
                if !outbox.isEmpty { outbox[0].attempts += 1 }
                return .transient(.server(error.localizedDescription))
            }
        }
        // After a rejection, the pull that follows replaces the dropped optimistic values.
        return .done
    }

    private func enqueue(_ kind: PendingChange.Kind) async {
        var snapshot = StudentSnapshot(outbox: outbox)
        snapshot.enqueue(PendingChange(kind: kind, queuedAt: now()))
        outbox = snapshot.outbox
        await persist()
        await sync()
    }

    private func persist() async {
        let snapshot = StudentSnapshot(identity: identity, catalog: catalog, subscriptions: subscriptions,
                                       progress: progress, outbox: outbox, lastSyncedAt: lastSyncedAt,
                                       recentLessonIDs: recentLessonIDs, catalogLastSeenAt: catalogLastSeenAt)
        do {
            try await snapshots.save(snapshot, userID: userID)
        } catch {
            notice = .syncFailed(String(localized: "Couldn't save changes on this device: \(error.localizedDescription)"))
        }
    }

    // MARK: - Student actions

    /// Subscribe to or unsubscribe from an OPTIONAL lesson. Required lessons are always part of
    /// the workload and are never toggled here (the server refuses it too).
    public func setSubscribed(_ active: Bool, lessonID: UUID) async {
        guard let lesson = catalog.lesson(lessonID), lesson.category == .optional else { return }
        if active, !lesson.isActive(at: now()) { return }
        guard (subscriptions[lessonID]?.isActive ?? false) != active else { return }
        let date = now()
        var row = subscriptions[lessonID] ?? LessonSubscription(lessonID: lessonID, isActive: active, subscribedAt: date)
        row.isActive = active
        if active { row.subscribedAt = date; row.unsubscribedAt = nil } else { row.unsubscribedAt = date }
        subscriptions[lessonID] = row          // progress is untouched either way
        await enqueue(.subscription(lessonID: lessonID, active: active))
    }

    public func setCompletedExercises(_ count: Int, lessonID: UUID) async {
        await updateProgress(lessonID) { current, lesson, date in
            ProgressRules.settingCompletedExercises(count, on: current, lesson: lesson, at: date)
        }
    }

    public func setStatus(_ status: ProgressStatus, lessonID: UUID) async {
        await updateProgress(lessonID) { current, lesson, date in
            ProgressRules.settingStatus(status, on: current, lesson: lesson, at: date)
        }
    }

    public func setNotes(_ notes: String, lessonID: UUID) async {
        guard notes != progress(for: lessonID).notes else { return }
        await updateProgress(lessonID) { current, lesson, date in
            ProgressRules.settingNotes(notes, on: current, lesson: lesson, at: date)
        }
    }

    private func updateProgress(_ lessonID: UUID,
                                _ transform: (LessonProgress, Lesson, Date) -> LessonProgress) async {
        guard let lesson = catalog.lesson(lessonID) else { return }
        let date = now()
        let current = ProgressRules.clamped(progress(for: lessonID), to: lesson)
        let next = transform(current, lesson, date)
        do {
            try ProgressRules.validate(next, for: lesson, now: date)
        } catch {
            notice = .changeRejected(String(localized: "That change isn't allowed for this lesson."))
            return
        }
        guard next != current else { return }
        progress[lessonID] = next
        await enqueue(.progress(next))
    }

    public func markOpened(_ lessonID: UUID) async {
        recentLessonIDs.removeAll { $0 == lessonID }
        recentLessonIDs.insert(lessonID, at: 0)
        recentLessonIDs = Array(recentLessonIDs.prefix(8))
        await persist()
    }

    public func markCatalogSeen() async {
        catalogLastSeenAt = now()
        await persist()
    }

    public func joinClass(code: String) async throws -> JoinClassResult {
        let result = try await backend.joinClass(code: code)
        if result == .joined || result == .alreadyJoined {
            identity?.isEnrolled = true
            await persist()
        }
        return result
    }

    public func exportMyData() async throws -> Data {
        try await backend.exportMyData()
    }

    public func updateDisplayName(_ name: String?) async throws {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(80))
        try await backend.updateDisplayName(value)
        identity?.displayName = value
        await persist()
    }

    // MARK: - Derived state

    public func progress(for lessonID: UUID) -> LessonProgress {
        progress[lessonID] ?? .empty(for: lessonID, at: .distantPast)
    }

    public func membership(of lesson: Lesson) -> Workload.Membership {
        Workload.membership(of: lesson, subscriptions: subscriptions, now: now())
    }

    public var dashboard: DashboardSummary {
        DashboardSummary.make(catalog: catalog, subscriptions: subscriptions, progress: progress, now: now())
    }

    public var history: [StudyHistory.Entry] {
        StudyHistory.entries(catalog: catalog, subscriptions: subscriptions, progress: progress, now: now())
    }

    public var newLessonIDs: Set<UUID> {
        NewLessons.ids(in: catalog, since: catalogLastSeenAt, now: now())
    }

    public var recentLessons: [Lesson] {
        recentLessonIDs.compactMap { catalog.lesson($0) }.filter { $0.isVisibleToStudents(at: now()) }
    }

    public func lessons(matching query: LessonQuery) -> [Lesson] {
        query.apply(to: catalog, subscriptions: subscriptions, now: now())
    }

    public var currentDate: Date { now() }

    static func describe(_ error: BackendError) -> String {
        switch error {
        case .offline: String(localized: "You're offline. Changes will sync when you reconnect.")
        case .unauthorized: String(localized: "Please sign in again.")
        case .forbidden(let message), .rejected(let message), .server(let message): message
        case .notFound: String(localized: "Not found.")
        }
    }
}
