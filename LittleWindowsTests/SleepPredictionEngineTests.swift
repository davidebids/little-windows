import CloudKit
import CoreData
import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import LittleWindows

final class SleepPredictionEngineTests: XCTestCase {
    func testManualCloudKitDevelopmentSchemaInitialization() throws {
        let environment = ProcessInfo.processInfo.environment
        guard Self.smokeConfigurationValue(
            "LW_CLOUDKIT_SCHEMA_INIT",
            environment: environment
        ) == "1" else {
            throw XCTSkip(
                "Set LW_CLOUDKIT_SCHEMA_INIT=1 to initialize the CloudKit development schema."
            )
        }

        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LittleWindowsCloudKitSchema", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let storeURL = storeDirectory.appendingPathComponent("Schema.sqlite")

        let configuration = ModelConfiguration(
            "CloudKitSchemaInitialization",
            schema: PersistenceService.schema,
            url: storeURL,
            cloudKitDatabase: .private(PersistenceService.iCloudContainerIdentifier)
        )
        let description = NSPersistentStoreDescription(url: configuration.url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: PersistenceService.iCloudContainerIdentifier
        )
        description.shouldAddStoreAsynchronously = false

        guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(
            for: PersistenceService.modelTypes
        ) else {
            XCTFail("Could not create the Core Data model used for CloudKit schema initialization.")
            return
        }

        let container = NSPersistentCloudKitContainer(
            name: "LittleWindowsCloudKitSchema",
            managedObjectModel: managedObjectModel
        )
        container.persistentStoreDescriptions = [description]

        var persistentStoreLoadError: Error?
        container.loadPersistentStores { _, error in
            persistentStoreLoadError = error
        }
        if let persistentStoreLoadError {
            throw persistentStoreLoadError
        }

        try container.initializeCloudKitSchema()

        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }
        print("LW_CLOUDKIT_SCHEMA_INIT initialized development schema")
    }

    func testManualWeatherKitSmoke() async throws {
        guard Self.smokeConfigurationValue(
            "LW_WEATHERKIT_SMOKE",
            environment: ProcessInfo.processInfo.environment
        ) == "1" else {
            throw XCTSkip("Set LW_WEATHERKIT_SMOKE=1 to run the signed WeatherKit service smoke test.")
        }

        let client = LiveTripWeatherForecastClient()
        let days = try await client.dailyForecast(
            latitude: 37.3349,
            longitude: -122.0090
        )
        let attribution = try await client.attribution()

        XCTAssertFalse(days.isEmpty)
        XCTAssertEqual(attribution.legalPageURL.scheme, "https")
        XCTAssertEqual(attribution.lightMarkURL.scheme, "https")
        XCTAssertEqual(attribution.darkMarkURL.scheme, "https")
    }

    @MainActor
    func testManualCloudKitSyncSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let mode = Self.smokeConfigurationValue(
            "LW_CLOUDKIT_SYNC_SMOKE",
            environment: environment
        ) else {
            throw XCTSkip("Set LW_CLOUDKIT_SYNC_SMOKE=write or read to run the manual CloudKit sync smoke test.")
        }
        let testID = Self.smokeConfigurationValue(
            "LW_CLOUDKIT_SYNC_ID",
            environment: environment
        ) ?? UUID().uuidString
        let profileName = "CloudKit Smoke \(testID)"
        let container = CKContainer(identifier: PersistenceService.iCloudContainerIdentifier)
        let status = try await container.accountStatus()
        print("LW_CLOUDKIT_SYNC accountStatus=\(Self.description(for: status)) mode=\(mode) id=\(testID)")
        guard status == .available else {
            XCTFail("Simulator must be signed in to iCloud before sync can be tested. Status: \(Self.description(for: status))")
            return
        }

        let modelContainer = try PersistenceService.makeModelContainer()
        let context = modelContainer.mainContext
        switch mode {
        case "write":
            let profile = try fetchOrCreateSmokeProfile(named: profileName, context: context)
            let event = CareEvent(
                profileID: profile.id,
                type: .custom,
                title: "CloudKit sync smoke",
                startDate: Date(),
                endDate: Date(),
                caregiverName: "Sync Smoke"
            )
            event.notes = "Created by simulator \(environment["RUN_DESTINATION_DEVICE_NAME"] ?? "unknown")"
            context.insert(event)
            try context.save()
            PersistenceService.recordLocalSave()
            print("LW_CLOUDKIT_SYNC wrote profile=\(profile.name) profileID=\(profile.id) eventID=\(event.id)")
            try await Task.sleep(nanoseconds: 30_000_000_000)
        case "read":
            let deadline = Date().addingTimeInterval(180)
            while Date() < deadline {
                if let profile = try fetchSmokeProfile(named: profileName, context: context) {
                    let eventCount = try smokeEventCount(profileID: profile.id, context: context)
                    print("LW_CLOUDKIT_SYNC read profile=\(profile.name) profileID=\(profile.id) events=\(eventCount)")
                    XCTAssertGreaterThanOrEqual(eventCount, 1)
                    return
                }
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
            XCTFail("Timed out waiting for \(profileName) to sync to this simulator.")
        default:
            XCTFail("Unsupported LW_CLOUDKIT_SYNC_SMOKE mode: \(mode)")
        }
    }

    func testICloudSyncPreferenceDefaultsOnAndPersistsChanges() throws {
        let defaults = try makeIsolatedDefaults()

        XCTAssertTrue(PersistenceService.isICloudSyncEnabled(defaults: defaults))

        PersistenceService.setICloudSyncEnabled(false, defaults: defaults)
        XCTAssertFalse(PersistenceService.isICloudSyncEnabled(defaults: defaults))

        PersistenceService.setICloudSyncEnabled(true, defaults: defaults)
        XCTAssertTrue(PersistenceService.isICloudSyncEnabled(defaults: defaults))
    }

    func testDestructiveDataScopeUsesOpenStoreAndConfirmedFamilyRole() {
        XCTAssertEqual(
            DataMutationScope.resolve(
                isUsingCloudKitStore: true,
                startupMode: .privateICloudSync,
                currentMode: .localOnly,
                familyRole: .none
            ),
            .privateICloud
        )
        XCTAssertEqual(
            DataMutationScope.resolve(
                isUsingCloudKitStore: false,
                startupMode: .sharedFamilySync,
                currentMode: .sharedFamilySync,
                familyRole: .owner
            ),
            .sharedFamilyOwner
        )
        XCTAssertEqual(
            DataMutationScope.resolve(
                isUsingCloudKitStore: false,
                startupMode: .sharedFamilySync,
                currentMode: .sharedFamilySync,
                familyRole: .participant
            ),
            .sharedFamilyParticipant
        )
        XCTAssertFalse(DataMutationScope.sharedFamilyParticipant.allowsBulkMutation)
        XCTAssertFalse(DataMutationScope.sharedFamilyUnknownRole.allowsBulkMutation)
        XCTAssertEqual(
            DataMutationScope.resolve(
                isUsingCloudKitStore: false,
                startupMode: .sharedFamilySync,
                currentMode: .privateICloudSync,
                familyRole: .owner
            ),
            .localDevice
        )
        XCTAssertEqual(
            DataMutationScope.resolve(
                isUsingCloudKitStore: false,
                startupMode: .localOnly,
                currentMode: .privateICloudSync,
                familyRole: .none
            ),
            .localDevice
        )
    }

    func testUnreadableStoreRecoveryPreservesAllArtifactsBeforeReset() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "LittleWindowsRecoveryTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: testRoot) }

        let storeDirectory = testRoot.appendingPathComponent("Store", isDirectory: true)
        let archiveRoot = testRoot.appendingPathComponent("Archives", isDirectory: true)
        try fileManager.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let storeURL = storeDirectory.appendingPathComponent("LittleWindows.store")
        let artifacts: [(String, Data)] = [
            ("LittleWindows.store", Data("main".utf8)),
            ("LittleWindows.store-wal", Data("wal".utf8)),
            ("LittleWindows.store-shm", Data("shm".utf8))
        ]
        for (name, data) in artifacts {
            try data.write(to: storeDirectory.appendingPathComponent(name))
        }
        let supportDirectory = storeDirectory.appendingPathComponent(
            ".LittleWindows_SUPPORT",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        try Data("support".utf8).write(
            to: supportDirectory.appendingPathComponent("metadata")
        )
        let unrelatedURL = storeDirectory.appendingPathComponent("keep-me.txt")
        try Data("unrelated".utf8).write(to: unrelatedURL)

        let preservedURL = try XCTUnwrap(PersistenceService.preserveStoreArtifacts(
            at: storeURL,
            archiveRoot: archiveRoot,
            fileManager: fileManager,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        for (name, expectedData) in artifacts {
            XCTAssertFalse(fileManager.fileExists(
                atPath: storeDirectory.appendingPathComponent(name).path
            ))
            XCTAssertEqual(
                try Data(contentsOf: preservedURL.appendingPathComponent(name)),
                expectedData
            )
        }
        XCTAssertFalse(fileManager.fileExists(atPath: supportDirectory.path))
        XCTAssertEqual(
            try Data(contentsOf: preservedURL
                .appendingPathComponent(".LittleWindows_SUPPORT", isDirectory: true)
                .appendingPathComponent("metadata")),
            Data("support".utf8)
        )
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedURL.path))
    }

    @MainActor
    func testSyncStatusReportsDisabledWhenICloudSyncPreferenceIsOff() async throws {
        let defaults = try makeIsolatedDefaults()
        PersistenceService.setICloudSyncEnabled(false, defaults: defaults)
        let service = SyncStatusService(defaults: defaults)

        await service.refreshStatus()

        XCTAssertEqual(service.availability, .disabled)
        XCTAssertEqual(service.accountStatusDescription, "Off")
        XCTAssertEqual(service.containerStatusDescription, "Local only")
        XCTAssertFalse(service.isICloudAvailable)
    }

    func testFamilySyncActivityDiffPrioritizesShoppingItemChanges() throws {
        let listID = UUID()
        let itemID = UUID()
        let local = familySyncDatasetJSON(
            shoppingLists: """
            [{
              "id":"\(listID.uuidString)",
              "householdID":"\(UUID().uuidString)",
              "name":"Market List",
              "listTypeRawValue":"general",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z",
              "isArchived":false
            }]
            """,
            shoppingListItems: """
            [{
              "id":"\(itemID.uuidString)",
              "householdID":"\(UUID().uuidString)",
              "shoppingListID":"\(listID.uuidString)",
              "name":"Apples",
              "isChecked":false,
              "isRecurringStaple":false,
              "priorityRawValue":"normal",
              "addedBy":"Caregiver B",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z",
              "purchaseCount":0,
              "inventoryLinkBehaviorRawValue":"askWhenChecked"
            }]
            """
        )
        let remote = familySyncDatasetJSON(
            shoppingLists: """
            [{
              "id":"\(listID.uuidString)",
              "householdID":"\(UUID().uuidString)",
              "name":"Market List",
              "listTypeRawValue":"general",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z",
              "isArchived":false
            }]
            """,
            shoppingListItems: """
            [{
              "id":"\(itemID.uuidString)",
              "householdID":"\(UUID().uuidString)",
              "shoppingListID":"\(listID.uuidString)",
              "name":"Apples",
              "isChecked":true,
              "checkedAt":"2026-01-01T00:05:00Z",
              "isRecurringStaple":false,
              "priorityRawValue":"normal",
              "addedBy":"Caregiver B",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:05:00Z",
              "purchaseCount":0,
              "inventoryLinkBehaviorRawValue":"askWhenChecked"
            }]
            """
        )

        let notification = try XCTUnwrap(FamilySyncActivityDiff.notification(
            localData: local,
            remoteData: remote
        ))

        XCTAssertEqual(notification.title, "Shopping list updated")
        XCTAssertEqual(notification.body, "Caregiver B checked off Apples on Market List.")
        XCTAssertEqual(notification.deepLinkPath, "food/shopping/\(listID.uuidString)")
    }

    func testFamilySyncActivityDiffSummarizesHomeTodoCompletion() throws {
        let listID = UUID()
        let itemID = UUID()
        let local = familySyncDatasetJSON(
            homeTodoLists: """
            [{
              "id":"\(listID.uuidString)",
              "householdID":"\(UUID().uuidString)",
              "name":"House Tasks",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z",
              "isArchived":false
            }]
            """,
            homeTodoItems: """
            [{
              "id":"\(itemID.uuidString)",
              "householdID":"\(UUID().uuidString)",
              "todoListID":"\(listID.uuidString)",
              "title":"Replace filter",
              "isCompleted":false,
              "addedBy":"Caregiver A",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z"
            }]
            """
        )
        let remote = familySyncDatasetJSON(
            homeTodoLists: """
            [{
              "id":"\(listID.uuidString)",
              "householdID":"\(UUID().uuidString)",
              "name":"House Tasks",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z",
              "isArchived":false
            }]
            """,
            homeTodoItems: """
            [{
              "id":"\(itemID.uuidString)",
              "householdID":"\(UUID().uuidString)",
              "todoListID":"\(listID.uuidString)",
              "title":"Replace filter",
              "isCompleted":true,
              "addedBy":"Caregiver A",
              "completedBy":"Caregiver B",
              "completedAt":"2026-01-01T00:05:00Z",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:05:00Z"
            }]
            """
        )

        let notification = try XCTUnwrap(FamilySyncActivityDiff.notification(
            localData: local,
            remoteData: remote
        ))

        XCTAssertEqual(notification.title, "Home to-do updated")
        XCTAssertEqual(notification.body, "Caregiver B updated House Tasks: completed Replace filter.")
        XCTAssertEqual(notification.deepLinkPath, "food/todos/\(listID.uuidString)")
        XCTAssertEqual(notification.category, .homeTodo)
    }

    func testFamilySyncHomeTodoNotificationToggleCanSuppressOnlyTodoAlerts() throws {
        let suiteName = "FamilySyncHomeTodoNotificationToggle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(NotificationManager.familySyncActivityNotificationsEnabled(
            for: .homeTodo,
            defaults: defaults
        ))
        XCTAssertTrue(NotificationManager.familySyncActivityNotificationsEnabled(
            for: .general,
            defaults: defaults
        ))

        defaults.set(false, forKey: "familySyncHomeTodoNotificationsEnabled")
        XCTAssertFalse(NotificationManager.familySyncActivityNotificationsEnabled(
            for: .homeTodo,
            defaults: defaults
        ))
        XCTAssertTrue(NotificationManager.familySyncActivityNotificationsEnabled(
            for: .general,
            defaults: defaults
        ))

        defaults.set(false, forKey: "familySyncActivityNotificationsEnabled")
        XCTAssertFalse(NotificationManager.familySyncActivityNotificationsEnabled(
            for: .general,
            defaults: defaults
        ))
    }

    func testFamilySyncTripPackingDiffSummarizesPackedItems() throws {
        let tripID = UUID()
        let itemID = UUID()
        let trip = """
        [{
          "id":"\(tripID.uuidString)",
          "title":"Sample Trip",
          "destinationName":"Sample Destination",
          "startDate":"2026-07-10T00:00:00Z",
          "endDate":"2026-07-12T00:00:00Z",
          "statusRawValue":"upcoming",
          "createdBy":"Caregiver A",
          "createdAt":"2026-07-01T00:00:00Z",
          "updatedAt":"2026-07-01T00:00:00Z",
          "isArchived":false
        }]
        """
        let local = familySyncDatasetJSON(
            packingTrips: trip,
            packingItems: """
            [{
              "id":"\(itemID.uuidString)",
              "tripID":"\(tripID.uuidString)",
              "title":"Leash",
              "priorityRawValue":"essential",
              "stateRawValue":"needed",
              "addedBy":"Caregiver A",
              "createdAt":"2026-07-01T00:00:00Z",
              "updatedAt":"2026-07-01T00:00:00Z"
            }]
            """
        )
        let remote = familySyncDatasetJSON(
            packingTrips: trip,
            packingItems: """
            [{
              "id":"\(itemID.uuidString)",
              "tripID":"\(tripID.uuidString)",
              "title":"Leash",
              "priorityRawValue":"essential",
              "stateRawValue":"packed",
              "addedBy":"Caregiver A",
              "packedBy":"Caregiver B",
              "packedAt":"2026-07-01T00:05:00Z",
              "createdAt":"2026-07-01T00:00:00Z",
              "updatedAt":"2026-07-01T00:05:00Z"
            }]
            """
        )

        let notification = try XCTUnwrap(FamilySyncActivityDiff.notification(
            localData: local,
            remoteData: remote
        ))

        XCTAssertEqual(notification.title, "Trip packing updated")
        XCTAssertEqual(notification.body, "Caregiver B packed 1 item for Sample Trip. 0 remaining.")
        XCTAssertEqual(notification.deepLinkPath, "food/trips/\(tripID.uuidString)")
        XCTAssertEqual(notification.category, .trip)
    }

    func testFamilySyncTripPackingDiffTargetsNewAssignee() throws {
        let tripID = UUID()
        let itemID = UUID()
        let trip = """
        [{
          "id":"\(tripID.uuidString)",
          "title":"Sample Trip",
          "startDate":"2026-07-10T00:00:00Z",
          "endDate":"2026-07-12T00:00:00Z",
          "statusRawValue":"upcoming",
          "createdAt":"2026-07-01T00:00:00Z",
          "updatedAt":"2026-07-01T00:00:00Z",
          "isArchived":false
        }]
        """
        let local = familySyncDatasetJSON(
            packingTrips: trip,
            packingItems: """
            [{
              "id":"\(itemID.uuidString)",
              "tripID":"\(tripID.uuidString)",
              "title":"Travel documents",
              "priorityRawValue":"essential",
              "stateRawValue":"needed",
              "createdAt":"2026-07-01T00:00:00Z",
              "updatedAt":"2026-07-01T00:00:00Z"
            }]
            """
        )
        let remote = familySyncDatasetJSON(
            packingTrips: trip,
            packingItems: """
            [{
              "id":"\(itemID.uuidString)",
              "tripID":"\(tripID.uuidString)",
              "title":"Travel documents",
              "priorityRawValue":"essential",
              "stateRawValue":"needed",
              "assignedCaregiverName":"Caregiver B",
              "caregiverReminderEnabled":true,
              "createdAt":"2026-07-01T00:00:00Z",
              "updatedAt":"2026-07-01T00:05:00Z"
            }]
            """
        )

        let notification = try XCTUnwrap(FamilySyncActivityDiff.notification(
            localData: local,
            remoteData: remote,
            currentCaregiverName: "caregiver b"
        ))

        XCTAssertEqual(notification.title, "Packing assigned to you")
        XCTAssertEqual(notification.body, "You were assigned 1 item for Sample Trip.")
        XCTAssertEqual(notification.deepLinkPath, "food/trips/\(tripID.uuidString)")
        XCTAssertEqual(notification.category, .trip)
    }

    func testFamilySyncTripNotificationToggleCanSuppressOnlyTripAlerts() throws {
        let suiteName = "FamilySyncTripNotificationToggle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(NotificationManager.familySyncActivityNotificationsEnabled(
            for: .trip,
            defaults: defaults
        ))
        defaults.set(false, forKey: "familySyncTripNotificationsEnabled")
        XCTAssertFalse(NotificationManager.familySyncActivityNotificationsEnabled(
            for: .trip,
            defaults: defaults
        ))
        XCTAssertTrue(NotificationManager.familySyncActivityNotificationsEnabled(
            for: .general,
            defaults: defaults
        ))
    }

    func testFamilySyncHomeTodoReorderDoesNotNotifyAsContentUpdate() throws {
        let listID = UUID()
        let itemID = UUID()
        let local = familySyncDatasetJSON(
            homeTodoLists: """
            [{
              "id":"\(listID.uuidString)",
              "name":"House Tasks",
              "notes":"Weekend",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z",
              "isArchived":false,
              "sortOrder":0
            }]
            """,
            homeTodoItems: """
            [{
              "id":"\(itemID.uuidString)",
              "todoListID":"\(listID.uuidString)",
              "title":"Replace filter",
              "notes":"Hallway",
              "isCompleted":false,
              "addedBy":"Caregiver A",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z",
              "sortOrder":0
            }]
            """
        )
        let remote = familySyncDatasetJSON(
            homeTodoLists: """
            [{
              "id":"\(listID.uuidString)",
              "name":"House Tasks",
              "notes":"Weekend",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:05:00Z",
              "isArchived":false,
              "sortOrder":1
            }]
            """,
            homeTodoItems: """
            [{
              "id":"\(itemID.uuidString)",
              "todoListID":"\(listID.uuidString)",
              "title":"Replace filter",
              "notes":"Hallway",
              "isCompleted":false,
              "addedBy":"Caregiver A",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:05:00Z",
              "sortOrder":1
            }]
            """
        )

        XCTAssertNil(FamilySyncActivityDiff.notification(localData: local, remoteData: remote))
    }

    func testFamilySyncActivityDiffSummarizesSharedCareEvents() throws {
        let profileID = UUID()
        let eventID = UUID()
        let remote = familySyncDatasetJSON(
            profiles: """
            [{
              "id":"\(profileID.uuidString)",
              "name":"Sample Child",
              "birthDate":"2025-01-01T00:00:00Z",
              "sexRawValue":"unknown",
              "notes":"",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z"
            }]
            """,
            events: """
            [{
              "id":"\(eventID.uuidString)",
              "profileID":"\(profileID.uuidString)",
              "typeRawValue":"sleep",
              "startDate":"2026-01-01T00:00:00Z",
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:05:00Z",
              "caregiverName":"Caregiver A",
              "sleepKindRawValue":"nap"
            }]
            """
        )

        let notification = try XCTUnwrap(FamilySyncActivityDiff.notification(
            localData: familySyncDatasetJSON(),
            remoteData: remote
        ))

        XCTAssertEqual(notification.title, "Shared care updated")
        XCTAssertEqual(notification.body, "Caregiver A added Sample Child nap sleep.")
        XCTAssertEqual(notification.deepLinkPath, "profile/\(profileID.uuidString)/history")
    }

    func testFamilySyncParticipantPushSubscriptionUsesSharedDatabaseSubscription() throws {
        let rootID = CKRecord.ID(
            recordName: "FamilyRoot",
            zoneID: CKRecordZone.ID(zoneName: "LittleWindowsFamily", ownerName: "owner")
        )

        let subscription = CloudKitSharingService.familySyncPushSubscription(
            rootRecordID: rootID,
            role: .participant,
            subscriptionID: "family-sync-participant-test"
        )

        XCTAssertTrue(subscription is CKDatabaseSubscription)
        XCTAssertFalse(subscription is CKRecordZoneSubscription)
        XCTAssertEqual(subscription.subscriptionID, "family-sync-participant-test")
        XCTAssertEqual(subscription.notificationInfo?.shouldSendContentAvailable, true)
    }

    func testFamilySyncOwnerPushSubscriptionUsesPrivateZoneSubscription() throws {
        let zoneID = CKRecordZone.ID(zoneName: "LittleWindowsFamily", ownerName: CKCurrentUserDefaultName)
        let rootID = CKRecord.ID(recordName: "FamilyRoot", zoneID: zoneID)

        let subscription = CloudKitSharingService.familySyncPushSubscription(
            rootRecordID: rootID,
            role: .owner,
            subscriptionID: "family-sync-owner-test"
        )
        let zoneSubscription = try XCTUnwrap(subscription as? CKRecordZoneSubscription)

        XCTAssertEqual(zoneSubscription.zoneID, zoneID)
        XCTAssertEqual(subscription.subscriptionID, "family-sync-owner-test")
        XCTAssertEqual(subscription.notificationInfo?.shouldSendContentAvailable, true)
    }

    func testFamilySyncEntityParentReferenceUsesCloudKitRequiredAction() {
        let rootID = CKRecord.ID(
            recordName: "FamilyRoot",
            zoneID: CKRecordZone.ID(
                zoneName: "LittleWindowsFamily",
                ownerName: CKCurrentUserDefaultName
            )
        )

        let reference = CloudKitSharingService.familyEntityParentReference(
            rootRecordID: rootID
        )

        XCTAssertEqual(reference.recordID, rootID)
        XCTAssertEqual(reference.action, .none)
    }

    func testFamilySyncUsesDistinctZoneForEachNewShare() {
        let first = CloudKitSharingService.familySyncZoneName(familyID: "first")
        let second = CloudKitSharingService.familySyncZoneName(familyID: "second")

        XCTAssertEqual(first, "LittleWindowsFamily-first")
        XCTAssertNotEqual(first, second)
    }

    func testFamilySyncInitialUploadUsesSmallSizeAwareBatches() {
        let ranges = CloudKitSharingService.familyEntityUploadBatchRanges(
            payloadSizes: [4, 4, 4, 20, 1],
            recordLimit: 2,
            byteLimit: 10
        )

        XCTAssertEqual(ranges, [0..<2, 2..<3, 3..<4, 4..<5])
        XCTAssertEqual(
            CloudKitSharingService.familyEntityUploadBatchRecordLimit,
            25
        )
        XCTAssertEqual(
            CloudKitSharingService.familyEntityUploadBatchByteLimit,
            8 * 1_024 * 1_024
        )
        XCTAssertEqual(
            CloudKitSharingService.familySnapshotAssetByteLimit,
            40 * 1_024 * 1_024
        )
    }

    func testFamilySyncEntityChangesOverlayInitialSnapshot() {
        let keep = Data("keep".utf8)
        let old = Data("old".utf8)
        let updated = Data("updated".utf8)
        let added = Data("added".utf8)

        let result = CloudKitSharingService.applyingFamilyEntityChanges(
            base: [
                "events|keep": keep,
                "events|update": old,
                "events|delete": old
            ],
            updates: [
                "events|update": updated,
                "events|new": added
            ],
            deletedKeys: ["events|delete"]
        )

        XCTAssertEqual(result["events|keep"], keep)
        XCTAssertEqual(result["events|update"], updated)
        XCTAssertEqual(result["events|new"], added)
        XCTAssertNil(result["events|delete"])
    }

    func testFamilyShareCreationProgressExplainsLongUpload() {
        XCTAssertEqual(
            FamilyShareCreationProgress.uploadingData(
                completed: 25,
                total: 80
            ).statusText,
            "Uploading family data (25 of 80)..."
        )
        XCTAssertEqual(
            FamilyShareCreationProgress.creatingShare.statusText,
            "Creating the secure iCloud share..."
        )
    }

    func testFamilySyncPushSubscriptionValidationRejectsStaleServerConfiguration() {
        let expectedRootID = CKRecord.ID(
            recordName: "FamilyRoot",
            zoneID: CKRecordZone.ID(zoneName: "LittleWindowsFamily", ownerName: "owner")
        )
        let matchingOwnerSubscription = CloudKitSharingService.familySyncPushSubscription(
            rootRecordID: expectedRootID,
            role: .owner,
            subscriptionID: "matching-owner"
        )
        let wrongZoneRootID = CKRecord.ID(
            recordName: "FamilyRoot",
            zoneID: CKRecordZone.ID(zoneName: "OtherFamily", ownerName: "owner")
        )
        let wrongZoneSubscription = CloudKitSharingService.familySyncPushSubscription(
            rootRecordID: wrongZoneRootID,
            role: .owner,
            subscriptionID: "wrong-zone"
        )
        let missingSilentPush = CKDatabaseSubscription(subscriptionID: "missing-silent-push")

        XCTAssertTrue(CloudKitSharingService.familySyncPushSubscription(
            matchingOwnerSubscription,
            matches: expectedRootID,
            role: .owner
        ))
        XCTAssertFalse(CloudKitSharingService.familySyncPushSubscription(
            wrongZoneSubscription,
            matches: expectedRootID,
            role: .owner
        ))
        XCTAssertFalse(CloudKitSharingService.familySyncPushSubscription(
            matchingOwnerSubscription,
            matches: expectedRootID,
            role: .participant
        ))
        XCTAssertFalse(CloudKitSharingService.familySyncPushSubscription(
            missingSilentPush,
            matches: expectedRootID,
            role: .participant
        ))
    }

    func testMainAppConfigurationIncludesCloudKitPushRequirements() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementsData = try Data(contentsOf: repositoryRoot
            .appendingPathComponent("LittleWindows/LittleWindows.entitlements"))
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: entitlementsData, format: nil)
                as? [String: Any]
        )
        XCTAssertEqual(entitlements["aps-environment"] as? String, "development")
        XCTAssertEqual(
            entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
            ["iCloud.com.debidia.LittleWindows"]
        )

        let infoData = try Data(contentsOf: repositoryRoot
            .appendingPathComponent("LittleWindows/Info.plist"))
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil)
                as? [String: Any]
        )
        XCTAssertTrue((info["UIBackgroundModes"] as? [String])?.contains(
            "remote-notification"
        ) == true)
    }

    func testFamilySyncUsesFastForegroundTimerPollingCadence() {
        XCTAssertEqual(
            CloudKitSharingService.foregroundTimerPollIntervalSeconds,
            5
        )
        XCTAssertEqual(CloudKitSharingService.foregroundTimerInitialDelaySeconds, 3)
        XCTAssertEqual(CloudKitSharingService.foregroundTimerFailureRetrySeconds, 30)
        XCTAssertEqual(
            (0...5).map(CloudKitSharingService.localMutationBusyRetryDelaySeconds),
            [2, 4, 8, 16, 30, 30]
        )
        XCTAssertTrue(CloudKitSharingService.foregroundPollNeedsDownload(
            remoteChecksum: "new",
            lastKnownChecksum: "old",
            pendingUpload: false
        ))
        XCTAssertFalse(CloudKitSharingService.foregroundPollNeedsDownload(
            remoteChecksum: "new",
            lastKnownChecksum: "new",
            pendingUpload: false
        ))
        XCTAssertFalse(CloudKitSharingService.foregroundPollNeedsDownload(
            remoteChecksum: "new",
            lastKnownChecksum: "old",
            pendingUpload: true
        ))
        XCTAssertTrue(FamilySyncReason.launch.usesLightweightRemoteCheck)
        XCTAssertTrue(FamilySyncReason.foregroundTimerPoll.usesLightweightRemoteCheck)
        XCTAssertFalse(FamilySyncReason.localMutation.usesLightweightRemoteCheck)
        XCTAssertFalse(FamilySyncReason.remoteNotification.usesLightweightRemoteCheck)
        XCTAssertTrue(FamilySyncReason.manual.requiresExplicitAccountCheck)
        XCTAssertFalse(FamilySyncReason.launch.requiresExplicitAccountCheck)
        XCTAssertFalse(FamilySyncReason.foregroundTimerPoll.requiresExplicitAccountCheck)
        XCTAssertTrue(FamilySyncReason.launch.ensuresPushSubscription)
        XCTAssertTrue(FamilySyncReason.manual.ensuresPushSubscription)
        XCTAssertFalse(FamilySyncReason.foregroundTimerPoll.ensuresPushSubscription)
    }

    @MainActor
    func testForegroundIntegrationReconciliationSkipsRecentUnchangedState() {
        let now = Date(timeIntervalSinceReferenceDate: 500_000)
        XCTAssertFalse(SystemIntegrationReconciler.needsForegroundReconciliation(
            lastCompletedAt: now.addingTimeInterval(-60),
            lastLocalSaveAt: now.addingTimeInterval(-120),
            now: now,
            maximumAge: 15 * 60
        ))
        XCTAssertTrue(SystemIntegrationReconciler.needsForegroundReconciliation(
            lastCompletedAt: now.addingTimeInterval(-120),
            lastLocalSaveAt: now.addingTimeInterval(-60),
            now: now,
            maximumAge: 15 * 60
        ))
        XCTAssertTrue(SystemIntegrationReconciler.needsForegroundReconciliation(
            lastCompletedAt: now.addingTimeInterval(-16 * 60),
            lastLocalSaveAt: nil,
            now: now,
            maximumAge: 15 * 60
        ))
        XCTAssertTrue(SystemIntegrationReconciler.needsForegroundReconciliation(
            lastCompletedAt: nil,
            lastLocalSaveAt: nil,
            now: now,
            maximumAge: 15 * 60
        ))
    }

    func testFamilySyncOnlyTreatsConfirmedCloudKitAccessFailuresAsTerminal() {
        XCTAssertTrue(CloudKitSharingService.isTerminalShareAccessError(code: .permissionFailure))
        XCTAssertTrue(CloudKitSharingService.isTerminalShareAccessError(code: .unknownItem))
        XCTAssertTrue(CloudKitSharingService.isTerminalShareAccessError(code: .zoneNotFound))
        XCTAssertTrue(CloudKitSharingService.isTerminalShareAccessError(code: .userDeletedZone))
        XCTAssertFalse(CloudKitSharingService.isTerminalShareAccessError(code: .networkUnavailable))
        XCTAssertFalse(CloudKitSharingService.isTerminalShareAccessError(code: .serviceUnavailable))
        XCTAssertFalse(CloudKitSharingService.isTerminalShareAccessError(code: .notAuthenticated))
    }

    @MainActor
    func testFamilySyncAccessEndedStateRequiresLocalCopyDecision() throws {
        let defaults = try makeIsolatedDefaults()
        PersistenceService.setFamilySyncMode(.privateICloudSync, defaults: defaults)
        defaults.set(
            FamilyShareInactiveReason.accessEnded.rawValue,
            forKey: CloudKitSharingService.inactiveReasonKey
        )
        defaults.set(UUID().uuidString, forKey: CloudKitSharingService.inactiveEventIDKey)
        let service = CloudKitSharingService(defaults: defaults)

        let inactiveState = service.currentState(privateSyncAvailable: true)

        XCTAssertEqual(inactiveState.status, .accessEnded)
        XCTAssertEqual(inactiveState.inactiveReason, .accessEnded)
        XCTAssertFalse(inactiveState.canCreateShare)
        XCTAssertFalse(inactiveState.canResumeShare)

        let container = try makeInMemoryContainer()
        try service.resolveInactiveShare(
            context: container.mainContext,
            deleteLocalData: false
        )
        let resolvedState = service.currentState(privateSyncAvailable: true)

        XCTAssertEqual(resolvedState.status, .readyToShare)
        XCTAssertNil(resolvedState.inactiveReason)
        XCTAssertTrue(resolvedState.canCreateShare)
    }

    @MainActor
    func testFamilySyncAccessEndedNotificationOpensSettings() {
        let content = NotificationManager.shared.buildFamilySyncAccessEndedNotificationContent(
            reason: .accessEnded
        )

        XCTAssertEqual(content.title, "Family Sync access ended")
        XCTAssertTrue(content.body.contains("downloaded data remains"))
        XCTAssertEqual(content.categoryIdentifier, NotificationManager.familySyncActivityCategoryID)
        XCTAssertEqual(
            content.userInfo["deepLink"] as? String,
            "littlewindows://settings/family-sync"
        )
    }

    @MainActor
    func testFamilySyncSettingsDeepLinkOpensRecoveryScreen() {
        let router = DeepLinkRouter.shared
        router.showingSettings = false
        router.showingFamilySyncSettings = false

        router.route(URL(string: "littlewindows://settings/family-sync")!)

        XCTAssertTrue(router.showingSettings)
        XCTAssertTrue(router.showingFamilySyncSettings)
        router.showingSettings = false
        router.showingFamilySyncSettings = false
    }

    @MainActor
    private func fetchOrCreateSmokeProfile(
        named name: String,
        context: ModelContext
    ) throws -> CareProfile {
        if let existing = try fetchSmokeProfile(named: name, context: context) {
            return existing
        }
        let profile = CareProfile(name: name, birthDate: Date(), sex: .unknown)
        context.insert(profile)
        return profile
    }

    @MainActor
    private func fetchSmokeProfile(
        named name: String,
        context: ModelContext
    ) throws -> CareProfile? {
        let descriptor = FetchDescriptor<CareProfile>(
            predicate: #Predicate<CareProfile> { profile in
                profile.name == name
            }
        )
        return try context.fetch(descriptor).first
    }

    @MainActor
    private func smokeEventCount(
        profileID: UUID,
        context: ModelContext
    ) throws -> Int {
        let descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate<CareEvent> { event in
                event.profileID == profileID
            }
        )
        return try context.fetchCount(descriptor)
    }

    private static func description(for status: CKAccountStatus) -> String {
        switch status {
        case .available: "available"
        case .noAccount: "noAccount"
        case .restricted: "restricted"
        case .couldNotDetermine: "couldNotDetermine"
        case .temporarilyUnavailable: "temporarilyUnavailable"
        @unknown default: "unknown"
        }
    }

    private static func smokeConfigurationValue(
        _ key: String,
        environment: [String: String]
    ) -> String? {
        environment[key]
            ?? UserDefaults.standard.string(forKey: key)
            ?? UserDefaults(suiteName: "com.debidia.LittleWindows")?.string(forKey: key)
    }

    private func familySyncDatasetJSON(
        profiles: String = "[]",
        events: String = "[]",
        milestones: String = "[]",
        appointments: String = "[]",
        shoppingLists: String = "[]",
        shoppingListItems: String = "[]",
        homeTodoLists: String = "[]",
        homeTodoItems: String = "[]",
        packingTrips: String = "[]",
        packingItems: String = "[]",
        inventoryItems: String = "[]",
        mealPrepItems: String = "[]",
        foodReminders: String = "[]"
    ) -> Data {
        Data("""
        {
          "version": 9,
          "exportedAt": "2026-01-01T00:00:00Z",
          "profiles": \(profiles),
          "events": \(events),
          "predictionRecords": [],
          "milestones": \(milestones),
          "appointments": \(appointments),
          "shoppingLists": \(shoppingLists),
          "shoppingListItems": \(shoppingListItems),
          "homeTodoLists": \(homeTodoLists),
          "homeTodoItems": \(homeTodoItems),
          "packingTrips": \(packingTrips),
          "packingItems": \(packingItems),
          "inventoryItems": \(inventoryItems),
          "mealPrepItems": \(mealPrepItems),
          "foodReminders": \(foodReminders)
        }
        """.utf8)
    }

    func testNursingSideIsAlwaysLeftOrRight() {
        XCTAssertEqual(NursingSide.allCases, [.left, .right])
    }

    func testOnlySleepAndCareEventsRefreshPrediction() {
        XCTAssertTrue(EventType.sleep.affectsSleepPrediction)
        XCTAssertTrue(EventType.feed.affectsSleepPrediction)
        XCTAssertTrue(EventType.nursing.affectsSleepPrediction)
        XCTAssertFalse(EventType.diaper.affectsSleepPrediction)
        XCTAssertFalse(EventType.activity.affectsSleepPrediction)
        XCTAssertFalse(EventType.medicine.affectsSleepPrediction)
        XCTAssertFalse(EventType.growth.affectsSleepPrediction)
        XCTAssertFalse(EventType.temperature.affectsSleepPrediction)
        XCTAssertFalse(EventType.custom.affectsSleepPrediction)
    }

    @MainActor
    func testSleepAndCareTimerStateChangesRefreshLittleWindowAlerts() {
        let sleep = CareEvent(type: .sleep, startDate: Date())
        let nursing = CareEvent(type: .nursing, startDate: Date())
        let diaper = CareEvent(type: .diaper, startDate: Date(), endDate: Date())

        XCTAssertTrue(EventMutationService.shouldRefreshLittleWindowAlert(after: sleep))
        XCTAssertTrue(EventMutationService.shouldRefreshLittleWindowAlert(after: nursing))
        XCTAssertFalse(EventMutationService.shouldRefreshLittleWindowAlert(after: diaper))
    }

    func testPottyIconUsesProfileContext() {
        XCTAssertEqual(EventType.potty.systemImage(for: .child), "figure.child")
        XCTAssertEqual(EventType.potty.systemImage(for: nil), "figure.child")
        XCTAssertEqual(EventType.potty.systemImage(for: .dog), "pawprint.fill")
        XCTAssertEqual(EventType.feed.systemImage(for: .child), EventType.feed.systemImage)
    }

    @MainActor
    func testLittleWindowAlertFireTimeUsesWindowStartAndLead() {
        let prediction = makeLittleWindowPrediction()
        let fireDate = NotificationManager.alertFireDate(
            prediction: prediction,
            leadMinutes: 15
        )

        XCTAssertEqual(
            fireDate,
            prediction.predictedWindowStart.addingTimeInterval(-15 * 60)
        )
    }

    @MainActor
    func testLittleWindowAlertHonorsConfidenceThreshold() {
        var prediction = makeLittleWindowPrediction()
        prediction.confidenceLabel = .low
        let settings = LittleWindowAlertSettings(
            enabled: true,
            leadMinutes: 10,
            napAlertsEnabled: true,
            bedtimeAlertsEnabled: true,
            confidenceThreshold: .medium
        )

        XCTAssertEqual(
            NotificationManager.schedulingDecision(
                prediction: prediction,
                settings: settings,
                now: Date(timeIntervalSinceReferenceDate: 1_000)
            ),
            .skip(.belowConfidenceThreshold)
        )
    }

    @MainActor
    func testLittleWindowAlertSkipsDisabledAndPastAlerts() {
        let prediction = makeLittleWindowPrediction()
        var settings = LittleWindowAlertSettings(
            enabled: false,
            leadMinutes: 10,
            napAlertsEnabled: true,
            bedtimeAlertsEnabled: true,
            confidenceThreshold: .low
        )
        XCTAssertEqual(
            NotificationManager.schedulingDecision(
                prediction: prediction,
                settings: settings,
                now: Date(timeIntervalSinceReferenceDate: 1_000)
            ),
            .skip(.alertsOff)
        )

        settings.enabled = true
        XCTAssertEqual(
            NotificationManager.schedulingDecision(
                prediction: prediction,
                settings: settings,
                now: prediction.predictedWindowStart
            ),
            .skip(.alertTimePassed)
        )
    }

    @MainActor
    func testLittleWindowAlertPausesWhileSleepingAndSchedulesAfterStopping() {
        let prediction = makeLittleWindowPrediction()
        let settings = LittleWindowAlertSettings(
            enabled: true,
            leadMinutes: 10,
            napAlertsEnabled: true,
            bedtimeAlertsEnabled: true,
            confidenceThreshold: .low
        )
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertEqual(
            NotificationManager.schedulingDecision(
                prediction: prediction,
                settings: settings,
                isSleeping: true,
                now: now
            ),
            .skip(.sleeping)
        )
        XCTAssertEqual(
            NotificationManager.schedulingDecision(
                prediction: prediction,
                settings: settings,
                isSleeping: false,
                now: now
            ),
            .schedule(prediction.predictedWindowStart.addingTimeInterval(-10 * 60))
        )
    }

    @MainActor
    func testLittleWindowAlertHonorsPredictionTypeToggles() {
        let prediction = makeLittleWindowPrediction(kind: .nap)
        let settings = LittleWindowAlertSettings(
            enabled: true,
            leadMinutes: 10,
            napAlertsEnabled: false,
            bedtimeAlertsEnabled: true,
            confidenceThreshold: .low
        )

        XCTAssertEqual(
            NotificationManager.schedulingDecision(
                prediction: prediction,
                settings: settings,
                now: Date(timeIntervalSinceReferenceDate: 1_000)
            ),
            .skip(.napAlertsOff)
        )
    }

    @MainActor
    func testLittleWindowAlertKeepsNearlyIdenticalSchedule() {
        let prediction = makeLittleWindowPrediction()
        let settings = LittleWindowAlertSettings(
            enabled: true,
            leadMinutes: 10,
            napAlertsEnabled: true,
            bedtimeAlertsEnabled: true,
            confidenceThreshold: .medium
        )
        let fireDate = NotificationManager.alertFireDate(
            prediction: prediction,
            leadMinutes: settings.leadMinutes
        )
        let state = LittleWindowNotificationState(
            lastScheduledPredictionID: "existing",
            lastScheduledPredictionStart: prediction.predictedStart.addingTimeInterval(-2 * 60),
            lastScheduledAlertTime: fireDate.addingTimeInterval(-2 * 60),
            lastScheduledKindRawValue: prediction.predictionKind.rawValue,
            lastScheduledConfidenceRawValue: prediction.confidenceLabel.rawValue,
            settingsSignature: settings.signature,
            skipReason: nil,
            lastUpdatedAt: Date()
        )

        XCTAssertTrue(
            NotificationManager.shouldKeepExistingSchedule(
                state: state,
                prediction: prediction,
                fireDate: fireDate,
                settings: settings
            )
        )
    }

    @MainActor
    func testLittleWindowNotificationCopyUsesSuggestiveLanguage() {
        let prediction = makeLittleWindowPrediction(kind: .nap)
        let copy = NotificationManager.notificationCopy(
            for: prediction,
            babyName: "Test Child",
            leadMinutes: 10
        )

        XCTAssertEqual(copy.title, "Nap window soon")
        XCTAssertTrue(copy.body.contains("estimated"))
        XCTAssertFalse(copy.body.contains("needs to"))
    }

    @MainActor
    func testProfileMigrationCreatesImportedChildAndAssignsLegacyRecords() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let legacyEvent = CareEvent(type: .feed, startDate: Date())
        let legacyMilestone = MilestoneEntry(
            title: "First smile",
            date: Date(),
            category: .social
        )
        legacyMilestone.profileID = UUID()
        context.insert(legacyEvent)
        context.insert(legacyMilestone)
        try context.save()

        ProfileMigrationService.ensureProfilesAndAssignments(context: context)

        let profiles = try context.fetch(FetchDescriptor<CareProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Imported Child")
        XCTAssertEqual(legacyEvent.profileID, profiles.first?.id)
        XCTAssertEqual(legacyMilestone.profileID, profiles.first?.id)
    }

    @MainActor
    func testProfileDuplicateRepairRemovesRepeatedIdentifierAndPreservesHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profileID = UUID()
        let birthDate = Date(timeIntervalSinceReferenceDate: 100_000)
        let original = CareProfile(
            id: profileID,
            name: "Test Child",
            birthDate: birthDate,
            sex: .unknown,
            createdAt: Date(timeIntervalSinceReferenceDate: 200_000)
        )
        let duplicate = CareProfile(
            id: profileID,
            name: "Test Child",
            birthDate: birthDate,
            sex: .unknown,
            createdAt: Date(timeIntervalSinceReferenceDate: 300_000)
        )
        let event = CareEvent(
            profileID: profileID,
            type: .feed,
            startDate: Date(timeIntervalSinceReferenceDate: 400_000)
        )
        context.insert(original)
        context.insert(duplicate)
        context.insert(event)
        try context.save()

        XCTAssertEqual(ProfileService.shared.allProfiles(in: [duplicate, original]).count, 1)
        XCTAssertEqual(ProfileDuplicateRepairService.repair(context: context), 1)

        let profiles = try context.fetch(FetchDescriptor<CareProfile>())
        let events = try context.fetch(FetchDescriptor<CareEvent>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.id, profileID)
        XCTAssertEqual(profiles.first?.createdAt, original.createdAt)
        XCTAssertEqual(events.map(\.profileID), [profileID])
    }

    @MainActor
    func testProfileDuplicateRepairRemovesNewEmptySetupShellAfterHistorySyncs() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let birthDate = Date(timeIntervalSinceReferenceDate: 100_000)
        let restoredProfile = CareProfile(
            name: "Test Child",
            birthDate: birthDate,
            sex: .unknown,
            createdAt: Date(timeIntervalSinceReferenceDate: 200_000)
        )
        let setupShell = CareProfile(
            name: "Test Child",
            birthDate: birthDate,
            sex: .unknown,
            createdAt: Date(timeIntervalSinceReferenceDate: 400_000),
            displayColor: "indigo"
        )
        context.insert(restoredProfile)
        context.insert(setupShell)
        try context.save()
        ProfileService.shared.switchProfile(setupShell)

        XCTAssertEqual(ProfileDuplicateRepairService.repair(context: context), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareProfile>()), 2)

        let restoredEvent = CareEvent(
            profileID: restoredProfile.id,
            type: .diaper,
            startDate: Date(timeIntervalSinceReferenceDate: 300_000)
        )
        context.insert(restoredEvent)
        try context.save()
        XCTAssertEqual(ProfileDuplicateRepairService.repair(context: context), 1)

        let profiles = try context.fetch(FetchDescriptor<CareProfile>())
        XCTAssertEqual(profiles.map(\.id), [restoredProfile.id])
        XCTAssertEqual(ProfileService.shared.selectedProfileID, restoredProfile.id)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CareEvent>()).map(\.profileID),
            [restoredProfile.id]
        )
    }

    @MainActor
    func testProfileDuplicateRepairPreservesMatchingProfilesWhenBothHaveHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let birthDate = Date(timeIntervalSinceReferenceDate: 100_000)
        let firstProfile = CareProfile(
            name: "Test Child",
            birthDate: birthDate,
            sex: .unknown,
            createdAt: Date(timeIntervalSinceReferenceDate: 200_000)
        )
        let secondProfile = CareProfile(
            name: "Test Child",
            birthDate: birthDate,
            sex: .unknown,
            createdAt: Date(timeIntervalSinceReferenceDate: 400_000)
        )
        context.insert(firstProfile)
        context.insert(secondProfile)
        context.insert(CareEvent(
            profileID: firstProfile.id,
            type: .feed,
            startDate: Date(timeIntervalSinceReferenceDate: 300_000)
        ))
        context.insert(CareEvent(
            profileID: secondProfile.id,
            type: .diaper,
            startDate: Date(timeIntervalSinceReferenceDate: 500_000)
        ))
        try context.save()

        XCTAssertEqual(ProfileDuplicateRepairService.repair(context: context), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareProfile>()), 2)
    }

    @MainActor
    func testProfileSelectionFallsBackToActiveChild() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testChild = CareProfile(name: "Test Child", birthDate: Date(), sex: .male)
        let sibling = CareProfile(name: "Sibling", birthDate: Date(), sex: .unknown)
        context.insert(testChild)
        context.insert(sibling)
        try context.save()

        ProfileService.shared.switchProfile(testChild)
        testChild.isArchived = true

        let selected = ProfileService.shared.ensureSelection(in: [testChild, sibling])
        XCTAssertEqual(selected?.id, sibling.id)
    }

    @MainActor
    func testArchivedProfileCanBeRestoredAndSelected() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testChild = CareProfile(name: "Test Child", birthDate: Date(), sex: .male)
        let sibling = CareProfile(name: "Sibling", birthDate: Date(), sex: .unknown)
        context.insert(testChild)
        context.insert(sibling)
        try context.save()

        ProfileService.shared.archiveProfile(
            testChild,
            profiles: [testChild, sibling],
            context: context
        )
        XCTAssertTrue(testChild.isArchived)
        XCTAssertEqual(ProfileService.shared.selectedProfile(in: [testChild, sibling])?.id, sibling.id)

        ProfileService.shared.restoreProfile(testChild, context: context)
        XCTAssertFalse(testChild.isArchived)
        XCTAssertEqual(ProfileService.shared.selectedProfile(in: [testChild, sibling])?.id, testChild.id)
    }

    @MainActor
    func testLastActiveProfileCanBeArchivedWithoutDeletingItsHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testChild = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        let event = CareEvent(
            profileID: testChild.id,
            type: .sleep,
            startDate: Date().addingTimeInterval(-120)
        )
        context.insert(testChild)
        context.insert(event)
        try context.save()
        ProfileService.shared.switchProfile(testChild)

        ProfileService.shared.archiveProfile(
            testChild,
            profiles: [testChild],
            context: context
        )

        XCTAssertTrue(testChild.isArchived)
        XCTAssertNil(ProfileService.shared.selectedProfileID)
        XCTAssertNil(ProfileService.shared.selectedProfile(in: [testChild]))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CareEvent>()).map(\.id),
            [event.id]
        )
        XCTAssertNotNil(event.endDate)
        XCTAssertFalse(event.isTimerDraft)
        XCTAssertGreaterThanOrEqual(event.duration ?? 0, 119)
    }

    @MainActor
    func testArchivingArchivedProfileIsNoOp() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testChild = CareProfile(name: "Test Child", birthDate: Date(), sex: .male)
        let sibling = CareProfile(name: "Sibling", birthDate: Date(), sex: .unknown)
        testChild.isArchived = true
        let updatedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        testChild.updatedAt = updatedAt
        context.insert(testChild)
        context.insert(sibling)
        try context.save()

        ProfileService.shared.switchProfile(sibling)
        ProfileService.shared.archiveChildProfile(
            testChild,
            profiles: [testChild, sibling],
            context: context
        )

        XCTAssertTrue(testChild.isArchived)
        XCTAssertEqual(testChild.updatedAt, updatedAt)
        XCTAssertEqual(ProfileService.shared.selectedProfileID, sibling.id)
    }

    @MainActor
    func testDeletingProfileRemovesScopedRecordsAndSelectsFallback() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testChild = CareProfile(name: "Test Child", birthDate: Date(), sex: .male)
        let sibling = CareProfile(name: "Sibling", birthDate: Date(), sex: .unknown)
        let solidEvent = CareEvent(profileID: testChild.id, type: .feed, startDate: Date())
        solidEvent.feedKind = .solid
        context.insert(testChild)
        context.insert(sibling)
        context.insert(solidEvent)
        context.insert(CareEvent(profileID: sibling.id, type: .diaper, startDate: Date()))
        context.insert(SleepPredictionRecord(
            prediction: makeLittleWindowPrediction(),
            basedOnLastSleepEventID: nil,
            profileID: testChild.id
        ))
        context.insert(MilestoneEntry(
            profileID: testChild.id,
            title: "First smile",
            date: Date(),
            category: .social
        ))
        context.insert(DoctorAppointment(
            profileID: testChild.id,
            title: "Checkup",
            startDate: Date()
        ))
        context.insert(AgeGuideReadState(profileID: testChild.id, guideID: "month-1"))
        context.insert(PuppyStageGuideReadState(profileID: testChild.id, guideID: "puppy-1"))
        context.insert(SolidsProfileState(profileID: testChild.id, isActivated: true))
        context.insert(SolidFoodProgress(
            profileID: testChild.id,
            foodID: "avocado",
            foodNameSnapshot: "Avocado"
        ))
        context.insert(SolidFoodEventItem(
            eventID: solidEvent.id,
            profileID: testChild.id,
            foodID: "avocado",
            foodNameSnapshot: "Avocado"
        ))
        context.insert(SolidAllergenProgress(
            profileID: testChild.id,
            allergenID: SolidsAllergen.egg.rawValue
        ))
        context.insert(PlannedSolidMeal(
            profileID: testChild.id,
            scheduledAt: Date(),
            foodIDs: ["avocado"],
            foodNames: ["Avocado"]
        ))
        try context.save()

        ProfileService.shared.switchProfile(testChild)
        ProfileService.shared.deleteProfile(
            testChild,
            profiles: [testChild, sibling],
            context: context
        )

        let profiles = try context.fetch(FetchDescriptor<CareProfile>())
        let events = try context.fetch(FetchDescriptor<CareEvent>())
        let predictions = try context.fetch(FetchDescriptor<SleepPredictionRecord>())
        let milestones = try context.fetch(FetchDescriptor<MilestoneEntry>())
        let appointments = try context.fetch(FetchDescriptor<DoctorAppointment>())
        let ageGuideStates = try context.fetch(FetchDescriptor<AgeGuideReadState>())
        let puppyGuideStates = try context.fetch(FetchDescriptor<PuppyStageGuideReadState>())
        let solidsProfileStates = try context.fetch(FetchDescriptor<SolidsProfileState>())
        let solidFoodProgress = try context.fetch(FetchDescriptor<SolidFoodProgress>())
        let solidFoodEventItems = try context.fetch(FetchDescriptor<SolidFoodEventItem>())
        let solidAllergenProgress = try context.fetch(FetchDescriptor<SolidAllergenProgress>())
        let plannedSolidMeals = try context.fetch(FetchDescriptor<PlannedSolidMeal>())

        XCTAssertEqual(profiles.map(\.id), [sibling.id])
        XCTAssertEqual(events.map(\.profileID), [sibling.id])
        XCTAssertTrue(predictions.isEmpty)
        XCTAssertTrue(milestones.isEmpty)
        XCTAssertTrue(appointments.isEmpty)
        XCTAssertTrue(ageGuideStates.isEmpty)
        XCTAssertTrue(puppyGuideStates.isEmpty)
        XCTAssertTrue(solidsProfileStates.isEmpty)
        XCTAssertTrue(solidFoodProgress.isEmpty)
        XCTAssertTrue(solidFoodEventItems.isEmpty)
        XCTAssertTrue(solidAllergenProgress.isEmpty)
        XCTAssertTrue(plannedSolidMeals.isEmpty)
        XCTAssertEqual(ProfileService.shared.selectedProfileID, sibling.id)
    }

    @MainActor
    func testProfileDeepLinkSwitchesBeforeRoutingAction() {
        let profileID = UUID()
        let eventID = UUID()

        DeepLinkRouter.shared.route(
            URL(string: "littlewindows://profile/\(profileID.uuidString)/action/stop/\(eventID.uuidString)")!
        )

        XCTAssertEqual(DeepLinkRouter.shared.pendingProfileID, profileID)
        XCTAssertEqual(DeepLinkRouter.shared.pendingAction, .stopTimer(eventID))
    }

    @MainActor
    func testProfileNotificationIdentifiersAndLinksAreScoped() {
        let profileID = UUID()
        let appointmentID = UUID()

        XCTAssertEqual(
            NotificationManager.scopedNotificationID(
                NotificationManager.prewindowNotificationID,
                profileID: profileID
            ),
            "profile.\(profileID.uuidString).littlewindow.next.prewindow"
        )
        XCTAssertTrue(
            NotificationManager.appointmentNotificationID(
                appointmentID: appointmentID,
                leadTime: .oneHour,
                profileID: profileID
            ).contains(profileID.uuidString)
        )
        XCTAssertEqual(
            NotificationManager.deepLink(path: "prediction", profileID: profileID),
            "littlewindows://profile/\(profileID.uuidString)/prediction"
        )
    }

    @MainActor
    func testWidgetTimerSnapshotCarriesProfileScope() {
        let profileID = UUID()
        let event = CareEvent(
            profileID: profileID,
            type: .sleep,
            startDate: Date(timeIntervalSinceReferenceDate: 1_000)
        )

        let snapshot = WidgetSnapshotService.activeSnapshot(
            event: event,
            profileID: profileID,
            babyName: "Test Child",
            additionalActiveCount: 0,
            now: Date(timeIntervalSinceReferenceDate: 1_300)
        )

        XCTAssertEqual(snapshot.profileID, profileID)
        XCTAssertEqual(snapshot.profileName, "Test Child")
        XCTAssertTrue(snapshot.stopURL.absoluteString.contains("/profile/\(profileID.uuidString)/"))
    }

    @MainActor
    func testProfileIDsRoundTripThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testChild = CareProfile(name: "Test Child", birthDate: Date(), sex: .male)
        let sibling = CareProfile(name: "Sibling", birthDate: Date(), sex: .unknown)
        context.insert(testChild)
        context.insert(sibling)
        let event = CareEvent(
            profileID: sibling.id,
            type: .diaper,
            startDate: Date(timeIntervalSinceReferenceDate: 1_000),
            startTimeZoneIdentifier: "America/New_York"
        )
        let appointment = DoctorAppointment(
            profileID: sibling.id,
            title: "Checkup",
            startDate: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        context.insert(event)
        context.insert(appointment)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let importedEvents = try context.fetch(FetchDescriptor<CareEvent>())
        let importedAppointments = try context.fetch(FetchDescriptor<DoctorAppointment>())
        XCTAssertEqual(importedEvents.first?.profileID, sibling.id)
        XCTAssertEqual(importedEvents.first?.startTimeZoneIdentifier, "America/New_York")
        XCTAssertEqual(importedAppointments.first?.profileID, sibling.id)
    }

    @MainActor
    func testInvalidBackupLeavesExistingDataUntouched() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let existingProfile = CareProfile(
            name: "Test Child",
            birthDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        context.insert(existingProfile)
        try context.save()

        let validBackup = try DataExportImportService.exportData(context: context)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validBackup) as? [String: Any]
        )
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        profiles.append(try XCTUnwrap(profiles.first))
        object["profiles"] = profiles
        let invalidBackup = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try DataExportImportService.importData(
                invalidBackup,
                context: context,
                createRecoveryBackup: false
            )
        )

        let profilesAfterFailure = try context.fetch(FetchDescriptor<CareProfile>())
        XCTAssertEqual(profilesAfterFailure.map(\.id), [existingProfile.id])
        XCTAssertEqual(profilesAfterFailure.first?.name, "Test Child")
    }

    func testTravelEventKeepsElapsedDurationAndRecordedLocalTimes() throws {
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-07-15T14:00:00Z"))
        let end = try XCTUnwrap(formatter.date(from: "2026-07-15T15:00:00Z"))
        let event = CareEvent(
            type: .sleep,
            startDate: start,
            endDate: end,
            startTimeZoneIdentifier: "America/New_York",
            endTimeZoneIdentifier: "America/Los_Angeles"
        )
        event.sleepKind = .nap

        XCTAssertEqual(event.duration, 60 * 60)
        XCTAssertEqual(event.localStartMinute(), 10 * 60)
        XCTAssertEqual(event.localEndMinute(), 8 * 60)
        XCTAssertTrue(event.spansTimeZones)

        let display = DateFormatting.window(
            start: start,
            end: end,
            startTimeZone: event.startTimeZone,
            endTimeZone: event.endTimeZone,
            includesTimeZones: true
        )
        XCTAssertTrue(display.contains("EDT"))
        XCTAssertTrue(display.contains("PDT"))

        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let selectedDay = try XCTUnwrap(
            pacificCalendar.date(from: DateComponents(year: 2026, month: 7, day: 15))
        )
        XCTAssertTrue(event.occursOnLocalDay(selectedDay, calendar: pacificCalendar))

        let placement = try XCTUnwrap(
            DayTimelineLayout.placements(
                for: [event],
                on: selectedDay,
                calendar: pacificCalendar
            ).first
        )
        XCTAssertEqual(placement.startMinute, 10 * 60)
        XCTAssertEqual(placement.endMinute, 11 * 60)
    }

    func testRecordedZonePreventsEntryMovingToPreviousDayAfterTravel() throws {
        let formatter = ISO8601DateFormatter()
        let eastCoastOneAM = try XCTUnwrap(formatter.date(from: "2026-01-15T06:00:00Z"))
        let event = CareEvent(
            type: .diaper,
            startDate: eastCoastOneAM,
            startTimeZoneIdentifier: "America/New_York"
        )

        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let january15 = try XCTUnwrap(
            pacificCalendar.date(from: DateComponents(year: 2026, month: 1, day: 15))
        )

        XCTAssertFalse(pacificCalendar.isDate(event.startDate, inSameDayAs: january15))
        XCTAssertTrue(event.occursOnLocalDay(january15, calendar: pacificCalendar))
    }

    func testManualCareTimeZoneOverrideWinsOverDetectedZone() throws {
        let suiteName = "CareTimeZoneSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(CareTimeZoneMode.manual.rawValue, forKey: CareTimeZoneSettings.modeKey)
        defaults.set("America/New_York", forKey: CareTimeZoneSettings.manualIdentifierKey)

        let detected = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(
            CareTimeZoneSettings.effectiveIdentifier(
                defaults: defaults,
                automaticTimeZone: detected
            ),
            "America/New_York"
        )
    }

    @MainActor
    func testDogProfilesAreSelectableFamilyProfiles() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testChild = CareProfile(name: "Test Child", birthDate: Date(), sex: .male)
        let testDog = CareProfile(
            profileType: .dog,
            name: "Test Dog",
            birthDate: Date().addingTimeInterval(-12 * 7 * 24 * 60 * 60),
            sex: .female,
            displayColor: "teal",
            species: "dog",
            breed: "Mini Goldendoodle"
        )
        context.insert(testChild)
        context.insert(testDog)
        try context.save()

        ProfileService.shared.switchProfile(testDog)

        XCTAssertEqual(ProfileService.shared.selectedProfile(in: [testChild, testDog])?.id, testDog.id)
        XCTAssertEqual(ProfileService.shared.allActiveProfiles(in: [testChild, testDog]).map(\.id), [testChild.id, testDog.id])
        XCTAssertEqual(testDog.profileSubtitle, "Mini Goldendoodle")
    }

    func testDogEventDetailsDriveTimelineSummaries() {
        var pottyDetails = DogEventDetails()
        pottyDetails.pottyType = .poop
        pottyDetails.pottyLocation = .walk
        pottyDetails.stoolQuality = .normal
        pottyDetails.poopColor = .brown
        let potty = CareEvent(type: .potty, startDate: Date(), endDate: Date())
        potty.profileTypeSnapshot = .dog
        potty.dogDetails = pottyDetails

        XCTAssertEqual(potty.displayTitle, "Potty: poop, walk, normal, brown")

        var walkDetails = DogEventDetails()
        walkDetails.distance = 1.2
        walkDetails.distanceUnit = .miles
        walkDetails.peeCount = 1
        walkDetails.poopCount = 1
        walkDetails.leashBehavior = .pulled
        let walk = CareEvent(
            type: .walk,
            startDate: Date(timeIntervalSinceReferenceDate: 1_000),
            endDate: Date(timeIntervalSinceReferenceDate: 1_000 + 34 * 60)
        )
        walk.profileTypeSnapshot = .dog
        walk.dogDetails = walkDetails

        XCTAssertTrue(walk.displayTitle.contains("34m"))
        XCTAssertTrue(walk.displayTitle.contains("1.2 mi"))
        XCTAssertTrue(walk.displayTitle.contains("pulled"))

        let plainWalk = CareEvent(type: .walk, startDate: Date(), endDate: Date())
        plainWalk.profileTypeSnapshot = .dog
        XCTAssertEqual(plainWalk.displayTitle, "Walk")
    }

    func testChildProductionEventDetailsDriveTimelineSummaries() {
        let solid = CareEvent(type: .feed, startDate: Date())
        solid.profileTypeSnapshot = .child
        solid.feedKind = .solid
        solid.foodDescription = "Avocado"
        solid.solidFeedingStyle = .babyLedWeaning
        solid.solidTexture = .mashed
        solid.solidReaction = .liked
        solid.solidAllergenExposure = true

        let pumping = CareEvent(type: .pumping, startDate: Date())
        pumping.profileTypeSnapshot = .child
        pumping.amountOz = 3.2

        let potty = CareEvent(type: .potty, startDate: Date())
        potty.profileTypeSnapshot = .child
        potty.childPottyKind = .both
        potty.childPottyLocation = .pottyChair
        potty.childPottyAccident = true

        XCTAssertEqual(solid.displayTitle, "Solid: Avocado · mashed · baby-led weaning · liked · allergen")
        XCTAssertEqual(pumping.displayTitle, "Pumping: 3.2 oz")
        XCTAssertEqual(potty.displayTitle, "Potty: both · potty chair · accident")
    }

    @MainActor
    func testPuppyStageGuideMatchesDogAgeAndPersistsReadState() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testDog = CareProfile(
            profileType: .dog,
            name: "Test Dog",
            birthDate: Date().addingTimeInterval(-12 * 7 * 24 * 60 * 60),
            sex: .female
        )
        context.insert(testDog)
        let guide = try XCTUnwrap(PuppyStageGuideService.shared.currentGuide(for: testDog))

        XCTAssertEqual(guide.stageKey, "stage_12_weeks")

        PuppyStageGuideService.shared.markGuideRead(
            guide,
            in: context,
            readStates: [],
            profileID: testDog.id
        )

        let states = try context.fetch(FetchDescriptor<PuppyStageGuideReadState>())
        XCTAssertEqual(states.first?.profileID, testDog.id)
        XCTAssertEqual(states.first?.guideID, guide.id)
        XCTAssertNotNil(states.first?.firstOpenedAt)
    }

    @MainActor
    func testDogProfileAndDogDetailsRoundTripThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testDog = CareProfile(
            profileType: .dog,
            name: "Test Dog",
            birthDate: Date(timeIntervalSinceReferenceDate: 1_000),
            sex: .female,
            adoptionDate: Date(timeIntervalSinceReferenceDate: 2_000),
            species: "dog",
            breed: "Mini Goldendoodle",
            coatColor: "Apricot"
        )
        context.insert(testDog)
        var details = DogEventDetails()
        details.foodName = "Chicken and rice"
        details.foodAmount = 4
        details.foodUnit = .ounces
        details.mealType = .dinner
        details.eatenAmount = .most
        let food = CareEvent(
            profileID: testDog.id,
            type: .food,
            startDate: Date(timeIntervalSinceReferenceDate: 3_000)
        )
        food.profileTypeSnapshot = .dog
        food.dogDetails = details
        context.insert(food)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let importedProfiles = try context.fetch(FetchDescriptor<CareProfile>())
        let importedDog = try XCTUnwrap(importedProfiles.first { $0.profileType == .dog })
        XCTAssertEqual(importedDog.breed, "Mini Goldendoodle")
        XCTAssertEqual(importedDog.coatColor, "Apricot")

        let importedEvent = try XCTUnwrap(try context.fetch(FetchDescriptor<CareEvent>()).first { $0.type == .food })
        XCTAssertEqual(importedEvent.profileID, testDog.id)
        XCTAssertEqual(importedEvent.profileTypeSnapshot, .dog)
        XCTAssertEqual(importedEvent.dogDetails.foodName, "Chicken and rice")
        XCTAssertEqual(importedEvent.dogDetails.eatenAmount, .most)
    }

    @MainActor
    func testChildProductionDetailsRoundTripThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let testChild = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        context.insert(testChild)

        let solid = CareEvent(
            profileID: testChild.id,
            type: .feed,
            startDate: Date(timeIntervalSinceReferenceDate: 3_000)
        )
        solid.profileTypeSnapshot = .child
        solid.feedKind = .solid
        solid.foodDescription = "Banana"
        solid.solidFeedingStyle = .pureeSpoonFed
        solid.solidTexture = .fingerFood
        solid.solidReaction = .sensitivity
        solid.solidAllergenExposure = true
        solid.solidSensitivityObserved = true
        context.insert(solid)

        let diaper = CareEvent(
            profileID: testChild.id,
            type: .diaper,
            startDate: Date(timeIntervalSinceReferenceDate: 3_300)
        )
        diaper.profileTypeSnapshot = .child
        diaper.diaperKind = .wet
        diaper.diaperRash = true
        context.insert(diaper)

        let potty = CareEvent(
            profileID: testChild.id,
            type: .potty,
            startDate: Date(timeIntervalSinceReferenceDate: 3_600)
        )
        potty.profileTypeSnapshot = .child
        potty.childPottyKind = .both
        potty.childPottyLocation = .toilet
        potty.childPottyAccident = false
        potty.peeAmount = .medium
        potty.pooAmount = .little
        potty.pooColor = .brown
        potty.pooTexture = .formed
        context.insert(potty)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let importedEvents = try context.fetch(FetchDescriptor<CareEvent>())
        let importedSolid = try XCTUnwrap(importedEvents.first { $0.feedKind == .solid })
        XCTAssertEqual(importedSolid.solidFeedingStyle, .pureeSpoonFed)
        XCTAssertEqual(importedSolid.solidTexture, .fingerFood)
        XCTAssertEqual(importedSolid.solidReaction, .sensitivity)
        XCTAssertEqual(importedSolid.solidAllergenExposure, true)
        XCTAssertEqual(importedSolid.solidSensitivityObserved, true)

        let importedDiaper = try XCTUnwrap(importedEvents.first { $0.type == .diaper })
        XCTAssertEqual(importedDiaper.diaperKind, .wet)
        XCTAssertEqual(importedDiaper.diaperRash, true)

        let importedPotty = try XCTUnwrap(importedEvents.first { $0.type == .potty })
        XCTAssertEqual(importedPotty.childPottyKind, .both)
        XCTAssertEqual(importedPotty.childPottyLocation, .toilet)
        XCTAssertEqual(importedPotty.childPottyAccident, false)
        XCTAssertEqual(importedPotty.peeAmount, .medium)
        XCTAssertEqual(importedPotty.pooAmount, .little)
        XCTAssertEqual(importedPotty.pooColor, .brown)
        XCTAssertEqual(importedPotty.pooTexture, .formed)
    }

    func testPredictionRecordRestoresDisplayPrediction() {
        let original = SleepPrediction(
            predictedStart: Date(timeIntervalSinceReferenceDate: 1_000),
            predictedWindowStart: Date(timeIntervalSinceReferenceDate: 900),
            predictedWindowEnd: Date(timeIntervalSinceReferenceDate: 1_100),
            predictionKind: .bedtime,
            confidence: 0.81,
            confidenceLabel: .high,
            explanation: ["Recent sleep history"],
            contributingFactors: [
                PredictionFactorValue(
                    name: "History",
                    valueDescription: "8 samples",
                    impactMinutes: 4,
                    confidenceImpact: 0.1,
                    explanation: "Recent samples"
                )
            ],
            napIndex: 3
        )

        let restored = SleepPredictionRecord(
            prediction: original,
            basedOnLastSleepEventID: nil
        ).prediction

        XCTAssertEqual(restored, original)
    }

    private func makeLittleWindowPrediction(
        kind: PredictionKind = .nap
    ) -> SleepPrediction {
        SleepPrediction(
            predictedStart: Date(timeIntervalSinceReferenceDate: 10_000),
            predictedWindowStart: Date(timeIntervalSinceReferenceDate: 9_700),
            predictedWindowEnd: Date(timeIntervalSinceReferenceDate: 11_200),
            predictionKind: kind,
            confidence: 0.7,
            confidenceLabel: .medium,
            explanation: [],
            contributingFactors: [],
            napIndex: 2
        )
    }

    func testSleepMiniPlanBuildsBaselineAndTightensLowConfidenceWindows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSinceReferenceDate: 500_000)
        let profile = CareProfile(name: "Test Child", birthDate: now.addingTimeInterval(-120 * 24 * 60 * 60), sex: .unknown)

        let baseline = SleepMiniPlanService.plan(
            profile: profile,
            events: [],
            records: [],
            prediction: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(baseline?.id, "baseline")

        let nap = CareEvent(
            type: .sleep,
            startDate: now.addingTimeInterval(-4 * 60 * 60),
            endDate: now.addingTimeInterval(-3 * 60 * 60)
        )
        nap.sleepKind = .nap
        var lowConfidencePrediction = makeLittleWindowPrediction()
        lowConfidencePrediction.confidenceLabel = .low

        let tighten = SleepMiniPlanService.plan(
            profile: profile,
            events: [nap],
            records: [],
            prediction: lowConfidencePrediction,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(tighten?.id, "tighten-window")
    }

    func testSleepMiniPlanIncludesDayAheadTimeline() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 13))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        let nap = CareEvent(
            type: .sleep,
            startDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9))!,
            endDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10))!
        )
        nap.sleepKind = .nap
        let bedtime = CareEvent(
            type: .sleep,
            startDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 20))!,
            endDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 6))!
        )
        bedtime.sleepKind = .nightSleep
        let nightWaking = CareEvent(
            type: .sleep,
            startDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 2))!,
            endDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 2, minute: 15))!
        )
        nightWaking.sleepKind = .nightWaking
        var prediction = makeLittleWindowPrediction()
        prediction.predictedStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 14, minute: 15))!
        prediction.predictedWindowStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 14))!
        prediction.predictedWindowEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 14, minute: 30))!

        let plan = SleepMiniPlanService.plan(
            profile: profile,
            events: [bedtime, nightWaking, nap],
            records: [],
            prediction: prediction,
            now: now,
            calendar: calendar
        )

        let items = try XCTUnwrap(plan?.timelineItems)
        XCTAssertEqual(items.map(\.id), ["awake-since", "next-window", "usual-bedtime"])
        XCTAssertEqual(items.first?.detail, "Nap ended")
        XCTAssertEqual(items.first?.timeText, DateFormatting.time.string(from: nap.endDate!))
    }

    func testSleepMiniPlanUsesCircularBedtimeSpreadAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let profile = CareProfile(name: "Test Child", birthDate: Date(timeIntervalSinceReferenceDate: 0), sex: .unknown)

        func date(day: Int, hour: Int, minute: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute)))
        }

        let nearMidnightOne = CareEvent(
            type: .sleep,
            startDate: try date(day: 12, hour: 23, minute: 45),
            endDate: try date(day: 13, hour: 6)
        )
        nearMidnightOne.sleepKind = .nightSleep
        let nearMidnightTwo = CareEvent(
            type: .sleep,
            startDate: try date(day: 14, hour: 0, minute: 15),
            endDate: try date(day: 14, hour: 7)
        )
        nearMidnightTwo.sleepKind = .nightSleep
        var prediction = makeLittleWindowPrediction(kind: .bedtime)
        prediction.confidenceLabel = .high

        let steady = SleepMiniPlanService.plan(
            profile: profile,
            events: [nearMidnightOne, nearMidnightTwo],
            records: [],
            prediction: prediction,
            now: try date(day: 15, hour: 12),
            calendar: calendar
        )
        XCTAssertEqual(steady?.id, "steady-rhythm")

        let early = CareEvent(
            type: .sleep,
            startDate: try date(day: 12, hour: 20),
            endDate: try date(day: 13, hour: 5)
        )
        early.sleepKind = .nightSleep
        let late = CareEvent(
            type: .sleep,
            startDate: try date(day: 13, hour: 23),
            endDate: try date(day: 14, hour: 7)
        )
        late.sleepKind = .nightSleep

        let anchor = SleepMiniPlanService.plan(
            profile: profile,
            events: [early, late],
            records: [],
            prediction: prediction,
            now: try date(day: 15, hour: 12),
            calendar: calendar
        )
        XCTAssertEqual(anchor?.id, "bedtime-anchor")
    }

    func testDayTimelinePlacesOverlappingEventsInSeparateColumns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let sleep = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(9 * 3600),
            endDate: day.addingTimeInterval(10 * 3600)
        )
        let feed = CareEvent(
            type: .feed,
            startDate: day.addingTimeInterval(9.5 * 3600),
            endDate: day.addingTimeInterval(9.75 * 3600)
        )
        let diaper = CareEvent(
            type: .diaper,
            startDate: day.addingTimeInterval(11 * 3600),
            endDate: day.addingTimeInterval(11 * 3600)
        )

        let placements = DayTimelineLayout.placements(
            for: [sleep, feed, diaper],
            on: day,
            calendar: calendar
        )
        let sleepPlacement = placements.first { $0.eventID == sleep.id }
        let feedPlacement = placements.first { $0.eventID == feed.id }
        let diaperPlacement = placements.first { $0.eventID == diaper.id }

        XCTAssertEqual(sleepPlacement?.columnCount, 2)
        XCTAssertEqual(feedPlacement?.columnCount, 2)
        XCTAssertNotEqual(sleepPlacement?.column, feedPlacement?.column)
        XCTAssertEqual(diaperPlacement?.columnCount, 1)
    }

    func testDayTimelineGivesPointEventsVisibleDuration() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let diaper = CareEvent(
            type: .diaper,
            startDate: day.addingTimeInterval(8 * 3600),
            endDate: day.addingTimeInterval(8 * 3600)
        )

        let placement = DayTimelineLayout.placements(
            for: [diaper],
            on: day,
            calendar: calendar
        ).first

        XCTAssertEqual((placement?.endMinute ?? 0) - (placement?.startMinute ?? 0), 30)
    }

    func testHistoryDayFilterIncludesPointDiapersAndExcludesTimerDrafts() {
        let selectedProfileID = UUID()
        let otherProfileID = UUID()
        let now = Date()
        let diaper = CareEvent(profileID: selectedProfileID, type: .diaper, startDate: now, endDate: nil)
        diaper.diaperKind = .wet
        let legacyDiaper = CareEvent(type: .diaper, startDate: now, endDate: nil)
        legacyDiaper.diaperKind = .dirty
        let otherProfileDiaper = CareEvent(profileID: otherProfileID, type: .diaper, startDate: now, endDate: nil)
        otherProfileDiaper.diaperKind = .both
        let timerDraft = CareEvent(profileID: selectedProfileID, type: .sleep, startDate: now, endDate: nil)

        XCTAssertTrue(HistoryView.visibleDayEvent(diaper, selectedProfileID: selectedProfileID))
        XCTAssertFalse(HistoryView.visibleDayEvent(legacyDiaper, selectedProfileID: selectedProfileID))
        XCTAssertFalse(HistoryView.visibleDayEvent(otherProfileDiaper, selectedProfileID: selectedProfileID))
        XCTAssertFalse(HistoryView.visibleDayEvent(timerDraft, selectedProfileID: selectedProfileID))
    }

    @MainActor
    func testDeepLinkRouterOpensReportsDayModeForHistory() {
        let router = DeepLinkRouter.shared
        router.selectedReportsMode = .summary
        router.route(URL(string: "littlewindows://history")!)
        XCTAssertEqual(router.selectedTab, .reports)
        XCTAssertEqual(router.selectedReportsMode, .day)
    }

    @MainActor
    func testDeepLinkRouterOpensReportsSummaryModeForInsights() {
        let router = DeepLinkRouter.shared
        router.selectedReportsMode = .day
        router.route(URL(string: "littlewindows://insights")!)
        XCTAssertEqual(router.selectedTab, .reports)
        XCTAssertEqual(router.selectedReportsMode, .summary)
    }

    @MainActor
    func testDeepLinkRouterPresentsSettings() {
        let router = DeepLinkRouter.shared
        router.showingSettings = false
        router.route(URL(string: "littlewindows://settings")!)
        XCTAssertTrue(router.showingSettings)
    }

    @MainActor
    func testDeepLinkRouterOpensMilestonesTab() {
        let router = DeepLinkRouter.shared
        router.route(URL(string: "littlewindows://milestones")!)
        XCTAssertEqual(router.selectedTab, .milestones)
    }

    @MainActor
    func testDeepLinkRouterQueuesPuppyGuideCommand() {
        let router = DeepLinkRouter.shared
        router.pendingPuppyGuideCommand = nil

        router.route(URL(string: "littlewindows://puppy-guide")!)

        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertEqual(router.consumePuppyGuideCommand(), .current)
    }

    @MainActor
    func testNightLightDeepLinkStartsRequestedPreset() {
        let router = DeepLinkRouter.shared
        router.pendingNightLightCommand = nil

        router.route(
            URL(string: "littlewindows://night-light/diaper-change")!
        )

        XCTAssertEqual(router.selectedTab, .nightLight)
        XCTAssertEqual(
            router.consumeNightLightCommand(),
            .start(.diaperChange)
        )
    }

    func testNightLightIncludesFullShapeCatalog() {
        XCTAssertGreaterThanOrEqual(NightLightShape.allCases.count, 30)
        XCTAssertTrue(NightLightShape.allCases.contains(.fullScreenGlow))
        XCTAssertTrue(NightLightShape.allCases.contains(.teddyBear))
        XCTAssertTrue(NightLightShape.allCases.contains(.windowGlow))
        XCTAssertTrue(NightLightShape.selectableCases.contains(.halo))
        XCTAssertFalse(NightLightShape.selectableCases.contains(.custom))
    }

    func testCandleGlowUsesSupportedSystemIcon() {
        XCTAssertEqual(NightLightGlowMode.candle.systemImage, "flame")
    }

    func testSceneBasedNightLightStylesOwnTheirArtwork() {
        XCTAssertTrue(NightLightGlowMode.steady.displaysSelectedShape)
        XCTAssertTrue(NightLightGlowMode.shimmer.displaysSelectedShape)
        XCTAssertFalse(NightLightGlowMode.fireplace.displaysSelectedShape)
        XCTAssertFalse(NightLightGlowMode.candle.displaysSelectedShape)
        XCTAssertFalse(NightLightGlowMode.rainyWindow.displaysSelectedShape)
        XCTAssertFalse(NightLightGlowMode.starryNight.displaysSelectedShape)
    }

    @MainActor
    func testNightLightScenesProduceChangingAnimationFrames() throws {
        let animatedModes: [NightLightGlowMode] = [
            .fireplace, .candle, .shimmer, .rainyWindow, .starryNight
        ]

        for mode in animatedModes {
            let firstFrame = try renderedNightLightFrame(mode: mode, time: 10)
            let secondFrame = try renderedNightLightFrame(mode: mode, time: 11.25)
            XCTAssertNotEqual(
                firstFrame,
                secondFrame,
                "\(mode.displayName) should visibly change over time."
            )
        }
    }

    func testNightLightPresetsUseSafeDimDefaults() {
        let diaper = NightLightPresetService.preset(for: .diaperChange)
        let soothing = NightLightPresetService.preset(for: .soothing)

        XCTAssertEqual(diaper.color, .softRed)
        XCTAssertLessThanOrEqual(diaper.brightness, 0.2)
        XCTAssertEqual(diaper.sound, .none)
        XCTAssertEqual(diaper.timerMinutes, 10)
        XCTAssertTrue(soothing.breathingEnabled)
        XCTAssertEqual(soothing.timerMinutes, 30)
    }

    func testNightLightGeneratedSoundsContainPlayableWAVData() {
        for sound in NightLightSound.allCases where sound != .none {
            let data = NightLightAudioService.generatedWAVData(for: sound)
            XCTAssertGreaterThan(data.count, 44)
            XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "RIFF")
            XCTAssertEqual(
                String(data: data.dropFirst(8).prefix(4), encoding: .utf8),
                "WAVE"
            )
        }
    }

    @MainActor
    func testNightLightGeneratedSoundPreparesWithoutBlockingStart() {
        let service = NightLightAudioService()

        service.play(.pinkNoise, volume: 0.25)

        XCTAssertTrue(service.isPreparing)
        XCTAssertFalse(service.isPlaying)
        service.stop()
    }

    func testNightLightWhiteNoiseHasBundledMasteredLoop() throws {
        let url = try XCTUnwrap(
            NightLightAudioService.masteredLoopURL(for: .whiteNoise)
        )
        let data = try Data(contentsOf: url)
        let samples = try wavSamples(from: data)
        let middle = trimmedMiddle(samples)

        XCTAssertGreaterThan(samples.count, 44_100 * 20)
        XCTAssertGreaterThan(rms(middle), 0.12)
        XCTAssertLessThan(rms(middle), 0.25)
        XCTAssertNil(NightLightAudioService.masteredLoopURL(for: .pinkNoise))
        XCTAssertNil(NightLightAudioService.masteredLoopURL(for: .brownNoise))
    }

    func testNightLightAmbientSoundsAvoidHarshStaticProfiles() throws {
        let white = try wavSamples(for: .whiteNoise)
        let whiteZeroCrossings = zeroCrossingRate(white)

        let rain = try wavSamples(for: .rain)
        let fireplace = try wavSamples(for: .fireplace)

        XCTAssertLessThan(
            zeroCrossingRate(rain),
            whiteZeroCrossings * 0.88,
            "Rain should be softer layered rain, not full-band static."
        )
        XCTAssertLessThan(
            zeroCrossingRate(fireplace),
            whiteZeroCrossings * 0.82,
            "Fireplace should have warm flame bed and sparse crackles, not static."
        )
        XCTAssertLessThan(rms(rain), rms(white) * 0.85)
        XCTAssertLessThan(rms(fireplace), rms(white) * 0.85)
    }

    func testNightLightNoiseColorsGetProgressivelyWarmer() throws {
        let white = trimmedMiddle(try wavSamples(for: .whiteNoise))
        let pink = trimmedMiddle(try wavSamples(for: .pinkNoise))
        let brown = trimmedMiddle(try wavSamples(for: .brownNoise))

        XCTAssertLessThan(
            zeroCrossingRate(pink),
            zeroCrossingRate(white) * 0.6
        )
        XCTAssertLessThan(
            zeroCrossingRate(brown),
            zeroCrossingRate(pink) * 0.35
        )
        XCTAssertGreaterThan(rms(pink), 0.06)
        XCTAssertGreaterThan(rms(brown), 0.04)
        XCTAssertLessThan(rms(brown), rms(pink))
    }

    func testNightLightAudioVolumeUsesFullUsefulRange() throws {
        let whiteNoise = trimmedMiddle(try wavSamples(for: .whiteNoise))

        XCTAssertGreaterThan(
            rms(whiteNoise),
            0.13,
            "White noise should be audible at full playback volume without feeling broken."
        )
        XCTAssertEqual(NightLightAudioService.playbackVolume(for: 0), 0)
        XCTAssertGreaterThan(
            NightLightAudioService.playbackVolume(for: 0.22),
            0.22
        )
        XCTAssertGreaterThan(
            NightLightAudioService.playbackVolume(for: 0.5),
            0.5
        )
        XCTAssertEqual(NightLightAudioService.playbackVolume(for: 1), 1)
        XCTAssertEqual(NightLightAudioService.playbackVolume(for: 2), 1)
    }

    func testNightLightShushingKeepsContinuousAirBed() throws {
        let shushing = trimmedMiddle(try wavSamples(for: .shushing))
        let envelopes = rmsWindows(shushing, windowSize: 4_410)
        let maxEnvelope = try XCTUnwrap(envelopes.max())
        let minEnvelope = try XCTUnwrap(envelopes.min())

        XCTAssertGreaterThan(
            minEnvelope / maxEnvelope,
            0.28,
            "Shushing should breathe gently without dropping into hard pulsing silence."
        )
        XCTAssertLessThan(rms(shushing), rms(try wavSamples(for: .whiteNoise)))
    }

    @MainActor
    func testNightLightSoundCanPreviewBeforeStarting() throws {
        let suiteName = "NightLightPreviewTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = NightLightViewModel(defaults: defaults)
        viewModel.selectSound(.rain)

        XCTAssertFalse(viewModel.isActive)
        XCTAssertEqual(viewModel.settings.selectedSound, .rain)
        XCTAssertEqual(viewModel.previewingSound, .rain)

        viewModel.stopSoundPreview()
        XCTAssertNil(viewModel.previewingSound)
    }

    @MainActor
    func testNightLightMutePreservesSelectedVolume() throws {
        let suiteName = "NightLightMuteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = NightLightViewModel(defaults: defaults)
        viewModel.settings.selectedSound = .rain
        viewModel.updateSoundVolume(0.36)

        viewModel.toggleSoundMuted()
        XCTAssertTrue(viewModel.isSoundMuted)
        XCTAssertEqual(viewModel.effectiveSoundVolume, 0)
        XCTAssertEqual(viewModel.settings.soundVolume, 0.36)

        viewModel.toggleSoundMuted()
        XCTAssertFalse(viewModel.isSoundMuted)
        XCTAssertEqual(viewModel.effectiveSoundVolume, 0.36)
        XCTAssertEqual(viewModel.settings.soundVolume, 0.36)
    }

    @MainActor
    private func renderedNightLightFrame(
        mode: NightLightGlowMode,
        time: TimeInterval
    ) throws -> Data {
        let renderer = ImageRenderer(
            content: NightLightAmbientEffect(
                mode: mode,
                color: .orange,
                intensity: 0.25,
                time: time
            )
            .frame(width: 195, height: 422)
            .background(.black)
        )
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage?.pngData())
    }

    @MainActor
    func testNightLightCanvasTapTogglesControls() {
        let viewModel = NightLightViewModel()
        XCTAssertTrue(viewModel.controlsVisible)

        viewModel.toggleControls()
        XCTAssertFalse(viewModel.controlsVisible)

        viewModel.toggleControls()
        XCTAssertTrue(viewModel.controlsVisible)
    }

    @MainActor
    func testNightLightSettingsPersistAcrossViewModels() throws {
        let suiteName = "NightLightTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = NightLightViewModel(defaults: defaults)
        first.applyPreset(.nursing)
        first.settings.selectedShape = .moon
        first.settings.shapeScale = 1.6
        first.settingsDidChange()

        let restored = NightLightViewModel(defaults: defaults)
        XCTAssertEqual(restored.settings.selectedPreset, .nursing)
        XCTAssertEqual(restored.settings.selectedShape, .moon)
        XCTAssertEqual(restored.settings.shapeScale, 1.6)
    }

    @MainActor
    func testNightLightTimerFadesOnlyNearTheEnd() {
        XCTAssertEqual(
            NightLightTimerService.fadeMultiplier(
                remaining: 300,
                totalDuration: 600
            ),
            1
        )
        XCTAssertEqual(
            NightLightTimerService.fadeMultiplier(
                remaining: 30,
                totalDuration: 600
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NightLightTimerService.fadeMultiplier(
                remaining: 0,
                totalDuration: 600
            ),
            0
        )
    }

    @MainActor
    func testLiveActivityStopCommandPausesSelectedTimerDraft() async throws {
        let container = try makeInMemoryContainer()
        let event = CareEvent(
            type: .sleep,
            startDate: Date().addingTimeInterval(-300)
        )
        container.mainContext.insert(event)
        try container.mainContext.save()

        let processed = await IntegrationCommandProcessor.process(
            URL(string: "littlewindows://action/stop/\(event.id.uuidString)")!,
            container: container
        )

        XCTAssertTrue(processed)
        XCTAssertNil(event.endDate)
        XCTAssertTrue(event.isTimerDraft)
        XCTAssertFalse(event.isTimerRunning)
        XCTAssertGreaterThan(event.timerElapsed(), 0)
    }

    @MainActor
    func testLiveActivityStopUsesWidgetTapTime() async throws {
        let container = try makeInMemoryContainer()
        let startedAt = Date().addingTimeInterval(-300)
        let requestedAt = Date().addingTimeInterval(-2)
        let event = CareEvent(type: .sleep, startDate: startedAt)
        event.updatedAt = startedAt
        container.mainContext.insert(event)
        try container.mainContext.save()

        let processed = await IntegrationCommandProcessor.process(
            URL(string: "littlewindows://action/stop/\(event.id.uuidString)?requestedAt=\(requestedAt.timeIntervalSince1970)")!,
            container: container
        )

        XCTAssertTrue(processed)
        XCTAssertFalse(event.isTimerRunning)
        XCTAssertEqual(
            event.timerAccumulatedSeconds ?? 0,
            requestedAt.timeIntervalSince(startedAt),
            accuracy: 0.01
        )
    }

    @MainActor
    func testLiveActivityStopSurvivesNewerNonTimerMetadataUpdate() async throws {
        let container = try makeInMemoryContainer()
        let startedAt = Date().addingTimeInterval(-300)
        let requestedAt = Date().addingTimeInterval(-2)
        let event = CareEvent(type: .sleep, startDate: startedAt)
        event.activeTimerSegmentStartDate = startedAt
        // Startup sync or bookkeeping can touch the event after the widget
        // tap without representing a newer timer action.
        event.updatedAt = requestedAt.addingTimeInterval(1)
        container.mainContext.insert(event)
        try container.mainContext.save()

        let processed = await IntegrationCommandProcessor.process(
            URL(string: "littlewindows://action/stop/\(event.id.uuidString)?requestedAt=\(requestedAt.timeIntervalSince1970)")!,
            container: container
        )

        XCTAssertTrue(processed)
        XCTAssertFalse(event.isTimerRunning)
        XCTAssertEqual(
            event.timerAccumulatedSeconds ?? 0,
            requestedAt.timeIntervalSince(startedAt),
            accuracy: 0.01
        )
    }

    @MainActor
    func testDelayedWidgetStopDoesNotOverrideNewerTimerAction() async throws {
        let container = try makeInMemoryContainer()
        let requestedAt = Date().addingTimeInterval(-2)
        let event = CareEvent(
            type: .sleep,
            startDate: Date().addingTimeInterval(-300)
        )
        event.activeTimerSegmentStartDate = requestedAt.addingTimeInterval(1)
        event.updatedAt = requestedAt.addingTimeInterval(1)
        container.mainContext.insert(event)
        try container.mainContext.save()

        let processed = await IntegrationCommandProcessor.process(
            URL(string: "littlewindows://action/stop/\(event.id.uuidString)?requestedAt=\(requestedAt.timeIntervalSince1970)")!,
            container: container
        )

        XCTAssertTrue(processed)
        XCTAssertTrue(event.isTimerRunning)
    }

    @MainActor
    func testLiveActivityStopActiveCommandPausesPrimaryTimerDraft() async throws {
        let container = try makeInMemoryContainer()
        let event = CareEvent(
            type: .nursing,
            startDate: Date().addingTimeInterval(-300)
        )
        event.nursingSide = .left
        event.activeNursingSide = .left
        container.mainContext.insert(event)
        try container.mainContext.save()

        let processed = await IntegrationCommandProcessor.process(
            URL(string: "littlewindows://action/stop-active")!,
            container: container
        )

        XCTAssertTrue(processed)
        XCTAssertNil(event.endDate)
        XCTAssertTrue(event.isTimerDraft)
        XCTAssertFalse(event.isTimerRunning)
        XCTAssertEqual(event.activeNursingSide, .left)
        XCTAssertGreaterThan(event.leftDurationSeconds ?? 0, 0)
    }

    func testRecentWakeWindowSamplesTakePrecedenceOverOldHistory() {
        let now = Date()
        let old = (0..<8).map {
            WakeWindowSample(
                minutes: 60,
                napIndex: 1,
                date: now.addingTimeInterval(Double(-90 - $0) * 86_400),
                weight: 0.04
            )
        }
        let recent = (0..<6).map {
            WakeWindowSample(
                minutes: 120,
                napIndex: 1,
                date: now.addingTimeInterval(Double(-$0) * 86_400),
                weight: 1
            )
        }

        let preferred = SleepPredictionEngine.preferredPredictionSamples(old + recent, now: now)

        XCTAssertEqual(preferred.count, recent.count)
        XCTAssertTrue(preferred.allSatisfy { $0.minutes == 120 })
    }

    func testWeightedStatisticsUseEffectiveSampleCount() {
        let samples = [
            WakeWindowSample(minutes: 90, napIndex: 1, date: Date(), weight: 1),
            WakeWindowSample(minutes: 110, napIndex: 1, date: Date(), weight: 0.5),
            WakeWindowSample(minutes: 180, napIndex: 1, date: Date(), weight: 0.1)
        ]

        let statistics = SleepPredictionEngine.statistics(for: samples)

        XCTAssertEqual(statistics?.sampleCount, 3)
        XCTAssertEqual(statistics?.effectiveSampleCount ?? 0, 1.6, accuracy: 0.001)
        XCTAssertLessThan(statistics?.weightedMean ?? 200, 110)
    }

    func testPlanningWakeWindowLeansLaterWhenSamplesVary() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let samples = [100.0, 110.0, 125.0, 145.0, 165.0].enumerated().map { offset, minutes in
            WakeWindowSample(
                minutes: minutes,
                napIndex: 1,
                date: day.addingTimeInterval(Double(offset) * 86_400),
                weight: 1
            )
        }

        let statistics = try XCTUnwrap(SleepPredictionEngine.statistics(for: samples))
        let target = SleepPredictionEngine.planningWakeWindowMinutes(statistics)

        XCTAssertGreaterThan(target, statistics.weightedMedian)
        XCTAssertLessThanOrEqual(target - statistics.weightedMedian, 18)
    }

    func testWakeWindowTrendDoesNotMoveExpectedTimeLater() {
        let statistics = WakeWindowStatistics(
            weightedMean: 135,
            weightedMedian: 120,
            upperQuartile: 140,
            standardDeviation: 35,
            interquartileRange: 40,
            trendMinutes: 30,
            sampleCount: 12,
            effectiveSampleCount: 10
        )

        let adjustment = SleepPredictionEngine.wakeWindowTrendAdjustmentMinutes(statistics)

        XCTAssertEqual(adjustment, 0)
    }

    func testShorteningWakeWindowTrendCanMoveExpectedTimeEarlier() {
        let statistics = WakeWindowStatistics(
            weightedMean: 115,
            weightedMedian: 120,
            upperQuartile: 135,
            standardDeviation: 28,
            interquartileRange: 35,
            trendMinutes: -30,
            sampleCount: 12,
            effectiveSampleCount: 10
        )

        let adjustment = SleepPredictionEngine.wakeWindowTrendAdjustmentMinutes(statistics)

        XCTAssertEqual(adjustment, -6, accuracy: 0.001)
    }

    func testCurrentPredictionIgnoresRecordBasedOnOlderSleep() throws {
        let now = Date()
        let profile = CareProfile(
            name: "Test Child",
            birthDate: now.addingTimeInterval(-150 * 86_400)
        )
        let firstSleep = CareEvent(
            profileID: profile.id,
            type: .sleep,
            startDate: now.addingTimeInterval(-6 * 60 * 60),
            endDate: now.addingTimeInterval(-5 * 60 * 60)
        )
        firstSleep.sleepKind = .nightSleep
        let latestSleep = CareEvent(
            profileID: profile.id,
            type: .sleep,
            startDate: now.addingTimeInterval(-2 * 60 * 60),
            endDate: now.addingTimeInterval(-90 * 60)
        )
        latestSleep.sleepKind = .nap

        let stalePrediction = SleepPrediction(
            predictedStart: now.addingTimeInterval(-4 * 60 * 60),
            predictedWindowStart: now.addingTimeInterval(-5 * 60 * 60),
            predictedWindowEnd: now.addingTimeInterval(-3 * 60 * 60),
            predictionKind: .nap,
            confidence: 0.8,
            confidenceLabel: .high,
            explanation: ["Stale"],
            contributingFactors: [],
            napIndex: 1
        )
        let staleRecord = SleepPredictionRecord(
            prediction: stalePrediction,
            basedOnLastSleepEventID: firstSleep.id,
            profileID: profile.id
        )

        let prediction = try XCTUnwrap(PredictionTuningService.currentPrediction(
            profile: profile,
            events: [firstSleep, latestSleep],
            records: [staleRecord]
        ))

        XCTAssertNotEqual(prediction.predictedStart, stalePrediction.predictedStart)
        XCTAssertGreaterThan(prediction.predictedStart, latestSleep.endDate ?? now)
    }

    func testCurrentPredictionIgnoresRecordWithDifferentTuningSettings() throws {
        let now = Date()
        let profile = CareProfile(
            name: "Test Child",
            birthDate: now.addingTimeInterval(-150 * 86_400)
        )
        let nightSleep = CareEvent(
            profileID: profile.id,
            type: .sleep,
            startDate: now.addingTimeInterval(-10 * 60 * 60),
            endDate: now.addingTimeInterval(-6 * 60 * 60)
        )
        nightSleep.sleepKind = .nightSleep
        let latestSleep = CareEvent(
            profileID: profile.id,
            type: .sleep,
            startDate: now.addingTimeInterval(-2 * 60 * 60),
            endDate: now.addingTimeInterval(-90 * 60)
        )
        latestSleep.sleepKind = .nap

        let cachedPrediction = SleepPrediction(
            predictedStart: now.addingTimeInterval(8 * 60 * 60),
            predictedWindowStart: now.addingTimeInterval(7 * 60 * 60),
            predictedWindowEnd: now.addingTimeInterval(9 * 60 * 60),
            predictionKind: .nap,
            confidence: 0.9,
            confidenceLabel: .high,
            explanation: ["Cached with old settings"],
            contributingFactors: [],
            napIndex: 1
        )
        let cachedRecord = SleepPredictionRecord(
            prediction: cachedPrediction,
            basedOnLastSleepEventID: latestSleep.id,
            profileID: profile.id,
            settings: .default
        )
        let tunedSettings = PredictionSettings(
            feedAdjustmentEnabled: true,
            nursingAdjustmentEnabled: true,
            bedtimePredictionEnabled: true,
            customBaselineMinimum: 45,
            customBaselineMaximum: 60
        )

        let prediction = try XCTUnwrap(PredictionTuningService.currentPrediction(
            profile: profile,
            events: [nightSleep, latestSleep],
            records: [cachedRecord],
            settings: tunedSettings
        ))

        XCTAssertNotEqual(prediction.predictedStart, cachedPrediction.predictedStart)
        XCTAssertNotEqual(
            cachedRecord.algorithmVersion,
            SleepPredictionEngine.cacheVersion(settings: tunedSettings)
        )
    }

    func testAgeBaselineUsesFractionalMonthsForFourMonthWakeWindows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let birthDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let fourAndHalfMonths = calendar.date(byAdding: .day, value: 135, to: birthDate)!

        let baseline = SleepPredictionEngine.ageBaselineMinutes(
            birthDate: birthDate,
            date: fourAndHalfMonths,
            customMinimum: nil,
            customMaximum: nil,
            calendar: calendar
        )

        XCTAssertEqual(baseline.lowerBound, 105)
        XCTAssertEqual(baseline.upperBound, 165)
    }

    func testLateShortNapUsesPreBedWakeWindowForBedtimePrediction() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 20, minute: 1))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        )
        var events = [CareEvent]()
        for offset in -14 ... -1 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let firstNapStart = calendar.date(bySettingHour: 16, minute: 8, second: 0, of: day)!
            let firstNapEnd = calendar.date(byAdding: .minute, value: 48, to: firstNapStart)!
            let secondNapStart = calendar.date(bySettingHour: 19, minute: 11, second: 0, of: day)!
            let secondNapEnd = calendar.date(byAdding: .minute, value: 48, to: secondNapStart)!
            let nightStart = calendar.date(bySettingHour: 21, minute: 50, second: 0, of: day)!
            let nightEnd = calendar.date(byAdding: .hour, value: 9, to: nightStart)!
            events.append(contentsOf: [
                makeSleep(kind: .nap, start: firstNapStart, end: firstNapEnd),
                makeSleep(kind: .nap, start: secondNapStart, end: secondNapEnd),
                makeSleep(kind: .nightSleep, start: nightStart, end: nightEnd)
            ])
        }
        events.append(contentsOf: [
            makeSleep(
                kind: .nap,
                start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 16, minute: 8))!,
                end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 16, minute: 53))!
            ),
            makeSleep(
                kind: .nap,
                start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 35))!,
                end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 59))!
            )
        ])

        let prediction = try XCTUnwrap(SleepPredictionEngine.predict(
            profile: profile,
            events: events,
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(prediction.predictionKind, .bedtime)
        XCTAssertEqual(prediction.napIndex, 5)
        XCTAssertEqual(
            prediction.predictedStart.timeIntervalSince(
                try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 21, minute: 50)))
            ),
            0,
            accuracy: 90
        )
    }

    func testBackwardsPlanBuildsTodayNapLayoutFromSevenDayHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        let events = makeTwoNapHistory(today: today, calendar: calendar)

        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: target,
            now: today,
            calendar: calendar
        )

        let naps = plan.segments.filter { $0.kind == .nap }
        XCTAssertEqual(plan.sourceDayCount, 7)
        XCTAssertEqual(plan.typicalNapCount, 2)
        XCTAssertEqual(plan.plannedNapCount, 2)
        XCTAssertEqual(plan.segments.first?.kind, .wakeWindow)
        XCTAssertEqual(
            plan.segments.first?.startDate,
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 6, minute: 30))
        )
        XCTAssertEqual(naps.map(\.napIndex), [1, 2])
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(naps.first?.startDate)), 8)
        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(naps.first?.startDate)), 30)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(naps.last?.startDate)), 12)
        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(naps.last?.startDate)), 0)
        XCTAssertEqual(plan.segments.last?.kind, .bedtime)
    }

    func testBackwardsPlanHonorsSelectedNapCount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )

        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: makeTwoNapHistory(today: today, calendar: calendar),
            targetBedtime: target,
            now: today,
            calendar: calendar,
            targetNapCount: 4
        )

        let naps = plan.segments.filter { $0.kind == .nap }
        XCTAssertEqual(plan.targetNapCount, 4)
        XCTAssertEqual(plan.typicalNapCount, 2)
        XCTAssertEqual(plan.plannedNapCount, 4)
        XCTAssertEqual(naps.map(\.napIndex), [1, 2, 3, 4])
        XCTAssertTrue(plan.explanation.contains { $0.contains("set for 4 naps") })
    }

    func testActiveSleepPlanActivationPersistsSelectedNapCount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let suiteName = "ActiveSleepPlanNapCount-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: makeTwoNapHistory(today: today, calendar: calendar),
            targetBedtime: target,
            now: today,
            calendar: calendar,
            targetNapCount: 3
        )

        let activePlan = ActiveSleepPlanService.activate(
            plan: plan,
            profileID: profile.id,
            defaults: defaults
        )
        let restoredPlan = ActiveSleepPlanService.activePlan(
            for: profile.id,
            now: today,
            calendar: calendar,
            defaults: defaults
        )

        XCTAssertEqual(activePlan.targetNapCount, 3)
        XCTAssertEqual(restoredPlan?.targetNapCount, 3)

        ActiveSleepPlanService.clearIfProfileIsInactive(
            activeProfileIDs: [UUID()],
            defaults: defaults
        )
        XCTAssertNil(ActiveSleepPlanService.activePlan(
            for: profile.id,
            now: today,
            calendar: calendar,
            defaults: defaults
        ))
    }

    func testBackwardsPlanShowsFullDayEvenAfterEarlierNapsPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 15))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )

        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: makeTwoNapHistory(today: now, calendar: calendar),
            targetBedtime: target,
            now: now,
            calendar: calendar
        )

        let naps = plan.segments.filter { $0.kind == .nap }
        XCTAssertEqual(naps.map(\.napIndex), [1, 2])
        XCTAssertLessThan(try XCTUnwrap(naps.first?.startDate), now)
        XCTAssertEqual(
            plan.segments.first?.startDate,
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 6, minute: 30))
        )
    }

    func testBackwardsPlanFallsBackWhenRecentHistoryIsSparse() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )

        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: [],
            targetBedtime: target,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.sourceDayCount, 0)
        XCTAssertEqual(plan.confidenceLabel, .low)
        XCTAssertTrue(plan.explanation.contains { $0.contains("age-based wake-window baseline") })
        XCTAssertEqual(plan.segments.last?.kind, .bedtime)
    }

    func testBackwardsPlanHonorsSelectedHistoryRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        let events = makeTwoNapHistory(
            today: today,
            calendar: calendar,
            dayOffsets: -14 ... -8
        )

        let sevenDayPlan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: target,
            now: today,
            calendar: calendar,
            historyRange: .sevenDays
        )
        let fourteenDayPlan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: target,
            now: today,
            calendar: calendar,
            historyRange: .fourteenDays
        )

        XCTAssertEqual(sevenDayPlan.sourceDayCount, 0)
        XCTAssertEqual(fourteenDayPlan.sourceDayCount, 7)
        XCTAssertEqual(fourteenDayPlan.historyRange, .fourteenDays)
        XCTAssertTrue(fourteenDayPlan.explanation.contains { $0.contains("last 14 days") })
    }

    func testBackwardsPlanIgnoresActiveSleepTimers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        var events = makeTwoNapHistory(today: today, calendar: calendar)
        let activeSleep = CareEvent(
            type: .sleep,
            startDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 6, minute: 45))!,
            endDate: nil
        )
        activeSleep.sleepKind = .nap
        events.append(activeSleep)

        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: target,
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(plan.plannedNapCount, 2)
        XCTAssertEqual(plan.segments.filter { $0.kind == .nap }.map(\.napIndex), [1, 2])
    }

    func testBackwardsPlanManualNapAdjustmentReflowsFollowingWindows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        let adjustedNapStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9))!
        let adjustedNapEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10, minute: 15))!

        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: makeTwoNapHistory(today: today, calendar: calendar),
            targetBedtime: target,
            now: today,
            calendar: calendar,
            adjustments: [
                BackwardsSleepPlanAdjustment(
                    kind: .nap,
                    napIndex: 1,
                    startDate: adjustedNapStart,
                    endDate: adjustedNapEnd
                )
            ]
        )

        let firstWake = try XCTUnwrap(plan.segments.first { $0.kind == .wakeWindow && $0.napIndex == 1 })
        let firstNap = try XCTUnwrap(plan.segments.first { $0.kind == .nap && $0.napIndex == 1 })
        let secondWake = try XCTUnwrap(plan.segments.first { $0.kind == .wakeWindow && $0.napIndex == 2 })
        let secondNap = try XCTUnwrap(plan.segments.first { $0.kind == .nap && $0.napIndex == 2 })

        XCTAssertEqual(firstWake.endDate, adjustedNapStart)
        XCTAssertEqual(firstNap.startDate, adjustedNapStart)
        XCTAssertEqual(firstNap.endDate, adjustedNapEnd)
        XCTAssertEqual(secondWake.startDate, adjustedNapEnd)
        XCTAssertEqual(
            secondNap.startDate,
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 12, minute: 45))
        )
        XCTAssertEqual(plan.segments.last?.startDate, target)
        XCTAssertEqual(plan.segmentAdjustments.count, 1)
    }

    func testActiveSleepPlanWakeAlertUsesPlannedNapEndForCurrentNap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8, minute: 45))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        var events = makeTwoNapHistory(today: now, calendar: calendar)
        let activeSleep = activeNap(
            profileID: profile.id,
            start: now
        )
        events.append(activeSleep)
        let activePlan = ActiveSleepPlan(
            profileID: profile.id,
            targetBedtime: target,
            historyRangeRawValue: BackwardsSleepPlanHistoryRange.sevenDays.rawValue,
            activatedAt: now,
            generatedAt: now
        )
        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: target,
            now: now,
            calendar: calendar
        )
        let plannedWake = try XCTUnwrap(
            plan.segments.first { $0.kind == .nap && $0.napIndex == 1 }?.endDate
        )

        let alert = ActiveSleepPlanService.wakeAlert(
            for: activePlan,
            profile: profile,
            events: events,
            activeSleep: activeSleep,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(alert?.wakeByDate, plannedWake)
        XCTAssertEqual(alert?.targetBedtime, target)
    }

    func testActiveSleepPlanWakeAlertUsesSelectedNapCount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8, minute: 45))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        var events = makeTwoNapHistory(today: now, calendar: calendar)
        let activeSleep = activeNap(
            profileID: profile.id,
            start: now
        )
        events.append(activeSleep)
        let activePlan = ActiveSleepPlan(
            profileID: profile.id,
            targetBedtime: target,
            historyRangeRawValue: BackwardsSleepPlanHistoryRange.sevenDays.rawValue,
            targetNapCount: 4,
            activatedAt: now,
            generatedAt: now
        )
        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: target,
            now: now,
            calendar: calendar,
            targetNapCount: 4
        )
        let plannedWake = try XCTUnwrap(
            plan.segments.first { $0.kind == .nap && $0.napIndex == 1 }?.endDate
        )

        let alert = ActiveSleepPlanService.wakeAlert(
            for: activePlan,
            profile: profile,
            events: events,
            activeSleep: activeSleep,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(alert?.wakeByDate, plannedWake)
    }

    func testActiveSleepPlanWakeAlertUsesAdjustedPlannedNapEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8, minute: 45))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        let adjustedNapEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10, minute: 15))!
        var events = makeTwoNapHistory(today: now, calendar: calendar)
        let activeSleep = activeNap(
            profileID: profile.id,
            start: now
        )
        events.append(activeSleep)
        let activePlan = ActiveSleepPlan(
            profileID: profile.id,
            targetBedtime: target,
            historyRangeRawValue: BackwardsSleepPlanHistoryRange.sevenDays.rawValue,
            activatedAt: now,
            generatedAt: now,
            segmentAdjustments: [
                BackwardsSleepPlanAdjustment(
                    kind: .nap,
                    napIndex: 1,
                    startDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9))!,
                    endDate: adjustedNapEnd
                )
            ]
        )

        let alert = ActiveSleepPlanService.wakeAlert(
            for: activePlan,
            profile: profile,
            events: events,
            activeSleep: activeSleep,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(alert?.wakeByDate, adjustedNapEnd)
    }

    func testActiveSleepPlanWakeAlertUsesBedtimeWakeWindowForLateNap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 18))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 20, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )
        let activeSleep = activeNap(
            profileID: profile.id,
            start: now
        )
        let activePlan = ActiveSleepPlan(
            profileID: profile.id,
            targetBedtime: target,
            historyRangeRawValue: BackwardsSleepPlanHistoryRange.sevenDays.rawValue,
            activatedAt: now,
            generatedAt: now
        )
        let settings = PredictionSettings(
            feedAdjustmentEnabled: true,
            nursingAdjustmentEnabled: true,
            bedtimePredictionEnabled: true,
            customBaselineMinimum: 134.5,
            customBaselineMaximum: 135.5
        )

        let alert = ActiveSleepPlanService.wakeAlert(
            for: activePlan,
            profile: profile,
            events: [activeSleep],
            activeSleep: activeSleep,
            now: now,
            calendar: calendar,
            settings: settings
        )

        XCTAssertEqual(
            alert?.wakeByDate,
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 18, minute: 15))
        )
    }

    func testBackwardsPlanShowsFullDayWhenSelectedBedtimeAlreadyPassedToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 21, minute: 30))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 20, minute: 30))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        )

        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: makeTwoNapHistory(today: now, calendar: calendar),
            targetBedtime: target,
            now: now,
            calendar: calendar
        )

        let naps = plan.segments.filter { $0.kind == .nap }
        let firstWake = try XCTUnwrap(plan.segments.first)
        XCTAssertEqual(plan.plannedNapCount, 2)
        XCTAssertEqual(naps.map(\.napIndex), [1, 2])
        XCTAssertEqual(firstWake.kind, .wakeWindow)
        XCTAssertEqual(firstWake.napIndex, 1)
        XCTAssertEqual(firstWake.durationMinutes, 140, accuracy: 0.001)
        XCTAssertEqual(calendar.component(.hour, from: firstWake.endDate), 8)
        XCTAssertEqual(calendar.component(.minute, from: firstWake.endDate), 50)
        XCTAssertEqual(plan.segments.last?.kind, .bedtime)
        XCTAssertEqual(plan.segments.last?.startDate, target)
    }

    func testSleepPressureLearnsRhythmUnderFourMonths() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        )

        let pressure = try XCTUnwrap(SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: [
                makeSleep(
                    kind: .nap,
                    start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!,
                    end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8))!
                )
            ],
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(pressure.band, .learning)
        XCTAssertNil(pressure.score)
        XCTAssertTrue(pressure.explanation.contains { $0.contains("under 4 months") })
    }

    func testSleepPressureMovesIntoReadyBandFromAwakeTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        )
        let lastNap = makeSleep(
            kind: .nap,
            start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7, minute: 30))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8, minute: 15))!
        )
        let settings = PredictionSettings(
            feedAdjustmentEnabled: true,
            nursingAdjustmentEnabled: true,
            bedtimePredictionEnabled: true,
            customBaselineMinimum: 119,
            customBaselineMaximum: 121
        )

        let pressure = try XCTUnwrap(SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: [lastNap],
            now: now,
            calendar: calendar,
            settings: settings
        ))

        XCTAssertEqual(pressure.band, .ready)
        XCTAssertEqual(try XCTUnwrap(pressure.awakeMinutes), 105, accuracy: 0.001)
        XCTAssertNotNil(pressure.score)
        XCTAssertGreaterThan(try XCTUnwrap(pressure.highAt), now)
    }

    @MainActor
    func testSleepPressureAlertSchedulesReadyThresholdSeparately() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        )
        let lastNap = makeSleep(
            kind: .nap,
            start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8))!
        )
        let settings = PredictionSettings(
            feedAdjustmentEnabled: true,
            nursingAdjustmentEnabled: true,
            bedtimePredictionEnabled: true,
            customBaselineMinimum: 119,
            customBaselineMaximum: 121
        )
        let pressure = try XCTUnwrap(SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: [lastNap],
            now: now,
            calendar: calendar,
            settings: settings
        ))

        let decision = NotificationManager.sleepPressureAlertDecision(
            pressure: pressure,
            enabled: true,
            now: now
        )

        guard case .schedule(let fireDate, let band) = decision else {
            XCTFail("Expected pressure alert to schedule")
            return
        }
        XCTAssertEqual(band, .ready)
        XCTAssertEqual(fireDate, pressure.readyAt)
    }

    private func makeTwoNapHistory(
        today: Date,
        calendar: Calendar,
        dayOffsets: ClosedRange<Int> = -7 ... -1
    ) -> [CareEvent] {
        let todayStart = calendar.startOfDay(for: today)
        return dayOffsets.flatMap { offset -> [CareEvent] in
            let day = calendar.date(byAdding: .day, value: offset, to: todayStart)!
            let nightStart = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: day)!
            let nightEnd = calendar.date(byAdding: .hour, value: 11, to: nightStart)!
            let napOneStart = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day)!
            let napOneEnd = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: day)!
            let napTwoStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            let napTwoEnd = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day)!
            return [
                makeSleep(kind: .nightSleep, start: nightStart, end: nightEnd),
                makeSleep(kind: .nap, start: napOneStart, end: napOneEnd),
                makeSleep(kind: .nap, start: napTwoStart, end: napTwoEnd)
            ]
        }
    }

    private func makeSleep(kind: SleepKind, start: Date, end: Date) -> CareEvent {
        let event = CareEvent(type: .sleep, startDate: start, endDate: end)
        event.sleepKind = kind
        return event
    }

    private func activeNap(
        profileID: UUID,
        start: Date
    ) -> CareEvent {
        let event = CareEvent(profileID: profileID, type: .sleep, startDate: start)
        event.sleepKind = .nap
        event.timerState = .running
        event.activeTimerSegmentStartDate = start
        return event
    }

    @MainActor
    func testBundledLegacyTrackerHistoryImportsWithoutActiveTimers() throws {
        let schema = PersistenceService.schema
        let configuration = Self.uniqueInMemoryConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let data = try SampleData.bundledLegacyTrackerHistory()
        try DataExportImportService.importData(data, context: container.mainContext)

        let events = try container.mainContext.fetch(FetchDescriptor<CareEvent>())
        XCTAssertEqual(events.count, 4_774)
        XCTAssertEqual(events.filter { $0.type == .growth }.count, 10)
        XCTAssertEqual(events.filter { $0.type == .custom }.count, 35)
        XCTAssertFalse(events.contains(where: \.isActiveTimer))
        XCTAssertFalse(events.contains { event in
            guard event.type == .nursing else { return false }
            guard let side = event.nursingSide else { return true }
            return !NursingSide.allCases.contains(side)
        })

        let profile = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<CareProfile>()).first
        )
        let growthEvents = events.filter { $0.type == .growth }
        XCTAssertEqual(
            GrowthReferenceService.shared.chartDataForGrowthEntries(
                growthEvents,
                chartType: .weightForAge,
                profile: profile
            ).count,
            10
        )
        XCTAssertEqual(
            GrowthReferenceService.shared.chartDataForGrowthEntries(
                growthEvents,
                chartType: .lengthForAge,
                profile: profile
            ).count,
            4
        )
        XCTAssertEqual(
            GrowthReferenceService.shared.chartDataForGrowthEntries(
                growthEvents,
                chartType: .headCircumferenceForAge,
                profile: profile
            ).count,
            3
        )
    }

    @MainActor
    func testFirstLaunchSeedDoesNotCreateProfileOrBundledHistory() async throws {
        let container = try makeInMemoryContainer()

        await SampleData.seedIfNeeded(in: container.mainContext)

        let profiles = try container.mainContext.fetch(FetchDescriptor<CareProfile>())
        let events = try container.mainContext.fetch(FetchDescriptor<CareEvent>())
        let records = try container.mainContext.fetch(FetchDescriptor<SleepPredictionRecord>())

        XCTAssertTrue(profiles.isEmpty)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(records.isEmpty)
    }

    func testFirstRunOnboardingOnlyPresentsForNewEmptyStores() {
        XCTAssertTrue(FirstRunOnboarding.shouldPresent(
            hasCompleted: false,
            profiles: [],
            households: []
        ))
        XCTAssertFalse(FirstRunOnboarding.shouldPresent(
            hasCompleted: true,
            profiles: [],
            households: []
        ))

        let existingProfile = CareProfile(
            name: "Sample Child",
            birthDate: Date(),
            sex: .unknown
        )
        XCTAssertFalse(FirstRunOnboarding.shouldPresent(
            hasCompleted: false,
            profiles: [existingProfile],
            households: []
        ))
        XCTAssertFalse(FirstRunOnboarding.shouldPresent(
            hasCompleted: false,
            profiles: [],
            households: [Household(name: "Home")]
        ))
    }

    func testFirstRunICloudRestoreRequiresPrivateCloudStoreAndAvailableAccount() {
        XCTAssertEqual(
            ICloudRestoreService.eligibility(
                syncMode: .privateICloudSync,
                isUsingCloudKitStore: true,
                availability: .available
            ),
            .ready
        )

        for eligibility in [
            ICloudRestoreService.eligibility(
                syncMode: .localOnly,
                isUsingCloudKitStore: false,
                availability: .available
            ),
            ICloudRestoreService.eligibility(
                syncMode: .privateICloudSync,
                isUsingCloudKitStore: false,
                availability: .available
            ),
            ICloudRestoreService.eligibility(
                syncMode: .privateICloudSync,
                isUsingCloudKitStore: true,
                availability: .unavailable("No iCloud account")
            )
        ] {
            guard case .unavailable(let message) = eligibility else {
                XCTFail("Expected iCloud restore to be unavailable")
                continue
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    @MainActor
    func testFirstRunICloudRestoreDetectsImportedProfilesWithoutWriting() async throws {
        let container = try makeInMemoryContainer()
        let profile = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        container.mainContext.insert(profile)

        let outcome = await ICloudRestoreService.waitForImportedData(
            context: container.mainContext,
            waitDuration: .zero,
            pollInterval: .zero
        )

        XCTAssertEqual(outcome, .restored(profileCount: 1, householdCount: 0))
        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<CareProfile>()).map(\.id),
            [profile.id]
        )
    }

    @MainActor
    func testFirstRunICloudRestoreDetectsHouseholdDataWithoutCareProfiles() async throws {
        let container = try makeInMemoryContainer()
        let household = Household(name: "Home")
        container.mainContext.insert(household)

        let outcome = await ICloudRestoreService.waitForImportedData(
            context: container.mainContext,
            waitDuration: .zero,
            pollInterval: .zero
        )

        XCTAssertEqual(outcome, .restored(profileCount: 0, householdCount: 1))
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<CareProfile>()).isEmpty
        )
        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<Household>()).map(\.id),
            [household.id]
        )
    }

    @MainActor
    func testFirstRunICloudRestoreLeavesEmptyStoreUnchangedWhenNothingArrives() async throws {
        let container = try makeInMemoryContainer()

        let outcome = await ICloudRestoreService.waitForImportedData(
            context: container.mainContext,
            waitDuration: .zero,
            pollInterval: .zero
        )

        XCTAssertEqual(outcome, .noDataArrived)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CareProfile>()).isEmpty)
    }

    @MainActor
    func testFoodHomeBootstrapDoesNotCreateDefaultFoodData() throws {
        let container = try makeInMemoryContainer()

        FoodHomeBootstrapService.seedIfNeeded(context: container.mainContext)

        let households = try container.mainContext.fetch(FetchDescriptor<Household>())
        let stores = try container.mainContext.fetch(FetchDescriptor<FoodStore>())
        let storeSections = try container.mainContext.fetch(FetchDescriptor<FoodStoreSection>())
        let shoppingLists = try container.mainContext.fetch(FetchDescriptor<ShoppingList>())
        let shoppingItems = try container.mainContext.fetch(FetchDescriptor<ShoppingListItem>())
        let locations = try container.mainContext.fetch(FetchDescriptor<InventoryLocation>())
        let inventoryItems = try container.mainContext.fetch(FetchDescriptor<InventoryItem>())
        let mealPrepItems = try container.mainContext.fetch(FetchDescriptor<MealPrepItem>())
        let foodReminders = try container.mainContext.fetch(FetchDescriptor<FoodReminder>())

        XCTAssertEqual(households.count, 1)
        XCTAssertTrue(stores.isEmpty)
        XCTAssertTrue(storeSections.isEmpty)
        XCTAssertTrue(shoppingLists.isEmpty)
        XCTAssertTrue(shoppingItems.isEmpty)
        XCTAssertTrue(locations.isEmpty)
        XCTAssertTrue(inventoryItems.isEmpty)
        XCTAssertTrue(mealPrepItems.isEmpty)
        XCTAssertTrue(foodReminders.isEmpty)
    }

    @MainActor
    func testLegacyTrackerGrowthMigrationRecoversMeasurements() throws {
        let schema = PersistenceService.schema
        let configuration = Self.uniqueInMemoryConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let profile = CareProfile(
            name: "Test Child",
            birthDate: SampleData.defaultBirthDate,
            sex: .male
        )
        let birthDate = try XCTUnwrap(profile.birthDate)
        container.mainContext.insert(profile)
        let event = CareEvent(
            type: .custom,
            title: "Growth",
            startDate: birthDate,
            endDate: birthDate,
            notes: "Weight: 8.6lbs.oz\nLength: 1.68ft.in\nHead: 14.2in\nBirth visit"
        )
        container.mainContext.insert(event)
        try container.mainContext.save()

        XCTAssertEqual(
            try LegacyTrackerGrowthMigration.migrate(in: container.mainContext),
            1
        )
        XCTAssertEqual(event.type, .growth)
        XCTAssertEqual(event.weightPounds, 8)
        XCTAssertEqual(event.weightOunces ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(event.heightFeet, 1)
        XCTAssertEqual(event.heightInches ?? 0, 6.8, accuracy: 0.001)
        XCTAssertEqual(event.headCircumferenceInches ?? 0, 14.2, accuracy: 0.001)
        XCTAssertEqual(event.notes, "Birth visit")
        XCTAssertEqual(event.growthSource, .other)
        XCTAssertEqual(event.growthSex, .male)
        XCTAssertEqual(
            profile.birthWeightKilograms ?? 0,
            GrowthUnitConversion.poundsAndOuncesToKilograms(pounds: 8, ounces: 6),
            accuracy: 0.000_001
        )
    }

    @MainActor
    func testBundledHistoryPredictionCompletesQuickly() throws {
        let schema = PersistenceService.schema
        let configuration = Self.uniqueInMemoryConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        try DataExportImportService.importData(
            SampleData.bundledLegacyTrackerHistory(),
            context: container.mainContext
        )
        let profile = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<CareProfile>()).first
        )
        let events = try container.mainContext.fetch(FetchDescriptor<CareEvent>())

        let startedAt = CFAbsoluteTimeGetCurrent()
        _ = SleepPredictionEngine.predict(profile: profile, events: events)
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        XCTAssertLessThan(elapsed, 1)
    }

    func testWeightedMean() {
        let result = SleepPredictionEngine.weightedMean([
            WeightedValue(value: 100, weight: 1),
            WeightedValue(value: 200, weight: 3)
        ])
        XCTAssertNotNil(result)
        XCTAssertEqual(result ?? 0, 175, accuracy: 0.001)
    }

    func testWeightedMedianFavorsHeavierRecentValue() {
        let result = SleepPredictionEngine.weightedMedian([
            WeightedValue(value: 90, weight: 1),
            WeightedValue(value: 120, weight: 4),
            WeightedValue(value: 180, weight: 1)
        ])
        XCTAssertEqual(result, 120)
    }

    func testDateWindowCollapsesInstantEventsToSingleTime() {
        let date = Date(timeIntervalSinceReferenceDate: 10 * 60 * 60)
        let sameDisplayedMinute = date.addingTimeInterval(30)

        XCTAssertEqual(
            DateFormatting.window(start: date, end: date),
            DateFormatting.time.string(from: date)
        )
        XCTAssertEqual(
            DateFormatting.window(start: date, end: sameDisplayedMinute),
            DateFormatting.time.string(from: date)
        )

        let nextDaySameTime = date.addingTimeInterval(24 * 60 * 60)
        XCTAssertEqual(
            DateFormatting.window(start: date, end: nextDaySameTime),
            "\(DateFormatting.day.string(from: date)) \(DateFormatting.time.string(from: date))-\(DateFormatting.day.string(from: nextDaySameTime)) \(DateFormatting.time.string(from: nextDaySameTime))"
        )
    }

    @MainActor
    func testDebugSimulatorSmokeSeedKeepsInstantCareEventsWithoutEndDates() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        DebugSimulatorSmokeSeedService.seedIfNeeded(
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )

        let events = try context.fetch(FetchDescriptor<CareEvent>())
        let diaper = try XCTUnwrap(events.first { $0.type == .diaper })
        let medicine = try XCTUnwrap(events.first { $0.type == .medicine })
        let bottle = try XCTUnwrap(events.first { $0.type == .feed })

        XCTAssertNil(diaper.endDate)
        XCTAssertNil(medicine.endDate)
        XCTAssertNotNil(bottle.endDate)
    }

    func testOutlierClippingRemovesExtremeWakeWindow() {
        let now = Date()
        let samples = [90, 95, 100, 105, 300].enumerated().map {
            WakeWindowSample(
                minutes: Double($0.element),
                napIndex: 1,
                date: now.addingTimeInterval(Double($0.offset) * 60),
                weight: 1
            )
        }
        XCTAssertEqual(SleepPredictionEngine.clipOutliers(samples).count, 4)
    }

    func testNapIndexDetection() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date())
        let first = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(9 * 3600),
            endDate: day.addingTimeInterval(10 * 3600)
        )
        first.sleepKind = .nap
        let second = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(13 * 3600),
            endDate: day.addingTimeInterval(14 * 3600)
        )
        second.sleepKind = .nap
        XCTAssertEqual(
            SleepPredictionEngine.napIndex(for: second, among: [first, second], calendar: calendar),
            2
        )
    }

    func testWakeWindowExtraction() {
        let day = Calendar.current.startOfDay(for: Date())
        let first = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(7 * 3600),
            endDate: day.addingTimeInterval(8 * 3600)
        )
        first.sleepKind = .nightSleep
        let second = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(10 * 3600),
            endDate: day.addingTimeInterval(11 * 3600)
        )
        second.sleepKind = .nap
        let samples = SleepPredictionEngine.wakeWindowSamples(from: [first, second])
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.minutes, 120)
        XCTAssertEqual(samples.first?.napIndex, 1)
    }

    func testWakeWindowSamplesIgnoreNightWakingLogs() {
        let day = Calendar.current.startOfDay(for: Date())
        let first = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(7 * 3600),
            endDate: day.addingTimeInterval(8 * 3600)
        )
        first.sleepKind = .nightSleep
        let waking = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(9 * 3600),
            endDate: day.addingTimeInterval(9 * 3600 + 10 * 60)
        )
        waking.sleepKind = .nightWaking
        let second = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(11 * 3600),
            endDate: day.addingTimeInterval(12 * 3600)
        )
        second.sleepKind = .nap

        let samples = SleepPredictionEngine.wakeWindowSamples(from: [first, waking, second])

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.minutes, 180)
        XCTAssertEqual(samples.first?.napIndex, 1)
    }

    func testConfidenceRisesWithStableSamples() {
        let sparse = SleepPredictionEngine.confidenceScore(sampleCount: 2, variability: 30)
        let mature = SleepPredictionEngine.confidenceScore(sampleCount: 18, variability: 10)
        XCTAssertGreaterThan(mature, sparse)
    }

    func testAccuracyCalculationAndBias() {
        let records = [-20.0, 10.0, 30.0].enumerated().map { offset, error in
            let prediction = SleepPrediction(
                predictedStart: Date(),
                predictedWindowStart: Date(),
                predictedWindowEnd: Date(),
                predictionKind: .nap,
                confidence: 0.7,
                confidenceLabel: .medium,
                explanation: [],
                contributingFactors: [],
                napIndex: 2
            )
            let record = SleepPredictionRecord(prediction: prediction, basedOnLastSleepEventID: nil)
            record.generatedAt = Date().addingTimeInterval(Double(offset) * 60)
            record.errorMinutes = error
            record.wasInsidePredictedWindow = offset != 2
            return record
        }
        let accuracy = PredictionTuningService.accuracy(records: records)
        XCTAssertEqual(accuracy.meanAbsoluteErrorMinutes ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(accuracy.insideWindowPercentage ?? 0, 66.666, accuracy: 0.01)
        XCTAssertEqual(accuracy.averageBiasMinutes ?? 0, 6.666, accuracy: 0.01)
        XCTAssertEqual(
            PredictionTuningService.conservativeBiasCorrection(records: records, napIndex: 2),
            1.666,
            accuracy: 0.01
        )
    }

    func testInsightsDailySleepTotalsGroupEarlyMorningNightWithPriorDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        let evening = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(20 * 3600),
            endDate: day.addingTimeInterval(23 * 3600)
        )
        evening.sleepKind = .nightSleep
        let morning = CareEvent(
            type: .sleep,
            startDate: nextDay.addingTimeInterval(1 * 3600),
            endDate: nextDay.addingTimeInterval(6 * 3600)
        )
        morning.sleepKind = .nightSleep
        let nap = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(10 * 3600),
            endDate: day.addingTimeInterval(11 * 3600)
        )
        nap.sleepKind = .nap

        let totals = InsightsAnalyticsService.dailySleepTotals(
            events: [evening, morning, nap],
            range: day..<nextDay,
            calendar: calendar
        )

        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].nightMinutes, 480, accuracy: 0.001)
        XCTAssertEqual(totals[0].daytimeMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(totals[0].napCount, 1)
    }

    func testNightWakingLogsAreTrackedSeparatelyFromSleepTotals() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        let nightSleep = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(20 * 3600),
            endDate: day.addingTimeInterval(23 * 3600)
        )
        nightSleep.sleepKind = .nightSleep
        let nightWaking = CareEvent(
            type: .sleep,
            startDate: nextDay.addingTimeInterval(1 * 3600),
            endDate: nextDay.addingTimeInterval(1 * 3600 + 20 * 60)
        )
        nightWaking.sleepKind = .nightWaking
        let nap = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(10 * 3600),
            endDate: day.addingTimeInterval(11 * 3600)
        )
        nap.sleepKind = .nap

        let totals = InsightsAnalyticsService.dailySleepTotals(
            events: [nightSleep, nightWaking, nap],
            range: day..<nextDay,
            calendar: calendar
        )

        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].nightMinutes, 180, accuracy: 0.001)
        XCTAssertEqual(totals[0].daytimeMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(totals[0].nightWakingCount, 1)
        XCTAssertEqual(totals[0].nightWakingMinutes, 20, accuracy: 0.001)
    }

    func testNightSleepScoreUsesNightSleepSegmentsAndWakeGaps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        let firstSegment = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(20 * 3600),
            endDate: nextDay
        )
        firstSegment.sleepKind = .nightSleep
        let secondSegment = CareEvent(
            type: .sleep,
            startDate: nextDay.addingTimeInterval(30 * 60),
            endDate: nextDay.addingTimeInterval(4 * 3600)
        )
        secondSegment.sleepKind = .nightSleep
        let nap = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(12 * 3600),
            endDate: day.addingTimeInterval(13 * 3600)
        )
        nap.sleepKind = .nap

        let scores = InsightsAnalyticsService.nightSleepScores(
            events: [firstSegment, secondSegment, nap],
            range: day..<nextDay,
            calendar: calendar
        )

        XCTAssertEqual(scores.count, 1)
        XCTAssertEqual(scores[0].totalSleepMinutes, 450, accuracy: 0.001)
        XCTAssertEqual(scores[0].wakeEventCount, 1)
        XCTAssertEqual(scores[0].totalWakeMinutes, 30, accuracy: 0.001)
        XCTAssertEqual(scores[0].wakeDurationsMinutes, [30])
        XCTAssertEqual(scores[0].longestStretchMinutes, 240, accuracy: 0.001)
        XCTAssertEqual(scores[0].score, 76)
    }

    func testNightSleepScoreUsesExplicitNightWakingLogsWhenPresent() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        let firstSegment = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(20 * 3600),
            endDate: nextDay
        )
        firstSegment.sleepKind = .nightSleep
        let explicitWaking = CareEvent(
            type: .sleep,
            startDate: nextDay.addingTimeInterval(5 * 60),
            endDate: nextDay.addingTimeInterval(20 * 60)
        )
        explicitWaking.sleepKind = .nightWaking
        let secondSegment = CareEvent(
            type: .sleep,
            startDate: nextDay.addingTimeInterval(30 * 60),
            endDate: nextDay.addingTimeInterval(4 * 3600)
        )
        secondSegment.sleepKind = .nightSleep

        let scores = InsightsAnalyticsService.nightSleepScores(
            events: [firstSegment, explicitWaking, secondSegment],
            range: day..<nextDay,
            calendar: calendar
        )

        XCTAssertEqual(scores.count, 1)
        XCTAssertEqual(scores[0].wakeEventCount, 1)
        XCTAssertEqual(scores[0].totalWakeMinutes, 15, accuracy: 0.001)
        XCTAssertEqual(scores[0].wakeDurationsMinutes, [15])
    }

    func testInsightsCustomDateRangeIncludesBothSelectedDaysOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 1)
        )!
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let thirdDay = calendar.date(byAdding: .day, value: 2, to: firstDay)!
        let events = [firstDay, secondDay, thirdDay].map { day in
            let event = CareEvent(
                type: .sleep,
                startDate: day.addingTimeInterval(10 * 3600),
                endDate: day.addingTimeInterval(11 * 3600)
            )
            event.sleepKind = .nap
            return event
        }

        let snapshot = InsightsAnalyticsService.snapshot(
            profileName: "Test Child",
            events: events,
            records: [],
            periodStart: firstDay,
            periodEnd: secondDay,
            now: thirdDay,
            compareToPrevious: true,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.periodStart, firstDay)
        XCTAssertEqual(snapshot.periodEnd, thirdDay)
        XCTAssertEqual(snapshot.dailySleep.count, 2)
        XCTAssertEqual(
            snapshot.dailySleep.reduce(0) { $0 + $1.totalMinutes },
            120,
            accuracy: 0.001
        )
        XCTAssertEqual(snapshot.comparisonLabel, "Compared with the previous 2 days")
    }

    func testInsightsSnapshotIncludesSleepPressureBeforeSleep() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        )
        let firstNap = makeSleep(
            kind: .nap,
            start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 7))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8))!
        )
        let secondNap = makeSleep(
            kind: .nap,
            start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10, minute: 15))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 11))!
        )

        let snapshot = InsightsAnalyticsService.snapshot(
            profileName: "Test Child",
            profile: profile,
            events: [firstNap, secondNap],
            records: [],
            periodStart: day,
            periodEnd: day,
            now: day,
            compareToPrevious: false,
            calendar: calendar
        )

        let pressurePoint = try XCTUnwrap(snapshot.sleepPressureBeforeSleep.first)
        XCTAssertEqual(pressurePoint.eventID, secondNap.id)
        XCTAssertEqual(pressurePoint.band, .ready)
        XCTAssertTrue(snapshot.wakeMetrics.contains { $0.title == "Pressure before sleep" })
        XCTAssertTrue(snapshot.wakeMetrics.contains { $0.title == "Ready/high starts" })
        XCTAssertEqual(snapshot.sleepPressureBandCounts.first?.category, SleepPressureBand.ready.displayName)
        XCTAssertEqual(snapshot.sleepPressureBandCounts.first?.value, 1)
        XCTAssertEqual(snapshot.sleepPressureAverages.first?.category, "Nap 2")
        XCTAssertEqual(try XCTUnwrap(snapshot.sleepPressureAverages.first?.value), pressurePoint.score, accuracy: 0.001)
    }

    @MainActor
    func testInsightsViewModelClampsCustomDateRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 12)
        )!
        let viewModel = InsightsViewModel(now: now, calendar: calendar)
        viewModel.selectedRange = .custom
        viewModel.refresh(
            profileName: "Test Child",
            events: [],
            records: [],
            now: now
        )

        viewModel.updateCustomStart(now)
        viewModel.updateCustomEnd(
            calendar.date(byAdding: .day, value: -3, to: now)!
        )

        XCTAssertEqual(
            Calendar.current.startOfDay(for: viewModel.customEndDate),
            Calendar.current.startOfDay(for: viewModel.customStartDate)
        )
    }

    @MainActor
    func testInsightsViewModelCalculatesSleepPressureOnlyForWakeWindows() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 804_000_000))
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(byAdding: .day, value: -180, to: day)!
        )
        let firstNap = makeSleep(
            kind: .nap,
            start: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)!,
            end: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        )
        let secondNap = makeSleep(
            kind: .nap,
            start: calendar.date(bySettingHour: 10, minute: 15, second: 0, of: day)!,
            end: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day)!
        )
        let viewModel = InsightsViewModel(now: day, calendar: calendar)

        viewModel.refresh(
            profileName: "Test Child",
            profile: profile,
            events: [firstNap, secondNap],
            records: [],
            now: day
        )
        XCTAssertTrue(viewModel.snapshot.sleepPressureBeforeSleep.isEmpty)

        viewModel.selectedSection = .wakeWindows
        viewModel.rebuild()

        XCTAssertFalse(viewModel.snapshot.sleepPressureBeforeSleep.isEmpty)
    }

    func testInsightsBedtimeExtractionIgnoresEarlyMorningSegments() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let end = calendar.date(byAdding: .day, value: 2, to: day)!
        let evening = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(20 * 3600),
            endDate: day.addingTimeInterval(23 * 3600)
        )
        evening.sleepKind = .nightSleep
        let earlyMorning = CareEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(26 * 3600),
            endDate: day.addingTimeInterval(29 * 3600)
        )
        earlyMorning.sleepKind = .nightSleep

        let points = InsightsAnalyticsService.bedtimeExtraction(
            events: [evening, earlyMorning],
            range: day..<end,
            calendar: calendar
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.value, 1_200)
    }

    func testInsightsFeedToSleepIntervalsUsesLatestCareSession() {
        let now = Date()
        let nursing = CareEvent(
            type: .nursing,
            startDate: now,
            endDate: now.addingTimeInterval(10 * 60)
        )
        nursing.nursingSide = .left
        let sleep = CareEvent(
            type: .sleep,
            startDate: now.addingTimeInterval(25 * 60),
            endDate: now.addingTimeInterval(60 * 60)
        )
        sleep.sleepKind = .nap

        let intervals = InsightsAnalyticsService.feedToSleepIntervals(
            events: [nursing, sleep],
            range: now.addingTimeInterval(-60)..<now.addingTimeInterval(120 * 60)
        )

        XCTAssertEqual(intervals, [25])
    }

    func testInsightsDiaperAndActivityAggregation() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let end = calendar.startOfNextDay(for: day)
        let wet = CareEvent(type: .diaper, startDate: day.addingTimeInterval(3600), endDate: nil)
        wet.diaperKind = .wet
        let both = CareEvent(type: .diaper, startDate: day.addingTimeInterval(7200), endDate: nil)
        both.diaperKind = .both
        let tummy = CareEvent(
            type: .activity,
            startDate: day.addingTimeInterval(10_800),
            endDate: day.addingTimeInterval(12_000)
        )
        tummy.activityType = .tummyTime

        let diapers = InsightsAnalyticsService.diaperAggregation(
            events: [wet, both, tummy],
            range: day..<end,
            calendar: calendar
        )
        let activities = InsightsAnalyticsService.activityAggregation(
            events: [wet, both, tummy],
            range: day..<end,
            calendar: calendar
        )

        XCTAssertEqual(diapers.first?.wet, 1)
        XCTAssertEqual(diapers.first?.both, 1)
        XCTAssertEqual(activities.first?.tummyMinutes ?? 0, 20, accuracy: 0.001)
    }

    func testInsightsTrendDetectionAndStatistics() {
        XCTAssertEqual(
            InsightsAnalyticsService.trendDirection(current: 110, previous: 100),
            .up
        )
        XCTAssertEqual(
            InsightsAnalyticsService.trendDirection(current: 102, previous: 100),
            .flat
        )
        XCTAssertEqual(InsightsAnalyticsService.median([1, 4, 2, 3]), 2.5)
        XCTAssertEqual(InsightsAnalyticsService.interquartileRange([1, 2, 3, 4]), 1.5)
    }

    func testInsightsPredictionErrorUsesEarlyNegativeLatePositiveConvention() {
        let prediction = SleepPrediction(
            predictedStart: Date(),
            predictedWindowStart: Date(),
            predictedWindowEnd: Date(),
            predictionKind: .nap,
            confidence: 0.7,
            confidenceLabel: .medium,
            explanation: [],
            contributingFactors: [],
            napIndex: 1
        )
        let record = SleepPredictionRecord(prediction: prediction, basedOnLastSleepEventID: nil)
        record.actualSleepStart = record.predictedStart.addingTimeInterval(10 * 60)
        record.errorMinutes = 10
        record.wasInsidePredictedWindow = false
        let range = record.predictedStart.addingTimeInterval(-60)..<record.predictedStart.addingTimeInterval(3600)

        let errors = InsightsAnalyticsService.predictionAccuracy(records: [record], range: range)

        XCTAssertEqual(errors.first?.errorMinutes, -10)
    }

    @MainActor
    func testEventTimerPriorityPrefersSleepThenNursing() {
        let bath = CareEvent(type: .activity, startDate: Date())
        bath.activityType = .bath
        let nursing = CareEvent(type: .nursing, startDate: Date())
        nursing.nursingSide = .left
        nursing.activeNursingSide = .left
        let pumping = CareEvent(type: .pumping, startDate: Date())
        let feed = CareEvent(type: .feed, startDate: Date())
        let sleep = CareEvent(type: .sleep, startDate: Date())
        sleep.sleepKind = .nap

        XCTAssertEqual(
            EventTimerService.primaryActiveEvent(in: [bath, nursing, sleep])?.id,
            sleep.id
        )
        XCTAssertEqual(
            EventTimerService.primaryActiveEvent(in: [bath, nursing])?.id,
            nursing.id
        )
        XCTAssertEqual(
            EventTimerService.primaryActiveEvent(in: [feed, pumping])?.id,
            pumping.id
        )
    }

    @MainActor
    func testWidgetSnapshotIncludesPrimaryTimerAndAdditionalCount() {
        let start = Date().addingTimeInterval(-600)
        let sleep = CareEvent(type: .sleep, startDate: start)
        sleep.sleepKind = .nap
        let bath = CareEvent(type: .activity, startDate: start)
        bath.activityType = .bath

        let snapshot = WidgetSnapshotService.makeSnapshot(
            babyName: "Test Child",
            events: [bath, sleep],
            prediction: nil
        )

        XCTAssertEqual(snapshot.activeTimer?.id, sleep.id)
        XCTAssertEqual(snapshot.activeTimer?.eventLabel, "Sleeping")
        XCTAssertEqual(snapshot.activeTimer?.additionalActiveCount, 1)
    }

    @MainActor
    func testWidgetSnapshotIncludesRankedQuickActions() {
        let now = Date(timeIntervalSinceReferenceDate: 340_000)
        let feed = CareEvent(type: .feed, startDate: now.addingTimeInterval(-3_600))
        let diaper = CareEvent(type: .diaper, startDate: now.addingTimeInterval(-7_200))
        let sleep = CareEvent(
            type: .sleep,
            startDate: now.addingTimeInterval(-14_400),
            endDate: now.addingTimeInterval(-10_800)
        )

        let snapshot = WidgetSnapshotService.makeSnapshot(
            profileType: .child,
            babyName: "Test Child",
            events: [feed, diaper, sleep],
            prediction: nil,
            now: now
        )

        let actionIDs = snapshot.resolvedQuickActions.map(\.id)
        XCTAssertTrue(actionIDs.contains("feed"))
        XCTAssertTrue(actionIDs.contains("diaper"))
        XCTAssertTrue(actionIDs.contains("sleep"))
        XCTAssertEqual(snapshot.resolvedQuickActions.count, 6)
    }

    @MainActor
    func testAdultWidgetQuickActionsExcludeChildCare() {
        let snapshot = WidgetSnapshotService.makeSnapshot(
            profileType: .adult,
            babyName: "Test Adult",
            events: [],
            prediction: nil
        )

        let actionIDs = Set(snapshot.resolvedQuickActions.map(\.id))
        XCTAssertTrue(actionIDs.contains("medicine"))
        XCTAssertTrue(actionIDs.contains("symptom"))
        XCTAssertFalse(actionIDs.contains("tummy-time"))
        XCTAssertFalse(actionIDs.contains("diaper"))
        XCTAssertFalse(actionIDs.contains("feed"))
    }

    @MainActor
    func testWidgetRefreshPublishesStoppedAndSavedTimerStateBeforeReturning() throws {
        let container = try makeInMemoryContainer()
        let now = Date()
        let event = try XCTUnwrap(EventTimerService.start(
            type: .sleep,
            sleepKind: .nap,
            caregiverName: "Caregiver 1",
            events: [],
            context: container.mainContext,
            at: now.addingTimeInterval(-300)
        ))

        WidgetSnapshotService.refresh(
            profile: nil,
            events: [event],
            prediction: nil
        )
        XCTAssertEqual(WidgetSnapshotService.read().activeTimer?.id, event.id)
        XCTAssertEqual(WidgetSnapshotService.read().activeTimer?.resolvedIsRunning, true)

        EventTimerService.stop(event, context: container.mainContext, at: now)
        WidgetSnapshotService.refresh(
            profile: nil,
            events: [event],
            prediction: nil
        )
        XCTAssertEqual(WidgetSnapshotService.read().activeTimer?.id, event.id)
        XCTAssertEqual(WidgetSnapshotService.read().activeTimer?.resolvedIsRunning, false)

        EventTimerService.save(event, context: container.mainContext, at: now)
        WidgetSnapshotService.refresh(
            profile: nil,
            events: [event],
            prediction: nil
        )
        XCTAssertNil(WidgetSnapshotService.read().activeTimer)
    }

    @MainActor
    func testQuickActionsOmitStartsForTimerTypesThatAreAlreadyActive() {
        let now = Date(timeIntervalSinceReferenceDate: 342_000)
        let sleep = CareEvent(
            type: .sleep,
            startDate: now.addingTimeInterval(-600)
        )
        let nursing = CareEvent(
            type: .nursing,
            startDate: now.addingTimeInterval(-300)
        )
        nursing.nursingSide = .left
        nursing.activeNursingSide = .left
        let activeTimer = WidgetSnapshotService.activeSnapshot(
            event: nursing,
            babyName: "Test Child",
            additionalActiveCount: 1,
            now: now
        )

        let actions = WidgetSnapshotService.makeQuickActions(
            profileType: .child,
            events: [sleep, nursing],
            activeTimer: activeTimer,
            pinnedActionIDs: ["sleep", "nursing-left"],
            now: now
        )
        let actionIDs = Set(actions.map(\.id))

        XCTAssertFalse(actionIDs.contains("sleep"))
        XCTAssertFalse(actionIDs.contains("nursing-left"))
        XCTAssertFalse(actionIDs.contains("nursing-right"))
        XCTAssertTrue(actionIDs.contains("active-timer"))
    }

    @MainActor
    func testDogQuickActionsPreferDogCareEvents() {
        let now = Date(timeIntervalSinceReferenceDate: 345_000)
        let food = CareEvent(type: .food, startDate: now.addingTimeInterval(-3_600))
        let walk = CareEvent(
            type: .walk,
            startDate: now.addingTimeInterval(-9_000),
            endDate: now.addingTimeInterval(-7_200)
        )

        let actions = WidgetSnapshotService.makeQuickActions(
            profileType: .dog,
            events: [food, walk],
            now: now
        )

        let actionIDs = actions.map(\.id)
        XCTAssertTrue(actionIDs.contains("food"))
        XCTAssertTrue(actionIDs.contains("walk"))
        XCTAssertFalse(actionIDs.contains("sleep"))
    }

    @MainActor
    func testQuickActionsIncludeRepeatLastAndPinnedActionsFirst() {
        let now = Date(timeIntervalSinceReferenceDate: 346_000)
        let feed = CareEvent(type: .feed, startDate: now.addingTimeInterval(-1_800), endDate: now.addingTimeInterval(-1_800))
        feed.feedKind = .bottle
        let diaper = CareEvent(type: .diaper, startDate: now.addingTimeInterval(-7_200), endDate: now.addingTimeInterval(-7_200))
        diaper.diaperKind = .wet

        let actions = WidgetSnapshotService.makeQuickActions(
            profileType: .child,
            events: [feed, diaper],
            pinnedActionIDs: ["medicine"],
            now: now
        )

        XCTAssertEqual(actions.first?.id, "medicine")
        XCTAssertEqual(actions.first?.resolvedIsPinned, true)
        XCTAssertTrue(actions.map(\.id).contains("repeat-last"))
        XCTAssertEqual(actions.first(where: { $0.id == "repeat-last" })?.subtitle, "Bottle")
    }

    @MainActor
    func testChildQuickActionsRespectCategoryVisibilityAndIncludeProductionActions() {
        let profileID = UUID()
        CareCategoryPreferenceStore.reset(profileID: profileID)
        let now = Date(timeIntervalSinceReferenceDate: 346_500)

        var actions = WidgetSnapshotService.makeQuickActions(
            profileID: profileID,
            profileType: .child,
            events: [],
            pinnedActionIDs: ["pumping", "potty"],
            now: now
        )
        XCTAssertTrue(actions.map(\.id).contains("pumping"))
        XCTAssertTrue(actions.map(\.id).contains("potty"))

        CareCategoryPreferenceStore.setHidden(true, type: .pumping, profileID: profileID)
        CareCategoryPreferenceStore.setHidden(true, type: .potty, profileID: profileID)

        actions = WidgetSnapshotService.makeQuickActions(
            profileID: profileID,
            profileType: .child,
            events: [],
            pinnedActionIDs: ["pumping"],
            now: now
        )
        XCTAssertFalse(actions.map(\.id).contains("pumping"))
        XCTAssertFalse(actions.map(\.id).contains("potty"))

        CareCategoryPreferenceStore.reset(profileID: profileID)
        XCTAssertTrue(CareCategoryPreferenceStore.hiddenTypes(profileID: profileID).isEmpty)
    }

    @MainActor
    func testQuickActionsRespectProfileScopeAndHiddenRepeatSources() {
        let profileID = UUID()
        let otherProfileID = UUID()
        CareCategoryPreferenceStore.reset(profileID: profileID)
        let now = Date(timeIntervalSinceReferenceDate: 346_800)

        let hiddenPump = CareEvent(
            profileID: profileID,
            type: .pumping,
            startDate: now.addingTimeInterval(-1_200),
            endDate: now.addingTimeInterval(-900)
        )
        hiddenPump.amountOz = 2
        let ownFeed = CareEvent(
            profileID: profileID,
            type: .feed,
            startDate: now.addingTimeInterval(-2_400),
            endDate: now.addingTimeInterval(-2_400)
        )
        ownFeed.feedKind = .bottle
        let otherActiveSleep = CareEvent(
            profileID: otherProfileID,
            type: .sleep,
            startDate: now.addingTimeInterval(-600)
        )

        CareCategoryPreferenceStore.setHidden(true, type: .pumping, profileID: profileID)
        let actions = WidgetSnapshotService.makeQuickActions(
            profileID: profileID,
            profileType: .child,
            events: [hiddenPump, ownFeed, otherActiveSleep],
            pinnedActionIDs: ["sleep"],
            now: now
        )

        XCTAssertFalse(actions.map(\.id).contains("pumping"))
        XCTAssertEqual(actions.first?.id, "sleep")
        XCTAssertEqual(actions.first(where: { $0.id == "repeat-last" })?.subtitle, "Bottle")

        CareCategoryPreferenceStore.reset(profileID: profileID)
    }

    @MainActor
    func testRepeatEventClonesStructuredDetailsAtCurrentTime() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profileID = UUID()
        let oldStart = Date(timeIntervalSinceReferenceDate: 300_000)
        let now = Date(timeIntervalSinceReferenceDate: 350_000)
        let source = CareEvent(
            profileID: profileID,
            type: .diaper,
            startDate: oldStart,
            endDate: oldStart,
            caregiverName: "Caregiver A",
            notes: "After lunch"
        )
        source.profileTypeSnapshot = .child
        source.diaperKind = .both
        source.peeAmount = .medium
        source.pooAmount = .little
        source.pooColor = .brown
        source.pooTexture = .soft
        source.diaperRash = true

        let repeated = try XCTUnwrap(EventMutationService.repeatEvent(
            source,
            caregiverName: "Caregiver B",
            profileID: profileID,
            profileType: .child,
            context: context,
            at: now
        ))

        XCTAssertNotEqual(repeated.id, source.id)
        XCTAssertEqual(repeated.profileID, profileID)
        XCTAssertEqual(repeated.startDate, now)
        XCTAssertEqual(repeated.endDate, now)
        XCTAssertEqual(repeated.caregiverName, "Caregiver B")
        XCTAssertEqual(repeated.notes, "After lunch")
        XCTAssertEqual(repeated.diaperKind, .both)
        XCTAssertEqual(repeated.peeAmount, .medium)
        XCTAssertEqual(repeated.pooAmount, .little)
        XCTAssertEqual(repeated.pooColor, .brown)
        XCTAssertEqual(repeated.pooTexture, .soft)
        XCTAssertEqual(repeated.diaperRash, true)
    }

    @MainActor
    func testRepeatEventClonesProductionChildCareDetails() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profileID = UUID()
        let oldStart = Date(timeIntervalSinceReferenceDate: 305_000)
        let now = Date(timeIntervalSinceReferenceDate: 355_000)
        let solid = CareEvent(
            profileID: profileID,
            type: .feed,
            startDate: oldStart,
            endDate: oldStart,
            notes: "First try"
        )
        solid.profileTypeSnapshot = .child
        solid.feedKind = .solid
        solid.foodDescription = "Pear"
        solid.solidFeedingStyle = .combination
        solid.solidTexture = .puree
        solid.solidReaction = .loved
        solid.solidAllergenExposure = false
        solid.solidSensitivityObserved = false

        let repeatedSolid = try XCTUnwrap(EventMutationService.repeatEvent(
            solid,
            caregiverName: nil,
            profileID: profileID,
            profileType: .child,
            context: context,
            at: now
        ))

        XCTAssertEqual(repeatedSolid.feedKind, FeedKind.solid)
        XCTAssertEqual(repeatedSolid.foodDescription, "Pear")
        XCTAssertEqual(repeatedSolid.solidFeedingStyle, SolidFeedingStyle.combination)
        XCTAssertEqual(repeatedSolid.solidTexture, SolidTexture.puree)
        XCTAssertEqual(repeatedSolid.solidReaction, SolidReaction.loved)
        XCTAssertEqual(repeatedSolid.solidAllergenExposure, false)
        XCTAssertEqual(repeatedSolid.solidSensitivityObserved, false)

        let potty = CareEvent(
            profileID: profileID,
            type: .potty,
            startDate: oldStart,
            endDate: oldStart
        )
        potty.profileTypeSnapshot = .child
        potty.childPottyKind = .pee
        potty.childPottyLocation = .trainingPants
        potty.childPottyAccident = true
        potty.peeAmount = .little

        let repeatedPotty = try XCTUnwrap(EventMutationService.repeatEvent(
            potty,
            caregiverName: nil,
            profileID: profileID,
            profileType: .child,
            context: context,
            at: now
        ))

        XCTAssertEqual(repeatedPotty.childPottyKind, ChildPottyKind.pee)
        XCTAssertEqual(repeatedPotty.childPottyLocation, ChildPottyLocation.trainingPants)
        XCTAssertEqual(repeatedPotty.childPottyAccident, true)
        XCTAssertEqual(repeatedPotty.peeAmount, DiaperAmount.little)
    }

    @MainActor
    func testFoodWidgetSnapshotIncludesActiveShoppingListItems() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let store = FoodStore(householdID: household.id, name: "Trader Joe's", sortOrder: 0)
        let section = FoodStoreSection(
            householdID: household.id,
            storeID: store.id,
            name: "Produce",
            sortOrder: 0
        )
        let list = ShoppingList(
            householdID: household.id,
            name: "Trader Joe's",
            storeID: store.id,
            listType: .store,
            sortOrder: 0
        )
        let bananas = ShoppingListItem(
            householdID: household.id,
            shoppingListID: list.id,
            name: "Bananas",
            quantity: 6,
            unit: "ct",
            storeSectionID: section.id,
            sortOrder: 1
        )
        let spinach = ShoppingListItem(
            householdID: household.id,
            shoppingListID: list.id,
            name: "Spinach",
            storeSectionID: section.id,
            sortOrder: 0
        )
        let checked = ShoppingListItem(
            householdID: household.id,
            shoppingListID: list.id,
            name: "Cereal",
            isChecked: true,
            sortOrder: 2
        )

        context.insert(household)
        context.insert(store)
        context.insert(section)
        context.insert(list)
        context.insert(bananas)
        context.insert(spinach)
        context.insert(checked)
        try context.save()

        let snapshot = WidgetSnapshotService.makeFoodSnapshot(context: context)

        XCTAssertEqual(snapshot.selectedList?.id, list.id)
        XCTAssertEqual(snapshot.selectedList?.activeItemCount, 2)
        XCTAssertEqual(snapshot.selectedList?.checkedItemCount, 1)
        XCTAssertEqual(snapshot.selectedList?.topActiveItems.map(\.name), ["Spinach", "Bananas"])
        XCTAssertEqual(snapshot.selectedList?.topActiveItems.last?.quantityText, "6 ct")
        XCTAssertEqual(snapshot.selectedList?.topActiveItems.first?.sectionName, "Produce")
    }

    @MainActor
    func testStoppedTimerDraftAppearsPausedButNotInDailySummary() throws {
        let container = try makeInMemoryContainer()
        let now = Date(timeIntervalSinceReferenceDate: 350_000)
        let event = try XCTUnwrap(EventTimerService.start(
            type: .nursing,
            nursingSide: .left,
            caregiverName: "Caregiver 1",
            events: [],
            context: container.mainContext,
            at: now.addingTimeInterval(-300)
        ))
        EventTimerService.stop(
            event,
            context: container.mainContext,
            at: now
        )

        let snapshot = WidgetSnapshotService.makeSnapshot(
            babyName: "Test Child",
            events: [event],
            prediction: nil,
            now: now
        )

        XCTAssertEqual(snapshot.activeTimer?.resolvedIsRunning, false)
        XCTAssertEqual(
            snapshot.activeTimer?.resolvedElapsedSeconds ?? 0,
            300,
            accuracy: 0.001
        )
        XCTAssertEqual(snapshot.todaySummary.careSessionCount, 0)
    }

    @MainActor
    func testActivityTypesAreScopedToTheSelectedProfileType() {
        let childActivities = ActivityType.cases(for: .child)
        let adultActivities = ActivityType.cases(for: .adult)

        XCTAssertTrue(childActivities.contains(.tummyTime))
        XCTAssertFalse(childActivities.contains(.physicalTherapy))
        XCTAssertTrue(adultActivities.contains(.exercise))
        XCTAssertTrue(adultActivities.contains(.bath))
        XCTAssertFalse(adultActivities.contains(.tummyTime))
        XCTAssertFalse(adultActivities.contains(.storyTime))
        XCTAssertTrue(ActivityType.cases(for: .dog).isEmpty)
    }

    @MainActor
    func testAdultActivityTimerRejectsChildSubtype() throws {
        let container = try makeInMemoryContainer()
        let profileID = UUID()

        let rejected = EventTimerService.start(
            type: .activity,
            activityType: .tummyTime,
            caregiverName: "Caregiver 1",
            events: [],
            context: container.mainContext,
            profileID: profileID,
            profileType: .adult
        )
        let accepted = EventTimerService.start(
            type: .activity,
            activityType: .physicalTherapy,
            caregiverName: "Caregiver 1",
            events: [],
            context: container.mainContext,
            profileID: profileID,
            profileType: .adult
        )

        XCTAssertNil(rejected)
        XCTAssertEqual(accepted?.activityType, .physicalTherapy)
        XCTAssertEqual(accepted?.profileTypeSnapshot, .adult)
    }

    @MainActor
    func testTimerStartRejectsSameTypeDraftButAllowsDifferentType() throws {
        let container = try makeInMemoryContainer()
        let now = Date(timeIntervalSinceReferenceDate: 355_000)
        let sleep = try XCTUnwrap(EventTimerService.start(
            type: .sleep,
            sleepKind: .nap,
            caregiverName: "Caregiver 1",
            events: [],
            context: container.mainContext,
            at: now.addingTimeInterval(-120)
        ))
        EventTimerService.stop(
            sleep,
            context: container.mainContext,
            at: now
        )

        let duplicateSleep = EventTimerService.start(
            type: .sleep,
            sleepKind: .nightSleep,
            caregiverName: "Caregiver 1",
            events: [sleep],
            context: container.mainContext,
            at: now
        )
        let nursing = EventTimerService.start(
            type: .nursing,
            nursingSide: .left,
            caregiverName: "Caregiver 1",
            events: [sleep],
            context: container.mainContext,
            at: now
        )

        XCTAssertNil(duplicateSleep)
        XCTAssertNotNil(nursing)
    }

    func testDailySummaryTracksDogCareMetricsSeparately() {
        let now = Date(timeIntervalSinceReferenceDate: 360_000)
        let food = CareEvent(type: .food, startDate: now)
        let water = CareEvent(type: .water, startDate: now)
        let potty = CareEvent(type: .potty, startDate: now)
        potty.dogDetails.accident = true
        let walk = CareEvent(
            type: .walk,
            startDate: now,
            endDate: now.addingTimeInterval(1_200)
        )
        let training = CareEvent(
            type: .training,
            startDate: now,
            endDate: now.addingTimeInterval(600)
        )
        let diaper = CareEvent(type: .diaper, startDate: now)
        diaper.diaperKind = .wet

        let summary = DailySummaryService.summary(
            for: [food, water, potty, walk, training, diaper]
        )

        XCTAssertEqual(summary.dogFoodCount, 1)
        XCTAssertEqual(summary.waterCount, 1)
        XCTAssertEqual(summary.pottyCount, 1)
        XCTAssertEqual(summary.pottyAccidents, 1)
        XCTAssertEqual(summary.walkTime, 1_200)
        XCTAssertEqual(summary.trainingTime, 600)
        XCTAssertEqual(summary.wetDiapers, 1)
    }

    func testDailySummaryTracksUnifiedChildCareMetrics() {
        let now = Date(timeIntervalSinceReferenceDate: 361_000)
        let bottle = CareEvent(type: .feed, startDate: now.addingTimeInterval(-600))
        bottle.feedKind = .bottle
        bottle.amountOz = 3
        let solid = CareEvent(type: .feed, startDate: now)
        solid.feedKind = .solid
        solid.solidReaction = .sensitivity
        solid.solidAllergenExposure = true
        solid.solidSensitivityObserved = true

        let pump = CareEvent(
            type: .pumping,
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(1_500)
        )
        pump.amountOz = 4

        let potty = CareEvent(type: .potty, startDate: now.addingTimeInterval(1_800))
        potty.profileTypeSnapshot = .child
        potty.childPottyKind = .both
        potty.childPottyAccident = true
        let activity = CareEvent(
            type: .activity,
            startDate: now.addingTimeInterval(2_400),
            endDate: now.addingTimeInterval(3_000)
        )
        activity.activityType = .tummyTime
        let growth = CareEvent(type: .growth, startDate: now.addingTimeInterval(3_600))
        let temperature = CareEvent(type: .temperature, startDate: now.addingTimeInterval(4_200))
        let custom = CareEvent(type: .custom, startDate: now.addingTimeInterval(4_800))

        let summary = DailySummaryService.summary(for: [
            bottle, solid, pump, potty, activity, growth, temperature, custom
        ])

        XCTAssertEqual(summary.feedCount, 2)
        XCTAssertEqual(summary.bottleFeedCount, 1)
        XCTAssertEqual(summary.bottleOunces, 3)
        XCTAssertEqual(summary.solidFeedCount, 1)
        XCTAssertEqual(summary.solidAllergenExposures, 1)
        XCTAssertEqual(summary.solidSensitivityObservations, 1)
        XCTAssertEqual(summary.pumpingSessions, 1)
        XCTAssertEqual(summary.pumpingOunces, 4)
        XCTAssertEqual(summary.pumpingTotal, 900)
        XCTAssertEqual(summary.childPottyCount, 1)
        XCTAssertEqual(summary.childPottyPeeCount, 1)
        XCTAssertEqual(summary.childPottyPooCount, 1)
        XCTAssertEqual(summary.childPottyAccidents, 1)
        XCTAssertEqual(summary.pottyAccidents, 1)
        XCTAssertEqual(summary.activityCount, 1)
        XCTAssertEqual(summary.tummyTime, 600)
        XCTAssertEqual(summary.growthCount, 1)
        XCTAssertEqual(summary.temperatureCount, 1)
        XCTAssertEqual(summary.customCount, 1)
    }

    @MainActor
    func testWidgetSnapshotUsesDogSummaryMetricsForDogProfiles() {
        let now = Date(timeIntervalSinceReferenceDate: 370_000)
        let food = CareEvent(type: .food, startDate: now)
        let water = CareEvent(type: .water, startDate: now)
        let potty = CareEvent(type: .potty, startDate: now)
        let walk = CareEvent(
            type: .walk,
            startDate: now.addingTimeInterval(-1_500),
            endDate: now.addingTimeInterval(-300)
        )

        let snapshot = WidgetSnapshotService.makeSnapshot(
            profileType: .dog,
            babyName: "Test Dog",
            events: [food, water, potty, walk],
            prediction: nil,
            now: now
        )

        XCTAssertTrue(snapshot.todaySummary.isDog)
        XCTAssertEqual(snapshot.todaySummary.dogFoodCount, 1)
        XCTAssertEqual(snapshot.todaySummary.dogWaterCount, 1)
        XCTAssertEqual(snapshot.todaySummary.dogPottyCount, 1)
        XCTAssertEqual(snapshot.todaySummary.dogWalkSeconds, 1_200)
        XCTAssertEqual(snapshot.todaySummary.diaperCount, 0)
    }

    @MainActor
    func testWidgetSnapshotCarriesUnifiedChildSummaryMetrics() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let pump = CareEvent(
            type: .pumping,
            startDate: now.addingTimeInterval(-900)
        )
        pump.endDate = pump.startDate.addingTimeInterval(600)
        pump.profileTypeSnapshot = .child
        pump.amountOz = 2.5

        let solid = CareEvent(type: .feed, startDate: now.addingTimeInterval(-600))
        solid.endDate = solid.startDate
        solid.profileTypeSnapshot = .child
        solid.feedKind = .solid
        solid.solidSensitivityObserved = true

        let potty = CareEvent(type: .potty, startDate: now.addingTimeInterval(-120))
        potty.profileTypeSnapshot = .child
        potty.childPottyKind = .pee
        potty.childPottyAccident = true
        let growth = CareEvent(type: .growth, startDate: now.addingTimeInterval(-60))
        let temperature = CareEvent(type: .temperature, startDate: now.addingTimeInterval(-45))
        let custom = CareEvent(type: .custom, startDate: now.addingTimeInterval(-30))
        custom.endDate = custom.startDate

        let snapshot = WidgetSnapshotService.makeSnapshot(
            profileType: .child,
            babyName: "Test Child",
            events: [pump, solid, potty, growth, temperature, custom],
            prediction: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.todaySummary.pumpingSessionCount, 1)
        XCTAssertEqual(snapshot.todaySummary.pumpingSeconds, 600)
        XCTAssertEqual(snapshot.todaySummary.solidFeedCount, 1)
        XCTAssertEqual(snapshot.todaySummary.solidSensitivityCount, 1)
        XCTAssertEqual(snapshot.todaySummary.childPottyCount, 1)
        XCTAssertEqual(snapshot.todaySummary.childPottyAccidentCount, 1)
        XCTAssertEqual(
            Set(snapshot.todaySummary.summaryMetrics?.map(\.id) ?? []),
            Set([
                "sleep-total", "sleep-naps", "feed-total", "feed-bottle",
                "feed-solids", "nursing", "pumping", "diapers", "potty",
                "medicine", "growth", "temperature", "activity", "custom"
            ])
        )
        XCTAssertEqual(
            snapshot.todaySummary.summaryMetrics?.first { $0.id == "growth" }?.value,
            "1"
        )
        XCTAssertEqual(
            snapshot.todaySummary.summaryMetrics?.first { $0.id == "temperature" }?.value,
            "1"
        )
        XCTAssertEqual(
            snapshot.todaySummary.summaryMetrics?.first { $0.id == "custom" }?.value,
            "1"
        )
    }

    func testMilestoneCategoriesAreProfileSpecific() {
        let dogCategories = MilestoneCategory.categories(for: .dog)
        XCTAssertTrue(dogCategories.contains(.pottyTraining))
        XCTAssertTrue(dogCategories.contains(.grooming))
        XCTAssertFalse(dogCategories.contains(.diapering))
        XCTAssertFalse(dogCategories.contains(.motor))

        let childCategories = MilestoneCategory.categories(for: .child)
        XCTAssertTrue(childCategories.contains(.diapering))
        XCTAssertFalse(childCategories.contains(.pottyTraining))
    }

    func testPredictionCountdownFormatting() {
        let now = Date(timeIntervalSinceReferenceDate: 400_000)

        XCTAssertEqual(
            PredictionCountdownFormatting.text(
                until: now.addingTimeInterval(50 * 60),
                from: now
            ),
            "In 50m"
        )
        XCTAssertEqual(
            PredictionCountdownFormatting.text(
                until: now.addingTimeInterval(90 * 60),
                from: now
            ),
            "In 1h 30m"
        )
        XCTAssertEqual(
            PredictionCountdownFormatting.text(
                until: now.addingTimeInterval(-60),
                from: now
            ),
            "Now"
        )
    }

    func testPredictionTimingMovesFromUpcomingToOverdue() {
        let start = Date(timeIntervalSinceReferenceDate: 500_000)
        let end = start.addingTimeInterval(50 * 60)

        XCTAssertEqual(
            PredictionTiming.phase(
                windowStart: start,
                windowEnd: end,
                now: start.addingTimeInterval(-60)
            ),
            .upcoming
        )
        XCTAssertEqual(
            PredictionTiming.phase(
                windowStart: start,
                windowEnd: end,
                now: start.addingTimeInterval(20 * 60)
            ),
            .inWindow
        )
        XCTAssertEqual(
            PredictionTiming.phase(
                windowStart: start,
                windowEnd: end,
                now: end.addingTimeInterval(60)
            ),
            .overdue
        )
    }

    func testPredictionSnapshotFallsBackToWindowMidpoint() {
        let start = Date(timeIntervalSinceReferenceDate: 500_000)
        let end = start.addingTimeInterval(40 * 60)
        let snapshot = PredictionSnapshot(
            kind: "Nap",
            expectedStart: nil,
            windowStart: start,
            windowEnd: end,
            confidenceLabel: "Medium"
        )

        XCTAssertEqual(
            snapshot.resolvedExpectedStart,
            start.addingTimeInterval(20 * 60)
        )
    }

    @MainActor
    func testSwitchNursingSideAccumulatesElapsedSideTime() throws {
        let schema = Schema([
            CareProfile.self,
            CareEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = Self.uniqueInMemoryConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let start = Date().addingTimeInterval(-300)
        let event = CareEvent(type: .nursing, startDate: start)
        event.nursingSide = .left
        event.activeNursingSide = .left
        event.updatedAt = start
        container.mainContext.insert(event)

        EventTimerService.switchNursingSide(
            event,
            context: container.mainContext,
            at: start.addingTimeInterval(180)
        )

        XCTAssertEqual(event.leftDurationSeconds ?? 0, 180, accuracy: 0.001)
        XCTAssertEqual(event.activeNursingSide, .right)
        XCTAssertEqual(event.nursingSide, .right)
    }

    @MainActor
    func testSettingNursingSideAccumulatesOnlyPreviousSide() throws {
        let schema = Schema([
            CareProfile.self,
            CareEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = Self.uniqueInMemoryConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let start = Date().addingTimeInterval(-300)
        let event = CareEvent(type: .nursing, startDate: start)
        event.nursingSide = .left
        event.activeNursingSide = .left
        event.activeTimerSegmentStartDate = start
        event.updatedAt = start
        container.mainContext.insert(event)

        EventTimerService.setNursingSide(
            event,
            to: .right,
            context: container.mainContext,
            at: start.addingTimeInterval(120)
        )
        EventTimerService.setNursingSide(
            event,
            to: .left,
            context: container.mainContext,
            at: start.addingTimeInterval(200)
        )

        XCTAssertEqual(event.leftDurationSeconds ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(event.rightDurationSeconds ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(event.activeNursingSide, .left)
        XCTAssertEqual(event.nursingSide, .left)
    }

    @MainActor
    func testAdjustingActiveTimerStartImmediatelyChangesSnapshot() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let event = CareEvent(
            type: .sleep,
            startDate: now.addingTimeInterval(-120)
        )
        let correctedStart = now.addingTimeInterval(-420)

        let result = EventTimerService.adjustStartDate(
            event,
            to: correctedStart,
            at: now
        )
        let snapshot = WidgetSnapshotService.activeSnapshot(
            event: event,
            babyName: "Test Child",
            additionalActiveCount: 0,
            now: now
        )
        let widgetSnapshot = WidgetSnapshotService.makeSnapshot(
            babyName: "Test Child",
            events: [event],
            prediction: nil,
            now: now
        )

        XCTAssertEqual(result, correctedStart)
        XCTAssertEqual(event.startDate, correctedStart)
        XCTAssertEqual(snapshot.startDate, correctedStart)
        XCTAssertEqual(snapshot.elapsedSeconds ?? 0, 420, accuracy: 0.001)
        XCTAssertEqual(widgetSnapshot.activeTimer?.startDate, correctedStart)
        XCTAssertEqual(widgetSnapshot.activeTimer?.elapsedSeconds ?? 0, 420, accuracy: 0.001)
        XCTAssertEqual(now.timeIntervalSince(event.startDate), 420, accuracy: 0.001)
    }

    @MainActor
    func testNursingTimerSnapshotCarriesLiveTotalAndActiveSideTime() {
        let now = Date(timeIntervalSinceReferenceDate: 150_000)
        let event = CareEvent(
            type: .nursing,
            startDate: now.addingTimeInterval(-900)
        )
        event.timerState = .running
        event.timerAccumulatedSeconds = 600
        event.activeTimerSegmentStartDate = now.addingTimeInterval(-300)
        event.nursingSide = .right
        event.activeNursingSide = .right
        event.leftDurationSeconds = 420
        event.rightDurationSeconds = 180

        let snapshot = WidgetSnapshotService.activeSnapshot(
            event: event,
            babyName: "Test Child",
            additionalActiveCount: 0,
            now: now
        )

        XCTAssertEqual(snapshot.resolvedElapsedSeconds, 900, accuracy: 0.001)
        XCTAssertEqual(snapshot.leftDurationSeconds, 420, accuracy: 0.001)
        XCTAssertEqual(snapshot.rightDurationSeconds, 480, accuracy: 0.001)
        XCTAssertEqual(snapshot.activeNursingSideElapsedSeconds, 480, accuracy: 0.001)
        XCTAssertEqual(
            snapshot.activeNursingSideTimerStartDate,
            now.addingTimeInterval(-480)
        )
    }

    @MainActor
    func testActiveTimerStartCannotMoveIntoFuture() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let event = CareEvent(
            type: .activity,
            startDate: now.addingTimeInterval(-60)
        )

        EventTimerService.adjustStartDate(
            event,
            to: now.addingTimeInterval(600),
            at: now
        )

        XCTAssertEqual(event.startDate, now)
    }

    @MainActor
    func testBackdatingActiveNursingTimerCreditsCurrentSide() throws {
        let schema = Schema([
            CareProfile.self,
            CareEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = Self.uniqueInMemoryConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let now = Date(timeIntervalSinceReferenceDate: 300_000)
        let originalStart = now.addingTimeInterval(-120)
        let correctedStart = now.addingTimeInterval(-300)
        let event = CareEvent(type: .nursing, startDate: originalStart)
        event.nursingSide = .left
        event.activeNursingSide = .left
        event.activeTimerSegmentStartDate = originalStart
        container.mainContext.insert(event)

        EventTimerService.adjustStartDate(
            event,
            to: correctedStart,
            at: now
        )
        EventTimerService.stop(
            event,
            context: container.mainContext,
            at: now
        )

        XCTAssertEqual(event.leftDurationSeconds ?? 0, 300, accuracy: 0.001)
        XCTAssertNil(event.activeTimerSegmentStartDate)
        XCTAssertFalse(event.isTimerRunning)
        XCTAssertTrue(event.isTimerDraft)
    }

    @MainActor
    func testTimerStopResumeExcludesPausedTimeAndSaveCommits() throws {
        let container = try makeInMemoryContainer()
        let start = Date(timeIntervalSinceReferenceDate: 600_000)
        let event = try XCTUnwrap(EventTimerService.start(
            type: .sleep,
            sleepKind: .nap,
            caregiverName: "Caregiver 1",
            events: [],
            context: container.mainContext,
            at: start
        ))

        EventTimerService.stop(
            event,
            context: container.mainContext,
            at: start.addingTimeInterval(120)
        )
        XCTAssertEqual(event.timerElapsed(), 120, accuracy: 0.001)
        XCTAssertFalse(event.isTimerRunning)
        XCTAssertNil(event.endDate)

        EventTimerService.resume(
            event,
            context: container.mainContext,
            at: start.addingTimeInterval(420)
        )
        EventTimerService.stop(
            event,
            context: container.mainContext,
            at: start.addingTimeInterval(480)
        )
        XCTAssertEqual(event.timerElapsed(), 180, accuracy: 0.001)

        EventTimerService.save(
            event,
            context: container.mainContext,
            at: start.addingTimeInterval(500)
        )
        XCTAssertFalse(event.isTimerDraft)
        XCTAssertEqual(
            event.endDate?.timeIntervalSince(event.startDate) ?? 0,
            180,
            accuracy: 0.001
        )
        XCTAssertNil(event.timerState)
        XCTAssertNil(event.timerAccumulatedSeconds)
    }

    @MainActor
    func testStoppedTimerCanSaveWithEditedEndDate() throws {
        let container = try makeInMemoryContainer()
        let start = Date(timeIntervalSinceReferenceDate: 650_000)
        let stoppedAt = start.addingTimeInterval(15 * 60)
        let editedEnd = start.addingTimeInterval(12 * 60)
        let event = try XCTUnwrap(EventTimerService.start(
            type: .sleep,
            sleepKind: .nap,
            caregiverName: "Caregiver 1",
            events: [],
            context: container.mainContext,
            at: start
        ))

        EventTimerService.stop(event, context: container.mainContext, at: stoppedAt)
        EventTimerService.save(
            event,
            context: container.mainContext,
            at: stoppedAt,
            endDate: editedEnd
        )

        XCTAssertFalse(event.isTimerDraft)
        XCTAssertEqual(event.endDate, editedEnd)
        XCTAssertNil(event.timerState)
        XCTAssertNil(event.timerAccumulatedSeconds)
    }

    @MainActor
    func testTimerResetClearsElapsedTimeAndKeepsRunningState() throws {
        let container = try makeInMemoryContainer()
        let start = Date(timeIntervalSinceReferenceDate: 700_000)
        let event = try XCTUnwrap(EventTimerService.start(
            type: .activity,
            activityType: .tummyTime,
            caregiverName: "Caregiver 1",
            events: [],
            context: container.mainContext,
            at: start
        ))
        let resetDate = start.addingTimeInterval(90)

        EventTimerService.reset(
            event,
            context: container.mainContext,
            at: resetDate
        )

        XCTAssertTrue(event.isTimerRunning)
        XCTAssertEqual(event.startDate, resetDate)
        XCTAssertEqual(event.timerElapsed(at: resetDate), 0, accuracy: 0.001)
    }

    @MainActor
    func testDeepLinkRouterParsesStopAndQuickLogActions() {
        let router = DeepLinkRouter.shared
        let eventID = UUID()

        router.route(URL(string: "littlewindows://action/stop/\(eventID.uuidString)")!)
        XCTAssertEqual(router.consumeAction(), .stopTimer(eventID))

        router.route(URL(string: "littlewindows://action/resume/\(eventID.uuidString)")!)
        XCTAssertEqual(router.consumeAction(), .resumeTimer(eventID))

        router.route(URL(string: "littlewindows://quick-log/nursing-right")!)
        XCTAssertEqual(router.consumeAction(), .startTimer(.nursing, .right))

        router.route(URL(string: "littlewindows://quick-log/repeat-last")!)
        XCTAssertEqual(router.consumeAction(), .repeatLast)

        router.route(URL(string: "littlewindows://quick-log/walk")!)
        XCTAssertEqual(router.consumeAction(), .startTimer(.walk, nil))

        let adultQuickLogs: [(String, EventType)] = [
            ("symptom", .symptom),
            ("blood-pressure", .bloodPressure),
            ("heart-rate", .heartRate),
            ("oxygen-saturation", .oxygenSaturation),
            ("glucose", .glucose),
            ("pain", .pain)
        ]
        for (path, expectedType) in adultQuickLogs {
            router.route(URL(string: "littlewindows://quick-log/\(path)")!)
            XCTAssertEqual(router.consumeAction(), .logEvent(expectedType))
        }

        router.pendingMedications = false
        router.route(URL(string: "littlewindows://quick-log/medicine")!)
        XCTAssertTrue(router.pendingMedications)
        XCTAssertEqual(router.selectedTab, .milestones)
        router.pendingMedications = false

        let doseCommand = MedicationDoseRouteCommand(
            profileID: UUID(),
            medicationID: UUID(),
            regimenID: UUID(),
            phaseID: nil,
            occurrenceKey: "scheduled-dose",
            scheduledAt: Date(timeIntervalSinceReferenceDate: 700_000),
            doseAmount: 1,
            doseUnit: "tablet",
            status: .taken
        )
        router.openMedicationDose(doseCommand)
        XCTAssertEqual(router.pendingMedicationDoseCommand, doseCommand)
        XCTAssertEqual(router.pendingProfileID, doseCommand.profileID)
        XCTAssertTrue(router.pendingMedications)
        XCTAssertEqual(router.selectedTab, .milestones)
        router.discardCareNavigationRequest()
    }

    @MainActor
    func testDeepLinkActionCanRemainQueuedUntilDataIsReady() {
        let router = DeepLinkRouter.shared
        router.isDataReady = false
        router.route(URL(string: "littlewindows://quick-log/sleep")!)

        XCTAssertEqual(router.pendingAction, .startTimer(.sleep, nil))

        router.isDataReady = true
        XCTAssertEqual(router.consumeAction(), .startTimer(.sleep, nil))
    }

    func testLegacyActivityTypesNormalizeWithoutLosingSubtype() {
        let tummy = CareEvent(type: .custom)
        tummy.typeRawValue = "tummyTime"
        let reading = CareEvent(type: .custom)
        reading.typeRawValue = "reading"
        let bath = CareEvent(type: .custom)
        bath.typeRawValue = "bath"

        XCTAssertEqual(tummy.type, .activity)
        XCTAssertEqual(tummy.activityType, .tummyTime)
        XCTAssertEqual(reading.activityType, .storyTime)
        XCTAssertEqual(bath.activityType, .bath)
    }

    func testRichDiaperAndMedicineTimelineSummaries() {
        let diaper = CareEvent(type: .diaper)
        diaper.diaperKind = .both
        diaper.peeAmount = .big
        diaper.pooAmount = .little
        diaper.pooColor = .brown
        diaper.diaperRash = true

        let medicine = CareEvent(type: .medicine)
        medicine.medicineName = "Tylenol"
        medicine.dose = 2.5
        medicine.medicineUnit = .milliliters

        XCTAssertEqual(diaper.displayTitle, "Diaper: mixed — pee big, poo little brown · diaper rash")
        XCTAssertEqual(medicine.displayTitle, "Medicine: Tylenol, 2.5 mL")
    }

    func testNursingTimelineDurationPrefersSideTotalOverWindowDuration() {
        let start = Date()
        let event = CareEvent(
            type: .nursing,
            startDate: start,
            endDate: start.addingTimeInterval(4 * 60)
        )
        event.nursingSide = .left
        event.leftDurationSeconds = 4 * 60

        XCTAssertEqual(event.displayTitle, "Left nursing")
        XCTAssertEqual(event.timelineDurationDescription, "4m")
    }

    func testTemperatureStoresCanonicalCelsiusAndConvertsForDisplay() {
        let event = CareEvent(type: .temperature)
        event.temperatureCelsius = 37
        event.temperatureUnit = .fahrenheit
        event.temperatureMethod = .forehead

        XCTAssertEqual(event.temperatureValue(in: .fahrenheit) ?? 0, 98.6, accuracy: 0.001)
        XCTAssertEqual(event.temperatureValue(in: .celsius) ?? 0, 37, accuracy: 0.001)
        XCTAssertEqual(event.displayTitle, "Temperature: 98.6°F, forehead")
    }

    @MainActor
    func testActivityTimerSnapshotUsesSpecificSubtype() {
        let bath = CareEvent(type: .activity, startDate: Date())
        bath.activityType = .bath

        let snapshot = WidgetSnapshotService.activeSnapshot(
            event: bath,
            babyName: "Test Child",
            additionalActiveCount: 0
        )

        XCTAssertEqual(snapshot.typeRawValue, EventType.activity.rawValue)
        XCTAssertEqual(snapshot.eventLabel, "Bath")
        XCTAssertEqual(snapshot.systemImage, "bathtub.fill")
    }

    func testGrowthTemperatureAndActivityInsightsUseNewFields() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let growth = CareEvent(type: .growth, startDate: day)
        growth.weightPounds = 14
        growth.weightOunces = 8
        growth.heightFeet = 2
        growth.heightInches = 1.5
        let temperature = CareEvent(type: .temperature, startDate: day.addingTimeInterval(60))
        temperature.temperatureCelsius = 37
        let outdoor = CareEvent(
            type: .activity,
            startDate: day.addingTimeInterval(120),
            endDate: day.addingTimeInterval(42 * 60 + 120)
        )
        outdoor.activityType = .outdoorPlay

        let snapshot = InsightsAnalyticsService.snapshot(
            profileName: "Test Child",
            events: [growth, temperature, outdoor],
            records: [],
            periodStart: day,
            periodEnd: day,
            now: day
        )

        XCTAssertEqual(snapshot.growthMeasurements.first?.weightPounds ?? 0, 14.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.growthMeasurements.first?.heightInches ?? 0, 25.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.temperatureMeasurements.first?.fahrenheit ?? 0, 98.6, accuracy: 0.001)
        XCTAssertEqual(snapshot.dailyActivities.first?.outdoorMinutes ?? 0, 42, accuracy: 0.001)
    }

    func testGrowthUnitConversionsAndAgeInDays() throws {
        XCTAssertEqual(
            GrowthUnitConversion.poundsAndOuncesToKilograms(pounds: 14, ounces: 8),
            6.577089365,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(
            GrowthUnitConversion.feetAndInchesToCentimeters(feet: 2, inches: 1.5),
            64.77,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            GrowthUnitConversion.inchesToCentimeters(16.5),
            41.91,
            accuracy: 0.000_001
        )

        let calendar = Calendar(identifier: .gregorian)
        let birthDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        let measurementDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 22))
        )
        XCTAssertEqual(
            GrowthUnitConversion.ageInDays(
                birthDate: birthDate,
                measurementDate: measurementDate,
                calendar: calendar
            ),
            21
        )
    }

    func testGrowthLMSAndNormalDistributionCalculations() {
        let zScore = GrowthReferenceService.lmsZScore(
            value: 9.7,
            l: -0.1600954,
            m: 9.476500305,
            s: 0.11218624
        )
        XCTAssertEqual(zScore, 0.207, accuracy: 0.002)
        XCTAssertEqual(GrowthReferenceService.normalCDF(0), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(GrowthReferenceService.normalCDF(1.96), 0.975, accuracy: 0.001)
        XCTAssertEqual(
            GrowthReferenceService.inverseNormalCDF(0.5),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            GrowthReferenceService.inverseNormalCDF(0.95),
            1.64485,
            accuracy: 0.000_1
        )
    }

    func testGrowthReferenceInterpolationAndPercentileBands() {
        let points = [
            GrowthReferencePoint(
                chartType: .weightForAge,
                sex: .male,
                ageInMonths: 0,
                l: 1,
                m: 10,
                s: 0.1,
                source: "test"
            ),
            GrowthReferencePoint(
                chartType: .weightForAge,
                sex: .male,
                ageInMonths: 1,
                l: 1,
                m: 20,
                s: 0.2,
                source: "test"
            )
        ]
        let service = GrowthReferenceService(points: points)
        let midpoint = service.interpolatedReference(
            chartType: .weightForAge,
            sex: .male,
            ageInDays: GrowthUnitConversion.averageDaysPerMonth / 2
        )

        XCTAssertEqual(midpoint?.m ?? 0, 15, accuracy: 0.000_001)
        XCTAssertEqual(midpoint?.s ?? 0, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(
            service.valueForPercentile(
                chartType: .weightForAge,
                sex: .male,
                ageInDays: Int(GrowthUnitConversion.averageDaysPerMonth / 2),
                percentile: 50
            ) ?? 0,
            15,
            accuracy: 0.1
        )
        XCTAssertEqual(service.nearestPercentileBand(50.8).label, "Near P50")
        XCTAssertEqual(
            service.nearestPercentileBand(62).label,
            "Between P50 and P75"
        )
    }

    func testGrowthPercentileFormattingUsesOrdinalPercent() {
        XCTAssertEqual(GrowthPercentileFormatting.ordinalPercent(54.2), "54th%")
        XCTAssertEqual(GrowthPercentileFormatting.ordinalPercent(1.1), "1st%")
        XCTAssertEqual(GrowthPercentileFormatting.ordinalPercent(2.2), "2nd%")
        XCTAssertEqual(GrowthPercentileFormatting.ordinalPercent(3.1), "3rd%")
        XCTAssertEqual(GrowthPercentileFormatting.ordinalPercent(11.1), "11th%")
        XCTAssertEqual(GrowthPercentileFormatting.ordinalPercent(12.1), "12th%")
        XCTAssertEqual(GrowthPercentileFormatting.ordinalPercent(13.1), "13th%")
        XCTAssertEqual(GrowthPercentileFormatting.ordinalPercent(21.2), "21st%")
    }

    func testOfficialWHOGrowthDataLoadsAndGeneratesSeries() {
        let service = GrowthReferenceService.shared
        let boysWeight = service.referencePoints(
            chartType: .weightForAge,
            sex: .male
        )
        XCTAssertEqual(boysWeight?.count, 25)
        XCTAssertEqual(boysWeight?.first?.m ?? 0, 3.3464, accuracy: 0.000_001)

        let series = service.referenceSeries(
            chartType: .headCircumferenceForAge,
            sex: .female,
            percentiles: [3, 50, 97, 99]
        )
        XCTAssertEqual(series.count, 100)
        XCTAssertTrue(series.allSatisfy { $0.measurementValue > 0 })
    }

    func testGrowthChartDataUsesCanonicalValuesAndProfileSex() {
        let birthDate = Date(timeIntervalSince1970: 1_767_225_600)
        let profile = CareProfile(name: "Test Child", birthDate: birthDate, sex: .male)
        let event = CareEvent(
            type: .growth,
            startDate: birthDate.addingTimeInterval(90 * 24 * 60 * 60),
            notes: "Three-month visit"
        )
        event.weightKilograms = 6.2
        event.growthSource = .pediatrician

        let points = GrowthReferenceService.shared.chartDataForGrowthEntries(
            [event],
            chartType: .weightForAge,
            profile: profile
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.measurementValue ?? 0, 6.2, accuracy: 0.000_001)
        XCTAssertEqual(points.first?.ageInDays, 90)
        XCTAssertEqual(points.first?.source, .pediatrician)
        XCTAssertNotNil(points.first?.result?.percentileEstimate)
    }

    func testMilestoneAgeDescriptionSupportsWeeksMonthsAndApproximateDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let birthDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        let threeWeeks = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 21, to: birthDate)
        )
        let threeMonths = try XCTUnwrap(
            calendar.date(byAdding: .month, value: 3, to: birthDate)
        )

        let smile = MilestoneEntry(title: "First smile", date: threeWeeks)
        let hands = MilestoneEntry(
            title: "Holding hands at center",
            date: threeMonths,
            approximateDate: true,
            category: .motor
        )

        XCTAssertEqual(
            smile.ageAtMilestoneDescription(birthDate: birthDate, calendar: calendar),
            "3 weeks old"
        )
        XCTAssertEqual(
            hands.ageAtMilestoneDescription(birthDate: birthDate, calendar: calendar),
            "about 3 months old"
        )
    }

    func testAutomaticMilestoneSummariesUseHundredDayCadence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let birthDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))
        )
        let now = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 305, to: birthDate)
        )
        let profile = CareProfile(name: "Test Child", birthDate: birthDate)

        let summaries = AutomaticMilestoneSummaryService.summaries(
            profile: profile,
            events: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summaries.map(\.id), [
            "automatic-days-300",
            "automatic-days-200",
            "automatic-days-100"
        ])
        XCTAssertEqual(summaries.last?.title, "Test Child is 100 days old!")
    }

    func testAutomaticMilestoneSummaryAggregatesCareGrowthAndActivities() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let birthDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))
        )
        let profile = CareProfile(
            name: "Test Child",
            birthDate: birthDate,
            birthWeightKilograms: 3
        )

        func date(day: Int, hour: Int = 0, minute: Int = 0) throws -> Date {
            let dayDate = try XCTUnwrap(
                calendar.date(byAdding: .day, value: day, to: birthDate)
            )
            return try XCTUnwrap(
                calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: dayDate
                )
            )
        }

        let sleepOne = CareEvent(
            type: .sleep,
            startDate: try date(day: 5, hour: 9),
            endDate: try date(day: 5, hour: 10)
        )
        let sleepTwo = CareEvent(
            type: .sleep,
            startDate: try date(day: 6, hour: 20),
            endDate: try date(day: 6, hour: 22)
        )
        let draftSleep = CareEvent(
            type: .sleep,
            startDate: try date(day: 7, hour: 9)
        )
        let nightWaking = CareEvent(
            type: .sleep,
            startDate: try date(day: 7, hour: 2),
            endDate: try date(day: 7, hour: 2, minute: 20)
        )
        nightWaking.sleepKind = .nightWaking

        let nursingOne = CareEvent(
            type: .nursing,
            startDate: try date(day: 10, hour: 10),
            endDate: try date(day: 10, hour: 10, minute: 20)
        )
        nursingOne.leftDurationSeconds = 20 * 60
        let nursingTwo = CareEvent(
            type: .nursing,
            startDate: try date(day: 10, hour: 10, minute: 30),
            endDate: try date(day: 10, hour: 10, minute: 45)
        )
        nursingTwo.rightDurationSeconds = 15 * 60
        let nursingThree = CareEvent(
            type: .nursing,
            startDate: try date(day: 11, hour: 10),
            endDate: try date(day: 11, hour: 10, minute: 10)
        )
        nursingThree.leftDurationSeconds = 10 * 60

        let pump = CareEvent(
            type: .custom,
            title: "Pump",
            startDate: try date(day: 20, hour: 8),
            endDate: try date(day: 20, hour: 8, minute: 15)
        )
        let diaperOne = CareEvent(type: .diaper, startDate: try date(day: 4))
        let diaperTwo = CareEvent(type: .diaper, startDate: try date(day: 8))

        let growth = CareEvent(type: .growth, startDate: try date(day: 90))
        growth.weightKilograms = 5

        let tummyOne = CareEvent(
            type: .activity,
            startDate: try date(day: 30, hour: 9),
            endDate: try date(day: 30, hour: 9, minute: 10)
        )
        tummyOne.activityType = .tummyTime
        let tummyTwo = CareEvent(
            type: .activity,
            startDate: try date(day: 31, hour: 9),
            endDate: try date(day: 31, hour: 9, minute: 10)
        )
        tummyTwo.activityType = .tummyTime
        let bath = CareEvent(
            type: .activity,
            startDate: try date(day: 32, hour: 18),
            endDate: try date(day: 32, hour: 18, minute: 30)
        )
        bath.activityType = .bath

        let now = try date(day: 105)
        let summary = try XCTUnwrap(
            AutomaticMilestoneSummaryService.summaries(
                profile: profile,
                events: [
                    sleepOne, sleepTwo, draftSleep, nightWaking,
                    nursingOne, nursingTwo, nursingThree,
                    pump, diaperOne, diaperTwo, growth,
                    tummyOne, tummyTwo, bath
                ],
                now: now,
                calendar: calendar
            ).first
        )

        XCTAssertEqual(summary.sleepSessions, 2)
        XCTAssertEqual(summary.totalSleepSeconds, 3 * 60 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.nursingSessions, 2)
        XCTAssertEqual(summary.nursingSeconds, 45 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.pumpingSessions, 1)
        XCTAssertEqual(summary.pumpingSeconds, 15 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.diaperChanges, 2)
        XCTAssertEqual(summary.weightGainPounds ?? 0, 4.409, accuracy: 0.01)
        XCTAssertEqual(summary.topActivities.map(\.activityType), [.tummyTime, .bath])
        XCTAssertEqual(summary.topActivities.first?.count, 2)
        XCTAssertEqual(summary.topActivities.first?.durationSeconds ?? 0, 20 * 60)
    }

    @MainActor
    func testProfileAvatarThumbnailIsSquareBeforeSwiftUILayout() throws {
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 240, height: 100)
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 100))
        }
        let data = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))
        let result = try XCTUnwrap(ThumbnailImageCache.squareImage(
            attachmentID: UUID(),
            data: data,
            size: 40
        ))

        XCTAssertEqual(result.size.width, 40, accuracy: 0.001)
        XCTAssertEqual(result.size.height, 40, accuracy: 0.001)
    }

    @MainActor
    func testMilestonesRoundTripThroughJSONBackup() throws {
        let schema = PersistenceService.schema
        let configuration = Self.uniqueInMemoryConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let birthDate = Date(timeIntervalSince1970: 1_767_225_600)
        let milestoneDate = birthDate.addingTimeInterval(21 * 24 * 60 * 60)
        let photoID = UUID()
        let profilePhotoID = UUID()

        let profile = CareProfile(name: "Test Child", birthDate: birthDate)
        profile.profilePhotoAttachmentID = profilePhotoID
        context.insert(profile)
        context.insert(PhotoAttachment(
            id: profilePhotoID,
            profileID: profile.id,
            ownerKind: .profilePhoto,
            imageData: Data([1, 2, 3, 4]),
            thumbnailData: Data([1, 2])
        ))
        context.insert(PhotoAttachment(
            id: photoID,
            profileID: profile.id,
            ownerKind: .milestone,
            imageData: Data([5, 6, 7, 8]),
            thumbnailData: Data([5, 6])
        ))
        context.insert(MilestoneEntry(
            profileID: profile.id,
            title: "First smile",
            date: milestoneDate,
            approximateDate: true,
            category: .social,
            notes: "A tiny smile.",
            photoAttachmentIDs: [photoID],
            caregiverName: "Caregiver 1",
            isFavorite: true,
            sortOrder: 2
        ))
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let imported = try XCTUnwrap(
            context.fetch(FetchDescriptor<MilestoneEntry>()).first
        )
        XCTAssertEqual(imported.title, "First smile")
        XCTAssertEqual(imported.category, .social)
        XCTAssertTrue(imported.approximateDate)
        XCTAssertTrue(imported.isFavorite)
        XCTAssertEqual(imported.notes, "A tiny smile.")
        XCTAssertEqual(imported.caregiverName, "Caregiver 1")
        XCTAssertEqual(imported.photoAttachmentIDs, [photoID])
        XCTAssertEqual(imported.sortOrder, 2)

        let importedProfile = try XCTUnwrap(
            context.fetch(FetchDescriptor<CareProfile>()).first
        )
        XCTAssertEqual(importedProfile.profilePhotoAttachmentID, profilePhotoID)

        let attachments = try context.fetch(FetchDescriptor<PhotoAttachment>())
        XCTAssertEqual(attachments.count, 2)
        let importedMilestonePhoto = try XCTUnwrap(attachments.first { $0.id == photoID })
        XCTAssertEqual(importedMilestonePhoto.ownerKind, .milestone)
        XCTAssertEqual(importedMilestonePhoto.profileID, profile.id)
        XCTAssertEqual(importedMilestonePhoto.imageData, Data([5, 6, 7, 8]))
        XCTAssertEqual(importedMilestonePhoto.thumbnailData, Data([5, 6]))
        let importedProfilePhoto = try XCTUnwrap(attachments.first { $0.id == profilePhotoID })
        XCTAssertEqual(importedProfilePhoto.ownerKind, .profilePhoto)
        XCTAssertEqual(importedProfilePhoto.imageData, Data([1, 2, 3, 4]))
    }

    @MainActor
    func testSolidFoodCatalogAndPhotoRoundTripThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let photoDraft = PhotoAttachmentDraft(
            imageData: Data([1, 3, 5, 7]),
            thumbnailData: Data([1, 3])
        )
        let item = try XCTUnwrap(SolidFoodCatalogService.create(
            name: "  Family oatmeal  ",
            photoDraft: photoDraft,
            existingItems: [],
            context: context,
            now: Date(timeIntervalSince1970: 1_790_000_000)
        ))
        XCTAssertTrue(PersistenceService.save(context: context))

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let imported = try XCTUnwrap(
            context.fetch(FetchDescriptor<SolidFoodCatalogItem>()).first
        )
        XCTAssertEqual(imported.name, "Family oatmeal")
        XCTAssertEqual(imported.normalizedName, "family oatmeal")
        XCTAssertEqual(imported.photoAttachmentID, photoDraft.id)

        let photo = try XCTUnwrap(
            context.fetch(FetchDescriptor<PhotoAttachment>()).first {
                $0.id == photoDraft.id
            }
        )
        XCTAssertEqual(photo.ownerKind, .solidFood)
        XCTAssertNil(photo.profileID)
        XCTAssertEqual(photo.imageData, Data([1, 3, 5, 7]))
        XCTAssertEqual(photo.thumbnailData, Data([1, 3]))
    }

    func testSolidFoodSelectionCleansAndDeduplicatesNames() {
        let names = SolidFoodSelection.names(
            from: "Banana, yogurt\n banana , Crème fraîche"
        )
        XCTAssertEqual(names, ["Banana", "yogurt", "Crème fraîche"])
        XCTAssertEqual(
            SolidFoodSelection.description(from: names),
            "Banana, yogurt, Crème fraîche"
        )
    }

    func testSolidFoodIdeaCatalogProvidesBalancedUniqueStarterLibrary() {
        let ideas = SolidFoodIdeaCatalog.foods
        let normalizedNames = ideas.map { SolidFoodSelection.normalizedName($0.name) }
        let expectedFoods = [
            "Spinach", "Peas", "Yogurt", "Carrot", "Prune", "Green beans",
            "Mango", "Egg", "Strawberry", "Pasta", "Blueberry", "Oatmeal",
            "Chicken", "Lentils", "Tofu", "Peanut butter", "Salmon"
        ]

        XCTAssertGreaterThanOrEqual(ideas.count, 50)
        XCTAssertEqual(Set(normalizedNames).count, ideas.count)
        XCTAssertTrue(ideas.allSatisfy { !$0.emoji.isEmpty })
        for expectedFood in expectedFoods {
            XCTAssertTrue(
                normalizedNames.contains(SolidFoodSelection.normalizedName(expectedFood)),
                "Expected the starter library to include \(expectedFood)"
            )
        }
        for category in SolidFoodIdeaCategory.allCases {
            XCTAssertTrue(
                ideas.contains { $0.category == category },
                "Expected at least one food in \(category.displayName)"
            )
        }
    }

    @MainActor
    func testAppointmentsRoundTripThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let birthDate = Date(timeIntervalSince1970: 1_767_225_600)
        let startDate = birthDate.addingTimeInterval(180 * 24 * 60 * 60 + 9 * 60 * 60)
        let growthID = UUID()
        let temperatureID = UUID()

        context.insert(CareProfile(name: "Test Child", birthDate: birthDate))
        context.insert(DoctorAppointment(
            title: "6-month wellness check",
            appointmentType: .wellnessCheck,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
            timeZoneIdentifier: "America/New_York",
            locationName: "Suite 4",
            address: "123 Care Lane",
            doctorName: "Dr. Rivera",
            clinicName: "Neighborhood Pediatrics",
            phoneNumber: "555-0100",
            notes: "Bring vaccine card.",
            questionsToAsk: "Ask about sleep stretches.",
            visitSummary: "Everything looked good.",
            followUpInstructions: "Next visit at 9 months.",
            medicationsDiscussed: "Vitamin D",
            vaccinesGiven: "DTaP",
            growthEntryID: growthID,
            temperatureEntryID: temperatureID,
            remindersEnabled: true,
            reminderLeadTimeMinutes: [
                AppointmentReminderLeadTime.oneDay.rawValue,
                AppointmentReminderLeadTime.oneHour.rawValue,
                AppointmentReminderLeadTime.atTime.rawValue
            ],
            lastScheduledAt: startDate.addingTimeInterval(-2 * 24 * 60 * 60),
            isCompleted: true,
            caregiverName: "Caregiver 2"
        ))
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let imported = try XCTUnwrap(
            context.fetch(FetchDescriptor<DoctorAppointment>()).first
        )
        XCTAssertEqual(imported.title, "6-month wellness check")
        XCTAssertEqual(imported.appointmentType, .wellnessCheck)
        XCTAssertEqual(imported.startDate, startDate)
        XCTAssertEqual(imported.endDate, startDate.addingTimeInterval(30 * 60))
        XCTAssertEqual(imported.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(imported.locationName, "Suite 4")
        XCTAssertEqual(imported.address, "123 Care Lane")
        XCTAssertEqual(imported.doctorName, "Dr. Rivera")
        XCTAssertEqual(imported.clinicName, "Neighborhood Pediatrics")
        XCTAssertEqual(imported.phoneNumber, "555-0100")
        XCTAssertEqual(imported.notes, "Bring vaccine card.")
        XCTAssertEqual(imported.questionsToAsk, "Ask about sleep stretches.")
        XCTAssertEqual(imported.visitSummary, "Everything looked good.")
        XCTAssertEqual(imported.followUpInstructions, "Next visit at 9 months.")
        XCTAssertEqual(imported.medicationsDiscussed, "Vitamin D")
        XCTAssertEqual(imported.vaccinesGiven, "DTaP")
        XCTAssertEqual(imported.growthEntryID, growthID)
        XCTAssertEqual(imported.temperatureEntryID, temperatureID)
        XCTAssertEqual(imported.reminderLeadTimes, [.oneDay, .oneHour, .atTime])
        XCTAssertTrue(imported.remindersEnabled)
        XCTAssertTrue(imported.isCompleted)
        XCTAssertEqual(imported.caregiverName, "Caregiver 2")
    }

    func testAppointmentQuestionListParsesAndStoresStructuredRows() {
        let questions = AppointmentQuestionList.parse("""
        - Ask about sleep stretches.
        2. Review solid foods.
        * Confirm next vaccine timing.
        """)

        XCTAssertEqual(questions, [
            "Ask about sleep stretches.",
            "Review solid foods.",
            "Confirm next vaccine timing."
        ])
        XCTAssertEqual(
            AppointmentQuestionList.storageString(from: questions + ["  "]),
            """
            Ask about sleep stretches.
            Review solid foods.
            Confirm next vaccine timing.
            """
        )
    }

    @MainActor
    func testMonthlyAgeGuideServiceFindsCurrentGuideAndPrompts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let birthDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31))!
        let profile = CareProfile(name: "Test Child", birthDate: birthDate)
        let service = AgeGuideService(calendar: calendar)

        let guide = try XCTUnwrap(service.currentAgeGuide(for: profile, now: now))

        XCTAssertEqual(guide.ageMonth, 4)
        XCTAssertFalse(guide.milestonePrompts.isEmpty)
        XCTAssertTrue(guide.sourceReferences.contains { $0.sourceName.contains("CDC") })
        XCTAssertEqual(service.allAgeGuides().map(\.ageMonth), Array(2...12))
        XCTAssertTrue(try XCTUnwrap(service.ageGuide(for: 9)).isCheckpointAge)
        XCTAssertTrue(try XCTUnwrap(service.ageGuide(for: 12)).isCheckpointAge)
    }

    func testSleepGuideServiceProvidesReviewedCredibleSources() {
        let lessons = SleepGuideService.shared.lessons
        let sourceNames = Set(lessons.flatMap { lesson in
            lesson.sourceReferences.map(\.sourceName)
        })

        XCTAssertEqual(lessons.count, 5)
        XCTAssertTrue(lessons.allSatisfy { !$0.bullets.isEmpty })
        XCTAssertTrue(sourceNames.contains { $0.contains("HealthyChildren") })
        XCTAssertTrue(sourceNames.contains { $0.contains("NICHD") })
        XCTAssertTrue(sourceNames.contains { $0.contains("Sleep Medicine") })
        XCTAssertTrue(sourceNames.contains { $0.contains("MedlinePlus") })
        XCTAssertTrue(lessons.flatMap(\.sourceReferences).allSatisfy { $0.sourceURL != nil })
        XCTAssertTrue(lessons.flatMap(\.sourceReferences).allSatisfy { $0.retrievedOrReviewedDate != nil })
    }

    @MainActor
    func testAgeGuideReadStateRoundTripsThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let openedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let notifiedAt = openedAt.addingTimeInterval(-60 * 60)

        context.insert(CareProfile(name: "Test Child", birthDate: SampleData.defaultBirthDate))
        context.insert(AgeGuideReadState(
            guideID: "age-04",
            firstOpenedAt: openedAt,
            lastOpenedAt: openedAt.addingTimeInterval(60),
            isDismissedFromToday: true,
            notificationSentAt: notifiedAt,
            createdAt: openedAt,
            updatedAt: openedAt.addingTimeInterval(60)
        ))
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let imported = try XCTUnwrap(
            context.fetch(FetchDescriptor<AgeGuideReadState>()).first
        )
        XCTAssertEqual(imported.guideID, "age-04")
        XCTAssertEqual(imported.firstOpenedAt, openedAt)
        XCTAssertEqual(imported.notificationSentAt, notifiedAt)
        XCTAssertTrue(imported.isDismissedFromToday)
    }

    @MainActor
    func testFoodHomeDataRoundTripsThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let store = FoodStore(householdID: household.id, name: "Test Market", sortOrder: 1)
        let section = FoodStoreSection(
            householdID: household.id,
            storeID: store.id,
            name: "Frozen",
            sortOrder: 2
        )
        let list = ShoppingList(
            householdID: household.id,
            name: "Test Market",
            storeID: store.id,
            listType: .store
        )
        let item = ShoppingListItem(
            householdID: household.id,
            shoppingListID: list.id,
            name: "Breakfast burritos",
            quantity: 8,
            unit: "pack",
            storeSectionID: section.id,
            isChecked: true,
            checkedAt: Date(timeIntervalSince1970: 1_780_100_000),
            isRecurringStaple: true,
            purchaseCount: 3
        )
        let location = InventoryLocation(
            householdID: household.id,
            name: "Freezer",
            locationType: .freezer
        )
        let inventory = InventoryItem(
            householdID: household.id,
            name: "Chicken soup",
            quantity: 4,
            unit: "containers",
            locationID: location.id
        )
        let mealPrep = MealPrepItem(
            householdID: household.id,
            name: "Turkey chili",
            locationID: location.id,
            servingsTotal: 6,
            servingsRemaining: 5,
            servingUnit: .serving,
            tagsJSON: "freezer,dinner"
        )
        let usage = MealPrepUsage(
            householdID: household.id,
            mealPrepItemID: mealPrep.id,
            servingsUsed: 1,
            notes: "Dinner"
        )
        let todoList = HomeTodoList(
            householdID: household.id,
            name: "House Tasks"
        )
        let reminder = FoodReminder(
            householdID: household.id,
            type: .shopping,
            title: "Check shopping list",
            relatedShoppingListID: list.id,
            dateTime: Date(timeIntervalSince1970: 1_780_200_000),
            timeZoneIdentifier: "America/Chicago"
        )
        let todoReminder = FoodReminder(
            householdID: household.id,
            type: .todos,
            title: "Check house tasks",
            relatedTodoListID: todoList.id,
            dateTime: Date(timeIntervalSince1970: 1_780_210_000)
        )

        context.insert(household)
        context.insert(store)
        context.insert(section)
        context.insert(list)
        context.insert(item)
        context.insert(location)
        context.insert(inventory)
        context.insert(mealPrep)
        context.insert(usage)
        context.insert(todoList)
        context.insert(reminder)
        context.insert(todoReminder)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let importedList = try XCTUnwrap(
            context.fetch(FetchDescriptor<ShoppingList>()).first { $0.name == "Test Market" }
        )
        let importedItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<ShoppingListItem>()).first { $0.name == "Breakfast burritos" }
        )
        let importedInventory = try XCTUnwrap(
            context.fetch(FetchDescriptor<InventoryItem>()).first { $0.name == "Chicken soup" }
        )
        let importedMealPrep = try XCTUnwrap(
            context.fetch(FetchDescriptor<MealPrepItem>()).first { $0.name == "Turkey chili" }
        )
        let importedUsage = try XCTUnwrap(
            context.fetch(FetchDescriptor<MealPrepUsage>()).first {
                $0.mealPrepItemID == importedMealPrep.id
            }
        )
        let importedReminder = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodReminder>()).first { $0.title == "Check shopping list" }
        )
        let importedTodoReminder = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodReminder>()).first { $0.title == "Check house tasks" }
        )

        XCTAssertEqual(importedList.storeID, store.id)
        XCTAssertEqual(importedItem.storeSectionID, section.id)
        XCTAssertTrue(importedItem.isChecked)
        XCTAssertTrue(importedItem.isRecurringStaple)
        XCTAssertEqual(importedItem.purchaseCount, 3)
        XCTAssertEqual(importedInventory.quantity, 4)
        XCTAssertEqual(importedMealPrep.servingsRemaining, 5)
        XCTAssertEqual(importedMealPrep.tagsJSON, "freezer,dinner")
        XCTAssertEqual(importedUsage.notes, "Dinner")
        XCTAssertEqual(importedReminder.relatedShoppingListID, list.id)
        XCTAssertEqual(importedReminder.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(importedTodoReminder.type, .todos)
        XCTAssertEqual(importedTodoReminder.relatedTodoListID, todoList.id)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<CareProfile>()).isEmpty,
            "Household backups must round-trip without inventing a care profile."
        )
    }

    @MainActor
    func testCreatingReturnPersistsDefaultSendBackDetailsOnFirstSave() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        context.insert(household)

        let request = try XCTUnwrap(ReturnTrackingService.createReturn(
            householdID: household.id,
            sortOrder: 0,
            itemName: "Sample Item",
            itemQuantity: 1,
            itemReason: "Not needed",
            returnURLString: "https://example.com/return",
            packageName: "",
            carrier: .wholeFoods,
            method: .dropOff,
            trackingNumber: "",
            returnByDate: nil,
            photoAttachmentIDs: [],
            context: context
        ))

        let package = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReturnPackage>()).first {
                $0.returnRequestID == request.id
            }
        )
        let item = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReturnItem>()).first {
                $0.returnRequestID == request.id
            }
        )

        XCTAssertEqual(package.carrier, .wholeFoods)
        XCTAssertEqual(package.method, .dropOff)
        XCTAssertEqual(item.packageID, package.id)
        XCTAssertEqual(item.name, "Sample Item")
    }

    @MainActor
    func testReturnTrackingStatusFollowsMultiPackageProgress() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let request = ReturnRequest(
            householdID: household.id
        )
        let firstPackage = ReturnPackage(
            householdID: household.id,
            returnRequestID: request.id,
            name: "Coat label",
            carrier: .ups
        )
        let secondPackage = ReturnPackage(
            householdID: household.id,
            returnRequestID: request.id,
            name: "Boot label",
            carrier: .fedEx
        )

        context.insert(household)
        context.insert(request)
        context.insert(firstPackage)
        context.insert(secondPackage)
        try context.save()

        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .readyToDropOff
        )

        ReturnTrackingService.markDroppedOff(
            request,
            packages: [firstPackage, secondPackage],
            at: Date(timeIntervalSince1970: 1_800_000_000),
            context: context
        )
        XCTAssertNotNil(firstPackage.droppedOffAt)
        XCTAssertNotNil(secondPackage.droppedOffAt)
        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .droppedOff
        )

        ReturnTrackingService.markInProgress(
            request,
            packages: [firstPackage, secondPackage],
            at: Date(timeIntervalSince1970: 1_800_005_000),
            context: context
        )
        XCTAssertNil(firstPackage.droppedOffAt)
        XCTAssertNil(secondPackage.droppedOffAt)
        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .readyToDropOff
        )

        ReturnTrackingService.markDroppedOff(firstPackage, at: Date(timeIntervalSince1970: 1_800_010_000), context: context)
        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .partiallyDroppedOff
        )

        ReturnTrackingService.markInProgress(firstPackage, at: Date(timeIntervalSince1970: 1_800_015_000), context: context)
        XCTAssertNil(firstPackage.droppedOffAt)
        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .readyToDropOff
        )

        ReturnTrackingService.markDroppedOff(firstPackage, at: Date(timeIntervalSince1970: 1_800_016_000), context: context)
        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .partiallyDroppedOff
        )

        ReturnTrackingService.markDroppedOff(secondPackage, at: Date(timeIntervalSince1970: 1_800_020_000), context: context)
        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .droppedOff
        )

        ReturnTrackingService.markComplete(
            request,
            packages: [firstPackage, secondPackage],
            at: Date(timeIntervalSince1970: 1_800_030_000),
            context: context
        )
        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .completed
        )
        XCTAssertNotNil(firstPackage.completedAt)
        XCTAssertNotNil(secondPackage.completedAt)

        ReturnTrackingService.markInProgress(
            request,
            packages: [firstPackage, secondPackage],
            at: Date(timeIntervalSince1970: 1_800_040_000),
            context: context
        )
        XCTAssertNotNil(firstPackage.droppedOffAt)
        XCTAssertNotNil(secondPackage.droppedOffAt)
        XCTAssertEqual(
            ReturnTrackingService.status(for: request, packages: [firstPackage, secondPackage]),
            .completed
        )
    }

    @MainActor
    func testDeletingLastReturnItemArchivesEmptyReturn() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let request = ReturnRequest(householdID: household.id)
        let photoID = UUID()
        let package = ReturnPackage(
            householdID: household.id,
            returnRequestID: request.id,
            name: "QR code",
            carrier: .wholeFoods,
            photoAttachmentIDs: [photoID]
        )
        let item = ReturnItem(
            householdID: household.id,
            returnRequestID: request.id,
            packageID: package.id,
            name: "Puzzle mat"
        )
        let photo = PhotoAttachment(
            id: photoID,
            ownerKind: .returnPhoto,
            imageData: Data([1, 2, 3]),
            thumbnailData: Data([1])
        )

        context.insert(household)
        context.insert(request)
        context.insert(package)
        context.insert(item)
        context.insert(photo)
        try context.save()

        ReturnTrackingService.deleteItem(
            item,
            from: request,
            items: [item],
            packages: [package],
            attachments: [photo],
            context: context
        )

        XCTAssertTrue(request.isArchived)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReturnItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReturnPackage>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PhotoAttachment>()).isEmpty)
    }

    @MainActor
    func testReturnsRoundTripThroughJSONBackupWithPhotos() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let request = ReturnRequest(
            householdID: household.id
        )
        let photoID = UUID()
        let package = ReturnPackage(
            householdID: household.id,
            returnRequestID: request.id,
            name: "QR code",
            carrier: .ups,
            method: .dropOff,
            trackingNumber: "1ZTEST",
            returnByDate: Date(timeIntervalSince1970: 1_801_000_000),
            photoAttachmentIDs: [photoID],
            droppedOffAt: Date(timeIntervalSince1970: 1_801_100_000)
        )
        let item = ReturnItem(
            householdID: household.id,
            returnRequestID: request.id,
            packageID: package.id,
            name: "Puzzle mat",
            quantity: 1,
            reason: "Duplicate",
            returnURLString: "https://example.com/return"
        )
        let photo = PhotoAttachment(
            id: photoID,
            ownerKind: .returnPhoto,
            imageData: Data([1, 2, 3, 4]),
            thumbnailData: Data([1, 2])
        )
        let reminder = FoodReminder(
            householdID: household.id,
            type: .returns,
            title: "Drop off return",
            relatedReturnRequestID: request.id,
            dateTime: Date(timeIntervalSince1970: 1_800_900_000)
        )

        context.insert(household)
        context.insert(request)
        context.insert(package)
        context.insert(item)
        context.insert(photo)
        context.insert(reminder)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let importedRequest = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReturnRequest>()).first { $0.id == request.id }
        )
        let importedPackage = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReturnPackage>()).first { $0.returnRequestID == importedRequest.id }
        )
        let importedItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReturnItem>()).first { $0.returnRequestID == importedRequest.id }
        )
        let importedPhoto = try XCTUnwrap(
            context.fetch(FetchDescriptor<PhotoAttachment>()).first { $0.id == photoID }
        )
        let importedReminder = try XCTUnwrap(
            context.fetch(FetchDescriptor<FoodReminder>()).first { $0.title == "Drop off return" }
        )

        XCTAssertEqual(importedPackage.trackingNumber, "1ZTEST")
        XCTAssertEqual(importedPackage.returnByDate, Date(timeIntervalSince1970: 1_801_000_000))
        XCTAssertEqual(importedPackage.photoAttachmentIDs, [photoID])
        XCTAssertEqual(importedItem.packageID, importedPackage.id)
        XCTAssertEqual(importedItem.returnURLString, "https://example.com/return")
        XCTAssertEqual(importedPhoto.ownerKind, .returnPhoto)
        XCTAssertEqual(importedPhoto.imageData, Data([1, 2, 3, 4]))
        XCTAssertEqual(importedReminder.type, .returns)
        XCTAssertEqual(importedReminder.relatedReturnRequestID, importedRequest.id)
    }

    @MainActor
    func testFoodReminderCancelRemovesScheduledReminder() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let reminder = FoodReminder(
            householdID: household.id,
            type: .shopping,
            title: "Check shopping list",
            dateTime: Date().addingTimeInterval(3600)
        )

        context.insert(household)
        context.insert(reminder)
        try context.save()

        await FoodReminderService.cancel(reminder, context: context)

        let reminders = try context.fetch(FetchDescriptor<FoodReminder>())
        XCTAssertTrue(reminders.isEmpty)
    }

    @MainActor
    func testFoodTodoReminderNotificationDeepLinksToList() throws {
        let householdID = UUID()
        let listID = UUID()
        let reminder = FoodReminder(
            householdID: householdID,
            type: .todos,
            title: "Check house tasks",
            relatedTodoListID: listID,
            dateTime: Date(timeIntervalSince1970: 1_780_210_000)
        )

        let content = NotificationManager.shared.buildFoodReminderNotificationContent(reminder: reminder)

        XCTAssertEqual(content.title, "Check house tasks")
        XCTAssertEqual(content.body, "Check your Home to-do list.")
        XCTAssertEqual(
            content.userInfo["deepLink"] as? String,
            "littlewindows://food/todos/\(listID.uuidString)"
        )
    }

    @MainActor
    func testInventoryLocationServiceCreatesUpdatesAndArchivesLocations() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        context.insert(household)
        try context.save()

        let location = try XCTUnwrap(InventoryLocationService.addLocation(
            name: "Basement Shelf",
            locationType: .custom,
            householdID: household.id,
            notes: "Bulk storage",
            existingLocations: [],
            context: context
        ))
        XCTAssertEqual(location.name, "Basement Shelf")
        XCTAssertEqual(location.locationType, .custom)
        XCTAssertEqual(location.notes, "Bulk storage")

        let duplicate = InventoryLocationService.addLocation(
            name: " basement shelf ",
            locationType: .household,
            householdID: household.id,
            notes: "",
            existingLocations: [location],
            context: context
        )
        XCTAssertNil(duplicate)

        XCTAssertTrue(InventoryLocationService.updateLocation(
            location,
            name: "Basement Freezer",
            locationType: .freezer,
            notes: "Overflow meals",
            existingLocations: [location],
            context: context
        ))
        XCTAssertEqual(location.name, "Basement Freezer")
        XCTAssertEqual(location.locationType, .freezer)

        let inventory = InventoryItem(
            householdID: household.id,
            name: "Soup",
            quantity: 2,
            locationID: location.id
        )
        XCTAssertFalse(InventoryLocationService.archiveLocation(
            location,
            inventoryItems: [inventory],
            mealPrepItems: [],
            context: context
        ))
        XCTAssertFalse(location.isArchived)

        XCTAssertTrue(InventoryLocationService.archiveLocation(
            location,
            inventoryItems: [],
            mealPrepItems: [],
            context: context
        ))
        XCTAssertTrue(location.isArchived)
    }

    @MainActor
    func testShoppingListServiceArchivesLists() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let updatedAt = Date(timeIntervalSince1970: 100)
        let archivedAt = Date(timeIntervalSince1970: 200)
        let list = ShoppingList(
            householdID: household.id,
            name: "Test Market",
            updatedAt: updatedAt
        )
        let item = ShoppingListItem(
            householdID: household.id,
            shoppingListID: list.id,
            name: "Milk"
        )

        context.insert(household)
        context.insert(list)
        context.insert(item)
        try context.save()

        XCTAssertTrue(ShoppingListService.archiveList(list, context: context, now: archivedAt))
        XCTAssertTrue(list.isArchived)
        XCTAssertEqual(list.updatedAt, archivedAt)

        let activeLists = try context.fetch(FetchDescriptor<ShoppingList>())
            .filter { !$0.isArchived }
        XCTAssertFalse(activeLists.contains { $0.id == list.id })

        let savedItems = try context.fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(savedItems.first?.shoppingListID, list.id)
        XCTAssertFalse(ShoppingListService.archiveList(list, context: context, now: Date(timeIntervalSince1970: 300)))
        XCTAssertEqual(list.updatedAt, archivedAt)
    }

    @MainActor
    func testShoppingListSmartAddReactivatesMatchesAndBulkAddsUniqueItems() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let list = ShoppingList(householdID: household.id, name: "Test Market")
        let milk = ShoppingListItem(
            householdID: household.id,
            shoppingListID: list.id,
            name: "Milk",
            isChecked: true,
            checkedAt: Date(timeIntervalSince1970: 100),
            purchaseCount: 3
        )
        context.insert(household)
        context.insert(list)
        context.insert(milk)
        try context.save()

        let reactivatedAt = Date(timeIntervalSince1970: 200)
        let reactivated = ShoppingListService.addItem(
            named: "  MILK  ",
            to: list,
            sectionID: nil,
            existingItems: [milk],
            context: context,
            now: reactivatedAt
        )

        XCTAssertEqual(reactivated?.id, milk.id)
        XCTAssertFalse(milk.isChecked)
        XCTAssertNil(milk.checkedAt)
        XCTAssertEqual(milk.lastUncheckedAt, reactivatedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoppingListItem>()).count, 1)

        ShoppingListService.setChecked(
            milk,
            isChecked: true,
            context: context,
            now: Date(timeIntervalSince1970: 250)
        )
        let addedCount = ShoppingListService.addItems(
            from: "Milk\nBananas, Bread\n  bananas  ",
            to: list,
            sectionID: nil,
            existingItems: [milk],
            context: context,
            now: Date(timeIntervalSince1970: 300)
        )
        let savedItems = try context.fetch(FetchDescriptor<ShoppingListItem>())

        XCTAssertEqual(addedCount, 3)
        XCTAssertEqual(savedItems.count, 3)
        XCTAssertEqual(Set(savedItems.map { $0.name.lowercased() }), ["milk", "bananas", "bread"])
        XCTAssertFalse(milk.isChecked)
    }

    @MainActor
    func testShoppingListDuplicateCreatesReusableTemplateAndUniqueName() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let store = FoodStore(householdID: household.id, name: "Test Store")
        let list = ShoppingList(
            householdID: household.id,
            name: "Weekly",
            storeID: store.id,
            listType: .store,
            notes: "Main trip"
        )
        let existingCopy = ShoppingList(householdID: household.id, name: "Weekly Copy")
        let item = ShoppingListItem(
            householdID: household.id,
            shoppingListID: list.id,
            name: "Oats",
            quantity: 2,
            unit: "bags",
            notes: "Old fashioned",
            isChecked: true,
            checkedAt: Date(timeIntervalSince1970: 90),
            isRecurringStaple: true,
            isFavorite: true,
            priority: .high,
            lastPurchasedAt: Date(timeIntervalSince1970: 100),
            purchaseCount: 4,
            inventoryLinkBehavior: .addToInventoryWhenChecked
        )
        context.insert(household)
        context.insert(store)
        context.insert(list)
        context.insert(existingCopy)
        context.insert(item)
        try context.save()

        let copy = ShoppingListService.duplicateList(
            list,
            items: [item],
            existingLists: [list, existingCopy],
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        let copiedItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<ShoppingListItem>()).first { $0.shoppingListID == copy.id }
        )

        XCTAssertEqual(copy.name, "Weekly Copy 2")
        XCTAssertEqual(copy.storeID, store.id)
        XCTAssertEqual(copy.listType, .store)
        XCTAssertEqual(copy.notes, "Main trip")
        XCTAssertFalse(copiedItem.isChecked)
        XCTAssertNil(copiedItem.checkedAt)
        XCTAssertEqual(copiedItem.purchaseCount, 0)
        XCTAssertNil(copiedItem.lastPurchasedAt)
        XCTAssertTrue(copiedItem.isRecurringStaple)
        XCTAssertTrue(copiedItem.isFavorite)
        XCTAssertEqual(copiedItem.priority, .high)
        XCTAssertEqual(copiedItem.inventoryLinkBehavior, .addToInventoryWhenChecked)
    }

    @MainActor
    func testShoppingListMoveMergesDuplicatesAndClearsIncompatibleSection() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let firstStore = FoodStore(householdID: household.id, name: "First Store")
        let secondStore = FoodStore(householdID: household.id, name: "Second Store")
        let firstList = ShoppingList(householdID: household.id, name: "First", storeID: firstStore.id)
        let secondList = ShoppingList(householdID: household.id, name: "Second", storeID: secondStore.id)
        let sectionID = UUID()
        let apples = ShoppingListItem(
            householdID: household.id,
            shoppingListID: firstList.id,
            name: "Apples",
            storeSectionID: sectionID
        )
        let bread = ShoppingListItem(
            householdID: household.id,
            shoppingListID: firstList.id,
            name: "Bread"
        )
        let existingBread = ShoppingListItem(
            householdID: household.id,
            shoppingListID: secondList.id,
            name: "bread",
            isChecked: true
        )
        context.insert(household)
        context.insert(firstStore)
        context.insert(secondStore)
        context.insert(firstList)
        context.insert(secondList)
        context.insert(apples)
        context.insert(bread)
        context.insert(existingBread)
        try context.save()

        XCTAssertTrue(ShoppingListService.moveItem(
            apples,
            from: firstList,
            to: secondList,
            existingDestinationItems: [existingBread],
            context: context
        ))
        XCTAssertEqual(apples.shoppingListID, secondList.id)
        XCTAssertNil(apples.storeSectionID)

        XCTAssertTrue(ShoppingListService.moveItem(
            bread,
            from: firstList,
            to: secondList,
            existingDestinationItems: [apples, existingBread],
            context: context
        ))
        let destinationItems = try context.fetch(FetchDescriptor<ShoppingListItem>())
            .filter { $0.shoppingListID == secondList.id }
        XCTAssertEqual(destinationItems.count, 2)
        XCTAssertFalse(existingBread.isChecked)
    }

    @MainActor
    func testHomeTodoServiceTracksActorsAndCompletion() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        context.insert(household)
        try context.save()

        let list = try XCTUnwrap(HomeTodoService.createList(
            name: "House Tasks",
            householdID: household.id,
            existingLists: [],
            context: context,
            now: Date(timeIntervalSince1970: 100)
        ))
        let item = try XCTUnwrap(HomeTodoService.addItem(
            title: "Replace filter",
            notes: "Hallway closet",
            addedBy: "Caregiver A",
            assignedCaregiverName: "  Caregiver B  ",
            to: list,
            existingItems: [],
            context: context,
            now: Date(timeIntervalSince1970: 110)
        ))
        let secondItem = try XCTUnwrap(HomeTodoService.addItem(
            title: "Clean vent",
            notes: "",
            addedBy: "Caregiver A",
            to: list,
            existingItems: [item],
            context: context,
            now: Date(timeIntervalSince1970: 115)
        ))

        XCTAssertEqual(item.addedBy, "Caregiver A")
        XCTAssertEqual(item.assignedCaregiverName, "Caregiver B")
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedBy)

        HomeTodoService.updateItem(
            item,
            title: item.title,
            notes: item.notes ?? "",
            addedBy: "Caregiver A",
            assignedCaregiverName: nil,
            context: context,
            now: Date(timeIntervalSince1970: 117)
        )
        XCTAssertNil(item.assignedCaregiverName)

        HomeTodoService.setCompleted(
            item,
            isCompleted: true,
            completedBy: "Caregiver B",
            siblingItems: [item, secondItem],
            context: context,
            now: Date(timeIntervalSince1970: 120)
        )
        XCTAssertTrue(item.isCompleted)
        XCTAssertEqual(item.completedBy, "Caregiver B")
        XCTAssertEqual(item.completedAt, Date(timeIntervalSince1970: 120))

        HomeTodoService.setCompleted(
            item,
            isCompleted: false,
            completedBy: "Caregiver A",
            siblingItems: [item, secondItem],
            context: context,
            now: Date(timeIntervalSince1970: 130)
        )
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedBy)
        XCTAssertNil(item.completedAt)
        XCTAssertEqual(item.lastReopenedAt, Date(timeIntervalSince1970: 130))
        XCTAssertEqual(item.sortOrder, 2)

        XCTAssertTrue(HomeTodoService.archiveList(
            list,
            context: context,
            now: Date(timeIntervalSince1970: 140)
        ))
        XCTAssertTrue(list.isArchived)
    }

    @MainActor
    func testFoodHomeInsightsIncludeTodosAndReturns() throws {
        let household = Household(name: "Home")
        let list = HomeTodoList(householdID: household.id, name: "House Tasks")
        let archivedList = HomeTodoList(householdID: household.id, name: "Old Tasks", isArchived: true)
        let openItem = HomeTodoItem(householdID: household.id, todoListID: list.id, title: "Replace filter")
        let completedItem = HomeTodoItem(
            householdID: household.id,
            todoListID: list.id,
            title: "Clean vent",
            isCompleted: true
        )
        let ignoredArchivedItem = HomeTodoItem(
            householdID: household.id,
            todoListID: archivedList.id,
            title: "Ignore"
        )
        let needsActionReturn = ReturnRequest(householdID: household.id)
        let readyReturn = ReturnRequest(householdID: household.id)
        let completedReturn = ReturnRequest(householdID: household.id, completedAt: Date())
        let readyPackage = ReturnPackage(
            householdID: household.id,
            returnRequestID: readyReturn.id,
            name: "Drop-off",
            carrier: .wholeFoods
        )

        let metrics = FoodInsightsService.metrics(
            householdID: household.id,
            locations: [],
            inventoryItems: [],
            mealPrepItems: [],
            packingTrips: [],
            shoppingLists: [],
            shoppingItems: [],
            todoLists: [list, archivedList],
            todoItems: [openItem, completedItem, ignoredArchivedItem],
            returnRequests: [needsActionReturn, readyReturn, completedReturn],
            returnPackages: [readyPackage]
        )

        XCTAssertEqual(metrics.first(where: { $0.title == "To-Do" })?.value, "1")
        XCTAssertEqual(metrics.first(where: { $0.title == "To-Do" })?.detail, "Open items across 1 list.")
        XCTAssertEqual(metrics.first(where: { $0.title == "Completed To-Dos" })?.value, "1")
        XCTAssertEqual(metrics.first(where: { $0.title == "Returns" })?.value, "2")
        XCTAssertEqual(metrics.first(where: { $0.title == "Returns" })?.detail, "1 need action, 1 ready.")
    }

    @MainActor
    func testTodayHomeSummaryPrioritizesUsefulRowsAndRoutesToHomeDetails() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 5,
            hour: 12
        )))
        let dayStart = calendar.startOfDay(for: now)
        let household = Household(name: "Test Home")
        let otherHousehold = Household(name: "Other Home")

        let todoList = HomeTodoList(householdID: household.id, name: "House Tasks")
        let todoItems = [
            HomeTodoItem(
                householdID: household.id,
                todoListID: todoList.id,
                title: "Assigned first",
                assignedCaregiverName: "Caregiver 1",
                updatedAt: now.addingTimeInterval(-300),
                sortOrder: 5
            ),
            HomeTodoItem(householdID: household.id, todoListID: todoList.id, title: "Second", sortOrder: 0),
            HomeTodoItem(householdID: household.id, todoListID: todoList.id, title: "Third", sortOrder: 1),
            HomeTodoItem(householdID: household.id, todoListID: todoList.id, title: "Fourth", sortOrder: 2),
            HomeTodoItem(
                householdID: household.id,
                todoListID: todoList.id,
                title: "Completed today",
                isCompleted: true,
                completedAt: now.addingTimeInterval(-600)
            )
        ]

        let shoppingList = ShoppingList(householdID: household.id, name: "Groceries")
        let shoppingItems = [
            ShoppingListItem(
                householdID: household.id,
                shoppingListID: shoppingList.id,
                name: "Milk",
                priority: .high
            ),
            ShoppingListItem(
                householdID: household.id,
                shoppingListID: shoppingList.id,
                name: "Bread"
            ),
            ShoppingListItem(
                householdID: household.id,
                shoppingListID: shoppingList.id,
                name: "Apples",
                isChecked: true,
                checkedAt: now.addingTimeInterval(-900)
            )
        ]

        let locationID = UUID()
        let lowMealPrep = MealPrepItem(
            householdID: household.id,
            name: "Soup",
            locationID: locationID,
            servingsTotal: 4,
            servingsRemaining: 1
        )
        let usage = MealPrepUsage(
            householdID: household.id,
            mealPrepItemID: lowMealPrep.id,
            dateTime: now.addingTimeInterval(-1_200),
            servingsUsed: 1
        )
        let usedUpInventory = InventoryItem(
            householdID: household.id,
            name: "Rice",
            quantity: 0,
            locationID: locationID,
            status: .usedUp
        )

        let trip = PackingTrip(
            householdID: household.id,
            title: "Day Trip",
            startDate: dayStart,
            endDate: dayStart.addingTimeInterval(2 * 86_400),
            finalCheckDate: now.addingTimeInterval(-3_600)
        )
        let essential = PackingItem(
            householdID: household.id,
            tripID: trip.id,
            title: "Tickets",
            priority: .essential,
            state: .needed
        )
        let itinerary = TripItineraryItem(
            householdID: household.id,
            tripID: trip.id,
            title: "Museum",
            scheduledDay: dayStart
        )

        let returnRequest = ReturnRequest(householdID: household.id)
        let returnItem = ReturnItem(
            householdID: household.id,
            returnRequestID: returnRequest.id,
            name: "Shoes"
        )
        let returnPackage = ReturnPackage(
            householdID: household.id,
            returnRequestID: returnRequest.id,
            name: "Drop-off",
            returnByDate: dayStart.addingTimeInterval(-86_400)
        )
        let reminder = FoodReminder(
            householdID: household.id,
            type: .shopping,
            title: "Pick up groceries",
            relatedShoppingListID: shoppingList.id,
            dateTime: now.addingTimeInterval(1_800)
        )
        let ignoredList = HomeTodoList(householdID: otherHousehold.id, name: "Ignore")
        let ignoredItem = HomeTodoItem(
            householdID: otherHousehold.id,
            todoListID: ignoredList.id,
            title: "Other household"
        )

        let summary = TodayHomeSummaryService.summary(
            householdID: household.id,
            currentCaregiverName: "Caregiver 1",
            todoLists: [todoList, ignoredList],
            todoItems: todoItems + [ignoredItem],
            shoppingLists: [shoppingList],
            shoppingItems: shoppingItems,
            inventoryItems: [usedUpInventory],
            mealPrepItems: [lowMealPrep],
            mealPrepUsages: [usage],
            packingTrips: [trip],
            packingItems: [essential],
            itineraryItems: [itinerary],
            returnRequests: [returnRequest],
            returnItems: [returnItem],
            returnPackages: [returnPackage],
            reminders: [reminder],
            now: now,
            calendar: calendar
        )

        let todos = try XCTUnwrap(summary.sections.first { $0.category == .todos })
        XCTAssertEqual(todos.countLabel, "4 open")
        XCTAssertEqual(todos.items.count, TodayHomeSummaryService.visibleItemLimit)
        XCTAssertEqual(todos.items.first?.title, "Assigned first")
        XCTAssertEqual(todos.items.first?.route, .todoList(todoList.id))
        XCTAssertEqual(todos.remainderText, "+ 1 more task")
        XCTAssertTrue(todos.summary.contains("1 completed today"))

        let shopping = try XCTUnwrap(summary.sections.first { $0.category == .shopping })
        XCTAssertEqual(shopping.countLabel, "2 items")
        XCTAssertEqual(shopping.items.first?.route, .shoppingList(shoppingList.id))
        XCTAssertEqual(shopping.items.first?.badge, "1 high priority")

        let kitchen = try XCTUnwrap(summary.sections.first { $0.category == .kitchen })
        XCTAssertEqual(kitchen.items.first?.route, .mealPrepItem(lowMealPrep.id))
        XCTAssertTrue(kitchen.summary.contains("1 used today"))

        let trips = try XCTUnwrap(summary.sections.first { $0.category == .trips })
        XCTAssertEqual(trips.items.first?.route, .itineraryItem(trip.id, itinerary.id))
        XCTAssertTrue(trips.summary.contains("1 itinerary item today"))

        let returns = try XCTUnwrap(summary.sections.first { $0.category == .returns })
        XCTAssertEqual(returns.items.first?.title, "Shoes")
        XCTAssertEqual(returns.items.first?.route, .returnRequest(returnRequest.id))
        XCTAssertEqual(returns.items.first?.badge, "Overdue")

        XCTAssertTrue(summary.attentionItems.contains { $0.route == .shoppingList(shoppingList.id) })
        XCTAssertTrue(summary.attentionItems.contains { $0.route == .mealPrepItem(lowMealPrep.id) })
        XCTAssertTrue(summary.attentionItems.contains { $0.route == .packingList(trip.id) })
        XCTAssertTrue(summary.attentionItems.contains { $0.route == .returnRequest(returnRequest.id) })
        XCTAssertFalse(summary.sections.flatMap(\.items).contains { $0.title == "Other household" })
    }

    @MainActor
    func testTodayDisplayModePersistsForTabChangesButTodayRoutesResetToCare() throws {
        let router = DeepLinkRouter.shared
        router.todayDisplayMode = .home
        router.selectedTab = .reports
        router.selectedTab = .today
        XCTAssertEqual(router.todayDisplayMode, .home)

        router.route(try XCTUnwrap(URL(string: "littlewindows://today")))
        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertEqual(router.todayDisplayMode, .care)

        router.todayDisplayMode = .home
        router.openToday(action: .logEvent(.feed))
        XCTAssertEqual(router.todayDisplayMode, .care)
        XCTAssertEqual(router.consumeAction(), .logEvent(.feed))
    }

    func testHouseholdOnlyExperienceKeepsHomeToolsAndNormalizesCareDestinations() {
        let householdOnly = AppExperienceMode(hasActiveCareProfile: false)

        XCTAssertEqual(householdOnly, .householdOnly)
        XCTAssertEqual(householdOnly.availableTabs, [.today, .food, .nightLight])
        XCTAssertEqual(householdOnly.normalizedTab(.reports), .today)
        XCTAssertEqual(householdOnly.normalizedTab(.milestones), .today)
        XCTAssertEqual(householdOnly.normalizedTab(.food), .food)
        XCTAssertEqual(householdOnly.normalizedTodayMode(.care), .home)

        let care = AppExperienceMode(hasActiveCareProfile: true)
        XCTAssertEqual(care.availableTabs, [.today, .food, .reports, .milestones, .nightLight])
        XCTAssertEqual(care.normalizedTab(.reports), .reports)
        XCTAssertEqual(care.normalizedTodayMode(.care), .care)
    }

    func testHouseholdOnlyNavigationPolicyPromptsOnlyForCareScopedRoutes() throws {
        let householdURLs = [
            "littlewindows://today",
            "littlewindows://food",
            "littlewindows://food/todos",
            "littlewindows://food/quick-add",
            "littlewindows://food/shopping/00000000-0000-0000-0000-000000000501",
            "littlewindows://food/trips/00000000-0000-0000-0000-000000000401",
            "littlewindows://food/inventory",
            "littlewindows://food/meal-prep",
            "littlewindows://food/returns",
            "littlewindows://night-light/diaper-change",
            "littlewindows://night-light/stop",
            "littlewindows://settings",
            "littlewindows://settings/family-sync",
            "littlewindows://profile/00000000-0000-0000-0000-000000000101/food",
            "littlewindows://profile/00000000-0000-0000-0000-000000000101/night-light"
        ]
        for value in householdURLs {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(AppNavigationPolicy.careProfileRequirement(for: url))
            XCTAssertTrue(AppNavigationPolicy.isHouseholdRoute(url))
        }

        let careRoutes: [(String, CareProfileRequirement)] = [
            ("littlewindows://quick-log/sleep", .logging),
            ("littlewindows://quick-log/nursing-left", .logging),
            ("littlewindows://quick-log/medicine", .logging),
            ("littlewindows://action/stop-active", .logging),
            ("littlewindows://active-timer", .logging),
            ("littlewindows://event/00000000-0000-0000-0000-000000000201", .logging),
            ("littlewindows://profile/00000000-0000-0000-0000-000000000101/today", .logging),
            ("littlewindows://history", .reports),
            ("littlewindows://reports/summary", .reports),
            ("littlewindows://insights/feeding", .reports),
            ("littlewindows://medical", .reports),
            ("littlewindows://prediction", .reports),
            ("littlewindows://care/solids", .care),
            ("littlewindows://food/solids/allergens", .care),
            ("littlewindows://milestones", .care),
            ("littlewindows://memories", .care),
            ("littlewindows://age-guide/6", .care),
            ("littlewindows://puppy-guide", .care),
            ("littlewindows://appointments", .appointments),
            ("littlewindows://visits", .appointments),
            ("littlewindows://appointment/00000000-0000-0000-0000-000000000301", .appointments),
            ("littlewindows://routines", .routines)
        ]
        for (value, expectedRequirement) in careRoutes {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(
                AppNavigationPolicy.careProfileRequirement(for: url),
                expectedRequirement
            )
            XCTAssertFalse(AppNavigationPolicy.isHouseholdRoute(url))
        }

        XCTAssertTrue(AppNavigationPolicy.isSettingsRoute(
            try XCTUnwrap(URL(string: "littlewindows://settings/family-sync"))
        ))
        XCTAssertFalse(AppNavigationPolicy.isSettingsRoute(
            try XCTUnwrap(URL(string: "littlewindows://food"))
        ))
    }

    @MainActor
    func testHouseholdNavigationDiscardsAnOverriddenCareCommand() throws {
        let router = DeepLinkRouter.shared
        router.route(try XCTUnwrap(URL(string: "littlewindows://quick-log/sleep")))
        XCTAssertNotNil(router.pendingAction)

        router.route(try XCTUnwrap(URL(string: "littlewindows://food")))

        XCTAssertNil(router.pendingAction)
        XCTAssertNil(router.pendingProfileID)
        XCTAssertEqual(router.selectedTab, .food)
    }

    @MainActor
    func testFoodHomeInsightsSeparatePackingTripsFromShoppingListHistory() {
        let household = Household(name: "Home")
        let usedShoppingList = ShoppingList(
            householdID: household.id,
            name: "Groceries",
            lastUsedAt: Date(timeIntervalSince1970: 100)
        )
        let unusedShoppingList = ShoppingList(householdID: household.id, name: "Supplies")
        let completedTrip = PackingTrip(
            householdID: household.id,
            title: "Completed Trip",
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 200),
            status: .completed,
            completedAt: Date(timeIntervalSince1970: 300)
        )
        let upcomingTrip = PackingTrip(
            householdID: household.id,
            title: "Upcoming Trip",
            startDate: Date(timeIntervalSince1970: 400),
            endDate: Date(timeIntervalSince1970: 500)
        )

        let metrics = FoodInsightsService.metrics(
            householdID: household.id,
            locations: [],
            inventoryItems: [],
            mealPrepItems: [],
            packingTrips: [completedTrip, upcomingTrip],
            shoppingLists: [usedShoppingList, unusedShoppingList],
            shoppingItems: [],
            todoLists: [],
            todoItems: [],
            returnRequests: [],
            returnPackages: []
        )

        XCTAssertEqual(metrics.first(where: { $0.title == "Lists Used" })?.value, "1")
        XCTAssertEqual(
            metrics.first(where: { $0.title == "Lists Used" })?.detail,
            "Reusable shopping lists completed at least once."
        )
        XCTAssertEqual(metrics.first(where: { $0.title == "Trips" })?.value, "1")
        XCTAssertEqual(metrics.first(where: { $0.title == "Trips" })?.detail, "Packing trips marked complete.")
        XCTAssertEqual(
            metrics.first(where: { $0.title == "Frequent Buy" })?.detail,
            "Complete a shopping list to build history."
        )
    }

    @MainActor
    func testHomeTodoServiceReordersItems() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let list = HomeTodoList(householdID: household.id, name: "House Tasks")
        let first = HomeTodoItem(householdID: household.id, todoListID: list.id, title: "First", sortOrder: 0)
        let second = HomeTodoItem(householdID: household.id, todoListID: list.id, title: "Second", sortOrder: 1)
        let third = HomeTodoItem(householdID: household.id, todoListID: list.id, title: "Third", sortOrder: 2)
        context.insert(household)
        context.insert(list)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        HomeTodoService.reorderItems(
            [first, second, third],
            from: IndexSet(integer: 2),
            to: 0,
            context: context,
            now: Date(timeIntervalSince1970: 300)
        )

        XCTAssertEqual(third.sortOrder, 0)
        XCTAssertEqual(first.sortOrder, 1)
        XCTAssertEqual(second.sortOrder, 2)
        XCTAssertEqual(first.updatedAt, Date(timeIntervalSince1970: 300))
    }

    @MainActor
    func testHomeTodoServiceReordersLists() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let first = HomeTodoList(householdID: household.id, name: "First", sortOrder: 0)
        let second = HomeTodoList(householdID: household.id, name: "Second", sortOrder: 1)
        let third = HomeTodoList(householdID: household.id, name: "Third", sortOrder: 2)
        context.insert(household)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        HomeTodoService.reorderLists(
            [first, second, third],
            from: IndexSet(integer: 0),
            to: 3,
            context: context,
            now: Date(timeIntervalSince1970: 310)
        )

        XCTAssertEqual(second.sortOrder, 0)
        XCTAssertEqual(third.sortOrder, 1)
        XCTAssertEqual(first.sortOrder, 2)
        XCTAssertEqual(third.updatedAt, Date(timeIntervalSince1970: 310))
    }

    @MainActor
    func testHomeTodosRoundTripThroughBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        let list = HomeTodoList(
            householdID: household.id,
            name: "Weekend",
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 201)
        )
        let item = HomeTodoItem(
            householdID: household.id,
            todoListID: list.id,
            title: "Change sheets",
            isCompleted: true,
            addedBy: "Caregiver A",
            assignedCaregiverName: "Caregiver B",
            completedBy: "Caregiver B",
            completedAt: Date(timeIntervalSince1970: 210),
            createdAt: Date(timeIntervalSince1970: 205),
            updatedAt: Date(timeIntervalSince1970: 210)
        )
        context.insert(household)
        context.insert(list)
        context.insert(item)
        try context.save()

        let data = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(data, context: context, recordLocalSave: false)

        let importedList = try XCTUnwrap(
            context.fetch(FetchDescriptor<HomeTodoList>()).first { $0.name == "Weekend" }
        )
        let importedItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<HomeTodoItem>()).first { $0.todoListID == importedList.id }
        )
        XCTAssertEqual(importedItem.title, "Change sheets")
        XCTAssertTrue(importedItem.isCompleted)
        XCTAssertEqual(importedItem.addedBy, "Caregiver A")
        XCTAssertEqual(importedItem.assignedCaregiverName, "Caregiver B")
        XCTAssertEqual(importedItem.completedBy, "Caregiver B")
        XCTAssertEqual(importedItem.completedAt, Date(timeIntervalSince1970: 210))
    }

    func testFamilySyncCaregiverDirectoryNormalizesAndPersistsNames() throws {
        let suiteName = "FamilySyncCaregiverDirectory-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CaregiverIdentityService.storeFamilySyncCaregiverNames(
            ["  Caregiver B ", "caregiver b", "Caregiver A", ""],
            defaults: defaults
        )

        XCTAssertEqual(
            CaregiverIdentityService.familySyncCaregiverNames(defaults: defaults),
            ["Caregiver A", "Caregiver B"]
        )
    }

    func testCaregiverIdentityRestoresFromNewerICloudPayload() throws {
        let suiteName = "CaregiverIdentityICloud-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updatedAt = Date(timeIntervalSince1970: 500)
        let data = try XCTUnwrap(CaregiverIdentityService.iCloudPayloadData(
            currentName: "Test Caregiver",
            primaryName: "Test Caregiver",
            updatedAt: updatedAt
        ))

        XCTAssertTrue(CaregiverIdentityService.applyICloudPayloadData(data, defaults: defaults))
        XCTAssertEqual(
            defaults.string(forKey: CaregiverIdentityService.currentCaregiverNameKey),
            "Test Caregiver"
        )
        XCTAssertEqual(
            defaults.string(forKey: CaregiverIdentityService.primaryCaregiverNameKey),
            "Test Caregiver"
        )
        XCTAssertEqual(
            defaults.object(forKey: CaregiverIdentityService.lastModifiedAtKey) as? Date,
            updatedAt
        )
    }

    func testCaregiverIdentityKeepsNewerLocalValue() throws {
        let suiteName = "CaregiverIdentityNewerLocal-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "Local Test Caregiver",
            forKey: CaregiverIdentityService.currentCaregiverNameKey
        )
        defaults.set(
            Date(timeIntervalSince1970: 600),
            forKey: CaregiverIdentityService.lastModifiedAtKey
        )
        let data = try XCTUnwrap(CaregiverIdentityService.iCloudPayloadData(
            currentName: "Cloud Test Caregiver",
            primaryName: "Cloud Test Caregiver",
            updatedAt: Date(timeIntervalSince1970: 500)
        ))

        XCTAssertFalse(CaregiverIdentityService.applyICloudPayloadData(data, defaults: defaults))
        XCTAssertEqual(
            defaults.string(forKey: CaregiverIdentityService.currentCaregiverNameKey),
            "Local Test Caregiver"
        )
    }

    func testCaregiverIdentityRecoversOnlyOneNonDefaultHistoricalName() {
        XCTAssertEqual(
            CaregiverIdentityService.recoverableHistoricalName(
                from: ["Caregiver 1", " Test Caregiver ", "test caregiver", nil]
            ),
            "Test Caregiver"
        )
        XCTAssertNil(CaregiverIdentityService.recoverableHistoricalName(
            from: ["Test Caregiver", "Second Caregiver"]
        ))
    }

    @MainActor
    func testCaregiverIdentityRoundTripsThroughJSONBackupButNotFamilyDataset() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        context.insert(CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown))
        try context.save()

        let sourceSuite = "CaregiverIdentityBackupSource-\(UUID().uuidString)"
        let targetSuite = "CaregiverIdentityBackupTarget-\(UUID().uuidString)"
        let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: sourceSuite))
        let targetDefaults = try XCTUnwrap(UserDefaults(suiteName: targetSuite))
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            targetDefaults.removePersistentDomain(forName: targetSuite)
        }
        PersistenceService.setFamilySyncMode(.localOnly, defaults: sourceDefaults)
        PersistenceService.setFamilySyncMode(.localOnly, defaults: targetDefaults)
        CaregiverIdentityService.storeIdentity(
            currentName: "Test Caregiver",
            primaryName: "Test Caregiver",
            defaults: sourceDefaults,
            now: Date(timeIntervalSince1970: 500)
        )

        let backup = try DataExportImportService.exportData(
            context: context,
            defaults: sourceDefaults
        )
        let backupObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: backup) as? [String: Any]
        )
        let identity = try XCTUnwrap(backupObject["caregiverIdentity"] as? [String: Any])
        XCTAssertEqual(identity["currentName"] as? String, "Test Caregiver")

        let familyData = try DataExportImportService.exportData(
            context: context,
            defaults: sourceDefaults,
            includeCaregiverIdentity: false
        )
        let familyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: familyData) as? [String: Any]
        )
        XCTAssertNil(familyObject["caregiverIdentity"])

        try DataExportImportService.importData(
            backup,
            context: context,
            recordLocalSave: false,
            createRecoveryBackup: false,
            defaults: targetDefaults
        )
        XCTAssertEqual(
            targetDefaults.string(forKey: CaregiverIdentityService.currentCaregiverNameKey),
            "Test Caregiver"
        )
    }

    @MainActor
    func testStoreSectionsCanReorderAndRemoveDefaultsWithoutOrphaningItems() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        context.insert(household)
        try context.save()

        let store = try XCTUnwrap(StoreLayoutService.createStore(
            name: "Test Store",
            householdID: household.id,
            context: context
        ))
        let originalSections = try context.fetch(FetchDescriptor<FoodStoreSection>())
            .filter { $0.storeID == store.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(originalSections.count, 6)

        let produce = try XCTUnwrap(originalSections.first { $0.name == "Produce" })
        let list = try XCTUnwrap(ShoppingListService.createList(
            name: "Test List",
            householdID: household.id,
            storeID: store.id,
            context: context
        ))
        let item = ShoppingListItem(
            householdID: household.id,
            shoppingListID: list.id,
            name: "Sample Item",
            storeSectionID: produce.id
        )
        context.insert(item)
        try context.save()

        let reversedSections = Array(originalSections.reversed())
        XCTAssertTrue(StoreLayoutService.reorderSections(
            reversedSections,
            in: store,
            context: context,
            now: Date(timeIntervalSince1970: 400)
        ))
        XCTAssertEqual(reversedSections.map(\.sortOrder), Array(0..<reversedSections.count))

        XCTAssertTrue(StoreLayoutService.deleteSection(
            produce,
            from: store,
            shoppingItems: [item],
            remainingSections: reversedSections,
            context: context,
            now: Date(timeIntervalSince1970: 500)
        ))

        let remainingSections = try context.fetch(FetchDescriptor<FoodStoreSection>())
            .filter { $0.storeID == store.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(remainingSections.count, 5)
        XCTAssertFalse(remainingSections.contains { $0.id == produce.id })
        XCTAssertEqual(remainingSections.map(\.sortOrder), Array(0..<remainingSections.count))
        XCTAssertNil(item.storeSectionID)
    }

    @MainActor
    func testFoodCleanupServicesRemoveAndArchiveUserItems() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Home")
        context.insert(household)
        try context.save()

        let store = try XCTUnwrap(StoreLayoutService.createStore(
            name: "Test Store",
            householdID: household.id,
            context: context
        ))
        XCTAssertTrue(StoreLayoutService.archiveStore(store, context: context))
        XCTAssertTrue(store.isArchived)
        XCTAssertFalse(StoreLayoutService.archiveStore(store, context: context))

        let location = try XCTUnwrap(InventoryLocationService.addLocation(
            name: "Pantry",
            locationType: .pantry,
            householdID: household.id,
            notes: "",
            existingLocations: [],
            context: context
        ))
        let inventory = try XCTUnwrap(FoodInventoryService.addInventoryItem(
            name: "Pasta",
            quantity: 2,
            unit: "boxes",
            locationID: location.id,
            householdID: household.id,
            context: context
        ))
        FoodInventoryService.deleteInventoryItem(inventory, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryItem>()).isEmpty)
        XCTAssertTrue(InventoryLocationService.archiveLocation(
            location,
            inventoryItems: [],
            mealPrepItems: [],
            context: context
        ))

        let shoppingList = try XCTUnwrap(ShoppingListService.createList(
            name: "Errands",
            householdID: household.id,
            storeID: nil,
            context: context
        ))
        ShoppingListService.addItem(
            named: "Soap",
            to: shoppingList,
            sectionID: nil,
            existingItems: [],
            context: context
        )
        let shoppingItem = try XCTUnwrap(try context.fetch(FetchDescriptor<ShoppingListItem>()).first)
        ShoppingListService.deleteItem(shoppingItem, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShoppingListItem>()).isEmpty)

        let mealPrep = try XCTUnwrap(MealPrepService.createMealPrepItem(
            name: "Soup portions",
            servingsRemaining: 3,
            servingUnit: .serving,
            locationID: location.id,
            householdID: household.id,
            preparedDate: nil,
            notes: "",
            tags: "",
            context: context
        ))
        MealPrepService.archive(mealPrep, context: context)
        XCTAssertTrue(mealPrep.isArchived)
    }

    @MainActor
    func testMonthlyAgeGuideNotificationTimingUsesReadableMorning() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reachedDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 2))!

        let oneDayAfter = NotificationManager.monthlyAgeGuideFireDate(
            reachedDate: reachedDate,
            timing: .oneDayAfter,
            calendar: calendar
        )
        let firstWeekend = NotificationManager.monthlyAgeGuideFireDate(
            reachedDate: reachedDate,
            timing: .firstWeekendAfter,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.hour, from: oneDayAfter), 9)
        XCTAssertEqual(calendar.component(.day, from: oneDayAfter), 16)
        XCTAssertTrue(calendar.isDateInWeekend(firstWeekend))
        XCTAssertEqual(calendar.component(.hour, from: firstWeekend), 9)
    }

    func testFamilySyncModeDefaultsToPrivateICloudAndTracksSharedMode() throws {
        let defaults = try makeIsolatedDefaults()

        XCTAssertEqual(PersistenceService.familySyncMode(defaults: defaults), .privateICloudSync)
        XCTAssertTrue(PersistenceService.isICloudSyncEnabled(defaults: defaults))

        PersistenceService.setICloudSyncEnabled(false, defaults: defaults)
        XCTAssertEqual(PersistenceService.familySyncMode(defaults: defaults), .localOnly)
        XCTAssertFalse(PersistenceService.isICloudSyncEnabled(defaults: defaults))

        PersistenceService.setFamilySyncMode(.sharedFamilySync, defaults: defaults)
        XCTAssertEqual(PersistenceService.familySyncMode(defaults: defaults), .sharedFamilySync)
        XCTAssertTrue(PersistenceService.isICloudSyncEnabled(defaults: defaults))
    }

    func testFamilySyncCanonicalDataIgnoresExportTimestamp() throws {
        let first = Data(
            #"{"version":14,"exportedAt":"2026-07-26T10:00:00Z","profiles":[],"events":[]}"#.utf8
        )
        let second = Data(
            #"{"version":14,"exportedAt":"2026-07-26T10:05:00Z","profiles":[],"events":[]}"#.utf8
        )

        XCTAssertEqual(
            try DataExportImportService.familySyncCanonicalData(from: first),
            try DataExportImportService.familySyncCanonicalData(from: second)
        )
    }

    func testFamilySyncThreeWayMergePreservesConcurrentRecordChanges() throws {
        let eventID = UUID().uuidString
        let appointmentID = UUID().uuidString
        let base = Data(
            #"{"version":14,"exportedAt":"2026-07-26T10:00:00Z","events":[],"appointments":[]}"#.utf8
        )
        let local = Data(
            """
            {"version":14,"exportedAt":"2026-07-26T10:01:00Z","events":[{"id":"\(eventID)","updatedAt":"2026-07-26T10:01:00Z"}],"appointments":[]}
            """.utf8
        )
        let remote = Data(
            """
            {"version":14,"exportedAt":"2026-07-26T10:02:00Z","events":[],"appointments":[{"id":"\(appointmentID)","updatedAt":"2026-07-26T10:02:00Z"}]}
            """.utf8
        )

        let merged = try DataExportImportService.mergeFamilySyncData(
            base: base,
            local: local,
            remote: remote,
            localChangedAt: Date(timeIntervalSince1970: 100),
            remoteChangedAt: Date(timeIntervalSince1970: 200)
        )
        let records = try DataExportImportService.familySyncEntityPayloads(from: merged)

        XCTAssertNotNil(records["events|\(eventID)"])
        XCTAssertNotNil(records["appointments|\(appointmentID)"])
    }

    func testFamilySyncThreeWayMergeRetainsRemoteDeletion() throws {
        let eventID = UUID().uuidString
        let baseAndLocal = Data(
            """
            {"version":14,"exportedAt":"2026-07-26T10:00:00Z","events":[{"id":"\(eventID)","updatedAt":"2026-07-26T10:00:00Z"}]}
            """.utf8
        )
        let remote = Data(
            #"{"version":14,"exportedAt":"2026-07-26T10:02:00Z","events":[]}"#.utf8
        )

        let merged = try DataExportImportService.mergeFamilySyncData(
            base: baseAndLocal,
            local: baseAndLocal,
            remote: remote,
            localChangedAt: Date(timeIntervalSince1970: 100),
            remoteChangedAt: Date(timeIntervalSince1970: 200)
        )
        let records = try DataExportImportService.familySyncEntityPayloads(from: merged)

        XCTAssertNil(records["events|\(eventID)"])
    }

    func testFamilySyncTripMergePreservesConcurrentItemsAndFutureCollections() throws {
        let localItemID = UUID().uuidString
        let remoteItemID = UUID().uuidString
        let futureRecordID = UUID().uuidString
        let base = Data(
            #"{"version":16,"exportedAt":"2026-07-26T10:00:00Z","packingItems":[],"futureTripRules":[]}"#.utf8
        )
        let local = Data(
            """
            {"version":16,"exportedAt":"2026-07-26T10:01:00Z","packingItems":[{"id":"\(localItemID)","title":"Local item","updatedAt":"2026-07-26T10:01:00Z"}],"futureTripRules":[]}
            """.utf8
        )
        let remote = Data(
            """
            {"version":17,"exportedAt":"2026-07-26T10:02:00Z","packingItems":[{"id":"\(remoteItemID)","title":"Remote item","updatedAt":"2026-07-26T10:02:00Z"}],"futureTripRules":[{"id":"\(futureRecordID)","updatedAt":"2026-07-26T10:02:00Z"}]}
            """.utf8
        )

        let merged = try DataExportImportService.mergeFamilySyncData(
            base: base,
            local: local,
            remote: remote,
            localChangedAt: Date(timeIntervalSince1970: 100),
            remoteChangedAt: Date(timeIntervalSince1970: 200)
        )
        let records = try DataExportImportService.familySyncEntityPayloads(from: merged)

        XCTAssertNotNil(records["packingItems|\(localItemID)"])
        XCTAssertNotNil(records["packingItems|\(remoteItemID)"])
        XCTAssertNotNil(records["futureTripRules|\(futureRecordID)"])
    }

    func testFamilySyncTripMergeRetainsRemoteItemDeletion() throws {
        let itemID = UUID().uuidString
        let baseAndLocal = Data(
            """
            {"version":16,"exportedAt":"2026-07-26T10:00:00Z","packingItems":[{"id":"\(itemID)","title":"Removed item","updatedAt":"2026-07-26T10:00:00Z"}]}
            """.utf8
        )
        let remote = Data(
            #"{"version":16,"exportedAt":"2026-07-26T10:02:00Z","packingItems":[]}"#.utf8
        )

        let merged = try DataExportImportService.mergeFamilySyncData(
            base: baseAndLocal,
            local: baseAndLocal,
            remote: remote,
            localChangedAt: Date(timeIntervalSince1970: 100),
            remoteChangedAt: Date(timeIntervalSince1970: 200)
        )
        let records = try DataExportImportService.familySyncEntityPayloads(from: merged)

        XCTAssertNil(records["packingItems|\(itemID)"])
    }

    @MainActor
    func testFamilySyncConflictResolverStopsDuplicateActiveTimers() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profileID = UUID()
        let earlyStart = Date(timeIntervalSince1970: 100)
        let laterStart = Date(timeIntervalSince1970: 200)
        let resolutionDate = Date(timeIntervalSince1970: 500)

        let first = CareEvent(
            id: UUID(),
            profileID: profileID,
            type: .sleep,
            startDate: earlyStart,
            caregiverName: "Caregiver A"
        )
        first.createdAt = earlyStart
        first.updatedAt = earlyStart
        first.timerState = .running
        first.timerAccumulatedSeconds = 0
        first.activeTimerSegmentStartDate = earlyStart

        let duplicate = CareEvent(
            id: UUID(),
            profileID: profileID,
            type: .sleep,
            startDate: laterStart,
            caregiverName: "Caregiver B"
        )
        duplicate.createdAt = laterStart
        duplicate.updatedAt = laterStart
        duplicate.timerState = .running
        duplicate.timerAccumulatedSeconds = 0
        duplicate.activeTimerSegmentStartDate = laterStart

        context.insert(first)
        context.insert(duplicate)
        try context.save()

        CloudKitFamilySyncConflictResolver.resolveDuplicateActiveTimers(
            in: context,
            now: resolutionDate
        )

        XCTAssertTrue(first.isTimerRunning)
        XCTAssertFalse(duplicate.isTimerRunning)
        XCTAssertTrue(duplicate.isTimerDraft)
        XCTAssertNil(duplicate.activeTimerSegmentStartDate)
        XCTAssertEqual(duplicate.timerElapsed(at: resolutionDate), 300, accuracy: 0.001)
    }

    private func wavSamples(for sound: NightLightSound) throws -> [Double] {
        let data = NightLightAudioService.generatedWAVData(for: sound)
        return try wavSamples(from: data)
    }

    private func wavSamples(from data: Data) throws -> [Double] {
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "RIFF")
        let sampleBytes = data.dropFirst(44)
        return stride(from: sampleBytes.startIndex, to: sampleBytes.endIndex, by: 2).compactMap {
            guard $0 + 1 < sampleBytes.endIndex else { return nil }
            let low = UInt16(sampleBytes[$0])
            let high = UInt16(sampleBytes[$0 + 1]) << 8
            return Double(Int16(bitPattern: high | low)) / Double(Int16.max)
        }
    }

    private func trimmedMiddle(_ samples: [Double]) -> [Double] {
        let trim = min(samples.count / 4, 22_050)
        guard samples.count > trim * 2 else { return samples }
        return Array(samples.dropFirst(trim).dropLast(trim))
    }

    private func rms(_ samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count))
    }

    private func zeroCrossingRate(_ samples: [Double]) -> Double {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for index in 1..<samples.count where (samples[index - 1] < 0) != (samples[index] < 0) {
            crossings += 1
        }
        return Double(crossings) / Double(samples.count - 1)
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "LittleWindowsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    func testCareRoutineTemplateCreatesScopedRoutineAndSteps() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profile = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        let household = Household(name: "Home")
        context.insert(profile)
        context.insert(household)

        let template = try XCTUnwrap(
            CareRoutineService.templates(for: .child).first { $0.kind == .childBedtime }
        )
        let routine = CareRoutineService.createRoutine(
            from: template,
            profileID: profile.id,
            profileType: profile.profileType,
            householdID: household.id,
            existingRoutines: [],
            context: context
        )

        let routines = try context.fetch(FetchDescriptor<CareRoutine>())
        let steps = try context.fetch(FetchDescriptor<CareRoutineStep>())
        XCTAssertEqual(routines.map(\.id), [routine.id])
        XCTAssertEqual(routine.scope, .profile)
        XCTAssertEqual(routine.profileType, .child)
        XCTAssertEqual(routine.profileID, profile.id)
        XCTAssertNil(routine.householdID)
        XCTAssertEqual(steps.filter { $0.routineID == routine.id }.count, template.steps.count)
    }

    @MainActor
    func testCareRoutineVisibilitySeparatesProfilesHouseholdAndArchived() throws {
        let profileID = UUID()
        let otherProfileID = UUID()
        let householdID = UUID()
        let otherHouseholdID = UUID()
        let profileRoutine = CareRoutine(scope: .profile, profileType: .child, profileID: profileID, title: "Profile care", sortOrder: 1)
        let otherProfileRoutine = CareRoutine(scope: .profile, profileType: .child, profileID: otherProfileID, title: "Other profile", sortOrder: 0)
        let householdRoutine = CareRoutine(scope: .household, profileType: .child, householdID: householdID, title: "Household reset", sortOrder: 2)
        let dogHouseholdRoutine = CareRoutine(scope: .household, profileType: .dog, householdID: householdID, title: "Dog reset", sortOrder: 3)
        let legacyHouseholdRoutine = CareRoutine(scope: .household, householdID: householdID, title: "Legacy shared", sortOrder: 4)
        let otherHouseholdRoutine = CareRoutine(scope: .household, householdID: otherHouseholdID, title: "Other household", sortOrder: 3)
        let archivedRoutine = CareRoutine(scope: .profile, profileID: profileID, title: "Archived", isArchived: true, sortOrder: 4)

        let visible = CareRoutineService.visibleRoutines(
            routines: [
                otherProfileRoutine,
                archivedRoutine,
                householdRoutine,
                dogHouseholdRoutine,
                legacyHouseholdRoutine,
                profileRoutine,
                otherHouseholdRoutine
            ],
            profileID: profileID,
            profileType: .child,
            householdID: householdID
        )

        XCTAssertEqual(visible.map(\.id), [profileRoutine.id, householdRoutine.id, legacyHouseholdRoutine.id])

        let dogVisible = CareRoutineService.visibleRoutines(
            routines: [profileRoutine, householdRoutine, dogHouseholdRoutine, legacyHouseholdRoutine],
            profileID: profileID,
            profileType: .dog,
            householdID: householdID
        )
        XCTAssertEqual(dogVisible.map(\.id), [dogHouseholdRoutine.id, legacyHouseholdRoutine.id])
    }

    @MainActor
    func testCareRoutineCompletedAndSkippedStepsFinishRunWithoutEvents() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let routine = CareRoutine(scope: .household, householdID: UUID(), title: "Grocery reset")
        let first = CareRoutineStep(routineID: routine.id, title: "Check pantry", sortOrder: 0)
        let second = CareRoutineStep(routineID: routine.id, title: "Open Food", action: .openFoodHome, sortOrder: 1)
        context.insert(routine)
        context.insert(first)
        context.insert(second)
        try context.save()

        let run = CareRoutineService.startRun(
            routine: routine,
            activeRuns: [],
            context: context,
            caregiverName: "Caregiver A"
        )
        CareRoutineService.completeStep(
            first,
            in: run,
            routine: routine,
            allSteps: [first, second],
            context: context,
            caregiverName: "Caregiver A"
        )
        XCTAssertEqual(run.state, .active)

        CareRoutineService.skipStep(
            second,
            in: run,
            routine: routine,
            allSteps: [first, second],
            context: context,
            caregiverName: "Caregiver B"
        )
        XCTAssertEqual(run.state, .completed)
        XCTAssertEqual(run.startedByCaregiverName, "Caregiver A")
        XCTAssertEqual(run.completedByCaregiverName, "Caregiver B")
        XCTAssertEqual(run.completedStepIDs, [first.id])
        XCTAssertEqual(run.skippedStepIDs, [second.id])
        XCTAssertEqual(run.resolutionRecord(for: first.id)?.caregiverName, "Caregiver A")
        XCTAssertEqual(run.resolutionRecord(for: first.id)?.resolution, .completed)
        XCTAssertEqual(run.resolutionRecord(for: second.id)?.caregiverName, "Caregiver B")
        XCTAssertEqual(run.resolutionRecord(for: second.id)?.resolution, .skipped)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareEvent>()).count, 0)
    }

    @MainActor
    func testCareRoutineStartRunReusesActiveRunButStartsAfterCancel() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let routine = CareRoutine(scope: .household, householdID: UUID(), title: "Evening reset")
        context.insert(routine)
        try context.save()

        let firstRun = CareRoutineService.startRun(routine: routine, activeRuns: [], context: context)
        let reusedRun = CareRoutineService.startRun(routine: routine, activeRuns: [firstRun], context: context)
        XCTAssertEqual(reusedRun.id, firstRun.id)

        CareRoutineService.cancelRun(firstRun, context: context)
        XCTAssertNil(CareRoutineService.activeRun(for: routine, runs: [firstRun]))

        let secondRun = CareRoutineService.startRun(routine: routine, activeRuns: [firstRun], context: context)
        XCTAssertNotEqual(secondRun.id, firstRun.id)
        XCTAssertEqual(secondRun.state, .active)
    }

    @MainActor
    func testCareRoutineStepResolutionTracksLatestCaregiver() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let routine = CareRoutine(scope: .household, householdID: UUID(), title: "Pack bag")
        let step = CareRoutineStep(routineID: routine.id, title: "Pack water", sortOrder: 0)
        context.insert(routine)
        context.insert(step)
        try context.save()

        let run = CareRoutineService.startRun(
            routine: routine,
            activeRuns: [],
            context: context,
            caregiverName: "Caregiver A"
        )
        CareRoutineService.skipStep(
            step,
            in: run,
            routine: routine,
            allSteps: [step],
            context: context,
            caregiverName: "Caregiver B"
        )
        CareRoutineService.completeStep(
            step,
            in: run,
            routine: routine,
            allSteps: [step],
            context: context,
            caregiverName: "Caregiver A"
        )

        XCTAssertEqual(run.completedStepIDs, [step.id])
        XCTAssertTrue(run.skippedStepIDs.isEmpty)
        let record = try XCTUnwrap(run.resolutionRecord(for: step.id))
        XCTAssertEqual(record.resolution, .completed)
        XCTAssertEqual(record.caregiverName, "Caregiver A")
        XCTAssertEqual(run.stepResolutionRecords.count, 1)
    }

    @MainActor
    func testCustomCareRoutineCreatesActionConfiguredSteps() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profile = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        context.insert(profile)

        let routine = try XCTUnwrap(CareRoutineService.createRoutine(
            title: "Custom evening",
            notes: "A custom care pass.",
            scope: .profile,
            iconName: "moon.stars.fill",
            tintName: "pink",
            steps: [
                CareRoutineStepInput(title: "Log bath", action: .logEvent, eventType: .activity, activityType: .bath),
                CareRoutineStepInput(title: "Start night sleep", action: .startTimer, eventType: .sleep, sleepKind: .nightSleep),
                CareRoutineStepInput(title: "Open light", action: .openNightLight)
            ],
            profileID: profile.id,
            profileType: profile.profileType,
            householdID: nil,
            existingRoutines: [],
            context: context
        ))

        let steps = try context.fetch(FetchDescriptor<CareRoutineStep>())
            .filter { $0.routineID == routine.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(routine.title, "Custom evening")
        XCTAssertEqual(routine.profileType, .child)
        XCTAssertEqual(routine.iconName, "moon.stars.fill")
        XCTAssertEqual(steps.map(\.action), [.logEvent, .startTimer, .openNightLight])
        XCTAssertEqual(steps[0].eventType, .activity)
        XCTAssertEqual(steps[0].activityType, .bath)
        XCTAssertEqual(steps[1].eventType, .sleep)
        XCTAssertEqual(steps[1].sleepKind, .nightSleep)
        XCTAssertNil(steps[2].eventType)
    }

    @MainActor
    func testAdultRoutineNormalizesChildOnlyActivitySubtype() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profile = CareProfile(profileType: .adult, name: "Test Adult")
        context.insert(profile)

        let routine = try XCTUnwrap(CareRoutineService.createRoutine(
            title: "Movement",
            scope: .profile,
            steps: [
                CareRoutineStepInput(
                    title: "Start movement",
                    action: .startTimer,
                    eventType: .activity,
                    activityType: .tummyTime
                )
            ],
            profileID: profile.id,
            profileType: .adult,
            householdID: nil,
            existingRoutines: [],
            context: context
        ))

        let step = try XCTUnwrap(
            context.fetch(FetchDescriptor<CareRoutineStep>())
                .first { $0.routineID == routine.id }
        )
        XCTAssertEqual(step.activityType, .exercise)
    }

    @MainActor
    func testCustomCareRoutineRejectsBlankTitleAndBlankSteps() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profileID = UUID()

        let missingTitle = CareRoutineService.createRoutine(
            title: "   ",
            scope: .profile,
            steps: [CareRoutineStepInput(title: "Check bag", action: .checklist)],
            profileID: profileID,
            profileType: .child,
            householdID: nil,
            existingRoutines: [],
            context: context
        )
        let missingSteps = CareRoutineService.createRoutine(
            title: "Morning",
            scope: .profile,
            steps: [CareRoutineStepInput(title: "   ", action: .checklist)],
            profileID: profileID,
            profileType: .child,
            householdID: nil,
            existingRoutines: [],
            context: context
        )

        XCTAssertNil(missingTitle)
        XCTAssertNil(missingSteps)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareRoutine>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareRoutineStep>()).count, 0)
    }

    @MainActor
    func testUpdatingCustomCareRoutinePreservesReorderedStepsAndReminder() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profile = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        let household = Household(name: "Home")
        context.insert(profile)
        context.insert(household)

        let routine = try XCTUnwrap(CareRoutineService.createRoutine(
            title: "Evening",
            scope: .profile,
            steps: [
                CareRoutineStepInput(title: "Brush teeth", action: .checklist),
                CareRoutineStepInput(title: "Start sleep", action: .startTimer, eventType: .sleep, sleepKind: .nap)
            ],
            profileID: profile.id,
            profileType: profile.profileType,
            householdID: nil,
            existingRoutines: [],
            context: context
        ))
        let originalSteps = try context.fetch(FetchDescriptor<CareRoutineStep>())
            .filter { $0.routineID == routine.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        let preservedID = try XCTUnwrap(originalSteps.last?.id)

        var edited = CareRoutineInput(routine: routine, steps: originalSteps)
        edited.title = "Household evening"
        edited.scope = .household
        edited.reminderEnabled = true
        edited.reminderTimeMinutesAfterMidnight = 19 * 60 + 15
        edited.steps = [
            CareRoutineStepInput(step: originalSteps[1]),
            CareRoutineStepInput(title: "Open shopping", action: .openShoppingList)
        ]

        XCTAssertTrue(CareRoutineService.updateRoutine(
            routine,
            input: edited,
            profileID: profile.id,
            profileType: profile.profileType,
            householdID: household.id,
            existingSteps: originalSteps,
            context: context
        ))

        let updatedSteps = try context.fetch(FetchDescriptor<CareRoutineStep>())
            .filter { $0.routineID == routine.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(routine.title, "Household evening")
        XCTAssertEqual(routine.scope, .household)
        XCTAssertEqual(routine.profileType, .child)
        XCTAssertNil(routine.profileID)
        XCTAssertEqual(routine.householdID, household.id)
        XCTAssertTrue(routine.reminderEnabled)
        XCTAssertEqual(routine.reminderTimeMinutesAfterMidnight, 19 * 60 + 15)
        XCTAssertEqual(updatedSteps.map(\.title), ["Start sleep", "Open shopping"])
        XCTAssertEqual(updatedSteps.first?.id, preservedID)
        XCTAssertEqual(updatedSteps.first?.sleepKind, .nap)
        XCTAssertEqual(updatedSteps.last?.action, .openShoppingList)
    }

    @MainActor
    func testCareRoutineDuplicateCopiesStepsWithoutReminder() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profile = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        context.insert(profile)

        let routine = try XCTUnwrap(CareRoutineService.createRoutine(
            title: "Morning",
            scope: .profile,
            reminderEnabled: true,
            reminderTimeMinutesAfterMidnight: 8 * 60,
            steps: [
                CareRoutineStepInput(title: "Log feed", action: .logEvent, eventType: .feed),
                CareRoutineStepInput(title: "Open guide", action: .openAgeGuide)
            ],
            profileID: profile.id,
            profileType: profile.profileType,
            householdID: nil,
            existingRoutines: [],
            context: context
        ))
        let steps = try context.fetch(FetchDescriptor<CareRoutineStep>())
        let copy = CareRoutineService.duplicateRoutine(
            routine,
            steps: steps,
            existingRoutines: [routine],
            context: context
        )

        let copiedSteps = try context.fetch(FetchDescriptor<CareRoutineStep>())
            .filter { $0.routineID == copy.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(copy.title, "Morning Copy")
        XCTAssertEqual(copy.profileType, .child)
        XCTAssertEqual(copy.profileID, profile.id)
        XCTAssertFalse(copy.reminderEnabled)
        XCTAssertNil(copy.reminderTimeMinutesAfterMidnight)
        XCTAssertEqual(copiedSteps.map(\.title), ["Log feed", "Open guide"])
        XCTAssertEqual(copiedSteps.first?.eventType, .feed)
        XCTAssertEqual(copiedSteps.last?.action, .openAgeGuide)
    }

    @MainActor
    func testCareRoutineReorderUpdatesSortOrder() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let first = CareRoutine(scope: .household, householdID: UUID(), title: "First", sortOrder: 0)
        let second = CareRoutine(scope: .household, householdID: UUID(), title: "Second", sortOrder: 1)
        let third = CareRoutine(scope: .household, householdID: UUID(), title: "Third", sortOrder: 2)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        CareRoutineService.reorderRoutines(
            [first, second, third],
            from: IndexSet(integer: 0),
            to: 3,
            context: context
        )

        XCTAssertEqual(second.sortOrder, 0)
        XCTAssertEqual(third.sortOrder, 1)
        XCTAssertEqual(first.sortOrder, 2)
    }

    @MainActor
    func testCareRoutinesRoundTripThroughBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profile = CareProfile(profileType: .dog, name: "Test Dog", birthDate: Date(), sex: .unknown)
        let household = Household(name: "Home")
        context.insert(profile)
        context.insert(household)
        let template = try XCTUnwrap(
            CareRoutineService.templates(for: .dog).first { $0.kind == .dogEvening }
        )
        let routine = CareRoutineService.createRoutine(
            from: template,
            profileID: profile.id,
            profileType: .dog,
            householdID: household.id,
            existingRoutines: [],
            context: context
        )
        let run = CareRoutineService.startRun(
            routine: routine,
            activeRuns: [],
            context: context,
            caregiverName: "Caregiver A"
        )
        let routineSteps = try context.fetch(FetchDescriptor<CareRoutineStep>())
            .filter { $0.routineID == routine.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        if let firstStep = routineSteps.first {
            CareRoutineService.completeStep(
                firstStep,
                in: run,
                routine: routine,
                allSteps: routineSteps,
                context: context,
                caregiverName: "Caregiver A"
            )
        }
        let backup = try DataExportImportService.exportData(context: context)

        try DataExportImportService.importData(backup, context: context)

        let routines = try context.fetch(FetchDescriptor<CareRoutine>())
        let steps = try context.fetch(FetchDescriptor<CareRoutineStep>())
        let runs = try context.fetch(FetchDescriptor<CareRoutineRun>())
        XCTAssertEqual(routines.map(\.id), [routine.id])
        XCTAssertEqual(routines.first?.profileType, .dog)
        XCTAssertEqual(routines.first?.profileID, profile.id)
        XCTAssertEqual(steps.filter { $0.routineID == routine.id }.count, template.steps.count)
        XCTAssertEqual(runs.map(\.id), [run.id])
        XCTAssertEqual(runs.first?.startedByCaregiverName, "Caregiver A")
        XCTAssertEqual(runs.first?.resolutionRecord(for: routineSteps[0].id)?.caregiverName, "Caregiver A")
    }

    @MainActor
    func testTripPackingSuggestionsScaleForDurationLaundryAndTravelerType() throws {
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_900_000_000))
        let endDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: startDate))
        let householdID = UUID()
        let tripID = UUID()
        let trip = PackingTrip(
            id: tripID,
            householdID: householdID,
            title: "Sample Trip",
            startDate: startDate,
            endDate: endDate,
            travelMode: .plane,
            laundryAvailable: true,
            activities: [.swimming]
        )
        let adult = TripTraveler(
            householdID: householdID,
            tripID: tripID,
            kind: .adult,
            displayName: "Adult Traveler"
        )
        let child = TripTraveler(
            householdID: householdID,
            tripID: tripID,
            kind: .child,
            profileID: UUID(),
            displayName: "Sample Child"
        )
        let dog = TripTraveler(
            householdID: householdID,
            tripID: tripID,
            kind: .dog,
            profileID: UUID(),
            displayName: "Sample Dog"
        )

        let suggestions = TripPackingSuggestionEngine.suggestions(
            for: trip,
            travelers: [adult, child, dog]
        )

        XCTAssertEqual(trip.dayCount, 7)
        XCTAssertEqual(
            suggestions.first { $0.templateKey == "adult.tops" }?.quantity,
            4
        )
        XCTAssertEqual(
            suggestions.first { $0.templateKey == "child.diapers" }?.quantity,
            49
        )
        XCTAssertEqual(
            suggestions.first { $0.templateKey == "dog.food" }?.quantity,
            7
        )
        XCTAssertNotNil(suggestions.first { $0.templateKey == "plane.carry-on-change" })
        XCTAssertNotNil(suggestions.first { $0.templateKey == "child.swim" })
    }

    @MainActor
    func testExpandedTripActivitiesProvidePackingSuggestions() throws {
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_900_000_000))
        let endDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: startDate))
        let householdID = UUID()
        let tripID = UUID()
        let trip = PackingTrip(
            id: tripID,
            householdID: householdID,
            title: "Sample Trip",
            startDate: startDate,
            endDate: endDate
        )
        let adult = TripTraveler(
            householdID: householdID,
            tripID: tripID,
            kind: .adult,
            displayName: "Adult Traveler"
        )
        let expectedSuggestionByActivity: [PackingTripActivity: String] = [
            .sightseeing: "activity.day-bag",
            .hiking: "activity.hiking-essentials",
            .camping: "activity.camping-sleep",
            .boating: "activity.dry-bag",
            .waterSports: "activity.towels",
            .cycling: "activity.cycling-safety",
            .fitness: "adult.workout-outfit",
            .snowSports: "activity.snow-safety",
            .themeParks: "activity.day-bag",
            .business: "activity.work-materials"
        ]

        XCTAssertEqual(PackingTripActivity.allCases.count, 15)
        XCTAssertTrue(PackingTripActivity.allCases.allSatisfy {
            !$0.displayName.isEmpty && !$0.systemImage.isEmpty
        })

        for (activity, expectedKey) in expectedSuggestionByActivity {
            trip.activities = [activity]
            let suggestions = TripPackingSuggestionEngine.suggestions(
                for: trip,
                travelers: [adult]
            )
            XCTAssertNotNil(
                suggestions.first { $0.templateKey == expectedKey },
                "Expected \(activity.displayName) to add \(expectedKey)."
            )
        }
    }

    @MainActor
    func testTripPackingCreationStateAttributionAndDuplicate() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let householdID = UUID()
        let profileID = UUID()
        let startDate = Date(timeIntervalSince1970: 1_900_000_000)
        let endDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: startDate))
        let input = PackingTripInput(
            title: "Sample Trip",
            destination: TripDestinationSelection(name: "Sample Destination"),
            startDate: startDate,
            endDate: endDate,
            travelMode: .car,
            lodgingType: .home,
            laundryAvailable: false,
            activities: [.outdoors],
            travelers: [
                TripTravelerInput(kind: .adult, profileID: nil, displayName: "Adult Traveler"),
                TripTravelerInput(kind: .child, profileID: profileID, displayName: "Sample Child")
            ],
            includeStarterList: true,
            weatherSuggestionsEnabled: true,
            reminderDate: nil,
            finalCheckDate: nil,
            notes: ""
        )

        let trip = try XCTUnwrap(TripPackingService.createTrip(
            input: input,
            householdID: householdID,
            existingTrips: [],
            context: context,
            caregiverName: "Caregiver A",
            now: startDate
        ))
        let travelers = try context.fetch(FetchDescriptor<TripTraveler>())
        let bags = try context.fetch(FetchDescriptor<PackingBag>())
        let items = try context.fetch(FetchDescriptor<PackingItem>())

        XCTAssertEqual(travelers.count, 2)
        XCTAssertEqual(travelers.first { $0.kind == .child }?.profileID, profileID)
        XCTAssertEqual(bags.map(\.name), ["Shared Bag"])
        XCTAssertFalse(items.isEmpty)

        let firstItem = try XCTUnwrap(items.first)
        XCTAssertTrue(TripPackingService.updateItem(
            firstItem,
            title: firstItem.title,
            category: firstItem.category,
            travelerID: firstItem.travelerID,
            bagID: firstItem.bagID,
            quantity: firstItem.quantity,
            unit: firstItem.unit ?? "",
            notes: firstItem.notes ?? "",
            priority: firstItem.priority,
            needsPurchase: firstItem.needsPurchase,
            assignedCaregiverName: "  Caregiver A  ",
            caregiverReminderEnabled: false,
            trip: trip,
            context: context,
            now: startDate.addingTimeInterval(30)
        ))
        XCTAssertEqual(firstItem.assignedCaregiverName, "Caregiver A")
        XCTAssertFalse(firstItem.caregiverReminderEnabled)
        let packedAt = startDate.addingTimeInterval(60)
        TripPackingService.setState(
            firstItem,
            state: .packed,
            trip: trip,
            context: context,
            caregiverName: "Caregiver B",
            now: packedAt
        )
        XCTAssertEqual(firstItem.state, .packed)
        XCTAssertEqual(firstItem.packedBy, "Caregiver B")
        XCTAssertEqual(firstItem.packedAt, packedAt)

        let duplicate = try XCTUnwrap(TripPackingService.duplicateTrip(
            trip,
            travelers: travelers,
            bags: bags,
            items: items,
            existingTrips: [trip],
            context: context,
            now: startDate.addingTimeInterval(120)
        ))
        let copiedItems = try context.fetch(FetchDescriptor<PackingItem>())
            .filter { $0.tripID == duplicate.id }

        XCTAssertEqual(duplicate.title, "Sample Trip Copy")
        XCTAssertEqual(duplicate.destinationStops.count, 1)
        XCTAssertNotEqual(duplicate.destinationStops.first?.id, trip.destinationStops.first?.id)
        XCTAssertEqual(copiedItems.count, items.count)
        XCTAssertTrue(copiedItems.allSatisfy { $0.state == .needed })
        XCTAssertTrue(copiedItems.allSatisfy { $0.packedBy == nil })
        let copiedAssignedItem = try XCTUnwrap(copiedItems.first {
            $0.sortOrder == firstItem.sortOrder
        })
        XCTAssertEqual(copiedAssignedItem.assignedCaregiverName, "Caregiver A")
        XCTAssertFalse(copiedAssignedItem.caregiverReminderEnabled)

        TripPackingService.archive(trip, context: context, now: startDate.addingTimeInterval(180))
        XCTAssertTrue(trip.isArchived)
        XCTAssertEqual(trip.status, .archived)

        let archivedItemTitle = firstItem.title
        XCTAssertFalse(TripPackingService.setState(
            firstItem,
            state: .needed,
            trip: trip,
            context: context,
            now: startDate.addingTimeInterval(190)
        ))
        XCTAssertEqual(firstItem.state, .packed)
        XCTAssertFalse(TripPackingService.updateItem(
            firstItem,
            title: "Changed Archived Item",
            category: firstItem.category,
            travelerID: firstItem.travelerID,
            bagID: firstItem.bagID,
            quantity: firstItem.quantity,
            unit: firstItem.unit ?? "",
            notes: firstItem.notes ?? "",
            priority: firstItem.priority,
            needsPurchase: firstItem.needsPurchase,
            assignedCaregiverName: firstItem.assignedCaregiverName,
            caregiverReminderEnabled: firstItem.caregiverReminderEnabled,
            trip: trip,
            context: context,
            now: startDate.addingTimeInterval(200)
        ))
        XCTAssertEqual(firstItem.title, archivedItemTitle)
        XCTAssertNil(TripPackingService.addItem(
            to: trip,
            title: "New Archived Item",
            category: .clothing,
            travelerID: nil,
            existingItems: items,
            context: context,
            now: startDate.addingTimeInterval(210)
        ))
        XCTAssertNil(TripPackingService.addBag(
            to: trip,
            name: "Archived Bag",
            travelerID: nil,
            existingBags: bags,
            context: context,
            now: startDate.addingTimeInterval(220)
        ))
        XCTAssertFalse(TripPackingService.deleteItem(
            firstItem,
            trip: trip,
            context: context,
            now: startDate.addingTimeInterval(230)
        ))
        XCTAssertFalse(TripPackingService.setCompleted(
            trip,
            completed: true,
            context: context,
            now: startDate.addingTimeInterval(235)
        ))
        XCTAssertEqual(trip.status, .archived)

        TripPackingService.restore(trip, context: context, now: startDate.addingTimeInterval(240))
        XCTAssertFalse(trip.isArchived)
        XCTAssertEqual(trip.status, .upcoming)
        XCTAssertTrue(TripPackingService.setState(
            firstItem,
            state: .needed,
            trip: trip,
            context: context,
            now: startDate.addingTimeInterval(250)
        ))
        XCTAssertEqual(firstItem.state, .needed)
    }

    @MainActor
    func testTripPackingDeleteRemovesTripScopedRecordsAndPreservesShoppingItems() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let householdID = UUID()
        let trip = PackingTrip(
            householdID: householdID,
            title: "Sample Trip",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_086_400)
        )
        let traveler = TripTraveler(
            householdID: householdID,
            tripID: trip.id,
            kind: .adult,
            displayName: "Adult Traveler"
        )
        let bag = PackingBag(
            householdID: householdID,
            tripID: trip.id,
            travelerID: traveler.id,
            name: "Carry On"
        )
        let shoppingList = ShoppingList(
            householdID: householdID,
            name: "Trip Shopping"
        )
        let shoppingItem = ShoppingListItem(
            householdID: householdID,
            shoppingListID: shoppingList.id,
            name: "Sample Item"
        )
        let packingItem = PackingItem(
            householdID: householdID,
            tripID: trip.id,
            travelerID: traveler.id,
            bagID: bag.id,
            title: "Sample Item",
            relatedShoppingItemID: shoppingItem.id
        )
        let choiceGroup = TripItineraryChoiceGroup(
            householdID: householdID,
            tripID: trip.id,
            title: "Sample options",
            scheduledDay: trip.startDate
        )
        let itineraryItem = TripItineraryItem(
            householdID: householdID,
            tripID: trip.id,
            choiceGroupID: choiceGroup.id,
            title: "Sample activity",
            scheduleKind: .anytime,
            scheduledDay: trip.startDate
        )
        let itineraryLink = TripItineraryLink(
            householdID: householdID,
            tripID: trip.id,
            itineraryItemID: itineraryItem.id,
            title: "Details",
            urlString: "https://example.com/details"
        )
        context.insert(trip)
        context.insert(traveler)
        context.insert(bag)
        context.insert(packingItem)
        context.insert(shoppingList)
        context.insert(shoppingItem)
        context.insert(choiceGroup)
        context.insert(itineraryItem)
        context.insert(itineraryLink)
        try context.save()

        XCTAssertTrue(TripPackingService.deleteTrip(trip, context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<PackingTrip>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TripTraveler>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PackingBag>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PackingItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TripItineraryChoiceGroup>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TripItineraryItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TripItineraryLink>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoppingList>()).map(\.id), [shoppingList.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoppingListItem>()).map(\.id), [shoppingItem.id])
    }

    @MainActor
    func testTripPackingRoundTripsThroughBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let householdID = UUID()
        let household = Household(id: householdID, name: "Test Home")
        let profile = CareProfile(
            profileType: .dog,
            name: "Sample Dog",
            birthDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let trip = PackingTrip(
            householdID: householdID,
            title: "Sample Trip",
            destinationName: "Sample Destination",
            destinationDetail: "Sample Region",
            destinationLatitude: 43.6532,
            destinationLongitude: -79.3832,
            destinationTimeZoneIdentifier: "America/Toronto",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_086_400),
            timeZoneIdentifier: "America/Los_Angeles",
            travelMode: .train,
            activities: [.outdoors]
        )
        trip.destinationStops = [
            TripDestinationStop(
                destination: TripDestinationSelection(
                    name: "Sample Destination",
                    detail: "Sample Region",
                    latitude: 43.6532,
                    longitude: -79.3832,
                    timeZoneIdentifier: "America/Toronto"
                ),
                startDate: trip.startDate
            ),
            TripDestinationStop(
                destination: TripDestinationSelection(
                    name: "Second Destination",
                    latitude: 42.9849,
                    longitude: -81.2453,
                    timeZoneIdentifier: "America/Toronto"
                ),
                startDate: trip.endDate
            )
        ]
        let traveler = TripTraveler(
            householdID: householdID,
            tripID: trip.id,
            kind: .dog,
            profileID: profile.id,
            displayName: "Sample Dog"
        )
        let bag = PackingBag(
            householdID: householdID,
            tripID: trip.id,
            travelerID: traveler.id,
            name: "Dog Bag"
        )
        let item = PackingItem(
            householdID: householdID,
            tripID: trip.id,
            travelerID: traveler.id,
            bagID: bag.id,
            title: "Leash",
            category: .dogCare,
            quantity: 1,
            priority: .essential,
            state: .packed,
            assignedCaregiverName: "Caregiver A",
            caregiverReminderEnabled: false,
            packedBy: "Caregiver A"
        )
        context.insert(household)
        context.insert(profile)
        context.insert(trip)
        context.insert(traveler)
        context.insert(bag)
        context.insert(item)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let restoredTrips = try context.fetch(FetchDescriptor<PackingTrip>())
        let restoredTravelers = try context.fetch(FetchDescriptor<TripTraveler>())
        let restoredBags = try context.fetch(FetchDescriptor<PackingBag>())
        let restoredItems = try context.fetch(FetchDescriptor<PackingItem>())
        XCTAssertEqual(restoredTrips.map(\.id), [trip.id])
        XCTAssertEqual(restoredTrips.first?.destinationDetail, "Sample Region")
        XCTAssertEqual(restoredTrips.first?.destinationLatitude, 43.6532)
        XCTAssertEqual(restoredTrips.first?.destinationLongitude, -79.3832)
        XCTAssertEqual(restoredTrips.first?.destinationTimeZoneIdentifier, "America/Toronto")
        XCTAssertEqual(restoredTrips.first?.destinationStops.count, 2)
        XCTAssertEqual(restoredTrips.first?.destinationStops.last?.destination.name, "Second Destination")
        XCTAssertEqual(restoredTrips.first?.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(restoredTravelers.first?.profileID, traveler.profileID)
        XCTAssertEqual(restoredBags.first?.travelerID, traveler.id)
        XCTAssertEqual(restoredItems.first?.bagID, bag.id)
        XCTAssertEqual(restoredItems.first?.state, .packed)
        XCTAssertEqual(restoredItems.first?.assignedCaregiverName, "Caregiver A")
        XCTAssertEqual(restoredItems.first?.caregiverReminderEnabled, false)
        XCTAssertEqual(restoredItems.first?.packedBy, "Caregiver A")
    }

    @MainActor
    func testTripDatesRemainDateOnlyInSavedTimeZone() throws {
        let start = tripDate(2026, 7, 10, timeZoneIdentifier: "Pacific/Kiritimati")
        let end = tripDate(2026, 7, 12, timeZoneIdentifier: "Pacific/Kiritimati")
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            startDate: start,
            endDate: end,
            timeZoneIdentifier: "Pacific/Kiritimati"
        )

        XCTAssertEqual(trip.dayCount, 3)
        XCTAssertEqual(
            trip.formattedDate(start, locale: Locale(identifier: "en_US_POSIX")),
            "Jul 10, 2026"
        )
        XCTAssertFalse(trip.isSingleDay)
    }

    @MainActor
    func testTripDestinationsCreateSequentialWeatherWindows() throws {
        let start = tripDate(2026, 7, 1, timeZoneIdentifier: "America/Los_Angeles")
        let secondStart = tripDate(2026, 7, 8, timeZoneIdentifier: "America/Los_Angeles")
        let end = tripDate(2026, 7, 14, timeZoneIdentifier: "America/Los_Angeles")
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            destinationStops: [
                TripDestinationStop(
                    destination: TripDestinationSelection(
                        name: "First Destination",
                        latitude: 42.3601,
                        longitude: -71.0589,
                        timeZoneIdentifier: "America/New_York"
                    ),
                    startDate: start
                ),
                TripDestinationStop(
                    destination: TripDestinationSelection(
                        name: "Second Destination",
                        latitude: 43.6532,
                        longitude: -79.3832,
                        timeZoneIdentifier: "America/Toronto"
                    ),
                    startDate: secondStart
                )
            ],
            startDate: start,
            endDate: end,
            timeZoneIdentifier: "America/Los_Angeles"
        )

        let windows = trip.destinationWeatherWindows
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.map(\.destination.name), ["First Destination", "Second Destination"])
        XCTAssertEqual(
            TripDayKey(date: windows[0].startDate, timeZone: trip.tripTimeZone).description,
            "2026-07-01"
        )
        XCTAssertEqual(
            TripDayKey(date: windows[0].endDate, timeZone: trip.tripTimeZone).description,
            "2026-07-07"
        )
        XCTAssertEqual(
            TripDayKey(date: windows[1].startDate, timeZone: trip.tripTimeZone).description,
            "2026-07-08"
        )
        XCTAssertEqual(
            TripDayKey(date: windows[1].endDate, timeZone: trip.tripTimeZone).description,
            "2026-07-14"
        )
        XCTAssertEqual(trip.destinationSummary, "First Destination + 1 more")
        XCTAssertTrue(TripPackingService.destinationStopsAreValid(
            trip.destinationStops,
            tripStartDate: trip.startDate,
            tripEndDate: trip.endDate,
            timeZoneIdentifier: trip.timeZoneIdentifier
        ))
    }

    @MainActor
    func testTripWeatherFiltersDestinationDaysAndLocalizesUnits() throws {
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            destinationName: "Sample Destination",
            destinationLatitude: 35.6762,
            destinationLongitude: 139.6503,
            destinationTimeZoneIdentifier: "Asia/Tokyo",
            startDate: tripDate(2026, 7, 10, timeZoneIdentifier: "America/Los_Angeles"),
            endDate: tripDate(2026, 7, 12, timeZoneIdentifier: "America/Los_Angeles"),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let query = try XCTUnwrap(TripWeatherQuery(trip: trip))
        let attribution = TripWeatherAttribution(
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal")),
            lightMarkURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            darkMarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalAttributionText: "Sample weather source attribution."
        )
        let days = [
            TripDailyWeather(date: tripDate(2026, 7, 9, timeZoneIdentifier: "Asia/Tokyo"), lowTemperatureCelsius: -20, highTemperatureCelsius: -10, precipitationChance: 1, uvIndex: 10),
            TripDailyWeather(date: tripDate(2026, 7, 10, timeZoneIdentifier: "Asia/Tokyo"), lowTemperatureCelsius: 5, highTemperatureCelsius: 20, precipitationChance: 0.1, uvIndex: 2),
            TripDailyWeather(date: tripDate(2026, 7, 11, timeZoneIdentifier: "Asia/Tokyo"), lowTemperatureCelsius: 8, highTemperatureCelsius: 30, precipitationChance: 0.6, uvIndex: 7),
            TripDailyWeather(date: tripDate(2026, 7, 12, timeZoneIdentifier: "Asia/Tokyo"), lowTemperatureCelsius: 10, highTemperatureCelsius: 25, precipitationChance: 0.1, uvIndex: 3),
            TripDailyWeather(date: tripDate(2026, 7, 13, timeZoneIdentifier: "Asia/Tokyo"), lowTemperatureCelsius: -20, highTemperatureCelsius: 50, precipitationChance: 1, uvIndex: 10)
        ]
        let fetchedAt = Date(timeIntervalSince1970: 1_900_000_000)

        let snapshot = try XCTUnwrap(TripWeatherService.makeSnapshot(
            query: query,
            days: days,
            attribution: attribution,
            locale: Locale(identifier: "en_US"),
            fetchedAt: fetchedAt
        ))

        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.lowTemperatureCelsius, 5)
        XCTAssertEqual(snapshot.highTemperatureCelsius, 30)
        XCTAssertTrue(snapshot.rainLikely)
        XCTAssertTrue(snapshot.coldWeather)
        XCTAssertTrue(snapshot.hotOrHighUV)
        XCTAssertTrue(snapshot.summary.contains("41–86°F"))
        XCTAssertEqual(snapshot.forecastDayCount, 3)
        XCTAssertEqual(snapshot.tripDayCount, 3)
        XCTAssertEqual(snapshot.dailyForecast.count, 3)
        XCTAssertEqual(snapshot.dailyForecast.map(\.date), Array(days[1...3]).map(\.date))
        XCTAssertEqual(snapshot.legalAttributionText, "Sample weather source attribution.")
        XCTAssertFalse(snapshot.hasPartialCoverage)
        XCTAssertEqual(snapshot.coverageSummary, "Forecast covers all 3 trip days.")
    }

    @MainActor
    func testTripWeatherDisclosesPartialForecastCoverage() throws {
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            destinationName: "Sample Destination",
            destinationLatitude: 43.6532,
            destinationLongitude: -79.3832,
            destinationTimeZoneIdentifier: "America/Toronto",
            startDate: tripDate(2026, 7, 10, timeZoneIdentifier: "America/Los_Angeles"),
            endDate: tripDate(2026, 7, 14, timeZoneIdentifier: "America/Los_Angeles"),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let query = try XCTUnwrap(TripWeatherQuery(trip: trip))
        let attribution = TripWeatherAttribution(
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal")),
            lightMarkURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            darkMarkURL: try XCTUnwrap(URL(string: "https://example.com/dark"))
        )
        let days = [
            TripDailyWeather(date: tripDate(2026, 7, 10, timeZoneIdentifier: "America/Toronto"), lowTemperatureCelsius: 15, highTemperatureCelsius: 24, precipitationChance: 0.1, uvIndex: 3),
            TripDailyWeather(date: tripDate(2026, 7, 11, timeZoneIdentifier: "America/Toronto"), lowTemperatureCelsius: 16, highTemperatureCelsius: 25, precipitationChance: 0.2, uvIndex: 4)
        ]

        let snapshot = try XCTUnwrap(TripWeatherService.makeSnapshot(
            query: query,
            days: days,
            attribution: attribution,
            locale: Locale(identifier: "en_US")
        ))

        XCTAssertEqual(snapshot.forecastDayCount, 2)
        XCTAssertEqual(snapshot.tripDayCount, 5)
        XCTAssertTrue(snapshot.hasPartialCoverage)
        XCTAssertEqual(
            snapshot.coverageSummary,
            "Forecast available for 2 of 5 trip days. Suggestions use only the available days."
        )
    }

    @MainActor
    func testTripDestinationForecastAppearsAsDatesApproach() async throws {
        let start = tripDate(2026, 7, 1, timeZoneIdentifier: "America/Los_Angeles")
        let secondStart = tripDate(2026, 7, 8, timeZoneIdentifier: "America/Los_Angeles")
        let end = tripDate(2026, 7, 14, timeZoneIdentifier: "America/Los_Angeles")
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            destinationStops: [
                TripDestinationStop(
                    destination: TripDestinationSelection(
                        name: "First Destination",
                        latitude: 42.3601,
                        longitude: -71.0589,
                        timeZoneIdentifier: "America/New_York"
                    ),
                    startDate: start
                ),
                TripDestinationStop(
                    destination: TripDestinationSelection(
                        name: "Second Destination",
                        latitude: 43.6532,
                        longitude: -79.3832,
                        timeZoneIdentifier: "America/Toronto"
                    ),
                    startDate: secondStart
                )
            ],
            startDate: start,
            endDate: end,
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let firstWeek = (1...7).map { day in
            TripDailyWeather(
                date: tripDate(2026, 7, day, timeZoneIdentifier: "America/New_York"),
                lowTemperatureCelsius: 16,
                highTemperatureCelsius: 24,
                precipitationChance: 0.1,
                uvIndex: 4
            )
        }
        let secondWeek = (8...14).map { day in
            TripDailyWeather(
                date: tripDate(2026, 7, day, timeZoneIdentifier: "America/Toronto"),
                lowTemperatureCelsius: 17,
                highTemperatureCelsius: 26,
                precipitationChance: 0.2,
                uvIndex: 5
            )
        }
        let client = TestTripWeatherClient(days: firstWeek)
        let cache = TripWeatherSnapshotCache()

        let earlierForecasts = await TripWeatherService.forecasts(
            for: trip,
            client: client,
            cache: cache,
            now: tripDate(2026, 6, 30, timeZoneIdentifier: "America/Los_Angeles"),
            forceRefresh: true
        )
        XCTAssertEqual(earlierForecasts.count, 2)
        XCTAssertEqual(earlierForecasts[0].availability, .available)
        XCTAssertEqual(earlierForecasts[0].snapshot?.forecastDayCount, 7)
        XCTAssertEqual(earlierForecasts[1].availability, .notYetAvailable)
        XCTAssertNil(earlierForecasts[1].snapshot)

        await client.replaceDays(firstWeek + secondWeek)
        let closerForecasts = await TripWeatherService.forecasts(
            for: trip,
            client: client,
            cache: cache,
            now: tripDate(2026, 7, 6, timeZoneIdentifier: "America/Los_Angeles"),
            forceRefresh: true
        )
        XCTAssertEqual(closerForecasts.map(\.availability), [.available, .available])
        XCTAssertEqual(closerForecasts[1].snapshot?.forecastDayCount, 7)
    }

    @MainActor
    func testTripWeatherCacheAndForceRefresh() async throws {
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            destinationName: "Sample Destination",
            destinationLatitude: 35.6762,
            destinationLongitude: 139.6503,
            destinationTimeZoneIdentifier: "Asia/Tokyo",
            startDate: tripDate(2026, 7, 10, timeZoneIdentifier: "America/Los_Angeles"),
            endDate: tripDate(2026, 7, 10, timeZoneIdentifier: "America/Los_Angeles"),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let client = TestTripWeatherClient(days: [
            TripDailyWeather(
                date: tripDate(2026, 7, 10, timeZoneIdentifier: "Asia/Tokyo"),
                lowTemperatureCelsius: 10,
                highTemperatureCelsius: 20,
                precipitationChance: 0,
                uvIndex: 1
            )
        ])
        let cache = TripWeatherSnapshotCache()
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        let firstSnapshot = try await TripWeatherService.snapshot(
            for: trip,
            client: client,
            cache: cache,
            now: now
        )
        let cachedSnapshot = try await TripWeatherService.snapshot(
            for: trip,
            client: client,
            cache: cache,
            now: now.addingTimeInterval(60)
        )
        let cachedRequestCount = await client.forecastRequestCount()
        XCTAssertNotNil(firstSnapshot)
        XCTAssertNotNil(cachedSnapshot)
        XCTAssertEqual(firstSnapshot?.fetchedAt, now)
        XCTAssertEqual(cachedSnapshot?.fetchedAt, now)
        XCTAssertEqual(cachedRequestCount, 1)

        let refreshedSnapshot = try await TripWeatherService.snapshot(
            for: trip,
            client: client,
            cache: cache,
            now: now.addingTimeInterval(120),
            forceRefresh: true
        )
        let refreshedRequestCount = await client.forecastRequestCount()
        XCTAssertNotNil(refreshedSnapshot)
        XCTAssertEqual(refreshedSnapshot?.fetchedAt, now.addingTimeInterval(120))
        XCTAssertEqual(refreshedRequestCount, 2)
    }

    func testTripWeatherFailureReasonDistinguishesConfigurationConnectionAndService() {
        XCTAssertEqual(
            TripWeatherService.failureReason(for: NSError(
                domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors",
                code: 2
            )),
            .appConfiguration
        )
        XCTAssertEqual(
            TripWeatherService.failureReason(for: URLError(.notConnectedToInternet)),
            .connection
        )
        XCTAssertEqual(
            TripWeatherService.failureReason(for: NSError(
                domain: "WeatherKit",
                code: 999
            )),
            .serviceUnavailable
        )
    }

    func testColdLaunchStartsOnTodayWhileFoodNavigationCanRestoreInProcess() throws {
        let suiteName = "NavigationRestoration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tripID = UUID()

        FoodNavigationRestorationState(
            selectedSection: .trips,
            path: [.packingTrip(tripID)]
        ).save(defaults: defaults)

        XCTAssertEqual(AppNavigationLaunchPolicy.initialTab, .today)
        XCTAssertEqual(
            FoodNavigationRestorationState.load(defaults: defaults),
            FoodNavigationRestorationState(
                selectedSection: .trips,
                path: [.packingTrip(tripID)]
            )
        )
    }

    func testTripCaregiverNamesAreDeduplicatedAndSorted() {
        XCTAssertEqual(
            TripPackingService.uniqueCaregiverNames(from: [
                " Caregiver B ",
                "caregiver a",
                nil,
                "CAREGIVER A",
                "",
                "Caregiver C"
            ]),
            ["caregiver a", "Caregiver B", "Caregiver C"]
        )
    }

    @MainActor
    func testTripBagLifecycleQuantityAndShoppingHandoffIntegrity() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let householdID = UUID()
        let trip = PackingTrip(
            householdID: householdID,
            title: "Sample Trip",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let firstBag = PackingBag(householdID: householdID, tripID: trip.id, name: "Carry On")
        let secondBag = PackingBag(householdID: householdID, tripID: trip.id, name: "Checked Bag")
        let item = PackingItem(
            householdID: householdID,
            tripID: trip.id,
            bagID: secondBag.id,
            title: "Sample Item"
        )
        let shoppingList = ShoppingList(householdID: householdID, name: "Trip Shopping")
        context.insert(trip)
        context.insert(firstBag)
        context.insert(secondBag)
        context.insert(item)
        context.insert(shoppingList)
        try context.save()

        XCTAssertFalse(TripPackingService.updateBag(
            secondBag,
            name: "carry on",
            travelerID: nil,
            trip: trip,
            existingBags: [firstBag, secondBag],
            context: context
        ))
        XCTAssertNil(TripPackingService.addItem(
            to: trip,
            title: "Invalid Quantity",
            category: .other,
            travelerID: nil,
            quantity: 0,
            existingItems: [item],
            context: context
        ))

        let firstShoppingItem = try XCTUnwrap(TripPackingService.addToShoppingList(
            item,
            trip: trip,
            shoppingList: shoppingList,
            existingShoppingItems: [],
            context: context
        ))
        let repeatedShoppingItem = try XCTUnwrap(TripPackingService.addToShoppingList(
            item,
            trip: trip,
            shoppingList: shoppingList,
            existingShoppingItems: [firstShoppingItem],
            context: context
        ))
        XCTAssertEqual(repeatedShoppingItem.id, firstShoppingItem.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoppingListItem>()).count, 1)

        XCTAssertTrue(TripPackingService.deleteBag(
            secondBag,
            trip: trip,
            items: [item],
            context: context
        ))
        XCTAssertNil(item.bagID)
    }

    @MainActor
    func testTripPackingReordersOnlyVisibleItemsWithinTheirSection() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let householdID = UUID()
        let trip = PackingTrip(
            householdID: householdID,
            title: "Sample Trip",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_086_400)
        )
        let travelerID = UUID()
        let firstShared = PackingItem(
            householdID: householdID,
            tripID: trip.id,
            title: "First Shared",
            sortOrder: 0
        )
        let hiddenShared = PackingItem(
            householdID: householdID,
            tripID: trip.id,
            title: "Packed Shared",
            state: .packed,
            sortOrder: 1
        )
        let travelerItem = PackingItem(
            householdID: householdID,
            tripID: trip.id,
            travelerID: travelerID,
            title: "Traveler Item",
            sortOrder: 2
        )
        let secondShared = PackingItem(
            householdID: householdID,
            tripID: trip.id,
            title: "Second Shared",
            sortOrder: 3
        )
        let allItems = [firstShared, hiddenShared, travelerItem, secondShared]
        context.insert(trip)
        allItems.forEach(context.insert)
        try context.save()

        XCTAssertTrue(TripPackingService.reorderItems(
            [firstShared, secondShared],
            from: IndexSet(integer: 0),
            to: 2,
            trip: trip,
            allItems: allItems,
            context: context,
            now: Date(timeIntervalSince1970: 1_900_000_100)
        ))

        let reordered = try context.fetch(FetchDescriptor<PackingItem>())
            .filter { $0.tripID == trip.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(
            reordered.map(\.title),
            ["Second Shared", "Packed Shared", "Traveler Item", "First Shared"]
        )
        XCTAssertEqual(reordered.map(\.sortOrder), [0, 1, 2, 3])

        XCTAssertFalse(TripPackingService.reorderItems(
            [secondShared, travelerItem],
            from: IndexSet(integer: 0),
            to: 2,
            trip: trip,
            allItems: reordered,
            context: context
        ))
    }

    @MainActor
    func testTripBackupRejectsCrossTripTravelerReferenceWithoutReplacingData() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let household = Household(name: "Test Home")
        let firstTrip = PackingTrip(
            householdID: household.id,
            title: "First Trip",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let secondTrip = PackingTrip(
            householdID: household.id,
            title: "Second Trip",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let firstTraveler = TripTraveler(
            householdID: household.id,
            tripID: firstTrip.id,
            kind: .adult,
            displayName: "Adult Traveler"
        )
        let secondTraveler = TripTraveler(
            householdID: household.id,
            tripID: secondTrip.id,
            kind: .adult,
            displayName: "Second Adult"
        )
        let item = PackingItem(
            householdID: household.id,
            tripID: firstTrip.id,
            travelerID: firstTraveler.id,
            title: "Sample Item"
        )
        context.insert(household)
        context.insert(firstTrip)
        context.insert(secondTrip)
        context.insert(firstTraveler)
        context.insert(secondTraveler)
        context.insert(item)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var packingItems = try XCTUnwrap(object["packingItems"] as? [[String: Any]])
        packingItems[0]["travelerID"] = secondTraveler.id.uuidString
        object["packingItems"] = packingItems
        let corruptBackup = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try DataExportImportService.importData(
            corruptBackup,
            context: context,
            createRecoveryBackup: false
        ))
        XCTAssertEqual(try context.fetch(FetchDescriptor<PackingTrip>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PackingItem>()).first?.travelerID, firstTraveler.id)
    }

    @MainActor
    func testTripReminderDatesIncludeOnlyFutureDatesInOrder() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            startDate: now,
            endDate: now,
            reminderDate: now.addingTimeInterval(-60),
            finalCheckDate: now.addingTimeInterval(120)
        )

        let dates = NotificationManager.packingTripReminderDates(trip: trip, now: now)

        XCTAssertEqual(dates.count, 1)
        XCTAssertEqual(dates.first?.date, now.addingTimeInterval(120))
        XCTAssertEqual(dates.first?.finalCheck, true)
    }

    @MainActor
    func testTripRemindersTargetOnlyMatchingCaregiverAssignments() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            startDate: now,
            endDate: now.addingTimeInterval(86_400),
            reminderDate: now.addingTimeInterval(60),
            finalCheckDate: now.addingTimeInterval(120)
        )
        let assignedItem = PackingItem(
            householdID: trip.householdID,
            tripID: trip.id,
            title: "Travel documents",
            assignedCaregiverName: "Caregiver A",
            caregiverReminderEnabled: true
        )
        let disabledItem = PackingItem(
            householdID: trip.householdID,
            tripID: trip.id,
            title: "Optional item",
            assignedCaregiverName: "Caregiver A",
            caregiverReminderEnabled: false
        )

        let matching = PackingTripReminderSnapshot(
            trip: trip,
            items: [assignedItem, disabledItem],
            currentCaregiverName: "caregiver a"
        )
        XCTAssertTrue(matching.usesTargetedReminders)
        XCTAssertTrue(matching.isEligibleForCurrentCaregiver)
        XCTAssertEqual(matching.assignedRemainingCount, 1)
        XCTAssertEqual(matching.targetCaregiverName, "caregiver a")

        let content = NotificationManager.shared.buildPackingTripNotificationContent(
            snapshot: matching,
            finalCheck: false
        )
        XCTAssertEqual(content.title, "Your packing reminder")
        XCTAssertEqual(content.body, "You have 1 assigned item left to pack for Sample Trip.")
        XCTAssertEqual(content.userInfo["targetCaregiverName"] as? String, "caregiver a")

        let otherCaregiver = PackingTripReminderSnapshot(
            trip: trip,
            items: [assignedItem, disabledItem],
            currentCaregiverName: "Caregiver B"
        )
        XCTAssertTrue(otherCaregiver.usesTargetedReminders)
        XCTAssertFalse(otherCaregiver.isEligibleForCurrentCaregiver)
        XCTAssertEqual(otherCaregiver.assignedRemainingCount, 0)

        assignedItem.state = .packed
        let completedAssignment = PackingTripReminderSnapshot(
            trip: trip,
            items: [assignedItem, disabledItem],
            currentCaregiverName: "Caregiver A"
        )
        XCTAssertTrue(completedAssignment.usesTargetedReminders)
        XCTAssertFalse(completedAssignment.isEligibleForCurrentCaregiver)
    }

    @MainActor
    func testTripTravelerManagementAddsSuggestionsAndPreservesItemsOnRemoval() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let householdID = UUID()
        let trip = PackingTrip(
            householdID: householdID,
            title: "Sample Trip",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_172_800)
        )
        let adult = TripTraveler(
            householdID: householdID,
            tripID: trip.id,
            kind: .adult,
            displayName: "Adult Traveler"
        )
        context.insert(trip)
        context.insert(adult)
        try context.save()

        let child = try XCTUnwrap(TripPackingService.addTraveler(
            to: trip,
            kind: .child,
            profileID: UUID(),
            displayName: "Sample Child",
            includeStarterItems: true,
            existingTravelers: [adult],
            existingItems: [],
            context: context,
            caregiverName: "Caregiver A"
        ))
        let childItems = try context.fetch(FetchDescriptor<PackingItem>())
            .filter { $0.travelerID == child.id }
        XCTAssertFalse(childItems.isEmpty)
        XCTAssertNotNil(childItems.first { $0.templateKey == "child.diapers" })

        let childBag = PackingBag(
            householdID: householdID,
            tripID: trip.id,
            travelerID: child.id,
            name: "Child Bag"
        )
        context.insert(childBag)
        try context.save()
        XCTAssertTrue(TripPackingService.removeTraveler(
            child,
            from: trip,
            travelers: [adult, child],
            bags: [childBag],
            items: childItems,
            context: context
        ))

        XCTAssertNil(childBag.travelerID)
        XCTAssertTrue(childItems.allSatisfy { $0.travelerID == nil })
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripTraveler>()).map(\.id), [adult.id])
    }

    @MainActor
    func testTripPackingDeepLinksOpenTripsAndSelectedTrip() throws {
        let tripID = UUID()
        let router = DeepLinkRouter.shared
        router.pendingFoodCommand = nil
        router.route(try XCTUnwrap(URL(string: "littlewindows://food/trips")))
        XCTAssertEqual(router.selectedTab, .food)
        XCTAssertEqual(router.pendingFoodCommand, .trips)

        router.route(try XCTUnwrap(URL(string: "littlewindows://food/trips/\(tripID.uuidString)")))
        XCTAssertEqual(router.selectedTab, .food)
        XCTAssertEqual(router.pendingFoodCommand, .packingTrip(tripID))
    }

    @MainActor
    func testTripPackingReminderContentDeepLinksToTrip() {
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            startDate: Date(timeIntervalSince1970: 1_900_000_000),
            endDate: Date(timeIntervalSince1970: 1_900_086_400)
        )

        let content = NotificationManager.shared.buildPackingTripNotificationContent(
            trip: trip,
            finalCheck: true
        )

        XCTAssertEqual(content.title, "Final packing check")
        XCTAssertEqual(content.body, "Review what is still unpacked for Sample Trip.")
        XCTAssertEqual(content.categoryIdentifier, NotificationManager.packingTripReminderCategoryID)
        XCTAssertEqual(
            content.userInfo["deepLink"] as? String,
            "littlewindows://food/trips/\(trip.id.uuidString)"
        )
    }

    @MainActor
    func testTripItineraryServiceSupportsBookedTasksLinksAndChoices() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let householdID = UUID()
        let start = tripDate(2027, 7, 10, timeZoneIdentifier: "America/Los_Angeles")
        let trip = PackingTrip(
            householdID: householdID,
            title: "Sample Trip",
            startDate: start,
            endDate: start.addingTimeInterval(3 * 86_400),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        context.insert(trip)

        let group = try XCTUnwrap(TripItineraryService.createChoiceGroup(
            title: "Weather plan",
            notes: "Choose after checking the forecast.",
            scheduledDay: start.addingTimeInterval(86_400),
            trip: trip,
            existingGroups: [],
            context: context
        ))
        let input = TripItineraryItemInput(
            title: "Confirm reservation",
            kind: .task,
            scheduleKind: .timed,
            scheduledDay: start.addingTimeInterval(86_400),
            startDate: start.addingTimeInterval(86_400 + 10 * 3_600),
            endDate: nil,
            startTimeZoneIdentifier: "America/Los_Angeles",
            endTimeZoneIdentifier: "America/Los_Angeles",
            location: TripDestinationSelection(name: "Sample Hotel"),
            origin: nil,
            notes: "Call before noon.",
            bookingStatus: .booked,
            providerName: "Sample Provider",
            confirmationNumber: "TEST-123",
            choiceGroupID: group.id,
            assignedCaregiverName: "Caregiver A",
            reminderEnabled: true,
            reminderOffsetMinutes: 30,
            links: [TripItineraryLinkInput(
                title: "Reservation",
                urlString: "https://example.com/reservation"
            )]
        )
        let item = try XCTUnwrap(TripItineraryService.createItem(
            input: input,
            trip: trip,
            choiceGroups: [group],
            existingItems: [],
            context: context,
            caregiverName: "Caregiver A"
        ))
        let alternative = TripItineraryItem(
            householdID: householdID,
            tripID: trip.id,
            choiceGroupID: group.id,
            title: "Alternative plan"
        )

        XCTAssertFalse(TripItineraryService.reminderIsEligible(for: item, choiceGroups: [group]))
        XCTAssertFalse(TripItineraryService.reminderIsEligible(for: alternative, choiceGroups: [group]))
        XCTAssertTrue(TripItineraryService.selectChoice(item, in: group, trip: trip, context: context))
        XCTAssertEqual(group.selectedItemID, item.id)
        XCTAssertTrue(TripItineraryService.reminderIsEligible(for: item, choiceGroups: [group]))
        XCTAssertFalse(TripItineraryService.reminderIsEligible(for: alternative, choiceGroups: [group]))
        XCTAssertTrue(TripItineraryService.setCompleted(
            item,
            completed: true,
            trip: trip,
            context: context,
            caregiverName: "Caregiver A"
        ))
        XCTAssertTrue(item.isCompleted)
        XCTAssertEqual(item.completedBy, "Caregiver A")
        XCTAssertEqual(try context.fetch(FetchDescriptor<TripItineraryLink>()).first?.url?.host, "example.com")

        let content = NotificationManager.shared.buildItineraryItemNotificationContent(item: item, trip: trip)
        XCTAssertEqual(content.categoryIdentifier, NotificationManager.itineraryReminderCategoryID)
        XCTAssertEqual(
            content.userInfo["deepLink"] as? String,
            "littlewindows://food/trips/\(trip.id.uuidString)/itinerary/\(item.id.uuidString)"
        )

        var ungroupedInput = input
        ungroupedInput.choiceGroupID = nil
        XCTAssertTrue(TripItineraryService.updateItem(
            item,
            input: ungroupedInput,
            trip: trip,
            choiceGroups: [group],
            existingLinks: try context.fetch(FetchDescriptor<TripItineraryLink>()),
            context: context
        ))
        XCTAssertNil(group.selectedItemID)
        XCTAssertNil(item.choiceGroupID)
        XCTAssertTrue(TripItineraryService.reminderIsEligible(for: item, choiceGroups: [group]))
    }

    @MainActor
    func testTripItineraryGroupDayOwnsAndMovesItsOptions() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let householdID = UUID()
        let start = tripDate(2027, 3, 6, timeZoneIdentifier: "America/Los_Angeles")
        let trip = PackingTrip(
            householdID: householdID,
            title: "Sample Trip",
            startDate: start,
            endDate: tripDate(2027, 3, 15, timeZoneIdentifier: "America/Los_Angeles"),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let firstDay = tripDate(2027, 3, 7, timeZoneIdentifier: "America/Los_Angeles")
        let secondDay = tripDate(2027, 3, 14, timeZoneIdentifier: "America/Los_Angeles")
        var londonCalendar = Calendar(identifier: .gregorian)
        londonCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let firstDayStart = londonCalendar.date(from: DateComponents(
            year: 2027,
            month: 3,
            day: 7,
            hour: 10
        ))!
        let group = TripItineraryChoiceGroup(
            householdID: householdID,
            tripID: trip.id,
            title: "Weather plan",
            scheduledDay: firstDay
        )
        let item = TripItineraryItem(
            householdID: householdID,
            tripID: trip.id,
            choiceGroupID: group.id,
            title: "Outdoor activity",
            scheduleKind: .timed,
            scheduledDay: firstDay,
            startDate: firstDayStart,
            startTimeZoneIdentifier: "Europe/London",
            endTimeZoneIdentifier: "Europe/London",
            reminderEnabled: true
        )
        context.insert(trip)
        context.insert(group)
        context.insert(item)
        try context.save()

        XCTAssertTrue(TripItineraryService.updateChoiceGroup(
            group,
            title: group.title,
            notes: "Choose based on the forecast.",
            scheduledDay: secondDay,
            trip: trip,
            items: [item],
            context: context
        ))
        XCTAssertTrue(trip.tripCalendar.isDate(item.scheduledDay!, inSameDayAs: secondDay))
        XCTAssertEqual(londonCalendar.component(.hour, from: item.startDate!), 10)

        XCTAssertTrue(TripItineraryService.updateChoiceGroup(
            group,
            title: group.title,
            notes: "Choose based on the forecast.",
            scheduledDay: nil,
            trip: trip,
            items: [item],
            context: context
        ))
        XCTAssertEqual(item.scheduleKind, .unscheduled)
        XCTAssertNil(item.scheduledDay)
        XCTAssertNil(item.startDate)
        XCTAssertFalse(item.reminderEnabled)
    }

    @MainActor
    func testTripDateEditReconcilesItineraryWithinNewRange() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let originalStart = tripDate(2027, 3, 6, timeZoneIdentifier: "America/Los_Angeles")
        let originalLastDay = tripDate(2027, 3, 7, timeZoneIdentifier: "America/Los_Angeles")
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            startDate: originalStart,
            endDate: originalLastDay,
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let group = TripItineraryChoiceGroup(
            householdID: trip.householdID,
            tripID: trip.id,
            title: "Last-day plan",
            scheduledDay: originalLastDay
        )
        var londonCalendar = Calendar(identifier: .gregorian)
        londonCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let originalItemStart = londonCalendar.date(from: DateComponents(
            year: 2027,
            month: 3,
            day: 7,
            hour: 10
        ))!
        let item = TripItineraryItem(
            householdID: trip.householdID,
            tripID: trip.id,
            choiceGroupID: group.id,
            title: "Check out",
            kind: .task,
            scheduleKind: .timed,
            scheduledDay: originalLastDay,
            startDate: originalItemStart,
            startTimeZoneIdentifier: "Europe/London",
            endTimeZoneIdentifier: "Europe/London",
            reminderEnabled: true
        )
        context.insert(trip)
        context.insert(group)
        context.insert(item)
        try context.save()

        let newStart = tripDate(2027, 3, 13, timeZoneIdentifier: "America/Los_Angeles")
        let newEnd = tripDate(2027, 3, 14, timeZoneIdentifier: "America/Los_Angeles")
        XCTAssertTrue(TripPackingService.updateTrip(
            trip,
            title: trip.title,
            destination: nil,
            startDate: newStart,
            endDate: newEnd,
            travelMode: trip.travelMode,
            lodgingType: trip.lodgingType,
            laundryAvailable: trip.laundryAvailable,
            activities: trip.activities,
            weatherSuggestionsEnabled: false,
            reminderDate: nil,
            finalCheckDate: nil,
            notes: "",
            context: context
        ))

        XCTAssertTrue(trip.tripCalendar.isDate(group.scheduledDay!, inSameDayAs: newEnd))
        XCTAssertTrue(trip.tripCalendar.isDate(item.scheduledDay!, inSameDayAs: newEnd))
        XCTAssertEqual(londonCalendar.component(.hour, from: item.startDate!), 10)
        XCTAssertTrue((trip.startDate...trip.endDate.addingTimeInterval(86_400)).contains(item.startDate!))
    }

    @MainActor
    func testTripItineraryValidationRejectsInconsistentOrUnsafeInputs() {
        let start = tripDate(2027, 7, 10, timeZoneIdentifier: "America/Los_Angeles")
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            startDate: start,
            endDate: start.addingTimeInterval(2 * 86_400),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let group = TripItineraryChoiceGroup(
            householdID: trip.householdID,
            tripID: trip.id,
            title: "Day plan",
            scheduledDay: start
        )
        var input = TripItineraryItemInput(
            title: "Sample activity",
            kind: .activity,
            scheduleKind: .timed,
            scheduledDay: start.addingTimeInterval(86_400),
            startDate: start.addingTimeInterval(86_400 + 9 * 3_600),
            endDate: nil,
            startTimeZoneIdentifier: "Not/A_Time_Zone",
            endTimeZoneIdentifier: "America/Los_Angeles",
            location: TripDestinationSelection(name: "Sample Place", latitude: 100, longitude: -122),
            origin: nil,
            notes: "",
            bookingStatus: .planned,
            providerName: "",
            confirmationNumber: "",
            choiceGroupID: group.id,
            assignedCaregiverName: nil,
            reminderEnabled: false,
            reminderOffsetMinutes: 30,
            links: [TripItineraryLinkInput(title: "Broken", urlString: "https:///missing-host")]
        )

        XCTAssertEqual(
            TripItineraryService.validationMessage(for: input, trip: trip, choiceGroups: [group]),
            "Options must use the same day as their option group."
        )
        input.scheduledDay = start
        input.startDate = start.addingTimeInterval(9 * 3_600)
        XCTAssertEqual(
            TripItineraryService.validationMessage(for: input, trip: trip, choiceGroups: [group]),
            "Choose a valid time zone."
        )
        input.startTimeZoneIdentifier = "America/Los_Angeles"
        XCTAssertEqual(
            TripItineraryService.validationMessage(for: input, trip: trip, choiceGroups: [group]),
            "Choose a valid place with a name and complete coordinates."
        )
        input.location = TripDestinationSelection(name: "Sample Place", latitude: 37, longitude: -122)
        XCTAssertEqual(
            TripItineraryService.validationMessage(for: input, trip: trip, choiceGroups: [group]),
            "Each link must use a valid http or https address."
        )
        input.links = [TripItineraryLinkInput(title: "Details", urlString: "https://example.com/details")]
        input.startDate = start.addingTimeInterval(86_400 + 9 * 3_600)
        XCTAssertEqual(
            TripItineraryService.validationMessage(for: input, trip: trip, choiceGroups: [group]),
            "The start time must be on the selected itinerary day."
        )
    }

    @MainActor
    func testTripItineraryTimeZoneChangesPreserveEnteredWallClock() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let value = tripDate(2027, 3, 10, timeZoneIdentifier: losAngeles.identifier)
            .addingTimeInterval(9 * 3_600)
        let converted = TripItineraryService.date(
            value,
            preservingWallClockFrom: losAngeles,
            to: london
        )
        var londonCalendar = Calendar(identifier: .gregorian)
        londonCalendar.timeZone = london
        XCTAssertEqual(londonCalendar.component(.hour, from: converted), 21)
        XCTAssertEqual(londonCalendar.component(.day, from: converted), 10)
    }

    @MainActor
    func testTripItineraryPresentationIndexLargeDatasetPerformance() {
        let start = tripDate(2027, 7, 1, timeZoneIdentifier: "America/Los_Angeles")
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            startDate: start,
            endDate: start.addingTimeInterval(29 * 86_400),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let groups = (0..<100).map { index in
            TripItineraryChoiceGroup(
                householdID: trip.householdID,
                tripID: trip.id,
                title: "Option Group \(index)",
                scheduledDay: start.addingTimeInterval(TimeInterval(index % 30) * 86_400),
                sortOrder: index
            )
        }
        var items = [TripItineraryItem]()
        items.reserveCapacity(3_000)
        for index in 0..<3_000 {
            let isUnscheduled = index % 11 == 0
            let isTimed = index % 3 == 0
            let dayOffset = TimeInterval(index % 30) * 86_400
            items.append(TripItineraryItem(
                householdID: trip.householdID,
                tripID: trip.id,
                choiceGroupID: index % 5 == 0 ? groups[index % groups.count].id : nil,
                title: "Itinerary Item \(index)",
                scheduleKind: isUnscheduled ? .unscheduled : (isTimed ? .timed : .anytime),
                scheduledDay: isUnscheduled ? nil : start.addingTimeInterval(dayOffset),
                startDate: isTimed ? start.addingTimeInterval(dayOffset + 9 * 3_600) : nil,
                sortOrder: index
            ))
        }
        var links = [TripItineraryLink]()
        links.reserveCapacity(1_500)
        for (index, item) in items.prefix(1_500).enumerated() {
            links.append(TripItineraryLink(
                householdID: trip.householdID,
                tripID: trip.id,
                itineraryItemID: item.id,
                title: "Details",
                urlString: "https://example.com/\(index)",
                sortOrder: index
            ))
        }

        var lastIndex: TripItineraryPresentationIndex?
        measure(metrics: [XCTClockMetric()]) {
            lastIndex = TripItineraryPresentationIndex(
                trip: trip,
                choiceGroups: groups,
                items: items,
                links: links
            )
        }
        XCTAssertEqual(lastIndex?.itineraryDays.count, 30)
        XCTAssertEqual(lastIndex?.linksByItemID.count, 1_500)
        XCTAssertEqual(lastIndex?.optionsByGroupID.values.reduce(0) { $0 + $1.count }, 600)
    }

    @MainActor
    func testTripDuplicationShiftsAndResetsItineraryPlanningState() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let start = tripDate(2027, 3, 10, timeZoneIdentifier: "America/Los_Angeles")
        let copyStart = tripDate(2027, 3, 20, timeZoneIdentifier: "America/Los_Angeles")
        let trip = PackingTrip(
            householdID: UUID(),
            title: "Sample Trip",
            startDate: start,
            endDate: start.addingTimeInterval(2 * 86_400),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let group = TripItineraryChoiceGroup(
            householdID: trip.householdID,
            tripID: trip.id,
            title: "Day plan",
            scheduledDay: start.addingTimeInterval(86_400)
        )
        var londonCalendar = Calendar(identifier: .gregorian)
        londonCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let itemDay = trip.tripCalendar.date(byAdding: .day, value: 1, to: start)!
        let itemDayComponents = trip.tripCalendar.dateComponents([.year, .month, .day], from: itemDay)
        var itemStartComponents = itemDayComponents
        itemStartComponents.hour = 10
        let itemStart = londonCalendar.date(from: itemStartComponents)!
        var itemEndComponents = itemDayComponents
        itemEndComponents.hour = 12
        let itemEnd = londonCalendar.date(from: itemEndComponents)!
        let item = TripItineraryItem(
            householdID: trip.householdID,
            tripID: trip.id,
            choiceGroupID: group.id,
            title: "Booked activity",
            kind: .activity,
            scheduleKind: .timed,
            scheduledDay: itemDay,
            startDate: itemStart,
            endDate: itemEnd,
            startTimeZoneIdentifier: londonCalendar.timeZone.identifier,
            endTimeZoneIdentifier: londonCalendar.timeZone.identifier,
            bookingStatus: .booked,
            confirmationNumber: "TEST-456",
            reminderEnabled: true
        )
        group.selectedItemID = item.id
        let link = TripItineraryLink(
            householdID: trip.householdID,
            tripID: trip.id,
            itineraryItemID: item.id,
            title: "Details",
            urlString: "https://example.com/details"
        )
        context.insert(trip)
        context.insert(group)
        context.insert(item)
        context.insert(link)
        try context.save()

        let duplicate = try XCTUnwrap(TripPackingService.duplicateTrip(
            trip,
            travelers: [],
            bags: [],
            items: [],
            itineraryChoiceGroups: [group],
            itineraryItems: [item],
            itineraryLinks: [link],
            existingTrips: [trip],
            context: context,
            now: copyStart,
            copiedTimeZoneIdentifier: "America/Los_Angeles"
        ))
        let copiedGroup = try XCTUnwrap(try context.fetch(FetchDescriptor<TripItineraryChoiceGroup>())
            .first { $0.tripID == duplicate.id })
        let copiedItem = try XCTUnwrap(try context.fetch(FetchDescriptor<TripItineraryItem>())
            .first { $0.tripID == duplicate.id })
        let copiedLink = try XCTUnwrap(try context.fetch(FetchDescriptor<TripItineraryLink>())
            .first { $0.tripID == duplicate.id })

        XCTAssertNil(copiedGroup.selectedItemID)
        XCTAssertEqual(copiedItem.bookingStatus, .planned)
        XCTAssertNil(copiedItem.confirmationNumber)
        XCTAssertFalse(copiedItem.reminderEnabled)
        XCTAssertEqual(copiedLink.itineraryItemID, copiedItem.id)
        XCTAssertTrue(duplicate.tripCalendar.isDate(
            try XCTUnwrap(copiedItem.scheduledDay),
            inSameDayAs: duplicate.tripCalendar.date(byAdding: .day, value: 1, to: copyStart)!
        ))
        XCTAssertEqual(londonCalendar.component(.hour, from: try XCTUnwrap(copiedItem.startDate)), 10)
        XCTAssertEqual(londonCalendar.component(.hour, from: try XCTUnwrap(copiedItem.endDate)), 12)
        XCTAssertEqual(londonCalendar.component(.day, from: try XCTUnwrap(copiedItem.startDate)), 21)
    }

    @MainActor
    func testTripItineraryBackupRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let household = Household(name: "Sample Home")
        let start = tripDate(2027, 7, 10, timeZoneIdentifier: "America/New_York")
        let trip = PackingTrip(
            householdID: household.id,
            title: "Sample Trip",
            startDate: start,
            endDate: start.addingTimeInterval(86_400),
            timeZoneIdentifier: "America/New_York"
        )
        let group = TripItineraryChoiceGroup(
            householdID: household.id,
            tripID: trip.id,
            title: "Dinner options",
            scheduledDay: start
        )
        let item = TripItineraryItem(
            householdID: household.id,
            tripID: trip.id,
            choiceGroupID: group.id,
            title: "Sample Restaurant",
            kind: .meal,
            scheduleKind: .evening,
            scheduledDay: start,
            location: TripDestinationSelection(name: "Sample Restaurant"),
            bookingStatus: .booked,
            confirmationNumber: "TEST-789"
        )
        group.selectedItemID = item.id
        let link = TripItineraryLink(
            householdID: household.id,
            tripID: trip.id,
            itineraryItemID: item.id,
            title: "Menu",
            urlString: "https://example.com/menu"
        )
        context.insert(household)
        context.insert(trip)
        context.insert(group)
        context.insert(item)
        context.insert(link)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        let familyPayloads = try DataExportImportService.familySyncEntityPayloads(from: backup)
        XCTAssertNotNil(familyPayloads[DataExportImportService.familySyncEntityKey(
            collection: "tripItineraryChoiceGroups",
            id: group.id.uuidString
        )])
        XCTAssertNotNil(familyPayloads[DataExportImportService.familySyncEntityKey(
            collection: "tripItineraryItems",
            id: item.id.uuidString
        )])
        XCTAssertNotNil(familyPayloads[DataExportImportService.familySyncEntityKey(
            collection: "tripItineraryLinks",
            id: link.id.uuidString
        )])
        var corruptObject = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var corruptLinks = try XCTUnwrap(corruptObject["tripItineraryLinks"] as? [[String: Any]])
        corruptLinks[0]["urlString"] = "https:///missing-host"
        corruptObject["tripItineraryLinks"] = corruptLinks
        let corruptBackup = try JSONSerialization.data(withJSONObject: corruptObject)
        XCTAssertThrowsError(try DataExportImportService.importData(
            corruptBackup,
            context: context,
            recordLocalSave: false,
            createRecoveryBackup: false
        ))
        try DataExportImportService.importData(
            backup,
            context: context,
            recordLocalSave: false,
            createRecoveryBackup: false
        )

        let restoredGroup = try XCTUnwrap(try context.fetch(FetchDescriptor<TripItineraryChoiceGroup>()).first)
        let restoredItem = try XCTUnwrap(try context.fetch(FetchDescriptor<TripItineraryItem>()).first)
        let restoredLink = try XCTUnwrap(try context.fetch(FetchDescriptor<TripItineraryLink>()).first)
        XCTAssertEqual(restoredGroup.selectedItemID, restoredItem.id)
        XCTAssertEqual(restoredItem.confirmationNumber, "TEST-789")
        XCTAssertEqual(restoredItem.choiceGroupID, restoredGroup.id)
        XCTAssertEqual(restoredLink.itineraryItemID, restoredItem.id)
        XCTAssertEqual(restoredLink.urlString, "https://example.com/menu")
    }

    @MainActor
    func testTripItineraryDeepLinkOpensSpecificItem() throws {
        let tripID = UUID()
        let itemID = UUID()
        let router = DeepLinkRouter.shared
        router.pendingFoodCommand = nil
        router.route(try XCTUnwrap(URL(
            string: "littlewindows://food/trips/\(tripID.uuidString)/itinerary/\(itemID.uuidString)"
        )))
        XCTAssertEqual(router.selectedTab, .food)
        XCTAssertEqual(router.pendingFoodCommand, .itineraryItem(tripID, itemID))
    }

    private func rmsWindows(_ samples: [Double], windowSize: Int) -> [Double] {
        stride(from: 0, to: samples.count - windowSize, by: windowSize).map { start in
            rms(Array(samples[start..<start + windowSize]))
        }
    }

    private func tripDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        timeZoneIdentifier: String
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = PersistenceService.schema
        let configuration = Self.uniqueInMemoryConfiguration(schema: schema)
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private static func uniqueInMemoryConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            "LittleWindowsTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
    }
}

private actor TestTripWeatherClient: TripWeatherForecastClient {
    private var days: [TripDailyWeather]
    private var forecastRequests = 0

    init(days: [TripDailyWeather]) {
        self.days = days
    }

    func dailyForecast(latitude: Double, longitude: Double) async throws -> [TripDailyWeather] {
        forecastRequests += 1
        return days
    }

    func attribution() async throws -> TripWeatherAttribution {
        TripWeatherAttribution(
            legalPageURL: URL(string: "https://example.com/legal")!,
            lightMarkURL: URL(string: "https://example.com/light")!,
            darkMarkURL: URL(string: "https://example.com/dark")!
        )
    }

    func forecastRequestCount() -> Int {
        forecastRequests
    }

    func replaceDays(_ value: [TripDailyWeather]) {
        days = value
    }
}
