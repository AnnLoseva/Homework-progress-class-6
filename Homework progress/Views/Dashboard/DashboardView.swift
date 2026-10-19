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
        .background(Color.appBackground)
        .navigationTitle(week?.title ?? String(localized: "Homework"))
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
            VStack(alignment: .leading, spacing: 4) {
                Text(week.dateRangeText)
                    .font(.title3.weight(.semibold))
                timingLabel
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if let current, current.id != week.id {
                Button("This Week") { router.select(current) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var timingLabel: some View {
        switch planner.timing(start: week.startDate, end: week.endDate) {
        case .current: Text("Current week").font(.subheadline).foregroundStyle(.indigo)
        case .past: Text("Past week").font(.subheadline).foregroundStyle(.secondary)
        case .upcoming: Text("Upcoming week").font(.subheadline).foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("No homework yet").font(.headline)
                    Text("Add this week’s assignments as they come in. Courses without homework can stay empty.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        router.activeSheet = .newAssignment(course: nil, week: week)
                    } label: {
                        Label("Add Assignment", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                    .accessibilityIdentifier("emptyWeekAddAssignment")
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    if let percent = summary.percent {
                        Text("\(percent)%")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .accessibilityLabel(Text("\(percent) percent of exercises done"))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if summary.totalExercises > 0 {
                            Text("\(summary.completedExercises) of \(summary.totalExercises) exercises done")
                                .font(.headline)
                                .monospacedDigit()
                            Text(summary.remainingExercises == 0
                                 ? String(localized: "Nothing left")
                                 : String(localized: "\(summary.remainingExercises) remaining"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No exercise counts yet").font(.headline)
                            Text("Add counts to assignments to track exercises.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ProgressBar(fraction: summary.fraction, tint: .indigo, height: 10)
                HStack(spacing: 16) {
                    StatPill(value: "\(summary.completedAssignmentCount)/\(summary.assignmentCount)",
                             label: String(localized: "assignments done"), symbol: "checkmark.circle")
                    StatPill(value: "\(summary.openAssignmentCount)",
                             label: String(localized: "still open"), symbol: "circle.dashed")
                }
                if summary.inconsistentAssignmentCount > 0 {
                    Label("Some completed counts exceed their totals", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .card(padding: 18)
    }
}

struct StatPill: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Courses

struct CourseOverviewSection: View {
    let week: AcademicWeek
    let courses: [Course]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Courses").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                    CourseSummaryRow(course: course, week: week)
                    if index < courses.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
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
                CourseIconView(iconName: course.iconName, palette: course.palette)
                VStack(alignment: .leading, spacing: 6) {
                    CourseTitleView(course: course, titleFont: .subheadline.weight(.semibold))
                    if summary.isEmpty {
                        Text("No homework this week")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        HStack(spacing: 8) {
                            Text(summary.assignmentCount == 1
                                 ? String(localized: "1 assignment")
                                 : String(localized: "\(summary.assignmentCount) assignments"))
                            if summary.totalExercises > 0 {
                                Text("·")
                                Text("\(summary.completedExercises)/\(summary.totalExercises)").monospacedDigit()
                                if summary.remainingExercises > 0 {
                                    Text("· \(summary.remainingExercises) left")
                                } else {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                            } else if summary.openAssignmentCount == 0 {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ProgressBar(fraction: summary.fraction ?? (summary.openAssignmentCount == 0 ? 1 : nil),
                                    tint: course.palette.color, height: 6)
                    }
                }
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
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
        ContentUnavailableView {
            Label("Start your first week", systemImage: "calendar.badge.plus")
        } description: {
            Text("Each academic week keeps its own homework and progress. Previous weeks are always kept.")
        } actions: {
            Button("Create Week") { router.activeSheet = .newWeek }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("createFirstWeek")
        }
    }
}
