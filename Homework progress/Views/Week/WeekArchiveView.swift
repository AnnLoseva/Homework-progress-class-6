//
//  WeekArchiveView.swift
//  Homework progress
//

import SwiftUI
import SwiftData

/// All weeks, grouped into current, upcoming and past. Past weeks are read-only history in
/// spirit, but stay fully editable.
struct WeekArchiveView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \AcademicWeek.startDate, order: .reverse) private var weeks: [AcademicWeek]
    @AppStorage("weekStartsOn") private var weekStartsOn = 1

    private var planner: WeekPlanner { WeekPlanner(firstWeekday: weekStartsOn) }

    var body: some View {
        let grouped = Dictionary(grouping: weeks) { planner.timing(start: $0.startDate, end: $0.endDate) }
        List {
            if weeks.isEmpty {
                ContentUnavailableView("No weeks yet", systemImage: "calendar")
            }
            section(String(localized: "Current"), grouped[.current])
            section(String(localized: "Upcoming"), grouped[.upcoming]?.reversed())
            section(String(localized: "Past"), grouped[.past])
        }
        .navigationTitle("All Weeks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.activeSheet = .newWeek
                } label: {
                    Label("New Week", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [AcademicWeek]?) -> some View {
        if let items, !items.isEmpty {
            Section(title) {
                ForEach(items) { week in
                    Button {
                        router.select(week)
                        if sizeClass == .compact { router.resetPath() } else { router.sidebar = .week(week) }
                    } label: {
                        ArchiveWeekRow(week: week)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Edit") { router.activeSheet = .editWeek(week) }
                    }
                    .contextMenu {
                        Button { router.activeSheet = .editWeek(week) } label: { Label("Edit Week", systemImage: "pencil") }
                    }
                }
            }
        }
    }
}

private struct ArchiveWeekRow: View {
    let week: AcademicWeek

    var body: some View {
        let summary = week.summary
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(week.title).font(.headline)
                Spacer()
                if let percent = summary.percent {
                    Text("\(percent)%").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                } else if !summary.isEmpty, summary.openAssignmentCount == 0 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            Text(week.dateRangeText).font(.subheadline).foregroundStyle(.secondary)
            if summary.isEmpty {
                Text("No homework").font(.caption).foregroundStyle(.tertiary)
            } else {
                Text("\(summary.completedAssignmentCount) of \(summary.assignmentCount) assignments done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressBar(fraction: summary.fraction, tint: .indigo, height: 5)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
