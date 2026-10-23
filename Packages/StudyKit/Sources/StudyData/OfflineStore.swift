import Foundation
import StudyDomain

/// A change made on this device that the server has not confirmed yet.
public struct PendingChange: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: Codable, Equatable, Sendable {
        case progress(LessonProgress)
        case subscription(lessonID: UUID, active: Bool)
    }

    public var id: UUID
    public var kind: Kind
    public var queuedAt: Date
    public var attempts: Int

    public init(id: UUID = UUID(), kind: Kind, queuedAt: Date, attempts: Int = 0) {
        self.id = id
        self.kind = kind
        self.queuedAt = queuedAt
        self.attempts = attempts
    }

    public var lessonID: UUID {
        switch kind {
        case .progress(let progress): progress.lessonID
        case .subscription(let lessonID, _): lessonID
        }
    }

    public var isProgress: Bool {
        if case .progress = kind { true } else { false }
    }

    /// Two changes of the same kind for the same lesson: only the newest needs sending.
    func supersedes(_ other: PendingChange) -> Bool {
        switch (kind, other.kind) {
        case (.progress(let a), .progress(let b)): a.lessonID == b.lessonID
        case (.subscription(let a, _), .subscription(let b, _)): a == b
        default: false
        }
    }
}

/// Everything the app keeps for one signed-in user, so it opens instantly and works offline.
/// The server stays the single source of truth; this is a cache plus the outbox.
public struct StudentSnapshot: Codable, Equatable, Sendable {
    public var identity: UserIdentity?
    public var catalog: Catalog
    public var subscriptions: [UUID: LessonSubscription]
    public var progress: [UUID: LessonProgress]
    public var outbox: [PendingChange]
    public var lastSyncedAt: Date?
    /// Device-only conveniences (never uploaded).
    public var recentLessonIDs: [UUID]
    public var catalogLastSeenAt: Date?

    public init(identity: UserIdentity? = nil, catalog: Catalog = .empty,
                subscriptions: [UUID: LessonSubscription] = [:], progress: [UUID: LessonProgress] = [:],
                outbox: [PendingChange] = [], lastSyncedAt: Date? = nil, recentLessonIDs: [UUID] = [],
                catalogLastSeenAt: Date? = nil) {
        self.identity = identity
        self.catalog = catalog
        self.subscriptions = subscriptions
        self.progress = progress
        self.outbox = outbox
        self.lastSyncedAt = lastSyncedAt
        self.recentLessonIDs = recentLessonIDs
        self.catalogLastSeenAt = catalogLastSeenAt
    }

    public mutating func enqueue(_ change: PendingChange) {
        outbox.removeAll { change.supersedes($0) }
        outbox.append(change)
    }
}

/// Persists one JSON snapshot per user in Application Support, protected by Data
/// Protection and excluded from backups. Deleted on sign-out and account deletion.
public actor SnapshotStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        // Default (Double) date encoding: lossless, so cached timestamps compare exactly.
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("StudentCache", isDirectory: true)
    }

    private func fileURL(for userID: UUID) -> URL {
        directory.appendingPathComponent("\(userID.uuidString.lowercased()).json")
    }

    public func load(userID: UUID) -> StudentSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: userID)) else { return nil }
        // A corrupt or outdated cache is simply rebuilt from the server.
        return try? decoder.decode(StudentSnapshot.self, from: data)
    }

    public func save(_ snapshot: StudentSnapshot, userID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = fileURL(for: userID)
        let data = try encoder.encode(snapshot)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    public func delete(userID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: userID))
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Exponential backoff for transient failures: 2, 4, 8 … seconds, capped at 2 minutes.
public enum RetryPolicy {
    public static func delay(afterAttempt attempt: Int) -> TimeInterval {
        min(pow(2, Double(max(attempt, 1))), 120)
    }
}
