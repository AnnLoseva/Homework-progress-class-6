//
//  AppRouter.swift
//  Homework progress
//

import SwiftUI
import SwiftData

/// Navigation state shared by the iPhone stack and the iPad split view.
@Observable
final class AppRouter {
    enum SidebarItem: Hashable {
        case week(AcademicWeek)
        case course(Course)
        case archive
        case settings
    }

    enum Route: Hashable {
        case course(Course)
        case assignment(HomeworkAssignment)
        case courseSettings(Course)
        case archive
        case settings
    }

    enum Sheet: Identifiable {
        case newWeek
        case editWeek(AcademicWeek)
        case newAssignment(course: Course?, week: AcademicWeek)
        case editAssignment(HomeworkAssignment)
        case importSharedPDF(URL)

        var id: String {
            switch self {
            case .newWeek: "newWeek"
            case .editWeek(let w): "editWeek-\(w.id)"
            case .newAssignment(let c, let w): "newAssignment-\(c?.id.uuidString ?? "any")-\(w.id)"
            case .editAssignment(let a): "editAssignment-\(a.id)"
            case .importSharedPDF(let url): "import-\(url.absoluteString)"
            }
        }
    }

    private static let selectedWeekKey = "selectedWeekID"

    var selectedWeekID: UUID? {
        didSet { UserDefaults.standard.set(selectedWeekID?.uuidString, forKey: Self.selectedWeekKey) }
    }

    /// iPad sidebar selection.
    var sidebar: SidebarItem?
    var path = NavigationPath()
    var activeSheet: Sheet?

    /// iPad: the assignment shown in the side inspector, when the window is wide enough.
    var inspectedAssignment: HomeworkAssignment?
    var usesInspector = false

    init() {
        selectedWeekID = UserDefaults.standard.string(forKey: Self.selectedWeekKey).flatMap(UUID.init)
    }

    func open(_ assignment: HomeworkAssignment) {
        if usesInspector {
            inspectedAssignment = assignment
        } else {
            path.append(Route.assignment(assignment))
        }
    }

    /// Opens the full-width workspace (PDF beside the counters on iPad).
    func openWorkspace(_ assignment: HomeworkAssignment) {
        inspectedAssignment = nil
        path.append(Route.assignment(assignment))
    }

    func open(_ course: Course) {
        path.append(Route.course(course))
    }

    func push(_ route: Route) {
        path.append(route)
    }

    func select(_ week: AcademicWeek) {
        selectedWeekID = week.id
        if sidebar != nil { sidebar = .week(week) }
    }

    /// Called before a model is deleted so no screen keeps showing it.
    func forget(_ assignment: HomeworkAssignment) {
        if inspectedAssignment?.id == assignment.id { inspectedAssignment = nil }
    }

    func resetPath() {
        path = NavigationPath()
    }
}
