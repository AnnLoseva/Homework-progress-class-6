import Foundation

/// iCloud key-value storage, or a stand-in for it in tests.
public protocol CloudKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {}

/// Small settings that follow the user to their other devices (same Apple ID) through iCloud
/// key-value storage. Each value is also kept in UserDefaults, so everything works the same
/// signed out of iCloud, and settings saved before this existed are carried over.
public struct SyncedSettings {
    public let local: UserDefaults
    public let cloud: (any CloudKeyValueStore)?

    public init(local: UserDefaults, cloud: (any CloudKeyValueStore)?) {
        self.local = local
        self.cloud = cloud
    }

    /// Posted when another device changed a value.
    public static var externalChange: Notification.Name { NSUbiquitousKeyValueStore.didChangeExternallyNotification }

    /// The newest value from either place; iCloud wins once it has one.
    public func bool(forKey key: String) -> Bool {
        (cloud?.object(forKey: key) as? Bool) ?? local.bool(forKey: key)
    }

    public func set(_ value: Bool, forKey key: String) {
        local.set(value, forKey: key)
        cloud?.set(value, forKey: key)
    }

    /// A set the user changes both ways (e.g. courses switched off): the last device to save wins.
    public func ids(forKey key: String) -> Set<UUID> {
        Self.decode(cloud?.object(forKey: key)) ?? Self.decode(local.object(forKey: key)) ?? []
    }

    public func set(_ ids: Set<UUID>, forKey key: String) {
        let value = Self.encode(ids)
        local.set(value, forKey: key)
        cloud?.set(value, forKey: key)
    }

    /// A set that only ever grows (e.g. lessons already copied): both devices' additions are
    /// kept, whichever saved last.
    public func growingIDs(forKey key: String) -> Set<UUID> {
        (Self.decode(local.object(forKey: key)) ?? []).union(Self.decode(cloud?.object(forKey: key)) ?? [])
    }

    public func add(_ ids: Set<UUID>, forKey key: String) {
        set(growingIDs(forKey: key).union(ids), forKey: key)
    }

    private static func decode(_ value: Any?) -> Set<UUID>? {
        (value as? [String]).map { Set($0.compactMap(UUID.init(uuidString:))) }
    }

    private static func encode(_ ids: Set<UUID>) -> [String] {
        ids.map(\.uuidString).sorted()
    }
}
