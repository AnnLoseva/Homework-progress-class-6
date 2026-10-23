//
//  ClassHomeworkImporter.swift
//  Homework progress
//
//  "Subscribe to class": copies the published lessons of every subscribed class course,
//  required and optional, into the user's homework weeks, with their PDFs. The mirror image of
//  ClassPublisher.
//
//  • An assignment reuses its lesson's id (and each PDF its attachment's id), so running again,
//    or on the other device, never duplicates anything; SyncMaintenance merges records that
//    share an id. Courses and weeks it creates get ids derived from the class too, for the same
//    reason.
//  • Only copies made here are updated when the lesson changes (title, due date, exercise
//    total), and never their progress, status or notes. The administrator's own homework,
//    which the lessons were published from, has the same ids and is left alone.
//  • An assignment the user deletes is not brought back. Turning the subscription off keeps
//    everything already copied, and so does switching a course off.
//

import CryptoKit
import ClassroomUI
import Foundation
import SwiftData
import StudyDomain

/// Which lessons were copied here (and may be updated), seen, or removed by the user. Shared
/// with the user's other devices through iCloud key-value storage.
///
/// Only `removed` stops a lesson from being added. `known` ("seen on some device") used to,
/// but key-value storage reaches devices whose homework doesn't: another CloudKit environment
/// (a TestFlight build next to a development build), or iCloud sync that hasn't delivered or
/// failed. Those devices skipped every lesson and kept an empty week. `known` is still
/// recorded, never cleared.
struct ClassImportLedger {
    static let createdKey = "classImport.created"
    static let knownKey = "classImport.known"
    /// Lesson ids whose assignment the user deleted (HomeworkStore records it on any device).
    static let removedKey = "classImport.removed"

    let settings: SyncedSettings
    var created: Set<UUID>
    var known: Set<UUID>
    var removed: Set<UUID>

    init(settings: SyncedSettings) {
        self.settings = settings
        created = settings.growingIDs(forKey: Self.createdKey)
        known = settings.growingIDs(forKey: Self.knownKey)
        removed = settings.growingIDs(forKey: Self.removedKey)
    }

    init(defaults: UserDefaults) {
        self.init(settings: SyncedSettings(local: defaults, cloud: nil))
    }

    func save() {
        settings.add(created, forKey: Self.createdKey)
        settings.add(known, forKey: Self.knownKey)
    }
}

struct ClassImportReport: Equatable {
    var added = 0
    var updated = 0
    var filesAdded = 0
    /// PDFs that couldn't be downloaded yet (offline, or restricted until the class code is
    /// entered). They are tried again on the next pass.
    var filesPending = 0
    /// Weeks that received new lessons.
    var weeksWithNewLessons: Set<UUID> = []

    // What the pass left out, and why (for the diagnostics).
    var notActive = 0
    var courseSwitchedOff = 0
    var courseMissing = 0
    var removedByUser = 0
    /// Already in the homework: the user's own (published from it) or a copy made earlier.
    var ownHomework = 0
    var existingCopies = 0
    /// Lesson id → the week it was added to.
    var placements: [Placement] = []

    struct Placement: Equatable {
        var lesson: UUID
        var week: UUID
    }

    var message: String {
        var parts: [String] = []
        if added > 0 {
            parts.append(String(localized: "Added \(added) class lesson(s) to your weeks."))
        } else if updated > 0 {
            parts.append(String(localized: "Updated \(updated) class lesson(s) in your weeks."))
        } else {
            parts.append(String(localized: "Your weeks have every class lesson."))
        }
        if filesPending > 0 {
            parts.append(String(localized: "\(filesPending) PDF(s) will follow once you're online and have joined the class with its code."))
        }
        return parts.joined(separator: " ")
    }
}

