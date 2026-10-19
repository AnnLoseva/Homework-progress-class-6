//
//  BackupService.swift
//  Homework progress
//
//  Backup format: see docs/BACKUP_FORMAT.md. One JSON file containing all structured data and
//  every PDF (base64). Versioned with `formatVersion`; restore merges and never deletes.
//

import Foundation
import SwiftData

struct BackupDocument: Codable, Equatable {
    static let formatIdentifier = "hit-homework-backup"
    static let currentVersion = 1

    var format: String = BackupDocument.formatIdentifier
    var formatVersion: Int = BackupDocument.currentVersion
    var exportedAt: Date
    var appVersion: String
    var courses: [CourseRecord]
    var weeks: [WeekRecord]
    var assignments: [AssignmentRecord]
    var attachments: [AttachmentRecord]

    struct CourseRecord: Codable, Equatable {
        var id: UUID
        var name: String
        var englishName: String
        var courseURL: String?
        var colorKey: String
        var iconName: String
        var sortOrder: Int
        var createdAt: Date
        var notebookName: String?
        var notebookLink: String?
    }

    struct WeekRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var number: Int?
        var startDate: Date
        var endDate: Date
        var notes: String
        var createdAt: Date
    }

    struct AssignmentRecord: Codable, Equatable {
        var id: UUID
        var courseID: UUID
        var weekID: UUID
        var title: String
        var dueDate: Date?
        var totalExercises: Int?
        var completedExercises: Int
        var notes: String
        var status: String
        var createdAt: Date
        var updatedAt: Date
    }

    struct AttachmentRecord: Codable, Equatable {
        var id: UUID
        var assignmentID: UUID
        var originalFilename: String
        var pageCount: Int
        var sortIndex: Int
        var importedAt: Date
        /// Raw PDF bytes, base64-encoded in JSON. `nil` if the app's copy was missing at export.
        var pdf: Data?
    }
}

struct BackupService {
    let context: ModelContext
    let files: AttachmentFileStore

