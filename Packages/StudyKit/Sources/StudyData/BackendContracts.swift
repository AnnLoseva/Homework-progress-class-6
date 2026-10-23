import Foundation
import StudyDomain

// The seams between the app and a backend. `StudySupabase` implements them against
// Supabase; `InMemoryServer` implements them for tests.
//
// Student and administrator operations are separate protocols on purpose: student screens
// never hold a reference that can publish lessons. The server enforces this anyway (RLS).

public enum BackendError: Error, Equatable, Sendable {
    /// No connection. The change stays queued and is retried.
    case offline
    /// The session is missing, expired or revoked. The user must sign in again.
    case unauthorized
    /// The server refused the operation for this user (RLS / missing role).
    case forbidden(String)
    /// The server rejected the data (validation or a business rule).
    case rejected(String)
    case notFound
    /// Temporary server-side failure; retried with backoff.
    case server(String)

    /// Worth retrying later without changing anything.
    public var isTransient: Bool {
        switch self {
        case .offline, .server: true
        default: false
        }
    }
}

public struct AuthSession: Equatable, Sendable {
    public var userID: UUID
    public var expiresAt: Date?

    public init(userID: UUID, expiresAt: Date? = nil) {
        self.userID = userID
        self.expiresAt = expiresAt
    }
}

/// What Sign in with Apple hands the app. The email is deliberately not part of it: it may be
/// a private relay address, is only sent on first sign-in, and is never used as an identity.
public struct AppleIDCredential: Sendable, Equatable {
    public var identityToken: String
    /// The unhashed nonce; Apple received its SHA-256 and Supabase verifies the match.
    public var rawNonce: String
    /// Apple's stable user identifier for this app, used only to check credential state.
    public var appleUserID: String
    public var authorizationCode: String?

    public init(identityToken: String, rawNonce: String, appleUserID: String, authorizationCode: String? = nil) {
        self.identityToken = identityToken
        self.rawNonce = rawNonce
        self.appleUserID = appleUserID
        self.authorizationCode = authorizationCode
    }
}

public protocol AuthService: Sendable {
    /// The stored session, refreshed if needed. `nil` when there is none or it can't be refreshed.
    func restoreSession() async -> AuthSession?
    func signInWithApple(_ credential: AppleIDCredential) async throws -> AuthSession
    func signOut() async
    /// Deletes the account and all personal data on the server.
    func deleteAccount(appleAuthorizationCode: String?) async throws
}

public enum JoinClassResult: String, Sendable, Equatable {
    case joined
    case alreadyJoined = "already_joined"
    case invalidCode = "invalid_code"
    case rateLimited = "rate_limited"
    case notConfigured = "not_configured"
}

public protocol StudentBackend: Sendable {
    func fetchIdentity() async throws -> UserIdentity
    func fetchCatalog() async throws -> Catalog
    func fetchSubscriptions() async throws -> [LessonSubscription]
    func fetchProgress() async throws -> [LessonProgress]
    /// Idempotent. Returns the stored row.
    func setSubscription(lessonID: UUID, active: Bool) async throws -> LessonSubscription
    /// Last-writer-wins by `clientModifiedAt`. Returns the row the server kept, which may be
    /// a newer one from another device.
    func saveProgress(_ progress: LessonProgress) async throws -> LessonProgress
    func joinClass(code: String) async throws -> JoinClassResult
    func exportMyData() async throws -> Data
    func updateDisplayName(_ name: String?) async throws
    func downloadAttachment(_ attachment: LessonAttachment) async throws -> Data
}

/// A new file for an attachment: a brand-new attachment, or a replacement of an existing one
/// (same attachment id, next version).
public struct AttachmentUpload: Sendable, Equatable {
    public var lessonID: UUID
    public var attachmentID: UUID
    /// The version being replaced, or nil for a new attachment.
    public var replacingVersion: Int?
    public var title: String
    public var description: String
    public var visibility: AttachmentVisibility
    public var fileName: String
    public var data: Data
    public var sortOrder: Int

    public init(lessonID: UUID, attachmentID: UUID = UUID(), replacingVersion: Int? = nil, title: String,
                description: String = "", visibility: AttachmentVisibility, fileName: String, data: Data,
                sortOrder: Int = 0) {
        self.lessonID = lessonID
        self.attachmentID = attachmentID
        self.replacingVersion = replacingVersion
        self.title = title
        self.description = description
        self.visibility = visibility
        self.fileName = fileName
        self.data = data
        self.sortOrder = sortOrder
    }

    public var version: Int { (replacingVersion ?? 0) + 1 }
    public var storagePath: String {
        StoragePath.lessonMaterial(lessonID: lessonID, attachmentID: attachmentID, version: version)
    }

    public func validate() throws {
        try AttachmentValidator.validate(fileName: fileName, byteSize: Int64(data.count), header: data.prefix(1024))
    }
}

public protocol AdminBackend: Sendable {
    /// Includes drafts; the server only returns them to administrators.
    func fetchAdminCatalog() async throws -> Catalog
    func saveCourse(_ draft: CourseDraft) async throws -> Course
    func saveLesson(_ draft: LessonDraft) async throws -> Lesson
    func setLessonStatus(_ lessonID: UUID, status: LessonStatus) async throws -> Lesson
    func deleteLesson(_ lessonID: UUID) async throws
    func uploadAttachment(_ upload: AttachmentUpload) async throws -> LessonAttachment
    func updateAttachmentDetails(_ attachment: LessonAttachment) async throws -> LessonAttachment
    func deleteAttachment(_ attachment: LessonAttachment) async throws
    func downloadAttachment(_ attachment: LessonAttachment) async throws -> Data
    func setClassJoinCode(_ code: String) async throws
    func classJoinCodeUpdatedAt() async throws -> Date?
}
