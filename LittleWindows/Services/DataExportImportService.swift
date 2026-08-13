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
    var caregiverIdentity: CaregiverIdentityDTO?
    var profiles: [ProfileDTO]
    var photoAttachments: [PhotoAttachmentDTO]?
    var solidFoods: [SolidFoodCatalogItemDTO]?
    var customSolidRecipes: [CustomSolidRecipeDTO]?
    var solidsProfileStates: [SolidsProfileStateDTO]?
    var solidFoodProgress: [SolidFoodProgressDTO]?
    var solidFoodEventItems: [SolidFoodEventItemDTO]?
    var solidAllergenProgress: [SolidAllergenProgressDTO]?
    var plannedSolidMeals: [PlannedSolidMealDTO]?
    var events: [EventDTO]
    var predictionRecords: [PredictionRecordDTO]
    var milestones: [MilestoneDTO]?
    var appointments: [AppointmentDTO]?
    var appointmentFollowUps: [AppointmentFollowUpDTO]?
    var attentionAcknowledgements: [AttentionAcknowledgementDTO]?
    var attentionClaims: [AttentionClaimDTO]?
    var caregiverHandoffNotes: [CaregiverHandoffNoteDTO]?
    var familyCaregiverIdentities: [FamilyCaregiverIdentityDTO]?
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
    var tripItineraryChoiceGroups: [TripItineraryChoiceGroupDTO]?
    var tripItineraryItems: [TripItineraryItemDTO]?
    var tripItineraryLinks: [TripItineraryLinkDTO]?
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
    var medications: [MedicationDTO]?
    var medicationRegimens: [MedicationRegimenDTO]?
    var medicationSchedulePhases: [MedicationSchedulePhaseDTO]?
    var medicationDoseRecords: [MedicationDoseRecordDTO]?
    var medicationSupplyLogs: [MedicationSupplyLogDTO]?
}

private struct CaregiverIdentityDTO: Codable {
    var currentName: String?
    var primaryName: String?
}

private struct ProfileDTO: Codable {
    var id: UUID
    var profileTypeRawValue: String?
    var name: String
    var birthDate: Date?
    var sexRawValue: String?
    var adultRelationshipRawValue: String?
    var sharingScopeRawValue: String?
    var ownerIdentifier: String?
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
    var allergenIDsJSON: String?
    var minimumAgeMonths: Int?
    var preparationNotes: String?
    var safetyNotes: String?
    var nutritionLabelJSON: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct CustomSolidRecipeDTO: Codable {
    var id: UUID
    var name: String
    var ingredientsJSON: String
    var servings: Double
    var minimumAgeMonths: Int
    var instructions: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}

private struct SolidsProfileStateDTO: Codable {
    var id: UUID
    var profileID: UUID
    var isActivated: Bool
    var startedAt: Date?
    var readinessNotes: String
    var guidedStartDate: Date?
    var favoriteRecipeIDsJSON: String?
    var wantToTryRecipeIDsJSON: String?
    var recipeCollectionsJSON: String?
    var completedFeedingSkillIDsJSON: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct SolidFoodProgressDTO: Codable {
    var id: UUID
    var profileID: UUID
    var foodID: String
    var foodNameSnapshot: String
    var statusRawValue: String
    var isFavorite: Bool
    var firstTriedAt: Date?
    var lastTriedAt: Date?
    var exposureCount: Int
    var lastReactionRawValue: String?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}

private struct SolidFoodEventItemDTO: Codable {
    var id: UUID
    var eventID: UUID
    var profileID: UUID
    var foodID: String
    var foodNameSnapshot: String
    var allergenIDsJSON: String
    var confirmedAllergenPortionIDsJSON: String?
    var reactionRawValue: String?
    var servingAmount: String?
    var amountOffered: Double?
    var amountEaten: Double?
    var portionUnitRawValue: String?
    var consumptionEstimateRawValue: String?
    var nutritionSnapshotJSON: String?
    var recipeID: String?
    var recipeNameSnapshot: String?
    var notes: String?
    var suspectedReaction: Bool?
    var symptomIDsJSON: String?
    var severityRawValue: String?
    var onsetMinutes: Int?
    var durationMinutes: Int?
    var responseNotes: String?
    var followUpRawValue: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct SolidAllergenProgressDTO: Codable {
    var id: UUID
    var profileID: UUID
    var allergenID: String
    var statusRawValue: String
    var statusOverrideRawValue: String?
    var introductionStep: Int
    var exposureMealCount: Int
    var firstIntroducedAt: Date?
    var lastExposureAt: Date?
    var nextExposureDueAt: Date?
    var reminderEnabled: Bool
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}

private struct PlannedSolidMealDTO: Codable {
    var id: UUID
    var profileID: UUID
    var scheduledAt: Date
    var title: String
    var foodIDsJSON: String
    var foodNamesJSON: String
    var notes: String
    var completedEventID: UUID?
    var recipeID: String?
    var isGuided: Bool?
    var guidedPosition: Int?
    var allergenID: String?
    var allergenIntroductionStep: Int?
    var allergenServingGuidance: String?
    var allergenObservationMinutes: Int?
    var reminderEnabled: Bool?
    var reminderOffsetMinutes: Int?
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
    var solidFoodDetailsJSON: String?
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
    var healthObservationDetailsData: Data?
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

private struct AppointmentFollowUpDTO: Codable {
    var id: UUID
    var appointmentID: UUID
    var householdID: UUID
    var profileID: UUID?
    var title: String
    var details: String?
    var dueDate: Date?
    var completedAt: Date?
    var completedByCaregiverIdentifier: String?
    var completedByCaregiverName: String?
    var createdByCaregiverIdentifier: String?
    var createdByCaregiverName: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct AttentionAcknowledgementDTO: Codable {
    var id: UUID
    var householdID: UUID
    var profileID: UUID?
    var sourceKey: String
    var sourceUpdatedAt: Date
    var caregiverIdentifier: String
    var caregiverName: String
    var acknowledgedAt: Date
    var updatedAt: Date
}

private struct AttentionClaimDTO: Codable {
    var id: UUID
    var householdID: UUID
    var profileID: UUID?
    var sourceKey: String
    var caregiverIdentifier: String?
    var caregiverName: String?
    var updatedByCaregiverIdentifier: String
    var updatedByCaregiverName: String
    var createdAt: Date
    var updatedAt: Date
}

private struct CaregiverHandoffNoteDTO: Codable {
    var id: UUID
    var householdID: UUID
    var profileID: UUID?
    var sourceKey: String?
    var sourceTitleSnapshot: String?
    var body: String
    var authorCaregiverIdentifier: String
    var authorCaregiverName: String
    var createdAt: Date
    var updatedAt: Date
}

private struct FamilyCaregiverIdentityDTO: Codable {
    var id: UUID
    var householdID: UUID
    var caregiverIdentifier: String
    var displayName: String
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date
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
    var assignedCaregiverName: String?
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

private struct TripItineraryChoiceGroupDTO: Codable {
    var id: UUID
    var householdID: UUID
    var tripID: UUID
    var title: String
    var notes: String?
    var scheduledDay: Date?
    var selectedItemID: UUID?
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
}

private struct TripItineraryItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var tripID: UUID
    var choiceGroupID: UUID?
    var title: String
    var kindRawValue: String
    var scheduleKindRawValue: String
    var scheduledDay: Date?
    var startDate: Date?
    var endDate: Date?
    var startTimeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var location: TripDestinationSelection?
    var origin: TripDestinationSelection?
    var notes: String?
    var bookingStatusRawValue: String
    var providerName: String?
    var confirmationNumber: String?
    var isCompleted: Bool
    var assignedCaregiverName: String?
    var reminderEnabled: Bool
    var reminderOffsetMinutes: Int
    var createdBy: String?
    var completedBy: String?
    var completedAt: Date?
    var lastReopenedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
}

private struct TripItineraryLinkDTO: Codable {
    var id: UUID
    var householdID: UUID
    var tripID: UUID
    var itineraryItemID: UUID?
    var title: String
    var urlString: String
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
}

private struct FoodItemDTO: Codable {
    var id: UUID
    var householdID: UUID
    var canonicalName: String
    var foodReferenceID: String?
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

private struct MedicationDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var name: String
    var formRawValue: String
    var strength: Double?
    var strengthUnit: String
    var routeRawValue: String
    var instructions: String
    var reasonForTaking: String
    var prescriber: String
    var pharmacy: String
    var currentSupply: Double?
    var refillThreshold: Double?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
}

private struct MedicationRegimenDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var medicationID: UUID
    var scheduleKindRawValue: String
    var startDate: Date
    var endDate: Date?
    var doseAmount: Double
    var doseUnit: String
    var doseTimesData: Data?
    var weekdayMask: Int
    var intervalDays: Int
    var cycleOnDays: Int
    var cycleOffDays: Int
    var minimumHoursBetweenDoses: Double?
    var maximumDosesPerDay: Int?
    var remindersEnabled: Bool
    var followUpRemindersEnabled: Bool?
    var reminderLeadMinutes: Int
    var timeZoneBehaviorRawValue: String
    var timeZoneIdentifier: String?
    var instructions: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
}

private struct MedicationSchedulePhaseDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var regimenID: UUID
    var sequence: Int
    var durationDays: Int?
    var doseAmount: Double
    var doseUnit: String
    var doseTimesData: Data?
    var createdAt: Date
    var updatedAt: Date
}

private struct MedicationDoseRecordDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var medicationID: UUID
    var regimenID: UUID?
    var phaseID: UUID?
    var occurrenceKey: String?
    var scheduledAt: Date?
    var statusRawValue: String
    var loggedAt: Date
    var takenAt: Date?
    var doseAmount: Double
    var doseUnit: String
    var supplyAdjustmentApplied: Double
    var caregiverIdentifier: String
    var caregiverName: String
    var notes: String
    var careEventID: UUID?
    var updatedAt: Date
}

private struct MedicationSupplyLogDTO: Codable {
    var id: UUID
    var profileID: UUID?
    var medicationID: UUID
    var doseRecordID: UUID?
    var adjustment: Double
    var resultingSupply: Double?
    var reasonRawValue: String
    var notes: String
    var loggedAt: Date
    var caregiverIdentifier: String
    var caregiverName: String
}

enum CareDataExportProfileScope: Equatable {
    case all
    case familyShared
}

enum DataExportImportService {
    private static let currentBackupVersion = 27
    private static let recoveryBackupLimit = 3

