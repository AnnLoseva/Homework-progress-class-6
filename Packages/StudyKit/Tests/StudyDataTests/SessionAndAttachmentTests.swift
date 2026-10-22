import Foundation
import Testing
@testable import StudyData
@testable import StudyDomain

/// A scripted auth backend.
actor FakeAuth: AuthService {
    var storedSession: AuthSession?
    var refreshSucceeds = true
    var signInError: BackendError?
    var deleteError: BackendError?
    private(set) var signOutCount = 0
    private(set) var deletedWithCode: String??

    init(storedSession: AuthSession? = nil) { self.storedSession = storedSession }

    func setRefreshSucceeds(_ value: Bool) { refreshSucceeds = value }
    func setSignInError(_ error: BackendError?) { signInError = error }
    func setDeleteError(_ error: BackendError?) { deleteError = error }

    func restoreSession() async -> AuthSession? { refreshSucceeds ? storedSession : nil }

    func signInWithApple(_ credential: AppleIDCredential) async throws -> AuthSession {
        if let signInError { throw signInError }
        let session = AuthSession(userID: UUID())
        storedSession = session
        return session
    }

    func signOut() async {
        signOutCount += 1
        storedSession = nil
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        if let deleteError { throw deleteError }
        deletedWithCode = .some(appleAuthorizationCode)
    }
}

struct FakeChecker: AppleCredentialChecker {
    let revoked: Bool
    func isRevoked(appleUserID: String) async -> Bool { revoked }
}

final class MemoryAppleIDStore: AppleUserIDStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    init(_ value: String? = nil) { self.value = value }
    func load() -> String? { lock.withLock { value } }
    func save(_ id: String?) { lock.withLock { value = id } }
}

@MainActor
@Suite("Session")
struct SessionControllerTests {
    let credential = AppleIDCredential(identityToken: "header.payload.sig", rawNonce: "nonce", appleUserID: "001234.abc", authorizationCode: "code")

    func make(_ auth: FakeAuth, revoked: Bool = false, appleID: String? = nil, cleared: Recorder<UUID> = Recorder()) -> SessionController {
        SessionController(auth: auth, credentialChecker: FakeChecker(revoked: revoked),
                          appleUserIDStore: MemoryAppleIDStore(appleID), clearLocalData: { cleared.append($0) })
    }

    @Test func successfulSignInWithApple() async {
        let auth = FakeAuth()
        let session = make(auth)
        await session.restore()
        #expect(session.state == .signedOut)
        await session.signIn(with: credential)
        guard case .signedIn = session.state else { Issue.record("expected signed in"); return }
        #expect(session.notice == nil)
    }

    @Test func failedSignInExplainsWhatHappened() async {
        let auth = FakeAuth()
        await auth.setSignInError(.offline)
        let session = make(auth)
        await session.signIn(with: credential)
        #expect(session.state == .signedOut)
        guard case .signInFailed(let message) = session.notice else { Issue.record("expected a notice"); return }
        #expect(message.contains("offline"))
    }

    @Test func sessionIsRestoredAfterRelaunch() async {
        let user = UUID()
        let session = make(FakeAuth(storedSession: AuthSession(userID: user)), appleID: "001234.abc")
        await session.restore()
        #expect(session.state == .signedIn(AuthSession(userID: user)))
    }

    @Test func revokedAppleIDSignsOutAndClearsLocalData() async {
        let user = UUID()
        let cleared = Recorder<UUID>()
        let session = make(FakeAuth(storedSession: AuthSession(userID: user)), revoked: true, appleID: "001234.abc", cleared: cleared)
        await session.restore()
        #expect(session.state == .signedOut)
        #expect(session.notice == .appleCredentialRevoked)
        #expect(cleared.values == [user])
    }

    @Test func signOutClearsTheDeviceCache() async {
        let auth = FakeAuth()
        let cleared = Recorder<UUID>()
        let session = make(auth, cleared: cleared)
        await session.signIn(with: credential)
        let user = session.currentUserID!
        await session.signOut()
        #expect(session.state == .signedOut)
        #expect(cleared.values == [user])
        #expect(await auth.signOutCount == 1)
    }

