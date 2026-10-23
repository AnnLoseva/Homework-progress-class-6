import Foundation
import Observation

/// "Subscribe to class": while it's on, the host app copies the published lessons of every
/// subscribed class course, required and optional, into the user's homework weeks. The Class
/// area only shows the switches and the result; the copying happens in the app, which owns
/// the homework data.
///
/// The switch and the course choices are shared with the user's other devices through iCloud,
/// so subscribing on the iPhone also subscribes the iPad.
@MainActor
@Observable
public final class HomeworkSubscription {
    public static let defaultsKey = "classroom.homeworkSubscription"
    /// Courses switched off. A course published later is subscribed automatically.
    public static let skippedCoursesKey = "classroom.homeworkSkippedCourses"

    /// Where the last subscription pass got to. Only `.done` means the class was reached and
    /// the weeks are up to date.
    public enum Phase: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    public var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            settings.set(isOn, forKey: Self.defaultsKey)
            if isOn { requestRefresh() } else { phase = .idle }
        }
    }

    public var phase: Phase = .idle

    /// Set when subscribing (or re-subscribing): the next pass fetches the class from the
    /// server first instead of trusting what's cached on this device.
    @ObservationIgnored public var needsRefresh = false
    /// Set when subscribing: the pass that completes shows the week the lessons went to.
    @ObservationIgnored public var revealPending = false

    /// Class courses whose lessons are not copied.
    public private(set) var skippedCourses: Set<UUID>

    /// What the last pass did, e.g. "Added 3 class lessons to your weeks.", or why it failed.
    public var status: String? {
        switch phase {
        case .idle, .working: nil
        case .done(let message), .failed(let message): message
        }
    }

    public var hasFailed: Bool { if case .failed = phase { true } else { false } }

    @ObservationIgnored public let settings: SyncedSettings
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// Where the importer keeps what it has already copied (shared with the other devices too).
    public var defaults: UserDefaults { settings.local }

    public init(settings: SyncedSettings) {
        self.settings = settings
        isOn = settings.bool(forKey: Self.defaultsKey)
        skippedCourses = settings.ids(forKey: Self.skippedCoursesKey)
        // Every launch starts with fresh class data.
        needsRefresh = isOn
        settings.cloud?.synchronize()
        observer = NotificationCenter.default.addObserver(forName: SyncedSettings.externalChange, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(settings: SyncedSettings(local: defaults, cloud: nil))
    }

    public func isSubscribed(toCourse id: UUID) -> Bool {
        !skippedCourses.contains(id)
    }

    public func setSubscribed(_ subscribed: Bool, toCourse id: UUID) {
        if subscribed { skippedCourses.remove(id) } else { skippedCourses.insert(id) }
        settings.set(skippedCourses, forKey: Self.skippedCoursesKey)
        if subscribed, isOn { requestRefresh() }
    }

    /// Subscribing again (or to another course) refreshes from the server; the copying itself
    /// is idempotent, so nothing is duplicated.
    public func requestRefresh() {
        needsRefresh = true
        revealPending = true
        phase = .working
    }

    /// Picks up a change made on another device.
    public func reload() {
        let on = settings.bool(forKey: Self.defaultsKey)
        if on != isOn { isOn = on }
        let skipped = settings.ids(forKey: Self.skippedCoursesKey)
        if skipped != skippedCourses { skippedCourses = skipped }
    }
}
