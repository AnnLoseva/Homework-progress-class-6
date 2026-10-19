//
//  DashboardView.swift
//  Homework progress
//

import SwiftUI
import SwiftData

/// Answers: how much is done this week, how much remains, and what to work on next.
struct DashboardView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \AcademicWeek.startDate) private var weeks: [AcademicWeek]
    @Query(sort: \Course.sortOrder) private var courses: [Course]
    @AppStorage("weekStartsOn") private var weekStartsOn = 1
    let week: AcademicWeek?

    var body: some View {
        Group {
            if let week {
                content(for: week)
            } else {
                NoWeeksView()
            }
        }
        .background { ForestBackdrop() }
        .navigationTitle(week?.title ?? String(localized: "Homework"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    private func content(for week: AcademicWeek) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WeekNavigationHeader(week: week, weeks: weeks, planner: WeekPlanner(firstWeekday: weekStartsOn))
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 20) {
                            WeeklyOverviewCard(week: week)
                            CourseOverviewSection(week: week, courses: courses)
                        }
                        .frame(minWidth: 360, maxWidth: .infinity)
                        RemainingWorkSection(week: week)
                            .frame(minWidth: 360, maxWidth: .infinity)
                    }
                    .frame(minWidth: 760)
                    VStack(alignment: .leading, spacing: 20) {
                        WeeklyOverviewCard(week: week)
                        RemainingWorkSection(week: week)
                        CourseOverviewSection(week: week, courses: courses)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if sizeClass == .compact {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { router.push(.archive) } label: { Label("Archive & All Weeks", systemImage: "archivebox") }
                    Button { router.push(.settings) } label: { Label("Settings", systemImage: "gearshape") }
                } label: {
                    Label("More", systemImage: "line.3.horizontal")
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let week {
                    Button {
                        router.activeSheet = .newAssignment(course: nil, week: week)
                    } label: {
                        Label("New Assignment", systemImage: "doc.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
                Button {
                    router.activeSheet = .newWeek
                } label: {
                    Label("New Week", systemImage: "calendar.badge.plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                if let week {
                    Button {
                        router.activeSheet = .editWeek(week)
                    } label: {
                        Label("Edit Week", systemImage: "pencil")
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .accessibilityIdentifier("dashboardAddMenu")
        }
    }
}

// MARK: - Header

struct WeekNavigationHeader: View {
    @Environment(AppRouter.self) private var router
    let week: AcademicWeek
    let weeks: [AcademicWeek]
    let planner: WeekPlanner

    private var sorted: [AcademicWeek] { weeks.sorted(by: AcademicWeek.chronological) }
    private var index: Int? { sorted.firstIndex { $0.id == week.id } }
    private var previous: AcademicWeek? { index.flatMap { $0 > 0 ? sorted[$0 - 1] : nil } }
    private var next: AcademicWeek? { index.flatMap { $0 + 1 < sorted.count ? sorted[$0 + 1] : nil } }
    private var current: AcademicWeek? { sorted.first { planner.contains(.now, start: $0.startDate, end: $0.endDate) } }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(week.title)
                    .font(.lora(26, weight: .bold))
                Text(week.dateRangeText)
                    .font(.lora(16, weight: .medium))
                timingLabel
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if let current, current.id != week.id {
                Button("This Week") { router.select(current) }
                    .font(.lora(13, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.forest)
                    .chip()
            }
            HStack(spacing: 4) {
                Button {
                    if let previous { withAnimation { router.select(previous) } }
                } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                .disabled(previous == nil)
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel("Previous week")

                Button {
                    if let next { withAnimation { router.select(next) } }
                } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
                .disabled(next == nil)
                .keyboardShortcut("]", modifiers: .command)
                .accessibilityLabel("Next week")
            }
            .buttonStyle(RoundIconButtonStyle())
        }
        .card(padding: 16)
    }

    @ViewBuilder
    private var timingLabel: some View {
        switch planner.timing(start: week.startDate, end: week.endDate) {
        case .current: Text("Current week").font(.loraItalic(14)).foregroundStyle(AppTheme.forest)
        case .past: Text("Past week").font(.loraItalic(14)).foregroundStyle(.secondary)
        case .upcoming: Text("Upcoming week").font(.loraItalic(14)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Overview

struct WeeklyOverviewCard: View {
    @Environment(AppRouter.self) private var router
    let week: AcademicWeek

    var body: some View {
        let summary = week.summary
        VStack(alignment: .leading, spacing: 14) {
            if summary.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No homework yet").font(.lora(19, weight: .semibold))
                        Text("Add this week’s assignments as they come in. Courses without homework can stay empty.")
                            .font(.lora(14))
                            .foregroundStyle(.secondary)
                    }
                    Illustration(name: Mascot.image(for: summary), size: 84)
                }
                Button {
                    router.activeSheet = .newAssignment(course: nil, week: week)
                } label: {
                    Label("Add Assignment", systemImage: "plus")
                }
                .buttonStyle(.goblinPrimary)
                .accessibilityIdentifier("emptyWeekAddAssignment")
            } else {
                HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let percent = summary.percent {
                        Text("\(percent)%")
                            .font(.lora(46, weight: .bold))
                            
                            .contentTransition(.numericText())
                            .accessibilityLabel(Text("\(percent) percent of exercises done"))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if summary.totalExercises > 0 {
                            Text("\(summary.completedExercises) of \(summary.totalExercises) exercises done")
                                .font(.lora(17, weight: .semibold))
                                
                            Text(summary.remainingExercises == 0
                                 ? String(localized: "Nothing left")
                                 : String(localized: "\(summary.remainingExercises) remaining"))
                                .font(.lora(15))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No exercise counts yet").font(.lora(17, weight: .semibold))
                            Text("Add counts to assignments to track exercises.")
                                .font(.lora(15))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Illustration(name: Mascot.image(for: summary), size: 92)
                    .transition(.scale.combined(with: .opacity))
                    .id(Mascot.image(for: summary))
                }
                ProgressBar(fraction: summary.fraction, tint: AppTheme.forest, height: 12)
                HStack(spacing: 16) {
                    StatPill(value: "\(summary.completedAssignmentCount)/\(summary.assignmentCount)",
                             label: String(localized: "assignments done"), symbol: "checkmark.circle")
                    StatPill(value: "\(summary.openAssignmentCount)",
                             label: String(localized: "still open"), symbol: "circle.dashed")
                }
                if summary.inconsistentAssignmentCount > 0 {
                    Label("Some completed counts exceed their totals", systemImage: "exclamationmark.triangle")
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.rust)
                }
            }
        }
        .card(padding: 18)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: Mascot.image(for: week.summary))
    }
}

struct StatPill: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(value).font(.lora(15, weight: .semibold))
            Text(label).font(.lora(15)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Courses

struct CourseOverviewSection: View {
    let week: AcademicWeek
    let courses: [Course]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Courses")
                .font(.lora(20, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)
            ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                CourseSummaryRow(course: course, week: week)
                if index < courses.count - 1 {
                    Divider().overlay(AppTheme.borderSoft).padding(.leading, 74)
                }
            }
        }
        .padding(.bottom, 6)
        .parchmentSurface()
    }
}

struct CourseSummaryRow: View {
    @Environment(AppRouter.self) private var router
    let course: Course
    let week: AcademicWeek

    var body: some View {
        let assignments = course.assignments(in: week)
        let summary = ProgressCalculator.summarize(assignments.map(\.snapshot))
        Button {
            if router.sidebar != nil {
                router.sidebar = .course(course)
            } else {
                router.open(course)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                CourseIconView(iconName: course.iconName, palette: course.palette, size: 48)
                VStack(alignment: .leading, spacing: 6) {
                    CourseTitleView(course: course, titleFont: .lora(16, weight: .semibold))
                    if summary.isEmpty {
                        Text("No homework this week")
                            .font(.lora(12))
                            .foregroundStyle(.tertiary)
                            .italic()
                    } else {
                        HStack(spacing: 8) {
                            Text(summary.assignmentCount == 1
                                 ? String(localized: "1 assignment")
                                 : String(localized: "\(summary.assignmentCount) assignments"))
                            if summary.totalExercises > 0 {
                                Text("·")
                                Text("\(summary.completedExercises)/\(summary.totalExercises)")
                                if summary.remainingExercises > 0 {
                                    Text("· \(summary.remainingExercises) left")
                                } else {
                                    Image(systemName: "checkmark").foregroundStyle(AppTheme.forest)
                                }
                            } else if summary.openAssignmentCount == 0 {
                                Image(systemName: "checkmark").foregroundStyle(AppTheme.forest)
                            }
                        }
                        .font(.lora(12))
                        .foregroundStyle(.secondary)
                        ProgressBar(fraction: summary.fraction ?? (summary.openAssignmentCount == 0 ? 1 : nil),
                                    tint: course.palette.color, height: 6)
                    }
                }
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("courseRow-\(course.id.uuidString)")
    }
}

// MARK: - Empty

struct NoWeeksView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            CozyEmptyState(
                image: "CatStudying",
                title: "Start your first week",
                message: "Each academic week keeps its own homework and progress. Previous weeks are always kept."
            ) {
                Button("Create Week") { router.activeSheet = .newWeek }
                    .buttonStyle(.goblinPrimary)
                    .padding(.top, 6)
                    .accessibilityIdentifier("createFirstWeek")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }
}

/// Round parchment button for the week arrows.
struct RoundIconButtonStyle: ButtonStyle {
    var size: CGFloat = 40
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isEnabled ? AppTheme.forest : AppTheme.border)
            .frame(width: size, height: size)
            .background(Circle().fill(AppTheme.chipFill))
            .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
