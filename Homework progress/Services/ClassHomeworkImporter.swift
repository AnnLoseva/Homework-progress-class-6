//
//  ClassHomeworkImporter.swift
//  Homework progress
//
//  "Subscribe to class": copies every published class lesson, required and optional, into the
//  user's homework weeks, with its PDFs. The mirror image of ClassPublisher.
//
//  • An assignment reuses its lesson's id (and each PDF its attachment's id), so running again,
//    or on the other device, never duplicates anything; iCloud sync merges the same ids.
//  • Only copies made here are updated when the lesson changes (title, due date, exercise
//    total), and never their progress, status or notes. The administrator's own homework,
//    which the lessons were published from, has the same ids and is left alone.
//  • An assignment the user deletes is not brought back. Turning the subscription off keeps
//    everything already copied.
//

import Foundation
import SwiftData
import StudyDomain

/// Which lessons this device already copied (and may update) or has seen (and must not copy
/// again, e.g. because the user deleted the assignment).
struct ClassImportLedger {
    static let createdKey = "classImport.created"
    static let knownKey = "classImport.known"

    let defaults: UserDefaults
    var created: Set<UUID>
    var known: Set<UUID>

    init(defaults: UserDefaults) {
        self.defaults = defaults
        created = Self.load(Self.createdKey, from: defaults)
        known = Self.load(Self.knownKey, from: defaults)
    }

    func save() {
        defaults.set(created.map(\.uuidString).sorted(), forKey: Self.createdKey)
        defaults.set(known.map(\.uuidString).sorted(), forKey: Self.knownKey)
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }
}

struct ClassImportReport: Equatable {
    var added = 0
    var updated = 0
    var filesAdded = 0
    /// PDFs that couldn't be downloaded yet (offline, or restricted until the class code is
    /// entered). They are tried again on the next pass.
    var filesPending = 0

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
    /// The local file of a lesson PDF (downloaded once, then cached by the Class area).
    let fetchFile: (LessonAttachment) async throws -> URL

    private var context: ModelContext { store.context }

    mutating func run(catalog: Catalog, now: Date = .now) async -> ClassImportReport {
        var report = ClassImportReport()
        let lessons = catalog.lessons
            .filter { $0.isActive(at: now) }
            .sorted { ($0.week ?? .max, $0.sortOrder, $0.title) < ($1.week ?? .max, $1.sortOrder, $1.title) }

        for lesson in lessons {
            if let assignment = existingAssignment(id: lesson.id) {
                ledger.known.insert(lesson.id)
                // Not a copy made here: the user's own homework that was published to the class.
                guard ledger.created.contains(lesson.id) else { continue }
                if update(assignment, from: lesson) { report.updated += 1 }
                await attachMissingFiles(of: lesson, to: assignment, catalog: catalog, report: &report)
                continue
            }
            // Copied before and deleted by the user since: respect that.
            if ledger.known.contains(lesson.id) { continue }
            guard let classCourse = catalog.course(lesson.courseID) else { continue }

            let assignment = store.createAssignment(
                title: lesson.title, course: homeworkCourse(for: classCourse), week: homeworkWeek(for: lesson, now: now),
                dueDate: lesson.dueAt, totalExercises: lesson.exerciseCount,
                notes: lesson.category == .optional ? String(localized: "Optional lesson from the class.") : "",
                id: lesson.id)
            ledger.created.insert(lesson.id)
            ledger.known.insert(lesson.id)
            ledger.save()
            report.added += 1
            await attachMissingFiles(of: lesson, to: assignment, catalog: catalog, report: &report)
        }
        ledger.save()
        return report
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
        if let match = courses.first(where: { Self.slug(of: $0) == classCourse.slug })
            ?? courses.first(where: { $0.name == classCourse.title }) {
            return match
        }
        let palette = CoursePalette.allCases.first { ClassPublisher.colorKey(for: $0.rawValue) == classCourse.colorKey } ?? .indigo
        return store.createCourse(name: classCourse.title, englishName: classCourse.subtitle ?? "", url: nil,
                                  palette: palette, icon: classCourse.iconName)
    }

    static func slug(of course: Course) -> String {
        ClassPublisher.slug(for: .init(id: course.id, name: course.name, englishName: course.englishName,
                                       iconName: course.iconName, colorKey: course.colorKey, sortOrder: course.sortOrder))
    }

    /// The week with the lesson's number, else the week containing its due date, else a new
    /// week around the due date (or this week when there is none).
    private func homeworkWeek(for lesson: Lesson, now: Date) -> AcademicWeek {
        let weeks = (try? context.fetch(FetchDescriptor<AcademicWeek>())) ?? []
        if let number = lesson.week, let match = weeks.first(where: { $0.number == number }) { return match }
        if let due = lesson.dueAt,
           let match = weeks.first(where: { planner.contains(due, start: $0.startDate, end: $0.endDate) }) {
            return match
        }
        let number = lesson.week ?? WeekPlanner.nextNumber(after: weeks.map(\.number))
        let module = lesson.moduleTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let range = planner.range(containing: lesson.dueAt ?? now)
        return store.createWeek(title: module.isEmpty ? WeekPlanner.defaultTitle(number: number) : module,
                                number: number, start: range.start, end: range.end, planner: planner)
    }
}
