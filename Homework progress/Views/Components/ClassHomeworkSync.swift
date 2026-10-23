//
//  ClassHomeworkSync.swift
//  Homework progress
//

import SwiftUI
import SwiftData
import ClassroomUI
import StudyData
import StudyDomain

extension View {
    /// Runs "Subscribe to class" whenever it's switched on and the class catalog, the chosen
    /// courses or the user's class membership change, and keeps progress in step (ClassProgressSync).
    /// Attach once, near the root.
    func classHomeworkSync() -> some View {
        modifier(ClassHomeworkSync())
    }
}

private struct ClassHomeworkSync: ViewModifier {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @AppStorage("weekStartsOn") private var weekStartsOn = 1

    /// Changes whenever something the import depends on changes; `nil` = nothing to do.
    private var trigger: [String]? {
        let classroom = services.classroom
        // Wait for this launch's first iCloud import, so lessons the other device already
        // copied (or deleted) are seen before anything is added here.
        guard services.sync.hasCaughtUp, let homework = classroom.homework, homework.isOn,
              let student = classroom.student, student.hasLoadedCache else { return nil }
        let catalog = student.catalog
        return ["enrolled:\(student.identity?.isEnrolled == true)"]
            + homework.skippedCourses.map { "skip:\($0)" }.sorted()
            + catalog.lessons.map { "\($0.id):\($0.status.rawValue):\($0.updatedAt.timeIntervalSince1970)" }
            + catalog.attachments.map { "\($0.id):\($0.version)" }
    }

    func body(content: Content) -> some View {
        content.task(id: trigger) {
            guard trigger != nil, let homework = services.classroom.homework,
                  let student = services.classroom.student else { return }
            let attachments = services.classroom.attachments
            var importer = ClassHomeworkImporter(
                store: services.store(context),
                planner: WeekPlanner(firstWeekday: weekStartsOn),
                ledger: ClassImportLedger(settings: homework.settings),
                skippedCourses: homework.skippedCourses,
                fetchFile: { file in
                    guard let attachments else { throw AttachmentError.notAuthorized }
                    return try await attachments.file(for: file)
                })
            let report = await importer.run(catalog: student.catalog)
            homework.status = report.message
            scheduleProgressSync()
        }
        // Progress both ways: when the class side changes, and when homework is saved.
        .onChange(of: services.classroom.student?.progress) { scheduleProgressSync() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleProgressSync() }
    }

    private func scheduleProgressSync() {
        let services = services
        let context = context
        services.classProgressSync.schedule {
            guard let homework = services.classroom.homework, homework.isOn,
                  let student = services.classroom.student, student.hasLoadedCache else { return nil }
            return ClassProgressSync(store: services.store(context), student: student, settings: homework.settings,
                                     skippedCourses: homework.skippedCourses)
        }
    }
}
