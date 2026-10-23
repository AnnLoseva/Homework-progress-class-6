//
//  NoteAppAndBackupTests.swift
//  Homework progressTests
//

import Foundation
import SwiftData
import Testing
@testable import Homework_progress

@Suite("Notability / Goodnotes handoff")
struct NoteAppTests {
    @Test func linkValidation() {
        #expect(NoteAppIntegration.validatedLink(from: "https://notability.com/n/abc") != nil)
        #expect(NoteAppIntegration.validatedLink(from: "  notability://open  ") != nil)
        #expect(NoteAppIntegration.validatedLink(from: "goodnotes://open?id=1") != nil)
        #expect(NoteAppIntegration.validatedLink(from: "javascript:alert(1)") == nil)
        #expect(NoteAppIntegration.validatedLink(from: "file:///etc/passwd") == nil)
        #expect(NoteAppIntegration.validatedLink(from: "moodlemobile://x") == nil)
        #expect(NoteAppIntegration.validatedLink(from: "Discrete Math") == nil)
        #expect(NoteAppIntegration.validatedLink(from: "https://") == nil)
        #expect(NoteAppIntegration.validatedLink(from: nil) == nil)
    }

    @Test func noLinkFallsBackToManualWithoutOpeningAnything() async {
        var opened: [URL] = []
        let outcome = await NoteAppIntegration.openNotebook(name: "Discrete Math", link: nil) { url in
            opened.append(url)
            return true
        }
        #expect(outcome == .manualOnly(notebookName: "Discrete Math"))
        #expect(opened.isEmpty)
    }

    @Test func blankNameIsTreatedAsMissing() async {
        let outcome = await NoteAppIntegration.openNotebook(name: "  ", link: nil) { _ in true }
        #expect(outcome == .manualOnly(notebookName: nil))
    }

    @Test func savedLinkIsHandedToIOS() async {
        let link = URL(string: "https://notability.com/n/abc")!
        let accepted = await NoteAppIntegration.openNotebook(name: "X", link: link) { _ in true }
        #expect(accepted == .linkHandedOff(link))
        let refused = await NoteAppIntegration.openNotebook(name: "X", link: link) { _ in false }
        #expect(refused == .linkFailed(link, notebookName: "X"))
    }

    @Test func bothNoteAppsAreRecognisedInTheShareSheet() {
        #expect(NoteAppIntegration.interpretShare(activityType: "com.gingerlabs.Notability.ShareExtension", completed: true) == .sentToNoteApp(.notability))
        #expect(NoteAppIntegration.interpretShare(activityType: "com.goodnotesapp.x.GoodNotesShareExtension", completed: true) == .sentToNoteApp(.goodnotes))
        #expect(NoteAppIntegration.interpretShare(activityType: "com.apple.UIKit.activity.RemoteOpenInApplication-ByCopy", completed: true) == .openedInApp)
        #expect(NoteAppIntegration.interpretShare(activityType: "com.apple.UIKit.activity.AirDrop", completed: true) == .sentElsewhere)
        #expect(NoteAppIntegration.interpretShare(activityType: "com.goodnotesapp.x.GoodNotesShareExtension", completed: false) == .cancelled)
    }

    @Test func shareOutcomesNeverClaimImportSucceeded() {
        #expect(NoteAppIntegration.message(for: .cancelled, notebookName: nil, preferred: .goodnotes) == nil)
        let outcomes: [NoteAppIntegration.HandoffOutcome] = [.sentToNoteApp(.notability), .sentToNoteApp(.goodnotes), .openedInApp, .sentElsewhere]
        for outcome in outcomes {
            let message = NoteAppIntegration.message(for: outcome, notebookName: "מתמטיקה בדידה", preferred: .goodnotes) ?? ""
            #expect(!message.lowercased().contains("imported"))
            #expect(message.contains("unchanged"))
        }
        let toGoodnotes = NoteAppIntegration.message(for: .sentToNoteApp(.goodnotes), notebookName: nil, preferred: .notability) ?? ""
        #expect(toGoodnotes.contains("Sent to Goodnotes"), "names the app iOS reported, not the preference")
        #expect(toGoodnotes.contains("Finish the import"))
        let handedOff = NoteAppIntegration.message(for: .openedInApp, notebookName: nil, preferred: .goodnotes) ?? ""
        #expect(handedOff.contains("If you chose Goodnotes"))
    }
}

