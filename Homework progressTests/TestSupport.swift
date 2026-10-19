//
//  TestSupport.swift
//  Homework progressTests
//

import Foundation
import SwiftData
import UIKit
@testable import Homework_progress

@MainActor
final class TestEnvironment {
    let container: ModelContainer
    let context: ModelContext
    let files: AttachmentFileStore
    let root: URL
    let defaults: UserDefaults

    init(storeURL: URL? = nil, root: URL? = nil) throws {
        let root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("HPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        container = try storeURL.map { try PersistenceFactory.makeContainer(storeURL: $0) }
            ?? PersistenceFactory.makeContainer(inMemory: true)
        context = container.mainContext
        files = AttachmentFileStore(directory: root.appendingPathComponent("Attachments"),
                                    handoffDirectory: root.appendingPathComponent("Handoff"))
        defaults = UserDefaults(suiteName: "HPTests-\(UUID().uuidString)")!
    }

    var store: HomeworkStore { HomeworkStore(context: context, files: files) }

    func seed() throws -> [Course] {
        try CourseSeeder.seedIfNeeded(context: context, defaults: defaults)
        return try context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    /// Writes a real PDF with `pages` pages and returns its URL.
    func makePDF(named name: String = "Sheet.pdf", pages: Int = 2) throws -> URL {
        let folder = root.appendingPathComponent("Source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 280))
        try renderer.writePDF(to: url) { context in
            for page in 1...pages {
                context.beginPage()
                ("Exercise page \(page)" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
            }
        }
        return url
    }

    func makeTextFile(named name: String = "notes.pdf") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("not a pdf".utf8).write(to: url)
        return url
    }

    func attachmentFileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: files.directory.path).count) ?? 0
    }
}

func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    return Calendar.current.date(from: components)!
}
