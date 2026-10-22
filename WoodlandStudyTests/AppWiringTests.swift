import Foundation
import Testing
@testable import WoodlandStudy
import StudyData
import StudyDomain

@MainActor
@Suite("App wiring")
struct AppWiringTests {
    @Test func withoutConfigurationTheAppRunsTheDemo() {
        let environment = AppEnvironment(arguments: [], info: [:])
        #expect(environment.mode == .demo(admin: false))
        #expect(environment.configurationProblem == nil)
    }

    @Test func aSecretKeyIsRefusedAndReported() {
        let environment = AppEnvironment(arguments: [], info: [
            "SUPABASE_URL": "https://abcdefghijklmnop.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_secret_x",
        ])
        #expect(environment.isDemo)
        #expect(environment.configurationProblem == .secretKeyInClient)
    }

    @Test func aValidConfigurationUsesSupabase() {
        let environment = AppEnvironment(arguments: [], info: [
            "SUPABASE_URL": "https://abcdefghijklmnop.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_example",
        ])
        #expect(environment.mode == .supabase)
    }

    @Test func demoStudentGetsStudentScreensOnly() async {
        let environment = AppEnvironment(arguments: ["-demo"], info: [:])
        await environment.session.signIn(with: AppleIDCredential(identityToken: "demo", rawNonce: "demo", appleUserID: "demo"))
        await environment.sessionChanged()
        #expect(environment.student?.catalog.lessons.isEmpty == false)
        #expect(environment.admin == nil, "admin screens need the server's admin role")
    }

    @Test func demoAdministratorGetsContentManagement() async {
        let environment = AppEnvironment(arguments: ["-demoAdmin"], info: [:])
        await environment.session.signIn(with: AppleIDCredential(identityToken: "demo", rawNonce: "demo", appleUserID: "demo"))
        await environment.sessionChanged()
        #expect(environment.admin != nil)
    }

    @Test func signingOutTearsDownTheUserStores() async {
        let environment = AppEnvironment(arguments: ["-demo"], info: [:])
        await environment.session.signIn(with: AppleIDCredential(identityToken: "demo", rawNonce: "demo", appleUserID: "demo"))
        await environment.sessionChanged()
        await environment.session.signOut()
        await environment.sessionChanged()
        #expect(environment.student == nil)
        #expect(environment.attachments == nil)
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

    @Test @MainActor func suggestedClassCodesAreReadable() {
        let code = ClassCodeView.randomCode()
        #expect(code.count == 14)
        #expect(!code.contains("0") && !code.contains("O") && !code.contains("1") && !code.contains("I"))
    }
}
