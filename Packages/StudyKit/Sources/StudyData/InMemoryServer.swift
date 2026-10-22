import Foundation
import StudyDomain

/// A small in-process stand-in for the Supabase backend, used by demo mode, previews and
/// tests. It applies the same rules as the database (ownership, required lessons, progress
/// validation, last-writer-wins, restricted files), but it is NOT a security boundary: the
/// SQL suites in supabase/tests are what prove the real backend is safe.
public actor InMemoryServer {
    private struct UserState {
        var subscriptions: [UUID: LessonSubscription] = [:]
        var progress: [UUID: LessonProgress] = [:]
        var isEnrolled = false
        var displayName: String?
    }

    private var courses: [UUID: Course] = [:]
    private var lessons: [UUID: Lesson] = [:]
    private var attachments: [UUID: LessonAttachment] = [:]
    private var files: [String: Data] = [:]
    private var users: [UUID: UserState] = [:]
    private var admins: Set<UUID> = []
    private var classCode: String?
    private var classCodeUpdatedAt: Date?
    private let now: @Sendable () -> Date

    /// Counts calls, so tests can check that retries don't duplicate work.
    public private(set) var writeCount = 0

    public init(catalog: Catalog = .empty, files: [String: Data] = [:], now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        for course in catalog.courses { courses[course.id] = course }
        for lesson in catalog.lessons { lessons[lesson.id] = lesson }
        for attachment in catalog.attachments { attachments[attachment.id] = attachment }
        self.files = files
    }

    // MARK: Test & demo setup

    public func addUser(_ id: UUID, isAdmin: Bool = false, isEnrolled: Bool = false) {
        if users[id] == nil { users[id] = UserState() }
        users[id]?.isEnrolled = isEnrolled || isAdmin
        if isAdmin { admins.insert(id) }
    }

    public func deleteUser(_ id: UUID) {
        users[id] = nil
        admins.remove(id)
    }

    public func hasUser(_ id: UUID) -> Bool { users[id] != nil }

    public func storedProgress(userID: UUID, lessonID: UUID) -> LessonProgress? {
        users[userID]?.progress[lessonID]
    }

    public func storedFile(_ path: String) -> Data? { files[path] }

    public func removeFile(_ path: String) { files[path] = nil }

    public func setLessonCategory(_ lessonID: UUID, _ category: LessonCategory) {
        guard var lesson = lessons[lessonID] else { return }
        let old = lesson.category
        lesson.category = category
        lessons[lessonID] = lesson
        // Same behavior as private.lessons_after_category_change.
        if old == .required, category == .optional, lesson.status == .published {
            for (userID, state) in users {
                if let row = state.progress[lessonID], row.status != .notStarted || !row.notes.isEmpty {
                    users[userID]?.subscriptions[lessonID] = LessonSubscription(lessonID: lessonID, isActive: true, subscribedAt: now())
                }
            }
        }
    }

    // MARK: Student operations

    func identity(_ userID: UUID) throws -> UserIdentity {
        guard let state = users[userID] else { throw BackendError.unauthorized }
        return UserIdentity(userID: userID, isAdmin: admins.contains(userID),
                            isEnrolled: state.isEnrolled || admins.contains(userID), displayName: state.displayName)
    }

    func catalog(for userID: UUID, includeDrafts: Bool) throws -> Catalog {
        if includeDrafts { guard admins.contains(userID) else { throw BackendError.forbidden("Administrator role required") } }
        let date = now()
        let visibleLessons = lessons.values.filter { includeDrafts || $0.isVisibleToStudents(at: date) }
        let visibleIDs = Set(visibleLessons.map(\.id))
        return Catalog(
            courses: courses.values.sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) },
            lessons: visibleLessons.sorted { ($0.week ?? 0, $0.sortOrder) < ($1.week ?? 0, $1.sortOrder) },
            attachments: attachments.values.filter { visibleIDs.contains($0.lessonID) }.sorted { $0.sortOrder < $1.sortOrder }
        )
    }

    func subscriptions(_ userID: UUID) throws -> [LessonSubscription] {
        guard let state = users[userID] else { throw BackendError.unauthorized }
        return Array(state.subscriptions.values)
    }

    func progress(_ userID: UUID) throws -> [LessonProgress] {
        guard let state = users[userID] else { throw BackendError.unauthorized }
        return Array(state.progress.values)
    }

    func setSubscription(_ userID: UUID, lessonID: UUID, active: Bool) throws -> LessonSubscription {
        guard users[userID] != nil else { throw BackendError.unauthorized }
        guard let lesson = lessons[lessonID] else { throw BackendError.notFound }
        writeCount += 1
        if lesson.category == .required {
            throw BackendError.rejected(active
                ? "Required lessons are always in your workload; no subscription is needed"
                : "Required lessons cannot be removed from your workload")
        }
        let existing = users[userID]!.subscriptions[lessonID]
        if existing?.isActive == active, let existing { return existing }
        if active, !lesson.isActive(at: now()) {
            throw BackendError.rejected("Only published lessons can be subscribed to")
        }
        var row = existing ?? LessonSubscription(lessonID: lessonID, isActive: active, subscribedAt: now())
        row.isActive = active
        if active { row.subscribedAt = now(); row.unsubscribedAt = nil } else { row.unsubscribedAt = now() }
        users[userID]!.subscriptions[lessonID] = row
        return row
    }

    func saveProgress(_ userID: UUID, _ incoming: LessonProgress) throws -> LessonProgress {
        guard users[userID] != nil else { throw BackendError.unauthorized }
        guard let lesson = lessons[incoming.lessonID] else { throw BackendError.notFound }
        writeCount += 1
        do {
            try ProgressRules.validate(incoming, for: lesson, now: now())
        } catch {
            throw BackendError.rejected("Invalid progress: \(error)")
        }
        let date = now()
        var row = incoming
        row.clientModifiedAt = min(incoming.clientModifiedAt, date.addingTimeInterval(300))
        if let existing = users[userID]!.progress[incoming.lessonID] {
            // Last writer (by device time) wins; a stale write returns the newer row.
            guard existing.clientModifiedAt <= row.clientModifiedAt else { return existing }
            row.completedAt = row.status == .completed ? (existing.status == .completed ? existing.completedAt : date) : nil
        } else {
            row.completedAt = row.status == .completed ? date : nil
        }
        row.lastActivityAt = date
        users[userID]!.progress[incoming.lessonID] = row
        return row
    }

    func joinClass(_ userID: UUID, code: String) throws -> JoinClassResult {
        guard users[userID] != nil else { throw BackendError.unauthorized }
        if users[userID]!.isEnrolled { return .alreadyJoined }
        guard let classCode else { return .notConfigured }
        let normalize = { (s: String) in s.uppercased().filter { !$0.isWhitespace && $0 != "-" } }
        guard normalize(code) == normalize(classCode) else { return .invalidCode }
        users[userID]!.isEnrolled = true
        return .joined
    }

    func export(_ userID: UUID) throws -> Data {
        guard let state = users[userID] else { throw BackendError.unauthorized }
        struct Export: Encodable {
            let userID: UUID
            let displayName: String?
            let subscriptions: [LessonSubscription]
            let progress: [LessonProgress]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Export(userID: userID, displayName: state.displayName,
                                         subscriptions: Array(state.subscriptions.values),
                                         progress: Array(state.progress.values)))
    }

    func setDisplayName(_ userID: UUID, _ name: String?) throws {
        guard users[userID] != nil else { throw BackendError.unauthorized }
        users[userID]!.displayName = name
    }

    func download(_ userID: UUID?, _ attachment: LessonAttachment) throws -> Data {
        guard let stored = attachments[attachment.id], stored.storagePath == attachment.storagePath,
              let lesson = lessons[stored.lessonID] else { throw BackendError.notFound }
        let isAdmin = userID.map { admins.contains($0) } ?? false
        if !isAdmin {
            guard lesson.isVisibleToStudents(at: now()) else { throw BackendError.notFound }
            if stored.visibility == .restricted {
                guard let userID, users[userID]?.isEnrolled == true else { throw BackendError.forbidden("Join the class to open this file") }
            }
        }
        guard let data = files[stored.storagePath] else { throw BackendError.notFound }
        return data
    }

    // MARK: Admin operations

    private func requireAdmin(_ userID: UUID) throws {
        guard admins.contains(userID) else { throw BackendError.forbidden("Administrator role required") }
    }

    func saveCourse(_ userID: UUID, _ draft: CourseDraft) throws -> Course {
        try requireAdmin(userID)
        let course = Course(id: draft.id ?? UUID(), slug: draft.slug, title: draft.title,
                            subtitle: draft.subtitle.isEmpty ? nil : draft.subtitle, iconName: draft.iconName,
                            colorKey: draft.colorKey, sortOrder: draft.sortOrder, isArchived: draft.isArchived)
        courses[course.id] = course
        return course
    }

    func saveLesson(_ userID: UUID, _ draft: LessonDraft) throws -> Lesson {
        try requireAdmin(userID)
        guard draft.isValid, let courseID = draft.courseID else { throw BackendError.rejected("Invalid lesson") }
        let date = now()
        var lesson = draft.id.flatMap { lessons[$0] }
            ?? Lesson(id: draft.id ?? UUID(), courseID: courseID, title: draft.trimmedTitle,
                      category: draft.category, createdAt: date, updatedAt: date)
        lesson.courseID = courseID
        lesson.title = draft.trimmedTitle
        lesson.description = draft.description
        lesson.week = draft.week
        lesson.moduleTitle = draft.trimmedModuleTitle
        lesson.sortOrder = draft.sortOrder
        lesson.availableFrom = draft.availableFrom
        lesson.dueAt = draft.dueAt
        lesson.estimatedMinutes = draft.estimatedMinutes
        lesson.exerciseCount = draft.exerciseCount
        lesson.prerequisiteIDs = draft.prerequisiteIDs
        lesson.updatedAt = date
        lessons[lesson.id] = lesson
        if lesson.category != draft.category { setLessonCategory(lesson.id, draft.category) }
        return lessons[lesson.id]!
    }

    func setStatus(_ userID: UUID, lessonID: UUID, status: LessonStatus) throws -> Lesson {
        try requireAdmin(userID)
        guard var lesson = lessons[lessonID] else { throw BackendError.notFound }
        if status == .archived && lesson.publishedAt == nil {
            throw BackendError.rejected("Only a lesson that was published can be archived; delete the draft instead")
        }
        if status == .published, courses[lesson.courseID]?.isArchived ?? true {
            throw BackendError.rejected("Cannot publish a lesson in an archived course")
        }
        lesson.status = status
        if status == .published, lesson.publishedAt == nil { lesson.publishedAt = now() }
        lesson.archivedAt = status == .archived ? now() : nil
        lesson.updatedAt = now()
        lessons[lessonID] = lesson
        return lesson
    }

    func deleteLesson(_ userID: UUID, _ lessonID: UUID) throws {
        try requireAdmin(userID)
        if users.values.contains(where: { $0.progress[lessonID] != nil }) {
            throw BackendError.rejected("Students have progress on this lesson. Archive it instead.")
        }
        lessons[lessonID] = nil
        for attachment in attachments.values where attachment.lessonID == lessonID {
            attachments[attachment.id] = nil
            files[attachment.storagePath] = nil
        }
        for id in users.keys { users[id]?.subscriptions[lessonID] = nil }
    }

    func upload(_ userID: UUID, _ upload: AttachmentUpload) throws -> LessonAttachment {
        try requireAdmin(userID)
        guard lessons[upload.lessonID] != nil else { throw BackendError.notFound }
        do { try upload.validate() } catch { throw BackendError.rejected("Invalid file: \(error)") }
        let previous = attachments[upload.attachmentID]
        if let previous, previous.version != upload.replacingVersion {
            throw BackendError.rejected("The attachment changed since you opened it. Reload and try again.")
        }
        let attachment = LessonAttachment(id: upload.attachmentID, lessonID: upload.lessonID, title: upload.title,
                                          description: upload.description, visibility: upload.visibility,
                                          fileName: (try? AttachmentValidator.sanitizedFileName(upload.fileName)) ?? "lesson.pdf",
                                          byteSize: Int64(upload.data.count), version: upload.version,
                                          sortOrder: upload.sortOrder, updatedAt: now())
        files[attachment.storagePath] = upload.data
        attachments[attachment.id] = attachment
        if let previous { files[previous.storagePath] = nil }
        return attachment
    }

    func updateAttachment(_ userID: UUID, _ attachment: LessonAttachment) throws -> LessonAttachment {
        try requireAdmin(userID)
        guard var stored = attachments[attachment.id] else { throw BackendError.notFound }
        stored.title = attachment.title
        stored.description = attachment.description
        stored.visibility = attachment.visibility
        stored.sortOrder = attachment.sortOrder
        stored.updatedAt = now()
        attachments[stored.id] = stored
        return stored
    }

    func deleteAttachment(_ userID: UUID, _ attachment: LessonAttachment) throws {
        try requireAdmin(userID)
        if let stored = attachments[attachment.id] { files[stored.storagePath] = nil }
        attachments[attachment.id] = nil
    }

    func setClassCode(_ userID: UUID, _ code: String) throws {
        try requireAdmin(userID)
        let normalized = code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard (8...64).contains(normalized.count) else { throw BackendError.rejected("The class code must have 8–64 letters or digits") }
        classCode = code
        classCodeUpdatedAt = now()
    }

    func codeUpdatedAt(_ userID: UUID) throws -> Date? {
        try requireAdmin(userID)
        return classCodeUpdatedAt
    }
}

