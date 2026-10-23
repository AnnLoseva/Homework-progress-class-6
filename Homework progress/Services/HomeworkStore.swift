//
//  HomeworkStore.swift
//  Homework progress
//

import Foundation
import ClassroomUI
import OSLog
import SwiftData

/// All mutations that touch more than one property, or the file system, go through here so the
/// invariants (one course + one week per assignment, independent week copies, files cleaned up
/// with their records) live in one place.
struct HomeworkStore {
    let context: ModelContext
    let files: AttachmentFileStore
    /// Where deletions are recorded so "Subscribe to class" doesn't bring a deleted class
    /// lesson back, here or on the user's other devices. Nil in tests and previews.
    var classLedger: SyncedSettings?

    private static let log = Logger(subsystem: "AnnaLoseva.Homework-progress", category: "HomeworkStore")
    /// The last save error (domain and code only, never record values), for the diagnostics.
    static var lastSaveFailure: String?

    func withClassLedger(_ settings: SyncedSettings?) -> HomeworkStore {
        var store = self
        store.classLedger = settings
        return store
    }

    private func recordRemoval(of assignments: [HomeworkAssignment]) {
        guard let classLedger, !assignments.isEmpty else { return }
        classLedger.add(Set(assignments.map(\.id)), forKey: ClassImportLedger.removedKey)
    }

    // MARK: Weeks

    @discardableResult
    func createWeek(title: String, number: Int?, start: Date, end: Date, planner: WeekPlanner = WeekPlanner(),
                    id: UUID = UUID()) -> AcademicWeek {
        let range = planner.normalized(start: start, end: end)
        let week = AcademicWeek(id: id, title: title, number: number, startDate: range.start, endDate: range.end)
        context.insert(week)
        save()
        return week
    }

    struct DuplicationOptions {
        var copyExerciseCounts = true
        var copyNotes = false
        var shiftDueDates = true
    }

    /// Copies assignment *structure* from `source` into `target` as new, independent records.
    /// Progress is reset; PDFs are not copied (each week gets its own sheets); nothing in
    /// `source` is modified.
    @discardableResult
    func duplicateAssignments(from source: AcademicWeek, into target: AcademicWeek,
                              options: DuplicationOptions = DuplicationOptions(),
                              planner: WeekPlanner = WeekPlanner()) -> [HomeworkAssignment] {
        let offset = planner.dayOffset(from: source.startDate, to: target.startDate)
        let originals = source.assignmentList.sorted { $0.createdAt < $1.createdAt }
        var copies: [HomeworkAssignment] = []
        for original in originals {
            guard let course = original.course else { continue }
            let copy = HomeworkAssignment(
                title: original.title,
                dueDate: options.shiftDueDates ? original.dueDate.map { planner.shift($0, byDays: offset) } : nil,
                totalExercises: options.copyExerciseCounts ? original.totalExercises : nil,
                completedExercises: 0,
                notes: options.copyNotes ? original.notes : "",
                status: .notStarted
            )
            context.insert(copy)
            copy.course = course
            copy.week = target
            copies.append(copy)
        }
        save()
        return copies
    }

    /// Deletes a week, its own assignments and their PDF files. Courses are never deleted.
    func delete(_ week: AcademicWeek) {
        recordRemoval(of: week.assignmentList)
        for assignment in week.assignmentList { deleteFiles(of: assignment) }
        context.delete(week)
        save()
    }

    // MARK: Assignments

    @discardableResult
    func createAssignment(title: String, course: Course, week: AcademicWeek, dueDate: Date? = nil,
                          totalExercises: Int? = nil, notes: String = "", id: UUID = UUID()) -> HomeworkAssignment {
        let cleanedTotal = totalExercises.flatMap { $0 > 0 ? $0 : nil }
        let assignment = HomeworkAssignment(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            totalExercises: cleanedTotal,
            notes: notes
        )
        context.insert(assignment)
        assignment.course = course
        assignment.week = week
        save()
        return assignment
    }

    func delete(_ assignment: HomeworkAssignment) {
        recordRemoval(of: [assignment])
        deleteFiles(of: assignment)
        context.delete(assignment)
        save()
    }

    func delete(_ course: Course) {
        recordRemoval(of: course.assignmentList)
        for assignment in course.assignmentList { deleteFiles(of: assignment) }
        context.delete(course)
        save()
    }

    // MARK: Attachments

