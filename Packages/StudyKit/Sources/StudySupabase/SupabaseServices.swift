import Foundation
import StudyData
import StudyDomain
import Supabase

public extension SupabaseClient {
    /// One shared client per configuration. Sessions are stored in the Keychain by the SDK
    /// and refreshed automatically.
    static func make(_ configuration: SupabaseConfiguration) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }
}

// MARK: - Auth

public struct SupabaseAuthService: AuthService {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func restoreSession() async -> AuthSession? {
        do {
            let session = try await client.auth.session      // refreshes if expired
            return AuthSession(userID: session.user.id, expiresAt: Date(timeIntervalSince1970: session.expiresAt))
        } catch {
            // Offline at launch: keep the stored session so cached data stays usable. The SDK
            // refreshes it once the network is back; a truly invalid session then fails with 401.
            if ErrorMapping.map(error) == .offline, let stored = client.auth.currentSession {
                return AuthSession(userID: stored.user.id, expiresAt: Date(timeIntervalSince1970: stored.expiresAt))
            }
            return nil
        }
    }

    public func signInWithApple(_ credential: AppleIDCredential) async throws -> AuthSession {
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: credential.identityToken,
                                                      nonce: credential.rawNonce)
            )
            return AuthSession(userID: session.user.id, expiresAt: Date(timeIntervalSince1970: session.expiresAt))
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    public func signOut() async {
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            // The local session is cleared even if the server can't be reached.
        }
    }

    public func deleteAccount(appleAuthorizationCode: String?) async throws {
        struct Body: Encodable {
            var appleAuthorizationCode: String?
            enum CodingKeys: String, CodingKey { case appleAuthorizationCode = "apple_authorization_code" }
        }
        do {
            _ = try await client.auth.session   // make sure the token sent is fresh
            try await client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(method: .post, body: Body(appleAuthorizationCode: appleAuthorizationCode))
            )
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}

// MARK: - Data

/// Talks to Postgres through PostgREST and to Storage. Every request carries the user's JWT;
/// what it may read or change is decided by RLS on the server, not here.
public struct SupabaseStudyBackend: StudentBackend, AdminBackend {
    private let client: SupabaseClient
    /// Signed download URLs live this long (seconds).
    static let signedURLLifetime = 300

    public init(client: SupabaseClient) {
        self.client = client
    }

