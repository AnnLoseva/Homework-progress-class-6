import AuthenticationServices
import CryptoKit
import Foundation
import Security
import StudyData

/// Nonce for Sign in with Apple: Apple receives the SHA-256, Supabase receives the raw value
/// and checks they match, so a stolen ID token can't be replayed.
enum AppleNonce {
    static func make(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "Secure random generator unavailable")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleIDCredential {
    /// Extracts what the app needs from Apple's credential. Name and email are not requested
    /// and not stored.
    init?(_ credential: ASAuthorizationAppleIDCredential, rawNonce: String) {
        guard let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else { return nil }
        self.init(identityToken: token, rawNonce: rawNonce, appleUserID: credential.user,
                  authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) })
    }
}

/// Checks whether the user revoked this app in Settings → Apple ID → Sign in with Apple.
struct SystemAppleCredentialChecker: AppleCredentialChecker {
    func isRevoked(appleUserID: String) async -> Bool {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserID) { state, _ in
                // `.notFound` also happens on simulators; only an explicit revocation signs out.
                continuation.resume(returning: state == .revoked)
            }
        }
    }
}

/// Keeps Apple's opaque user identifier in the Keychain (this device only).
struct KeychainAppleUserIDStore: AppleUserIDStore {
    private let service = "woodland-study.apple-user-id"

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ id: String?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let id else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(id.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }
}

/// Runs a Sign in with Apple request outside of the SwiftUI button, used to get a fresh
/// authorization code before deleting the account (so the Apple token can be revoked).
@MainActor
final class AppleReauthentication: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleIDCredential, Error>?
    private var rawNonce = ""

    func run() async throws -> AppleIDCredential {
        rawNonce = AppleNonce.make()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = AppleNonce.sha256(rawNonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
               let credential = AppleIDCredential(apple, rawNonce: rawNonce) {
                continuation?.resume(returning: credential)
            } else {
                continuation?.resume(throwing: ASAuthorizationError(.failed))
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
