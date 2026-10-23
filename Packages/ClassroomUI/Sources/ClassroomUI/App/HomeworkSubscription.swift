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

    public var isOn: Bool {
        didSet { if isOn != oldValue { settings.set(isOn, forKey: Self.defaultsKey) } }
    }

    /// Class courses whose lessons are not copied.
    public private(set) var skippedCourses: Set<UUID>

    /// What the last pass did, e.g. "Added 3 class lessons to your weeks."
    public var status: String?

    @ObservationIgnored public let settings: SyncedSettings
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// Where the importer keeps what it has already copied (shared with the other devices too).
    public var defaults: UserDefaults { settings.local }

    public init(settings: SyncedSettings) {
        self.settings = settings
        isOn = settings.bool(forKey: Self.defaultsKey)
        skippedCourses = settings.ids(forKey: Self.skippedCoursesKey)
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
    }

    /// Picks up a change made on another device.
    public func reload() {
        let on = settings.bool(forKey: Self.defaultsKey)
        if on != isOn { isOn = on }
        let skipped = settings.ids(forKey: Self.skippedCoursesKey)
        if skipped != skippedCourses { skippedCourses = skipped }
    }
}
