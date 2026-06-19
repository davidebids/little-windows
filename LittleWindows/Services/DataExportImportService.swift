import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct BackupEnvelope: Codable {
    var version: Int
    var exportedAt: Date
    var profiles: [ProfileDTO]
    var photoAttachments: [PhotoAttachmentDTO]?
    var events: [EventDTO]
    var predictionRecords: [PredictionRecordDTO]
    var milestones: [MilestoneDTO]?
    var appointments: [AppointmentDTO]?
    var ageGuideReadStates: [AgeGuideReadStateDTO]?
    var puppyStageGuideReadStates: [PuppyStageGuideReadStateDTO]?
    var households: [HouseholdDTO]?
    var foodStores: [FoodStoreDTO]?
    var foodStoreSections: [FoodStoreSectionDTO]?
    var shoppingLists: [ShoppingListDTO]?
    var shoppingListItems: [ShoppingListItemDTO]?
    var foodItems: [FoodItemDTO]?
    var inventoryLocations: [InventoryLocationDTO]?
    var inventoryItems: [InventoryItemDTO]?
    var mealPrepItems: [MealPrepItemDTO]?
    var mealPrepUsages: [MealPrepUsageDTO]?
    var foodReminders: [FoodReminderDTO]?
}

private struct ProfileDTO: Codable {
    var id: UUID
    var profileTypeRawValue: String?
    var name: String
    var birthDate: Date
    var sexRawValue: String?
    var birthWeightKilograms: Double?
    var birthLengthCentimeters: Double?
    var birthHeadCircumferenceCentimeters: Double?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool?
    var displayColor: String?
    var adoptionDate: Date?
    var species: String?
    var breed: String?
    var coatColor: String?
    var microchipNumber: String?
    var vetName: String?
    var vetClinic: String?
    var vetPhone: String?
    var emergencyVet: String?
    var profilePhotoAttachmentID: UUID?
}

private struct PhotoAttachmentDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var ownerKindRawValue: String
    var contentType: String
    var filename: String?
    var imageData: Data?
    var thumbnailData: Data?
    var byteCount: Int
    var createdAt: Date
    var updatedAt: Date
}

private struct EventDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var profileTypeSnapshotRawValue: String?
    var typeRawValue: String
    var title: String?
    var startDate: Date
    var endDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var caregiverName: String?
    var notes: String?
    var sleepKindRawValue: String?
    var feedKindRawValue: String?
    var amountOz: Double?
    var foodDescription: String?
    var nursingSideRawValue: String?
    var activeNursingSideRawValue: String?
    var timerStateRawValue: String?
    var timerAccumulatedSeconds: Double?
    var activeTimerSegmentStartDate: Date?
    var leftDurationSeconds: Double?
    var rightDurationSeconds: Double?
    var diaperKindRawValue: String?
    var peeAmountRawValue: String?
    var pooAmountRawValue: String?
    var pooColorRawValue: String?
    var pooTextureRawValue: String?
    var stoolColor: String?
    var stoolTexture: String?
    var bookTitle: String?
    var medicineName: String?
    var dose: Double?
    var doseUnit: String?
    var reason: String?
    var activityTypeRawValue: String?
    var heightFeet: Int?
    var heightInches: Double?
    var weightPounds: Int?
    var weightOunces: Double?
    var headCircumferenceInches: Double?
    var growthSexRawValue: String?
    var growthSourceRawValue: String?
    var weightKilograms: Double?
    var lengthCentimeters: Double?
    var headCircumferenceCentimeters: Double?
    var temperatureCelsius: Double?
    var temperatureUnitRawValue: String?
    var temperatureMethodRawValue: String?
    var dogDetailsData: Data?
}

private struct PredictionRecordDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var generatedAt: Date
    var basedOnLastSleepEventID: UUID?
    var predictedStart: Date
    var predictedWindowStart: Date
    var predictedWindowEnd: Date
    var predictionKindRawValue: String
    var confidence: Double
    var confidenceLabelRawValue: String
    var explanationSnapshot: String
    var factorsData: Data?
    var napIndex: Int
    var algorithmVersion: String
    var actualSleepEventID: UUID?
    var actualSleepStart: Date?
    var errorMinutes: Double?
    var wasInsidePredictedWindow: Bool?
    var createdAt: Date
    var updatedAt: Date
}

private struct MilestoneDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var title: String
    var date: Date
    var approximateDate: Bool
    var categoryRawValue: String
    var notes: String?
    var photoAttachmentIDs: [UUID]?
    var createdAt: Date
    var updatedAt: Date
    var caregiverName: String?
    var isFavorite: Bool
    var sortOrder: Int?
}

private struct AppointmentDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var title: String
    var appointmentTypeRawValue: String
    var startDate: Date
    var endDate: Date?
    var locationName: String?
    var address: String?
    var doctorName: String?
    var clinicName: String?
    var phoneNumber: String?
    var notes: String?
    var questionsToAsk: String?
    var visitSummary: String?
    var followUpInstructions: String?
    var medicationsDiscussed: String?
    var vaccinesGiven: String?
    var growthEntryID: UUID?
    var temperatureEntryID: UUID?
    var remindersEnabled: Bool
    var reminderLeadTimeMinutes: [Int]
    var lastScheduledAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isCompleted: Bool
    var caregiverName: String?
}

