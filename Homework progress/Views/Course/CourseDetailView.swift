//
//  CourseDetailView.swift
//  Homework progress
//

import SwiftUI
import SwiftData

struct CourseDetailView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    let course: Course
    let week: AcademicWeek?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    links
                }
                .card(padding: 18)
                if let week {
                    weekSection(week)
                    otherWeeksSection(excluding: week)
                } else {
                    Text("Create a week to add homework for this course.")
                        .foregroundStyle(.secondary)
                        .card()
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { ForestBackdrop() }
        .navigationTitle(course.englishName.isEmpty ? course.name : course.englishName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.push(.courseSettings(course))
                } label: {
                    Label("Course Settings", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("courseSettings")
            }
            if let week {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        router.activeSheet = .newAssignment(course: course, week: week)
                    } label: {
                        Label("New Assignment", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("courseAddAssignment")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CourseIconView(iconName: course.iconName, palette: course.palette, size: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.lora(24, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("courseHebrewTitle")
                if !course.englishName.isEmpty {
                    Text(course.englishName).font(.lora(15)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var links: some View {
        HStack(spacing: 10) {
            OpenMoodleButton(course: course)
            OpenNotebookButton(course: course)
        }
        .controlSize(.large)
    }

    private func weekSection(_ week: AcademicWeek) -> some View {
        let assignments = course.assignments(in: week)
        let summary = ProgressCalculator.summarize(assignments.map(\.snapshot))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(week.fullLabel).font(.lora(20, weight: .semibold))
                Spacer()
                if let percent = summary.percent {
                    Text("\(percent)%").font(.lora(17, weight: .semibold)).foregroundStyle(course.palette.color)
                }
            }
            if assignments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No homework for this course this week.")
                        .foregroundStyle(.secondary)
                    Button {
                        router.activeSheet = .newAssignment(course: course, week: week)
                    } label: {
                        Label("Add Assignment", systemImage: "plus")
                    }
                    .buttonStyle(.goblinSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if summary.totalExercises > 0 {
                        Text("\(summary.completedExercises) of \(summary.totalExercises) exercises · \(summary.remainingExercises) remaining")
                            .font(.lora(15))
                            .foregroundStyle(.secondary)
                    }
                    ProgressBar(fraction: summary.fraction, tint: course.palette.color, height: 8)
                }
                VStack(spacing: 0) {
                    ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                        AssignmentRow(assignment: assignment)
                        if index < assignments.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
                .padding(.horizontal, -18)
            }
        }
        .card(padding: 18)
    }

    /// Previous and upcoming weeks for this course — separate records, separate progress.
    @ViewBuilder
    private func otherWeeksSection(excluding week: AcademicWeek) -> some View {
        let others = Dictionary(grouping: course.assignmentList.filter { $0.week != nil && $0.week?.id != week.id }) { $0.week! }
        let sortedWeeks = others.keys.sorted { $0.startDate > $1.startDate }
        if !sortedWeeks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Other Weeks").font(.lora(20, weight: .semibold))
                ForEach(sortedWeeks) { other in
                    let items = (others[other] ?? []).sorted(by: HomeworkAssignment.defaultOrder)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(other.fullLabel).font(.lora(15, weight: .semibold))
                            Spacer()
                            Button("Go to Week") { router.select(other) }
                                .font(.lora(12))
                        }
                        VStack(spacing: 0) {
                            ForEach(items) { AssignmentRow(assignment: $0) }
                        }
                        .padding(.horizontal, -18)
                    }
                }
            }
            .card(padding: 18)
        }
    }
}
