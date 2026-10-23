//
//  ClassPublisher.swift
//  Homework progress
//
//  Publishes homework to the Class tab as lessons, for the class administrator. Only the
//  shared parts are sent: course, title, week, due date, exercise total and the PDFs. Your
//  progress, completed counts, status and notes stay in your homework and are never uploaded.
//
//  Lessons and attachments reuse the homework's own ids, so publishing again updates the same
//  lessons instead of duplicating them, and a replaced PDF becomes a new version of the same
//  attachment (students keep their progress).
//

import Foundation
import StudyData
import StudyDomain

/// The parts of one assignment that can be shared, copied out of SwiftData so publishing can
/// run without holding model objects across suspension points.
struct ClassPublishItem: Identifiable, Equatable {
    struct CourseInfo: Equatable {
        var id: UUID
        var name: String
        var englishName: String
        var iconName: String
        var colorKey: String
        var sortOrder: Int
    }

    struct File: Equatable {
        var id: UUID
        var fileName: String
        var byteCount: Int64
        var sortIndex: Int
        var storedFilename: String
    }

    var id: UUID
    var title: String
    var course: CourseInfo
    var weekNumber: Int?
    var weekTitle: String
    /// The homework week's first and last day: students get the same calendar week.
    var weekStart: Date?
    var weekEnd: Date?
    var orderInWeek: Int
    var dueDate: Date?
    var totalExercises: Int?
    var files: [File]

    init(assignment: HomeworkAssignment, orderInWeek: Int) {
        id = assignment.id
        title = assignment.title
        let course = assignment.course
        self.course = CourseInfo(id: course?.id ?? UUID(), name: course?.name ?? "", englishName: course?.englishName ?? "",
                                 iconName: course?.iconName ?? "CourseStudy", colorKey: course?.colorKey ?? "",
                                 sortOrder: course?.sortOrder ?? 0)
        weekNumber = assignment.week?.number
        weekTitle = assignment.week?.title ?? ""
        weekStart = assignment.week?.startDate
        weekEnd = assignment.week?.endDate
        self.orderInWeek = orderInWeek
        dueDate = assignment.dueDate
        totalExercises = assignment.totalExercises
        files = assignment.attachmentList.sorted { $0.sortIndex < $1.sortIndex }.map {
            File(id: $0.id, fileName: $0.originalFilename, byteCount: $0.byteCount, sortIndex: $0.sortIndex,
                 storedFilename: $0.storedFilename)
        }
    }

    init(id: UUID, title: String, course: CourseInfo, weekNumber: Int?, weekTitle: String, orderInWeek: Int,
         dueDate: Date?, totalExercises: Int?, files: [File], weekStart: Date? = nil, weekEnd: Date? = nil) {
        self.id = id
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.title = title
        self.course = course
        self.weekNumber = weekNumber
        self.weekTitle = weekTitle
        self.orderInWeek = orderInWeek
        self.dueDate = dueDate
        self.totalExercises = totalExercises
        self.files = files
    }
}

struct ClassPublishOptions: Equatable {
    /// Only for lessons published for the first time; existing lessons keep theirs.
    var category: LessonCategory = .required
    /// Restricted = only students who joined the class with its code (and administrators).
    var fileVisibility: AttachmentVisibility = .restricted
}

struct ClassPublishReport: Equatable {
    var lessonsCreated = 0
    var lessonsUpdated = 0
    var filesUploaded = 0
    var filesReplaced = 0
    var filesUnchanged = 0
    var failures: [String] = []

    var succeeded: Bool { failures.isEmpty }
}

@MainActor
struct ClassPublisher {
    let admin: AdminStore
    /// Reads a PDF's bytes; `nil` if the file is missing on this device.
    let fileData: (ClassPublishItem.File) -> Data?

    func publish(_ items: [ClassPublishItem], options: ClassPublishOptions) async -> ClassPublishReport {
        var report = ClassPublishReport()
        await admin.load()
        if let error = admin.errorMessage {
            report.failures.append(error)
            return report
        }

        var remoteCourses: [UUID: UUID] = [:]
        for item in items {
            do {
                let courseID: UUID
                if let known = remoteCourses[item.course.id] {
                    courseID = known
                } else {
                    courseID = try await remoteCourse(for: item.course).id
                    remoteCourses[item.course.id] = courseID
                }
                try await publish(item, courseID: courseID, options: options, report: &report)
            } catch {
                report.failures.append("\(item.title): \(AdminStore.message(for: error))")
            }
        }
        return report
    }

