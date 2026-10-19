//
//  Homework_progressApp.swift
//  Homework progress
//
//  Created by Anna Loseva on 19/10/2026.
//

import SwiftUI
import SwiftData

@main
struct Homework_progressApp: App {
    @State private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            switch bootstrap.state {
            case .ready(let container, let services):
                RootView()
                    .goblinChrome()
                    .modelContainer(container)
                    .environment(services)
                    .environment(services.router)
            case .failed(let message):
                StorageErrorView(message: message)
                    .goblinChrome()
            }
        }
    }
}

/// Creates the persistent store once. A failure shows an explanation instead of crashing, and
/// never deletes the existing store.
@Observable
final class AppBootstrap {
    enum State {
        case ready(ModelContainer, AppServices)
        case failed(String)
    }

    let state: State

    init() {
        AppChrome.apply()
        let arguments = ProcessInfo.processInfo.arguments
        var isEphemeral = arguments.contains("-uiTesting")
        #if DEBUG
        let wantsDemo = arguments.contains("-demoData")
        isEphemeral = isEphemeral || wantsDemo
        #endif
        do {
            let (container, storeKind) = try PersistenceFactory.makeAppContainer(ephemeral: isEphemeral)
            let defaults = isEphemeral ? (UserDefaults(suiteName: "ephemeral-\(UUID().uuidString)") ?? .standard) : .standard
            let context = container.mainContext
            try CourseSeeder.seedIfNeeded(context: context, defaults: defaults,
                                          sharedFlag: storeKind == .iCloud ? UbiquitousSeedFlag() : nil)
            CourseSeeder.upgradeSeededIcons(context: context)
            let files = AttachmentFileStore.appDefault()
            files.clearHandoffCopies()
            #if DEBUG
            if wantsDemo { DemoData.populate(context, files: files) }
            #endif
            let maintenance = SyncMaintenance(context: context, files: files)
            maintenance.run()
            let sync = SyncMonitor(storeKind: storeKind) { maintenance.run() }
            state = .ready(container, AppServices(files: files, sync: sync))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// App-wide services shared through the environment.
@Observable
final class AppServices {
    let files: AttachmentFileStore
    let sync: SyncMonitor
    let router = AppRouter()
    /// A transient, non-blocking message ("Sent to Notability…").
    var toast: String?

    init(files: AttachmentFileStore, sync: SyncMonitor) {
        self.files = files
        self.sync = sync
    }

    func store(_ context: ModelContext) -> HomeworkStore {
        HomeworkStore(context: context, files: files)
    }

    /// True when this device has (or could recreate) the PDF file — e.g. one that just synced
    /// from the other device arrives as data and is written to a local file on first use.
    func hasLocalFile(_ attachment: HomeworkAttachment) -> Bool {
        files.ensureLocalFile(storedFilename: attachment.storedFilename) { attachment.pdfData }
    }

    func show(_ message: String?) {
        guard let message else { return }
        toast = message
    }
}

struct StorageErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Your homework couldn’t be loaded", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Your data has not been deleted. Try restarting the app or freeing up storage.\n\n\(message)")
        }
    }
}
