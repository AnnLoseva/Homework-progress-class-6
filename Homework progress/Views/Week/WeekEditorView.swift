//
//  WeekEditorView.swift
//  Homework progress
//

import SwiftUI
import SwiftData

/// Creates a week (optionally copying another week's assignment structure) or edits one.
struct WeekEditorView: View {
    enum Mode {
        case create
        case edit(AcademicWeek)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Query(sort: \AcademicWeek.startDate, order: .reverse) private var weeks: [AcademicWeek]
    @AppStorage("weekStartsOn") private var weekStartsOn = 1

    let mode: Mode

    @State private var title = ""
    @State private var number: Int?
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var copySourceID: UUID?
    @State private var copyCounts = true
    @State private var shiftDueDates = true
    @State private var confirmDelete = false
    @State private var didLoad = false

    private var planner: WeekPlanner { WeekPlanner(firstWeekday: weekStartsOn) }
    private var isCreating: Bool { if case .create = mode { true } else { false } }
    private var copySource: AcademicWeek? { weeks.first { $0.id == copySourceID } }

    private var overlapping: AcademicWeek? {
        let range = planner.normalized(start: startDate, end: endDate)
        return weeks.first { other in
            if case .edit(let week) = mode, week.id == other.id { return false }
            return other.startDate <= range.end && other.endDate >= range.start
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    TextField("Name, e.g. Week 5", text: $title)
                        .accessibilityIdentifier("weekTitleField")
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { old, new in
                            // Keep the week length when moving the start.
                            let length = planner.dayOffset(from: old, to: endDate)
                            if length >= 0 { endDate = planner.shift(new, byDays: length) }
                        }
                    DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WeekPlanner.rangeText(start: startDate, end: endDate))
                        if let overlapping {
                            Text("Overlaps \(overlapping.title). That’s allowed, but the dashboard picks one week per day.")
                                .foregroundStyle(AppTheme.rust)
                        }
                    }
                }

                if isCreating, !weeks.isEmpty {
                    Section {
                        Picker("Copy assignments from", selection: $copySourceID) {
                            Text("Don’t copy").tag(UUID?.none)
                            ForEach(weeks) { week in
                                Text(week.fullLabel).tag(Optional(week.id))
                            }
                        }
                        if let copySource {
                            Toggle("Copy exercise counts", isOn: $copyCounts)
                            Toggle("Shift due dates to the new week", isOn: $shiftDueDates)
                            Text("\(copySource.assignmentList.count) assignments will be created with fresh progress. PDFs and progress from \(copySource.title) are not copied, and that week isn’t changed.")
                                .font(.lora(12))
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Structure")
                    }
                }

                if case .edit(let week) = mode {
                    Section {
                        Button("Delete Week…", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Deletes this week’s \(week.assignmentList.count) assignments and their PDFs. Courses and other weeks are not affected.")
                    }
                }
                }
                .listRowBackground(AppTheme.parchmentCard)
            }
            .parchmentList()
            .navigationTitle(isCreating ? "New Week" : "Edit Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Create" : "Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("saveWeek")
                }
            }
            .confirmationDialog("Delete this week?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Week", role: .destructive, action: deleteWeek)
            } message: {
                Text("Its assignments, progress and PDF copies will be deleted. This can’t be undone.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        switch mode {
        case .create:
            let latest = weeks.max(by: AcademicWeek.chronological)
            let range: WeekPlanner.Range
            if let latest, latest.endDate >= planner.range(containing: .now).start {
                range = planner.range(after: latest.endDate)
            } else {
                range = planner.range(containing: .now)
            }
            startDate = range.start
            endDate = range.end
            let next = WeekPlanner.nextNumber(after: weeks.map(\.number))
            number = next
            title = WeekPlanner.defaultTitle(number: next)
            copySourceID = nil
        case .edit(let week):
            title = week.title
            number = week.number
            startDate = week.startDate
            endDate = week.endDate
        }
    }

    private func save() {
        let store = services.store(context)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .create:
            let week = store.createWeek(title: cleanTitle, number: parsedNumber(cleanTitle) ?? number,
                                        start: startDate, end: endDate, planner: planner)
            if let copySource {
                store.duplicateAssignments(
                    from: copySource, into: week,
                    options: .init(copyExerciseCounts: copyCounts, copyNotes: false, shiftDueDates: shiftDueDates),
                    planner: planner
                )
            }
            router.select(week)
        case .edit(let week):
            let range = planner.normalized(start: startDate, end: endDate)
            week.title = cleanTitle
            week.number = parsedNumber(cleanTitle) ?? week.number
            week.startDate = range.start
            week.endDate = range.end
            store.save()
        }
        dismiss()
    }

    /// "Week 7" → 7, so the next new week can suggest "Week 8".
    private func parsedNumber(_ title: String) -> Int? {
        title.split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
    }

    private func deleteWeek() {
        guard case .edit(let week) = mode else { return }
        if let inspected = router.inspectedAssignment, inspected.week?.id == week.id { router.inspectedAssignment = nil }
        router.resetPath()
        if router.selectedWeekID == week.id { router.selectedWeekID = nil }
        if case .week(let selected) = router.sidebar, selected.id == week.id { router.sidebar = nil }
        services.store(context).delete(week)
        dismiss()
    }
}
