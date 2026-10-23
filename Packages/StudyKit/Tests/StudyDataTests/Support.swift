import Foundation
@testable import StudyData
@testable import StudyDomain

/// A clock tests can move forward.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_790_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("StudyKitTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// One "device": its own cache directory and network, talking to a shared server.
@MainActor
struct Device {
    let store: StudentStore
    let network: NetworkSwitch
    let cacheDirectory: URL
    let connection: InMemoryConnection

    init(server: InMemoryServer, userID: UUID, clock: TestClock, cacheDirectory: URL = temporaryDirectory(),
         onUnauthorized: @escaping @MainActor () async -> Void = {}) {
        network = NetworkSwitch()
        connection = InMemoryConnection(server: server, userID: userID, network: network)
        self.cacheDirectory = cacheDirectory
        store = StudentStore(userID: userID, backend: connection, snapshots: SnapshotStore(directory: cacheDirectory),
                             automaticRetry: false, now: { clock.now }, onUnauthorized: onUnauthorized)
    }
}

enum Lessons {
    // Fixture ids from TestCatalog (same as supabase/tests/fixtures.sql).
    static let vectors = UUID(uuidString: "00000000-0000-4000-8000-0000000001a1")!      // required, 8 exercises
    static let determinants = UUID(uuidString: "00000000-0000-4000-8000-0000000001a3")! // optional, 12 exercises
    static let logic = UUID(uuidString: "00000000-0000-4000-8000-0000000001b1")!        // required, 6 exercises
    static let puzzles = UUID(uuidString: "00000000-0000-4000-8000-0000000001b2")!      // optional, no exercises
    static let archived = UUID(uuidString: "00000000-0000-4000-8000-0000000001c2")!
    static let draft = UUID(uuidString: "00000000-0000-4000-8000-0000000001d1")!
}

func makeServer(clock: TestClock, students: [UUID] = [], admins: [UUID] = [], enrolled: Bool = true) async -> InMemoryServer {
    let (catalog, files) = TestCatalog.make(now: clock.now)
    let server = InMemoryServer(catalog: catalog, files: files, now: { clock.now })
    for id in students { await server.addUser(id, isEnrolled: enrolled) }
    for id in admins { await server.addUser(id, isAdmin: true) }
    return server
}

/// Thread-safe call recorder for fakes.
final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []
    func append(_ value: Value) { lock.withLock { storage.append(value) } }
    var values: [Value] { lock.withLock { storage } }
}
