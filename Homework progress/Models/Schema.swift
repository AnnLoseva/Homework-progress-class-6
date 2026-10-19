//
//  Schema.swift
//  Homework progress
//

import Foundation
import SwiftData

enum HomeworkSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Course.self,
            AcademicWeek.self,
            HomeworkAssignment.self,
            HomeworkAttachment.self,
            NotabilityNotebookAssociation.self,
        ]
    }
}

/// Add new schema versions and migration stages here; never edit V1 in place.
enum HomeworkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HomeworkSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum PersistenceFactory {
    /// Creates the app's container. Pass `storeURL` for tests; `inMemory` for previews and UI tests.
    static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: HomeworkSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, migrationPlan: HomeworkMigrationPlan.self, configurations: [configuration])
    }
}
