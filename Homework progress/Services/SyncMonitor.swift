//
//  SyncMonitor.swift
//  Homework progress
//
//  Reports whether iCloud sync is active and when it last ran, and triggers housekeeping when
//  changes arrive from the other device. Purely informational: the app works the same offline.
//

import CloudKit
import CoreData
import Foundation
import Observation

@Observable
final class SyncMonitor {
    enum Status: Equatable {
        case checking
        /// iCloud store open and the account is available.
        case active
        /// Signed out of iCloud (or iCloud Drive off): changes stay on this device until sign-in.
        case signedOut
        /// The iCloud store couldn't be opened; data is stored on this device only.
        case localOnly
        /// UI tests / demo data.
        case disabled
    }

    private(set) var status: Status = .checking
    private(set) var lastSync: Date?
    private(set) var lastError: String?

    let storeKind: PersistenceFactory.StoreKind
    private var observers: [NSObjectProtocol] = []
    private var pendingMaintenance: Task<Void, Never>?
    private let onRemoteChange: () -> Void

    init(storeKind: PersistenceFactory.StoreKind, onRemoteChange: @escaping () -> Void) {
        self.storeKind = storeKind
        self.onRemoteChange = onRemoteChange
        switch storeKind {
        case .iCloud: startObserving()
        case .localOnly: status = .localOnly
        case .inMemory: status = .disabled
        }
    }

    func refreshAccountStatus() async {
        guard storeKind == .iCloud else { return }
        do {
            let account = try await CKContainer(identifier: PersistenceFactory.cloudContainerID).accountStatus()
            status = account == .available ? .active : .signedOut
        } catch {
            status = .signedOut
        }
    }

    private func startObserving() {
        let center = NotificationCenter.default
        // Import/export events from the CloudKit mirror behind SwiftData.
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, let endDate = event.endDate else { return }
            MainActor.assumeIsolated {
                if event.succeeded {
                    self?.lastSync = endDate
                    self?.lastError = nil
                    if event.type == .import { self?.scheduleMaintenance() }
                } else if let error = event.error {
                    self?.lastError = error.localizedDescription
                }
            }
        })
        // Fires when another device's changes were merged into the local store.
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleMaintenance() }
        })
    }

    /// Coalesces bursts of import notifications into one housekeeping pass.
    private func scheduleMaintenance() {
        pendingMaintenance?.cancel()
        pendingMaintenance = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.onRemoteChange()
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
