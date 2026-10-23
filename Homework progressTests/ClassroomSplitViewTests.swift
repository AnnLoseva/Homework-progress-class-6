//
//  ClassroomSplitViewTests.swift
//  Homework progressTests
//
//  The iPad shows the Class area inside the app's NavigationSplitView. SwiftUI hoists a
//  pushed screen's `.searchable` to the split view, so the class stores must be in the
//  environment above it. These tests render the screens in a real window; a missing store
//  crashes the test process.
//

import SwiftUI
import Testing
import UIKit
@testable import ClassroomUI
import StudyData
import StudyDomain

@MainActor
@Suite("Class screens inside the iPad split view")
struct ClassroomSplitViewTests {
    func makeEnvironment() async -> ClassroomEnvironment {
        let userID = UUID()
        let server = InMemoryServer(catalog: Catalog(), files: [:])
        let auth = InMemoryAuthService(server: server, userID: userID, isAdmin: true, startSignedIn: true)
        let environment = ClassroomEnvironment(
            mode: .supabase, problem: nil, auth: auth, credentialChecker: nil, appleUserIDStore: InMemoryAppleIDStore(),
            studentBackend: { InMemoryConnection(server: server, userID: $0) },
            adminBackend: { InMemoryConnection(server: server, userID: $0) },
            snapshotDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("SplitView-\(UUID().uuidString)"))
        await environment.start()
        await environment.sessionChanged()
        return environment
    }

    func render(_ view: some View) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        for _ in 0..<10 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(window.rootViewController?.view.subviews.isEmpty == false)
        window.isHidden = true
    }

    @Test(arguments: ClassroomSection.allCases)
    func everySectionRenders(section: ClassroomSection) async throws {
        let environment = await makeEnvironment()
        #expect(environment.admin != nil)
        try await render(
            NavigationSplitView { List { Text("Sidebar") } } detail: { ClassroomDetailView(section: section) }
                .classroomLifecycle(environment))
    }

    /// "Browse lessons" on Class Home pushes the searchable catalog (it used to crash).
    @Test func browsingLessonsFromClassHomeRenders() async throws {
        let environment = await makeEnvironment()
        try await render(PushedCatalog().classroomLifecycle(environment))
    }

    private struct PushedCatalog: View {
        @Environment(ClassroomEnvironment.self) private var environment
        @State private var path = NavigationPath([CatalogLink()])

        var body: some View {
            NavigationSplitView {
                List { Text("Sidebar") }
            } detail: {
                NavigationStack(path: $path) { HomeView() }
            }
        }
    }
}