@Suite("Backup")
@MainActor
struct BackupTests {
    @Test func roundTripIncludesDataAndPDFs() throws {
        let source = try TestEnvironment()
        let courses = try source.seed()
        source.store.setNotebook(for: courses[0], name: "Linear Algebra", link: "https://notability.com/n/xyz")
        let week = source.store.createWeek(title: "Week 5", number: 5, start: date(2026, 10, 18), end: date(2026, 10, 24))
        let assignment = source.store.createAssignment(title: "HW", course: courses[0], week: week, totalExercises: 8)
        assignment.apply(assignment.exerciseState.settingCompleted(3))
        let pdfURL = try source.makePDF(named: "Sheet.pdf", pages: 2)
        source.store.attach(try source.files.importPDF(from: pdfURL), to: assignment)

        let data = try BackupService(context: source.context, files: source.files).exportData()
        let document = try BackupService.decoder().decode(BackupDocument.self, from: data)
        #expect(document.formatVersion == 1)
        #expect(document.format == "hit-homework-backup")

        let target = try TestEnvironment()
        let report = try BackupService(context: target.context, files: target.files).restore(from: data)
        #expect(report.coursesAdded == 5)
        #expect(report.weeksAdded == 1)
        #expect(report.assignmentsAdded == 1)
        #expect(report.attachmentsAdded == 1)

        let restored = try #require(try target.context.fetch(FetchDescriptor<HomeworkAssignment>()).first)
        #expect(restored.completedExercises == 3)
        #expect(restored.course?.name == "אלגברה ליניארית וייצוג נתונים - חלק א")
        #expect(restored.course?.courseURLString == "https://md.hit.ac.il/course/view.php?id=27796")
        #expect(restored.course?.notebook?.notebookName == "Linear Algebra")
        let file = try #require(restored.attachmentList.first)
        #expect(target.files.fileExists(storedFilename: file.storedFilename))

        // Restoring again changes nothing.
        let second = try BackupService(context: target.context, files: target.files).restore(from: data)
        #expect(second.assignmentsAdded == 0)
        #expect(second.skippedExisting == 5 + 1 + 1 + 1)
        #expect(try target.context.fetchCount(FetchDescriptor<HomeworkAssignment>()) == 1)
    }

    @Test func rejectsForeignAndNewerFiles() throws {
        let env = try TestEnvironment()
        let service = BackupService(context: env.context, files: env.files)
        var document = BackupDocument(exportedAt: .now, appVersion: "1", courses: [], weeks: [], assignments: [], attachments: [])
        document.formatVersion = 99
        #expect(throws: BackupService.BackupError.self) {
            try service.restore(from: BackupService.encoder().encode(document))
        }
        document.formatVersion = 1
        document.format = "something-else"
        #expect(throws: BackupService.BackupError.self) {
            try service.restore(from: BackupService.encoder().encode(document))
        }
    }
}

@Suite("Text handling")
struct TextTests {
    @Test func filenameDeduplication() {
        #expect(FilenameDeduplicator.unique("A.pdf", existing: []) == "A.pdf")
        #expect(FilenameDeduplicator.unique("A.pdf", existing: ["a.PDF", "A (2).pdf"]) == "A (3).pdf")
        #expect(FilenameDeduplicator.sanitized("../evil/name") == "..-evil-name.pdf")
        #expect(FilenameDeduplicator.sanitized("   ") == "Homework.pdf")
        #expect(FilenameDeduplicator.sanitized("תרגיל 3.pdf") == "תרגיל 3.pdf")
    }

    @Test func bidiIsolation() {
        let name = "מבוא לאנליזה"
        #expect(BidiText.isolate(name) == "\u{2068}מבוא לאנליזה\u{2069}")
        #expect(BidiText.isRightToLeft(name))
        #expect(!BidiText.isRightToLeft("Week 5"))
        #expect(BidiText.isRightToLeft("5 מתמטיקה"))
    }
}