@MainActor
struct ClassHomeworkImporter {
    let store: HomeworkStore
    let planner: WeekPlanner
    var ledger: ClassImportLedger
    /// Class courses the user switched off.
    var skippedCourses: Set<UUID> = []
    /// The local file of a lesson PDF (downloaded once, then cached by the Class area).
    let fetchFile: (LessonAttachment) async throws -> URL

    private var context: ModelContext { store.context }

    mutating func run(catalog: Catalog, now: Date = .now) async -> ClassImportReport {
        // Deletions since this importer was made (here or on another device) count too.
        ledger.removed.formUnion(ledger.settings.growingIDs(forKey: ClassImportLedger.removedKey))
        var report = ClassImportReport()
        var lessons: [Lesson] = []
        for lesson in catalog.lessons {
            if !lesson.isActive(at: now) { report.notActive += 1 }
            else if skippedCourses.contains(lesson.courseID) { report.courseSwitchedOff += 1 }
            else if catalog.course(lesson.courseID) == nil { report.courseMissing += 1 }
            else { lessons.append(lesson) }
        }
        lessons.sort { ($0.week ?? .max, $0.sortOrder, $0.title) < ($1.week ?? .max, $1.sortOrder, $1.title) }

        for lesson in lessons {
            if let assignment = existingAssignment(id: lesson.id) {
                ledger.known.insert(lesson.id)
                // Not a copy made here: the user's own homework that was published to the class.
                guard ledger.created.contains(lesson.id) else { report.ownHomework += 1; continue }
                report.existingCopies += 1
                if update(assignment, from: lesson) { report.updated += 1 }
                await attachMissingFiles(of: lesson, to: assignment, catalog: catalog, report: &report)
                continue
            }
            // The user deleted its assignment (on this or another device): respect that.
            if ledger.removed.contains(lesson.id) { report.removedByUser += 1; continue }
            guard let assignment = copy(lesson, into: homeworkWeek(for: lesson, now: now), catalog: catalog) else { continue }
            report.added += 1
            if let week = assignment.week {
                report.weeksWithNewLessons.insert(week.id)
                report.placements.append(.init(lesson: lesson.id, week: week.id))
            }
            await attachMissingFiles(of: lesson, to: assignment, catalog: catalog, report: &report)
        }
        ledger.save()
        return report
    }

    /// Class lessons of the subscribed courses that belong to a week (same number, or due within
    /// its dates) and aren't in the homework yet. With `includingRemoved`, also the ones the user
    /// deleted earlier, for adding them back by hand.
    func lessons(forWeekNumber number: Int?, start: Date, end: Date, catalog: Catalog,
                 includingRemoved: Bool = false, now: Date = .now) -> [Lesson] {
        let removed = ledger.removed.union(ledger.settings.growingIDs(forKey: ClassImportLedger.removedKey))
        return catalog.lessons
            .filter { lesson in
                guard lesson.isActive(at: now), !skippedCourses.contains(lesson.courseID),
                      catalog.course(lesson.courseID) != nil, existingAssignment(id: lesson.id) == nil,
                      includingRemoved || !removed.contains(lesson.id) else { return false }
                if let dates = classWeekDates(of: lesson) { return planner.contains(dates.start, start: start, end: end) }
                if let week = lesson.week, let number { return week == number }
                return lesson.dueAt.map { planner.contains($0, start: start, end: end) } ?? false
            }
            .sorted { ($0.dueAt ?? .distantFuture, $0.sortOrder, $0.title) < ($1.dueAt ?? .distantFuture, $1.sortOrder, $1.title) }
    }

    /// Copies the chosen lessons into `week`, whatever week the class gives them.
    mutating func add(_ lessons: [Lesson], to week: AcademicWeek, catalog: Catalog) async -> ClassImportReport {
        var report = ClassImportReport()
        for lesson in lessons where existingAssignment(id: lesson.id) == nil {
            guard let assignment = copy(lesson, into: week, catalog: catalog) else { continue }
            report.added += 1
            await attachMissingFiles(of: lesson, to: assignment, catalog: catalog, report: &report)
        }
        ledger.save()
        return report
    }

