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

struct AutomaticRecoveryBackup: Identifiable, Hashable {
    var url: URL
    var createdAt: Date

    var id: URL { url }

    var displayName: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct BackupEnvelope: Codable {
    var version: Int
    var exportedAt: Date
    var profiles: [ProfileDTO]
    var photoAttachments: [PhotoAttachmentDTO]?
    var solidFoods: [SolidFoodCatalogItemDTO]?
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
    var homeTodoLists: [HomeTodoListDTO]?
    var homeTodoItems: [HomeTodoItemDTO]?
    var packingTrips: [PackingTripDTO]?
    var tripTravelers: [TripTravelerDTO]?
    var packingBags: [PackingBagDTO]?
    var packingItems: [PackingItemDTO]?
    var foodItems: [FoodItemDTO]?
    var inventoryLocations: [InventoryLocationDTO]?
    var inventoryItems: [InventoryItemDTO]?
    var mealPrepItems: [MealPrepItemDTO]?
    var mealPrepUsages: [MealPrepUsageDTO]?
    var returnRequests: [ReturnRequestDTO]?
    var returnItems: [ReturnItemDTO]?
    var returnPackages: [ReturnPackageDTO]?
    var foodReminders: [FoodReminderDTO]?
    var careRoutines: [CareRoutineDTO]?
    var careRoutineSteps: [CareRoutineStepDTO]?
    var careRoutineRuns: [CareRoutineRunDTO]?
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

private struct SolidFoodCatalogItemDTO: Codable {
    var id: UUID
    var name: String
    var photoAttachmentID: UUID?
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
    var startTimeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var caregiverName: String?
    var notes: String?
    var sleepKindRawValue: String?
    var feedKindRawValue: String?
    var amountOz: Double?
    var foodDescription: String?
    var solidReactionRawValue: String?
    var solidTextureRawValue: String?
    var solidFeedingStyleRawValue: String?
    var solidAllergenExposure: Bool?
    var solidSensitivityObserved: Bool?
    var nursingSideRawValue: String?
    var activeNursingSideRawValue: String?
    var timerStateRawValue: String?
    var timerAccumulatedSeconds: Double?
    var activeTimerSegmentStartDate: Date?
    var leftDurationSeconds: Double?
    var rightDurationSeconds: Double?
    var diaperKindRawValue: String?
    var diaperRash: Bool?
    var childPottyKindRawValue: String?
    var childPottyLocationRawValue: String?
    var childPottyAccident: Bool?
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
    var timeZoneIdentifier: String?
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
    var isFavorite: Bool?
    var priorityRawValue: String
    var addedBy: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int?
    var lastPurchasedAt: Date?
    var purchaseCount: Int
    var inventoryLinkBehaviorRawValue: String
}

private struct HomeTodoListDTO: Codable {
    var id: UUID
    var householdID: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var sortOrder: Int?
}

private struct HomeTodoItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var todoListID: UUID
    var title: String
    var notes: String?
    var isCompleted: Bool
    var addedBy: String?
    var completedBy: String?
    var completedAt: Date?
    var lastReopenedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int?
}

private struct PackingTripDTO: Codable {
    var id: UUID
    var householdID: UUID
    var title: String
    var destinationName: String?
    var destinationDetail: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var destinationTimeZoneIdentifier: String?
    var destinationStops: [TripDestinationStop]?
    var startDate: Date
    var endDate: Date
    var timeZoneIdentifier: String?
    var travelModeRawValue: String
    var lodgingTypeRawValue: String
    var laundryAvailable: Bool
    var activitiesRawValue: String
    var notes: String?
    var statusRawValue: String
    var weatherSuggestionsEnabled: Bool
    var reminderDate: Date?
    var finalCheckDate: Date?
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isArchived: Bool
    var sortOrder: Int?
}

private struct TripTravelerDTO: Codable {
    var id: UUID
    var householdID: UUID
    var tripID: UUID
    var kindRawValue: String
    var profileID: UUID?
    var displayName: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
}

private struct PackingBagDTO: Codable {
    var id: UUID
    var householdID: UUID
    var tripID: UUID
    var travelerID: UUID?
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
}

private struct PackingItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var tripID: UUID
    var travelerID: UUID?
    var bagID: UUID?
    var templateKey: String?
    var title: String
    var categoryRawValue: String
    var quantity: Double?
    var unit: String?
    var notes: String?
    var priorityRawValue: String
    var stateRawValue: String
    var needsPurchase: Bool
    var relatedShoppingItemID: UUID?
    var addedBy: String?
    var assignedCaregiverName: String?
    var caregiverReminderEnabled: Bool?
    var packedBy: String?
    var packedAt: Date?
    var lastUnpackedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
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

private struct ReturnRequestDTO: Codable {
    var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isArchived: Bool
    var sortOrder: Int?
}

private struct ReturnItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var returnRequestID: UUID
    var packageID: UUID?
    var name: String
    var quantity: Double?
    var reason: String?
    var returnURLString: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int?
}

private struct ReturnPackageDTO: Codable {
    var id: UUID
    var householdID: UUID
    var returnRequestID: UUID
    var name: String
    var carrierRawValue: String
    var methodRawValue: String
    var trackingNumber: String?
    var returnByDate: Date?
    var photoAttachmentIDs: [UUID]?
    var droppedOffAt: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int?
}