/// A device's connection to the in-memory server. `network` lets tests and demo mode
/// simulate going offline.
public final class NetworkSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var online = true
    private var queuedFailures: [BackendError] = []

    public init(online: Bool = true) { self.online = online }

    public var isOnline: Bool {
        get { lock.withLock { online } }
        set { lock.withLock { online = newValue } }
    }

    /// The next calls fail with these errors (e.g. a 500), in order.
    public func failNext(_ errors: BackendError...) {
        lock.withLock { queuedFailures.append(contentsOf: errors) }
    }

    func check() throws {
        try lock.withLock {
            if !online { throw BackendError.offline }
            if !queuedFailures.isEmpty { throw queuedFailures.removeFirst() }
        }
    }
}

public struct InMemoryConnection: StudentBackend, AdminBackend {
    public let server: InMemoryServer
    public let userID: UUID
    public let network: NetworkSwitch

    public init(server: InMemoryServer, userID: UUID, network: NetworkSwitch = NetworkSwitch()) {
        self.server = server
        self.userID = userID
        self.network = network
    }

    public func fetchIdentity() async throws -> UserIdentity { try network.check(); return try await server.identity(userID) }
    public func fetchCatalog() async throws -> Catalog { try network.check(); return try await server.catalog(for: userID, includeDrafts: false) }
    public func fetchSubscriptions() async throws -> [LessonSubscription] { try network.check(); return try await server.subscriptions(userID) }
    public func fetchProgress() async throws -> [LessonProgress] { try network.check(); return try await server.progress(userID) }
    public func setSubscription(lessonID: UUID, active: Bool) async throws -> LessonSubscription {
        try network.check(); return try await server.setSubscription(userID, lessonID: lessonID, active: active)
    }
    public func saveProgress(_ progress: LessonProgress) async throws -> LessonProgress {
        try network.check(); return try await server.saveProgress(userID, progress)
    }
    public func joinClass(code: String) async throws -> JoinClassResult { try network.check(); return try await server.joinClass(userID, code: code) }
    public func exportMyData() async throws -> Data { try network.check(); return try await server.export(userID) }
    public func updateDisplayName(_ name: String?) async throws { try network.check(); try await server.setDisplayName(userID, name) }
    public func downloadAttachment(_ attachment: LessonAttachment) async throws -> Data {
        try network.check(); return try await server.download(userID, attachment)
    }

