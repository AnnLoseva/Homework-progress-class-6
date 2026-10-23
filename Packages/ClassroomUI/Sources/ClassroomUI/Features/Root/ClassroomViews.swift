import SwiftUI
import StudyData
import StudyDomain

// The public entry points of the Class area. The host app owns the tab bar and the iPad
// sidebar; these views fill them. Everything below them stays internal to this module.

/// A place in the Class area, used by the host app's tab and sidebar.
public enum ClassroomSection: String, Hashable, CaseIterable, Identifiable, Sendable {
    case home
    case lessons
    case required
    case optional
    case myLessons
    case manage
    case account

    public var id: String { rawValue }

    public var title: LocalizedStringKey {
        switch self {
        case .home: "Class Home"
        case .lessons: "All lessons"
        case .required: "Required"
        case .optional: "Optional"
        case .myLessons: "My Lessons"
        case .manage: "Manage lessons"
        case .account: "Class Account"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: "graduationcap"
        case .lessons: "books.vertical"
        case .required: LessonCategory.required.symbol
        case .optional: LessonCategory.optional.symbol
        case .myLessons: "checklist"
        case .manage: "square.and.pencil"
        case .account: "person.crop.circle"
        }
    }

    /// The sections this user can open. "Manage" needs the server's administrator role.
    @MainActor
    public static func visible(in environment: ClassroomEnvironment) -> [ClassroomSection] {
        allCases.filter { $0 != .manage || environment.admin != nil }
    }
}

extension View {
    /// Restores the class session, keeps the per-user stores in step with it, and syncs when
    /// the app comes back to the foreground. Attach once, near the root.
    public func classroomLifecycle(_ environment: ClassroomEnvironment) -> some View {
        modifier(ClassroomLifecycle(environment: environment))
    }
}

private struct ClassroomLifecycle: ViewModifier {
    let environment: ClassroomEnvironment
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(environment)
            // The stores go here, above the host app's NavigationSplitView: on iPad SwiftUI
            // hoists `.searchable` of a pushed screen to the split view, and it would not see
            // stores injected only inside the detail column.
            .environment(environment.student)
            .environment(environment.admin)
            .task { await environment.start() }
            .onChange(of: environment.session.currentUserID) {
                Task { await environment.sessionChanged() }
            }
            .onChange(of: environment.student?.identity) {
                environment.refreshAdminAccess()
            }
            .onChange(of: scenePhase) { _, phase in
                // Pull other devices' changes whenever the app comes back to the foreground.
                if phase == .active { Task { await environment.student?.sync() } }
            }
    }
}

/// iPhone: the whole Class area in one tab, with a menu between its sections.
public struct ClassroomCompactView: View {
    @Environment(ClassroomEnvironment.self) private var environment
    /// Scene storage, so the chosen section survives SwiftUI rebuilding this view.
    @SceneStorage("classroom.compactSection") private var section: ClassroomSection = .home

    public init() {}

    public var body: some View {
        ClassroomGate {
            NavigationStack {
                ClassroomSectionView(section: section)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                Picker("Section", selection: $section) {
                                    ForEach(compactSections) { item in
                                        Label(item.title, systemImage: item.systemImage).tag(item)
                                    }
                                }
                            } label: {
                                Label("Sections", systemImage: "list.bullet")
                            }
                            .accessibilityIdentifier("classSectionMenu")
                        }
                    }
            }
            .id(section)
        }
        .woodChrome()
    }

    /// Required/optional are filters inside "All lessons" on iPhone.
    private var compactSections: [ClassroomSection] {
        ClassroomSection.visible(in: environment).filter { $0 != .required && $0 != .optional }
    }
}

/// iPad: the detail column for a section chosen in the host app's sidebar.
public struct ClassroomDetailView: View {
    let section: ClassroomSection

    public init(section: ClassroomSection) {
        self.section = section
    }

    public var body: some View {
        ClassroomGate {
            NavigationStack {
                ClassroomSectionView(section: section)
            }
            .id(section)
        }
        .woodChrome()
    }
}

/// Shows sign-in until there is a session, then the content with the student's store.
private struct ClassroomGate<Content: View>: View {
    @Environment(ClassroomEnvironment.self) private var environment
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch environment.session.state {
        case .restoring:
            ZStack {
                ForestBackdrop()
                ProgressView("Opening your study nook…").font(.woodBody)
            }
        case .signedOut:
            SignInView()
        case .signedIn:
            if let student = environment.student {
                content().environment(student)
            } else {
                ZStack { ForestBackdrop(); ProgressView() }
            }
        }
    }
}

private struct ClassroomSectionView: View {
    @Environment(ClassroomEnvironment.self) private var environment
    let section: ClassroomSection

    var body: some View {
        switch section {
        case .home: HomeView()
        case .lessons: CatalogView(preset: .all)
        case .required: CatalogView(preset: CatalogPreset(category: .required))
        case .optional: CatalogView(preset: CatalogPreset(category: .optional))
        case .myLessons: MyLessonsView()
        case .account: SettingsView()
        case .manage:
            if let admin = environment.admin { AdminHomeView().environment(admin) } else { HomeView() }
        }
    }
}

/// A catalog opened with a filter already applied.
struct CatalogPreset: Hashable {
    var category: LessonCategory?
    var courseID: UUID?
    var subscription: LessonQuery.SubscriptionFilter = .all

    static let all = CatalogPreset()
}
