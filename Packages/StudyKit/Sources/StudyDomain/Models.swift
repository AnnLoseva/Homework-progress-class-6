import Foundation

// Plain value types mirroring the database rows. They carry no persistence or networking
// code, so every rule in StudyDomain can be tested in isolation.

/// The lesson's academic classification. Not a subscription or a completion state.
public enum LessonCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case required
    case optional
}

public enum LessonStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case draft
    case published
    case archived
}

public enum AttachmentVisibility: String, Codable, Sendable, CaseIterable, Hashable {
    /// Readable by anyone once the lesson is published.
    case `public`
    /// Readable by students who joined the class (and administrators).
    case restricted
}

public enum ProgressStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed
}

public struct Course: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var slug: String
    public var title: String
    public var subtitle: String?
    public var iconName: String
    public var colorKey: String
    public var sortOrder: Int
    public var isArchived: Bool

    public init(id: UUID = UUID(), slug: String, title: String, subtitle: String? = nil,
                iconName: String = "CourseStudy", colorKey: String = "forest",
                sortOrder: Int = 0, isArchived: Bool = false) {
        self.id = id
        self.slug = slug
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.colorKey = colorKey
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }
}

public struct Lesson: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var courseID: UUID
    public var title: String
    public var description: String
    public var category: LessonCategory
    public var status: LessonStatus
    public var week: Int?
    public var moduleTitle: String?
    public var sortOrder: Int
    public var availableFrom: Date?
    public var dueAt: Date?
    public var estimatedMinutes: Int?
    /// 0 means the lesson has no numbered exercises and is completed manually.
    public var exerciseCount: Int
    public var publishedAt: Date?
    public var archivedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var prerequisiteIDs: [UUID]
    /// The class week's first and last day ("2026-10-18"), from the homework week the lesson
    /// was published from, so every student's copy lands in the same calendar week. Nil for
    /// lessons published before the dates existed.
    public var weekStartsOn: String?
    public var weekEndsOn: String?

    public init(id: UUID = UUID(), courseID: UUID, title: String, description: String = "",
                category: LessonCategory, status: LessonStatus = .draft, week: Int? = nil,
                moduleTitle: String? = nil, sortOrder: Int = 0, availableFrom: Date? = nil,
                dueAt: Date? = nil, estimatedMinutes: Int? = nil, exerciseCount: Int = 0,
                publishedAt: Date? = nil, archivedAt: Date? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date(), prerequisiteIDs: [UUID] = [],
                weekStartsOn: String? = nil, weekEndsOn: String? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.description = description
        self.category = category
        self.status = status
        self.week = week
        self.moduleTitle = moduleTitle
        self.sortOrder = sortOrder
        self.availableFrom = availableFrom
        self.dueAt = dueAt
        self.estimatedMinutes = estimatedMinutes
        self.exerciseCount = exerciseCount
        self.publishedAt = publishedAt
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.prerequisiteIDs = prerequisiteIDs
        self.weekStartsOn = weekStartsOn
        self.weekEndsOn = weekEndsOn
    }

    public var hasExercises: Bool { exerciseCount > 0 }

    /// Same rule as `private.lesson_is_visible` in the database.
    public func isVisibleToStudents(at now: Date) -> Bool {
        (status == .published || status == .archived) && (availableFrom.map { $0 <= now } ?? true)
    }

    /// Published, available and not archived: something a student can actively work on.
    public func isActive(at now: Date) -> Bool {
        status == .published && isVisibleToStudents(at: now)
    }
}

public struct LessonAttachment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var lessonID: UUID
    public var title: String
    public var description: String
    public var visibility: AttachmentVisibility
    public var storagePath: String
    public var fileName: String
    public var mimeType: String
    public var byteSize: Int64
    public var version: Int
    public var sortOrder: Int
    public var updatedAt: Date

    public init(id: UUID = UUID(), lessonID: UUID, title: String, description: String = "",
                visibility: AttachmentVisibility = .restricted, storagePath: String? = nil,
                fileName: String, mimeType: String = "application/pdf", byteSize: Int64,
                version: Int = 1, sortOrder: Int = 0, updatedAt: Date = Date()) {
        self.id = id
        self.lessonID = lessonID
        self.title = title
        self.description = description
        self.visibility = visibility
        self.storagePath = storagePath
            ?? StoragePath.lessonMaterial(lessonID: lessonID, attachmentID: id, version: version)
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.version = version
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }

    /// Changes whenever the file is replaced, so caches never serve an old version.
    public var cacheKey: String { "\(id.uuidString.lowercased())-v\(version)" }
}

