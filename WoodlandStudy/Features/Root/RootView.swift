import SwiftUI
import StudyData
import StudyDomain

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

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
                MainShell()
                    .environment(student)
            } else {
                ZStack { ForestBackdrop(); ProgressView() }
            }
        }
    }
}

/// Top-level destinations, shared by the iPhone tab bar and the iPad sidebar.
enum Destination: Hashable {
    case home
    case catalog(CatalogPreset)
    case myLessons
    case settings
    case admin
}

/// A catalog opened from the iPad sidebar with a filter already applied.
struct CatalogPreset: Hashable {
    var category: LessonCategory?
    var courseID: UUID?
    var subscription: LessonQuery.SubscriptionFilter = .all

    static let all = CatalogPreset()
}

struct MainShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            SplitShell()
        } else {
            TabShell()
        }
    }
}

/// iPhone: a tab bar.
private struct TabShell: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: Destination = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Destination.home)
            NavigationStack { CatalogView(preset: .all) }
                .tabItem { Label("Lessons", systemImage: "books.vertical") }
                .tag(Destination.catalog(.all))
            NavigationStack { MyLessonsView() }
                .tabItem { Label("My Lessons", systemImage: "checklist") }
                .tag(Destination.myLessons)
            if let admin = environment.admin {
                NavigationStack { AdminHomeView().environment(admin) }
                    .tabItem { Label("Manage", systemImage: "square.and.pencil") }
                    .tag(Destination.admin)
            }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Destination.settings)
        }
    }
}

/// iPad: sidebar with courses, categories and subscriptions; detail in a larger area.
private struct SplitShell: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(StudentStore.self) private var store
    @State private var selection: Destination? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    Label("Home", systemImage: "house").tag(Destination.home)
                    Label("All lessons", systemImage: "books.vertical").tag(Destination.catalog(.all))
                    Label("My Lessons", systemImage: "checklist").tag(Destination.myLessons)
                }
                Section("Categories") {
                    Label { Text(LessonCategory.required.title) } icon: { Image(systemName: LessonCategory.required.symbol).foregroundStyle(LessonCategory.required.color) }
                        .tag(Destination.catalog(CatalogPreset(category: .required)))
                    Label { Text(LessonCategory.optional.title) } icon: { Image(systemName: LessonCategory.optional.symbol).foregroundStyle(LessonCategory.optional.color) }
                        .tag(Destination.catalog(CatalogPreset(category: .optional)))
                    Label("In my workload", systemImage: "tray.full")
                        .tag(Destination.catalog(CatalogPreset(subscription: .inMyWorkload)))
                }
                Section("Courses") {
                    ForEach(store.catalog.courses.filter { !$0.isArchived }) { course in
                        Label { Text(course.title) } icon: { CourseIcon(course: course, size: 26) }
                            .tag(Destination.catalog(CatalogPreset(courseID: course.id)))
                    }
                }
                Section {
                    if environment.admin != nil {
                        Label("Manage lessons", systemImage: "square.and.pencil").tag(Destination.admin)
                    }
                    Label("Settings", systemImage: "gearshape").tag(Destination.settings)
                }
            }
            .navigationTitle("Woodland Study")
            .woodList()
        } detail: {
            NavigationStack {
                switch selection ?? .home {
                case .home: HomeView()
                case .catalog(let preset): CatalogView(preset: preset).id(preset)
                case .myLessons: MyLessonsView()
                case .settings: SettingsView()
                case .admin:
                    if let admin = environment.admin { AdminHomeView().environment(admin) } else { HomeView() }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
