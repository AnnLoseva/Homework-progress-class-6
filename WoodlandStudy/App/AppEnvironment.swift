import Foundation
import Network
import Observation
import StudyData
import StudyDomain
import StudySupabase
import Supabase

/// Wires the app together: which backend to use, the session, and the per-user stores.
///
/// Modes:
/// * **Supabase**: `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are set (Config/Local.xcconfig).
/// * **Demo**: no configuration, or the `-demo` launch argument. Synthetic data in memory,
///   no network, no Apple ID. `-demoAdmin` signs in as the administrator.
@MainActor
@Observable
final class AppEnvironment {
    enum Mode: Equatable {
        case supabase
        case demo(admin: Bool)
    }

    let mode: Mode
    /// Set when a Supabase configuration exists but is unusable, e.g. a secret key was pasted.
    let configurationProblem: SupabaseConfiguration.Problem?
    let session: SessionController

    private(set) var student: StudentStore?
    private(set) var admin: AdminStore?
    private(set) var attachments: AttachmentRepository?

    @ObservationIgnored private let makeStudentBackend: (UUID) -> any StudentBackend
    @ObservationIgnored private let makeAdminBackend: (UUID) -> any AdminBackend
    @ObservationIgnored private let snapshots: SnapshotStore
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var wasOffline = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        let isUITest = arguments.contains("-uiTesting")
        let forceDemo = arguments.contains("-demo") || arguments.contains("-demoAdmin")
        snapshots = SnapshotStore(directory: SnapshotStore.defaultDirectory())

        let configuration = SupabaseConfiguration.fromInfoDictionary(info)
        let checker: (any AppleCredentialChecker)?
        let auth: any AuthService

        switch (forceDemo, configuration) {
        case (false, .success(let config)):
            mode = .supabase
            configurationProblem = nil
            let client = SupabaseClient.make(config)
            let backend = SupabaseStudyBackend(client: client)
            auth = SupabaseAuthService(client: client)
            checker = SystemAppleCredentialChecker()
            makeStudentBackend = { _ in backend }
            makeAdminBackend = { _ in backend }
        case (_, let result):
            let asAdmin = arguments.contains("-demoAdmin")
            mode = .demo(admin: asAdmin)
            if case .failure(let problem) = result, problem != .missing { configurationProblem = problem } else { configurationProblem = nil }
            let (catalog, files) = DemoContent.makeCatalog(now: Date())
            let server = InMemoryServer(catalog: catalog, files: files)
            let userID = asAdmin ? DemoContent.adminID : DemoContent.studentID
            auth = DemoAuthService(server: server, userID: userID, isAdmin: asAdmin, startSignedIn: isUITest)
            checker = nil
            makeStudentBackend = { InMemoryConnection(server: server, userID: $0) }
            makeAdminBackend = { InMemoryConnection(server: server, userID: $0) }
        }

        let snapshots = snapshots
        session = SessionController(
            auth: auth,
            credentialChecker: checker,
            appleUserIDStore: mode == .supabase ? KeychainAppleUserIDStore() : InMemoryAppleIDStore(),
            clearLocalData: { userID in
                await snapshots.delete(userID: userID)
                await AttachmentCache(directory: AttachmentCache.defaultDirectory(for: userID)).removeAll()
            }
        )

        if isUITest {
            // Every UI test starts from a clean device.
            Task { await snapshots.deleteAll() }
        }
    }

    var isDemo: Bool { if case .demo = mode { true } else { false } }

    /// Called whenever the session changes: builds or tears down the per-user stores.
    func sessionChanged() async {
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
    func refreshAdminAccess() {
        guard let student, let userID = session.currentUserID else { return }
        if student.identity?.isAdmin == true {
            if admin == nil { admin = AdminStore(backend: makeAdminBackend(userID)) }
        } else {
            admin = nil
        }
    }

    /// Syncs as soon as the network comes back.
    func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                if online, self.wasOffline { await self.student?.sync() }
                self.wasOffline = !online
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "woodland-study.network"))
    }
}

/// Demo mode doesn't touch the Keychain.
final class InMemoryAppleIDStore: AppleUserIDStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func load() -> String? { lock.withLock { value } }
    func save(_ id: String?) { lock.withLock { value = id } }
}
