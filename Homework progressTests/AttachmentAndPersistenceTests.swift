//
//  AttachmentAndPersistenceTests.swift
//  Homework progressTests
//

import Foundation
import SwiftData
import Testing
@testable import Homework_progress

@Suite("PDF attachments")
@MainActor
struct AttachmentTests {
    @Test func importCopiesIntoAppStorage() throws {
        let env = try TestEnvironment()
        let source = try env.makePDF(named: "Discrete HW5.pdf", pages: 3)
        let imported = try env.files.importPDF(from: source)

        #expect(imported.originalFilename == "Discrete HW5.pdf")
        #expect(imported.pageCount == 3)
        #expect(imported.byteCount > 0)
        #expect(imported.storedFilename != "Discrete HW5.pdf")
        #expect(env.files.fileExists(storedFilename: imported.storedFilename))

        // The app's copy survives the source disappearing (e.g. a temporary picker URL).
        try FileManager.default.removeItem(at: source)
        #expect(env.files.fileExists(storedFilename: imported.storedFilename))
    }

    @Test func nonPDFIsRejectedWithoutLeavingFiles() throws {
        let env = try TestEnvironment()
        #expect(throws: AttachmentFileStore.StoreError.notAPDF("notes.pdf")) {
            try env.files.importPDF(from: env.makeTextFile())
        }
        #expect(env.attachmentFileCount() == 0)
    }

    @Test func missingSourceIsReported() throws {
        let env = try TestEnvironment()
        let missing = env.root.appendingPathComponent("gone.pdf")
        #expect(throws: AttachmentFileStore.StoreError.self) {
            try env.files.importPDF(from: missing)
        }
    }

    @Test func duplicateFilenamesAreDisambiguated() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let assignment = env.store.createAssignment(title: "HW", course: courses[0], week: week)
        let first = env.store.attach(try env.files.importPDF(from: env.makePDF(named: "Sheet.pdf")), to: assignment)
        let second = env.store.attach(try env.files.importPDF(from: env.makePDF(named: "Sheet.pdf")), to: assignment)
        #expect(first.originalFilename == "Sheet.pdf")
        #expect(second.originalFilename == "Sheet (2).pdf")
        #expect(first.storedFilename != second.storedFilename)
        #expect(env.attachmentFileCount() == 2)
    }

    @Test func replacingKeepsProgressAndRemovesOldCopy() async throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let assignment = env.store.createAssignment(title: "HW", course: courses[0], week: week, totalExercises: 8)
        assignment.apply(assignment.exerciseState.settingCompleted(3))
        let attachment = env.store.attach(try env.files.importPDF(from: env.makePDF(named: "Old.pdf")), to: assignment)
        let oldStored = attachment.storedFilename

        try await env.store.replace(attachment, with: env.makePDF(named: "New.pdf", pages: 4))

        #expect(attachment.originalFilename == "New.pdf")
        #expect(attachment.pageCount == 4)
        #expect(!env.files.fileExists(storedFilename: oldStored))
        #expect(env.files.fileExists(storedFilename: attachment.storedFilename))
        #expect(assignment.completedExercises == 3)
        #expect(assignment.totalExercises == 8)
    }

    @Test func failedReplacementKeepsTheOriginal() async throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let assignment = env.store.createAssignment(title: "HW", course: courses[0], week: week)
        let attachment = env.store.attach(try env.files.importPDF(from: env.makePDF(named: "Keep.pdf")), to: assignment)

        await #expect(throws: AttachmentFileStore.StoreError.self) {
            try await env.store.replace(attachment, with: env.makeTextFile())
        }
        #expect(attachment.originalFilename == "Keep.pdf")
        #expect(env.files.fileExists(storedFilename: attachment.storedFilename))
    }

    @Test func removingDeletesFileButKeepsProgress() throws {
        let env = try TestEnvironment()
        let courses = try env.seed()
        let week = env.store.createWeek(title: "W", number: nil, start: .now, end: .now)
        let assignment = env.store.createAssignment(title: "HW", course: courses[0], week: week, totalExercises: 5)
        assignment.apply(assignment.exerciseState.settingCompleted(2))
        let attachment = env.store.attach(try env.files.importPDF(from: env.makePDF()), to: assignment)
        let stored = attachment.storedFilename

        env.store.remove(attachment)

        #expect(assignment.attachmentList.isEmpty)
        #expect(!env.files.fileExists(storedFilename: stored))
        #expect(assignment.completedExercises == 2)
    }

    @Test func missingFileIsHandledGracefully() throws {
        let env = try TestEnvironment()
        let imported = try env.files.importPDF(from: env.makePDF(named: "Lost.pdf"))
        try FileManager.default.removeItem(at: env.files.url(forStoredFilename: imported.storedFilename))

        #expect(!env.files.fileExists(storedFilename: imported.storedFilename))
        #expect(throws: AttachmentFileStore.StoreError.missingFile("Lost.pdf")) {
            try env.files.makeHandoffCopy(storedFilename: imported.storedFilename, displayName: "Lost.pdf")
        }
        try env.files.delete(storedFilename: imported.storedFilename) // no throw for missing files
    }

    @Test func handoffCopyLeavesOriginalIntact() throws {
        let env = try TestEnvironment()
        let imported = try env.files.importPDF(from: env.makePDF(named: "Algebra.pdf"))
        let original = try env.files.data(forStoredFilename: imported.storedFilename)

        let copy = try env.files.makeHandoffCopy(storedFilename: imported.storedFilename, displayName: "Algebra.pdf")
        #expect(copy.lastPathComponent == "Algebra.pdf")
        try FileManager.default.removeItem(at: copy) // whatever the receiving app does…
        env.files.clearHandoffCopies()

        #expect(try env.files.data(forStoredFilename: imported.storedFilename) == original)
    }
}

@Suite("Persistence across launches")
@MainActor
struct PersistenceTests {
    @Test func dataAndFilesSurviveRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HPRelaunch-\(UUID().uuidString)")
        let storeURL = root.appendingPathComponent("Homework.store")
        var storedFilename = ""

        do {
            let env = try TestEnvironment(storeURL: storeURL, root: root)
            let courses = try env.seed()
            let week = env.store.createWeek(title: "Week 5", number: 5, start: date(2026, 10, 18), end: date(2026, 10, 24))
            let assignment = env.store.createAssignment(title: "HW 5", course: courses[4], week: week, totalExercises: 9)
            assignment.apply(assignment.exerciseState.settingCompleted(6))
            let attachment = env.store.attach(try env.files.importPDF(from: env.makePDF()), to: assignment)
            storedFilename = attachment.storedFilename
            try env.context.save()
        }

        // "Relaunch": a brand-new container on the same store file.
        let relaunched = try TestEnvironment(storeURL: storeURL, root: root)
        let assignments = try relaunched.context.fetch(FetchDescriptor<HomeworkAssignment>())
        let assignment = try #require(assignments.first)
        #expect(assignment.title == "HW 5")
        #expect(assignment.completedExercises == 6)
        #expect(assignment.totalExercises == 9)
        #expect(assignment.course?.name == "מתמטיקה בדידה")
        #expect(assignment.week?.title == "Week 5")
        let attachment = try #require(assignment.attachmentList.first)
        #expect(attachment.storedFilename == storedFilename)
        #expect(relaunched.files.fileExists(storedFilename: storedFilename))
        #expect(try relaunched.context.fetchCount(FetchDescriptor<Course>()) == 5)
    }
}
