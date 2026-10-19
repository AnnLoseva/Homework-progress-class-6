//
//  Homework_progressApp.swift
//  Homework progress
//
//  Created by Anna Loseva on 19/10/2026.
//

import SwiftUI
import CoreData

@main
struct Homework_progressApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