private struct AgeGuideReadStateDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var guideID: String
    var firstOpenedAt: Date?
    var lastOpenedAt: Date?
    var isDismissedFromToday: Bool
    var notificationSentAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

private struct PuppyStageGuideReadStateDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var guideID: String
    var firstOpenedAt: Date?
    var lastOpenedAt: Date?
    var isDismissedFromToday: Bool
    var notificationSentAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

private struct HouseholdDTO: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

private struct FoodStoreDTO: Codable {
    var id: UUID
    var householdID: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var sortOrder: Int?
}

private struct FoodStoreSectionDTO: Codable {
    var id: UUID
    var householdID: UUID
    var storeID: UUID
    var name: String
    var sortOrder: Int
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct ShoppingListDTO: Codable {
    var id: UUID
    var householdID: UUID
    var name: String
    var storeID: UUID?
    var listTypeRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var sortOrder: Int?
    var notes: String?
    var lastUsedAt: Date?
}

private struct ShoppingListItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var shoppingListID: UUID
    var foodItemID: UUID?
    var name: String
    var quantity: Double?
    var unit: String?
    var notes: String?
    var storeSectionID: UUID?
    var categoryName: String?
    var isChecked: Bool
    var checkedAt: Date?
    var lastUncheckedAt: Date?
    var isRecurringStaple: Bool
    var priorityRawValue: String
    var addedBy: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int?
    var lastPurchasedAt: Date?
    var purchaseCount: Int
    var inventoryLinkBehaviorRawValue: String
}

private struct FoodItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var canonicalName: String
    var aliasesJSON: String?
    var defaultUnit: String?
    var defaultStoreSectionByStoreJSON: String?
    var defaultInventoryLocationID: UUID?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
}

private struct InventoryLocationDTO: Codable {
    var id: UUID
    var householdID: UUID
    var name: String
    var locationTypeRawValue: String
    var sortOrder: Int
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
}

private struct InventoryItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var foodItemID: UUID?
    var name: String
    var quantity: Double
    var unit: String
    var locationID: UUID
    var storageDetail: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var statusRawValue: String
}

private struct MealPrepItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var name: String
    var locationID: UUID
    var servingsTotal: Double?
    var servingsRemaining: Double
    var servingUnitRawValue: String
    var preparedDate: Date?
    var notes: String?
    var tagsJSON: String?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var isArchived: Bool
}

