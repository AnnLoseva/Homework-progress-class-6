//
//  SettingsView.swift
//  Homework progress
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Query(sort: \Course.sortOrder) private var courses: [Course]

    @AppStorage("weekStartsOn") private var weekStartsOn = 1
    @AppStorage(MoodleIntegration.openInAppKey) private var moodleInApp = true
    @AppStorage(MoodleIntegration.schemeKey) private var moodleScheme = MoodleIntegration.defaultScheme
    @AppStorage(ReminderSettings.deadlineEnabledKey) private var deadlineReminders = false
    @AppStorage(ReminderSettings.deadlineLeadHoursKey) private var leadHours = 24
    @AppStorage(ReminderSettings.weeklyReviewEnabledKey) private var weeklyReview = false
    @AppStorage(ReminderSettings.weeklyReviewWeekdayKey) private var reviewWeekday = 7
    @AppStorage(ReminderSettings.weeklyReviewHourKey) private var reviewHour = 19

    @State private var notificationsDenied = false
    @State private var showingNewCourse = false
    @State private var exportDocument: BackupFile?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var message: String?

    var body: some View {
        Form {
            Group {
            Section("Courses") {
                ForEach(courses) { course in
                    Button {
                        router.push(.courseSettings(course))
                    } label: {
                        HStack(spacing: 10) {
                            CourseIconView(iconName: course.iconName, palette: course.palette, size: 30)
                            Text(course.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.forward").font(.lora(12)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onMove { from, to in
                    var reordered = courses
                    reordered.move(fromOffsets: from, toOffset: to)
                    services.store(context).reorder(reordered)
                }
                Button {
                    showingNewCourse = true
                } label: {
                    Label("Add Course", systemImage: "plus")
                }
            }

            SyncStatusSection()

            Section("Weeks") {
                Picker("Weeks start on", selection: $weekStartsOn) {
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                }
            }

            Section {
                Toggle("Open courses in the Moodle app", isOn: $moodleInApp)
                if moodleInApp {
                    LabeledContent("App link scheme") {
                        TextField(MoodleIntegration.defaultScheme, text: $moodleScheme)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if MoodleIntegration.validatedScheme(moodleScheme) == nil {
                        Label("Not a valid scheme — “\(MoodleIntegration.defaultScheme)” will be used.", systemImage: "exclamationmark.triangle")
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.rust)
                    }
                }
            } header: {
                Text("Moodle")
            } footer: {
                Text("Course buttons open the course page right inside the Moodle app (it asks you to log in to md.hit.ac.il the first time). If the app isn’t installed, the page opens in the browser. Keep “moodlemobile” for the official Moodle app; a branded college app uses its own scheme.")
            }

            Section {
                Toggle("Deadline reminders", isOn: $deadlineReminders)
                if deadlineReminders {
                    Picker("Remind me", selection: $leadHours) {
                        Text("2 hours before").tag(2)
                        Text("1 day before").tag(24)
                        Text("2 days before").tag(48)
                    }
                }
                Toggle("Weekly review", isOn: $weeklyReview)
                if weeklyReview {
                    Picker("Day", selection: $reviewWeekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                    Picker("Time", selection: $reviewHour) {
                        ForEach(6...22, id: \.self) { hour in
                            Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!,
                                 format: .dateTime.hour()).tag(hour)
                        }
                    }
                }
                if notificationsDenied {
                    Label("Notifications are turned off for this app in iOS Settings.", systemImage: "bell.slash")
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.rust)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Optional local notifications. Everything else works without them.")
            }
            .onChange(of: deadlineReminders) { _, on in remindersChanged(enabled: on) }
            .onChange(of: weeklyReview) { _, on in remindersChanged(enabled: on) }
            .onChange(of: leadHours) { _, _ in remindersChanged(enabled: true) }
            .onChange(of: reviewWeekday) { _, _ in remindersChanged(enabled: true) }
            .onChange(of: reviewHour) { _, _ in remindersChanged(enabled: true) }

            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                }
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Restore from Backup…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("A single file with all weeks, courses, assignments, progress and PDFs. Restoring adds what’s missing and never overwrites or deletes existing data.")
            }

            Section("Notability") {
                NavigationLink {
                    NotabilityInfoView()
                } label: {
                    Label("How the Notability integration works", systemImage: "info.circle")
                }
            }
            }
            .listRowBackground(AppTheme.parchmentCard)
        }
        .parchmentList()
        .navigationTitle("Settings")
        .toolbar { EditButton() }
        .sheet(isPresented: $showingNewCourse) { NewCourseView().goblinChrome() }
        .fileExporter(isPresented: $isExporterPresented, document: exportDocument, contentType: .json,
                      defaultFilename: BackupService.suggestedFilename()) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
            else { message = String(localized: "Backup saved.") }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { restore(from: url) }
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .task { await refreshAuthorization() }
    }

    private func remindersChanged(enabled: Bool) {
        Task {
            if enabled {
                let granted = await ReminderScheduler.requestAuthorization()
                notificationsDenied = !granted
            }
            let assignments = (try? context.fetch(FetchDescriptor<HomeworkAssignment>())) ?? []
            let items = assignments.compactMap { a -> ReminderScheduler.DeadlineItem? in
                guard !a.isCompleted, let due = a.dueDate else { return nil }
                return .init(id: a.id, title: a.title, courseName: a.course?.name ?? "", dueDate: due)
            }
            await ReminderScheduler.reschedule(deadlines: items)
        }
    }

    private func refreshAuthorization() async {
        let settings = await UNUserNotificationCenterProxy.authorizationStatus()
        notificationsDenied = (deadlineReminders || weeklyReview) && settings == .denied
    }

    private func exportBackup() {
        do {
            let data = try BackupService(context: context, files: services.files).exportData()
            exportDocument = BackupFile(data: data)
            isExporterPresented = true
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let report = try BackupService(context: context, files: services.files).restore(from: data)
            message = String(localized: "Restored \(report.weeksAdded) weeks, \(report.assignmentsAdded) assignments and \(report.attachmentsAdded) PDFs. \(report.skippedExisting) items were already here and were kept as they are.")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

import UserNotifications

enum UNUserNotificationCenterProxy {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NewCourseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services
    @State private var name = ""
    @State private var englishName = ""
    @State private var url = ""
    @State private var palette: CoursePalette = .blue

    var body: some View {
        NavigationStack {
            Form {
                Group {
                TextField("Course name", text: $name)
                TextField("English label (optional)", text: $englishName)
                TextField("Course page URL (optional)", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                Picker("Color", selection: $palette) {
                    ForEach(CoursePalette.allCases) { Text($0.name).tag($0) }
                }
                }
                .listRowBackground(AppTheme.parchmentCard)
            }
            .parchmentList()
            .navigationTitle("New Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        services.store(context).createCourse(name: name.trimmingCharacters(in: .whitespaces),
                                                             englishName: englishName, url: url.isEmpty ? nil : url,
                                                             palette: palette, icon: "CourseStudy")
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct NotabilityInfoView: View {
    var body: some View {
        List {
            Group {
            Section("Works today") {
                Label("Add PDF to Notability: the share sheet sends a copy of the homework PDF. Choose Notability, then pick a new or existing note inside Notability.", systemImage: "checkmark.circle")
                Label("Your PDF stays in this app. Notability gets its own copy.", systemImage: "checkmark.circle")
                Label("Each course remembers its Notability folder name and, optionally, a link you saved.", systemImage: "checkmark.circle")
            }
            Section("Not available") {
                Label("Opening a specific notebook directly. Notability doesn’t publish a URL scheme or API for this.", systemImage: "xmark.circle")
                Label("Confirming that Notability finished importing. iOS only reports which app was chosen, so the app never shows a false “imported” message.", systemImage: "xmark.circle")
            }
            Section("Needs you") {
                Label("Choosing the destination note or folder inside Notability after sharing.", systemImage: "hand.tap")
                Label("Opening Notability yourself when no notebook link is saved.", systemImage: "hand.tap")
            }
            }
            .listRowBackground(AppTheme.parchmentCard)
        }
        .parchmentList()
        .navigationTitle("Notability")
    }
}

/// Shows whether iPhone and iPad are syncing through iCloud.
struct SyncStatusSection: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let sync = services.sync
        Section {
            HStack(spacing: 12) {
                Image(systemName: symbol(sync.status))
                    .font(.title3)
                    .foregroundStyle(sync.status == .active ? AppTheme.forest : AppTheme.rust)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(sync.status)).font(.lora(16, weight: .semibold))
                    if let last = sync.lastSync {
                        Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                            .font(.lora(12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            // When signed out, CloudKit's error only repeats the status above (e.g. Cocoa error 134400).
            if sync.status == .active, let error = sync.lastError {
                Text(error).font(.lora(12)).foregroundStyle(AppTheme.rust)
            }
        } header: {
            Text("iCloud Sync")
        } footer: {
            Text(footer(sync.status))
        }
        .task { await sync.refreshAccountStatus() }
    }

    private func symbol(_ status: SyncMonitor.Status) -> String {
        switch status {
        case .active: "checkmark.icloud"
        case .checking: "icloud"
        case .signedOut: "icloud.slash"
        case .localOnly, .disabled: "externaldrive"
        }
    }

    private func title(_ status: SyncMonitor.Status) -> String {
        switch status {
        case .active: String(localized: "Syncing with your other devices")
        case .checking: String(localized: "Checking iCloud…")
        case .signedOut: String(localized: "iCloud isn’t available")
        case .localOnly: String(localized: "Saved on this device only")
        case .disabled: String(localized: "Sync is off (test data)")
        }
    }

    private func footer(_ status: SyncMonitor.Status) -> String {
        switch status {
        case .active, .checking:
            String(localized: "Weeks, assignments, progress, notes, course settings and PDFs sync through your private iCloud between iPhone and iPad signed in to the same Apple Account. Changes usually appear within seconds when both are online; offline changes upload later.")
        case .signedOut:
            String(localized: "Sign in to iCloud in the Settings app (and allow iCloud for this app) to sync with your iPad or iPhone. Your homework stays saved on this device meanwhile.")
        case .localOnly:
            String(localized: "The iCloud store couldn’t be opened, so data is kept on this device. Nothing was deleted; sync starts after the app is reinstalled from a build with iCloud enabled.")
        case .disabled:
            String(localized: "This session uses temporary data.")
        }
    }
}
