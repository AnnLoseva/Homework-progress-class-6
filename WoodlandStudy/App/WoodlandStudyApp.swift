import SwiftUI

@main
struct WoodlandStudyApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .woodChrome()
                .task {
                    environment.startNetworkMonitoring()
                    await environment.session.restore()
                }
                .onChange(of: environment.session.currentUserID) {
                    Task { await environment.sessionChanged() }
                }
                .onChange(of: environment.student?.identity) {
                    environment.refreshAdminAccess()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Pull other devices' changes whenever the app comes back to the foreground.
                    if phase == .active { Task { await environment.student?.sync() } }
                }
        }
    }
}
