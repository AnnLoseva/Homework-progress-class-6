import Foundation
import StudyDomain

// JSON shapes of the database rows (snake_case, Postgres timestamps) and their mapping to
// domain types. Kept separate from the domain so the database can evolve independently.

enum PostgresDate {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    // Formatters are not thread-safe; every use goes through this lock.
    private static let lock = NSLock()

    /// Accepts `2026-10-22T12:00:00Z`, `…:00.123456+00:00`, and Postgres' `… 12:00:00+00`.
    static func parse(_ raw: String) -> Date? {
        var string = raw.replacingOccurrences(of: " ", with: "T")
        // "+00" → "+00:00"
        if let match = string.range(of: #"[+-]\d\d$"#, options: .regularExpression) {
            string.replaceSubrange(match, with: string[match] + ":00")
        }
        // Keep at most 3 fractional digits; ISO8601DateFormatter is unreliable beyond that.
        if let match = string.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = string[match].dropFirst().prefix(3)
            string.replaceSubrange(match, with: "." + digits)
        }
        return lock.withLock { withFraction.date(from: string) ?? plain.date(from: string) }
    }

    static func format(_ date: Date) -> String {
        lock.withLock { withFraction.string(from: date) }
    }
}

enum SupabaseCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = PostgresDate.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized timestamp \(string)")
            }
            return date
        }
        return decoder
    }()
}

struct CourseRow: Codable, Equatable {
    var id: UUID
    var slug: String
    var title: String
    var subtitle: String?
    var iconName: String
    var colorKey: String
    var sortOrder: Int
    var isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case id, slug, title, subtitle
        case iconName = "icon_name"
        case colorKey = "color_key"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
    }

    var domain: Course {
        Course(id: id, slug: slug, title: title, subtitle: subtitle, iconName: iconName, colorKey: colorKey,
               sortOrder: sortOrder, isArchived: isArchived)
    }
}

/// Columns the administrator may write for a course. Every optional is sent explicitly
/// (as null) so clearing a field works.
struct CourseWrite: Encodable {
    var slug: String
    var title: String
    var subtitle: String?
    var iconName: String
    var colorKey: String
    var sortOrder: Int
    var isArchived: Bool

    init(_ draft: CourseDraft) {
        slug = draft.slug
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sub = draft.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitle = sub.isEmpty ? nil : sub
        iconName = draft.iconName
        colorKey = draft.colorKey
        sortOrder = draft.sortOrder
        isArchived = draft.isArchived
    }

    enum CodingKeys: String, CodingKey {
        case slug, title, subtitle
        case iconName = "icon_name"
        case colorKey = "color_key"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(slug, forKey: .slug)
        try c.encode(title, forKey: .title)
        try c.encode(subtitle, forKey: .subtitle)
        try c.encode(iconName, forKey: .iconName)
        try c.encode(colorKey, forKey: .colorKey)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(isArchived, forKey: .isArchived)
    }
}

struct LessonRow: Codable, Equatable {
    var id: UUID
    var courseId: UUID
    var title: String
    var description: String
    var category: LessonCategory
    var status: LessonStatus
    var week: Int?
    var moduleTitle: String?
    var sortOrder: Int
    var availableFrom: Date?
    var dueAt: Date?
    var estimatedMinutes: Int?
    var exerciseCount: Int
    var publishedAt: Date?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    /// `date` columns arrive as "2026-10-18" and are kept as that string.
    var weekStartsOn: String?
    var weekEndsOn: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, status, week
        case courseId = "course_id"
        case moduleTitle = "module_title"
        case sortOrder = "sort_order"
        case availableFrom = "available_from"
        case dueAt = "due_at"
        case estimatedMinutes = "estimated_minutes"
        case exerciseCount = "exercise_count"
        case publishedAt = "published_at"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case weekStartsOn = "week_starts_on"
        case weekEndsOn = "week_ends_on"
    }

    func domain(prerequisites: [UUID]) -> Lesson {
        Lesson(id: id, courseID: courseId, title: title, description: description, category: category,
               status: status, week: week, moduleTitle: moduleTitle, sortOrder: sortOrder,
               availableFrom: availableFrom, dueAt: dueAt, estimatedMinutes: estimatedMinutes,
               exerciseCount: exerciseCount, publishedAt: publishedAt, archivedAt: archivedAt,
               createdAt: createdAt, updatedAt: updatedAt, prerequisiteIDs: prerequisites,
               weekStartsOn: weekStartsOn, weekEndsOn: weekEndsOn)
    }
}

/// Lesson columns the administrator may write. Status, author and lifecycle timestamps are
/// not here: the server sets them (`private.lessons_before_write`).
struct LessonWrite: Encodable {
    var draft: LessonDraft

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, week
        case courseId = "course_id"
        case moduleTitle = "module_title"
        case sortOrder = "sort_order"
        case availableFrom = "available_from"
        case dueAt = "due_at"
        case estimatedMinutes = "estimated_minutes"
        case exerciseCount = "exercise_count"
        case weekStartsOn = "week_starts_on"
        case weekEndsOn = "week_ends_on"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let id = draft.id { try c.encode(id, forKey: .id) }
        try c.encode(draft.courseID, forKey: .courseId)
        try c.encode(draft.trimmedTitle, forKey: .title)
        try c.encode(draft.description, forKey: .description)
        try c.encode(draft.category.rawValue, forKey: .category)
        try c.encode(draft.week, forKey: .week)
        try c.encode(draft.trimmedModuleTitle, forKey: .moduleTitle)
        try c.encode(draft.sortOrder, forKey: .sortOrder)
        try c.encode(draft.availableFrom.map(PostgresDate.format), forKey: .availableFrom)
        try c.encode(draft.dueAt.map(PostgresDate.format), forKey: .dueAt)
        try c.encode(draft.estimatedMinutes, forKey: .estimatedMinutes)
        try c.encode(draft.exerciseCount, forKey: .exerciseCount)
        try c.encode(draft.weekStartsOn, forKey: .weekStartsOn)
        try c.encode(draft.weekEndsOn, forKey: .weekEndsOn)
    }
}