    /// Imports a PDF off the main thread and attaches it. Never stores the picker URL.
    @discardableResult
    func attachPDF(from url: URL, to assignment: HomeworkAssignment) async throws -> HomeworkAttachment {
        let files = self.files
        let imported = try await Task.detached(priority: .userInitiated) {
            try files.importPDF(from: url)
        }.value
        return attach(imported, to: assignment)
    }

    @discardableResult
    func attach(_ imported: AttachmentFileStore.ImportedPDF, to assignment: HomeworkAssignment,
                id: UUID = UUID()) -> HomeworkAttachment {
        let existing = assignment.attachmentList.map(\.originalFilename)
        let attachment = HomeworkAttachment(
            id: id,
            originalFilename: FilenameDeduplicator.unique(imported.originalFilename, existing: existing),
            storedFilename: imported.storedFilename,
            byteCount: imported.byteCount,
            pageCount: imported.pageCount,
            sortIndex: (assignment.attachmentList.map(\.sortIndex).max() ?? -1) + 1,
            // The bytes travel with the record so the PDF syncs to the user's other devices.
            pdfData: try? files.data(forStoredFilename: imported.storedFilename)
        )
        context.insert(attachment)
        attachment.assignment = assignment
        assignment.touch()
        save()
        return attachment
    }

    /// Imports the new file first; only after it is safely stored is the old copy removed.
    /// Progress, notes and status are untouched.
    @discardableResult
    func replace(_ attachment: HomeworkAttachment, with url: URL) async throws -> HomeworkAttachment {
        let files = self.files
        let imported = try await Task.detached(priority: .userInitiated) {
            try files.importPDF(from: url)
        }.value
        let oldStored = attachment.storedFilename
        let siblings = attachment.assignment?.attachmentList.filter { $0.id != attachment.id }.map(\.originalFilename) ?? []
        attachment.originalFilename = FilenameDeduplicator.unique(imported.originalFilename, existing: siblings)
        attachment.storedFilename = imported.storedFilename
        attachment.byteCount = imported.byteCount
        attachment.pageCount = imported.pageCount
        attachment.pdfData = try? files.data(forStoredFilename: imported.storedFilename)
        attachment.importedAt = .now
        attachment.assignment?.touch()
        save()
        try? files.delete(storedFilename: oldStored)
        return attachment
    }

    /// Removes the record and the app's copy of the file. Assignment progress is kept.
    func remove(_ attachment: HomeworkAttachment) {
        let stored = attachment.storedFilename
        attachment.assignment?.touch()
        context.delete(attachment)
        save()
        try? files.delete(storedFilename: stored)
    }

    private func deleteFiles(of assignment: HomeworkAssignment) {
        for attachment in assignment.attachmentList {
            try? files.delete(storedFilename: attachment.storedFilename)
        }
    }

    // MARK: Courses

    @discardableResult
    func createCourse(name: String, englishName: String, url: String?, palette: CoursePalette, icon: String,
                      id: UUID = UUID()) -> Course {
        let maxOrder = (try? context.fetch(FetchDescriptor<Course>()))?.map(\.sortOrder).max() ?? -1
        let course = Course(id: id, name: name, englishName: englishName, courseURLString: url,
                            colorKey: palette.rawValue, iconName: icon, sortOrder: maxOrder + 1)
        context.insert(course)
        save()
        return course
    }

    /// Rewrites sort orders 0…n-1 in the given order. Only `sortOrder` changes; assignments
    /// reference courses by relationship, so they are unaffected.
    func reorder(_ courses: [Course]) {
        for (index, course) in courses.enumerated() where course.sortOrder != index {
            course.sortOrder = index
        }
        save()
    }

    func setNotebook(for course: Course, name: String, link: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = link?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLink = !(trimmedLink ?? "").isEmpty
        if trimmedName.isEmpty && !hasLink {
            if let notebook = course.notebook {
                course.notebook = nil
                context.delete(notebook)
            }
        } else if let notebook = course.notebook {
            notebook.notebookName = trimmedName
            notebook.linkString = hasLink ? trimmedLink : nil
            notebook.updatedAt = .now
        } else {
            let notebook = NotabilityNotebookAssociation(notebookName: trimmedName, linkString: hasLink ? trimmedLink : nil)
            context.insert(notebook)
            course.notebook = notebook
        }
        save()
    }

    func save() {
        // The error can quote record values, so it stays redacted in device logs.
        do {
            try context.save()
        } catch {
            Self.log.error("Save failed: \(error, privacy: .private)")
            let ns = error as NSError
            Self.lastSaveFailure = "\(ns.domain) \(ns.code)"
        }
    }
}
