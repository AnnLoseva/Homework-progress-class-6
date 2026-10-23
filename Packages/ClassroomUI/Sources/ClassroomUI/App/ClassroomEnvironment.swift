import Foundation
import Network
import Observation
import StudyData
import StudyDomain
import StudySupabase
import Supabase

/// Wires the class lessons together: the backend, the session, and the per-user stores.
///
/// The backend is Supabase, configured with `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`
/// (Config/Local.xcconfig → Info.plist). Without a usable configuration the Class area says
/// how to connect it; there is no offline sample content.
@MainActor
@Observable
public final class ClassroomEnvironment {
    public enum Mode: Equatable {
        case supabase
        case notConfigured
    }

    public let mode: Mode
    /// Set when a Supabase configuration exists but is unusable, e.g. a secret key was pasted.
    public let configurationProblem: SupabaseConfiguration.Problem?
    public let session: SessionController

    public private(set) var student: StudentStore?
    public private(set) var admin: AdminStore?
    public private(set) var attachments: AttachmentRepository?

    @ObservationIgnored private let makeStudentBackend: (UUID) -> any StudentBackend
    @ObservationIgnored private let makeAdminBackend: (UUID) -> any AdminBackend
    @ObservationIgnored private let snapshots: SnapshotStore
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var wasOffline = false
    @ObservationIgnored private var isMonitoring = false

    public convenience init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        let configuration = SupabaseConfiguration.fromInfoDictionary(info)
        switch configuration {
        case .success(let config):
            let client = SupabaseClient.make(config)
            let backend = SupabaseStudyBackend(client: client)
            self.init(mode: .supabase, problem: nil, auth: SupabaseAuthService(client: client),
                      credentialChecker: SystemAppleCredentialChecker(), appleUserIDStore: KeychainAppleUserIDStore(),
                      studentBackend: { _ in backend }, adminBackend: { _ in backend })
        case .failure(let problem):
            let backend = UnconfiguredBackend()
            self.init(mode: .notConfigured, problem: problem == .missing ? nil : problem, auth: backend,
                      credentialChecker: nil, appleUserIDStore: InMemoryAppleIDStore(),
                      studentBackend: { _ in backend }, adminBackend: { _ in backend })
        }
    }

    /// Lets tests run the real wiring against an in-memory backend.
    init(mode: Mode, problem: SupabaseConfiguration.Problem?, auth: any AuthService,
         credentialChecker: (any AppleCredentialChecker)?, appleUserIDStore: any AppleUserIDStore,
         studentBackend: @escaping (UUID) -> any StudentBackend, adminBackend: @escaping (UUID) -> any AdminBackend,
         snapshotDirectory: URL = SnapshotStore.defaultDirectory()) {
        self.mode = mode
        configurationProblem = problem
        makeStudentBackend = studentBackend
        makeAdminBackend = adminBackend
        let snapshots = SnapshotStore(directory: snapshotDirectory)
        self.snapshots = snapshots
        session = SessionController(
            auth: auth,
            credentialChecker: credentialChecker,
            appleUserIDStore: appleUserIDStore,
            clearLocalData: { userID in
                await snapshots.delete(userID: userID)
                await AttachmentCache(directory: AttachmentCache.defaultDirectory(for: userID)).removeAll()
            }
        )
    }

    public var isConfigured: Bool { mode == .supabase }

    /// Restores the saved session and starts watching the network. Safe to call repeatedly.
    public func start() async {
        startNetworkMonitoring()
        guard session.state == .restoring else { return }
        await session.restore()
    }

    /// Called whenever the session changes: builds or tears down the per-user stores.
    public func sessionChanged() async {
        guard let userID = session.currentUserID else {
            student?.stop()
            student = nil
            admin = nil
            attachments = nil
            return
        }
        guard student?.userID != userID else { return }
        let store = StudentStore(userID: userID, backend: makeStudentBackend(userID), snapshots: snapshots,
                                 onUnauthorized: { [weak self] in await self?.session.handleUnauthorized() })
        student = store
        attachments = AttachmentRepository(cache: AttachmentCache(directory: AttachmentCache.defaultDirectory(for: userID)),
                                           backend: makeStudentBackend(userID))
        await store.start()
        refreshAdminAccess()
    }

    /// Admin screens appear only when the SERVER says this user is an administrator. Even
    /// then, every admin request is checked again by RLS.
    public func refreshAdminAccess() {
        guard let student, let userID = session.currentUserID else { return }
        if student.identity?.isAdmin == true {
            if admin == nil { admin = AdminStore(backend: makeAdminBackend(userID)) }
        } else {
            admin = nil
        }
    }

    /// Syncs as soon as the network comes back.
    private func startNetworkMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                if online, self.wasOffline { await self.student?.sync() }
                self.wasOffline = !online
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "classroom.network"))
    }
}

/// Used when there is no Supabase configuration: there is no session to restore and signing
/// in explains what is missing. Nothing is stored and nothing is sent.
nonisolated final class UnconfiguredBackend: AuthService, StudentBackend, AdminBackend {
    private var notConnected: BackendError {
        .rejected(String(localized: "Class lessons aren't connected in this build."))
    }

    func restoreSession() async -> AuthSession? { nil }
    func signInWithApple(_ credential: AppleIDCredential) async throws -> AuthSession { throw notConnected }
    func signOut() async {}
    func deleteAccount(appleAuthorizationCode: String?) async throws { throw notConnected }

    func fetchIdentity() async throws -> StudyDomain.UserIdentity { throw notConnected }
    func fetchCatalog() async throws -> Catalog { throw notConnected }
    func fetchSubscriptions() async throws -> [LessonSubscription] { throw notConnected }
    func fetchProgress() async throws -> [LessonProgress] { throw notConnected }
    func setSubscription(lessonID: UUID, active: Bool) async throws -> LessonSubscription { throw notConnected }
    func saveProgress(_ progress: LessonProgress) async throws -> LessonProgress { throw notConnected }
    func joinClass(code: String) async throws -> JoinClassResult { throw notConnected }
    func exportMyData() async throws -> Data { throw notConnected }
    func updateDisplayName(_ name: String?) async throws { throw notConnected }
    func downloadAttachment(_ attachment: LessonAttachment) async throws -> Data { throw notConnected }

    func fetchAdminCatalog() async throws -> Catalog { throw notConnected }
    func saveCourse(_ draft: CourseDraft) async throws -> Course { throw notConnected }
    func saveLesson(_ draft: LessonDraft) async throws -> Lesson { throw notConnected }
    func setLessonStatus(_ lessonID: UUID, status: LessonStatus) async throws -> Lesson { throw notConnected }
    func deleteLesson(_ lessonID: UUID) async throws { throw notConnected }
    func uploadAttachment(_ upload: AttachmentUpload) async throws -> LessonAttachment { throw notConnected }
    func updateAttachmentDetails(_ attachment: LessonAttachment) async throws -> LessonAttachment { throw notConnected }
    func deleteAttachment(_ attachment: LessonAttachment) async throws { throw notConnected }
    func setClassJoinCode(_ code: String) async throws { throw notConnected }
    func classJoinCodeUpdatedAt() async throws -> Date? { throw notConnected }
}

/// The Keychain is only used once a real backend is configured.
final class InMemoryAppleIDStore: AppleUserIDStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func load() -> String? { lock.withLock { value } }
    func save(_ id: String?) { lock.withLock { value = id } }
}