    private func publish(_ item: ClassPublishItem, courseID: UUID, options: ClassPublishOptions,
                         report: inout ClassPublishReport) async throws {
        let existing = admin.catalog.lesson(item.id)
        let draft = Self.lessonDraft(for: item, courseID: courseID,
                                     category: existing?.category ?? options.category)
        let lesson = try await admin.save(draft)
        if existing == nil { report.lessonsCreated += 1 } else { report.lessonsUpdated += 1 }

        let remoteFiles = admin.catalog.attachments(for: lesson.id)
        for file in item.files {
            let previous = remoteFiles.first { $0.id == file.id }
            if let previous, previous.byteSize == file.byteCount {
                report.filesUnchanged += 1
                continue
            }
            guard let data = fileData(file) else {
                report.failures.append(String(localized: "\(item.title): “\(file.fileName)” isn’t on this device, so it wasn’t uploaded."))
                continue
            }
            let title = (file.fileName as NSString).deletingPathExtension
            try await admin.upload(AttachmentUpload(
                lessonID: lesson.id, attachmentID: file.id, replacingVersion: previous?.version,
                title: String((title.isEmpty ? file.fileName : title).prefix(200)),
                visibility: previous?.visibility ?? options.fileVisibility,
                fileName: file.fileName, data: data, sortOrder: file.sortIndex))
            if previous == nil { report.filesUploaded += 1 } else { report.filesReplaced += 1 }
        }

        if lesson.status == .draft {
            try await admin.setStatus(.published, lessonID: lesson.id)
        }
    }

    /// The class course for a homework course, matched by slug so each is created once.
    private func remoteCourse(for course: ClassPublishItem.CourseInfo) async throws -> StudyDomain.Course {
        let slug = Self.slug(for: course)
        if let match = admin.catalog.courses.first(where: { $0.slug == slug }) { return match }
        return try await admin.save(CourseDraft(
            slug: slug, title: String(course.name.prefix(120)), subtitle: course.englishName,
            iconName: course.iconName.hasPrefix("Course") ? course.iconName : "CourseStudy",
            colorKey: Self.colorKey(for: course.colorKey), sortOrder: course.sortOrder))
    }

    static func lessonDraft(for item: ClassPublishItem, courseID: UUID, category: LessonCategory,
                            calendar: Calendar = .current) -> LessonDraft {
        let week = item.weekNumber.flatMap { (0...60).contains($0) ? $0 : nil }
        // The database takes weeks of at most two weeks; anything longer is left undated.
        var days: (String, String)?
        if let start = item.weekStart, let end = item.weekEnd,
           let length = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                                to: calendar.startOfDay(for: end)).day, (0...13).contains(length) {
            days = (CalendarDay.string(from: start, calendar: calendar), CalendarDay.string(from: end, calendar: calendar))
        }
        return LessonDraft(id: item.id, courseID: courseID, title: String(item.title.prefix(200)),
                           category: category, week: week, moduleTitle: item.weekTitle,
                           sortOrder: item.orderInWeek, dueAt: item.dueDate,
                           exerciseCount: min(max(item.totalExercises ?? 0, 0), 500),
                           weekStartsOn: days?.0, weekEndsOn: days?.1)
    }

    /// From the English name when there is one (Hebrew names have no ASCII slug); otherwise
    /// from the course's id, so it stays the same every time.
    static func slug(for course: ClassPublishItem.CourseInfo) -> String {
        let english = course.englishName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !english.isEmpty {
            let slug = CourseDraft.suggestedSlug(for: english)
            if !slug.hasPrefix("course-") { return slug }
        }
        return "course-\(course.id.uuidString.prefix(8).lowercased())"
    }

    /// Homework palette keys → the class catalog's color keys (same shades, different names).
    static func colorKey(for paletteKey: String) -> String {
        switch CoursePalette(rawValue: paletteKey) {
        case .indigo: "dusk"
        case .teal: "moss"
        case .coral: "rust"
        case .green, .none: "forest"
        case .plum: "berry"
        case .blue: "lake"
        case .amber: "honey"
        case .slate: "bark"
        }
    }
}
