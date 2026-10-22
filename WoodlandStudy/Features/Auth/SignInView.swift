import AuthenticationServices
import SwiftUI
import StudyData
import StudySupabase

struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @State private var rawNonce = AppleNonce.make()

    var body: some View {
        ZStack {
            ForestBackdrop()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 40)
                    Image("CatStudying")
                        .resizable().scaledToFit().frame(maxWidth: 180)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("Woodland Study").font(.woodTitle)
                        Text("Lessons, materials and your own progress, in one calm place.")
                            .font(.woodBody).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
                    }

                    if let notice = environment.session.notice {
                        NoticeView(notice: notice)
                    }
                    if let problem = environment.configurationProblem {
                        ConfigurationProblemView(problem: problem)
                    }

                    if environment.isDemo {
                        Button {
                            Task { await environment.session.signIn(with: AppleIDCredential(identityToken: "demo", rawNonce: "demo", appleUserID: "demo")) }
                        } label: {
                            Label("Explore the demo", systemImage: "leaf")
                        }
                        .buttonStyle(.woodPrimary)
                        .accessibilityIdentifier("demoSignIn")
                        Text("Demo mode uses sample lessons stored only on this device. Nothing is sent anywhere.")
                            .font(.lora(13, relativeTo: .footnote)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            rawNonce = AppleNonce.make()
                            // No name or email: the app doesn't need them.
                            request.requestedScopes = []
                            request.nonce = AppleNonce.sha256(rawNonce)
                        } onCompletion: { result in
                            handle(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 52)
                        .clipShape(Capsule())
                        .disabled(environment.session.isWorking)
                        .accessibilityIdentifier("appleSignIn")

                        Text("Your Apple ID is only used to sign you in. Your progress and notes are private to you.")
                            .font(.lora(13, relativeTo: .footnote)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
                    }

                    if environment.session.isWorking { ProgressView().accessibilityLabel(Text("Signing in")) }
                    Spacer(minLength: 20)
                }
                .padding(28)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let credential = AppleIDCredential(apple, rawNonce: rawNonce) else {
                environment.session.reportSignInFailure(String(localized: "Apple didn't return a sign-in token. Please try again."))
                return
            }
            Task { await environment.session.signIn(with: credential) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            environment.session.reportSignInFailure(error.localizedDescription)
        }
    }
}

private struct NoticeView: View {
    let notice: SessionController.Notice

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol) }
            .font(.lora(15, relativeTo: .callout))
            .woodCard(padding: 12)
            .accessibilityIdentifier("sessionNotice")
    }

    private var text: String {
        switch notice {
        case .sessionExpired: String(localized: "Your session expired. Please sign in again; changes saved on this device will sync afterwards.")
        case .appleCredentialRevoked: String(localized: "Sign in with Apple was turned off for this app, so you were signed out.")
        case .accountDeleted: String(localized: "Your account and all your data were deleted.")
        case .signedOut: String(localized: "You signed out. Data from this device was removed.")
        case .signInFailed(let message): String(localized: "Sign-in failed: \(message)")
        }
    }

    private var symbol: String {
        switch notice {
        case .signInFailed, .sessionExpired, .appleCredentialRevoked: "exclamationmark.circle"
        default: "checkmark.circle"
        }
    }
}

private struct ConfigurationProblemView: View {
    let problem: SupabaseConfiguration.Problem

    var body: some View {
        Label {
            Text(problem == .secretKeyInClient
                 ? "The app was built with a Supabase SECRET key. It refuses to use it. Put the publishable key in Config/Local.xcconfig and rotate the secret key now."
                 : "The Supabase settings in Config/Local.xcconfig look invalid, so the app is running in demo mode.")
        } icon: {
            Image(systemName: "exclamationmark.shield")
        }
        .font(.lora(14, relativeTo: .callout))
        .foregroundStyle(Palette.rust)
        .woodCard(padding: 12)
    }
}