    @Test func expiredSessionThatCannotRefreshSignsOutWithAnExplanation() async {
        let auth = FakeAuth(storedSession: AuthSession(userID: UUID()))
        let session = make(auth)
        await session.restore()
        await auth.setRefreshSucceeds(false)
        await session.handleUnauthorized()
        #expect(session.state == .signedOut)
        #expect(session.notice == .sessionExpired)
    }

    @Test func expiredSessionThatRefreshesStaysSignedIn() async {
        let user = UUID()
        let session = make(FakeAuth(storedSession: AuthSession(userID: user)))
        await session.restore()
        await session.handleUnauthorized()
        #expect(session.state == .signedIn(AuthSession(userID: user)))
    }

    @Test func accountDeletionDeletesServerDataThenLocalData() async throws {
        let auth = FakeAuth()
        let cleared = Recorder<UUID>()
        let session = make(auth, cleared: cleared)
        await session.signIn(with: credential)
        let user = session.currentUserID!
        try await session.deleteAccount(appleAuthorizationCode: "fresh-code")
        #expect(await auth.deletedWithCode == .some("fresh-code"))
        #expect(session.state == .signedOut)
        #expect(session.notice == .accountDeleted)
        #expect(cleared.values == [user])
    }

    @Test func failedAccountDeletionKeepsTheUserSignedIn() async {
        let auth = FakeAuth()
        await auth.setDeleteError(.server("HTTP 500"))
        let cleared = Recorder<UUID>()
        let session = make(auth, cleared: cleared)
        await session.signIn(with: credential)
        await #expect(throws: BackendError.server("HTTP 500")) { try await session.deleteAccount(appleAuthorizationCode: nil) }
        guard case .signedIn = session.state else { Issue.record("should still be signed in"); return }
        #expect(cleared.values.isEmpty, "nothing is wiped if the server didn't delete the account")
    }

    @Test func accountDeletionOnTheServerRemovesAllPersonalData() async throws {
        let clock = TestClock()
        let user = UUID()
        let server = await makeServer(clock: clock, students: [user])
        let api = InMemoryConnection(server: server, userID: user)
        _ = try await api.saveProgress(LessonProgress(lessonID: Lessons.logic, status: .inProgress, completedExercises: 1, notes: "n"))
        let auth = DemoAuthService(server: server, userID: user, isAdmin: false, startSignedIn: true)
        try await auth.deleteAccount(appleAuthorizationCode: nil)
        #expect(await server.hasUser(user) == false)
        await #expect(throws: BackendError.unauthorized) { _ = try await api.fetchProgress() }
    }
}

@Suite("Attachments")
struct AttachmentTests {
    let clock = TestClock()

    func setup(enrolled: Bool = true) async throws -> (InMemoryServer, InMemoryConnection, AttachmentRepository, Catalog, NetworkSwitch) {
        let user = UUID()
        let server = await makeServer(clock: clock, students: [user], enrolled: enrolled)
        let network = NetworkSwitch()
        let connection = InMemoryConnection(server: server, userID: user, network: network)
        let repository = AttachmentRepository(cache: AttachmentCache(directory: temporaryDirectory()), backend: connection)
        return (server, connection, repository, try await connection.fetchCatalog(), network)
    }

    @Test func downloadedPDFsOpenOffline() async throws {
        let (_, _, repository, catalog, network) = try await setup()
        let sheet = try #require(catalog.attachments(for: Lessons.vectors).first)
        let url = try await repository.file(for: sheet)
        #expect(AttachmentValidator.looksLikePDF(try Data(contentsOf: url)))
        #expect(url.lastPathComponent.hasSuffix(".pdf"), "the share sheet gets a real .pdf file")

        network.isOnline = false
        #expect(try await repository.file(for: sheet) == url)
    }

    @Test func notDownloadedAndOffline() async throws {
        let (_, _, repository, catalog, network) = try await setup()
        network.isOnline = false
        let sheet = try #require(catalog.attachments(for: Lessons.vectors).first)
        await #expect(throws: AttachmentError.offlineNotDownloaded) { _ = try await repository.file(for: sheet) }
    }

    @Test func missingFileIsReported() async throws {
        let (server, _, repository, catalog, _) = try await setup()
        let sheet = try #require(catalog.attachments(for: Lessons.vectors).first)
        await server.removeFile(sheet.storagePath)
        await #expect(throws: AttachmentError.missing) { _ = try await repository.file(for: sheet) }
    }

