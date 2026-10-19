//
//  RemainingWorkSection.swift
//  Homework progress
//

import SwiftUI

enum RemainingSort: String, CaseIterable, Identifiable {
    case dueDate, course, mostRemaining, recentlyUpdated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueDate: String(localized: "Due Date")
        case .course: String(localized: "Course")
        case .mostRemaining: String(localized: "Most Remaining")
        case .recentlyUpdated: String(localized: "Recently Updated")
        }
    }

    /// Sorts unfinished assignments. Assignments without due dates are never given one: they are
    /// listed after dated ones when sorting by due date.
    func sorted(_ items: [HomeworkAssignment]) -> [HomeworkAssignment] {
        items.sorted { lhs, rhs in
            switch self {
            case .dueDate:
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?) where l != r: return l < r
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
            case .course:
                let l = lhs.course?.sortOrder ?? .max, r = rhs.course?.sortOrder ?? .max
                if l != r { return l < r }
            case .mostRemaining:
                let l = lhs.progress.remaining ?? -1, r = rhs.progress.remaining ?? -1
                if l != r { return l > r }
            case .recentlyUpdated:
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

struct RemainingWorkSection: View {
    @AppStorage("remainingSort") private var sort: RemainingSort = .dueDate
    let week: AcademicWeek

    var body: some View {
        let open = sort.sorted(week.assignments.filter { !$0.isCompleted })
        if !week.assignments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Remaining Work").font(.lora(20, weight: .semibold))
                    Spacer()
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(RemainingSort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label(sort.title, systemImage: "arrow.up.arrow.down")
                            .font(.lora(13, weight: .medium))
                            .foregroundStyle(AppTheme.forest)
                            .chip()
                    }
                    .accessibilityLabel(Text("Sort remaining work, currently \(sort.title)"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)

                if open.isEmpty {
                    HStack(spacing: 14) {
                        Illustration(name: "MushroomCheer", size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("All done for this week").font(.lora(17, weight: .semibold))
                            Text("Time for tea and a slow walk.")
                                .font(.loraItalic(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                } else {
                    ForEach(Array(open.enumerated()), id: \.element.id) { index, assignment in
                        AssignmentRow(assignment: assignment, showsCourse: true)
                        if index < open.count - 1 { Divider().overlay(AppTheme.borderSoft).padding(.leading, 78) }
                    }
                }
            }
            .padding(.bottom, 6)
            .parchmentSurface()
        }
    }
}

/// A tappable assignment row used on the dashboard and course screens.
struct AssignmentRow: View {
    @Environment(AppRouter.self) private var router
    let assignment: HomeworkAssignment
    var showsCourse = false

    var body: some View {
        let progress = assignment.progress
        let palette = assignment.course?.palette ?? .slate
        let isInspected = router.inspectedAssignment?.id == assignment.id
        Button {
            router.open(assignment)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if showsCourse, let course = assignment.course {
                    CourseIconView(iconName: course.iconName, palette: course.palette, size: 52)
                } else {
                    Image(systemName: assignment.status.symbolName)
                        .font(.lora(20))
                        .foregroundStyle(assignment.isCompleted ? AppTheme.forest : palette.color)
                        .frame(width: 52)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(assignment.title.isEmpty ? String(localized: "Untitled") : assignment.title)
                        .font(.lora(15, weight: .semibold))
                        .strikethrough(assignment.isCompleted, color: .secondary)
                    if showsCourse, let course = assignment.course {
                        Text(course.name)
                            .font(.lora(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        if let due = assignment.dueDate { DueDateText(date: due) }
                        if assignment.status == .postponed || assignment.status == .notAssigned {
                            StatusBadge(status: assignment.status)
                        }
                        if !assignment.attachments.isEmpty {
                            Image(systemName: "doc.richtext")
                                .font(.lora(12))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Has PDF")
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    ExerciseCountText(progress: progress)
                        .font(.lora(12, weight: .medium))
                    if progress.hasExerciseCount {
                        ProgressBar(fraction: progress.fraction, tint: palette.color, height: 5)
                            .frame(width: 64)
                    }
                }
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isInspected ? AppTheme.chipFill : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assignmentRow-\(assignment.title)")
    }
}
