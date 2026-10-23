//
//  ClassProgressSync.swift
//  Homework progress
//
//  The progress half of "Subscribe to class". ClassHomeworkImporter copies the lessons into
//  the homework weeks; this keeps each copy's progress and its class lesson's progress in
//  step, both ways, so ticking an exercise in Homework also counts in Class and vice versa.
//
//  • Linked = a homework assignment with the lesson's id: a copy made by the importer, or the
//    administrator's own homework the lesson was published from.
//  • Whichever side changed since the last sync wins; if both changed, the newer change wins.
//    "Completed" always counts every exercise, so slightly different totals can't make the
//    two sides flip each other back and forth.
//  • Class progress stays private to the student (RLS), exactly as before. Notes aren't synced.
//  • Optional lessons of subscribed courses are also followed in Class (once each, on any of
//    the user's devices), so they count in the Class workload like the required ones. A lesson
//    unfollowed later in Class stays unfollowed.
//

import ClassroomUI
import Foundation
import SwiftData
import StudyData
import StudyDomain

@MainActor
struct ClassProgressSync {
    struct Report: Equatable {
        var sentToClass = 0
        var takenFromClass = 0
        var optionalLessonsFollowed = 0
    }

    let store: HomeworkStore
    let student: StudentStore
    let settings: SyncedSettings
    var skippedCourses: Set<UUID> = []

    @discardableResult
    func run() async -> Report {
        var report = Report()
        let lessons = student.catalog.lessons.filter { $0.isActive(at: student.currentDate) }
        guard !lessons.isEmpty else { return report }
        var state = State.load(from: settings, userID: student.userID)
        let original = state

        for lesson in lessons where lesson.category == .optional && !skippedCourses.contains(lesson.courseID)
            && !state.followed.contains(lesson.id) {
            if student.subscriptions[lesson.id]?.isActive != true {
                await student.setSubscribed(true, lessonID: lesson.id)
                report.optionalLessonsFollowed += 1
            }
            state.followed.insert(lesson.id)
        }

        for lesson in lessons {
            guard let assignment = assignment(id: lesson.id) else { continue }
            state.synced[lesson.id] = await sync(assignment, with: lesson, last: state.synced[lesson.id], report: &report)
        }

        // Saving with nothing to save would only trigger another pass.
        if store.context.hasChanges { store.save() }
        if state != original { state.save(to: settings, userID: student.userID) }
        return report
    }

    /// Returns the progress both sides agree on afterwards.
    private func sync(_ assignment: HomeworkAssignment, with lesson: Lesson, last: SyncedProgress?,
                      report: inout Report) async -> SyncedProgress {
        let homework = Self.homeworkProgress(assignment, lesson: lesson)
        let remote = student.progress[lesson.id]
        let classSide = Self.classProgress(remote ?? .empty(for: lesson.id), lesson: lesson)
        guard homework != classSide else { return homework }

        let homeworkChanged = homework != last
        let classChanged = remote != nil && classSide != last
        let sendToClass = switch (homeworkChanged, classChanged) {
        case (true, false): true
        case (false, true): false
        default: assignment.updatedAt >= (remote?.clientModifiedAt ?? .distantPast)
        }

        if sendToClass {
            if lesson.exerciseCount > 0, student.progress(for: lesson.id).completedExercises != homework.completed {
                await student.setCompletedExercises(homework.completed, lessonID: lesson.id)
            }
            if student.progress(for: lesson.id).status != homework.status {
                await student.setStatus(homework.status, lessonID: lesson.id)
            }
            report.sentToClass += 1
        } else {
            report.takenFromClass += 1
        }
        // The class may round a change (e.g. "completed" fills the count): mirror the result.
        let agreed = Self.classProgress(student.progress(for: lesson.id), lesson: lesson)
        apply(agreed, to: assignment, lesson: lesson)
        return agreed
    }

    private func apply(_ progress: SyncedProgress, to assignment: HomeworkAssignment, lesson: Lesson) {
        guard Self.homeworkProgress(assignment, lesson: lesson) != progress else { return }
        var state = assignment.exerciseState
        if lesson.exerciseCount > 0 { state = state.settingCompleted(progress.completed) }
        switch progress.status {
        case .completed:
            state = state.markedCompleted()
        case .inProgress:
            if state.status != .inProgress { state = state.settingStatus(.inProgress) }
        case .notStarted:
            if state.status == .completed || state.status == .inProgress { state = state.settingStatus(.notStarted) }
        }
        assignment.apply(state)
    }

    private func assignment(id: UUID) -> HomeworkAssignment? {
        var descriptor = FetchDescriptor<HomeworkAssignment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? store.context.fetch(descriptor).first
    }

    // MARK: Both sides in the class's terms

    static func homeworkProgress(_ assignment: HomeworkAssignment, lesson: Lesson) -> SyncedProgress {
        let total = lesson.exerciseCount
        let completed = total > 0 ? min(max(assignment.completedExercises, 0), total) : 0
        let status: ProgressStatus = switch assignment.status {
        case .completed: .completed
        case .inProgress: .inProgress
        case .notStarted, .notAssigned, .postponed: completed > 0 ? .inProgress : .notStarted
        }
        return SyncedProgress(completed: status == .completed ? total : completed, status: status)
    }

    static func classProgress(_ progress: LessonProgress, lesson: Lesson) -> SyncedProgress {
        let total = lesson.exerciseCount
        let completed = progress.status == .completed ? total : (total > 0 ? min(progress.completedExercises, total) : 0)
        return SyncedProgress(completed: completed, status: progress.status)
    }
}

struct SyncedProgress: Codable, Equatable {
    var completed: Int
    var status: ProgressStatus
}

extension ClassProgressSync {
    /// What was last synced, per user, on this device; the optional lessons already followed
    /// are shared with the user's other devices.
    struct State: Codable, Equatable {
        var synced: [UUID: SyncedProgress] = [:]
        var followed: Set<UUID> = []

        static func key(for userID: UUID) -> String { "classProgressSync.\(userID.uuidString.lowercased())" }
        static func followedKey(for userID: UUID) -> String { "classFollowed.\(userID.uuidString.lowercased())" }

        static func load(from settings: SyncedSettings, userID: UUID) -> State {
            var state = settings.local.data(forKey: key(for: userID))
                .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
            state.followed.formUnion(settings.growingIDs(forKey: followedKey(for: userID)))
            return state
        }

        func save(to settings: SyncedSettings, userID: UUID) {
            if let data = try? JSONEncoder().encode(self) { settings.local.set(data, forKey: Self.key(for: userID)) }
            settings.add(followed, forKey: Self.followedKey(for: userID))
        }
    }
}

/// Runs a pass a moment after something changes, one pass at a time.
@MainActor
final class ClassSyncCoordinator {
    private var pending: Task<Void, Never>?
    private var isRunning = false
    private var runAgain = false

    func schedule(_ makeSync: @escaping @MainActor () -> ClassProgressSync?) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.run(makeSync)
        }
    }

    private func run(_ makeSync: @escaping @MainActor () -> ClassProgressSync?) async {
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
