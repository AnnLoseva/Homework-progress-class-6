import Foundation

// Editable forms for the administrator's content screens. Validation mirrors the table
// CHECK constraints so problems show up as form messages instead of server errors.

public enum ContentIssue: Equatable, Sendable, Hashable {
    case titleMissing
    case titleTooLong(maximum: Int)
    case descriptionTooLong(maximum: Int)
    case courseMissing
    case weekOutOfRange
    case exerciseCountOutOfRange
    case estimatedMinutesOutOfRange
    case dueBeforeAvailable
    case lessonIsOwnPrerequisite
    case slugInvalid
}

public struct LessonDraft: Equatable, Sendable {
    public var id: UUID?
    public var courseID: UUID?
    public var title: String
    public var description: String
    public var category: LessonCategory
    public var week: Int?
    public var moduleTitle: String
    public var sortOrder: Int
    public var availableFrom: Date?
    public var dueAt: Date?
    public var estimatedMinutes: Int?
    public var exerciseCount: Int
    public var prerequisiteIDs: [UUID]

    public init(id: UUID? = nil, courseID: UUID? = nil, title: String = "", description: String = "",
                category: LessonCategory = .required, week: Int? = nil, moduleTitle: String = "",
                sortOrder: Int = 0, availableFrom: Date? = nil, dueAt: Date? = nil,
                estimatedMinutes: Int? = nil, exerciseCount: Int = 0, prerequisiteIDs: [UUID] = []) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.description = description
        self.category = category
        self.week = week
        self.moduleTitle = moduleTitle
        self.sortOrder = sortOrder
        self.availableFrom = availableFrom
        self.dueAt = dueAt
        self.estimatedMinutes = estimatedMinutes
        self.exerciseCount = exerciseCount
        self.prerequisiteIDs = prerequisiteIDs
    }

    public init(lesson: Lesson) {
        self.init(id: lesson.id, courseID: lesson.courseID, title: lesson.title, description: lesson.description,
                  category: lesson.category, week: lesson.week, moduleTitle: lesson.moduleTitle ?? "",
                  sortOrder: lesson.sortOrder, availableFrom: lesson.availableFrom, dueAt: lesson.dueAt,
                  estimatedMinutes: lesson.estimatedMinutes, exerciseCount: lesson.exerciseCount,
                  prerequisiteIDs: lesson.prerequisiteIDs)
    }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedModuleTitle: String? {
        let value = moduleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value.prefix(120))
    }

    public var issues: [ContentIssue] {
        var issues: [ContentIssue] = []
        if trimmedTitle.isEmpty { issues.append(.titleMissing) }
        if trimmedTitle.count > 200 { issues.append(.titleTooLong(maximum: 200)) }
        if description.count > 20_000 { issues.append(.descriptionTooLong(maximum: 20_000)) }
        if courseID == nil { issues.append(.courseMissing) }
        if let week, !(0...60).contains(week) { issues.append(.weekOutOfRange) }
        if !(0...500).contains(exerciseCount) { issues.append(.exerciseCountOutOfRange) }
        if let estimatedMinutes, !(1...10_000).contains(estimatedMinutes) { issues.append(.estimatedMinutesOutOfRange) }
        if let dueAt, let availableFrom, dueAt < availableFrom { issues.append(.dueBeforeAvailable) }
        if let id, prerequisiteIDs.contains(id) { issues.append(.lessonIsOwnPrerequisite) }
        return issues
    }

    public var isValid: Bool { issues.isEmpty }
}

public struct CourseDraft: Equatable, Sendable {
    public var id: UUID?
    public var slug: String
    public var title: String
    public var subtitle: String
    public var iconName: String
    public var colorKey: String
    public var sortOrder: Int
    public var isArchived: Bool

    public static let colorKeys = ["dusk", "moss", "rust", "forest", "berry", "lake", "honey", "bark", "lavender"]

    public init(id: UUID? = nil, slug: String = "", title: String = "", subtitle: String = "",
                iconName: String = "CourseStudy", colorKey: String = "forest", sortOrder: Int = 0,
                isArchived: Bool = false) {
        self.id = id
        self.slug = slug
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.colorKey = colorKey
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }

    public init(course: Course) {
        self.init(id: course.id, slug: course.slug, title: course.title, subtitle: course.subtitle ?? "",
                  iconName: course.iconName, colorKey: course.colorKey, sortOrder: course.sortOrder,
                  isArchived: course.isArchived)
    }

    /// Lowercase ASCII slug derived from a title, e.g. "Linear Algebra 2" → "linear-algebra-2".
    public static func suggestedSlug(for title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var slug = ""
        for scalar in folded.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, slug.last != "-" {
                slug.append("-")
            }
        }
        slug = String(slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(63))
        return slug.count >= 2 ? slug : "course-\(UUID().uuidString.prefix(8).lowercased())"
    }

    public var issues: [ContentIssue] {
        var issues: [ContentIssue] = []
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { issues.append(.titleMissing) }
        if trimmed.count > 120 { issues.append(.titleTooLong(maximum: 120)) }
        if slug.range(of: "^[a-z0-9][a-z0-9-]{1,62}$", options: .regularExpression) == nil { issues.append(.slugInvalid) }
        return issues
    }
}
