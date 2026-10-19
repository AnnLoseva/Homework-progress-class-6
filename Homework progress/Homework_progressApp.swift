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
            let container = try PersistenceFactory.makeContainer(inMemory: isEphemeral)
            let defaults = isEphemeral ? (UserDefaults(suiteName: "ephemeral-\(UUID().uuidString)") ?? .standard) : .standard
            try CourseSeeder.seedIfNeeded(context: container.mainContext, defaults: defaults)
            CourseSeeder.upgradeSeededIcons(context: container.mainContext)
            let files = AttachmentFileStore.appDefault()
            files.clearHandoffCopies()
            #if DEBUG
            if wantsDemo { DemoData.populate(container.mainContext, files: files) }
            #endif
            state = .ready(container, AppServices(files: files))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// App-wide services shared through the environment.
@Observable
final class AppServices {
    let files: AttachmentFileStore
    let router = AppRouter()
    /// A transient, non-blocking message ("Sent to Notability…").
    var toast: String?

    init(files: AttachmentFileStore) {
        self.files = files
    }

    func store(_ context: ModelContext) -> HomeworkStore {
        HomeworkStore(context: context, files: files)
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