private struct FoodReminderDTO: Codable {
    var id: UUID
    var householdID: UUID
    var typeRawValue: String
    var title: String
    var relatedTodoListID: UUID?
    var relatedShoppingListID: UUID?
    var relatedMealPrepItemID: UUID?
    var relatedReturnRequestID: UUID?
    var dateTime: Date
    var timeZoneIdentifier: String?
    var isEnabled: Bool
    var recurrence: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct CareRoutineDTO: Codable {
    var id: UUID
    var scopeRawValue: String
    var profileTypeRawValue: String?
    var profileID: UUID?
    var householdID: UUID?
    var title: String
    var notes: String?
    var iconName: String
    var tintName: String
    var templateKindRawValue: String?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var sortOrder: Int
    var reminderEnabled: Bool
    var reminderTimeMinutesAfterMidnight: Int?
    var lastStartedAt: Date?
    var lastCompletedAt: Date?
}

private struct CareRoutineStepDTO: Codable {
    var id: UUID
    var routineID: UUID
    var title: String
    var notes: String?
    var actionRawValue: String
    var eventTypeRawValue: String?
    var activityTypeRawValue: String?
    var nursingSideRawValue: String?
    var sleepKindRawValue: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}

private struct CareRoutineRunDTO: Codable {
    var id: UUID
    var routineID: UUID
    var profileID: UUID?
    var householdID: UUID?
    var stateRawValue: String
    var startedAt: Date
    var completedAt: Date?
    var cancelledAt: Date?
    var startedByCaregiverName: String?
    var completedByCaregiverName: String?
    var cancelledByCaregiverName: String?
    var completedStepIDsData: Data?
    var skippedStepIDsData: Data?
    var stepResolutionRecordsData: Data?
    var createdAt: Date
    var updatedAt: Date
}

enum DataExportImportService {
    private static let currentBackupVersion = 16
    private static let recoveryBackupLimit = 3

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
        let solidFoods = try context.fetch(FetchDescriptor<SolidFoodCatalogItem>()).map {
            SolidFoodCatalogItemDTO(
                id: $0.id,
                name: $0.name,
                photoAttachmentID: $0.photoAttachmentID,
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
                startDate: $0.startDate,
                endDate: $0.endDate,
                startTimeZoneIdentifier: $0.startTimeZoneIdentifier,
                endTimeZoneIdentifier: $0.endTimeZoneIdentifier,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt, caregiverName: $0.caregiverName, notes: $0.notes,
                sleepKindRawValue: $0.sleepKindRawValue, feedKindRawValue: $0.feedKindRawValue,
                amountOz: $0.amountOz, foodDescription: $0.foodDescription,
                solidReactionRawValue: $0.solidReactionRawValue,
                solidTextureRawValue: $0.solidTextureRawValue,
                solidFeedingStyleRawValue: $0.solidFeedingStyleRawValue,
                solidAllergenExposure: $0.solidAllergenExposure,
                solidSensitivityObserved: $0.solidSensitivityObserved,
                nursingSideRawValue: $0.nursingSideRawValue,
                activeNursingSideRawValue: $0.activeNursingSideRawValue,
                timerStateRawValue: $0.timerStateRawValue,
                timerAccumulatedSeconds: $0.timerAccumulatedSeconds,
                activeTimerSegmentStartDate: $0.activeTimerSegmentStartDate,
                leftDurationSeconds: $0.leftDurationSeconds,
                rightDurationSeconds: $0.rightDurationSeconds,
                diaperKindRawValue: $0.diaperKindRawValue,
                diaperRash: $0.diaperRash,
                childPottyKindRawValue: $0.childPottyKindRawValue,
                childPottyLocationRawValue: $0.childPottyLocationRawValue,
                childPottyAccident: $0.childPottyAccident,
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
                timeZoneIdentifier: $0.timeZoneIdentifier,
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
                isFavorite: $0.isFavorite,
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
        let homeTodoLists = try context.fetch(FetchDescriptor<HomeTodoList>()).map {
            HomeTodoListDTO(
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
        let homeTodoItems = try context.fetch(FetchDescriptor<HomeTodoItem>()).map {
            HomeTodoItemDTO(
                id: $0.id,
                householdID: $0.householdID,
                todoListID: $0.todoListID,
                title: $0.title,
                notes: $0.notes,
                isCompleted: $0.isCompleted,
                addedBy: $0.addedBy,
                completedBy: $0.completedBy,
                completedAt: $0.completedAt,
                lastReopenedAt: $0.lastReopenedAt,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder
            )
        }
        let packingTrips = try context.fetch(FetchDescriptor<PackingTrip>()).map {
            PackingTripDTO(
                id: $0.id,
                householdID: $0.householdID,
                title: $0.title,
                destinationName: $0.destinationName,
                destinationDetail: $0.destinationDetail,
                destinationLatitude: $0.destinationLatitude,
                destinationLongitude: $0.destinationLongitude,
                destinationTimeZoneIdentifier: $0.destinationTimeZoneIdentifier,
                destinationStops: $0.destinationStops,
                startDate: $0.startDate,
                endDate: $0.endDate,
                timeZoneIdentifier: $0.timeZoneIdentifier,
                travelModeRawValue: $0.travelModeRawValue,
                lodgingTypeRawValue: $0.lodgingTypeRawValue,
                laundryAvailable: $0.laundryAvailable,
                activitiesRawValue: $0.activitiesRawValue,
                notes: $0.notes,
                statusRawValue: $0.statusRawValue,
                weatherSuggestionsEnabled: $0.weatherSuggestionsEnabled,
                reminderDate: $0.reminderDate,
                finalCheckDate: $0.finalCheckDate,
                createdBy: $0.createdBy,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                completedAt: $0.completedAt,
                isArchived: $0.isArchived,
                sortOrder: $0.sortOrder
            )
        }
        let tripTravelers = try context.fetch(FetchDescriptor<TripTraveler>()).map {
            TripTravelerDTO(
                id: $0.id,
                householdID: $0.householdID,
                tripID: $0.tripID,
                kindRawValue: $0.kindRawValue,
                profileID: $0.profileID,
                displayName: $0.displayName,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder
            )
        }
        let packingBags = try context.fetch(FetchDescriptor<PackingBag>()).map {
            PackingBagDTO(
                id: $0.id,
                householdID: $0.householdID,
                tripID: $0.tripID,
                travelerID: $0.travelerID,
                name: $0.name,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder
            )
        }
        let packingItems = try context.fetch(FetchDescriptor<PackingItem>()).map {
            PackingItemDTO(
                id: $0.id,
                householdID: $0.householdID,
                tripID: $0.tripID,
                travelerID: $0.travelerID,
                bagID: $0.bagID,
                templateKey: $0.templateKey,
                title: $0.title,
                categoryRawValue: $0.categoryRawValue,
                quantity: $0.quantity,
                unit: $0.unit,
                notes: $0.notes,
                priorityRawValue: $0.priorityRawValue,
                stateRawValue: $0.stateRawValue,
                needsPurchase: $0.needsPurchase,
                relatedShoppingItemID: $0.relatedShoppingItemID,
                addedBy: $0.addedBy,
                assignedCaregiverName: $0.assignedCaregiverName,
                caregiverReminderEnabled: $0.caregiverReminderEnabled,
                packedBy: $0.packedBy,
                packedAt: $0.packedAt,
                lastUnpackedAt: $0.lastUnpackedAt,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder
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
        let returnRequests = try context.fetch(FetchDescriptor<ReturnRequest>()).map {
            ReturnRequestDTO(
                id: $0.id,
                householdID: $0.householdID,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                completedAt: $0.completedAt,
                isArchived: $0.isArchived,
                sortOrder: $0.sortOrder
            )
        }
        let returnItems = try context.fetch(FetchDescriptor<ReturnItem>()).map {
            ReturnItemDTO(
                id: $0.id,
                householdID: $0.householdID,
                returnRequestID: $0.returnRequestID,
                packageID: $0.packageID,
                name: $0.name,
                quantity: $0.quantity,
                reason: $0.reason,
                returnURLString: $0.returnURLString,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder
            )
        }
        let returnPackages = try context.fetch(FetchDescriptor<ReturnPackage>()).map {
            ReturnPackageDTO(
                id: $0.id,
                householdID: $0.householdID,
                returnRequestID: $0.returnRequestID,
                name: $0.name,
                carrierRawValue: $0.carrierRawValue,
                methodRawValue: $0.methodRawValue,
                trackingNumber: $0.trackingNumber,
                returnByDate: $0.returnByDate,
                photoAttachmentIDs: $0.photoAttachmentIDs,
                droppedOffAt: $0.droppedOffAt,
                completedAt: $0.completedAt,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder
            )
        }
        let foodReminders = try context.fetch(FetchDescriptor<FoodReminder>()).map {
            FoodReminderDTO(
                id: $0.id,
                householdID: $0.householdID,
                typeRawValue: $0.typeRawValue,
                title: $0.title,
                relatedTodoListID: $0.relatedTodoListID,
                relatedShoppingListID: $0.relatedShoppingListID,
                relatedMealPrepItemID: $0.relatedMealPrepItemID,
                relatedReturnRequestID: $0.relatedReturnRequestID,
                dateTime: $0.dateTime,
                timeZoneIdentifier: $0.timeZoneIdentifier,
                isEnabled: $0.isEnabled,
                recurrence: $0.recurrence,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let careRoutines = try context.fetch(FetchDescriptor<CareRoutine>()).map {
            CareRoutineDTO(
                id: $0.id,
                scopeRawValue: $0.scopeRawValue,
                profileTypeRawValue: $0.profileTypeRawValue,
                profileID: $0.profileID,
                householdID: $0.householdID,
                title: $0.title,
                notes: $0.notes,
                iconName: $0.iconName,
                tintName: $0.tintName,
                templateKindRawValue: $0.templateKindRawValue,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                isArchived: $0.isArchived,
                sortOrder: $0.sortOrder,
                reminderEnabled: $0.reminderEnabled,
                reminderTimeMinutesAfterMidnight: $0.reminderTimeMinutesAfterMidnight,
                lastStartedAt: $0.lastStartedAt,
                lastCompletedAt: $0.lastCompletedAt
            )
        }
        let careRoutineSteps = try context.fetch(FetchDescriptor<CareRoutineStep>()).map {
            CareRoutineStepDTO(
                id: $0.id,
                routineID: $0.routineID,
                title: $0.title,
                notes: $0.notes,
                actionRawValue: $0.actionRawValue,
                eventTypeRawValue: $0.eventTypeRawValue,
                activityTypeRawValue: $0.activityTypeRawValue,
                nursingSideRawValue: $0.nursingSideRawValue,
                sleepKindRawValue: $0.sleepKindRawValue,
                sortOrder: $0.sortOrder,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let careRoutineRuns = try context.fetch(FetchDescriptor<CareRoutineRun>()).map {
            CareRoutineRunDTO(
                id: $0.id,
                routineID: $0.routineID,
                profileID: $0.profileID,
                householdID: $0.householdID,
                stateRawValue: $0.stateRawValue,
                startedAt: $0.startedAt,
                completedAt: $0.completedAt,
                cancelledAt: $0.cancelledAt,
                startedByCaregiverName: $0.startedByCaregiverName,
                completedByCaregiverName: $0.completedByCaregiverName,
                cancelledByCaregiverName: $0.cancelledByCaregiverName,
                completedStepIDsData: $0.completedStepIDsData,
                skippedStepIDsData: $0.skippedStepIDsData,
                stepResolutionRecordsData: $0.stepResolutionRecordsData,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let envelope = BackupEnvelope(
            version: currentBackupVersion,
            exportedAt: Date(),
            profiles: profiles,
            photoAttachments: photoAttachments,
            solidFoods: solidFoods,
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
            homeTodoLists: homeTodoLists,
            homeTodoItems: homeTodoItems,
            packingTrips: packingTrips,
            tripTravelers: tripTravelers,
            packingBags: packingBags,
            packingItems: packingItems,
            foodItems: foodItems,
            inventoryLocations: inventoryLocations,
            inventoryItems: inventoryItems,
            mealPrepItems: mealPrepItems,
            mealPrepUsages: mealPrepUsages,
            returnRequests: returnRequests,
            returnItems: returnItems,
            returnPackages: returnPackages,
            foodReminders: foodReminders,
            careRoutines: careRoutines,
            careRoutineSteps: careRoutineSteps,
            careRoutineRuns: careRoutineRuns
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    @MainActor
    static func importData(
        _ data: Data,
        context: ModelContext,
        recordLocalSave: Bool = true,
        createRecoveryBackup: Bool = true
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        guard (1...currentBackupVersion).contains(envelope.version) else {
            throw CocoaError(.fileReadUnknown)
        }
        try validate(envelope)
        if createRecoveryBackup {
            _ = try createAutomaticRecoveryBackup(context: context, reason: "before-import")
        }

        do {
            try deleteAll(context: context, saveChanges: false, recordLocalSave: false)

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
        for value in envelope.solidFoods ?? [] {
            context.insert(SolidFoodCatalogItem(
                id: value.id,
                name: value.name,
                photoAttachmentID: value.photoAttachmentID,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
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
                startTimeZoneIdentifier: value.startTimeZoneIdentifier,
                endTimeZoneIdentifier: value.endTimeZoneIdentifier,
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
            event.solidReactionRawValue = value.solidReactionRawValue
            event.solidTextureRawValue = value.solidTextureRawValue
            event.solidFeedingStyleRawValue = value.solidFeedingStyleRawValue
            event.solidAllergenExposure = value.solidAllergenExposure
            event.solidSensitivityObserved = value.solidSensitivityObserved
            event.nursingSideRawValue = value.nursingSideRawValue
            event.activeNursingSideRawValue = value.activeNursingSideRawValue
            event.timerStateRawValue = value.timerStateRawValue
            event.timerAccumulatedSeconds = value.timerAccumulatedSeconds
            event.activeTimerSegmentStartDate = value.activeTimerSegmentStartDate
            event.leftDurationSeconds = value.leftDurationSeconds
            event.rightDurationSeconds = value.rightDurationSeconds
            event.diaperKindRawValue = value.diaperKindRawValue
            event.diaperRash = value.diaperRash
            event.childPottyKindRawValue = value.childPottyKindRawValue
            event.childPottyLocationRawValue = value.childPottyLocationRawValue
            event.childPottyAccident = value.childPottyAccident
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
                timeZoneIdentifier: value.timeZoneIdentifier,
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
                isFavorite: value.isFavorite ?? false,
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
        for value in envelope.homeTodoLists ?? [] {
            context.insert(HomeTodoList(
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
        for value in envelope.homeTodoItems ?? [] {
            context.insert(HomeTodoItem(
                id: value.id,
                householdID: value.householdID,
                todoListID: value.todoListID,
                title: value.title,
                notes: value.notes,
                isCompleted: value.isCompleted,
                addedBy: value.addedBy,
                completedBy: value.completedBy,
                completedAt: value.completedAt,
                lastReopenedAt: value.lastReopenedAt,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.packingTrips ?? [] {
            context.insert(PackingTrip(
                id: value.id,
                householdID: value.householdID,
                title: value.title,
                destinationName: value.destinationName,
                destinationDetail: value.destinationDetail,
                destinationLatitude: value.destinationLatitude,
                destinationLongitude: value.destinationLongitude,
                destinationTimeZoneIdentifier: value.destinationTimeZoneIdentifier,
                destinationStops: value.destinationStops ?? [],
                startDate: value.startDate,
                endDate: value.endDate,
                timeZoneIdentifier: value.timeZoneIdentifier,
                travelMode: PackingTravelMode(rawValue: value.travelModeRawValue) ?? .other,
                lodgingType: PackingLodgingType(rawValue: value.lodgingTypeRawValue) ?? .other,
                laundryAvailable: value.laundryAvailable,
                activities: Set(value.activitiesRawValue.split(separator: ",").compactMap {
                    PackingTripActivity(rawValue: String($0))
                }),
                notes: value.notes,
                status: PackingTripStatus(rawValue: value.statusRawValue) ?? .upcoming,
                weatherSuggestionsEnabled: value.weatherSuggestionsEnabled,
                reminderDate: value.reminderDate,
                finalCheckDate: value.finalCheckDate,
                createdBy: value.createdBy,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                completedAt: value.completedAt,
                isArchived: value.isArchived,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.tripTravelers ?? [] {
            context.insert(TripTraveler(
                id: value.id,
                householdID: value.householdID,
                tripID: value.tripID,
                kind: TripTravelerKind(rawValue: value.kindRawValue) ?? .adult,
                profileID: value.profileID,
                displayName: value.displayName,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.packingBags ?? [] {
            context.insert(PackingBag(
                id: value.id,
                householdID: value.householdID,
                tripID: value.tripID,
                travelerID: value.travelerID,
                name: value.name,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder
            ))
        }
        let importedShoppingItemsByID = Dictionary(
            (envelope.shoppingListItems ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for value in envelope.packingItems ?? [] {
            let relatedShoppingItemID: UUID?
            if let relatedID = value.relatedShoppingItemID,
               importedShoppingItemsByID[relatedID]?.householdID == value.householdID {
                relatedShoppingItemID = relatedID
            } else {
                relatedShoppingItemID = nil
            }
            context.insert(PackingItem(
                id: value.id,
                householdID: value.householdID,
                tripID: value.tripID,
                travelerID: value.travelerID,
                bagID: value.bagID,
                templateKey: value.templateKey,
                title: value.title,
                category: PackingItemCategory(rawValue: value.categoryRawValue) ?? .other,
                quantity: value.quantity,
                unit: value.unit,
                notes: value.notes,
                priority: PackingItemPriority(rawValue: value.priorityRawValue) ?? .normal,
                state: PackingItemState(rawValue: value.stateRawValue) ?? .needed,
                needsPurchase: value.needsPurchase,
                relatedShoppingItemID: relatedShoppingItemID,
                addedBy: value.addedBy,
                assignedCaregiverName: value.assignedCaregiverName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                caregiverReminderEnabled: value.caregiverReminderEnabled ?? true,
                packedBy: value.packedBy,
                packedAt: value.packedAt,
                lastUnpackedAt: value.lastUnpackedAt,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder
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
        for value in envelope.returnRequests ?? [] {
            context.insert(ReturnRequest(
                id: value.id,
                householdID: value.householdID,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                completedAt: value.completedAt,
                isArchived: value.isArchived,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.returnItems ?? [] {
            context.insert(ReturnItem(
                id: value.id,
                householdID: value.householdID,
                returnRequestID: value.returnRequestID,
                packageID: value.packageID,
                name: value.name,
                quantity: value.quantity,
                reason: value.reason,
                returnURLString: value.returnURLString,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.returnPackages ?? [] {
            context.insert(ReturnPackage(
                id: value.id,
                householdID: value.householdID,
                returnRequestID: value.returnRequestID,
                name: value.name,
                carrier: ReturnPackageCarrier(rawValue: value.carrierRawValue) ?? .other,
                method: ReturnPackageMethod(rawValue: value.methodRawValue) ?? .unknown,
                trackingNumber: value.trackingNumber,
                returnByDate: value.returnByDate,
                photoAttachmentIDs: value.photoAttachmentIDs ?? [],
                droppedOffAt: value.droppedOffAt,
                completedAt: value.completedAt,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.foodReminders ?? [] {
            context.insert(FoodReminder(
                id: value.id,
                householdID: value.householdID,
                type: FoodReminderType(rawValue: value.typeRawValue) ?? .custom,
                title: value.title,
                relatedTodoListID: value.relatedTodoListID,
                relatedShoppingListID: value.relatedShoppingListID,
                relatedMealPrepItemID: value.relatedMealPrepItemID,
                relatedReturnRequestID: value.relatedReturnRequestID,
                dateTime: value.dateTime,
                timeZoneIdentifier: value.timeZoneIdentifier,
                isEnabled: value.isEnabled,
                recurrence: value.recurrence,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.careRoutines ?? [] {
            let scope = CareRoutineScope(rawValue: value.scopeRawValue) ?? .profile
            context.insert(CareRoutine(
                id: value.id,
                scope: scope,
                profileType: value.profileTypeRawValue.flatMap(CareProfileType.init(rawValue:)),
                profileID: scope == .profile ? value.profileID ?? fallbackProfileID : value.profileID,
                householdID: value.householdID,
                title: value.title,
                notes: value.notes,
                iconName: value.iconName,
                tintName: value.tintName,
                templateKind: value.templateKindRawValue.flatMap(CareRoutineTemplateKind.init(rawValue:)),
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                isArchived: value.isArchived,
                sortOrder: value.sortOrder,
                reminderEnabled: value.reminderEnabled,
                reminderTimeMinutesAfterMidnight: value.reminderTimeMinutesAfterMidnight,
                lastStartedAt: value.lastStartedAt,
                lastCompletedAt: value.lastCompletedAt
            ))
        }
        for value in envelope.careRoutineSteps ?? [] {
            context.insert(CareRoutineStep(
                id: value.id,
                routineID: value.routineID,
                title: value.title,
                notes: value.notes,
                action: CareRoutineStepAction(rawValue: value.actionRawValue) ?? .checklist,
                eventType: value.eventTypeRawValue.map(EventType.normalized(rawValue:)),
                activityType: value.activityTypeRawValue.flatMap(ActivityType.init(rawValue:)),
                nursingSide: value.nursingSideRawValue.flatMap(NursingSide.init(rawValue:)),
                sleepKind: value.sleepKindRawValue.flatMap(SleepKind.init(rawValue:)),
                sortOrder: value.sortOrder,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.careRoutineRuns ?? [] {
            let routineScope = (envelope.careRoutines ?? [])
                .first { $0.id == value.routineID }
                .flatMap { CareRoutineScope(rawValue: $0.scopeRawValue) } ?? .profile
            let run = CareRoutineRun(
                id: value.id,
                routineID: value.routineID,
                profileID: routineScope == .profile ? value.profileID ?? fallbackProfileID : value.profileID,
                householdID: value.householdID,
                state: CareRoutineRunState(rawValue: value.stateRawValue) ?? .active,
                startedAt: value.startedAt,
                completedAt: value.completedAt,
                cancelledAt: value.cancelledAt,
                startedByCaregiverName: value.startedByCaregiverName,
                completedByCaregiverName: value.completedByCaregiverName,
                cancelledByCaregiverName: value.cancelledByCaregiverName,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            )
            run.completedStepIDsData = value.completedStepIDsData
            run.skippedStepIDsData = value.skippedStepIDsData
            run.stepResolutionRecordsData = value.stepResolutionRecordsData
            context.insert(run)
        }
            CloudKitFamilySyncConflictResolver.resolveDuplicateActiveTimers(in: context)
            _ = try LegacyTrackerGrowthMigration.migrate(in: context, saveChanges: false)
            ProfileMigrationService.ensureProfilesAndAssignments(
                context: context,
                saveChanges: false
            )
            try context.save()
            if recordLocalSave {
                PersistenceService.recordLocalSave()
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    static func validateBackupData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        guard (1...currentBackupVersion).contains(envelope.version) else {
            throw CocoaError(.fileReadUnknown)
        }
        try validate(envelope)
    }

    @MainActor
    static func deleteAll(
        context: ModelContext,
        saveChanges: Bool = true,
        recordLocalSave: Bool = true
    ) throws {
        try deleteAll(CareRoutineRun.self, context: context)
        try deleteAll(CareRoutineStep.self, context: context)
        try deleteAll(CareRoutine.self, context: context)
        try deleteAll(FoodReminder.self, context: context)
        try deleteAll(PackingItem.self, context: context)
        try deleteAll(PackingBag.self, context: context)
        try deleteAll(TripTraveler.self, context: context)
        try deleteAll(PackingTrip.self, context: context)
        try deleteAll(ReturnPackage.self, context: context)
        try deleteAll(ReturnItem.self, context: context)
        try deleteAll(ReturnRequest.self, context: context)
        try deleteAll(MealPrepUsage.self, context: context)
        try deleteAll(MealPrepItem.self, context: context)
        try deleteAll(InventoryItem.self, context: context)
        try deleteAll(InventoryLocation.self, context: context)
        try deleteAll(FoodItem.self, context: context)
        try deleteAll(HomeTodoItem.self, context: context)
        try deleteAll(HomeTodoList.self, context: context)
        try deleteAll(ShoppingListItem.self, context: context)
        try deleteAll(ShoppingList.self, context: context)
        try deleteAll(FoodStoreSection.self, context: context)
        try deleteAll(FoodStore.self, context: context)
        try deleteAll(Household.self, context: context)
        try deleteAll(SolidFoodCatalogItem.self, context: context)
        try deleteAll(PhotoAttachment.self, context: context)
        try deleteAll(PredictionFactor.self, context: context)
        try deleteAll(SleepPredictionRecord.self, context: context)
        try deleteAll(BabyEvent.self, context: context)
        try deleteAll(DoctorAppointment.self, context: context)
        try deleteAll(MilestoneEntry.self, context: context)
        try deleteAll(AgeGuideReadState.self, context: context)
        try deleteAll(PuppyStageGuideReadState.self, context: context)
        try deleteAll(BabyProfile.self, context: context)
        guard saveChanges else { return }
        do {
            try context.save()
            if recordLocalSave {
                PersistenceService.recordLocalSave()
            }
        } catch {
            context.rollback()
            throw error
        }
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

    @MainActor
    @discardableResult
    static func createAutomaticRecoveryBackup(
        context: ModelContext,
        reason: String
    ) throws -> URL {
        let data = try exportData(context: context)
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let directory = baseDirectory
            .appendingPathComponent("LittleWindows", isDirectory: true)
            .appendingPathComponent("RecoveryBackups", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let safeReason = reason
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = directory
            .appendingPathComponent("little-windows-\(safeReason)-\(timestamp)")
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)

        let backups = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted {
            let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return first > second
        }
        for oldBackup in backups.dropFirst(recoveryBackupLimit) {
            try? fileManager.removeItem(at: oldBackup)
        }
        return url
    }

    static func automaticRecoveryBackups(
        fileManager: FileManager = .default
    ) -> [AutomaticRecoveryBackup] {
        let baseDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let directory = baseDirectory
            .appendingPathComponent("LittleWindows", isDirectory: true)
            .appendingPathComponent("RecoveryBackups", isDirectory: true)
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { url in
                let date = (try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ))?.contentModificationDate ?? .distantPast
                return AutomaticRecoveryBackup(url: url, createdAt: date)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func validatedRecoveryBackupData(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        try validateBackupData(data)
        return data
    }

    static func mergeFamilySyncData(
        base: Data?,
        local: Data,
        remote: Data,
        localChangedAt: Date?,
        remoteChangedAt: Date?
    ) throws -> Data {
        let baseObject = try base.map { try jsonObject(from: $0) }
        let localObject = try jsonObject(from: local)
        let remoteObject = try jsonObject(from: remote)
        var merged = remoteObject

        let collectionKeys = Set(localObject.compactMap { key, value in
            value is [Any] ? key : nil
        })
        .union(remoteObject.compactMap { key, value in value is [Any] ? key : nil })
        .union(baseObject?.compactMap { key, value in value is [Any] ? key : nil } ?? [])

        for key in collectionKeys {
            let baseRecords = recordsByID(baseObject?[key])
            let localRecords = recordsByID(localObject[key])
            let remoteRecords = recordsByID(remoteObject[key])
            let allIDs = Set(baseRecords.keys)
                .union(localRecords.keys)
                .union(remoteRecords.keys)
            let values = allIDs.compactMap { id -> [String: Any]? in
                mergedRecord(
                    base: baseRecords[id],
                    local: localRecords[id],
                    remote: remoteRecords[id],
                    localChangedAt: localChangedAt,
                    remoteChangedAt: remoteChangedAt
                )
            }
            .sorted { stringValue($0["id"]) < stringValue($1["id"]) }
            merged[key] = values
        }

        merged["version"] = max(
            currentBackupVersion,
            max(intValue(localObject["version"]), intValue(remoteObject["version"]))
        )
        merged["exportedAt"] = ISO8601DateFormatter().string(from: Date())
        return try JSONSerialization.data(
            withJSONObject: merged,
            options: [.sortedKeys]
        )
    }

    static func familySyncCanonicalData(from data: Data) throws -> Data {
        var object = try jsonObject(from: data)
        object.removeValue(forKey: "exportedAt")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func familySyncEntityPayloads(from data: Data) throws -> [String: Data] {
        let object = try jsonObject(from: data)
        var result: [String: Data] = [:]
        for (collection, value) in object {
            guard let records = value as? [Any] else { continue }
            for value in records {
                guard let record = value as? [String: Any],
                      let id = record["id"] as? String else {
                    continue
                }
                result[familySyncEntityKey(collection: collection, id: id)] = try JSONSerialization.data(
                    withJSONObject: record,
                    options: [.sortedKeys]
                )
            }
        }
        return result
    }

    static func familySyncData(
        template: Data,
        entityPayloads: [String: Data]
    ) throws -> Data {
        var object = try jsonObject(from: template)
        for (key, value) in object where value is [Any] {
            object[key] = []
        }
        for (key, payload) in entityPayloads {
            guard let parts = familySyncEntityKeyParts(key),
                  let record = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                continue
            }
            var values = object[parts.collection] as? [[String: Any]] ?? []
            values.append(record)
            object[parts.collection] = values
        }
        for (key, value) in object {
            guard let records = value as? [[String: Any]] else { continue }
            object[key] = records.sorted {
                stringValue($0["id"]) < stringValue($1["id"])
            }
        }
        object["version"] = currentBackupVersion
        object["exportedAt"] = ISO8601DateFormatter().string(from: Date())
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func familySyncEntityKey(collection: String, id: String) -> String {
        "\(collection)|\(id)"
    }

    static func familySyncEntityKeyParts(_ key: String) -> (collection: String, id: String)? {
        guard let separator = key.firstIndex(of: "|") else { return nil }
        return (
            String(key[..<separator]),
            String(key[key.index(after: separator)...])
        )
    }

    private static func validate(_ envelope: BackupEnvelope) throws {
        let profileIDs = Set(envelope.profiles.map(\.id))
        guard profileIDs.count == envelope.profiles.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let requiredCollections: [[UUID]] = [
            envelope.events.map(\.id),
            envelope.predictionRecords.map(\.id)
        ]
        guard requiredCollections.allSatisfy({ Set($0).count == $0.count }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let solidFoods = envelope.solidFoods,
           Set(solidFoods.map(\.id)).count != solidFoods.count {
            throw CocoaError(.fileReadCorruptFile)
        }
        let packingTrips = envelope.packingTrips ?? []
        let tripTravelers = envelope.tripTravelers ?? []
        let packingBags = envelope.packingBags ?? []
        let packingItems = envelope.packingItems ?? []
        let householdIDs = Set((envelope.households ?? []).map(\.id))
        let shoppingItemsByID = Dictionary(
            (envelope.shoppingListItems ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let tripIDs = Set(packingTrips.map(\.id))
        let travelerIDs = Set(tripTravelers.map(\.id))
        let bagIDs = Set(packingBags.map(\.id))
        let tripsByID = Dictionary(
            packingTrips.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let travelersByID = Dictionary(
            tripTravelers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let bagsByID = Dictionary(
            packingBags.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let bagNamesAreUnique = Dictionary(grouping: packingBags, by: \.tripID).values.allSatisfy { bags in
            let normalizedNames = bags.map {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            return !normalizedNames.contains("") && Set(normalizedNames).count == normalizedNames.count
        }
        guard tripIDs.count == packingTrips.count,
              travelerIDs.count == tripTravelers.count,
              bagIDs.count == packingBags.count,
              Set(packingItems.map(\.id)).count == packingItems.count,
              bagNamesAreUnique,
              packingTrips.allSatisfy({ trip in
                  let title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines)
                  let coordinatesAreValid: Bool
                  switch (trip.destinationLatitude, trip.destinationLongitude) {
                  case (nil, nil):
                      coordinatesAreValid = true
                  case (let latitude?, let longitude?):
                      coordinatesAreValid = latitude.isFinite
                          && longitude.isFinite
                          && (-90...90).contains(latitude)
                          && (-180...180).contains(longitude)
                  default:
                      coordinatesAreValid = false
                  }
                  let timeZonesAreValid = (trip.timeZoneIdentifier.map {
                      TimeZone(identifier: $0) != nil
                  } ?? true)
                      && (trip.destinationTimeZoneIdentifier.map {
                          TimeZone(identifier: $0) != nil
                      } ?? true)
                  let destinationStopsAreValid = TripPackingService.destinationStopsAreValid(
                      trip.destinationStops ?? [],
                      tripStartDate: trip.startDate,
                      tripEndDate: trip.endDate,
                      timeZoneIdentifier: trip.timeZoneIdentifier
                  )
                  return !title.isEmpty
                      && trip.endDate >= trip.startDate
                      && coordinatesAreValid
                      && timeZonesAreValid
                      && destinationStopsAreValid
                      && TripPackingService.reminderDatesAreValid(
                          reminderDate: trip.reminderDate,
                          finalCheckDate: trip.finalCheckDate
                      )
                      && (householdIDs.isEmpty || householdIDs.contains(trip.householdID))
              }),
              tripTravelers.allSatisfy({ traveler in
                  guard let trip = tripsByID[traveler.tripID] else { return false }
                  return traveler.householdID == trip.householdID
                      && !traveler.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && traveler.profileID.map(profileIDs.contains) != false
              }),
              packingBags.allSatisfy({ bag in
                  guard let trip = tripsByID[bag.tripID] else { return false }
                  return bag.householdID == trip.householdID
                      && bag.travelerID.map { travelerID in
                          travelersByID[travelerID]?.tripID == bag.tripID
                      } != false
              }),
              packingItems.allSatisfy({ item in
                  guard let trip = tripsByID[item.tripID] else { return false }
                  let relatedShoppingItemIsValid = item.relatedShoppingItemID.map { relatedID in
                      guard let related = shoppingItemsByID[relatedID] else { return true }
                      return related.householdID == item.householdID
                  } ?? true
                  return item.householdID == trip.householdID
                      && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && (item.assignedCaregiverName.map {
                          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      } ?? true)
                      && TripPackingService.isValidQuantity(item.quantity)
                      && item.travelerID.map { travelerID in
                          travelersByID[travelerID]?.tripID == item.tripID
                      } != false
                      && item.bagID.map { bagID in
                          bagsByID[bagID]?.tripID == item.tripID
                      } != false
                      && relatedShoppingItemIsValid
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    private static func recordsByID(_ value: Any?) -> [String: [String: Any]] {
        guard let values = value as? [Any] else { return [:] }
        var result: [String: [String: Any]] = [:]
        for value in values {
            guard let record = value as? [String: Any],
                  let id = record["id"] as? String else {
                continue
            }
            result[id] = record
        }
        return result
    }

    private static func mergedRecord(
        base: [String: Any]?,
        local: [String: Any]?,
        remote: [String: Any]?,
        localChangedAt: Date?,
        remoteChangedAt: Date?
    ) -> [String: Any]? {
        switch (base, local, remote) {
        case (_, nil, nil):
            return nil
        case (nil, let local?, nil):
            return local
        case (nil, nil, let remote?):
            return remote
        case (nil, let local?, let remote?):
            return newer(local, remote)
        case (let base?, let local?, let remote?):
            let localChanged = !recordsEqual(local, base)
            let remoteChanged = !recordsEqual(remote, base)
            if !localChanged { return remote }
            if !remoteChanged { return local }
            return newer(local, remote)
        case (let base?, let local?, nil):
            guard !recordsEqual(local, base) else { return nil }
            return recordDate(local) > (remoteChangedAt ?? .distantPast) ? local : nil
        case (let base?, nil, let remote?):
            guard !recordsEqual(remote, base) else { return nil }
            return (localChangedAt ?? .distantPast) > recordDate(remote) ? nil : remote
        }
    }

    private static func newer(
        _ first: [String: Any],
        _ second: [String: Any]
    ) -> [String: Any] {
        let firstDate = recordDate(first)
        let secondDate = recordDate(second)
        if firstDate != secondDate { return firstDate > secondDate ? first : second }
        return stringValue(first["id"]) <= stringValue(second["id"]) ? first : second
    }

    private static func recordDate(_ record: [String: Any]) -> Date {
        guard let value = record["updatedAt"] as? String else { return .distantPast }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? .distantPast
    }

    private static func recordsEqual(
        _ first: [String: Any],
        _ second: [String: Any]
    ) -> Bool {
        NSDictionary(dictionary: first).isEqual(to: second)
    }

    private static func stringValue(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private static func intValue(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
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
    static func migrate(
        in context: ModelContext,
        saveChanges: Bool = true
    ) throws -> Int {
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
                  event.occursOnLocalDay(profile.birthDate) else {
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

        if migratedCount > 0, saveChanges {
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