    enum BackupError: LocalizedError {
        case unsupportedFormat
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: String(localized: "This file isn’t a Homework Progress backup.")
            case .newerVersion(let v): String(localized: "This backup (format \(v)) was made by a newer version of the app.")
            }
        }
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func makeDocument(now: Date = .now) throws -> BackupDocument {
        let courses = try context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.sortOrder)]))
        let weeks = try context.fetch(FetchDescriptor<AcademicWeek>(sortBy: [SortDescriptor(\.startDate)]))
        let assignments = try context.fetch(FetchDescriptor<HomeworkAssignment>())
        let attachments = try context.fetch(FetchDescriptor<HomeworkAttachment>())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

        return BackupDocument(
            exportedAt: now,
            appVersion: version,
            courses: courses.map {
                .init(id: $0.id, name: $0.name, englishName: $0.englishName, courseURL: $0.courseURLString,
                      colorKey: $0.colorKey, iconName: $0.iconName, sortOrder: $0.sortOrder, createdAt: $0.createdAt,
                      notebookName: $0.notebook?.notebookName, notebookLink: $0.notebook?.linkString)
            },
            weeks: weeks.map {
                .init(id: $0.id, title: $0.title, number: $0.number, startDate: $0.startDate,
                      endDate: $0.endDate, notes: $0.notes, createdAt: $0.createdAt)
            },
            assignments: assignments.compactMap { a in
                guard let course = a.course, let week = a.week else { return nil }
                return .init(id: a.id, courseID: course.id, weekID: week.id, title: a.title, dueDate: a.dueDate,
                             totalExercises: a.totalExercises, completedExercises: a.completedExercises,
                             notes: a.notes, status: a.statusRaw, createdAt: a.createdAt, updatedAt: a.updatedAt)
            },
            attachments: attachments.compactMap { file in
                guard let assignment = file.assignment else { return nil }
                return .init(id: file.id, assignmentID: assignment.id, originalFilename: file.originalFilename,
                             pageCount: file.pageCount, sortIndex: file.sortIndex, importedAt: file.importedAt,
                             pdf: try? files.data(forStoredFilename: file.storedFilename))
            }
        )
    }

    func exportData() throws -> Data {
        try Self.encoder().encode(makeDocument())
    }

    static func suggestedFilename(now: Date = .now) -> String {
        "Homework Backup \(now.formatted(.iso8601.year().month().day())).json"
    }

    struct RestoreReport: Equatable {
        var coursesAdded = 0
        var weeksAdded = 0
        var assignmentsAdded = 0
        var attachmentsAdded = 0
        var skippedExisting = 0
        var missingFiles = 0
    }

    /// Merges a backup into the current database. Records whose ID already exists are left as
    /// they are, so restoring never overwrites or deletes anything.
    func restore(from data: Data) throws -> RestoreReport {
        let document = try Self.decoder().decode(BackupDocument.self, from: data)
        guard document.format == BackupDocument.formatIdentifier else { throw BackupError.unsupportedFormat }
        guard document.formatVersion <= BackupDocument.currentVersion else { throw BackupError.newerVersion(document.formatVersion) }

        var report = RestoreReport()
        var courses = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Course>()).map { ($0.id, $0) })
        var weeks = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AcademicWeek>()).map { ($0.id, $0) })
        var assignments = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<HomeworkAssignment>()).map { ($0.id, $0) })
        let attachmentIDs = Set(try context.fetch(FetchDescriptor<HomeworkAttachment>()).map(\.id))

        for record in document.courses {
            guard courses[record.id] == nil else { report.skippedExisting += 1; continue }
            let course = Course(id: record.id, name: record.name, englishName: record.englishName,
                                courseURLString: record.courseURL, colorKey: record.colorKey,
                                iconName: record.iconName, sortOrder: record.sortOrder, createdAt: record.createdAt)
            context.insert(course)
            if record.notebookName != nil || record.notebookLink != nil {
                let notebook = NotabilityNotebookAssociation(notebookName: record.notebookName ?? "", linkString: record.notebookLink)
                context.insert(notebook)
                course.notebook = notebook
            }
            courses[record.id] = course
            report.coursesAdded += 1
        }

        for record in document.weeks {
            guard weeks[record.id] == nil else { report.skippedExisting += 1; continue }
            let week = AcademicWeek(id: record.id, title: record.title, number: record.number, startDate: record.startDate,
                                    endDate: record.endDate, notes: record.notes, createdAt: record.createdAt)
            context.insert(week)
            weeks[record.id] = week
            report.weeksAdded += 1
        }

        for record in document.assignments {
            guard assignments[record.id] == nil else { report.skippedExisting += 1; continue }
            guard let course = courses[record.courseID], let week = weeks[record.weekID] else { continue }
            let assignment = HomeworkAssignment(id: record.id, title: record.title, dueDate: record.dueDate,
                                                totalExercises: record.totalExercises,
                                                completedExercises: record.completedExercises, notes: record.notes,
                                                status: AssignmentStatus(rawValue: record.status) ?? .notStarted,
                                                createdAt: record.createdAt)
            assignment.updatedAt = record.updatedAt
            context.insert(assignment)
            assignment.course = course
            assignment.week = week
            assignments[record.id] = assignment
            report.assignmentsAdded += 1
        }

        for record in document.attachments {
            guard !attachmentIDs.contains(record.id) else { report.skippedExisting += 1; continue }
            guard let assignment = assignments[record.assignmentID] else { continue }
            guard let pdf = record.pdf,
                  let imported = try? files.importPDF(data: pdf, originalName: record.originalFilename) else {
                report.missingFiles += 1
                continue
            }
            let attachment = HomeworkAttachment(id: record.id, originalFilename: record.originalFilename,
                                                storedFilename: imported.storedFilename, byteCount: imported.byteCount,
                                                pageCount: imported.pageCount, importedAt: record.importedAt,
                                                sortIndex: record.sortIndex)
            context.insert(attachment)
            attachment.assignment = assignment
            report.attachmentsAdded += 1
        }

        try context.save()
        return report
    }
}
