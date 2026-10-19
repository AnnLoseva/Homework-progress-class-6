//
//  Schema.swift
//  Homework progress
//
//  The iCloud private database keeps iPhone and iPad in sync; SwiftData is the on-device store,
//  so everything keeps working offline and changes upload when the network is back. If CloudKit
//  can't be opened (signed out, no entitlement), the app falls back to a local store at the same
//  location — existing data is never deleted to do it.
//

import Foundation
import SwiftData

enum PersistenceFactory {
    static let cloudContainerID = "iCloud.AnnaLoseva.Homework-progress"

    static let models: [any PersistentModel.Type] = [
        Course.self,
        AcademicWeek.self,
        HomeworkAssignment.self,
        HomeworkAttachment.self,
        NotabilityNotebookAssociation.self,
    ]

    static var schema: Schema { Schema(models) }

    enum StoreKind: Equatable {
        case iCloud
        case localOnly
        case inMemory
    }

    /// Test and preview containers. Always local: `cloudKitDatabase` must be `.none` explicitly,
    /// because the default (`.automatic`) would try to sync as soon as the app has iCloud entitlements.
    static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// The app's container: iCloud-synced when possible, otherwise local.
    static func makeAppContainer(ephemeral: Bool) throws -> (ModelContainer, StoreKind) {
        if ephemeral { return (try makeContainer(inMemory: true), .inMemory) }
        let runningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !runningUnitTests {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return (container, .iCloud)
            }
        }
        return (try makeContainer(), .localOnly)
    }
}