    @discardableResult
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try SupabaseCoding.decoder.decode(type, from: data)
    }

    private func currentUserID() async throws -> UUID {
        try await client.auth.session.user.id
    }

    // MARK: Student

    public func fetchIdentity() async throws -> StudyDomain.UserIdentity {
        try await run {
            let userID = try await currentUserID()
            async let adminRows = client.from("administrator_roles").select("user_id").eq("user_id", value: userID).execute()
            async let enrollmentRows = client.from("class_enrollments").select("user_id").eq("user_id", value: userID).execute()
            async let profileRows = client.from("profiles").select("display_name").eq("id", value: userID).execute()
            let admin = try decode([UserIDRow].self, try await adminRows.data)
            let enrolled = try decode([UserIDRow].self, try await enrollmentRows.data)
            let profile = try decode([ProfileRow].self, try await profileRows.data)
            return StudyDomain.UserIdentity(userID: userID, isAdmin: !admin.isEmpty, isEnrolled: !enrolled.isEmpty || !admin.isEmpty,
                                displayName: profile.first?.displayName)
        }
    }

    public func fetchCatalog() async throws -> Catalog {
        try await run { try await loadCatalog() }
    }

    /// RLS decides which lessons come back: students get published/archived ones,
    /// administrators also get drafts.
    private func loadCatalog() async throws -> Catalog {
        async let courseRows = client.from("courses").select().order("sort_order").execute()
        async let lessonRows = client.from("lessons").select().order("sort_order").execute()
        async let prerequisiteRows = client.from("lesson_prerequisites").select().execute()
        async let attachmentRows = client.from("lesson_attachments").select().order("sort_order").execute()

        let courses = try decode([CourseRow].self, try await courseRows.data).map(\.domain)
        let prerequisites = try decode([PrerequisiteRow].self, try await prerequisiteRows.data)
        let byLesson = Dictionary(grouping: prerequisites, by: \.lessonId).mapValues { $0.map(\.prerequisiteId) }
        let lessons = try decode([LessonRow].self, try await lessonRows.data).map { $0.domain(prerequisites: byLesson[$0.id] ?? []) }
        let attachments = try decode([AttachmentRow].self, try await attachmentRows.data).map(\.domain)
        return Catalog(courses: courses, lessons: lessons, attachments: attachments)
    }

    public func fetchSubscriptions() async throws -> [LessonSubscription] {
        try await run {
            let data = try await client.from("lesson_subscriptions")
                .select("lesson_id, is_active, subscribed_at, unsubscribed_at").execute().data
            return try decode([SubscriptionRow].self, data).map(\.domain)
        }
    }

    public func fetchProgress() async throws -> [LessonProgress] {
        try await run {
            let data = try await client.from("lesson_progress")
                .select("lesson_id, status, completed_exercises, notes, last_activity_at, completed_at, client_modified_at")
                .execute().data
            return try decode([ProgressRow].self, data).map(\.domain)
        }
    }

    public func setSubscription(lessonID: UUID, active: Bool) async throws -> LessonSubscription {
        try await run {
            let data = try await client.rpc("set_lesson_subscription",
                                            params: SetSubscriptionParams(pLessonId: lessonID, pActive: active)).execute().data
            return try decode(SubscriptionRow.self, data).domain
        }
    }

    public func saveProgress(_ progress: LessonProgress) async throws -> LessonProgress {
        try await run {
            let data = try await client.rpc("set_lesson_progress", params: SetProgressParams(progress)).execute().data
            return try decode(ProgressRow.self, data).domain
        }
    }

    public func joinClass(code: String) async throws -> JoinClassResult {
        try await run {
            let data = try await client.rpc("join_class", params: CodeParams(pCode: code)).execute().data
            let raw = try decode(String.self, data)
            guard let result = JoinClassResult(rawValue: raw) else { throw BackendError.server("Unexpected response \(raw)") }
            return result
        }
    }

    public func exportMyData() async throws -> Data {
        try await run {
            let data = try await client.rpc("export_my_data").execute().data
            let object = try JSONSerialization.jsonObject(with: data)
            return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        }
    }

    public func updateDisplayName(_ name: String?) async throws {
        try await run {
            let userID = try await currentUserID()
            try await client.from("profiles").update(ProfileWrite(displayName: name)).eq("id", value: userID).execute()
        }
    }

    /// Downloads through a short-lived signed URL. Storage only signs it if the caller passes
    /// the bucket's SELECT policy (published lesson, visibility, enrollment).
    public func downloadAttachment(_ attachment: LessonAttachment) async throws -> Data {
        try await run {
            let url = try await client.storage.from(StoragePath.lessonMaterialsBucket)
                .createSignedURL(path: attachment.storagePath, expiresIn: Self.signedURLLifetime)
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw ErrorMapping.map(httpStatus: http.statusCode, message: "Download failed (\(http.statusCode))")
            }
            return data
        }
    }

    // MARK: Admin

    public func fetchAdminCatalog() async throws -> Catalog {
        try await run { try await loadCatalog() }
    }

    public func saveCourse(_ draft: CourseDraft) async throws -> Course {
        try await run {
            let query = client.from("courses")
            let data: Data
            if let id = draft.id {
                data = try await query.update(CourseWrite(draft)).eq("id", value: id).select().single().execute().data
            } else {
                data = try await query.insert(CourseWrite(draft), returning: .representation).select().single().execute().data
            }
            return try decode(CourseRow.self, data).domain
        }
    }

    public func saveLesson(_ draft: LessonDraft) async throws -> Lesson {
        try await run {
            let data: Data
            if draft.id != nil {
                // Upsert by id: the editor updates an existing lesson, and "Publish to class"
                // creates lessons with ids derived from the homework, so re-publishing never
                // duplicates. `status` isn't part of the write, so an update keeps it.
                data = try await client.from("lessons").upsert(LessonWrite(draft: draft), onConflict: "id", returning: .representation)
                    .select().single().execute().data
            } else {
                data = try await client.from("lessons").insert(LessonWrite(draft: draft), returning: .representation)
                    .select().single().execute().data
            }
            let row = try decode(LessonRow.self, data)

            // Replace the prerequisite set.
            try await client.from("lesson_prerequisites").delete().eq("lesson_id", value: row.id).execute()
            let prerequisites = draft.prerequisiteIDs.filter { $0 != row.id }
            if !prerequisites.isEmpty {
                try await client.from("lesson_prerequisites")
                    .insert(prerequisites.map { PrerequisiteRow(lessonId: row.id, prerequisiteId: $0) }).execute()
            }
            return row.domain(prerequisites: prerequisites)
        }
    }

    public func setLessonStatus(_ lessonID: UUID, status: LessonStatus) async throws -> Lesson {
        try await run {
            let data = try await client.from("lessons").update(StatusWrite(status: status)).eq("id", value: lessonID)
                .select().single().execute().data
            let prereqData = try await client.from("lesson_prerequisites").select().eq("lesson_id", value: lessonID).execute().data
            let prerequisites = try decode([PrerequisiteRow].self, prereqData).map(\.prerequisiteId)
            return try decode(LessonRow.self, data).domain(prerequisites: prerequisites)
        }
    }

    public func deleteLesson(_ lessonID: UUID) async throws {
        try await run {
            let attachmentData = try await client.from("lesson_attachments").select().eq("lesson_id", value: lessonID).execute().data
            let paths = try decode([AttachmentRow].self, attachmentData).map(\.storagePath)
            let deleted = try await client.from("lessons").delete(returning: .representation).eq("id", value: lessonID).execute().data
            guard try !(JSONSerialization.jsonObject(with: deleted) as? [Any] ?? []).isEmpty else { throw BackendError.notFound }
            if !paths.isEmpty {
                _ = try? await client.storage.from(StoragePath.lessonMaterialsBucket).remove(paths: paths)
            }
        }
    }

    /// Upload first, then point the attachment row at the new file, then delete the old file.
    /// A failed row write removes the just-uploaded object, so nothing is left half-done.
    public func uploadAttachment(_ upload: AttachmentUpload) async throws -> LessonAttachment {
        try upload.validate()
        return try await run {
            let bucket = client.storage.from(StoragePath.lessonMaterialsBucket)
            try await bucket.upload(upload.storagePath, data: upload.data,
                                    options: FileOptions(cacheControl: "3600", contentType: AttachmentValidator.pdfMIMEType, upsert: false))
            let row = AttachmentWrite(
                id: upload.attachmentID, lessonId: upload.lessonID, title: upload.title, description: upload.description,
                visibility: upload.visibility, storagePath: upload.storagePath,
                fileName: try AttachmentValidator.sanitizedFileName(upload.fileName),
                mimeType: AttachmentValidator.pdfMIMEType, byteSize: Int64(upload.data.count),
                version: upload.version, sortOrder: upload.sortOrder)
            do {
                let data: Data
                if let previous = upload.replacingVersion {
                    data = try await client.from("lesson_attachments").update(row)
                        .eq("id", value: upload.attachmentID).eq("version", value: previous)
                        .select().single().execute().data
                    let oldPath = StoragePath.lessonMaterial(lessonID: upload.lessonID, attachmentID: upload.attachmentID, version: previous)
                    _ = try? await bucket.remove(paths: [oldPath])
                } else {
                    data = try await client.from("lesson_attachments").insert(row, returning: .representation)
                        .select().single().execute().data
                }
                return try decode(AttachmentRow.self, data).domain
            } catch {
                _ = try? await bucket.remove(paths: [upload.storagePath])
                throw error
            }
        }
    }

    public func updateAttachmentDetails(_ attachment: LessonAttachment) async throws -> LessonAttachment {
        try await run {
            let data = try await client.from("lesson_attachments")
                .update(AttachmentDetailsWrite(title: attachment.title, description: attachment.description,
                                               visibility: attachment.visibility, sortOrder: attachment.sortOrder))
                .eq("id", value: attachment.id).select().single().execute().data
            return try decode(AttachmentRow.self, data).domain
        }
    }

    public func deleteAttachment(_ attachment: LessonAttachment) async throws {
        try await run {
            try await client.from("lesson_attachments").delete().eq("id", value: attachment.id).execute()
            _ = try? await client.storage.from(StoragePath.lessonMaterialsBucket).remove(paths: [attachment.storagePath])
        }
    }

    public func setClassJoinCode(_ code: String) async throws {
        try await run {
            try await client.rpc("set_class_join_code", params: CodeParams(pCode: code)).execute()
        }
    }

    public func classJoinCodeUpdatedAt() async throws -> Date? {
        try await run {
            let data = try await client.rpc("class_join_code_updated_at").execute().data
            guard let raw = try decode(String?.self, data) else { return nil }
            return PostgresDate.parse(raw)
        }
    }
}
