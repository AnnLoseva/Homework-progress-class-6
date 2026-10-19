//
//  MoodleIntegration.swift
//  Homework progress
//
//  Opens course pages in the Moodle app using its documented custom URL scheme
//  (Moodle Developer Resources → "Deep linking"):
//
//      moodlemobile://https://domain.com?redirect=https://domain.com/course/view.php?id=2
//
//  The app opens the site (asking to log in if needed) and then the redirect page; the
//  redirect must be on the same site. Branded Moodle apps use their own scheme instead of
//  `moodlemobile`, so the scheme is configurable. If no app accepts the link, the page opens
//  in the browser instead.
//

import Foundation

nonisolated enum MoodleIntegration {
    static let defaultScheme = "moodlemobile"
    static let openInAppKey = "moodle.openInApp"
    static let schemeKey = "moodle.scheme"

    /// A usable custom scheme: starts with a letter; letters, digits, "+", "-", "." only.
    /// Web schemes are rejected — they would just open the browser.
    static func validatedScheme(_ raw: String?) -> String? {
        let scheme = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "://", with: "")
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }),
              !["http", "https", "file", "javascript", "data"].contains(scheme) else { return nil }
        return scheme
    }

    /// The Moodle site root for a page URL, keeping any sub-directory install
    /// ("https://x.com/moodle/course/view.php?id=1" → "https://x.com/moodle").
    static func siteURL(for pageURL: URL) -> URL? {
        guard let scheme = pageURL.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              components.host?.isEmpty == false else { return nil }
        let path = components.path
        let markers = ["/course/", "/mod/", "/my/", "/user/", "/grade/", "/calendar/"]
        let cut = markers.compactMap { path.range(of: $0)?.lowerBound }.min()
        components.path = cut.map { String(path[..<$0]) } ?? ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// `moodlemobile://https://md.hit.ac.il?redirect=https://md.hit.ac.il/course/view.php?id=27796`
    static func appLink(for pageURL: URL, scheme: String = defaultScheme) -> URL? {
        guard let scheme = validatedScheme(scheme), let site = siteURL(for: pageURL) else { return nil }
        return URL(string: "\(scheme)://\(site.absoluteString)?redirect=\(pageURL.absoluteString)")
    }

    enum OpenOutcome: Equatable {
        case openedInApp
        /// Opened in the browser; `appUnavailable` when the app link was tried first and refused.
        case openedInBrowser(appUnavailable: Bool)
        case failed
    }

    static func open(_ pageURL: URL, preferApp: Bool, scheme: String?,
                     using open: (URL) async -> Bool) async -> OpenOutcome {
        var triedApp = false
        if preferApp, let link = appLink(for: pageURL, scheme: validatedScheme(scheme) ?? defaultScheme) {
            triedApp = true
            if await open(link) { return .openedInApp }
        }
        return await open(pageURL) ? .openedInBrowser(appUnavailable: triedApp) : .failed
    }
}