    public func fetchAdminCatalog() async throws -> Catalog { try network.check(); return try await server.catalog(for: userID, includeDrafts: true) }
    public func saveCourse(_ draft: CourseDraft) async throws -> Course { try network.check(); return try await server.saveCourse(userID, draft) }
    public func saveLesson(_ draft: LessonDraft) async throws -> Lesson { try network.check(); return try await server.saveLesson(userID, draft) }
    public func setLessonStatus(_ lessonID: UUID, status: LessonStatus) async throws -> Lesson {
        try network.check(); return try await server.setStatus(userID, lessonID: lessonID, status: status)
    }
    public func deleteLesson(_ lessonID: UUID) async throws { try network.check(); try await server.deleteLesson(userID, lessonID) }
    public func uploadAttachment(_ upload: AttachmentUpload) async throws -> LessonAttachment {
        try network.check(); return try await server.upload(userID, upload)
    }
    public func updateAttachmentDetails(_ attachment: LessonAttachment) async throws -> LessonAttachment {
        try network.check(); return try await server.updateAttachment(userID, attachment)
    }
    public func deleteAttachment(_ attachment: LessonAttachment) async throws { try network.check(); try await server.deleteAttachment(userID, attachment) }
    public func setClassJoinCode(_ code: String) async throws { try network.check(); try await server.setClassCode(userID, code) }
    public func classJoinCodeUpdatedAt() async throws -> Date? { try network.check(); return try await server.codeUpdatedAt(userID) }
}

/// Demo-mode authentication: a fixed local account, no network, no Apple ID.
public actor DemoAuthService: AuthService {
    private let server: InMemoryServer
    private let userID: UUID
    private let isAdmin: Bool
    private var signedIn: Bool

    public init(server: InMemoryServer, userID: UUID, isAdmin: Bool, startSignedIn: Bool) {
        self.server = server
        self.userID = userID
        self.isAdmin = isAdmin
        self.signedIn = startSignedIn
    }

    public func restoreSession() async -> AuthSession? {
        guard signedIn else { return nil }
        await server.addUser(userID, isAdmin: isAdmin, isEnrolled: true)
        return AuthSession(userID: userID)
    }

    public func signInWithApple(_ credential: AppleIDCredential) async throws -> AuthSession {
        signedIn = true
        await server.addUser(userID, isAdmin: isAdmin, isEnrolled: true)
        return AuthSession(userID: userID)
    }

    public func signOut() async { signedIn = false }

    public func deleteAccount(appleAuthorizationCode: String?) async throws {
        await server.deleteUser(userID)
        signedIn = false
    }
}