private struct MealPrepUsageDTO: Codable {
    var id: UUID
    var householdID: UUID
    var mealPrepItemID: UUID
    var dateTime: Date
    var servingsUsed: Double
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct FoodReminderDTO: Codable {
    var id: UUID
    var householdID: UUID
    var typeRawValue: String
    var title: String
    var relatedShoppingListID: UUID?
    var relatedMealPrepItemID: UUID?
    var dateTime: Date
    var isEnabled: Bool
    var recurrence: String?
    var createdAt: Date
    var updatedAt: Date
}

enum DataExportImportService {
    @MainActor
    static func exportData(context: ModelContext) throws -> Data {
        let profiles = try context.fetch(FetchDescriptor<BabyProfile>()).map {
            ProfileDTO(
                id: $0.id,
                profileTypeRawValue: $0.profileTypeRawValue,
                name: $0.name,
                birthDate: $0.birthDate,
                sexRawValue: $0.sexRawValue,
                birthWeightKilograms: $0.birthWeightKilograms,
                birthLengthCentimeters: $0.birthLengthCentimeters,
                birthHeadCircumferenceCentimeters: $0.birthHeadCircumferenceCentimeters,
                notes: $0.notes,
                createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                isArchived: $0.isArchived,
                displayColor: $0.displayColor,
                adoptionDate: $0.adoptionDate,
                species: $0.species,
                breed: $0.breed,
                coatColor: $0.coatColor,
                microchipNumber: $0.microchipNumber,
                vetName: $0.vetName,
                vetClinic: $0.vetClinic,
                vetPhone: $0.vetPhone,
                emergencyVet: $0.emergencyVet,
                profilePhotoAttachmentID: $0.profilePhotoAttachmentID
            )
        }
        let photoAttachments = try context.fetch(FetchDescriptor<PhotoAttachment>()).map {
            PhotoAttachmentDTO(
                id: $0.id,
                profileID: $0.profileID,
                ownerKindRawValue: $0.ownerKindRawValue,
                contentType: $0.contentType,
                filename: $0.filename,
                imageData: $0.imageData,
                thumbnailData: $0.thumbnailData,
                byteCount: $0.byteCount,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let events = try context.fetch(FetchDescriptor<BabyEvent>()).map {
            EventDTO(
                id: $0.id,
                profileID: $0.profileID,
                profileTypeSnapshotRawValue: $0.profileTypeSnapshotRawValue,
                typeRawValue: $0.typeRawValue,
                title: $0.title,
                startDate: $0.startDate, endDate: $0.endDate, createdAt: $0.createdAt,
                updatedAt: $0.updatedAt, caregiverName: $0.caregiverName, notes: $0.notes,
                sleepKindRawValue: $0.sleepKindRawValue, feedKindRawValue: $0.feedKindRawValue,
                amountOz: $0.amountOz, foodDescription: $0.foodDescription,
                nursingSideRawValue: $0.nursingSideRawValue,
                activeNursingSideRawValue: $0.activeNursingSideRawValue,
                timerStateRawValue: $0.timerStateRawValue,
                timerAccumulatedSeconds: $0.timerAccumulatedSeconds,
                activeTimerSegmentStartDate: $0.activeTimerSegmentStartDate,
                leftDurationSeconds: $0.leftDurationSeconds,
                rightDurationSeconds: $0.rightDurationSeconds,
                diaperKindRawValue: $0.diaperKindRawValue,
                peeAmountRawValue: $0.peeAmountRawValue,
                pooAmountRawValue: $0.pooAmountRawValue,
                pooColorRawValue: $0.pooColorRawValue,
                pooTextureRawValue: $0.pooTextureRawValue,
                stoolColor: $0.stoolColor,
                stoolTexture: $0.stoolTexture, bookTitle: $0.bookTitle,
                medicineName: $0.medicineName, dose: $0.dose, doseUnit: $0.doseUnit,
                reason: $0.reason, activityTypeRawValue: $0.activityTypeRawValue,
                heightFeet: $0.heightFeet, heightInches: $0.heightInches,
                weightPounds: $0.weightPounds, weightOunces: $0.weightOunces,
                headCircumferenceInches: $0.headCircumferenceInches,
                growthSexRawValue: $0.growthSexRawValue,
                growthSourceRawValue: $0.growthSourceRawValue,
                weightKilograms: $0.weightKilograms,
                lengthCentimeters: $0.lengthCentimeters,
                headCircumferenceCentimeters: $0.headCircumferenceCentimeters,
                temperatureCelsius: $0.temperatureCelsius,
                temperatureUnitRawValue: $0.temperatureUnitRawValue,
                temperatureMethodRawValue: $0.temperatureMethodRawValue,
                dogDetailsData: $0.dogDetailsData
            )
        }
        let records = try context.fetch(FetchDescriptor<SleepPredictionRecord>()).map {
            PredictionRecordDTO(
                id: $0.id, profileID: $0.profileID, generatedAt: $0.generatedAt,
                basedOnLastSleepEventID: $0.basedOnLastSleepEventID,
                predictedStart: $0.predictedStart, predictedWindowStart: $0.predictedWindowStart,
                predictedWindowEnd: $0.predictedWindowEnd,
                predictionKindRawValue: $0.predictionKindRawValue,
                confidence: $0.confidence, confidenceLabelRawValue: $0.confidenceLabelRawValue,
                explanationSnapshot: $0.explanationSnapshot, factorsData: $0.factorsData,
                napIndex: $0.napIndex, algorithmVersion: $0.algorithmVersion,
                actualSleepEventID: $0.actualSleepEventID, actualSleepStart: $0.actualSleepStart,
                errorMinutes: $0.errorMinutes,
                wasInsidePredictedWindow: $0.wasInsidePredictedWindow,
                createdAt: $0.createdAt, updatedAt: $0.updatedAt
            )
        }
        let milestones = try context.fetch(FetchDescriptor<MilestoneEntry>()).map {
            MilestoneDTO(
                id: $0.id,
                profileID: $0.profileID,
                title: $0.title,
                date: $0.date,
                approximateDate: $0.approximateDate,
                categoryRawValue: $0.categoryRawValue,
                notes: $0.notes,
                photoAttachmentIDs: $0.photoAttachmentIDs,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                caregiverName: $0.caregiverName,
                isFavorite: $0.isFavorite,
                sortOrder: $0.sortOrder
            )
        }
        let appointments = try context.fetch(FetchDescriptor<DoctorAppointment>()).map {
            AppointmentDTO(
                id: $0.id,
                profileID: $0.profileID,
                title: $0.title,
                appointmentTypeRawValue: $0.appointmentTypeRawValue,
                startDate: $0.startDate,
                endDate: $0.endDate,
                locationName: $0.locationName,
                address: $0.address,
                doctorName: $0.doctorName,
                clinicName: $0.clinicName,
                phoneNumber: $0.phoneNumber,
                notes: $0.notes,
                questionsToAsk: $0.questionsToAsk,
                visitSummary: $0.visitSummary,
                followUpInstructions: $0.followUpInstructions,
                medicationsDiscussed: $0.medicationsDiscussed,
                vaccinesGiven: $0.vaccinesGiven,
                growthEntryID: $0.growthEntryID,
                temperatureEntryID: $0.temperatureEntryID,
                remindersEnabled: $0.remindersEnabled,
                reminderLeadTimeMinutes: $0.reminderLeadTimeMinutes,
                lastScheduledAt: $0.lastScheduledAt,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                isCompleted: $0.isCompleted,
                caregiverName: $0.caregiverName
            )
        }
        let ageGuideReadStates = try context.fetch(FetchDescriptor<AgeGuideReadState>()).map {
            AgeGuideReadStateDTO(
                id: $0.id,
                profileID: $0.profileID,
                guideID: $0.guideID,
                firstOpenedAt: $0.firstOpenedAt,
                lastOpenedAt: $0.lastOpenedAt,
                isDismissedFromToday: $0.isDismissedFromToday,
                notificationSentAt: $0.notificationSentAt,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let puppyStageGuideReadStates = try context.fetch(FetchDescriptor<PuppyStageGuideReadState>()).map {
            PuppyStageGuideReadStateDTO(
                id: $0.id,
                profileID: $0.profileID,
                guideID: $0.guideID,
                firstOpenedAt: $0.firstOpenedAt,
                lastOpenedAt: $0.lastOpenedAt,
                isDismissedFromToday: $0.isDismissedFromToday,
                notificationSentAt: $0.notificationSentAt,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let households = try context.fetch(FetchDescriptor<Household>()).map {
            HouseholdDTO(id: $0.id, name: $0.name, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
        let foodStores = try context.fetch(FetchDescriptor<FoodStore>()).map {
            FoodStoreDTO(
                id: $0.id,
                householdID: $0.householdID,
                name: $0.name,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                isArchived: $0.isArchived,
                sortOrder: $0.sortOrder
            )
        }
        let foodStoreSections = try context.fetch(FetchDescriptor<FoodStoreSection>()).map {
            FoodStoreSectionDTO(
                id: $0.id,
                householdID: $0.householdID,
                storeID: $0.storeID,
                name: $0.name,
                sortOrder: $0.sortOrder,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let shoppingLists = try context.fetch(FetchDescriptor<ShoppingList>()).map {
            ShoppingListDTO(
                id: $0.id,
                householdID: $0.householdID,
                name: $0.name,
                storeID: $0.storeID,
                listTypeRawValue: $0.listTypeRawValue,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                isArchived: $0.isArchived,
                sortOrder: $0.sortOrder,
                notes: $0.notes,
                lastUsedAt: $0.lastUsedAt
            )
        }
        let shoppingListItems = try context.fetch(FetchDescriptor<ShoppingListItem>()).map {
            ShoppingListItemDTO(
                id: $0.id,
                householdID: $0.householdID,
                shoppingListID: $0.shoppingListID,
                foodItemID: $0.foodItemID,
                name: $0.name,
                quantity: $0.quantity,
                unit: $0.unit,
                notes: $0.notes,
                storeSectionID: $0.storeSectionID,
                categoryName: $0.categoryName,
                isChecked: $0.isChecked,
                checkedAt: $0.checkedAt,
                lastUncheckedAt: $0.lastUncheckedAt,
                isRecurringStaple: $0.isRecurringStaple,
                priorityRawValue: $0.priorityRawValue,
                addedBy: $0.addedBy,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder,
                lastPurchasedAt: $0.lastPurchasedAt,
                purchaseCount: $0.purchaseCount,
                inventoryLinkBehaviorRawValue: $0.inventoryLinkBehaviorRawValue
            )
        }
        let foodItems = try context.fetch(FetchDescriptor<FoodItem>()).map {
            FoodItemDTO(
                id: $0.id,
                householdID: $0.householdID,
                canonicalName: $0.canonicalName,
                aliasesJSON: $0.aliasesJSON,
                defaultUnit: $0.defaultUnit,
                defaultStoreSectionByStoreJSON: $0.defaultStoreSectionByStoreJSON,
                defaultInventoryLocationID: $0.defaultInventoryLocationID,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                isArchived: $0.isArchived
            )
        }
        let inventoryLocations = try context.fetch(FetchDescriptor<InventoryLocation>()).map {
            InventoryLocationDTO(
                id: $0.id,
                householdID: $0.householdID,
                name: $0.name,
                locationTypeRawValue: $0.locationTypeRawValue,
                sortOrder: $0.sortOrder,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                isArchived: $0.isArchived
            )
        }
        let inventoryItems = try context.fetch(FetchDescriptor<InventoryItem>()).map {
            InventoryItemDTO(
                id: $0.id,
                householdID: $0.householdID,
                foodItemID: $0.foodItemID,
                name: $0.name,
                quantity: $0.quantity,
                unit: $0.unit,
                locationID: $0.locationID,
                storageDetail: $0.storageDetail,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                lastUsedAt: $0.lastUsedAt,
                statusRawValue: $0.statusRawValue
            )
        }
        let mealPrepItems = try context.fetch(FetchDescriptor<MealPrepItem>()).map {
            MealPrepItemDTO(
                id: $0.id,
                householdID: $0.householdID,
                name: $0.name,
                locationID: $0.locationID,
                servingsTotal: $0.servingsTotal,
                servingsRemaining: $0.servingsRemaining,
                servingUnitRawValue: $0.servingUnitRawValue,
                preparedDate: $0.preparedDate,
                notes: $0.notes,
                tagsJSON: $0.tagsJSON,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                lastUsedAt: $0.lastUsedAt,
                isArchived: $0.isArchived
            )
        }
        let mealPrepUsages = try context.fetch(FetchDescriptor<MealPrepUsage>()).map {
            MealPrepUsageDTO(
                id: $0.id,
                householdID: $0.householdID,
                mealPrepItemID: $0.mealPrepItemID,
                dateTime: $0.dateTime,
                servingsUsed: $0.servingsUsed,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let foodReminders = try context.fetch(FetchDescriptor<FoodReminder>()).map {
            FoodReminderDTO(
                id: $0.id,
                householdID: $0.householdID,
                typeRawValue: $0.typeRawValue,
                title: $0.title,
                relatedShoppingListID: $0.relatedShoppingListID,
                relatedMealPrepItemID: $0.relatedMealPrepItemID,
                dateTime: $0.dateTime,
                isEnabled: $0.isEnabled,
                recurrence: $0.recurrence,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let envelope = BackupEnvelope(
            version: 9,
            exportedAt: Date(),
            profiles: profiles,
            photoAttachments: photoAttachments,
            events: events,
            predictionRecords: records,
            milestones: milestones,
            appointments: appointments,
            ageGuideReadStates: ageGuideReadStates,
            puppyStageGuideReadStates: puppyStageGuideReadStates,
            households: households,
            foodStores: foodStores,
            foodStoreSections: foodStoreSections,
            shoppingLists: shoppingLists,
            shoppingListItems: shoppingListItems,
            foodItems: foodItems,
            inventoryLocations: inventoryLocations,
            inventoryItems: inventoryItems,
            mealPrepItems: mealPrepItems,
            mealPrepUsages: mealPrepUsages,
            foodReminders: foodReminders
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    @MainActor
    static func importData(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        guard (1...9).contains(envelope.version) else { throw CocoaError(.fileReadUnknown) }
        try deleteAll(context: context)

        for value in envelope.profiles {
            context.insert(BabyProfile(
                id: value.id,
                profileType: value.profileTypeRawValue.flatMap(CareProfileType.init(rawValue:)) ?? .child,
                name: value.name, birthDate: value.birthDate,
                sex: value.sexRawValue.flatMap(BabySex.init(rawValue:)) ?? .male,
                birthWeightKilograms: value.birthWeightKilograms,
                birthLengthCentimeters: value.birthLengthCentimeters,
                birthHeadCircumferenceCentimeters: value.birthHeadCircumferenceCentimeters,
                notes: value.notes, createdAt: value.createdAt, updatedAt: value.updatedAt,
                isArchived: value.isArchived ?? false,
                displayColor: value.displayColor,
                adoptionDate: value.adoptionDate,
                species: value.species,
                breed: value.breed,
                coatColor: value.coatColor,
                microchipNumber: value.microchipNumber,
                vetName: value.vetName,
                vetClinic: value.vetClinic,
                vetPhone: value.vetPhone,
                emergencyVet: value.emergencyVet,
                profilePhotoAttachmentID: value.profilePhotoAttachmentID
            ))
        }
        for value in envelope.photoAttachments ?? [] {
            if let imageData = value.imageData {
                context.insert(PhotoAttachment(
                    id: value.id,
                    profileID: value.profileID,
                    ownerKind: PhotoAttachmentOwnerKind(rawValue: value.ownerKindRawValue) ?? .milestone,
                    contentType: value.contentType,
                    filename: value.filename,
                    imageData: imageData,
                    thumbnailData: value.thumbnailData,
                    byteCount: value.byteCount,
                    createdAt: value.createdAt,
                    updatedAt: value.updatedAt
                ))
            }
        }
        let fallbackProfileID = envelope.profiles.first?.id
        for value in envelope.events {
            let event = BabyEvent(
                id: value.id,
                profileID: value.profileID ?? fallbackProfileID,
                type: EventType.normalized(rawValue: value.typeRawValue),
                title: value.title,
                startDate: value.startDate,
                endDate: value.endDate,
                caregiverName: value.caregiverName,
                notes: value.notes
            )
            event.createdAt = value.createdAt
            event.updatedAt = value.updatedAt
            event.profileTypeSnapshotRawValue = value.profileTypeSnapshotRawValue
            event.sleepKindRawValue = value.sleepKindRawValue
            event.feedKindRawValue = value.feedKindRawValue
            event.amountOz = value.amountOz
            event.foodDescription = value.foodDescription
            event.nursingSideRawValue = value.nursingSideRawValue
            event.activeNursingSideRawValue = value.activeNursingSideRawValue
            event.timerStateRawValue = value.timerStateRawValue
            event.timerAccumulatedSeconds = value.timerAccumulatedSeconds
            event.activeTimerSegmentStartDate = value.activeTimerSegmentStartDate
            event.leftDurationSeconds = value.leftDurationSeconds
            event.rightDurationSeconds = value.rightDurationSeconds
            event.diaperKindRawValue = value.diaperKindRawValue
            event.peeAmountRawValue = value.peeAmountRawValue
            event.pooAmountRawValue = value.pooAmountRawValue
            event.pooColorRawValue = value.pooColorRawValue
            event.pooTextureRawValue = value.pooTextureRawValue
            event.stoolColor = value.stoolColor
            event.stoolTexture = value.stoolTexture
            event.bookTitle = value.bookTitle
            event.medicineName = value.medicineName
            event.dose = value.dose
            event.doseUnit = value.doseUnit
            event.reason = value.reason
            event.activityTypeRawValue = value.activityTypeRawValue
                ?? ActivityType.legacyType(rawValue: value.typeRawValue)?.rawValue
            event.heightFeet = value.heightFeet
            event.heightInches = value.heightInches
            event.weightPounds = value.weightPounds
            event.weightOunces = value.weightOunces
            event.headCircumferenceInches = value.headCircumferenceInches
            event.growthSexRawValue = value.growthSexRawValue
            event.growthSourceRawValue = value.growthSourceRawValue
            event.weightKilograms = value.weightKilograms
                ?? ((value.weightPounds != nil || value.weightOunces != nil)
                    ? GrowthUnitConversion.poundsAndOuncesToKilograms(
                        pounds: value.weightPounds ?? 0,
                        ounces: value.weightOunces ?? 0
                    )
                    : nil)
            event.lengthCentimeters = value.lengthCentimeters
                ?? ((value.heightFeet != nil || value.heightInches != nil)
                    ? GrowthUnitConversion.feetAndInchesToCentimeters(
                        feet: value.heightFeet ?? 0,
                        inches: value.heightInches ?? 0
                    )
                    : nil)
            event.headCircumferenceCentimeters = value.headCircumferenceCentimeters
                ?? value.headCircumferenceInches.map(GrowthUnitConversion.inchesToCentimeters)
            event.temperatureCelsius = value.temperatureCelsius
            event.temperatureUnitRawValue = value.temperatureUnitRawValue
            event.temperatureMethodRawValue = value.temperatureMethodRawValue
            event.dogDetailsData = value.dogDetailsData
            context.insert(event)
        }
        for value in envelope.predictionRecords {
            let placeholder = SleepPrediction(
                predictedStart: value.predictedStart,
                predictedWindowStart: value.predictedWindowStart,
                predictedWindowEnd: value.predictedWindowEnd,
                predictionKind: PredictionKind(rawValue: value.predictionKindRawValue) ?? .nap,
                confidence: value.confidence,
                confidenceLabel: ConfidenceLabel(rawValue: value.confidenceLabelRawValue) ?? .low,
                explanation: value.explanationSnapshot.split(separator: "\n").map(String.init),
                contributingFactors: [],
                napIndex: value.napIndex
            )
            let record = SleepPredictionRecord(
                prediction: placeholder,
                basedOnLastSleepEventID: value.basedOnLastSleepEventID
            )
            record.id = value.id
            record.profileID = value.profileID ?? fallbackProfileID
            record.generatedAt = value.generatedAt
            record.explanationSnapshot = value.explanationSnapshot
            record.factorsData = value.factorsData
            record.algorithmVersion = value.algorithmVersion
            record.actualSleepEventID = value.actualSleepEventID
            record.actualSleepStart = value.actualSleepStart
            record.errorMinutes = value.errorMinutes
            record.wasInsidePredictedWindow = value.wasInsidePredictedWindow
            record.createdAt = value.createdAt
            record.updatedAt = value.updatedAt
            context.insert(record)
        }
        for value in envelope.milestones ?? [] {
            context.insert(MilestoneEntry(
                id: value.id,
                profileID: value.profileID ?? fallbackProfileID,
                title: value.title,
                date: value.date,
                approximateDate: value.approximateDate,
                category: MilestoneCategory(rawValue: value.categoryRawValue) ?? .custom,
                notes: value.notes,
                photoAttachmentIDs: value.photoAttachmentIDs ?? [],
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                caregiverName: value.caregiverName,
                isFavorite: value.isFavorite,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.appointments ?? [] {
            let appointment = DoctorAppointment(
                id: value.id,
                profileID: value.profileID ?? fallbackProfileID,
                title: value.title,
                appointmentType: AppointmentType(rawValue: value.appointmentTypeRawValue) ?? .other,
                startDate: value.startDate,
                endDate: value.endDate,
                locationName: value.locationName,
                address: value.address,
                doctorName: value.doctorName,
                clinicName: value.clinicName,
                phoneNumber: value.phoneNumber,
                notes: value.notes,
                questionsToAsk: value.questionsToAsk,
                visitSummary: value.visitSummary,
                followUpInstructions: value.followUpInstructions,
                medicationsDiscussed: value.medicationsDiscussed,
                vaccinesGiven: value.vaccinesGiven,
                growthEntryID: value.growthEntryID,
                temperatureEntryID: value.temperatureEntryID,
                remindersEnabled: value.remindersEnabled,
                reminderLeadTimeMinutes: value.reminderLeadTimeMinutes,
                lastScheduledAt: value.lastScheduledAt,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                isCompleted: value.isCompleted,
                caregiverName: value.caregiverName
            )
            context.insert(appointment)
        }
        for value in envelope.ageGuideReadStates ?? [] {
            context.insert(AgeGuideReadState(
                id: value.id,
                profileID: value.profileID ?? fallbackProfileID,
                guideID: value.guideID,
                firstOpenedAt: value.firstOpenedAt,
                lastOpenedAt: value.lastOpenedAt,
                isDismissedFromToday: value.isDismissedFromToday,
                notificationSentAt: value.notificationSentAt,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.puppyStageGuideReadStates ?? [] {
            context.insert(PuppyStageGuideReadState(
                id: value.id,
                profileID: value.profileID ?? fallbackProfileID,
                guideID: value.guideID,
                firstOpenedAt: value.firstOpenedAt,
                lastOpenedAt: value.lastOpenedAt,
                isDismissedFromToday: value.isDismissedFromToday,
                notificationSentAt: value.notificationSentAt,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.households ?? [] {
            context.insert(Household(
                id: value.id,
                name: value.name,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.foodStores ?? [] {
            context.insert(FoodStore(
                id: value.id,
                householdID: value.householdID,
                name: value.name,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                isArchived: value.isArchived,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.foodStoreSections ?? [] {
            context.insert(FoodStoreSection(
                id: value.id,
                householdID: value.householdID,
                storeID: value.storeID,
                name: value.name,
                sortOrder: value.sortOrder,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.shoppingLists ?? [] {
            context.insert(ShoppingList(
                id: value.id,
                householdID: value.householdID,
                name: value.name,
                storeID: value.storeID,
                listType: ShoppingListType(rawValue: value.listTypeRawValue) ?? .general,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                isArchived: value.isArchived,
                sortOrder: value.sortOrder,
                notes: value.notes,
                lastUsedAt: value.lastUsedAt
            ))
        }
        for value in envelope.shoppingListItems ?? [] {
            context.insert(ShoppingListItem(
                id: value.id,
                householdID: value.householdID,
                shoppingListID: value.shoppingListID,
                foodItemID: value.foodItemID,
                name: value.name,
                quantity: value.quantity,
                unit: value.unit,
                notes: value.notes,
                storeSectionID: value.storeSectionID,
                categoryName: value.categoryName,
                isChecked: value.isChecked,
                checkedAt: value.checkedAt,
                lastUncheckedAt: value.lastUncheckedAt,
                isRecurringStaple: value.isRecurringStaple,
                priority: ShoppingItemPriority(rawValue: value.priorityRawValue) ?? .normal,
                addedBy: value.addedBy,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder,
                lastPurchasedAt: value.lastPurchasedAt,
                purchaseCount: value.purchaseCount,
                inventoryLinkBehavior: InventoryLinkBehavior(
                    rawValue: value.inventoryLinkBehaviorRawValue
                ) ?? .askWhenChecked
            ))
        }
        for value in envelope.foodItems ?? [] {
            context.insert(FoodItem(
                id: value.id,
                householdID: value.householdID,
                canonicalName: value.canonicalName,
                aliasesJSON: value.aliasesJSON,
                defaultUnit: value.defaultUnit,
                defaultStoreSectionByStoreJSON: value.defaultStoreSectionByStoreJSON,
                defaultInventoryLocationID: value.defaultInventoryLocationID,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                isArchived: value.isArchived
            ))
        }
        for value in envelope.inventoryLocations ?? [] {
            context.insert(InventoryLocation(
                id: value.id,
                householdID: value.householdID,
                name: value.name,
                locationType: InventoryLocationType(rawValue: value.locationTypeRawValue) ?? .custom,
                sortOrder: value.sortOrder,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                isArchived: value.isArchived
            ))
        }
        for value in envelope.inventoryItems ?? [] {
            context.insert(InventoryItem(
                id: value.id,
                householdID: value.householdID,
                foodItemID: value.foodItemID,
                name: value.name,
                quantity: value.quantity,
                unit: value.unit,
                locationID: value.locationID,
                storageDetail: value.storageDetail,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                lastUsedAt: value.lastUsedAt,
                status: InventoryItemStatus(rawValue: value.statusRawValue) ?? .available
            ))
        }
        for value in envelope.mealPrepItems ?? [] {
            context.insert(MealPrepItem(
                id: value.id,
                householdID: value.householdID,
                name: value.name,
                locationID: value.locationID,
                servingsTotal: value.servingsTotal,
                servingsRemaining: value.servingsRemaining,
                servingUnit: MealPrepServingUnit(rawValue: value.servingUnitRawValue) ?? .serving,
                preparedDate: value.preparedDate,
                notes: value.notes,
                tagsJSON: value.tagsJSON,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                lastUsedAt: value.lastUsedAt,
                isArchived: value.isArchived
            ))
        }
        for value in envelope.mealPrepUsages ?? [] {
            context.insert(MealPrepUsage(
                id: value.id,
                householdID: value.householdID,
                mealPrepItemID: value.mealPrepItemID,
                dateTime: value.dateTime,
                servingsUsed: value.servingsUsed,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.foodReminders ?? [] {
            context.insert(FoodReminder(
                id: value.id,
                householdID: value.householdID,
                type: FoodReminderType(rawValue: value.typeRawValue) ?? .custom,
                title: value.title,
                relatedShoppingListID: value.relatedShoppingListID,
                relatedMealPrepItemID: value.relatedMealPrepItemID,
                dateTime: value.dateTime,
                isEnabled: value.isEnabled,
                recurrence: value.recurrence,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        try context.save()
        PersistenceService.recordLocalSave()
        _ = try LegacyTrackerGrowthMigration.migrate(in: context)
        ProfileMigrationService.ensureProfilesAndAssignments(context: context)
    }

    @MainActor
    static func deleteAll(context: ModelContext) throws {
        try deleteAll(FoodReminder.self, context: context)
        try deleteAll(MealPrepUsage.self, context: context)
        try deleteAll(MealPrepItem.self, context: context)
        try deleteAll(InventoryItem.self, context: context)
        try deleteAll(InventoryLocation.self, context: context)
        try deleteAll(FoodItem.self, context: context)
        try deleteAll(ShoppingListItem.self, context: context)
        try deleteAll(ShoppingList.self, context: context)
        try deleteAll(FoodStoreSection.self, context: context)
        try deleteAll(FoodStore.self, context: context)
        try deleteAll(Household.self, context: context)
        try deleteAll(PhotoAttachment.self, context: context)
        try deleteAll(PredictionFactor.self, context: context)
        try deleteAll(SleepPredictionRecord.self, context: context)
        try deleteAll(BabyEvent.self, context: context)
        try deleteAll(DoctorAppointment.self, context: context)
        try deleteAll(MilestoneEntry.self, context: context)
        try deleteAll(AgeGuideReadState.self, context: context)
        try deleteAll(PuppyStageGuideReadState.self, context: context)
        try deleteAll(BabyProfile.self, context: context)
        try context.save()
        PersistenceService.recordLocalSave()
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(
        _ modelType: T.Type,
        context: ModelContext
    ) throws {
        for item in try context.fetch(FetchDescriptor<T>()) {
            context.delete(item)
        }
    }
}

enum LegacyTrackerGrowthMigration {
    struct ParsedMeasurement: Equatable {
        var weightPounds: Int?
        var weightOunces: Double?
        var heightFeet: Int?
        var heightInches: Double?
        var headCircumferenceInches: Double?
        var notes: String?
    }

    @MainActor
    @discardableResult
    static func migrate(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate {
                $0.typeRawValue == "custom" && $0.title == "Growth"
            }
        )
        let legacyEvents = try context.fetch(descriptor)
        guard !legacyEvents.isEmpty else { return 0 }

        let profile = try context.fetch(FetchDescriptor<BabyProfile>()).first
        var migratedCount = 0

        for event in legacyEvents {
            guard let measurement = parse(notes: event.notes) else { continue }

            event.type = .growth
            event.title = nil
            event.notes = measurement.notes
            event.weightPounds = measurement.weightPounds
            event.weightOunces = measurement.weightOunces
            event.heightFeet = measurement.heightFeet
            event.heightInches = measurement.heightInches
            event.headCircumferenceInches = measurement.headCircumferenceInches
            event.weightKilograms = canonicalWeight(for: measurement)
            event.lengthCentimeters = canonicalLength(for: measurement)
            event.headCircumferenceCentimeters = measurement.headCircumferenceInches.map(
                GrowthUnitConversion.inchesToCentimeters
            )
            event.growthSex = profile?.sex ?? .unknown
            event.growthSource = .other
            migratedCount += 1

            guard let profile,
                  Calendar.current.isDate(event.startDate, inSameDayAs: profile.birthDate) else {
                continue
            }
            profile.birthWeightKilograms =
                profile.birthWeightKilograms ?? event.weightKilograms
            profile.birthLengthCentimeters =
                profile.birthLengthCentimeters ?? event.lengthCentimeters
            profile.birthHeadCircumferenceCentimeters =
                profile.birthHeadCircumferenceCentimeters
                ?? event.headCircumferenceCentimeters
        }

        if migratedCount > 0 {
            try context.save()
            PersistenceService.recordLocalSave()
        }
        return migratedCount
    }

    static func parse(notes: String?) -> ParsedMeasurement? {
        guard let notes else { return nil }
        var result = ParsedMeasurement()
        var remainingLines = [String]()

        for rawLine in notes.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = value(after: "Weight:", in: line) {
                let parsed = parseCompound(value, suffix: "lbs.oz")
                result.weightPounds = parsed?.major
                result.weightOunces = parsed?.minor
            } else if let value = value(after: "Length:", in: line) {
                let parsed = parseCompound(value, suffix: "ft.in")
                result.heightFeet = parsed?.major
                result.heightInches = parsed?.minor
            } else if let value = value(after: "Head:", in: line) {
                result.headCircumferenceInches = parseInches(value)
            } else if !line.isEmpty {
                remainingLines.append(line)
            }
        }

        guard result.weightPounds != nil
                || result.heightFeet != nil
                || result.headCircumferenceInches != nil else {
            return nil
        }
        result.notes = remainingLines.isEmpty ? nil : remainingLines.joined(separator: "\n")
        return result
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        return String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseCompound(
        _ value: String,
        suffix: String
    ) -> (major: Int, minor: Double)? {
        guard value.lowercased().hasSuffix(suffix.lowercased()) else { return nil }
        let number = String(value.dropLast(suffix.count))
        let parts = number.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let major = Int(parts[0]) else { return nil }
        guard parts.count == 2, !parts[1].isEmpty else { return (major, 0) }

        let encodedMinor = String(parts[1])
        guard let digits = Double(encodedMinor) else { return nil }
        let minor = encodedMinor.count == 1 ? digits : digits / 10
        return (major, minor)
    }

    private static func parseInches(_ value: String) -> Double? {
        guard value.lowercased().hasSuffix("in") else { return nil }
        return Double(value.dropLast(2))
    }

    private static func canonicalWeight(for value: ParsedMeasurement) -> Double? {
        guard value.weightPounds != nil || value.weightOunces != nil else { return nil }
        return GrowthUnitConversion.poundsAndOuncesToKilograms(
            pounds: value.weightPounds ?? 0,
            ounces: value.weightOunces ?? 0
        )
    }

    private static func canonicalLength(for value: ParsedMeasurement) -> Double? {
        guard value.heightFeet != nil || value.heightInches != nil else { return nil }
        return GrowthUnitConversion.feetAndInchesToCentimeters(
            feet: value.heightFeet ?? 0,
            inches: value.heightInches ?? 0
        )
    }
}
