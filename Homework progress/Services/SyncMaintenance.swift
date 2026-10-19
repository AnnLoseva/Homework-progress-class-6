//
//  SyncMaintenance.swift
//  Homework progress
//
//  Housekeeping that keeps two devices' data tidy after iCloud sync:
//  • Each device seeds the five courses with the same stable IDs before it has seen the other
//    device's data, and iCloud has no uniqueness constraints — so records sharing an `id` are
//    merged (their assignments, PDFs and notebook are moved to one keeper, nothing is lost).
//  • PDFs imported before sync existed get their bytes copied into the record so they upload.
//  • PDFs that arrived from the other device are written to local files.
//  • Local PDF copies whose record was deleted (here or on the other device) are removed.
//

import Foundation
import SwiftData

struct SyncMaintenance {
    let context: ModelContext
    let files: AttachmentFileStore

    struct Report: Equatable {
        var mergedCourses = 0
        var mergedWeeks = 0
        var mergedAssignments = 0
        var mergedAttachments = 0
        var uploadedPDFs = 0
        var downloadedPDFs = 0
        var removedLocalFiles = 0

        var changedDatabase: Bool {
            mergedCourses + mergedWeeks + mergedAssignments + mergedAttachments + uploadedPDFs > 0
        }
    }

    /// Local files younger than this are kept even if unreferenced: a PDF picked in the
    /// "New Assignment" sheet is stored before its record exists.
    static let orphanGracePeriod: TimeInterval = 24 * 3600

    @discardableResult
    func run(now: Date = .now) -> Report {
        var report = Report()
        report.mergedCourses = mergeDuplicateCourses()
        report.mergedWeeks = mergeDuplicateWeeks()
        report.mergedAssignments = mergeDuplicateAssignments()
        report.mergedAttachments = mergeDuplicateAttachments()
        (report.uploadedPDFs, report.downloadedPDFs) = reconcilePDFs()
        if report.changedDatabase { try? context.save() }
        report.removedLocalFiles = removeOrphanFiles(now: now)
        return report
    }

    // MARK: Duplicates

    private func groups<T: PersistentModel>(_ type: T.Type, id: (T) -> UUID) -> [[T]] {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return Dictionary(grouping: all, by: id).values.filter { $0.count > 1 }
    }

    /// Keeps the oldest course (the one created first, on whichever device) and moves
    /// everything that points at the copies onto it.
    func mergeDuplicateCourses() -> Int {
        var merged = 0
        for group in groups(Course.self, id: \.id) {
            let sorted = group.sorted {
                ($0.createdAt, -$0.assignmentList.count) < ($1.createdAt, -$1.assignmentList.count)
            }
            let keeper = sorted[0]
            for duplicate in sorted.dropFirst() {
                for assignment in duplicate.assignmentList { assignment.course = keeper }
                if keeper.notebook == nil, let notebook = duplicate.notebook {
                    duplicate.notebook = nil
                    keeper.notebook = notebook
                }
                context.delete(duplicate)
                merged += 1
            }
        }
        return merged
    }

    func mergeDuplicateWeeks() -> Int {
        var merged = 0
        for group in groups(AcademicWeek.self, id: \.id) {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            let keeper = sorted[0]
            for duplicate in sorted.dropFirst() {
                for assignment in duplicate.assignmentList { assignment.week = keeper }
                context.delete(duplicate)
                merged += 1
            }
        }
        return merged
    }

    /// Keeps the most recently updated copy, so the latest progress wins.
    func mergeDuplicateAssignments() -> Int {
        var merged = 0
        for group in groups(HomeworkAssignment.self, id: \.id) {
            let sorted = group.sorted { $0.updatedAt > $1.updatedAt }
            let keeper = sorted[0]
            for duplicate in sorted.dropFirst() {
                for attachment in duplicate.attachmentList { attachment.assignment = keeper }
                context.delete(duplicate)
                merged += 1
            }
        }
        return merged
    }

    func mergeDuplicateAttachments() -> Int {
        var merged = 0
        for group in groups(HomeworkAttachment.self, id: \.id) {
            let sorted = group.sorted { ($0.pdfData == nil ? 1 : 0) < ($1.pdfData == nil ? 1 : 0) }
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                merged += 1
            }
        }
        return merged
    }

    // MARK: PDFs

    /// Uploads bytes for PDFs imported before sync existed; writes local files for PDFs
    /// that synced in from the other device.
    func reconcilePDFs() -> (uploaded: Int, downloaded: Int) {
        let attachments = (try? context.fetch(FetchDescriptor<HomeworkAttachment>())) ?? []
        var uploaded = 0, downloaded = 0
        for attachment in attachments {
            let hasFile = files.fileExists(storedFilename: attachment.storedFilename)
            if hasFile {
                if attachment.pdfData == nil, let data = try? files.data(forStoredFilename: attachment.storedFilename) {
                    attachment.pdfData = data
                    uploaded += 1
                }
            } else if files.ensureLocalFile(storedFilename: attachment.storedFilename, data: { attachment.pdfData }) {
                downloaded += 1
            }
        }
        return (uploaded, downloaded)
    }

    /// Deletes local copies no record refers to any more (the PDF was removed or replaced,
    /// possibly on the other device). The synced data itself is untouched.
    func removeOrphanFiles(now: Date) -> Int {
        let attachments = (try? context.fetch(FetchDescriptor<HomeworkAttachment>())) ?? []
        let referenced = Set(attachments.map(\.storedFilename))
        var removed = 0
        for file in files.localFiles() where !referenced.contains(file.name) {
            guard now.timeIntervalSince(file.modified) > Self.orphanGracePeriod else { continue }
            if (try? files.delete(storedFilename: file.name)) != nil { removed += 1 }
        }
        return removed
    }
}