    private mutating func copy(_ lesson: Lesson, into week: AcademicWeek, catalog: Catalog) -> HomeworkAssignment? {
        guard let classCourse = catalog.course(lesson.courseID) else { return nil }
        let assignment = store.createAssignment(
            title: lesson.title, course: homeworkCourse(for: classCourse), week: week,
            dueDate: lesson.dueAt, totalExercises: lesson.exerciseCount,
            notes: lesson.category == .optional ? String(localized: "Optional lesson from the class.") : "",
            id: lesson.id)
        ledger.created.insert(lesson.id)
        ledger.known.insert(lesson.id)
        ledger.save()
        return assignment
    }

    private func existingAssignment(id: UUID) -> HomeworkAssignment? {
        var descriptor = FetchDescriptor<HomeworkAssignment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Shared fields only. The exercise total never drops below what the user already completed.
    private func update(_ assignment: HomeworkAssignment, from lesson: Lesson) -> Bool {
        var changed = false
        if assignment.title != lesson.title { assignment.title = lesson.title; changed = true }
        if assignment.dueDate != lesson.dueAt { assignment.dueDate = lesson.dueAt; changed = true }
        let total = lesson.exerciseCount > 0 ? lesson.exerciseCount : nil
        if assignment.totalExercises != total, (total ?? 0) >= assignment.completedExercises {
            assignment.totalExercises = total
            changed = true
        }
        if changed {
            assignment.touch()
            store.save()
        }
        return changed
    }

    private func attachMissingFiles(of lesson: Lesson, to assignment: HomeworkAssignment, catalog: Catalog,
                                    report: inout ClassImportReport) async {
        for file in catalog.attachments(for: lesson.id)
        where !assignment.attachmentList.contains(where: { $0.id == file.id }) {
            do {
                let url = try await fetchFile(file)
                let data = try Data(contentsOf: url)
                // The assignment may have been deleted while the PDF was downloading.
                guard assignment.modelContext != nil else { return }
                let imported = try store.files.importPDF(data: data, originalName: file.fileName)
                store.attach(imported, to: assignment, id: file.id)
                report.filesAdded += 1
            } catch {
                report.filesPending += 1
            }
        }
    }

    /// The homework course a class course came from (same slug rule as publishing), else one
    /// with the same name, else a new course.
    private func homeworkCourse(for classCourse: StudyDomain.Course) -> Course {
        let courses = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        if let match = courses.first(where: { Self.matches($0, classCourse) }) { return match }
        // One of the five default courses: create it as seeding would (same id, Moodle link and
        // icon), so it merges with the other device's copy instead of becoming a second course.
        if let seed = CourseSeeder.defaults.first(where: { Self.matches($0, classCourse) }) {
            return store.createCourse(name: seed.name, englishName: seed.englishName, url: seed.url,
                                      palette: seed.palette, icon: seed.icon, id: seed.id)
        }
        return store.createCourse(name: classCourse.title, englishName: classCourse.subtitle ?? "", url: nil,
                                  palette: Self.palette(for: classCourse), icon: classCourse.iconName, id: classCourse.id)
    }

    /// The same course on both sides: same id, same slug (publishing's rule) or same name.
    static func matches(_ course: Course, _ classCourse: StudyDomain.Course) -> Bool {
        course.id == classCourse.id || slug(of: course) == classCourse.slug || course.name == classCourse.title
    }

    static func matches(_ seed: CourseSeed, _ classCourse: StudyDomain.Course) -> Bool {
        seed.id == classCourse.id || seed.name == classCourse.title
            || (!seed.englishName.isEmpty && seed.englishName == classCourse.subtitle)
            || CourseDraft.suggestedSlug(for: seed.englishName) == classCourse.slug
    }

    /// The class course a homework course belongs to, if the class has it.
    static func classCourse(for course: Course, in catalog: Catalog) -> StudyDomain.Course? {
        catalog.courses.first { !$0.isArchived && matches(course, $0) }
    }

    static func palette(for classCourse: StudyDomain.Course) -> CoursePalette {
        CoursePalette.allCases.first { ClassPublisher.colorKey(for: $0.rawValue) == classCourse.colorKey } ?? .indigo
    }

    static func slug(of course: Course) -> String {
        ClassPublisher.slug(for: .init(id: course.id, name: course.name, englishName: course.englishName,
                                       iconName: course.iconName, colorKey: course.colorKey, sortOrder: course.sortOrder))
    }

    /// The week with the lesson's number, else the week containing its due date, else a new
    /// week around the due date (or this week when there is none).
    ///
    /// A week that has to be created goes where the user's own numbered weeks put that number
    /// (week 4 is three weeks after their week 1), so a class lesson never lands in a week whose
    /// dates contradict the user's calendar. Without numbered weeks the due date decides.
    func homeworkWeek(for lesson: Lesson, now: Date) -> AcademicWeek {
        let weeks = (try? context.fetch(FetchDescriptor<AcademicWeek>())) ?? []
        // The class week's own dates come first: the student's week that holds its first day,
        // else a week with exactly those dates, so everyone has the same calendar week.
        if let dates = classWeekDates(of: lesson) {
            if let match = weeks.first(where: { planner.contains(dates.start, start: $0.startDate, end: $0.endDate) }) {
                return match
            }
            let number = lesson.week ?? WeekPlanner.nextNumber(after: weeks.map(\.number))
            let module = lesson.moduleTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return store.createWeek(title: module.isEmpty ? WeekPlanner.defaultTitle(number: number) : module,
                                    number: number, start: dates.start, end: dates.end, planner: planner,
                                    id: UUID.derived(from: "class-week:\(number):\(lesson.weekStartsOn ?? "")"))
        }
        if let number = lesson.week, let match = weeks.first(where: { $0.number == number }) { return match }
        let anchored = lesson.week.flatMap { anchoredDate(forWeek: $0, among: weeks) }
        if let day = anchored ?? lesson.dueAt,
           let match = weeks.first(where: { planner.contains(day, start: $0.startDate, end: $0.endDate) }) {
            return match
        }
        let number = lesson.week ?? WeekPlanner.nextNumber(after: weeks.map(\.number))
        let module = lesson.moduleTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let range = planner.range(containing: anchored ?? lesson.dueAt ?? now)
        // Both devices may add the same week before either sees the other's: same id, merged.
        return store.createWeek(title: module.isEmpty ? WeekPlanner.defaultTitle(number: number) : module,
                                number: number, start: range.start, end: range.end, planner: planner,
                                id: UUID.derived(from: "class-week:\(number):\(Int(range.start.timeIntervalSince1970))"))
    }
}

extension ClassHomeworkImporter {
    /// The class week's first and last day on this device's calendar, when the class has them.
    func classWeekDates(of lesson: Lesson) -> (start: Date, end: Date)? {
        guard let first = lesson.weekStartsOn.flatMap({ CalendarDay.date(from: $0, calendar: planner.calendar) }),
              let last = lesson.weekEndsOn.flatMap({ CalendarDay.date(from: $0, calendar: planner.calendar) }),
              first <= last else { return nil }
        return (first, last)
    }

    /// A day inside week `number` on the user's calendar: counted in whole weeks from their
    /// nearest numbered week. Nil when they have no numbered week to count from.
    func anchoredDate(forWeek number: Int, among weeks: [AcademicWeek]) -> Date? {
        guard let reference = weeks.filter({ $0.number != nil })
            .min(by: { abs($0.number! - number) < abs($1.number! - number) }),
              let referenceNumber = reference.number else { return nil }
        return planner.shift(reference.startDate, byDays: (number - referenceNumber) * 7)
    }
}

extension UUID {
    /// The same UUID for the same name on every device (SHA-256 based, version 5 layout).
    static func derived(from name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
