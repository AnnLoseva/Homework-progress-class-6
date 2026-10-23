//
//  RootView.swift
//  Homework progress
//

import SwiftUI
import SwiftData
import ClassroomUI
import StudyData
import StudyDomain

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Query(sort: \AcademicWeek.startDate) private var weeks: [AcademicWeek]
    @AppStorage("weekStartsOn") private var weekStartsOn = 1

    var body: some View {
        @Bindable var router = router
        GeometryReader { proxy in
            Group {
                if sizeClass == .regular {
                    SplitRootView(selectedWeek: selectedWeek)
                } else {
                    CompactRootView(selectedWeek: selectedWeek)
                }
            }
            .onAppear { updateLayout(width: proxy.size.width) }
            .onChange(of: proxy.size.width) { _, width in updateLayout(width: width) }
            .onChange(of: sizeClass) { _, _ in updateLayout(width: proxy.size.width) }
        }
        .onAppear(perform: selectCurrentWeekOnLaunch)
        .sheet(item: $router.activeSheet) { sheet in
            sheetContent(sheet)
                .goblinChrome()
        }
        .onOpenURL { url in
            // PDFs shared to this app ("Open in Homework Progress") arrive here.
            if url.isFileURL { router.activeSheet = .importSharedPDF(url) }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .modifier(ClassHomeworkSyncTrigger())
        .classHomeworkSync()
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { rescheduleReminders() }
        }
    }

    private var planner: WeekPlanner { WeekPlanner(firstWeekday: weekStartsOn) }

    private var selectedWeek: AcademicWeek? {
        if let id = router.selectedWeekID, let match = weeks.first(where: { $0.id == id }) { return match }
        return planner.preferredWeek(in: weeks, start: \.startDate, end: \.endDate)
    }

    private func updateLayout(width: CGFloat) {
        let wide = sizeClass == .regular && width >= 900
        router.usesInspector = wide
        if !wide { router.inspectedAssignment = nil }
    }

    /// The dashboard is about *this* week: on launch, jump to the week containing today.
    private func selectCurrentWeekOnLaunch() {
        if let current = weeks.first(where: { planner.contains(.now, start: $0.startDate, end: $0.endDate) }) {
            router.selectedWeekID = current.id
        } else if let preferred = selectedWeek {
            router.selectedWeekID = preferred.id
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppRouter.Sheet) -> some View {
        switch sheet {
        case .newWeek:
            WeekEditorView(mode: .create)
        case .editWeek(let week):
            WeekEditorView(mode: .edit(week))
        case .newAssignment(let course, let week):
            AssignmentEditorView(mode: .create(course: course, week: week))
        case .editAssignment(let assignment):
            AssignmentEditorView(mode: .edit(assignment))
        case .importSharedPDF(let url):
            if let week = selectedWeek {
                AssignmentEditorView(mode: .create(course: nil, week: week), incomingPDF: url)
            } else {
                ContentUnavailableView("Create a week first",
                                       systemImage: "calendar.badge.plus",
                                       description: Text("Shared PDFs are added to an assignment in the selected week."))
                    .presentationDetents([.medium])
            }
        }
    }

    private func rescheduleReminders() {
        let assignments = (try? context.fetch(FetchDescriptor<HomeworkAssignment>())) ?? []
        let items = assignments.compactMap { a -> ReminderScheduler.DeadlineItem? in
            guard !a.isCompleted, let due = a.dueDate else { return nil }
            return .init(id: a.id, title: a.title, courseName: a.course?.name ?? "", dueDate: due)
        }
        Task { await ReminderScheduler.reschedule(deadlines: items) }
    }
}

// MARK: - iPhone / narrow

struct CompactRootView: View {
    enum Tab: String {
        case homework
        case classroom
    }

    @Environment(AppRouter.self) private var router
    /// Stored outside the view tree: without an explicit selection, a TabView that SwiftUI
    /// rebuilds (for example after Class data changes) falls back to its first tab, and the
    /// user was thrown from Class back to Homework.
    @SceneStorage("compactRoot.tab") private var tab = Tab.homework
    var selectedWeek: AcademicWeek?

    var body: some View {
        @Bindable var router = router
        TabView(selection: $tab) {
            NavigationStack(path: $router.path) {
                DashboardView(week: selectedWeek)
                    .navigationDestination(for: AppRouter.Route.self) { route in
                        RouteDestination(route: route, selectedWeek: selectedWeek)
                    }
            }
            .tabItem { Label("Homework", systemImage: "book.closed") }
            .tag(Tab.homework)

            ClassroomCompactView()
                .tabItem { Label("Class", systemImage: "graduationcap") }
                .tag(Tab.classroom)
        }
    }
}

struct RouteDestination: View {
    let route: AppRouter.Route
    let selectedWeek: AcademicWeek?

