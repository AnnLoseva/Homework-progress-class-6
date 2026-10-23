//
//  ClassHomeworkSync.swift
//  Homework progress
//
//  "Follow the whole class" (Class → Class Account): every published class lesson, required
//  and optional, becomes an assignment in the student's Homework weeks, with its PDFs, and
//  the lesson's progress and the assignment's progress stay in step both ways.
//
//  • The assignment reuses the lesson's id. Publishing already does the same in the other
//    direction, so an administrator's own homework is linked instead of duplicated, and two
//    devices importing the same lesson converge (SyncMaintenance merges records by id).
//  • Weeks are matched by number, then by due date; a missing week is created with an id
//    derived from its number and dates, so iPhone and iPad create the same week.
//  • Courses are matched like ClassPublisher names them (slug), then by name; otherwise the
//    class course is added to Homework.
//  • Only shared content is copied. Turning the option off stops syncing but removes nothing,
//    and an assignment the student deleted is not brought back.
//  • Progress: whichever side changed since the last sync wins; if both changed, the newer
//    change wins. Progress stays private to the student (RLS), exactly like Class progress.
//

import CryptoKit
import Foundation
import SwiftData
import StudyData
import StudyDomain

@MainActor
struct ClassHomeworkSync {
    struct Report: Equatable {
        var assignmentsCreated = 0
        var assignmentsUpdated = 0
        var weeksCreated = 0
        var coursesCreated = 0
        var filesAdded = 0
        var filesReplaced = 0
        var optionalLessonsFollowed = 0
        var progressSentToClass = 0
        var progressTakenFromClass = 0
    }

    let store: HomeworkStore
    let student: StudentStore
    /// Returns a local copy of a lesson PDF (the Class tab's offline cache). `nil` skips PDFs.
    let download: ((LessonAttachment) async throws -> URL)?
    let defaults: UserDefaults
    var planner = WeekPlanner()

    private var context: ModelContext { store.context }

    @discardableResult
    func run() async -> Report {
        var report = Report()
        let now = student.currentDate
        let lessons = student.catalog.lessons
            .filter { $0.isActive(at: now) }
            .sorted { ($0.week ?? .max, $0.sortOrder, $0.title) < ($1.week ?? .max, $1.sortOrder, $1.title) }
        guard !lessons.isEmpty else { return report }

        var state = LinkState.load(from: defaults, userID: student.userID)
        let original = state

        for lesson in lessons where lesson.category == .optional && !state.followedLessonIDs.contains(lesson.id) {
            // Once per lesson: a lesson the student unfollows later in Class stays unfollowed.
            if student.subscriptions[lesson.id]?.isActive != true {
                await student.setSubscribed(true, lessonID: lesson.id)
                report.optionalLessonsFollowed += 1
            }
            state.followedLessonIDs.insert(lesson.id)
        }

        for lesson in lessons {
            var link = state.lessons[lesson.id]
            guard let assignment = linkedAssignment(for: lesson, link: &link, report: &report) else {
                state.lessons[lesson.id] = link
                continue
            }
            var current = link ?? Link(lessonUpdatedAt: lesson.updatedAt)
            // Progress before files: attaching a PDF bumps the assignment's modification date.
            await syncProgress(assignment, lesson: lesson, link: &current, report: &report)
            await syncFiles(assignment, lesson: lesson, link: &current, report: &report)
            state.lessons[lesson.id] = current
        }

        // Saving with nothing to save would trigger the next pass for no reason.
        if context.hasChanges { store.save() }
        if state != original { state.save(to: defaults, userID: student.userID) }
        return report
    }

    // MARK: Assignments

    /// The homework assignment for a lesson: found, created on first sight, or `nil` when the
    /// student deleted the one created earlier.
    private func linkedAssignment(for lesson: Lesson, link: inout Link?, report: inout Report) -> HomeworkAssignment? {
        if let existing = assignment(id: lesson.id) {
            if var known = link {
                if lesson.updatedAt > known.lessonUpdatedAt {
                    updateContent(of: existing, from: lesson)
                    known.lessonUpdatedAt = lesson.updatedAt
                    link = known
                    report.assignmentsUpdated += 1
                }
            } else {
                // Already in Homework (the administrator's own published homework): link only.
                link = Link(lessonUpdatedAt: lesson.updatedAt)
            }
            return existing
        }
        guard link == nil else { return nil }
        let course = homeworkCourse(for: lesson, report: &report)
        let week = homeworkWeek(for: lesson, report: &report)
        let created = store.createAssignment(
            title: lesson.title, course: course, week: week, dueDate: lesson.dueAt,
            totalExercises: lesson.exerciseCount > 0 ? lesson.exerciseCount : nil, id: lesson.id)
        link = Link(lessonUpdatedAt: lesson.updatedAt)
        report.assignmentsCreated += 1
        return created
    }

