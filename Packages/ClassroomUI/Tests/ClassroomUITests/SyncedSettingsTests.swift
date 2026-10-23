import Foundation
import Testing
@testable import ClassroomUI

/// iCloud key-value storage shared by two simulated devices.
private final class FakeCloud: CloudKeyValueStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func synchronize() -> Bool { true }
}

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "SyncedSettingsTests-\(UUID().uuidString)")!
}

@MainActor
@Suite("Subscribe to class on two devices")
struct SyncedSettingsTests {
    @Test func subscribingAndCourseChoicesFollowToTheOtherDevice() {
        let cloud = FakeCloud()
        let course = UUID()
        let iPhone = HomeworkSubscription(settings: SyncedSettings(local: freshDefaults(), cloud: cloud))
        let iPad = HomeworkSubscription(settings: SyncedSettings(local: freshDefaults(), cloud: cloud))
        #expect(!iPad.isOn)

        iPhone.isOn = true
        iPhone.setSubscribed(false, toCourse: course)
        iPad.reload()                       // what the external-change notification does

        #expect(iPad.isOn)
        #expect(!iPad.isSubscribed(toCourse: course))
        #expect(iPad.isSubscribed(toCourse: UUID()), "a course published later is subscribed automatically")
    }

    @Test func aSwitchSavedBeforeICloudSyncIsKept() {
        let local = freshDefaults()
        local.set(true, forKey: HomeworkSubscription.defaultsKey)
        let subscription = HomeworkSubscription(settings: SyncedSettings(local: local, cloud: FakeCloud()))
        #expect(subscription.isOn)
    }

    @Test func growingSetsKeepBothDevicesAdditions() {
        let cloud = FakeCloud()
        let a = SyncedSettings(local: freshDefaults(), cloud: cloud)
        let b = SyncedSettings(local: freshDefaults(), cloud: cloud)
        let first = UUID(), second = UUID()
        a.add([first], forKey: "seen")
        cloud.values["seen"] = nil          // b saves over a stale copy…
        b.add([second], forKey: "seen")
        a.add([], forKey: "seen")           // …and a's next save puts its own back
        #expect(b.growingIDs(forKey: "seen") == [first, second])
    }
}