    var body: some View {
        switch route {
        case .course(let course):
            CourseDetailView(course: course, week: selectedWeek)
        case .assignment(let assignment):
            AssignmentDetailView(assignment: assignment)
        case .courseSettings(let course):
            CourseSettingsView(course: course)
        case .archive:
            WeekArchiveView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - iPad

struct SplitRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Query(sort: \AcademicWeek.startDate, order: .reverse) private var weeks: [AcademicWeek]
    @Query(sort: \Course.sortOrder) private var courses: [Course]
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    var selectedWeek: AcademicWeek?

    var body: some View {
        @Bindable var router = router
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $router.sidebar) {
                Section("Weeks") {
                    ForEach(weeks) { week in
                        NavigationLink(value: AppRouter.SidebarItem.week(week)) {
                            SidebarWeekRow(week: week, isSelected: week.id == selectedWeek?.id)
                        }
                    }
                    Button {
                        router.activeSheet = .newWeek
                    } label: {
                        Label("New Week", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                }
                Section("Courses") {
                    ForEach(courses) { course in
                        NavigationLink(value: AppRouter.SidebarItem.course(course)) {
                            HStack(spacing: 10) {
                                CourseIconView(iconName: course.iconName, palette: course.palette, size: 34)
                                Text(course.name).lineLimit(2)
                            }
                        }
                    }
                }
                Section("Class") {
                    ForEach(ClassroomSection.visible(in: services.classroom)) { section in
                        NavigationLink(value: AppRouter.SidebarItem.classroom(section)) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
                }
                Section {
                    NavigationLink(value: AppRouter.SidebarItem.archive) {
                        Label("Archive", systemImage: "archivebox")
                    }
                    NavigationLink(value: AppRouter.SidebarItem.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .parchmentList()
            .navigationTitle("Homework")
        } detail: {
            if case .classroom(let section) = router.sidebar {
                // The Class area has its own navigation stack and data.
                ClassroomDetailView(section: section)
            } else {
                homeworkDetail
            }
        }
        .onAppear {
            if router.sidebar == nil, let selectedWeek { router.sidebar = .week(selectedWeek) }
        }
        .onChange(of: router.sidebar) { _, item in
            router.resetPath()
            if case .week(let week) = item { router.selectedWeekID = week.id }
            if case .classroom = item { router.inspectedAssignment = nil }
        }
    }

    private var homeworkDetail: some View {
        @Bindable var router = router
        return HStack(spacing: 0) {
            NavigationStack(path: $router.path) {
                splitContent
                    .navigationDestination(for: AppRouter.Route.self) { route in
                        RouteDestination(route: route, selectedWeek: selectedWeek)
                    }
            }
            // Side panel for the selected assignment, so browsing and inspecting don't
            // require navigating back and forth.
            if let assignment = router.inspectedAssignment, assignment.modelContext != nil {
                Rectangle().fill(AppTheme.border).frame(width: 1).ignoresSafeArea()
                NavigationStack {
                    AssignmentDetailView(assignment: assignment, isInspector: true)
                }
                .id(assignment.id)
                .frame(width: 400)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: router.inspectedAssignment?.id)
    }

    @ViewBuilder
    private var splitContent: some View {
        switch router.sidebar {
        case .course(let course):
            CourseDetailView(course: course, week: selectedWeek)
        case .archive:
            WeekArchiveView()
        case .settings:
            SettingsView()
        case .week, .classroom, .none:
            DashboardView(week: selectedWeek)
        }
    }
}

struct SidebarWeekRow: View {
    let week: AcademicWeek
    let isSelected: Bool

    var body: some View {
        let summary = week.summary
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(week.title).font(.lora(16, weight: isSelected ? .semibold : .regular))
                Spacer()
                if let percent = summary.percent {
                    Text("\(percent)%").font(.lora(12)).foregroundStyle(.secondary)
                }
            }
            Text(week.dateRangeText).font(.lora(12)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        if let message = services.toast {
            HStack(spacing: 12) {
                Illustration(name: "MushroomHappy", size: 40)
                Text(message)
                    .font(.lora(15))
                    .foregroundStyle(AppTheme.ink)
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .parchmentSurface(cornerRadius: 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { services.toast = nil }
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(6))
                    withAnimation { services.toast = nil }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Starts "Follow the whole class" passes when the class catalog or progress changes, when
/// homework is saved, and when the switch is turned on.
private struct ClassHomeworkSyncTrigger: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    @AppStorage("weekStartsOn") private var weekStartsOn = 1

    func body(content: Content) -> some View {
        let student = services.classroom.student
        content
            .onChange(of: student?.catalog, initial: true) { schedule() }
            .onChange(of: student?.progress) { schedule() }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in schedule() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in schedule() }
    }

    private func schedule() {
        let services = services
        let context = context
        let planner = WeekPlanner(firstWeekday: weekStartsOn)
        services.classSync.schedule {
            guard let student = services.classroom.student,
                  UserDefaults.standard.bool(forKey: ClassroomPreferences.followWholeClassKey(for: student.userID))
            else { return nil }
            let attachments = services.classroom.attachments
            return ClassHomeworkSync(
                store: services.store(context), student: student,
                download: attachments.map { repository in { try await repository.file(for: $0) } },
                defaults: .standard, planner: planner)
        }
    }
}
