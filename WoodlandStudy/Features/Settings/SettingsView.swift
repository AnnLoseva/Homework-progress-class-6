import SwiftUI
import StudyData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(StudentStore.self) private var store

    @State private var classCode = ""
    @State private var joinMessage: String?
    @State private var isJoining = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleteError: String?
    @State private var isDeleting = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Signed in with", value: environment.isDemo ? String(localized: "Demo account") : "Apple")
                if let identity = store.identity {
                    LabeledContent("Role", value: identity.isAdmin ? String(localized: "Administrator") : String(localized: "Student"))
                    LabeledContent("Class membership", value: identity.isEnrolled ? String(localized: "Joined") : String(localized: "Not joined"))
                }
            }

            if store.identity?.isEnrolled != true {
                Section {
                    TextField("Class code", text: $classCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("classCodeField")
                    Button {
                        Task { await join() }
                    } label: {
                        if isJoining { ProgressView() } else { Text("Join class") }
                    }
                    .disabled(classCode.trimmingCharacters(in: .whitespaces).count < 8 || isJoining)
                    if let joinMessage { Text(joinMessage).foregroundStyle(Palette.inkSoft) }
                } header: {
                    Text("Join your class")
                } footer: {
                    Text("Your instructor shares this code. It unlocks materials marked “Class members”.")
                }
            }

            Section {
                LabeledContent("Status", value: syncText)
                if let last = store.lastSyncedAt {
                    LabeledContent("Last synced", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Sync now") { Task { await store.sync() } }
            } header: {
                Text("Sync")
            } footer: {
                Text("Your subscriptions and progress are stored in your account and sync to every device you sign in on. The app also keeps a copy on this device so it works offline.")
            }

            Section {
                Button("Export my data") { Task { await export() } }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share export file", systemImage: "square.and.arrow.up") }
                }
                if let exportError { Text(exportError).foregroundStyle(Palette.rust) }
                NavigationLink("Privacy") { PrivacySummaryView() }
            } header: {
                Text("Your data")
            } footer: {
                Text("The export contains everything stored about you: subscriptions, progress, notes and your account id.")
            }

            Section {
                Button("Sign out") { confirmSignOut = true }
                    .accessibilityIdentifier("signOutButton")
                Button("Delete account and data", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("deleteAccountButton")
                if isDeleting { ProgressView("Deleting…") }
                if let deleteError { Text(deleteError).foregroundStyle(Palette.rust) }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Text("Woodland Study Tracker is open-source software (MIT License). Lora font: SIL Open Font License 1.1.")
                    .font(.lora(13, relativeTo: .footnote)).foregroundStyle(Palette.inkSoft)
            }
        }
        .woodList()
        .navigationTitle("Settings")
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await environment.session.signOut() } }
        } message: {
            Text(store.pendingChangeCount > 0
                 ? "\(store.pendingChangeCount) change(s) haven't synced yet and will be lost. Downloaded files and cached data are removed from this device."
                 : "Downloaded files and cached data are removed from this device. Your progress stays in your account.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently deletes your account, subscriptions, progress and notes from the server and this device. It cannot be undone. You'll be asked to confirm with Apple.")
        }
    }

    private var syncText: String {
        switch store.syncStatus {
        case .idle: store.pendingChangeCount == 0 ? String(localized: "Up to date") : String(localized: "\(store.pendingChangeCount) change(s) waiting")
        case .syncing: String(localized: "Syncing…")
        case .offline: String(localized: "Offline")
        case .failed(let message): message
        }
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        do {
            joinMessage = switch try await store.joinClass(code: classCode) {
            case .joined: String(localized: "Welcome to the class!")
            case .alreadyJoined: String(localized: "You're already a member.")
            case .invalidCode: String(localized: "That code isn't right. Check it with your instructor.")
            case .rateLimited: String(localized: "Too many attempts. Try again in an hour.")
            case .notConfigured: String(localized: "Your instructor hasn't set a class code yet.")
            }
            classCode = ""
        } catch {
            joinMessage = String(localized: "Couldn't join: \(error.localizedDescription)")
        }
    }

    private func export() async {
        do {
            let data = try await store.exportMyData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("woodland-study-export.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
            exportError = nil
        } catch {
            exportError = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            var code: String?
            if !environment.isDemo {
                // A fresh Apple authorization lets the server revoke the Sign in with Apple token.
                code = try await AppleReauthentication().run().authorizationCode
            }
            try await environment.session.deleteAccount(appleAuthorizationCode: code)
        } catch {
            deleteError = String(localized: "Your account was not deleted: \(error.localizedDescription)")
        }
    }
}

/// A short, honest summary; the full policy template is in PRIVACY.md.
struct PrivacySummaryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("What this app stores").font(.woodHeadline)
                Text("• A stable account id from Sign in with Apple. No name, email or Apple ID password is requested or stored.\n• Which optional lessons you follow.\n• Your progress, exercise counts and private notes.\n• Whether you joined the class with its code.")
                Text("Who can see it").font(.woodHeadline)
                Text("Only you. Database rules prevent other students and the administrator from reading your progress and notes.")
                Text("On this device").font(.woodHeadline)
                Text("A cache of lessons, your progress and downloaded PDFs, so the app works offline. It is removed when you sign out or delete your account. Recently opened lessons are remembered on this device only.")
                Text("No tracking").font(.woodHeadline)
                Text("No advertising, analytics or tracking SDKs. Your data is never sold.")
                Text("Deleting your data").font(.woodHeadline)
                Text("Settings → Delete account removes your account and all personal data from the server immediately.")
            }
            .font(.woodBody)
            .padding()
        }
        .background(Palette.page)
        .navigationTitle("Privacy")
    }
}
