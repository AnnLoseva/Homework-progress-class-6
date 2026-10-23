import Foundation
import Testing
@testable import ClassroomUI
import StudyData
import StudyDomain

@MainActor
@Suite("Class wiring")
struct ClassWiringTests {
    @Test func withoutConfigurationClassLessonsAreOffAndSignedOut() async {
        let environment = ClassroomEnvironment(info: [:])
        #expect(environment.mode == .notConfigured)
        #expect(environment.configurationProblem == nil)
        await environment.start()
        #expect(environment.session.state == .signedOut, "nothing to restore, and no sample content")
        await environment.session.signIn(with: AppleIDCredential(identityToken: "t", rawNonce: "n", appleUserID: "a"))
        #expect(environment.session.currentUserID == nil)
    }

    @Test func aSecretKeyIsRefusedAndReported() {
        let environment = ClassroomEnvironment(info: [
            "SUPABASE_URL": "https://abcdefghijklmnop.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_secret_x",
        ])
        #expect(environment.mode == .notConfigured)
        #expect(environment.configurationProblem == .secretKeyInClient)
    }

    @Test func aValidConfigurationUsesSupabase() {
        let environment = ClassroomEnvironment(info: [
            "SUPABASE_URL": "https://abcdefghijklmnop.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_example",
        ])
        #expect(environment.mode == .supabase)
    }

    @Test func aStudentGetsStudentSectionsOnly() async {
        let environment = await makeEnvironment(isAdmin: false)
        await environment.session.signIn(with: credential)
        await environment.sessionChanged()
        #expect(environment.student != nil)
        #expect(environment.admin == nil, "admin screens need the server's admin role")
        #expect(!ClassroomSection.visible(in: environment).contains(.manage))
    }

    @Test func anAdministratorGetsContentManagement() async {
        let environment = await makeEnvironment(isAdmin: true)
        await environment.session.signIn(with: credential)
        await environment.sessionChanged()
        #expect(environment.admin != nil)
        #expect(ClassroomSection.visible(in: environment).contains(.manage))
    }

    @Test func signingOutTearsDownTheUserStores() async {
        let environment = await makeEnvironment(isAdmin: false)
        await environment.session.signIn(with: credential)
        await environment.sessionChanged()
        await environment.session.signOut()
        await environment.sessionChanged()
        #expect(environment.student == nil)
        #expect(environment.attachments == nil)
    }

    private let credential = AppleIDCredential(identityToken: "t", rawNonce: "n", appleUserID: "a")

    private func makeEnvironment(isAdmin: Bool) async -> ClassroomEnvironment {
        let userID = UUID()
        let server = InMemoryServer(catalog: Catalog(), files: [:])
        let auth = InMemoryAuthService(server: server, userID: userID, isAdmin: isAdmin, startSignedIn: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClassroomUITests-\(UUID().uuidString)")
        return ClassroomEnvironment(mode: .supabase, problem: nil, auth: auth, credentialChecker: nil,
                                    appleUserIDStore: InMemoryAppleIDStore(),
                                    studentBackend: { InMemoryConnection(server: server, userID: $0) },
                                    adminBackend: { InMemoryConnection(server: server, userID: $0) },
                                    snapshotDirectory: directory)
    }
}

@Suite("Sign in with Apple helpers")
struct AppleSignInTests {
    @Test func noncesAreRandomAndURLSafe() {
        let a = AppleNonce.make(), b = AppleNonce.make()
        #expect(a.count == 32)
        #expect(a != b)
        #expect(a.allSatisfy { $0.isLetter || $0.isNumber || "-._".contains($0) })
    }

    @Test func nonceHashIsSHA256Hex() {
        #expect(AppleNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func suggestedClassCodesAreReadable() {
        let code = ClassCodeView.randomCode()
        #expect(code.count == 14)
        #expect(!code.contains("0") && !code.contains("O") && !code.contains("1") && !code.contains("I"))
    }
}