struct PrerequisiteRow: Codable, Equatable {
    var lessonId: UUID
    var prerequisiteId: UUID

    enum CodingKeys: String, CodingKey {
        case lessonId = "lesson_id"
        case prerequisiteId = "prerequisite_id"
    }
}

struct AttachmentRow: Codable, Equatable {
    var id: UUID
    var lessonId: UUID
    var title: String
    var description: String
    var visibility: AttachmentVisibility
    var storagePath: String
    var fileName: String
    var mimeType: String
    var byteSize: Int64
    var version: Int
    var sortOrder: Int
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, visibility, version
        case lessonId = "lesson_id"
        case storagePath = "storage_path"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
    }

    var domain: LessonAttachment {
        LessonAttachment(id: id, lessonID: lessonId, title: title, description: description, visibility: visibility,
                         storagePath: storagePath, fileName: fileName, mimeType: mimeType, byteSize: byteSize,
                         version: version, sortOrder: sortOrder, updatedAt: updatedAt)
    }
}

struct AttachmentWrite: Encodable {
    var id: UUID
    var lessonId: UUID
    var title: String
    var description: String
    var visibility: AttachmentVisibility
    var storagePath: String
    var fileName: String
    var mimeType: String
    var byteSize: Int64
    var version: Int
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description, visibility, version
        case lessonId = "lesson_id"
        case storagePath = "storage_path"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case sortOrder = "sort_order"
    }
}

struct AttachmentDetailsWrite: Encodable {
    var title: String
    var description: String
    var visibility: AttachmentVisibility
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case title, description, visibility
        case sortOrder = "sort_order"
    }
}

struct SubscriptionRow: Codable, Equatable {
    var lessonId: UUID
    var isActive: Bool
    var subscribedAt: Date
    var unsubscribedAt: Date?

    enum CodingKeys: String, CodingKey {
        case lessonId = "lesson_id"
        case isActive = "is_active"
        case subscribedAt = "subscribed_at"
        case unsubscribedAt = "unsubscribed_at"
    }

    var domain: LessonSubscription {
        LessonSubscription(lessonID: lessonId, isActive: isActive, subscribedAt: subscribedAt, unsubscribedAt: unsubscribedAt)
    }
}

struct ProgressRow: Codable, Equatable {
    var lessonId: UUID
    var status: ProgressStatus
    var completedExercises: Int
    var notes: String
    var lastActivityAt: Date
    var completedAt: Date?
    var clientModifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case status, notes
        case lessonId = "lesson_id"
        case completedExercises = "completed_exercises"
        case lastActivityAt = "last_activity_at"
        case completedAt = "completed_at"
        case clientModifiedAt = "client_modified_at"
    }

    var domain: LessonProgress {
        LessonProgress(lessonID: lessonId, status: status, completedExercises: completedExercises, notes: notes,
                       lastActivityAt: lastActivityAt, completedAt: completedAt, clientModifiedAt: clientModifiedAt)
    }
}

/// Parameters of `public.set_lesson_progress`. There is no user id: the server uses auth.uid().
struct SetProgressParams: Encodable, Equatable {
    var pLessonId: UUID
    var pStatus: String
    var pCompletedExercises: Int
    var pNotes: String
    var pClientModifiedAt: String

    init(_ progress: LessonProgress) {
        pLessonId = progress.lessonID
        pStatus = progress.status.rawValue
        pCompletedExercises = progress.completedExercises
        pNotes = progress.notes
        pClientModifiedAt = PostgresDate.format(progress.clientModifiedAt)
    }

    enum CodingKeys: String, CodingKey {
        case pLessonId = "p_lesson_id"
        case pStatus = "p_status"
        case pCompletedExercises = "p_completed_exercises"
        case pNotes = "p_notes"
        case pClientModifiedAt = "p_client_modified_at"
    }
}

struct SetSubscriptionParams: Encodable, Equatable {
    var pLessonId: UUID
    var pActive: Bool

    enum CodingKeys: String, CodingKey {
        case pLessonId = "p_lesson_id"
        case pActive = "p_active"
    }
}

struct CodeParams: Encodable {
    var pCode: String
    enum CodingKeys: String, CodingKey { case pCode = "p_code" }
}

struct ProfileRow: Codable {
    var displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

struct ProfileWrite: Encodable {
    var displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
    }
}

struct UserIDRow: Codable {
    var userId: UUID
    enum CodingKeys: String, CodingKey { case userId = "user_id" }
}

struct StatusWrite: Encodable {
    var status: LessonStatus
}