    static func exportData(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        includeCaregiverIdentity: Bool = true,
        profileScope: CareDataExportProfileScope = .all
    ) throws -> Data {
        let profiles = try context.fetch(FetchDescriptor<CareProfile>()).map {
            ProfileDTO(
                id: $0.id,
                profileTypeRawValue: $0.profileTypeRawValue,
                name: $0.name,
                birthDate: $0.birthDate,
                sexRawValue: $0.sexRawValue,
                adultRelationshipRawValue: $0.adultRelationshipRawValue,
                sharingScopeRawValue: $0.sharingScopeRawValue,
                ownerIdentifier: $0.ownerIdentifier,
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
                allergenIDsJSON: $0.allergenIDsJSON,
                minimumAgeMonths: $0.minimumAgeMonths,
                preparationNotes: $0.preparationNotes,
                safetyNotes: $0.safetyNotes,
                nutritionLabelJSON: $0.nutritionLabelJSON,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let customSolidRecipes = try context.fetch(FetchDescriptor<CustomSolidRecipe>()).map {
            CustomSolidRecipeDTO(
                id: $0.id,
                name: $0.name,
                ingredientsJSON: $0.ingredientsJSON,
                servings: $0.servings,
                minimumAgeMonths: $0.minimumAgeMonths,
                instructions: $0.instructions,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let solidsProfileStates = try context.fetch(FetchDescriptor<SolidsProfileState>()).map {
            SolidsProfileStateDTO(
                id: $0.id,
                profileID: $0.profileID,
                isActivated: $0.isActivated,
                startedAt: $0.startedAt,
                readinessNotes: $0.readinessNotes,
                guidedStartDate: $0.guidedStartDate,
                favoriteRecipeIDsJSON: $0.favoriteRecipeIDsJSON,
                wantToTryRecipeIDsJSON: $0.wantToTryRecipeIDsJSON,
                recipeCollectionsJSON: $0.recipeCollectionsJSON,
                completedFeedingSkillIDsJSON: $0.completedFeedingSkillIDsJSON,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let solidFoodProgress = try context.fetch(FetchDescriptor<SolidFoodProgress>()).map {
            SolidFoodProgressDTO(
                id: $0.id,
                profileID: $0.profileID,
                foodID: $0.foodID,
                foodNameSnapshot: $0.foodNameSnapshot,
                statusRawValue: $0.statusRawValue,
                isFavorite: $0.isFavorite,
                firstTriedAt: $0.firstTriedAt,
                lastTriedAt: $0.lastTriedAt,
                exposureCount: $0.exposureCount,
                lastReactionRawValue: $0.lastReactionRawValue,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let solidFoodEventItems = try context.fetch(FetchDescriptor<SolidFoodEventItem>()).map {
            SolidFoodEventItemDTO(
                id: $0.id,
                eventID: $0.eventID,
                profileID: $0.profileID,
                foodID: $0.foodID,
                foodNameSnapshot: $0.foodNameSnapshot,
                allergenIDsJSON: $0.allergenIDsJSON,
                confirmedAllergenPortionIDsJSON: $0.confirmedAllergenPortionIDsJSON,
                reactionRawValue: $0.reactionRawValue,
                servingAmount: $0.servingAmount,
                amountOffered: $0.amountOffered,
                amountEaten: $0.amountEaten,
                portionUnitRawValue: $0.portionUnitRawValue,
                consumptionEstimateRawValue: $0.consumptionEstimateRawValue,
                nutritionSnapshotJSON: $0.nutritionSnapshotJSON,
                recipeID: $0.recipeID,
                recipeNameSnapshot: $0.recipeNameSnapshot,
                notes: $0.notes,
                suspectedReaction: $0.suspectedReaction,
                symptomIDsJSON: $0.symptomIDsJSON,
                severityRawValue: $0.severityRawValue,
                onsetMinutes: $0.onsetMinutes,
                durationMinutes: $0.durationMinutes,
                responseNotes: $0.responseNotes,
                followUpRawValue: $0.followUpRawValue,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let solidAllergenProgress = try context.fetch(FetchDescriptor<SolidAllergenProgress>()).map {
            SolidAllergenProgressDTO(
                id: $0.id,
                profileID: $0.profileID,
                allergenID: $0.allergenID,
                statusRawValue: $0.statusRawValue,
                statusOverrideRawValue: $0.statusOverrideRawValue,
                introductionStep: $0.introductionStep,
                exposureMealCount: $0.exposureMealCount,
                firstIntroducedAt: $0.firstIntroducedAt,
                lastExposureAt: $0.lastExposureAt,
                nextExposureDueAt: $0.nextExposureDueAt,
                reminderEnabled: $0.reminderEnabled,
                notes: $0.notes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let plannedSolidMeals = try context.fetch(FetchDescriptor<PlannedSolidMeal>()).map {
            PlannedSolidMealDTO(
                id: $0.id,
                profileID: $0.profileID,
                scheduledAt: $0.scheduledAt,
                title: $0.title,
                foodIDsJSON: $0.foodIDsJSON,
                foodNamesJSON: $0.foodNamesJSON,
                notes: $0.notes,
                completedEventID: $0.completedEventID,
                recipeID: $0.recipeID,
                isGuided: $0.isGuided,
                guidedPosition: $0.guidedPosition,
                allergenID: $0.allergenID,
                allergenIntroductionStep: $0.allergenIntroductionStep,
                allergenServingGuidance: $0.allergenServingGuidance,
                allergenObservationMinutes: $0.allergenObservationMinutes,
                reminderEnabled: $0.reminderEnabled,
                reminderOffsetMinutes: $0.reminderOffsetMinutes,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let events = try context.fetch(FetchDescriptor<CareEvent>()).map {
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
                solidFoodDetailsJSON: $0.solidFoodDetailsJSON,
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
                dogDetailsData: $0.dogDetailsData,
                healthObservationDetailsData: $0.healthObservationDetailsData
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
        let appointmentFollowUps = try context.fetch(FetchDescriptor<AppointmentFollowUp>()).map {
            AppointmentFollowUpDTO(
                id: $0.id,
                appointmentID: $0.appointmentID,
                householdID: $0.householdID,
                profileID: $0.profileID,
                title: $0.title,
                details: $0.details,
                dueDate: $0.dueDate,
                completedAt: $0.completedAt,
                completedByCaregiverIdentifier: $0.completedByCaregiverIdentifier,
                completedByCaregiverName: $0.completedByCaregiverName,
                createdByCaregiverIdentifier: $0.createdByCaregiverIdentifier,
                createdByCaregiverName: $0.createdByCaregiverName,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let attentionAcknowledgements = try context.fetch(
            FetchDescriptor<HouseholdAttentionAcknowledgement>()
        ).map {
            AttentionAcknowledgementDTO(
                id: $0.id,
                householdID: $0.householdID,
                profileID: $0.profileID,
                sourceKey: $0.sourceKey,
                sourceUpdatedAt: $0.sourceUpdatedAt,
                caregiverIdentifier: $0.caregiverIdentifier,
                caregiverName: $0.caregiverName,
                acknowledgedAt: $0.acknowledgedAt,
                updatedAt: $0.updatedAt
            )
        }
        let attentionClaims = try context.fetch(FetchDescriptor<HouseholdAttentionClaim>()).map {
            AttentionClaimDTO(
                id: $0.id,
                householdID: $0.householdID,
                profileID: $0.profileID,
                sourceKey: $0.sourceKey,
                caregiverIdentifier: $0.caregiverIdentifier,
                caregiverName: $0.caregiverName,
                updatedByCaregiverIdentifier: $0.updatedByCaregiverIdentifier,
                updatedByCaregiverName: $0.updatedByCaregiverName,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let caregiverHandoffNotes = try context.fetch(FetchDescriptor<CaregiverHandoffNote>()).map {
            CaregiverHandoffNoteDTO(
                id: $0.id,
                householdID: $0.householdID,
                profileID: $0.profileID,
                sourceKey: $0.sourceKey,
                sourceTitleSnapshot: $0.sourceTitleSnapshot,
                body: $0.body,
                authorCaregiverIdentifier: $0.authorCaregiverIdentifier,
                authorCaregiverName: $0.authorCaregiverName,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let familyCaregiverIdentities = try context.fetch(FetchDescriptor<FamilyCaregiverIdentity>()).map {
            FamilyCaregiverIdentityDTO(
                id: $0.id,
                householdID: $0.householdID,
                caregiverIdentifier: $0.caregiverIdentifier,
                displayName: $0.displayName,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                lastSeenAt: $0.lastSeenAt
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
                assignedCaregiverName: $0.assignedCaregiverName,
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
        let tripItineraryChoiceGroups = try context.fetch(
            FetchDescriptor<TripItineraryChoiceGroup>()
        ).map {
            TripItineraryChoiceGroupDTO(
                id: $0.id,
                householdID: $0.householdID,
                tripID: $0.tripID,
                title: $0.title,
                notes: $0.notes,
                scheduledDay: $0.scheduledDay,
                selectedItemID: $0.selectedItemID,
                createdBy: $0.createdBy,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder
            )
        }
        let tripItineraryItems = try context.fetch(FetchDescriptor<TripItineraryItem>()).map {
            TripItineraryItemDTO(
                id: $0.id,
                householdID: $0.householdID,
                tripID: $0.tripID,
                choiceGroupID: $0.choiceGroupID,
                title: $0.title,
                kindRawValue: $0.kindRawValue,
                scheduleKindRawValue: $0.scheduleKindRawValue,
                scheduledDay: $0.scheduledDay,
                startDate: $0.startDate,
                endDate: $0.endDate,
                startTimeZoneIdentifier: $0.startTimeZoneIdentifier,
                endTimeZoneIdentifier: $0.endTimeZoneIdentifier,
                location: $0.location,
                origin: $0.origin,
                notes: $0.notes,
                bookingStatusRawValue: $0.bookingStatusRawValue,
                providerName: $0.providerName,
                confirmationNumber: $0.confirmationNumber,
                isCompleted: $0.isCompleted,
                assignedCaregiverName: $0.assignedCaregiverName,
                reminderEnabled: $0.reminderEnabled,
                reminderOffsetMinutes: $0.reminderOffsetMinutes,
                createdBy: $0.createdBy,
                completedBy: $0.completedBy,
                completedAt: $0.completedAt,
                lastReopenedAt: $0.lastReopenedAt,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                sortOrder: $0.sortOrder
            )
        }
        let tripItineraryLinks = try context.fetch(FetchDescriptor<TripItineraryLink>()).map {
            TripItineraryLinkDTO(
                id: $0.id,
                householdID: $0.householdID,
                tripID: $0.tripID,
                itineraryItemID: $0.itineraryItemID,
                title: $0.title,
                urlString: $0.urlString,
                createdBy: $0.createdBy,
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
                foodReferenceID: $0.foodReferenceID,
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
        let medications = try context.fetch(FetchDescriptor<Medication>()).map {
            MedicationDTO(
                id: $0.id,
                profileID: $0.profileID,
                name: $0.name,
                formRawValue: $0.formRawValue,
                strength: $0.strength,
                strengthUnit: $0.strengthUnit,
                routeRawValue: $0.routeRawValue,
                instructions: $0.instructions,
                reasonForTaking: $0.reasonForTaking,
                prescriber: $0.prescriber,
                pharmacy: $0.pharmacy,
                currentSupply: $0.currentSupply,
                refillThreshold: $0.refillThreshold,
                isArchived: $0.isArchived,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let medicationRegimens = try context.fetch(FetchDescriptor<MedicationRegimen>()).map {
            MedicationRegimenDTO(
                id: $0.id,
                profileID: $0.profileID,
                medicationID: $0.medicationID,
                scheduleKindRawValue: $0.scheduleKindRawValue,
                startDate: $0.startDate,
                endDate: $0.endDate,
                doseAmount: $0.doseAmount,
                doseUnit: $0.doseUnit,
                doseTimesData: $0.doseTimesData,
                weekdayMask: $0.weekdayMask,
                intervalDays: $0.intervalDays,
                cycleOnDays: $0.cycleOnDays,
                cycleOffDays: $0.cycleOffDays,
                minimumHoursBetweenDoses: $0.minimumHoursBetweenDoses,
                maximumDosesPerDay: $0.maximumDosesPerDay,
                remindersEnabled: $0.remindersEnabled,
                followUpRemindersEnabled: $0.followUpRemindersEnabled,
                reminderLeadMinutes: $0.reminderLeadMinutes,
                timeZoneBehaviorRawValue: $0.timeZoneBehaviorRawValue,
                timeZoneIdentifier: $0.timeZoneIdentifier,
                instructions: $0.instructions,
                isActive: $0.isActive,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let medicationSchedulePhases = try context.fetch(FetchDescriptor<MedicationSchedulePhase>()).map {
            MedicationSchedulePhaseDTO(
                id: $0.id,
                profileID: $0.profileID,
                regimenID: $0.regimenID,
                sequence: $0.sequence,
                durationDays: $0.durationDays,
                doseAmount: $0.doseAmount,
                doseUnit: $0.doseUnit,
                doseTimesData: $0.doseTimesData,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let medicationDoseRecords = try context.fetch(FetchDescriptor<MedicationDoseRecord>()).map {
            MedicationDoseRecordDTO(
                id: $0.id,
                profileID: $0.profileID,
                medicationID: $0.medicationID,
                regimenID: $0.regimenID,
                phaseID: $0.phaseID,
                occurrenceKey: $0.occurrenceKey,
                scheduledAt: $0.scheduledAt,
                statusRawValue: $0.statusRawValue,
                loggedAt: $0.loggedAt,
                takenAt: $0.takenAt,
                doseAmount: $0.doseAmount,
                doseUnit: $0.doseUnit,
                supplyAdjustmentApplied: $0.supplyAdjustmentApplied,
                caregiverIdentifier: $0.caregiverIdentifier,
                caregiverName: $0.caregiverName,
                notes: $0.notes,
                careEventID: $0.careEventID,
                updatedAt: $0.updatedAt
            )
        }
        let medicationSupplyLogs = try context.fetch(FetchDescriptor<MedicationSupplyLog>()).map {
            MedicationSupplyLogDTO(
                id: $0.id,
                profileID: $0.profileID,
                medicationID: $0.medicationID,
                doseRecordID: $0.doseRecordID,
                adjustment: $0.adjustment,
                resultingSupply: $0.resultingSupply,
                reasonRawValue: $0.reasonRawValue,
                notes: $0.notes,
                loggedAt: $0.loggedAt,
                caregiverIdentifier: $0.caregiverIdentifier,
                caregiverName: $0.caregiverName
            )
        }
        let caregiverIdentity: CaregiverIdentityDTO?
        if includeCaregiverIdentity {
            let currentName = defaults.string(
                forKey: CaregiverIdentityService.currentCaregiverNameKey
            )?.nilIfBlank
            let primaryName = defaults.string(
                forKey: CaregiverIdentityService.primaryCaregiverNameKey
            )?.nilIfBlank
            caregiverIdentity = if currentName != nil || primaryName != nil {
                CaregiverIdentityDTO(
                    currentName: currentName,
                    primaryName: primaryName
                )
            } else {
                nil
            }
        } else {
            caregiverIdentity = nil
        }
        var envelope = BackupEnvelope(
            version: currentBackupVersion,
            exportedAt: Date(),
            caregiverIdentity: caregiverIdentity,
            profiles: profiles,
            photoAttachments: photoAttachments,
            solidFoods: solidFoods,
            customSolidRecipes: customSolidRecipes,
            solidsProfileStates: solidsProfileStates,
            solidFoodProgress: solidFoodProgress,
            solidFoodEventItems: solidFoodEventItems,
            solidAllergenProgress: solidAllergenProgress,
            plannedSolidMeals: plannedSolidMeals,
            events: events,
            predictionRecords: records,
            milestones: milestones,
            appointments: appointments,
            appointmentFollowUps: appointmentFollowUps,
            attentionAcknowledgements: attentionAcknowledgements,
            attentionClaims: attentionClaims,
            caregiverHandoffNotes: caregiverHandoffNotes,
            familyCaregiverIdentities: familyCaregiverIdentities,
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
            tripItineraryChoiceGroups: tripItineraryChoiceGroups,
            tripItineraryItems: tripItineraryItems,
            tripItineraryLinks: tripItineraryLinks,
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
            careRoutineRuns: careRoutineRuns,
            medications: medications,
            medicationRegimens: medicationRegimens,
            medicationSchedulePhases: medicationSchedulePhases,
            medicationDoseRecords: medicationDoseRecords,
            medicationSupplyLogs: medicationSupplyLogs
        )
        if profileScope == .familyShared {
            let sharedProfileIDs = Set(
                envelope.profiles
                    .filter {
                        CareProfileSharingScope(rawValue: $0.sharingScopeRawValue ?? "") == .family
                    }
                    .map(\.id)
            )
            envelope.profiles.removeAll { !sharedProfileIDs.contains($0.id) }
            envelope.photoAttachments = envelope.photoAttachments?.filter {
                $0.profileID == nil || $0.profileID.map(sharedProfileIDs.contains) == true
            }
            envelope.solidsProfileStates = envelope.solidsProfileStates?.filter { sharedProfileIDs.contains($0.profileID) }
            envelope.solidFoodProgress = envelope.solidFoodProgress?.filter { sharedProfileIDs.contains($0.profileID) }
            envelope.solidFoodEventItems = envelope.solidFoodEventItems?.filter { sharedProfileIDs.contains($0.profileID) }
            envelope.solidAllergenProgress = envelope.solidAllergenProgress?.filter { sharedProfileIDs.contains($0.profileID) }
            envelope.plannedSolidMeals = envelope.plannedSolidMeals?.filter { sharedProfileIDs.contains($0.profileID) }
            envelope.events.removeAll { $0.profileID.map(sharedProfileIDs.contains) != true }
            envelope.predictionRecords.removeAll { $0.profileID.map(sharedProfileIDs.contains) != true }
            envelope.milestones = envelope.milestones?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
            envelope.appointments = envelope.appointments?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
            let sharedAppointmentIDs = Set((envelope.appointments ?? []).map(\.id))
            envelope.appointmentFollowUps = envelope.appointmentFollowUps?.filter {
                sharedAppointmentIDs.contains($0.appointmentID)
                    && $0.profileID.map(sharedProfileIDs.contains) == true
            }
            let sharedFollowUpSourceKeys = Set((envelope.appointmentFollowUps ?? []).map {
                "\(HouseholdAttentionSourceKind.appointmentFollowUp.rawValue):\($0.id.uuidString.lowercased())"
            })
            let appointmentFollowUpPrefix = "\(HouseholdAttentionSourceKind.appointmentFollowUp.rawValue):"
            let isIncludedAppointmentSource: (String?) -> Bool = { sourceKey in
                guard let sourceKey, sourceKey.hasPrefix(appointmentFollowUpPrefix) else {
                    return true
                }
                return sharedFollowUpSourceKeys.contains(sourceKey)
            }
            envelope.attentionAcknowledgements = envelope.attentionAcknowledgements?.filter {
                ($0.profileID == nil || $0.profileID.map(sharedProfileIDs.contains) == true)
                    && isIncludedAppointmentSource($0.sourceKey)
            }
            envelope.attentionClaims = envelope.attentionClaims?.filter {
                sharedFollowUpSourceKeys.contains($0.sourceKey)
            }
            envelope.caregiverHandoffNotes = envelope.caregiverHandoffNotes?.filter {
                ($0.profileID == nil || $0.profileID.map(sharedProfileIDs.contains) == true)
                    && isIncludedAppointmentSource($0.sourceKey)
            }
            envelope.ageGuideReadStates = envelope.ageGuideReadStates?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
            envelope.puppyStageGuideReadStates = envelope.puppyStageGuideReadStates?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
            envelope.tripTravelers = envelope.tripTravelers?.filter {
                $0.profileID == nil || $0.profileID.map(sharedProfileIDs.contains) == true
            }
            let includedTravelerIDs = Set((envelope.tripTravelers ?? []).map(\.id))
            envelope.packingBags = envelope.packingBags?.filter {
                $0.travelerID == nil || $0.travelerID.map(includedTravelerIDs.contains) == true
            }
            let includedBagIDs = Set((envelope.packingBags ?? []).map(\.id))
            envelope.packingItems = envelope.packingItems?.filter {
                ($0.travelerID == nil || $0.travelerID.map(includedTravelerIDs.contains) == true)
                    && ($0.bagID == nil || $0.bagID.map(includedBagIDs.contains) == true)
            }
            let includedRoutineIDs = Set((envelope.careRoutines ?? []).filter {
                $0.profileID == nil || $0.profileID.map(sharedProfileIDs.contains) == true
            }.map(\.id))
            envelope.careRoutines = envelope.careRoutines?.filter { includedRoutineIDs.contains($0.id) }
            envelope.careRoutineSteps = envelope.careRoutineSteps?.filter { includedRoutineIDs.contains($0.routineID) }
            envelope.careRoutineRuns = envelope.careRoutineRuns?.filter {
                includedRoutineIDs.contains($0.routineID)
                    && ($0.profileID == nil || $0.profileID.map(sharedProfileIDs.contains) == true)
            }
            envelope.medications = envelope.medications?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
            envelope.medicationRegimens = envelope.medicationRegimens?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
            envelope.medicationSchedulePhases = envelope.medicationSchedulePhases?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
            envelope.medicationDoseRecords = envelope.medicationDoseRecords?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
            envelope.medicationSupplyLogs = envelope.medicationSupplyLogs?.filter { $0.profileID.map(sharedProfileIDs.contains) == true }
        }
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
        createRecoveryBackup: Bool = true,
        preservePrivateProfiles: Bool = false,
        defaults: UserDefaults = .standard
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var envelope = try decoder.decode(BackupEnvelope.self, from: data)
        guard (1...currentBackupVersion).contains(envelope.version) else {
            throw CocoaError(.fileReadUnknown)
        }
        normalizeMedicationDoseRecords(in: &envelope)
        try validate(envelope)
        if createRecoveryBackup {
            _ = try createAutomaticRecoveryBackup(context: context, reason: "before-import")
        }

        do {
            let preservedProfileIDs: Set<UUID>
            if preservePrivateProfiles {
                preservedProfileIDs = Set(
                    try context.fetch(FetchDescriptor<CareProfile>())
                        .filter { $0.sharingScope == .privateOnly }
                        .map(\.id)
                )
            } else {
                preservedProfileIDs = []
            }
            excludeProfileData(preservedProfileIDs, from: &envelope)
            try deleteAll(
                context: context,
                saveChanges: false,
                recordLocalSave: false,
                preservingProfileIDs: preservedProfileIDs
            )

        for value in envelope.profiles {
            context.insert(CareProfile(
                id: value.id,
                profileType: value.profileTypeRawValue.flatMap(CareProfileType.init(rawValue:)) ?? .child,
                name: value.name, birthDate: value.birthDate,
                sex: value.sexRawValue.flatMap(ProfileSex.init(rawValue:)) ?? .unknown,
                adultRelationship: value.adultRelationshipRawValue.flatMap(AdultCareRelationship.init(rawValue:)),
                sharingScope: value.sharingScopeRawValue.flatMap(CareProfileSharingScope.init(rawValue:)) ?? .privateOnly,
                ownerIdentifier: value.ownerIdentifier ?? CaregiverIdentityService.stableCaregiverIdentifier(),
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
                allergenIDs: value.allergenIDsJSON.flatMap { dataString in
                    dataString.data(using: .utf8).flatMap {
                        try? JSONDecoder().decode([String].self, from: $0)
                    }
                } ?? [],
                minimumAgeMonths: value.minimumAgeMonths ?? 6,
                preparationNotes: value.preparationNotes ?? "",
                safetyNotes: value.safetyNotes ?? "",
                nutritionLabel: value.nutritionLabelJSON.flatMap { dataString in
                    dataString.data(using: .utf8).flatMap {
                        try? JSONDecoder().decode(SolidManualNutritionLabel.self, from: $0)
                    }
                },
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.customSolidRecipes ?? [] {
            context.insert(CustomSolidRecipe(
                id: value.id,
                name: value.name,
                ingredients: value.ingredientsJSON.data(using: .utf8).flatMap {
                    try? JSONDecoder().decode([CustomSolidRecipeIngredient].self, from: $0)
                } ?? [],
                servings: value.servings,
                minimumAgeMonths: value.minimumAgeMonths,
                instructions: value.instructions,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.solidsProfileStates ?? [] {
            context.insert(SolidsProfileState(
                id: value.id,
                profileID: value.profileID,
                isActivated: value.isActivated,
                startedAt: value.startedAt,
                readinessNotes: value.readinessNotes,
                guidedStartDate: value.guidedStartDate,
                favoriteRecipeIDs: value.favoriteRecipeIDsJSON.flatMap { dataString in
                    dataString.data(using: .utf8).flatMap {
                        try? JSONDecoder().decode([String].self, from: $0)
                    }
                } ?? [],
                wantToTryRecipeIDs: value.wantToTryRecipeIDsJSON.flatMap { dataString in
                    dataString.data(using: .utf8).flatMap {
                        try? JSONDecoder().decode([String].self, from: $0)
                    }
                } ?? [],
                recipeCollections: value.recipeCollectionsJSON.flatMap { dataString in
                    dataString.data(using: .utf8).flatMap {
                        try? JSONDecoder().decode([SolidRecipeCollection].self, from: $0)
                    }
                } ?? [],
                completedFeedingSkillIDs: value.completedFeedingSkillIDsJSON.flatMap { dataString in
                    dataString.data(using: .utf8).flatMap {
                        try? JSONDecoder().decode([String].self, from: $0)
                    }
                } ?? [],
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.solidFoodProgress ?? [] {
            context.insert(SolidFoodProgress(
                id: value.id,
                profileID: value.profileID,
                foodID: value.foodID,
                foodNameSnapshot: value.foodNameSnapshot,
                status: SolidsFoodStatus(rawValue: value.statusRawValue) ?? .notTried,
                isFavorite: value.isFavorite,
                firstTriedAt: value.firstTriedAt,
                lastTriedAt: value.lastTriedAt,
                exposureCount: value.exposureCount,
                lastReactionRawValue: value.lastReactionRawValue,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.solidFoodEventItems ?? [] {
            let item = SolidFoodEventItem(
                id: value.id,
                eventID: value.eventID,
                profileID: value.profileID,
                foodID: value.foodID,
                foodNameSnapshot: value.foodNameSnapshot,
                confirmedAllergenPortionIDs: value.confirmedAllergenPortionIDsJSON.flatMap { dataString in
                    dataString.data(using: .utf8).flatMap {
                        try? JSONDecoder().decode([String].self, from: $0)
                    }
                },
                reactionRawValue: value.reactionRawValue,
                servingAmount: value.servingAmount ?? "",
                amountOffered: value.amountOffered,
                amountEaten: value.amountEaten,
                portionUnit: value.portionUnitRawValue.flatMap(SolidPortionUnit.init(rawValue:)),
                consumptionEstimate: value.consumptionEstimateRawValue.flatMap(SolidConsumptionEstimate.init(rawValue:)),
                nutritionSnapshot: value.nutritionSnapshotJSON.flatMap { dataString in
                    dataString.data(using: .utf8).flatMap {
                        try? JSONDecoder().decode(SolidNutritionSnapshot.self, from: $0)
                    }
                },
                recipeID: value.recipeID,
                recipeNameSnapshot: value.recipeNameSnapshot,
                notes: value.notes ?? "",
                suspectedReaction: value.suspectedReaction ?? false,
                severity: SolidReactionSeverity(rawValue: value.severityRawValue ?? "") ?? .unknown,
                onsetMinutes: value.onsetMinutes,
                durationMinutes: value.durationMinutes,
                responseNotes: value.responseNotes ?? "",
                followUp: SolidReactionFollowUp(rawValue: value.followUpRawValue ?? "") ?? .none,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            )
            item.allergenIDsJSON = value.allergenIDsJSON
            item.symptomIDsJSON = value.symptomIDsJSON ?? "[]"
            context.insert(item)
        }
        for value in envelope.solidAllergenProgress ?? [] {
            context.insert(SolidAllergenProgress(
                id: value.id,
                profileID: value.profileID,
                allergenID: value.allergenID,
                status: SolidAllergenStatus(rawValue: value.statusRawValue) ?? .notStarted,
                statusOverride: value.statusOverrideRawValue.flatMap(SolidAllergenStatus.init(rawValue:)),
                introductionStep: value.introductionStep,
                exposureMealCount: value.exposureMealCount,
                firstIntroducedAt: value.firstIntroducedAt,
                lastExposureAt: value.lastExposureAt,
                nextExposureDueAt: value.nextExposureDueAt,
                reminderEnabled: value.reminderEnabled,
                notes: value.notes,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.plannedSolidMeals ?? [] {
            let plan = PlannedSolidMeal(
                id: value.id,
                profileID: value.profileID,
                scheduledAt: value.scheduledAt,
                title: value.title,
                foodIDs: [],
                foodNames: [],
                notes: value.notes,
                completedEventID: value.completedEventID,
                recipeID: value.recipeID,
                isGuided: value.isGuided ?? false,
                guidedPosition: value.guidedPosition,
                allergenID: value.allergenID,
                allergenIntroductionStep: value.allergenIntroductionStep,
                allergenServingGuidance: value.allergenServingGuidance,
                allergenObservationMinutes: value.allergenObservationMinutes,
                reminderEnabled: value.reminderEnabled ?? false,
                reminderOffsetMinutes: value.reminderOffsetMinutes ?? 30,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            )
            plan.foodIDsJSON = value.foodIDsJSON
            plan.foodNamesJSON = value.foodNamesJSON
            context.insert(plan)
        }
        let fallbackProfileID = envelope.profiles.first?.id
        for value in envelope.events {
            let event = CareEvent(
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
            event.solidFoodDetailsJSON = value.solidFoodDetailsJSON
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
            event.healthObservationDetailsData = value.healthObservationDetailsData
            context.insert(event)
        }
        for value in envelope.medications ?? [] {
            guard let profileID = value.profileID ?? fallbackProfileID else { continue }
            context.insert(Medication(
                id: value.id,
                profileID: profileID,
                name: value.name,
                form: MedicationForm(rawValue: value.formRawValue) ?? .other,
                strength: value.strength,
                strengthUnit: value.strengthUnit,
                route: MedicationRoute(rawValue: value.routeRawValue) ?? .other,
                instructions: value.instructions,
                reasonForTaking: value.reasonForTaking,
                prescriber: value.prescriber,
                pharmacy: value.pharmacy,
                currentSupply: value.currentSupply,
                refillThreshold: value.refillThreshold,
                isArchived: value.isArchived,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.medicationRegimens ?? [] {
            guard let profileID = value.profileID ?? fallbackProfileID else { continue }
            let regimen = MedicationRegimen(
                id: value.id,
                profileID: profileID,
                medicationID: value.medicationID,
                scheduleKind: MedicationScheduleKind(rawValue: value.scheduleKindRawValue) ?? .daily,
                startDate: value.startDate,
                endDate: value.endDate,
                doseAmount: value.doseAmount,
                doseUnit: value.doseUnit,
                doseTimes: [],
                weekdayMask: value.weekdayMask,
                intervalDays: value.intervalDays,
                cycleOnDays: value.cycleOnDays,
                cycleOffDays: value.cycleOffDays,
                minimumHoursBetweenDoses: value.minimumHoursBetweenDoses,
                maximumDosesPerDay: value.maximumDosesPerDay,
                remindersEnabled: value.remindersEnabled,
                followUpRemindersEnabled: value.followUpRemindersEnabled ?? false,
                reminderLeadMinutes: value.reminderLeadMinutes,
                timeZoneBehavior: MedicationTimeZoneBehavior(rawValue: value.timeZoneBehaviorRawValue) ?? .localTime,
                timeZoneIdentifier: value.timeZoneIdentifier,
                instructions: value.instructions,
                isActive: value.isActive,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            )
            regimen.doseTimesData = value.doseTimesData
            context.insert(regimen)
        }
        for value in envelope.medicationSchedulePhases ?? [] {
            guard let profileID = value.profileID ?? fallbackProfileID else { continue }
            let phase = MedicationSchedulePhase(
                id: value.id,
                profileID: profileID,
                regimenID: value.regimenID,
                sequence: value.sequence,
                durationDays: value.durationDays,
                doseAmount: value.doseAmount,
                doseUnit: value.doseUnit,
                doseTimes: [],
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            )
            phase.doseTimesData = value.doseTimesData
            context.insert(phase)
        }
        for value in envelope.medicationDoseRecords ?? [] {
            guard let profileID = value.profileID ?? fallbackProfileID else { continue }
            context.insert(MedicationDoseRecord(
                id: value.id,
                profileID: profileID,
                medicationID: value.medicationID,
                regimenID: value.regimenID,
                phaseID: value.phaseID,
                occurrenceKey: value.occurrenceKey,
                scheduledAt: value.scheduledAt,
                status: MedicationDoseStatus(rawValue: value.statusRawValue) ?? .taken,
                loggedAt: value.loggedAt,
                takenAt: value.takenAt,
                doseAmount: value.doseAmount,
                doseUnit: value.doseUnit,
                supplyAdjustmentApplied: value.supplyAdjustmentApplied,
                caregiverIdentifier: value.caregiverIdentifier,
                caregiverName: value.caregiverName,
                notes: value.notes,
                careEventID: value.careEventID,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.medicationSupplyLogs ?? [] {
            guard let profileID = value.profileID ?? fallbackProfileID else { continue }
            context.insert(MedicationSupplyLog(
                id: value.id,
                profileID: profileID,
                medicationID: value.medicationID,
                doseRecordID: value.doseRecordID,
                adjustment: value.adjustment,
                resultingSupply: value.resultingSupply,
                reason: MedicationSupplyReason(rawValue: value.reasonRawValue) ?? .correction,
                notes: value.notes,
                loggedAt: value.loggedAt,
                caregiverIdentifier: value.caregiverIdentifier,
                caregiverName: value.caregiverName
            ))
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
        for value in envelope.appointmentFollowUps ?? [] {
            context.insert(AppointmentFollowUp(
                id: value.id,
                appointmentID: value.appointmentID,
                householdID: value.householdID,
                profileID: value.profileID,
                title: value.title,
                details: value.details,
                dueDate: value.dueDate,
                completedAt: value.completedAt,
                completedByCaregiverIdentifier: value.completedByCaregiverIdentifier,
                completedByCaregiverName: value.completedByCaregiverName,
                createdByCaregiverIdentifier: value.createdByCaregiverIdentifier,
                createdByCaregiverName: value.createdByCaregiverName,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.attentionAcknowledgements ?? [] {
            context.insert(HouseholdAttentionAcknowledgement(
                id: value.id,
                householdID: value.householdID,
                profileID: value.profileID,
                sourceKey: value.sourceKey,
                sourceUpdatedAt: value.sourceUpdatedAt,
                caregiverIdentifier: value.caregiverIdentifier,
                caregiverName: value.caregiverName,
                acknowledgedAt: value.acknowledgedAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.attentionClaims ?? [] {
            context.insert(HouseholdAttentionClaim(
                id: value.id,
                householdID: value.householdID,
                profileID: value.profileID,
                sourceKey: value.sourceKey,
                caregiverIdentifier: value.caregiverIdentifier,
                caregiverName: value.caregiverName,
                updatedByCaregiverIdentifier: value.updatedByCaregiverIdentifier,
                updatedByCaregiverName: value.updatedByCaregiverName,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.caregiverHandoffNotes ?? [] {
            context.insert(CaregiverHandoffNote(
                id: value.id,
                householdID: value.householdID,
                profileID: value.profileID,
                sourceKey: value.sourceKey,
                sourceTitleSnapshot: value.sourceTitleSnapshot,
                body: value.body,
                authorCaregiverIdentifier: value.authorCaregiverIdentifier,
                authorCaregiverName: value.authorCaregiverName,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in envelope.familyCaregiverIdentities ?? [] {
            context.insert(FamilyCaregiverIdentity(
                id: value.id,
                householdID: value.householdID,
                caregiverIdentifier: value.caregiverIdentifier,
                displayName: value.displayName,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                lastSeenAt: value.lastSeenAt
            ))
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
                assignedCaregiverName: value.assignedCaregiverName,
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
        for value in envelope.tripItineraryChoiceGroups ?? [] {
            context.insert(TripItineraryChoiceGroup(
                id: value.id,
                householdID: value.householdID,
                tripID: value.tripID,
                title: value.title,
                notes: value.notes,
                scheduledDay: value.scheduledDay,
                selectedItemID: value.selectedItemID,
                createdBy: value.createdBy,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.tripItineraryItems ?? [] {
            context.insert(TripItineraryItem(
                id: value.id,
                householdID: value.householdID,
                tripID: value.tripID,
                choiceGroupID: value.choiceGroupID,
                title: value.title,
                kind: TripItineraryItemKind(rawValue: value.kindRawValue) ?? .activity,
                scheduleKind: TripItineraryScheduleKind(rawValue: value.scheduleKindRawValue) ?? .anytime,
                scheduledDay: value.scheduledDay,
                startDate: value.startDate,
                endDate: value.endDate,
                startTimeZoneIdentifier: value.startTimeZoneIdentifier,
                endTimeZoneIdentifier: value.endTimeZoneIdentifier,
                location: value.location,
                origin: value.origin,
                notes: value.notes,
                bookingStatus: TripItineraryBookingStatus(rawValue: value.bookingStatusRawValue) ?? .planned,
                providerName: value.providerName,
                confirmationNumber: value.confirmationNumber,
                isCompleted: value.isCompleted,
                assignedCaregiverName: value.assignedCaregiverName,
                reminderEnabled: value.reminderEnabled,
                reminderOffsetMinutes: value.reminderOffsetMinutes,
                createdBy: value.createdBy,
                completedBy: value.completedBy,
                completedAt: value.completedAt,
                lastReopenedAt: value.lastReopenedAt,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt,
                sortOrder: value.sortOrder
            ))
        }
        for value in envelope.tripItineraryLinks ?? [] {
            context.insert(TripItineraryLink(
                id: value.id,
                householdID: value.householdID,
                tripID: value.tripID,
                itineraryItemID: value.itineraryItemID,
                title: value.title,
                urlString: value.urlString,
                createdBy: value.createdBy,
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
                foodReferenceID: value.foodReferenceID,
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
            if let caregiverIdentity = envelope.caregiverIdentity {
                CaregiverIdentityService.restoreIdentityIfMissing(
                    currentName: caregiverIdentity.currentName,
                    primaryName: caregiverIdentity.primaryName,
                    defaults: defaults
                )
            }
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
        var envelope = try decoder.decode(BackupEnvelope.self, from: data)
        guard (1...currentBackupVersion).contains(envelope.version) else {
            throw CocoaError(.fileReadUnknown)
        }
        normalizeMedicationDoseRecords(in: &envelope)
        try validate(envelope)
    }

    @MainActor
    static func deleteAll(
        context: ModelContext,
        saveChanges: Bool = true,
        recordLocalSave: Bool = true,
        preservingProfileIDs: Set<UUID> = []
    ) throws {
        let protectedRoutineIDs = Set(
            try context.fetch(FetchDescriptor<CareRoutine>())
                .filter { $0.profileID.map(preservingProfileIDs.contains) == true }
                .map(\.id)
        )
        let protectedTravelerIDs = Set(
            try context.fetch(FetchDescriptor<TripTraveler>())
                .filter { $0.profileID.map(preservingProfileIDs.contains) == true }
                .map(\.id)
        )
        let protectedBagIDs = Set(
            try context.fetch(FetchDescriptor<PackingBag>())
                .filter { $0.travelerID.map(protectedTravelerIDs.contains) == true }
                .map(\.id)
        )
        try deleteAll(CareRoutineRun.self, context: context) {
            !protectedRoutineIDs.contains($0.routineID)
        }
        try deleteAll(CareRoutineStep.self, context: context) {
            !protectedRoutineIDs.contains($0.routineID)
        }
        try deleteAll(CareRoutine.self, context: context) {
            $0.profileID.map(preservingProfileIDs.contains) != true
        }
        try deleteAll(CaregiverHandoffNote.self, context: context) {
            $0.profileID.map(preservingProfileIDs.contains) != true
        }
        try deleteAll(HouseholdAttentionClaim.self, context: context) {
            $0.profileID.map(preservingProfileIDs.contains) != true
        }
        try deleteAll(HouseholdAttentionAcknowledgement.self, context: context) {
            $0.profileID.map(preservingProfileIDs.contains) != true
        }
        try deleteAll(AppointmentFollowUp.self, context: context) {
            $0.profileID.map(preservingProfileIDs.contains) != true
        }
        try deleteAll(FamilyCaregiverIdentity.self, context: context)
        try deleteAll(FoodReminder.self, context: context)
        try deleteAll(TripItineraryLink.self, context: context)
        try deleteAll(TripItineraryItem.self, context: context)
        try deleteAll(TripItineraryChoiceGroup.self, context: context)
        try deleteAll(PackingItem.self, context: context) {
            $0.travelerID.map(protectedTravelerIDs.contains) != true
                && $0.bagID.map(protectedBagIDs.contains) != true
        }
        try deleteAll(PackingBag.self, context: context) {
            !protectedBagIDs.contains($0.id)
        }
        try deleteAll(TripTraveler.self, context: context) {
            !protectedTravelerIDs.contains($0.id)
        }
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
        try deleteAll(PlannedSolidMeal.self, context: context) { !preservingProfileIDs.contains($0.profileID) }
        try deleteAll(SolidAllergenProgress.self, context: context) { !preservingProfileIDs.contains($0.profileID) }
        try deleteAll(SolidFoodEventItem.self, context: context) { !preservingProfileIDs.contains($0.profileID) }
        try deleteAll(SolidFoodProgress.self, context: context) { !preservingProfileIDs.contains($0.profileID) }
        try deleteAll(SolidsProfileState.self, context: context) { !preservingProfileIDs.contains($0.profileID) }
        try deleteAll(CustomSolidRecipe.self, context: context)
        try deleteAll(SolidFoodCatalogItem.self, context: context)
        try deleteAll(PhotoAttachment.self, context: context) {
            $0.profileID.map(preservingProfileIDs.contains) != true
        }
        try deleteAll(PredictionFactor.self, context: context)
        try deleteAllProfileScoped(MedicationSupplyLog.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(MedicationDoseRecord.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(MedicationSchedulePhase.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(MedicationRegimen.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(Medication.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(SleepPredictionRecord.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(CareEvent.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(DoctorAppointment.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(MilestoneEntry.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(AgeGuideReadState.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAllProfileScoped(PuppyStageGuideReadState.self, context: context, preservingProfileIDs: preservingProfileIDs)
        try deleteAll(CareProfile.self, context: context) { !preservingProfileIDs.contains($0.id) }
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

    private static func normalizeMedicationDoseRecords(in envelope: inout BackupEnvelope) {
        guard let records = envelope.medicationDoseRecords else { return }
        var recordsWithoutOccurrence = [MedicationDoseRecordDTO]()
        var grouped = [String: [MedicationDoseRecordDTO]]()
        for record in records {
            if let occurrenceKey = record.occurrenceKey {
                grouped[occurrenceKey, default: []].append(record)
            } else {
                recordsWithoutOccurrence.append(record)
            }
        }

        var discardedCareEventIDs = Set<UUID>()
        var discardedDoseRecordIDs = Set<UUID>()
        let scheduledRecords = grouped.values.compactMap { candidates -> MedicationDoseRecordDTO? in
            guard let winner = candidates.max(by: { first, second in
                if first.updatedAt != second.updatedAt {
                    return first.updatedAt < second.updatedAt
                }
                return first.id.uuidString > second.id.uuidString
            }) else { return nil }
            for candidate in candidates where candidate.id != winner.id {
                discardedDoseRecordIDs.insert(candidate.id)
                if let careEventID = candidate.careEventID {
                    discardedCareEventIDs.insert(careEventID)
                }
            }
            if MedicationDoseStatus(rawValue: winner.statusRawValue) == .skipped,
               let careEventID = winner.careEventID {
                discardedCareEventIDs.insert(careEventID)
            }
            return winner
        }

        envelope.medicationDoseRecords = (recordsWithoutOccurrence + scheduledRecords)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        envelope.events.removeAll { discardedCareEventIDs.contains($0.id) }
        envelope.medicationSupplyLogs = envelope.medicationSupplyLogs?.filter {
            $0.doseRecordID.map(discardedDoseRecordIDs.contains) != true
        }
    }

    private static func excludeProfileData(
        _ excludedProfileIDs: Set<UUID>,
        from envelope: inout BackupEnvelope
    ) {
        guard !excludedProfileIDs.isEmpty else { return }
        envelope.profiles.removeAll { excludedProfileIDs.contains($0.id) }
        envelope.photoAttachments = envelope.photoAttachments?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.solidsProfileStates = envelope.solidsProfileStates?.filter {
            !excludedProfileIDs.contains($0.profileID)
        }
        envelope.solidFoodProgress = envelope.solidFoodProgress?.filter {
            !excludedProfileIDs.contains($0.profileID)
        }
        envelope.solidFoodEventItems = envelope.solidFoodEventItems?.filter {
            !excludedProfileIDs.contains($0.profileID)
        }
        envelope.solidAllergenProgress = envelope.solidAllergenProgress?.filter {
            !excludedProfileIDs.contains($0.profileID)
        }
        envelope.plannedSolidMeals = envelope.plannedSolidMeals?.filter {
            !excludedProfileIDs.contains($0.profileID)
        }
        envelope.events.removeAll { $0.profileID.map(excludedProfileIDs.contains) == true }
        envelope.predictionRecords.removeAll { $0.profileID.map(excludedProfileIDs.contains) == true }
        envelope.milestones = envelope.milestones?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.appointments = envelope.appointments?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.appointmentFollowUps = envelope.appointmentFollowUps?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.attentionAcknowledgements = envelope.attentionAcknowledgements?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.attentionClaims = envelope.attentionClaims?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.caregiverHandoffNotes = envelope.caregiverHandoffNotes?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.ageGuideReadStates = envelope.ageGuideReadStates?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.puppyStageGuideReadStates = envelope.puppyStageGuideReadStates?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }

        let excludedTravelerIDs = Set((envelope.tripTravelers ?? []).filter {
            $0.profileID.map(excludedProfileIDs.contains) == true
        }.map(\.id))
        envelope.tripTravelers = envelope.tripTravelers?.filter {
            !excludedTravelerIDs.contains($0.id)
        }
        let excludedBagIDs = Set((envelope.packingBags ?? []).filter {
            $0.travelerID.map(excludedTravelerIDs.contains) == true
        }.map(\.id))
        envelope.packingBags = envelope.packingBags?.filter {
            !excludedBagIDs.contains($0.id)
        }
        envelope.packingItems = envelope.packingItems?.filter {
            $0.travelerID.map(excludedTravelerIDs.contains) != true
                && $0.bagID.map(excludedBagIDs.contains) != true
        }

        let excludedRoutineIDs = Set((envelope.careRoutines ?? []).filter {
            $0.profileID.map(excludedProfileIDs.contains) == true
        }.map(\.id))
        envelope.careRoutines = envelope.careRoutines?.filter {
            !excludedRoutineIDs.contains($0.id)
        }
        envelope.careRoutineSteps = envelope.careRoutineSteps?.filter {
            !excludedRoutineIDs.contains($0.routineID)
        }
        envelope.careRoutineRuns = envelope.careRoutineRuns?.filter {
            !excludedRoutineIDs.contains($0.routineID)
                && $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.medications = envelope.medications?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.medicationRegimens = envelope.medicationRegimens?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.medicationSchedulePhases = envelope.medicationSchedulePhases?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.medicationDoseRecords = envelope.medicationDoseRecords?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
        }
        envelope.medicationSupplyLogs = envelope.medicationSupplyLogs?.filter {
            $0.profileID.map(excludedProfileIDs.contains) != true
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
    private static func deleteAll<T: PersistentModel>(
        _ modelType: T.Type,
        context: ModelContext,
        matching shouldDelete: (T) -> Bool
    ) throws {
        for item in try context.fetch(FetchDescriptor<T>()) where shouldDelete(item) {
            context.delete(item)
        }
    }

    @MainActor
    private static func deleteAllProfileScoped<T: PersistentModel & ProfileScopedRecord>(
        _ modelType: T.Type,
        context: ModelContext,
        preservingProfileIDs: Set<UUID>
    ) throws {
        try deleteAll(modelType, context: context) {
            $0.profileID.map(preservingProfileIDs.contains) != true
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
        merged.removeValue(forKey: "caregiverIdentity")

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
        object.removeValue(forKey: "caregiverIdentity")
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
        object.removeValue(forKey: "caregiverIdentity")
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

    private static func isValidNutritionSnapshot(_ snapshot: SolidNutritionSnapshot) -> Bool {
        let savedAmountIsValid = snapshot.eatenAmount.map { $0.isFinite && $0 >= 0 } ?? true
        let savedAmountAndUnitArePaired = (snapshot.eatenAmount == nil) == (snapshot.portionUnit == nil)
        return !snapshot.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !snapshot.sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !snapshot.sourceVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !snapshot.amountDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && savedAmountIsValid
            && savedAmountAndUnitArePaired
            && (snapshot.estimatedEatenGrams.map { $0.isFinite && $0 >= 0 } ?? true)
            && snapshot.nutrients.hasValues
            && !snapshot.nutrients.hasNegativeValue
            && snapshot.isComplete == snapshot.nutrients.isComplete
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
        let appointmentFollowUps = envelope.appointmentFollowUps ?? []
        let attentionAcknowledgements = envelope.attentionAcknowledgements ?? []
        let attentionClaims = envelope.attentionClaims ?? []
        let caregiverHandoffNotes = envelope.caregiverHandoffNotes ?? []
        let familyCaregiverIdentities = envelope.familyCaregiverIdentities ?? []
        let appointments = envelope.appointments ?? []
        let appointmentsByID = Dictionary(
            appointments.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let followUpsBySourceKey = Dictionary(
            appointmentFollowUps.map {
                ("\(HouseholdAttentionSourceKind.appointmentFollowUp.rawValue):\($0.id.uuidString.lowercased())", $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let attentionHouseholdIDs = Set((envelope.households ?? []).map(\.id))
        let acknowledgementKeys = attentionAcknowledgements.map {
            "\($0.sourceKey)|\($0.caregiverIdentifier)"
        }
        let claimSourceKeys = attentionClaims.map(\.sourceKey)
        let caregiverIdentityKeys = familyCaregiverIdentities.map {
            "\($0.householdID.uuidString)|\($0.caregiverIdentifier)"
        }
        guard Set(appointments.map(\.id)).count == appointments.count,
              Set(appointmentFollowUps.map(\.id)).count == appointmentFollowUps.count,
              Set(attentionAcknowledgements.map(\.id)).count == attentionAcknowledgements.count,
              Set(acknowledgementKeys).count == acknowledgementKeys.count,
              Set(attentionClaims.map(\.id)).count == attentionClaims.count,
              Set(claimSourceKeys).count == claimSourceKeys.count,
              Set(caregiverHandoffNotes.map(\.id)).count == caregiverHandoffNotes.count,
              Set(familyCaregiverIdentities.map(\.id)).count == familyCaregiverIdentities.count,
              Set(caregiverIdentityKeys).count == caregiverIdentityKeys.count,
              appointmentFollowUps.allSatisfy({
                  guard let appointment = appointmentsByID[$0.appointmentID] else { return false }
                  let completedIdentifier = $0.completedByCaregiverIdentifier?
                      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                  let completedName = $0.completedByCaregiverName?
                      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                  let createdIdentifier = $0.createdByCaregiverIdentifier?
                      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                  let createdName = $0.createdByCaregiverName?
                      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                  return appointment.profileID == $0.profileID
                      && attentionHouseholdIDs.contains($0.householdID)
                      && ($0.profileID.map(profileIDs.contains) ?? true)
                      && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && (createdIdentifier.isEmpty == createdName.isEmpty)
                      && (completedIdentifier.isEmpty == completedName.isEmpty)
                      && (($0.completedAt == nil) == completedIdentifier.isEmpty)
              }),
              attentionAcknowledgements.allSatisfy({
                  attentionHouseholdIDs.contains($0.householdID)
                      && ($0.profileID.map(profileIDs.contains) ?? true)
                      && !$0.sourceKey.isEmpty
                      && !$0.caregiverIdentifier.isEmpty
                      && !$0.caregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              attentionClaims.allSatisfy({
                  let caregiverIdentifier = $0.caregiverIdentifier?
                      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                  let caregiverName = $0.caregiverName?
                      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                  guard let followUp = followUpsBySourceKey[$0.sourceKey] else { return false }
                  return attentionHouseholdIDs.contains($0.householdID)
                      && ($0.profileID.map(profileIDs.contains) ?? true)
                      && followUp.householdID == $0.householdID
                      && followUp.profileID == $0.profileID
                      && (caregiverIdentifier.isEmpty == caregiverName.isEmpty)
                      && !$0.updatedByCaregiverIdentifier.isEmpty
                      && !$0.updatedByCaregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              caregiverHandoffNotes.allSatisfy({
                  let sourceKey = $0.sourceKey?
                      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                  let sourceTitle = $0.sourceTitleSnapshot?
                      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                  return attentionHouseholdIDs.contains($0.householdID)
                      && ($0.profileID.map(profileIDs.contains) ?? true)
                      && (sourceKey.isEmpty == sourceTitle.isEmpty)
                      && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.authorCaregiverIdentifier.isEmpty
                      && !$0.authorCaregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              familyCaregiverIdentities.allSatisfy({
                  attentionHouseholdIDs.contains($0.householdID)
                      && !$0.caregiverIdentifier.isEmpty
                      && !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let solidFoods = envelope.solidFoods ?? []
        if envelope.solidFoods != nil {
            guard Set(solidFoods.map(\.id)).count == solidFoods.count,
                  solidFoods.allSatisfy({ food in
                      guard let labelJSON = food.nutritionLabelJSON else { return true }
                      return labelJSON.data(using: .utf8).flatMap {
                          try? JSONDecoder().decode(SolidManualNutritionLabel.self, from: $0)
                      }?.isValid == true
                  }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        let validCustomFoodIDs = Set(
            solidFoods.map { "custom-\($0.id.uuidString.lowercased())" }
        )
        let customSolidRecipes = envelope.customSolidRecipes ?? []
        guard Set(customSolidRecipes.map(\.id)).count == customSolidRecipes.count,
              Set(customSolidRecipes.map {
                  SolidFoodSelection.normalizedName($0.name)
              }).count == customSolidRecipes.count,
              customSolidRecipes.allSatisfy({ recipe in
                  guard recipe.servings.isFinite, recipe.servings > 0,
                        !recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        let data = recipe.ingredientsJSON.data(using: .utf8),
                        let ingredients = try? JSONDecoder().decode([CustomSolidRecipeIngredient].self, from: data),
                        !ingredients.isEmpty else { return false }
                  return ingredients.allSatisfy {
                      $0.amount.isFinite
                          && $0.amount > 0
                          && !$0.foodID.isEmpty
                          && !$0.foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && (validCustomFoodIDs.contains($0.foodID)
                              || SolidsReferenceCatalog.foodSummary(id: $0.foodID) != nil)
                  }
                      && Set(ingredients.map(\.foodID)).count == ingredients.count
                      && Set(ingredients.map(\.id)).count == ingredients.count
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let solidsProfileStates = envelope.solidsProfileStates ?? []
        let solidFoodProgress = envelope.solidFoodProgress ?? []
        let solidFoodEventItems = envelope.solidFoodEventItems ?? []
        let solidAllergenProgress = envelope.solidAllergenProgress ?? []
        let plannedSolidMeals = envelope.plannedSolidMeals ?? []
        let eventIDs = Set(envelope.events.map(\.id))
        let eventsByID = Dictionary(
            envelope.events.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard Set(solidsProfileStates.map(\.id)).count == solidsProfileStates.count,
              Set(solidFoodProgress.map(\.id)).count == solidFoodProgress.count,
              Set(solidFoodEventItems.map(\.id)).count == solidFoodEventItems.count,
              Set(solidAllergenProgress.map(\.id)).count == solidAllergenProgress.count,
              Set(plannedSolidMeals.map(\.id)).count == plannedSolidMeals.count,
              solidsProfileStates.allSatisfy({ profileIDs.contains($0.profileID) }),
              solidFoodProgress.allSatisfy({ profileIDs.contains($0.profileID) && !$0.foodID.isEmpty }),
              solidFoodEventItems.allSatisfy({ item in
                  guard profileIDs.contains(item.profileID), eventIDs.contains(item.eventID), !item.foodID.isEmpty,
                        [item.amountOffered, item.amountEaten].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
                        (item.portionUnitRawValue.flatMap(SolidPortionUnit.init(rawValue:)) != nil
                            || item.portionUnitRawValue == nil),
                        (item.consumptionEstimateRawValue.flatMap(SolidConsumptionEstimate.init(rawValue:)) != nil
                            || item.consumptionEstimateRawValue == nil),
                        (item.amountOffered == nil && item.amountEaten == nil) || item.portionUnitRawValue != nil,
                        !(item.amountOffered.map { offered in
                            item.amountEaten.map { $0 > offered } ?? false
                        } ?? false),
                        !(item.consumptionEstimateRawValue.flatMap(SolidConsumptionEstimate.init(rawValue:))?.offeredFraction != nil
                            && item.amountEaten == nil
                            && item.amountOffered == nil) else { return false }
                  guard let snapshotJSON = item.nutritionSnapshotJSON else { return true }
                  guard let snapshot = snapshotJSON.data(using: .utf8).flatMap({
                      try? JSONDecoder().decode(SolidNutritionSnapshot.self, from: $0)
                  }) else { return false }
                  return isValidNutritionSnapshot(snapshot)
              }),
              solidAllergenProgress.allSatisfy({
                  profileIDs.contains($0.profileID) && SolidsAllergen(rawValue: $0.allergenID) != nil
              }),
              plannedSolidMeals.allSatisfy({
                  profileIDs.contains($0.profileID)
                      && ($0.completedEventID.map(eventIDs.contains) ?? true)
                      && ($0.allergenID.map { SolidsAllergen(rawValue: $0) != nil } ?? true)
                      && ($0.allergenIntroductionStep.map { (1...3).contains($0) } ?? true)
        }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let solidFoodDetailsAreValid = envelope.events.allSatisfy { event in
            guard let detailsJSON = event.solidFoodDetailsJSON else { return true }
            guard let data = detailsJSON.data(using: .utf8),
                  let details = try? JSONDecoder().decode([SolidFoodLogDetail].self, from: data) else {
                return false
            }
            return details.allSatisfy { detail in
                let amounts = [detail.amountOffered, detail.amountEaten].compactMap { $0 }
                guard !detail.foodID.isEmpty,
                      !detail.foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      amounts.allSatisfy({ $0.isFinite && $0 >= 0 }),
                      amounts.isEmpty || detail.portionUnit != nil,
                      !(detail.amountOffered.map { offered in
                          detail.amountEaten.map { $0 > offered } ?? false
                      } ?? false),
                      !(detail.consumptionEstimate?.offeredFraction != nil
                          && detail.amountEaten == nil
                          && detail.amountOffered == nil) else { return false }
                guard let snapshot = detail.nutritionSnapshot else { return true }
                return isValidNutritionSnapshot(snapshot)
            }
        }
        guard solidFoodDetailsAreValid else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let profileTypesByID = Dictionary(
            uniqueKeysWithValues: envelope.profiles.compactMap { profile in
                CareProfileType(rawValue: profile.profileTypeRawValue ?? CareProfileType.child.rawValue)
                    .map { (profile.id, $0) }
            }
        )
        let healthObservationDetailsAreValid = envelope.events.allSatisfy { event in
            let eventType = EventType.normalized(rawValue: event.typeRawValue)
            let profileType = event.profileID.flatMap { profileTypesByID[$0] }
                ?? event.profileTypeSnapshotRawValue.flatMap(CareProfileType.init(rawValue:))
            if profileType == .dog {
                return event.healthObservationDetailsData == nil
            }
            let healthTypes: Set<EventType> = [
                .symptom,
                .bloodPressure,
                .heartRate,
                .oxygenSaturation,
                .respiratoryRate,
                .glucose,
                .pain
            ]
            guard let data = event.healthObservationDetailsData else {
                return !healthTypes.contains(eventType)
            }
            guard let details = try? JSONDecoder().decode(
                HealthObservationDetails.self,
                from: data
            ),
                  details.symptomSeverity.map({ (0...10).contains($0) }) ?? true,
                  details.systolicBloodPressure.map({ $0 > 0 }) ?? true,
                  details.diastolicBloodPressure.map({ $0 > 0 }) ?? true,
                  details.heartRateBPM.map({ $0 > 0 }) ?? true,
                  details.oxygenSaturationPercent.map({
                      $0.isFinite && $0 > 0 && $0 <= 100
                  }) ?? true,
                  details.respiratoryRatePerMinute.map({ $0 > 0 }) ?? true,
                  details.bloodGlucoseValue.map({ $0.isFinite && $0 > 0 }) ?? true,
                  details.bloodGlucoseUnitRawValue.map({
                      BloodGlucoseUnit(rawValue: $0) != nil
                  }) ?? true,
                  details.bloodGlucoseContextRawValue.map({
                      BloodGlucoseContext(rawValue: $0) != nil
                  }) ?? true,
                  details.painScore.map({ (0...10).contains($0) }) ?? true else {
                return false
            }
            switch eventType {
            case .symptom:
                return details.symptomName.map {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                } == true && details.symptomSeverity != nil
            case .bloodPressure:
                return details.systolicBloodPressure != nil
                    && details.diastolicBloodPressure != nil
            case .heartRate:
                return details.heartRateBPM != nil
            case .oxygenSaturation:
                return details.oxygenSaturationPercent != nil
            case .respiratoryRate:
                return details.respiratoryRatePerMinute != nil
            case .glucose:
                return details.bloodGlucoseValue != nil
                    && details.bloodGlucoseUnit != nil
                    && details.bloodGlucoseContext != nil
            case .pain:
                return details.painScore != nil
            default:
                return false
            }
        }
        guard healthObservationDetailsAreValid else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let medications = envelope.medications ?? []
        let regimens = envelope.medicationRegimens ?? []
        let phases = envelope.medicationSchedulePhases ?? []
        let doseRecords = envelope.medicationDoseRecords ?? []
        let supplyLogs = envelope.medicationSupplyLogs ?? []
        let medicationIDs = Set(medications.map(\.id))
        let regimenIDs = Set(regimens.map(\.id))
        let phaseIDs = Set(phases.map(\.id))
        let medicationProfileIDs = Dictionary(
            medications.compactMap { medication in
                medication.profileID.map { (medication.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let regimensByID = Dictionary(
            regimens.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let phasesByID = Dictionary(
            phases.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let doseRecordsByID = Dictionary(
            doseRecords.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let occurrenceKeys = doseRecords.compactMap(\.occurrenceKey)
        let medicationsByID = Dictionary(
            medications.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let regimenActivityIsValid = Dictionary(grouping: regimens, by: \.medicationID)
            .values
            .allSatisfy { medicationRegimens in
                medicationRegimens.filter(\.isActive).count <= 1
                    && medicationRegimens.allSatisfy { regimen in
                        !(regimen.isActive && (medicationsByID[regimen.medicationID]?.isArchived == true))
                    }
            }
        let phasesByRegimenID = Dictionary(grouping: phases, by: \.regimenID)
        let phaseSequencesAreUnique = phasesByRegimenID
            .values
            .allSatisfy { values in
                Set(values.map(\.sequence)).count == values.count
            }
        let decodedDoseTimesAreValid: (Data?, Bool) -> Bool = { data, allowEmpty in
            guard let data,
                  let times = try? JSONDecoder().decode([MedicationDoseTime].self, from: data) else {
                return allowEmpty
            }
            return (allowEmpty || !times.isEmpty)
                && Set(times).count == times.count
                && times.allSatisfy { (0...23).contains($0.hour) && (0...59).contains($0.minute) }
        }
        let regimenDoseTimesAreValid = regimens.allSatisfy { regimen in
            guard let kind = MedicationScheduleKind(rawValue: regimen.scheduleKindRawValue) else {
                return false
            }
            return decodedDoseTimesAreValid(
                regimen.doseTimesData,
                kind == .asNeeded
            ) && (kind != .asNeeded || ((regimen.doseTimesData.flatMap {
                try? JSONDecoder().decode([MedicationDoseTime].self, from: $0)
            }) ?? []).isEmpty)
        }
        let phaseDoseTimesAreValid = phases.allSatisfy {
            decodedDoseTimesAreValid($0.doseTimesData, false)
        }
        let phaseStructuresAreValid = regimens.allSatisfy { regimen in
            guard let kind = MedicationScheduleKind(rawValue: regimen.scheduleKindRawValue) else {
                return false
            }
            let regimenPhases = (phasesByRegimenID[regimen.id] ?? [])
                .sorted { $0.sequence < $1.sequence }
            let hasContiguousSequences = regimenPhases.map(\.sequence)
                == Array(0..<regimenPhases.count)
            switch kind {
            case .alternating:
                return regimenPhases.count == 2
                    && hasContiguousSequences
                    && regimenPhases.allSatisfy { $0.durationDays != nil }
            case .taper:
                return regimenPhases.count >= 2
                    && hasContiguousSequences
                    && regimenPhases.allSatisfy { $0.durationDays != nil }
                    && zip(regimenPhases, regimenPhases.dropFirst()).allSatisfy {
                        $0.0.doseAmount > $0.1.doseAmount
                    }
            default:
                return regimenPhases.isEmpty
            }
        }
        guard medicationIDs.count == medications.count,
              regimenIDs.count == regimens.count,
              phaseIDs.count == phases.count,
              Set(doseRecords.map(\.id)).count == doseRecords.count,
              Set(occurrenceKeys).count == occurrenceKeys.count,
              Set(supplyLogs.map(\.id)).count == supplyLogs.count,
              regimenActivityIsValid,
              phaseSequencesAreUnique,
              regimenDoseTimesAreValid,
              phaseDoseTimesAreValid,
              phaseStructuresAreValid,
              medications.allSatisfy({
                  $0.profileID.map(profileIDs.contains) == true
                      && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && MedicationForm(rawValue: $0.formRawValue) != nil
                      && MedicationRoute(rawValue: $0.routeRawValue) != nil
                      && ($0.strength.map { $0 > 0 } ?? true)
                      && ($0.currentSupply.map { $0 >= 0 } ?? true)
                      && ($0.refillThreshold.map { $0 >= 0 } ?? true)
              }),
              regimens.allSatisfy({ regimen in
                  let kind = MedicationScheduleKind(rawValue: regimen.scheduleKindRawValue)
                  return regimen.profileID.map(profileIDs.contains) == true
                      && medicationIDs.contains(regimen.medicationID)
                      && regimen.profileID == medicationProfileIDs[regimen.medicationID]
                      && regimen.doseAmount > 0
                      && !regimen.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && kind != nil
                      && MedicationTimeZoneBehavior(rawValue: regimen.timeZoneBehaviorRawValue) != nil
                      && regimen.doseAmount.isFinite
                      && regimen.intervalDays > 0
                      && regimen.cycleOnDays > 0
                      && regimen.cycleOffDays >= 0
                      && (regimen.minimumHoursBetweenDoses.map { $0 > 0 } ?? true)
                      && (regimen.maximumDosesPerDay.map { $0 > 0 } ?? true)
                      && (regimen.endDate.map { $0 >= regimen.startDate } ?? true)
                      && (kind != .fixedCourse || regimen.endDate != nil)
                      && (kind != .specificWeekdays || (1...127).contains(regimen.weekdayMask))
                      && (kind != .asNeeded || (!regimen.remindersEnabled && !(regimen.followUpRemindersEnabled ?? false)))
                      && (!(regimen.followUpRemindersEnabled ?? false) || regimen.remindersEnabled)
                      && regimen.reminderLeadMinutes >= 0
                      && (regimen.timeZoneBehaviorRawValue != MedicationTimeZoneBehavior.fixedTimeZone.rawValue
                          || regimen.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil)
              }),
              phases.allSatisfy({
                  $0.profileID.map(profileIDs.contains) == true
                      && regimenIDs.contains($0.regimenID)
                      && $0.profileID == regimensByID[$0.regimenID]?.profileID
                      && $0.doseAmount.isFinite
                      && $0.doseAmount > 0
                      && !$0.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.sequence >= 0
                      && ($0.durationDays.map { $0 > 0 } ?? true)
              }),
              doseRecords.allSatisfy({ doseRecord in
                  doseRecord.profileID.map(profileIDs.contains) == true
                      && medicationIDs.contains(doseRecord.medicationID)
                      && doseRecord.profileID == medicationProfileIDs[doseRecord.medicationID]
                      && (doseRecord.regimenID.map(regimenIDs.contains) ?? true)
                      && (doseRecord.regimenID.map { regimenID in
                          regimensByID[regimenID]?.medicationID == doseRecord.medicationID
                              && regimensByID[regimenID]?.profileID == doseRecord.profileID
                      } ?? true)
                      && (doseRecord.phaseID.map(phaseIDs.contains) ?? true)
                      && (doseRecord.phaseID.map { phaseID in
                          phasesByID[phaseID]?.regimenID == doseRecord.regimenID
                              && phasesByID[phaseID]?.profileID == doseRecord.profileID
                      } ?? true)
                      && (doseRecord.careEventID.map { careEventID in
                          eventsByID[careEventID]?.profileID == doseRecord.profileID
                              && EventType.normalized(
                                  rawValue: eventsByID[careEventID]?.typeRawValue ?? ""
                              ) == .medicine
                      } ?? true)
                      && doseRecord.doseAmount > 0
                      && !doseRecord.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && MedicationDoseStatus(rawValue: doseRecord.statusRawValue) != nil
                      && doseRecord.supplyAdjustmentApplied <= 0
                      && doseRecord.supplyAdjustmentApplied >= -doseRecord.doseAmount
              }),
              supplyLogs.allSatisfy({ supplyLog in
                  supplyLog.profileID.map(profileIDs.contains) == true
                      && medicationIDs.contains(supplyLog.medicationID)
                      && supplyLog.profileID == medicationProfileIDs[supplyLog.medicationID]
                      && MedicationSupplyReason(rawValue: supplyLog.reasonRawValue) != nil
                      && (supplyLog.resultingSupply.map { $0 >= 0 } ?? true)
                      && (supplyLog.doseRecordID.map { doseRecordID in
                          doseRecordsByID[doseRecordID]?.medicationID == supplyLog.medicationID
                              && doseRecordsByID[doseRecordID]?.profileID == supplyLog.profileID
                      } ?? true)
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let packingTrips = envelope.packingTrips ?? []
        let tripTravelers = envelope.tripTravelers ?? []
        let packingBags = envelope.packingBags ?? []
        let packingItems = envelope.packingItems ?? []
        let householdIDs = Set((envelope.households ?? []).map(\.id))
        let homeTodoLists = envelope.homeTodoLists ?? []
        let homeTodoItems = envelope.homeTodoItems ?? []
        let homeTodoListIDs = Set(homeTodoLists.map(\.id))
        guard homeTodoListIDs.count == homeTodoLists.count,
              Set(homeTodoItems.map(\.id)).count == homeTodoItems.count,
              homeTodoItems.allSatisfy({ item in
                  homeTodoListIDs.contains(item.todoListID)
                      && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && (item.assignedCaregiverName.map {
                          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      } ?? true)
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
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

        let itineraryChoiceGroups = envelope.tripItineraryChoiceGroups ?? []
        let itineraryItems = envelope.tripItineraryItems ?? []
        let itineraryLinks = envelope.tripItineraryLinks ?? []
        let itineraryItemIDs = Set(itineraryItems.map(\.id))
        let itineraryGroupsByID = Dictionary(
            itineraryChoiceGroups.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let itineraryItemsByID = Dictionary(
            itineraryItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let destinationIsValid: (TripDestinationSelection?) -> Bool = { destination in
            guard let destination else { return true }
            guard !destination.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            switch (destination.latitude, destination.longitude) {
            case (nil, nil): break
            case (let latitude?, let longitude?):
                guard latitude.isFinite,
                      longitude.isFinite,
                      (-90...90).contains(latitude),
                      (-180...180).contains(longitude) else { return false }
            default: return false
            }
            return destination.timeZoneIdentifier.map { TimeZone(identifier: $0) != nil } ?? true
        }
        let scheduledDayIsValid: (Date?, PackingTripDTO) -> Bool = { day, trip in
            guard let day else { return true }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = trip.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            return (calendar.startOfDay(for: trip.startDate)...calendar.startOfDay(for: trip.endDate))
                .contains(calendar.startOfDay(for: day))
        }
        guard Set(itineraryChoiceGroups.map(\.id)).count == itineraryChoiceGroups.count,
              itineraryItemIDs.count == itineraryItems.count,
              Set(itineraryLinks.map(\.id)).count == itineraryLinks.count,
              itineraryChoiceGroups.allSatisfy({ group in
                  guard let trip = tripsByID[group.tripID] else { return false }
                  return group.householdID == trip.householdID
                      && !group.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && scheduledDayIsValid(group.scheduledDay, trip)
                      && group.selectedItemID.map { selectedID in
                          guard let item = itineraryItemsByID[selectedID] else { return false }
                          return item.tripID == group.tripID && item.choiceGroupID == group.id
                      } != false
              }),
              itineraryItems.allSatisfy({ item in
                  guard let trip = tripsByID[item.tripID],
                        let kind = TripItineraryItemKind(rawValue: item.kindRawValue),
                        let schedule = TripItineraryScheduleKind(rawValue: item.scheduleKindRawValue),
                        TripItineraryBookingStatus(rawValue: item.bookingStatusRawValue) != nil else {
                      return false
                  }
                  let scheduleIsValid: Bool
                  switch schedule {
                  case .unscheduled:
                      scheduleIsValid = item.scheduledDay == nil
                          && item.startDate == nil
                          && item.endDate == nil
                          && !item.reminderEnabled
                  case .timed:
                      scheduleIsValid = item.scheduledDay != nil
                          && item.startDate != nil
                          && (item.endDate.map { end in
                              item.startDate.map { end >= $0 } ?? false
                          } ?? true)
                  case .morning, .afternoon, .evening, .anytime:
                      scheduleIsValid = item.scheduledDay != nil
                          && item.startDate == nil
                          && item.endDate == nil
                          && !item.reminderEnabled
                  }
                  let choiceGroupIsValid: Bool
                  if let groupID = item.choiceGroupID {
                      choiceGroupIsValid = itineraryGroupsByID[groupID]?.tripID == item.tripID
                  } else {
                      choiceGroupIsValid = true
                  }
                  return item.householdID == trip.householdID
                      && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && scheduleIsValid
                      && scheduledDayIsValid(item.scheduledDay, trip)
                      && item.reminderOffsetMinutes >= 0
                      && choiceGroupIsValid
                      && (item.assignedCaregiverName.map {
                          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      } ?? true)
                      && (item.startTimeZoneIdentifier.map { TimeZone(identifier: $0) != nil } ?? true)
                      && (item.endTimeZoneIdentifier.map { TimeZone(identifier: $0) != nil } ?? true)
                      && destinationIsValid(item.location)
                      && destinationIsValid(kind.supportsOrigin ? item.origin : nil)
              }),
              itineraryLinks.allSatisfy({ link in
                  guard let trip = tripsByID[link.tripID],
                        let url = URL(string: link.urlString),
                        let scheme = url.scheme?.lowercased(),
                        (scheme == "http" || scheme == "https"),
                        url.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                      return false
                  }
                  let itineraryItemIsValid: Bool
                  if let itemID = link.itineraryItemID {
                      itineraryItemIsValid = itineraryItemsByID[itemID]?.tripID == link.tripID
                  } else {
                      itineraryItemIsValid = true
                  }
                  return link.householdID == trip.householdID
                      && !link.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && itineraryItemIsValid
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
        let descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.typeRawValue == "custom" && $0.title == "Growth"
            }
        )
        let legacyEvents = try context.fetch(descriptor)
        guard !legacyEvents.isEmpty else { return 0 }

        let profile = try context.fetch(FetchDescriptor<CareProfile>()).first
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
                  let birthDate = profile.birthDate,
                  event.occursOnLocalDay(birthDate) else {
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