    @Test func restrictedFilesNeedClassMembership() async throws {
        let (_, _, repository, catalog, _) = try await setup(enrolled: false)
        let restricted = try #require(catalog.attachments.first { $0.visibility == .restricted })
        let open = try #require(catalog.attachments.first { $0.visibility == .public })
        await #expect(throws: AttachmentError.notAuthorized) { _ = try await repository.file(for: restricted) }
        _ = try await repository.file(for: open)
    }

    @Test func aReplacedPDFIsDownloadedAgain() async throws {
        let (server, _, repository, catalog, _) = try await setup()
        let sheet = try #require(catalog.attachments(for: Lessons.vectors).first)
        let first = try await repository.file(for: sheet)

        let admin = UUID()
        await server.addUser(admin, isAdmin: true)
        let replaced = try await InMemoryConnection(server: server, userID: admin).uploadAttachment(AttachmentUpload(
            lessonID: sheet.lessonID, attachmentID: sheet.id, replacingVersion: sheet.version, title: sheet.title,
            visibility: sheet.visibility, fileName: "new.pdf", data: SamplePDF.make(title: "Second edition", lines: [])))
        #expect(replaced.id == sheet.id)

        let second = try await repository.file(for: replaced)
        #expect(second != first)
        #expect(String(decoding: try Data(contentsOf: second), as: UTF8.self).contains("Second edition"))
        #expect(!FileManager.default.fileExists(atPath: first.path), "the old version is removed from the cache")
    }

    @Test func nonPDFDownloadsAreRejected() async throws {
        let repository = AttachmentRepository(cache: AttachmentCache(directory: temporaryDirectory()),
                                              download: { _ in Data("<html>login</html>".utf8) })
        let attachment = LessonAttachment(lessonID: UUID(), title: "x", fileName: "x.pdf", byteSize: 10)
        await #expect(throws: AttachmentError.corrupt) { _ = try await repository.file(for: attachment) }
    }
}

@MainActor
@Suite("Administrator")
struct AdminStoreTests {
    let clock = TestClock()

    @Test func adminCreatesAndPublishesALessonWithAPDF() async throws {
        let admin = UUID(), student = UUID()
        let server = await makeServer(clock: clock, students: [student], admins: [admin])
        let store = AdminStore(backend: InMemoryConnection(server: server, userID: admin))
        await store.load()
        #expect(store.catalog.lesson(Lessons.draft) != nil, "admins see drafts")

        let course = try #require(store.catalog.courses.first)
        let lesson = try await store.save(LessonDraft(courseID: course.id, title: "Graphs", category: .optional, week: 4, exerciseCount: 3))
        #expect(lesson.status == .draft)
        try await store.upload(AttachmentUpload(lessonID: lesson.id, title: "Graph sheet", visibility: .restricted,
                                                fileName: "graphs.pdf", data: SamplePDF.make(title: "Graphs", lines: [])))

        let studentAPI = InMemoryConnection(server: server, userID: student)
        #expect(try await studentAPI.fetchCatalog().lesson(lesson.id) == nil, "not visible before publishing")
        try await store.setStatus(.published, lessonID: lesson.id)
        let published = try await studentAPI.fetchCatalog()
        #expect(published.lesson(lesson.id)?.status == .published)
        #expect(published.attachments(for: lesson.id).count == 1)
    }

