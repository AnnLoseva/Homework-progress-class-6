import Foundation
import Observation
import StudyDomain

/// Content management for administrators. Every call is authorized again by the server
/// (RLS + triggers); this class only organizes the screens' state.
///
/// Administrators never get a view of students' progress or notes; there is no API for it.
@MainActor
@Observable
public final class AdminStore {
    public private(set) var catalog: Catalog = .empty
    public private(set) var isLoading = false
    public private(set) var classCodeUpdatedAt: Date?
    public var errorMessage: String?

    @ObservationIgnored private let backend: any AdminBackend

    public init(backend: any AdminBackend) {
        self.backend = backend
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await backend.fetchAdminCatalog()
            classCodeUpdatedAt = try await backend.classJoinCodeUpdatedAt()
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func lessons(matching query: LessonQuery, now: Date = Date()) -> [Lesson] {
        query.apply(to: catalog, subscriptions: [:], now: now)
    }

    @discardableResult
    public func save(_ draft: LessonDraft) async throws -> Lesson {
        guard draft.isValid else { throw BackendError.rejected(String(localized: "Please fix the highlighted fields.")) }
        let lesson = try await perform { try await self.backend.saveLesson(draft) }
        upsert(lesson)
        return lesson
    }

    public func setStatus(_ status: LessonStatus, lessonID: UUID) async throws {
        let lesson = try await perform { try await self.backend.setLessonStatus(lessonID, status: status) }
        upsert(lesson)
    }

    public func deleteLesson(_ lessonID: UUID) async throws {
        try await perform { try await self.backend.deleteLesson(lessonID) }
        catalog.lessons.removeAll { $0.id == lessonID }
        catalog.attachments.removeAll { $0.lessonID == lessonID }
    }

    @discardableResult
    public func save(_ draft: CourseDraft) async throws -> Course {
        guard draft.issues.isEmpty else { throw BackendError.rejected(String(localized: "Please fix the highlighted fields.")) }
        let course = try await perform { try await self.backend.saveCourse(draft) }
        catalog.courses.removeAll { $0.id == course.id }
        catalog.courses.append(course)
        catalog.courses.sort { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
        return course
    }

    /// Uploads a new attachment or replaces an existing one. Validation (PDF header, size)
    /// runs before any bytes are sent.
    @discardableResult
    public func upload(_ upload: AttachmentUpload) async throws -> LessonAttachment {
        try upload.validate()
        let attachment = try await perform { try await self.backend.uploadAttachment(upload) }
        catalog.attachments.removeAll { $0.id == attachment.id }
        catalog.attachments.append(attachment)
        return attachment
    }

    public func updateDetails(_ attachment: LessonAttachment) async throws {
        let updated = try await perform { try await self.backend.updateAttachmentDetails(attachment) }
        catalog.attachments.removeAll { $0.id == updated.id }
        catalog.attachments.append(updated)
    }

    public func deleteAttachment(_ attachment: LessonAttachment) async throws {
        try await perform { try await self.backend.deleteAttachment(attachment) }
        catalog.attachments.removeAll { $0.id == attachment.id }
    }

    public func previewData(for attachment: LessonAttachment) async throws -> Data {
        try await perform { try await self.backend.downloadAttachment(attachment) }
    }

    public func setClassJoinCode(_ code: String) async throws {
        try await perform { try await self.backend.setClassJoinCode(code) }
        classCodeUpdatedAt = try? await backend.classJoinCodeUpdatedAt()
    }

    private func upsert(_ lesson: Lesson) {
        if let index = catalog.lessons.firstIndex(where: { $0.id == lesson.id }) {
            catalog.lessons[index] = lesson
        } else {
            catalog.lessons.append(lesson)
        }
    }

    private func perform<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        do {
            let value = try await operation()
            errorMessage = nil
            return value
        } catch {
            errorMessage = Self.message(for: error)
            throw error
        }
    }

    public static func message(for error: Error) -> String {
        switch error {
        case let error as BackendError:
            switch error {
            case .offline: String(localized: "You're offline. Content changes need a connection.")
            case .unauthorized: String(localized: "Your session expired. Please sign in again.")
            case .forbidden: String(localized: "Your account doesn't have administrator rights for this.")
            case .rejected(let message), .server(let message): message
            case .notFound: String(localized: "That item no longer exists.")
            }
        case let error as AttachmentValidationError:
            switch error {
            case .empty: String(localized: "The file is empty.")
            case .tooLarge: String(localized: "The file is larger than 50 MB.")
            case .notAPDF: String(localized: "Only PDF files can be uploaded.")
            case .invalidFileName: String(localized: "The file name isn't valid.")
            }
        default:
            error.localizedDescription
        }
    }
}
