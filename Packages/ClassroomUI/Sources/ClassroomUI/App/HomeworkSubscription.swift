import Foundation
import Observation

/// "Subscribe to class": while it's on, the host app copies every published class lesson,
/// required and optional, into the user's homework weeks. The Class area only shows the switch
/// and the result; the copying happens in the app, which owns the homework data.
@MainActor
@Observable
public final class HomeworkSubscription {
    public static let defaultsKey = "classroom.homeworkSubscription"

    public var isOn: Bool {
        didSet { defaults.set(isOn, forKey: Self.defaultsKey) }
    }

    /// What the last pass did, e.g. "Added 3 class lessons to your weeks."
    public var status: String?

    /// Stays on this device, like the other per-device preferences.
    @ObservationIgnored public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.bool(forKey: Self.defaultsKey)
    }
}
