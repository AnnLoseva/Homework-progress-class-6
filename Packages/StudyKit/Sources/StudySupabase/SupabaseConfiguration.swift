import Foundation

/// The two values the app needs to reach a Supabase project. Both are public by design:
/// the publishable (anon) key only identifies the project, and RLS protects the data.
public struct SupabaseConfiguration: Equatable, Sendable {
    public var url: URL
    public var publishableKey: String

    public enum Problem: Error, Equatable, Sendable {
        case missing
        case placeholder
        case invalidURL
        /// A service-role / secret key must never ship in an app. Refuse to start with one.
        case secretKeyInClient
    }

    public init(url: URL, publishableKey: String) throws {
        try Self.check(url: url, key: publishableKey)
        self.url = url
        self.publishableKey = publishableKey
    }

    /// Reads `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from Info.plist (filled from
    /// Config/Supabase.xcconfig, which is git-ignored).
    public static func fromInfoDictionary(_ info: [String: Any]) -> Result<SupabaseConfiguration, Problem> {
        guard let rawURL = (info["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (info["SUPABASE_PUBLISHABLE_KEY"] as? String)?.trimmingCharacters(in: .whitespaces),
              !rawURL.isEmpty, !key.isEmpty, !rawURL.hasPrefix("$("), !key.hasPrefix("$(")
        else { return .failure(.missing) }
        guard let url = URL(string: rawURL) else { return .failure(.invalidURL) }
        do {
            return .success(try SupabaseConfiguration(url: url, publishableKey: key))
        } catch let problem as Problem {
            return .failure(problem)
        } catch {
            return .failure(.missing)
        }
    }

    static func check(url: URL, key: String) throws {
        let placeholders = ["your-project", "YOUR_", "replace-me", "<", "example.supabase.co"]
        if placeholders.contains(where: { url.absoluteString.contains($0) || key.contains($0) }) {
            throw Problem.placeholder
        }
        guard let scheme = url.scheme, ["https", "http"].contains(scheme), url.host != nil else {
            throw Problem.invalidURL
        }
        // Plain HTTP is only acceptable for a local `supabase start` stack.
        if scheme == "http", !["127.0.0.1", "localhost"].contains(url.host ?? "") {
            throw Problem.invalidURL
        }
        if isSecretKey(key) { throw Problem.secretKeyInClient }
    }

    /// New-style secret keys start with `sb_secret_`; legacy keys are JWTs whose payload has
    /// `"role": "service_role"`.
    static func isSecretKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return true }
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (json["role"] as? String) == "service_role"
    }
}