/// A student's choice to follow an optional lesson. Inactive rows are kept for history.
public struct LessonSubscription: Hashable, Codable, Sendable {
    public var lessonID: UUID
    public var isActive: Bool
    public var subscribedAt: Date
    public var unsubscribedAt: Date?

    public init(lessonID: UUID, isActive: Bool, subscribedAt: Date = Date(), unsubscribedAt: Date? = nil) {
        self.lessonID = lessonID
        self.isActive = isActive
        self.subscribedAt = subscribedAt
        self.unsubscribedAt = unsubscribedAt
    }
}

public struct LessonProgress: Hashable, Codable, Sendable {
    public var lessonID: UUID
    public var status: ProgressStatus
    public var completedExercises: Int
    public var notes: String
    public var lastActivityAt: Date
    public var completedAt: Date?
    /// When the change happened on the device; the server keeps the newest one.
    public var clientModifiedAt: Date

    public init(lessonID: UUID, status: ProgressStatus = .notStarted, completedExercises: Int = 0,
                notes: String = "", lastActivityAt: Date = Date(), completedAt: Date? = nil,
                clientModifiedAt: Date = Date()) {
        self.lessonID = lessonID
        self.status = status
        self.completedExercises = completedExercises
        self.notes = notes
        self.lastActivityAt = lastActivityAt
        self.completedAt = completedAt
        self.clientModifiedAt = clientModifiedAt
    }

    public static func empty(for lessonID: UUID, at date: Date = Date()) -> LessonProgress {
        LessonProgress(lessonID: lessonID, lastActivityAt: date, clientModifiedAt: date)
    }
}

/// Everything shared with the whole class.
public struct Catalog: Hashable, Codable, Sendable {
    public var courses: [Course]
    public var lessons: [Lesson]
    public var attachments: [LessonAttachment]

    public init(courses: [Course] = [], lessons: [Lesson] = [], attachments: [LessonAttachment] = []) {
        self.courses = courses
        self.lessons = lessons
        self.attachments = attachments
    }

    public static let empty = Catalog()

    public func course(_ id: UUID) -> Course? { courses.first { $0.id == id } }
    public func lesson(_ id: UUID) -> Lesson? { lessons.first { $0.id == id } }
    public func attachments(for lessonID: UUID) -> [LessonAttachment] {
        attachments.filter { $0.lessonID == lessonID }.sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
    }
}

/// Who the signed-in user is, as reported by the server (never decided by the app).
public struct UserIdentity: Hashable, Codable, Sendable {
    public var userID: UUID
    public var isAdmin: Bool
    public var isEnrolled: Bool
    public var displayName: String?

    public init(userID: UUID, isAdmin: Bool = false, isEnrolled: Bool = false, displayName: String? = nil) {
        self.userID = userID
        self.isAdmin = isAdmin
        self.isEnrolled = isEnrolled
        self.displayName = displayName
    }
}

public enum StoragePath {
    public static let lessonMaterialsBucket = "lesson-materials"
    public static let studentPrivateBucket = "student-private"

    /// `<lesson_id>/<attachment_id>/v<version>.pdf`, the only layout the storage policies accept.
    public static func lessonMaterial(lessonID: UUID, attachmentID: UUID, version: Int) -> String {
        "\(lessonID.uuidString.lowercased())/\(attachmentID.uuidString.lowercased())/v\(version).pdf"
    }
}

/// A calendar day as the database stores a `date`: "2026-10-18", read in the user's own calendar.
public enum CalendarDay {
    public static func string(from date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The start of that day, or nil for anything that isn't a valid "yyyy-MM-dd".
    public static func date(from string: String, calendar: Calendar) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components).map(calendar.startOfDay(for:))
    }
}