    /// Shared fields only; the student's progress, notes and week placement are kept.
    private func updateContent(of assignment: HomeworkAssignment, from lesson: Lesson) {
        assignment.title = lesson.title
        assignment.dueDate = lesson.dueAt
        if lesson.exerciseCount > 0, assignment.totalExercises != lesson.exerciseCount {
            assignment.apply(assignment.exerciseState.settingTotal(lesson.exerciseCount, resolving: .keepCompleted))
        }
    }

    private func assignment(id: UUID) -> HomeworkAssignment? {
        var descriptor = FetchDescriptor<HomeworkAssignment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Courses and weeks

    private func homeworkCourse(for lesson: Lesson, report: inout Report) -> Course {
        let courses = (try? context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        guard let classCourse = student.catalog.course(lesson.courseID) else {
            return courses.first ?? newCourse(id: lesson.courseID, name: String(localized: "Class"), report: &report)
        }
        if let match = courses.first(where: { $0.id == classCourse.id })
            ?? courses.first(where: { ClassPublisher.slug(for: Self.courseInfo($0)) == classCourse.slug })
            ?? courses.first(where: { $0.name == classCourse.title }) {
            return match
        }
        let course = newCourse(id: classCourse.id, name: classCourse.title, report: &report)
        course.englishName = classCourse.subtitle ?? ""
        course.iconName = classCourse.iconName
        course.colorKey = Self.paletteKey(forClassColor: classCourse.colorKey)
        course.sortOrder = (courses.map(\.sortOrder).max() ?? 0) + 1
        return course
    }

    private func newCourse(id: UUID, name: String, report: inout Report) -> Course {
        let course = Course(id: id, name: name)
        context.insert(course)
        report.coursesCreated += 1
        return course
    }

    private func homeworkWeek(for lesson: Lesson, report: inout Report) -> AcademicWeek {
        let weeks = ((try? context.fetch(FetchDescriptor<AcademicWeek>())) ?? []).sorted(by: AcademicWeek.chronological)
        if let number = lesson.week, let match = weeks.first(where: { $0.number == number }) { return match }
        if let due = lesson.dueAt,
           let match = weeks.first(where: { planner.contains(due, start: $0.startDate, end: $0.endDate) }) {
            return match
        }

        let range: WeekPlanner.Range
        if let due = lesson.dueAt {
            range = planner.range(containing: due)
        } else if let number = lesson.week, let anchor = weeks.first(where: { $0.number != nil }), let anchorNumber = anchor.number {
            let start = planner.shift(anchor.startDate, byDays: 7 * (number - anchorNumber))
            range = planner.range(containing: start)
        } else {
            range = planner.range(containing: student.currentDate)
        }
        let title = lesson.moduleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (lesson.week.map(WeekPlanner.defaultTitle(number:)) ?? String(localized: "Class lessons"))
            : lesson.moduleTitle
        let week = store.createWeek(title: title, number: lesson.week, start: range.start, end: range.end, planner: planner)
        week.id = Self.stableID("class-week|\(lesson.week.map(String.init) ?? "-")|\(Int(range.start.timeIntervalSince1970))")
        report.weeksCreated += 1
        return week
    }

    // MARK: Progress

    private func syncProgress(_ assignment: HomeworkAssignment, lesson: Lesson, link: inout Link, report: inout Report) async {
        let homework = Self.homeworkProgress(assignment, lesson: lesson)
        let remote = student.progress[lesson.id]
        let classSide = Self.classProgress(remote ?? .empty(for: lesson.id), lesson: lesson)
        guard homework != classSide else {
            link.synced = homework
            return
        }

        let homeworkChanged = homework != link.synced
        let classChanged = remote != nil && classSide != link.synced
        let sendToClass: Bool
        switch (homeworkChanged, classChanged) {
        case (true, false): sendToClass = true
        case (false, true): sendToClass = false
        default: sendToClass = assignment.updatedAt >= (remote?.clientModifiedAt ?? .distantPast)
        }

        if sendToClass {
            if lesson.exerciseCount > 0, student.progress(for: lesson.id).completedExercises != homework.completed {
                await student.setCompletedExercises(homework.completed, lessonID: lesson.id)
            }
            if student.progress(for: lesson.id).status.rawValue != homework.status {
                await student.setStatus(ProgressStatus(rawValue: homework.status) ?? .notStarted, lessonID: lesson.id)
            }
            report.progressSentToClass += 1
            // The class may round the change (e.g. "completed" fills the count); mirror that back.
            apply(Self.classProgress(student.progress(for: lesson.id), lesson: lesson), to: assignment, lesson: lesson)
        } else {
            apply(classSide, to: assignment, lesson: lesson)
            report.progressTakenFromClass += 1
        }
        link.synced = Self.classProgress(student.progress(for: lesson.id), lesson: lesson)
    }

    private func apply(_ progress: SyncedProgress, to assignment: HomeworkAssignment, lesson: Lesson) {
        guard Self.homeworkProgress(assignment, lesson: lesson) != progress else { return }
        var state = assignment.exerciseState
        if lesson.exerciseCount > 0 { state = state.settingCompleted(progress.completed) }
        switch ProgressStatus(rawValue: progress.status) ?? .notStarted {
        case .completed:
            state = state.markedCompleted()
        case .inProgress:
            if state.status != .inProgress { state = state.settingStatus(.inProgress) }
        case .notStarted:
            if state.status == .completed || state.status == .inProgress { state = state.settingStatus(.notStarted) }
        }
        assignment.apply(state)
    }

    /// Both sides in the class's terms. "Completed" always counts every exercise, so a lesson
    /// and an assignment with slightly different totals don't flip each other back and forth.
    static func homeworkProgress(_ assignment: HomeworkAssignment, lesson: Lesson) -> SyncedProgress {
        let total = lesson.exerciseCount
        let completed = total > 0 ? min(max(assignment.completedExercises, 0), total) : 0
        let status: ProgressStatus = switch assignment.status {
        case .completed: .completed
        case .inProgress: .inProgress
        case .notStarted, .notAssigned, .postponed: completed > 0 ? .inProgress : .notStarted
        }
        return SyncedProgress(completed: status == .completed ? total : completed, status: status.rawValue)
    }

    static func classProgress(_ progress: LessonProgress, lesson: Lesson) -> SyncedProgress {
        let total = lesson.exerciseCount
        let completed = progress.status == .completed ? total : (total > 0 ? min(progress.completedExercises, total) : 0)
        return SyncedProgress(completed: completed, status: progress.status.rawValue)
    }

    // MARK: Files

    private func syncFiles(_ assignment: HomeworkAssignment, lesson: Lesson, link: inout Link, report: inout Report) async {
        guard let download else { return }
        let enrolled = student.identity?.isEnrolled == true
        for file in student.catalog.attachments(for: lesson.id) {
            if file.visibility == .restricted, !enrolled { continue }   // needs the class code first
            let known = link.fileVersions[file.id]
            let existing = assignment.attachmentList.first { $0.id == file.id }
            if let known, existing == nil { continue }                  // the student removed it
            if let known, known >= file.version { continue }
            guard let url = try? await download(file) else { continue } // retried next time
            if let existing {
                guard (try? await store.replace(existing, with: url)) != nil else { continue }
                report.filesReplaced += 1
            } else {
                guard let imported = try? store.files.importPDF(from: url) else { continue }
                store.attach(imported, to: assignment, id: file.id)
                report.filesAdded += 1
            }
            link.fileVersions[file.id] = file.version
        }
    }

    // MARK: Helpers

    static func courseInfo(_ course: Course) -> ClassPublishItem.CourseInfo {
        .init(id: course.id, name: course.name, englishName: course.englishName, iconName: course.iconName,
              colorKey: course.colorKey, sortOrder: course.sortOrder)
    }

    /// The inverse of `ClassPublisher.colorKey(for:)`.
    static func paletteKey(forClassColor key: String) -> String {
        let palette: CoursePalette = switch key {
        case "dusk": .indigo
        case "moss": .teal
        case "rust": .coral
        case "berry": .plum
        case "lake": .blue
        case "honey": .amber
        case "bark": .slate
        default: .green
        }
        return palette.rawValue
    }

    /// A UUID that is the same on every device for the same text.
    static func stableID(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - What was synced last (per user, on this device)

struct SyncedProgress: Codable, Equatable {
    var completed: Int
    var status: String
}

extension ClassHomeworkSync {
    struct Link: Codable, Equatable {
        var lessonUpdatedAt: Date
        var synced: SyncedProgress?
        var fileVersions: [UUID: Int] = [:]
    }

    struct LinkState: Codable, Equatable {
        var lessons: [UUID: Link] = [:]
        var followedLessonIDs: Set<UUID> = []

        static func key(for userID: UUID) -> String { "classSync.state.\(userID.uuidString.lowercased())" }

        static func load(from defaults: UserDefaults, userID: UUID) -> LinkState {
            guard let data = defaults.data(forKey: key(for: userID)),
                  let state = try? JSONDecoder().decode(LinkState.self, from: data) else { return LinkState() }
            return state
        }

        func save(to defaults: UserDefaults, userID: UUID) {
            if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(for: userID)) }
        }
    }
}

// MARK: - When it runs

/// Runs `ClassHomeworkSync` a moment after Class data or homework changes, one pass at a time.
@MainActor
final class ClassSyncCoordinator {
    private var pending: Task<Void, Never>?
    private var isRunning = false
    private var runAgain = false

    func schedule(_ makeSync: @escaping @MainActor () -> ClassHomeworkSync?) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.run(makeSync)
        }
    }

    private func run(_ makeSync: @escaping @MainActor () -> ClassHomeworkSync?) async {
        guard !isRunning else { runAgain = true; return }
        isRunning = true
        defer { isRunning = false }
        repeat {
            runAgain = false
            guard let sync = makeSync() else { return }
            await sync.run()
        } while runAgain
    }
}
