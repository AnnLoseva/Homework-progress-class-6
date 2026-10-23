import Foundation
import Observation

/// Whether Apple still considers the user signed in to this app (they can revoke it in
/// Settings → Apple ID → Sign in with Apple). Implemented with AuthenticationServices.
public protocol AppleCredentialChecker: Sendable {
    func isRevoked(appleUserID: String) async -> Bool
}

/// Remembers Apple's user identifier (not the email) for the credential-state check.
public protocol AppleUserIDStore: Sendable {
    func load() -> String?
    func save(_ id: String?)
}

/// Owns the sign-in state machine:
/// restoring → signedIn | signedOut, with clear notices for expiry, revocation and errors.
@MainActor
@Observable
public final class SessionController {
    public enum State: Equatable, Sendable {
        case restoring
        case signedOut
        case signedIn(AuthSession)
    }

    public enum Notice: Equatable, Sendable {
        case sessionExpired
        case appleCredentialRevoked
        case accountDeleted
        case signedOut
        case signInFailed(String)
    }

    public private(set) var state: State = .restoring
    public private(set) var notice: Notice?
    public private(set) var isWorking = false

    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private let credentialChecker: (any AppleCredentialChecker)?
    @ObservationIgnored private let appleUserIDStore: any AppleUserIDStore
    /// Wipes this user's cached data and PDFs (privacy on shared devices).
    @ObservationIgnored private let clearLocalData: @MainActor (UUID) async -> Void

    public init(auth: any AuthService,
                credentialChecker: (any AppleCredentialChecker)?,
                appleUserIDStore: any AppleUserIDStore,
                clearLocalData: @escaping @MainActor (UUID) async -> Void) {
        self.auth = auth
        self.credentialChecker = credentialChecker
        self.appleUserIDStore = appleUserIDStore
        self.clearLocalData = clearLocalData
    }

    public var currentUserID: UUID? {
        if case .signedIn(let session) = state { session.userID } else { nil }
    }

    public func dismissNotice() { notice = nil }

    /// Called at launch: restores the Keychain session (refreshing it if needed) and checks
    /// that the Apple ID authorization hasn't been revoked.
    public func restore() async {
        state = .restoring
        guard let session = await auth.restoreSession() else {
            state = .signedOut
            return
        }
        if let appleID = appleUserIDStore.load(), let checker = credentialChecker,
           await checker.isRevoked(appleUserID: appleID) {
            await endSession(userID: session.userID, notice: .appleCredentialRevoked)
            return
        }
        state = .signedIn(session)
    }

    public func signIn(with credential: AppleIDCredential) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await auth.signInWithApple(credential)
            appleUserIDStore.save(credential.appleUserID)
            notice = nil
            state = .signedIn(session)
        } catch {
            notice = .signInFailed(Self.message(for: error))
            state = .signedOut
        }
    }

    /// Reports a failed Apple sheet (other than the user cancelling) as a sign-in error.
    public func reportSignInFailure(_ message: String) {
        notice = .signInFailed(message)
    }

    public func signOut() async {
        guard let userID = currentUserID else { return }
        isWorking = true
        defer { isWorking = false }
        await auth.signOut()
        await endSession(userID: userID, notice: .signedOut)
    }

    /// The server said the token is no longer valid. Try one refresh; otherwise sign out
    /// with an explanation. Cached data is kept so queued changes survive re-sign-in.
    public func handleUnauthorized() async {
        guard case .signedIn(let current) = state else { return }
        if let refreshed = await auth.restoreSession(), refreshed.userID == current.userID {
            state = .signedIn(refreshed)
            return
        }
        await auth.signOut()
        notice = .sessionExpired
        state = .signedOut
    }

    public func deleteAccount(appleAuthorizationCode: String?) async throws {
        guard let userID = currentUserID else { return }
        isWorking = true
        defer { isWorking = false }
        try await auth.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
        await auth.signOut()
        await endSession(userID: userID, notice: .accountDeleted)
    }

    private func endSession(userID: UUID, notice: Notice) async {
        appleUserIDStore.save(nil)
        await clearLocalData(userID)
        self.notice = notice
        state = .signedOut
    }

    static func message(for error: Error) -> String {
        if let backend = error as? BackendError {
            switch backend {
            case .offline: return String(localized: "You're offline. Connect to the internet to sign in.")
            case .unauthorized, .forbidden: return String(localized: "Apple sign-in was not accepted. Please try again.")
            case .rejected(let message), .server(let message): return message
            case .notFound: return String(localized: "The sign-in service is not available.")
            }
        }
        return error.localizedDescription
    }
}