    @Test func invalidFilesAreRejectedBeforeUpload() async throws {
        let admin = UUID()
        let server = await makeServer(clock: clock, admins: [admin])
        let store = AdminStore(backend: InMemoryConnection(server: server, userID: admin))
        await #expect(throws: AttachmentValidationError.notAPDF) {
            try await store.upload(AttachmentUpload(lessonID: Lessons.vectors, title: "x", visibility: .public,
                                                    fileName: "x.pdf", data: Data("not a pdf".utf8)))
        }
    }

    @Test func uploadFailureLeavesNothingBehind() async throws {
        let admin = UUID()
        let server = await makeServer(clock: clock, admins: [admin])
        let network = NetworkSwitch()
        let store = AdminStore(backend: InMemoryConnection(server: server, userID: admin, network: network))
        await store.load()
        let before = store.catalog.attachments.count
        network.isOnline = false
        let upload = AttachmentUpload(lessonID: Lessons.vectors, title: "x", visibility: .public, fileName: "x.pdf",
                                      data: SamplePDF.make(title: "x", lines: []))
        await #expect(throws: BackendError.offline) { try await store.upload(upload) }
        #expect(store.catalog.attachments.count == before)
        #expect(store.errorMessage?.contains("offline") == true)
        #expect(await server.storedFile(upload.storagePath) == nil)
    }

    @Test func studentsCannotUseAdministratorOperations() async {
        let student = UUID()
        let server = await makeServer(clock: clock, students: [student])
        let store = AdminStore(backend: InMemoryConnection(server: server, userID: student))
        await #expect(throws: BackendError.self) {
            try await store.save(LessonDraft(courseID: UUID(), title: "Fake", category: .required))
        }
        await #expect(throws: BackendError.self) { try await store.setStatus(.published, lessonID: Lessons.draft) }
        await #expect(throws: BackendError.self) { try await store.setClassJoinCode("SNEAKY-CODE") }
    }

    @Test func lessonsWithStudentProgressCannotBeDeleted() async throws {
        let admin = UUID(), student = UUID()
        let server = await makeServer(clock: clock, students: [student], admins: [admin])
        _ = try await InMemoryConnection(server: server, userID: student)
            .saveProgress(LessonProgress(lessonID: Lessons.logic, status: .inProgress, completedExercises: 1))
        let store = AdminStore(backend: InMemoryConnection(server: server, userID: admin))
        await #expect(throws: BackendError.self) { try await store.deleteLesson(Lessons.logic) }
        #expect(store.errorMessage?.contains("Archive") == true)
    }

    @Test func draftsCannotBeArchived() async {
        let admin = UUID()
        let server = await makeServer(clock: clock, admins: [admin])
        let store = AdminStore(backend: InMemoryConnection(server: server, userID: admin))
        await #expect(throws: BackendError.self) { try await store.setStatus(.archived, lessonID: Lessons.draft) }
    }
}

@Suite("Snapshot cache")
struct SnapshotTests {
    @Test func roundTripsAndDeletes() async throws {
        let store = SnapshotStore(directory: temporaryDirectory())
        let user = UUID()
        let (catalog, _) = DemoContent.makeCatalog(now: Date())
        var snapshot = StudentSnapshot(catalog: catalog, lastSyncedAt: Date(timeIntervalSince1970: 1_790_000_000.123))
        snapshot.enqueue(PendingChange(kind: .subscription(lessonID: Lessons.puzzles, active: true), queuedAt: Date()))
        try await store.save(snapshot, userID: user)
        let loaded = try #require(await store.load(userID: user))
        #expect(loaded.catalog == catalog)
        #expect(loaded.outbox.count == 1)
        #expect(abs(loaded.lastSyncedAt!.timeIntervalSince1970 - 1_790_000_000.123) < 0.001)
        await store.delete(userID: user)
        #expect(await store.load(userID: user) == nil)
    }

    @Test func aNewerQueuedChangeReplacesAnOlderOneForTheSameLesson() {
        var snapshot = StudentSnapshot()
        snapshot.enqueue(PendingChange(kind: .subscription(lessonID: Lessons.puzzles, active: true), queuedAt: Date()))
        snapshot.enqueue(PendingChange(kind: .progress(LessonProgress(lessonID: Lessons.puzzles)), queuedAt: Date()))
        snapshot.enqueue(PendingChange(kind: .subscription(lessonID: Lessons.puzzles, active: false), queuedAt: Date()))
        #expect(snapshot.outbox.count == 2)
        #expect(snapshot.outbox.last?.kind == .subscription(lessonID: Lessons.puzzles, active: false))
    }

    @Test func backoffGrowsAndIsCapped() {
        #expect(RetryPolicy.delay(afterAttempt: 1) == 2)
        #expect(RetryPolicy.delay(afterAttempt: 3) == 8)
        #expect(RetryPolicy.delay(afterAttempt: 20) == 120)
    }

    @Test func samplePDFIsAValidPDF() {
        let data = SamplePDF.make(title: "Hello (world)", lines: ["Line"])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("%PDF-1.4"))
        #expect(text.hasSuffix("%%EOF\n"))
        #expect(text.contains("Hello \\(world\\)"))
    }
}
