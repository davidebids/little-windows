import SwiftData
import SwiftUI
import PhotosUI
import UIKit
import Combine

struct DebouncedSearchModifier: ViewModifier {
    @Binding private var effectiveText: String
    @State private var draft: String
    private let prompt: String
    private let delay: Duration

    init(
        effectiveText: Binding<String>,
        prompt: String,
        delay: Duration = .milliseconds(120)
    ) {
        _effectiveText = effectiveText
        _draft = State(initialValue: effectiveText.wrappedValue)
        self.prompt = prompt
        self.delay = delay
    }

    func body(content: Content) -> some View {
        content
            .searchable(text: $draft, prompt: prompt)
            .task(id: draft) {
                if !draft.isEmpty {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled else { return }
                effectiveText = draft
            }
            .onChange(of: effectiveText) { _, newValue in
                if draft != newValue { draft = newValue }
            }
    }
}

extension View {
    func debouncedSearch(
        text: Binding<String>,
        prompt: String,
        delay: Duration = .milliseconds(120)
    ) -> some View {
        modifier(DebouncedSearchModifier(
            effectiveText: text,
            prompt: prompt,
            delay: delay
        ))
    }
}

@MainActor
enum ThumbnailImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    static func image(attachmentID: UUID, data: Data) -> UIImage? {
        let key = attachmentID.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        let decodedCost = image.cgImage.map { $0.width * $0.height * 4 } ?? data.count
        cache.setObject(image, forKey: key, cost: max(data.count, decodedCost))
        return image
    }
}

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @Query(sort: \BabyEvent.startDate, order: .reverse) private var allEvents: [BabyEvent]
    @Query(sort: \SolidFoodCatalogItem.name) private var customSolidFoods: [SolidFoodCatalogItem]
    @Query(sort: \SolidsProfileState.updatedAt, order: .reverse) private var solidsProfileStates: [SolidsProfileState]
    @StateObject private var profileService = ProfileService.shared
    @AppStorage("caregiverOne") private var caregiverOne = "Caregiver 1"
    @AppStorage("currentCaregiverName") private var currentCaregiverName = ""

    let existingEvent: BabyEvent?
    let onSave: (BabyEvent) -> Void

    @State private var type: EventType
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasEndDate: Bool
    @State private var startTimeZoneIdentifier: String
    @State private var endTimeZoneIdentifier: String
    @State private var caregiverName: String
    @State private var notes: String
    @State private var sleepKind: SleepKind
    @State private var feedKind: FeedKind
    @State private var amountOzText: String
    @State private var foodDescription: String
    @State private var solidTexture: SolidTexture
    @State private var solidFeedingStyle: SolidFeedingStyle
    @State private var showingSolidTextureOptions = false
    @State private var showingSolidFeedingStyleOptions = false
    @State private var solidFoodDetails: [SolidFoodLogDetail]
    @State private var editingSolidFoodID: String?
    @State private var nursingSide: NursingSide
    @State private var nursingMinutes: Double
    @State private var diaperKind: DiaperKind
    @State private var diaperRash: Bool
    @State private var childPottyKind: ChildPottyKind
    @State private var childPottyLocation: ChildPottyLocation
    @State private var childPottyAccident: Bool
    @State private var peeAmount: DiaperAmount
    @State private var pooAmount: DiaperAmount
    @State private var pooColor: PooColor
    @State private var pooTexture: PooTexture
    @State private var diaperDetailsExpanded: Bool
    @State private var medicineName: String
    @State private var dose: Double
    @State private var medicineUnit: MedicineUnit
    @State private var reason: String
    @State private var activityType: ActivityType
    @State private var heightFeet: Int
    @State private var heightInches: Double
    @State private var weightPounds: Int
    @State private var weightOunces: Double
    @State private var headCircumferenceInches: Double?
    @State private var growthSex: BabySex
    @State private var growthSource: GrowthMeasurementSource
    @State private var temperatureValue: Double
    @State private var temperatureUnit: TemperatureUnit
    @State private var temperatureMethod: TemperatureMethod
    @State private var dogFoodName: String
    @State private var dogFoodAmount: Double
    @State private var dogFoodUnit: DogAmountUnit
    @State private var dogMealType: DogMealType
    @State private var dogEatenAmount: DogEatenAmount
    @State private var dogWaterAmount: Double
    @State private var dogWaterUnit: DogWaterUnit
    @State private var dogTreatName: String
    @State private var dogTreatQuantity: Double
    @State private var dogPottyType: DogPottyType
    @State private var dogPottyLocation: DogPottyLocation
    @State private var dogPottyAccident: Bool
    @State private var dogPeeAmount: DiaperAmount
    @State private var dogPeeColor: DogPeeColor
    @State private var dogPoopAmount: DiaperAmount
    @State private var dogStoolQuality: DogStoolQuality
    @State private var dogPoopColor: DogPoopColor
    @State private var dogDistance: Double
    @State private var dogDistanceUnit: DogDistanceUnit
    @State private var dogPeeCount: Int
    @State private var dogPoopCount: Int
    @State private var dogLeashBehavior: DogLeashBehavior
    @State private var dogWeather: String
    @State private var dogRestType: DogRestType
    @State private var dogTrainingType: DogTrainingType
    @State private var dogTrainingSkill: String
    @State private var dogTrainingOutcome: DogTrainingOutcome
    @State private var dogGroomingType: DogGroomingType
    @State private var dogMedicineUnit: DogMedicineUnit
    @State private var dogMedicineRoute: DogMedicineRoute
    @State private var dogVaccineType: DogVaccineType
    @State private var dogHasVaccineDueDate: Bool
    @State private var dogVaccineDueDate: Date
    @State private var dogVaccineLotNumber: String
    @State private var dogVaccineClinic: String
    @State private var dogSymptomType: DogSymptomType
    @State private var dogSymptomSeverity: DogSymptomSeverity
    @State private var dogSymptomResolved: Bool
    @State private var dogGlucoseValue: Double
    @State private var dogGlucoseUnit: DogGlucoseUnit
    @State private var dogGlucoseMealRelation: DogMealRelation
    @State private var recentMedicineNames: [String]
    @State private var growthMeasurementEditor: GrowthMeasurementEditorKind?
    @State private var showingSolidFoodPicker: Bool
    @State private var validationMessage: String?

    init(
        type: EventType,
        event: BabyEvent? = nil,
        solidPreset: SolidFeedEditorPreset? = nil,
        onSave: @escaping (BabyEvent) -> Void
    ) {
        let selectedType = event?.type ?? type
        let selectedProfileID = event?.profileID
            ?? ProfileService.shared.selectedProfileID
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let unloadedID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let loadsSolidData = selectedType == .feed
            || event?.feedKind == .solid
            || solidPreset != nil
        let solidProfileID = loadsSolidData ? selectedProfileID : unloadedID
        let feedRawValue = EventType.feed.rawValue
        let solidRawValue = FeedKind.solid.rawValue
        var recentSolidEventDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { event in
                event.profileID == solidProfileID
                    && event.typeRawValue == feedRawValue
                    && event.feedKindRawValue == solidRawValue
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        recentSolidEventDescriptor.fetchLimit = 120
        _allEvents = Query(recentSolidEventDescriptor)
        _solidsProfileStates = Query(FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == solidProfileID },
            sortBy: [SortDescriptor(\SolidsProfileState.updatedAt, order: .reverse)]
        ))
        if loadsSolidData {
            _customSolidFoods = Query(FetchDescriptor<SolidFoodCatalogItem>(
                sortBy: [SortDescriptor(\SolidFoodCatalogItem.name)]
            ))
        } else {
            _customSolidFoods = Query(FetchDescriptor<SolidFoodCatalogItem>(
                predicate: #Predicate { $0.normalizedName == "__unloaded_custom_food__" },
                sortBy: [SortDescriptor(\SolidFoodCatalogItem.name)]
            ))
        }
        existingEvent = event
        self.onSave = onSave
        _type = State(initialValue: selectedType)
        _title = State(initialValue: event?.title ?? "")
        _startDate = State(initialValue: event?.startDate ?? Date())
        _endDate = State(initialValue: event?.endDate ?? Date())
        _hasEndDate = State(initialValue: selectedType.supportsTimer && (event == nil || event?.endDate != nil))
        let effectiveTimeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
        let initialStartTimeZoneIdentifier = event?.startTimeZoneIdentifier
            ?? effectiveTimeZoneIdentifier
        _startTimeZoneIdentifier = State(initialValue: initialStartTimeZoneIdentifier)
        _endTimeZoneIdentifier = State(
            initialValue: event?.endTimeZoneIdentifier
                ?? event?.startTimeZoneIdentifier
                ?? effectiveTimeZoneIdentifier
        )
        _caregiverName = State(initialValue: event?.caregiverName ?? "")
        _notes = State(initialValue: event?.notes ?? "")
        _sleepKind = State(initialValue: event?.sleepKind ?? .nap)
        _feedKind = State(initialValue: event?.feedKind ?? (solidPreset == nil ? .bottle : .solid))
        _amountOzText = State(initialValue: Self.amountText(for: event?.amountOz))
        let detailFoodNames = event?.solidFoodDetails.map(\.foodName) ?? []
        let fallbackFoodNames = detailFoodNames.isEmpty
            ? solidPreset?.foodNames ?? []
            : detailFoodNames
        let persistedFoodDescription = event?.foodDescription
        let initialFoodDescription = SolidFoodSelection.names(from: persistedFoodDescription).isEmpty
            ? SolidFoodSelection.description(from: fallbackFoodNames)
            : persistedFoodDescription
        _foodDescription = State(initialValue: initialFoodDescription ?? "")
        _solidTexture = State(initialValue: event?.solidTexture ?? .unknown)
        _solidFeedingStyle = State(initialValue: event?.solidFeedingStyle ?? .unknown)
        _solidFoodDetails = State(initialValue: Self.initialSolidFoodDetails(event: event, preset: solidPreset))
        _editingSolidFoodID = State(initialValue: nil)
        _nursingSide = State(initialValue: event?.nursingSide ?? .left)
        _nursingMinutes = State(initialValue: (event?.totalNursingDurationSeconds ?? 0) / 60)
        _diaperKind = State(initialValue: event?.diaperKind ?? .wet)
        _diaperRash = State(initialValue: event?.diaperRash == true)
        _childPottyKind = State(initialValue: event?.childPottyKind ?? .pee)
        _childPottyLocation = State(initialValue: event?.childPottyLocation ?? .pottyChair)
        _childPottyAccident = State(initialValue: event?.childPottyAccident ?? false)
        _peeAmount = State(initialValue: event?.peeAmount ?? .unknown)
        _pooAmount = State(initialValue: event?.pooAmount ?? .unknown)
        _pooColor = State(initialValue: event?.pooColor ?? .unknown)
        _pooTexture = State(initialValue: event?.pooTexture ?? .unknown)
        _diaperDetailsExpanded = State(initialValue: true)
        _medicineName = State(initialValue: event?.medicineName ?? "")
        _dose = State(initialValue: event?.dose ?? 0)
        _medicineUnit = State(initialValue: event?.medicineUnit ?? .milliliters)
        _reason = State(initialValue: event?.reason ?? "")
        _activityType = State(initialValue: event?.activityType ?? .tummyTime)
        let lengthParts = event?.canonicalLengthCentimeters.map(
            GrowthUnitConversion.centimetersToFeetAndInches
        )
        let weightParts = event?.canonicalWeightKilograms.map(
            GrowthUnitConversion.kilogramsToPoundsAndOunces
        )
        _heightFeet = State(initialValue: event?.heightFeet ?? lengthParts?.feet ?? 0)
        _heightInches = State(initialValue: event?.heightInches ?? lengthParts?.inches ?? 0)
        _weightPounds = State(initialValue: event?.weightPounds ?? weightParts?.pounds ?? 0)
        _weightOunces = State(initialValue: event?.weightOunces ?? weightParts?.ounces ?? 0)
        _headCircumferenceInches = State(
            initialValue: event?.headCircumferenceInches
                ?? event?.canonicalHeadCircumferenceCentimeters.map {
                    $0 / GrowthUnitConversion.centimetersPerInch
                }
        )
        _growthSex = State(initialValue: event?.growthSex ?? .unknown)
        _growthSource = State(initialValue: event?.growthSource ?? .pediatrician)
        let selectedTemperatureUnit = event?.temperatureUnit ?? .fahrenheit
        _temperatureUnit = State(initialValue: selectedTemperatureUnit)
        _temperatureValue = State(
            initialValue: event?.temperatureValue(in: selectedTemperatureUnit)
                ?? (selectedTemperatureUnit == .fahrenheit ? 98.6 : 37)
        )
        _temperatureMethod = State(initialValue: event?.temperatureMethod ?? .forehead)
        let dog = event?.dogDetails ?? DogEventDetails()
        _dogFoodName = State(initialValue: dog.foodName ?? "")
        _dogFoodAmount = State(initialValue: dog.foodAmount ?? 0)
        _dogFoodUnit = State(initialValue: dog.foodUnit ?? .scoop)
        _dogMealType = State(initialValue: dog.mealType ?? .breakfast)
        _dogEatenAmount = State(initialValue: dog.eatenAmount ?? .unknown)
        _dogWaterAmount = State(initialValue: dog.waterAmount ?? 0)
        _dogWaterUnit = State(initialValue: dog.waterUnit ?? .bowl)
        _dogTreatName = State(initialValue: dog.treatName ?? "")
        _dogTreatQuantity = State(initialValue: dog.treatQuantity ?? 0)
        _dogPottyType = State(initialValue: dog.pottyType ?? .pee)
        _dogPottyLocation = State(initialValue: dog.pottyLocation ?? .outside)
        _dogPottyAccident = State(initialValue: dog.accident ?? false)
        _dogPeeAmount = State(initialValue: dog.peeAmount ?? .unknown)
        _dogPeeColor = State(initialValue: dog.peeColor ?? .unknown)
        _dogPoopAmount = State(initialValue: dog.poopAmount ?? .unknown)
        _dogStoolQuality = State(initialValue: dog.stoolQuality ?? .unknown)
        _dogPoopColor = State(initialValue: dog.poopColor ?? .unknown)
        _dogDistance = State(initialValue: dog.distance ?? 0)
        _dogDistanceUnit = State(initialValue: dog.distanceUnit ?? .miles)
        _dogPeeCount = State(initialValue: dog.peeCount ?? 0)
        _dogPoopCount = State(initialValue: dog.poopCount ?? 0)
        _dogLeashBehavior = State(initialValue: dog.leashBehavior ?? .unknown)
        _dogWeather = State(initialValue: dog.weather ?? "")
        _dogRestType = State(initialValue: dog.restType ?? .nap)
        _dogTrainingType = State(initialValue: dog.trainingType ?? .obedience)
        _dogTrainingSkill = State(initialValue: dog.trainingSkill ?? "")
        _dogTrainingOutcome = State(initialValue: dog.trainingOutcome ?? .notApplicable)
        _dogGroomingType = State(initialValue: dog.groomingType ?? .brush)
        _dogMedicineUnit = State(initialValue: dog.medicineUnit ?? .tablet)
        _dogMedicineRoute = State(initialValue: dog.medicineRoute ?? .oral)
        _dogVaccineType = State(initialValue: dog.vaccineType ?? .rabies)
        _dogHasVaccineDueDate = State(initialValue: dog.vaccineDueDate != nil)
        _dogVaccineDueDate = State(initialValue: dog.vaccineDueDate ?? Date())
        _dogVaccineLotNumber = State(initialValue: dog.vaccineLotNumber ?? "")
        _dogVaccineClinic = State(initialValue: dog.vaccineClinic ?? "")
        _dogSymptomType = State(initialValue: dog.symptomType ?? .other)
        _dogSymptomSeverity = State(initialValue: dog.symptomSeverity ?? .unknown)
        _dogSymptomResolved = State(initialValue: dog.symptomResolved ?? false)
        _dogGlucoseValue = State(initialValue: dog.glucoseValue ?? 0)
        _dogGlucoseUnit = State(initialValue: dog.glucoseUnit ?? .mgdl)
        _dogGlucoseMealRelation = State(initialValue: dog.glucoseMealRelation ?? .unknown)
        _recentMedicineNames = State(initialValue: [])
        _growthMeasurementEditor = State(initialValue: nil)
        _showingSolidFoodPicker = State(initialValue: false)
    }

    private var selectedProfile: CareProfile? {
        profileService.selectedProfile(in: profiles)
    }
    private var activeProfileID: UUID? {
        existingEvent?.profileID ?? selectedProfile?.id
    }

    private var activeProfileType: CareProfileType {
        existingEvent?.profileTypeSnapshot ?? selectedProfile?.profileType ?? .child
    }
    private var activeProfile: CareProfile? {
        guard let activeProfileID else { return selectedProfile }
        return profiles.first { $0.id == activeProfileID }
    }
    private var isDogProfile: Bool {
        activeProfileType == .dog
    }
    private var solidsAccessLevel: SolidsAccessLevel {
        SolidsTrackingService.accessLevel(
            for: activeProfile,
            events: allEvents,
            state: solidsProfileStates.first { $0.profileID == activeProfileID }
        )
    }
    private var canLogSolidFeed: Bool {
        activeProfileType == .child && solidsAccessLevel == .full
    }
    private var availableFeedKinds: [FeedKind] {
        FeedKind.allCases.filter { $0 != .solid || canLogSolidFeed }
    }
    private var temperatureMethods: [TemperatureMethod] {
        isDogProfile ? [.rectal, .ear, .unknown] : TemperatureMethod.allCases
    }
    private var activeCaregiverName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: currentCaregiverName,
            primaryName: caregiverOne
        )
    }

    private var positiveAmountOz: Double? {
        Self.positiveAmount(from: amountOzText)
    }

    private var selectedSolidFoodNames: [String] {
        SolidFoodSelection.names(from: foodDescription)
    }

    private static func initialSolidFoodDetails(
        event: BabyEvent?,
        preset: SolidFeedEditorPreset?
    ) -> [SolidFoodLogDetail] {
        if let event, !event.solidFoodDetails.isEmpty { return event.solidFoodDetails }
        let names = SolidFoodSelection.names(
            from: event?.foodDescription ?? SolidFoodSelection.description(from: preset?.foodNames ?? [])
        )
        let presetIDs = Dictionary(
            uniqueKeysWithValues: zip(preset?.foodNames ?? [], preset?.foodIDs ?? []).map {
                (SolidFoodSelection.normalizedName($0.0), $0.1)
            }
        )
        let presetConfirmedAllergens = Set(preset?.confirmedAllergenPortionIDs ?? [])
        return names.map { name in
            let reference = SolidsReferenceCatalog.food(named: name)
            let foodID = presetIDs[SolidFoodSelection.normalizedName(name)]
                ?? reference?.id
                ?? "custom-\(SolidFoodSelection.normalizedName(name).replacingOccurrences(of: " ", with: "-"))"
            let allergenIDs = preset?.allergenIDsByFoodID[foodID] ?? reference?.allergenIDs ?? []
            return SolidFoodLogDetail(
                foodID: foodID,
                foodName: reference?.name ?? name,
                allergenIDs: allergenIDs,
                confirmedAllergenPortionIDs: allergenIDs.filter(presetConfirmedAllergens.contains),
                preference: event?.solidReaction == .sensitivity ? .unknown : event?.solidReaction ?? .unknown,
                suspectedReaction: event?.solidSensitivityObserved == true || event?.solidReaction == .sensitivity
            )
        }
    }

    private func syncSolidFoodDetails(names: [String]) {
        let existingByName = Dictionary(
            uniqueKeysWithValues: solidFoodDetails.map {
                (SolidFoodSelection.normalizedName($0.foodName), $0)
            }
        )
        solidFoodDetails = names.map { name in
            let key = SolidFoodSelection.normalizedName(name)
            if var existing = existingByName[key] {
                let catalogAllergens = SolidsReferenceCatalog.food(id: existing.foodID)?.allergenIDs
                    ?? customSolidFoods.first(where: {
                        "custom-\($0.id.uuidString.lowercased())" == existing.foodID
                            || $0.normalizedName == key
                    })?.allergenIDs
                    ?? []
                if existing.allergenIDs.isEmpty, !catalogAllergens.isEmpty {
                    existing.allergenIDs = catalogAllergens
                    existing.confirmedAllergenPortionIDs = []
                }
                return existing
            }
            if let reference = SolidsReferenceCatalog.food(named: name) {
                return SolidFoodLogDetail(
                    foodID: reference.id,
                    foodName: reference.name,
                    allergenIDs: reference.allergenIDs,
                    confirmedAllergenPortionIDs: []
                )
            }
            if let custom = customSolidFoods.first(where: { $0.normalizedName == key }) {
                return SolidFoodLogDetail(
                    foodID: "custom-\(custom.id.uuidString.lowercased())",
                    foodName: custom.name,
                    allergenIDs: custom.allergenIDs,
                    confirmedAllergenPortionIDs: []
                )
            }
            return SolidFoodLogDetail(
                foodID: "custom-\(key.replacingOccurrences(of: " ", with: "-"))",
                foodName: name,
                confirmedAllergenPortionIDs: []
            )
        }
    }

    private var recentSolidFoodNames: [String] {
        var seen = Set<String>()
        var result = [String]()
        for event in allEvents where event.id != existingEvent?.id {
            guard event.type == .feed,
                  event.feedKind == .solid,
                  event.matchesProfile(activeProfileID) else { continue }
            for name in SolidFoodSelection.names(from: event.foodDescription) {
                let normalizedName = SolidFoodSelection.normalizedName(name)
                guard seen.insert(normalizedName).inserted else { continue }
                result.append(name)
                if result.count == 8 { return result }
            }
        }
        return result
    }

    private var startTimeZone: TimeZone {
        TimeZone(identifier: startTimeZoneIdentifier) ?? .autoupdatingCurrent
    }

    private var endTimeZone: TimeZone {
        TimeZone(identifier: endTimeZoneIdentifier) ?? startTimeZone
    }

    private static func amountText(for amount: Double?) -> String {
        guard let amount, amount > 0 else { return "" }
        return amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static let positiveAmountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter
    }()

    private static func positiveAmount(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let amount = positiveAmountFormatter.number(from: trimmed)?.doubleValue, amount > 0 {
            return amount
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else { return nil }
        return amount
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $type) {
                    ForEach(EventType.cases(for: activeProfileType)) { type in
                        Label(type.displayName, systemImage: type.systemImage(for: activeProfileType)).tag(type)
                    }
                }
                if type == .custom || (type == .activity && activityType == .custom) {
                    TextField("Title", text: $title)
                }
                DatePicker("Start", selection: $startDate)
                    .environment(\.timeZone, startTimeZone)
                if type.supportsTimer {
                    Toggle("Has ended", isOn: $hasEndDate)
                }
                if type.supportsTimer, hasEndDate {
                    DatePicker("End", selection: $endDate, in: startDate...)
                        .environment(\.timeZone, endTimeZone)
                }
                LabeledContent("Logged by") {
                    TextField("Name", text: $caregiverName)
                        .textContentType(.name)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Event")
            } footer: {
                Text("This name is saved with the event so history can show who logged it.")
            }

            Section {
                NavigationLink {
                    TimeZonePickerView(selection: $startTimeZoneIdentifier)
                } label: {
                    LabeledContent(
                        "Start time zone",
                        value: CareTimeZoneSettings.displayName(
                            for: startTimeZone,
                            on: startDate
                        )
                    )
                }

                if type.supportsTimer, hasEndDate {
                    NavigationLink {
                        TimeZonePickerView(selection: $endTimeZoneIdentifier)
                    } label: {
                        LabeledContent(
                            "End time zone",
                            value: CareTimeZoneSettings.displayName(
                                for: endTimeZone,
                                on: endDate
                            )
                        )
                    }
                }
            } header: {
                Text("Time zones")
            } footer: {
                Text("Clock times stay attached to these zones when you travel. Durations use real elapsed time, even when the start and end are in different zones.")
            }

            eventSpecificFields

            Section("Notes") {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(existingEvent == nil ? "Add Event" : "Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard existingEvent == nil,
                  caregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            caregiverName = activeCaregiverName
        }
        .onAppear(perform: refreshRecentMedicineNamesIfNeeded)
        .onAppear(perform: normalizeDogTemperatureMethod)
        .onAppear {
            if type == .feed, feedKind == .solid {
                syncSolidFoodDetails(names: selectedSolidFoodNames)
            }
        }
        .onChange(of: type) { _, newType in
            if newType == .temperature {
                normalizeDogTemperatureMethod()
            }
            refreshRecentMedicineNamesIfNeeded()
        }
        .onChange(of: activeProfileID) {
            refreshRecentMedicineNamesIfNeeded()
        }
        .sheet(item: $growthMeasurementEditor) { editor in
            GrowthMeasurementInputSheet(
                kind: editor,
                initialImperialValue: growthMeasurementImperialValue(for: editor)
            ) { value in
                saveGrowthMeasurement(editor, imperialValue: value)
            }
            .presentationDetents([.height(600), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSolidFoodPicker) {
            SolidFoodPickerView(
                initialSelection: selectedSolidFoodNames,
                recentFoodNames: recentSolidFoodNames
            ) { names in
                foodDescription = SolidFoodSelection.description(from: names) ?? ""
                syncSolidFoodDetails(names: names)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingSolidFoodID != nil },
            set: { if !$0 { editingSolidFoodID = nil } }
        )) {
            if let editingSolidFoodID,
               let index = solidFoodDetails.firstIndex(where: { $0.foodID == editingSolidFoodID }) {
                NavigationStack {
                    SolidFoodLogDetailEditor(detail: $solidFoodDetails[index])
                }
            }
        }
        .appActionSheet(
            isPresented: $showingSolidFeedingStyleOptions,
            title: "Feeding style",
            message: "Choose how the solid meal was offered.",
            systemImage: "fork.knife",
            tint: .orange,
            options: SolidFeedingStyle.allCases.map { value in
                AppActionSheetOption(
                    title: value.displayName,
                    systemImage: "fork.knife",
                    tint: .orange,
                    isSelected: solidFeedingStyle == value
                ) {
                    solidFeedingStyle = value
                }
            }
        )
        .appActionSheet(
            isPresented: $showingSolidTextureOptions,
            title: "Food texture",
            message: "Choose the texture that best describes this meal.",
            systemImage: "square.stack.3d.up",
            tint: .orange,
            options: SolidTexture.allCases.map { value in
                AppActionSheetOption(
                    title: value.displayName,
                    systemImage: "circle.grid.3x3.fill",
                    tint: .orange,
                    isSelected: solidTexture == value
                ) {
                    solidTexture = value
                }
            }
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .alert("Check this event", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
        }
        .onChange(of: startTimeZoneIdentifier) { oldValue, newValue in
            if endTimeZoneIdentifier == oldValue {
                endTimeZoneIdentifier = newValue
            }
        }
        .onChange(of: hasEndDate) { _, hasEnded in
            if hasEnded, TimeZone(identifier: endTimeZoneIdentifier) == nil {
                endTimeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
            }
        }
        .onChange(of: temperatureUnit) { oldValue, newValue in
            guard oldValue != newValue else { return }
            temperatureValue = newValue == .celsius
                ? (temperatureValue - 32) * 5 / 9
                : temperatureValue * 9 / 5 + 32
        }
        .task {
            if type == .growth,
               growthSex == .unknown,
               let profile = profileService.selectedProfile(in: profiles) {
                growthSex = profile.sex
            }
        }
    }

    @ViewBuilder
    private var eventSpecificFields: some View {
        switch type {
        case .sleep:
            Section("Sleep") {
                Picker("Kind", selection: $sleepKind) {
                    ForEach(SleepKind.allCases) { Text($0.displayName).tag($0) }
                }
                if sleepKind == .nightWaking {
                    Text("Night waking tracks awake time during the overnight period and is used in sleep insights, not as sleep duration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .feed:
            Section("Feed") {
                Picker("Kind", selection: $feedKind) {
                    ForEach(availableFeedKinds) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("event.feed-kind")
                if feedKind == .bottle {
                    LabeledContent("Amount") {
                        TextField("Optional", text: $amountOzText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if feedKind == .solid {
                    SolidFoodSelectionRow(
                        foodNames: selectedSolidFoodNames,
                        onChooseFoods: { showingSolidFoodPicker = true }
                    )
                    if !solidFoodDetails.isEmpty {
                        SolidFoodDetailSummary(
                            details: solidFoodDetails,
                            edit: { editingSolidFoodID = $0 }
                        )
                    }
                    solidsSelectionButton(
                        title: "Style",
                        value: solidFeedingStyle.displayName,
                        systemImage: "fork.knife"
                    ) {
                        showingSolidFeedingStyleOptions = true
                    }
                    solidsSelectionButton(
                        title: "Texture",
                        value: solidTexture.displayName,
                        systemImage: "square.stack.3d.up"
                    ) {
                        showingSolidTextureOptions = true
                    }
                    Text("Preference, allergens, and possible reactions are recorded for each selected food. Contact your pediatrician for allergy or medical concerns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Details", text: $foodDescription)
                }
            }
        case .pumping:
            Section("Pumping") {
                LabeledContent("Amount pumped") {
                    TextField("Optional", text: $amountOzText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Details", text: $foodDescription)
            }
        case .nursing:
            Section("Nursing") {
                Picker("Side", selection: $nursingSide) {
                    ForEach(NursingSide.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Duration") {
                    HStack(spacing: 6) {
                        TextField("0", value: $nursingMinutes, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("min")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .diaper:
            Section("Diaper") {
                Picker("Kind", selection: $diaperKind) {
                    ForEach(DiaperKind.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                DisclosureGroup(
                    "Optional details",
                    isExpanded: $diaperDetailsExpanded
                ) {
                    if diaperKind.hasPee {
                        Picker("Pee amount", selection: $peeAmount) {
                            ForEach(DiaperAmount.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    if diaperKind.hasPoo {
                        Picker("Poo amount", selection: $pooAmount) {
                            ForEach(DiaperAmount.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("Color", selection: $pooColor) {
                            ForEach(PooColor.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("Texture", selection: $pooTexture) {
                            ForEach(PooTexture.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    Toggle("Diaper rash", isOn: $diaperRash)
                        .accessibilityIdentifier("diaper-rash-toggle")
                }
            }
        case .medicine:
            Section("Medicine") {
                TextField(isDogProfile ? "Medication or supplement name" : "Medicine name", text: $medicineName)
                if !recentMedicineNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(recentMedicineNames, id: \.self) { name in
                                Button(name) { medicineName = name }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Dose", value: $dose, format: .number)
                        .keyboardType(.decimalPad)
                    if activeProfileType == .dog {
                        Picker("Unit", selection: $dogMedicineUnit) {
                            ForEach(DogMedicineUnit.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                    } else {
                        Picker("Unit", selection: $medicineUnit) {
                            ForEach(MedicineUnit.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                if activeProfileType == .dog {
                    Picker("Route", selection: $dogMedicineRoute) {
                        ForEach(DogMedicineRoute.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text("Little Windows records medicines only and does not provide dosing advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Reason", text: $reason)
            }
        case .growth:
            Section("Growth") {
                Button {
                    growthMeasurementEditor = .weight
                } label: {
                    GrowthMeasurementRow(
                        title: "Weight",
                        value: weightDisplayText
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("growth-weight-row")

                Button {
                    growthMeasurementEditor = .height
                } label: {
                    GrowthMeasurementRow(
                        title: isDogProfile ? "Length/height" : "Height",
                        value: heightDisplayText
                    )
                }
                .buttonStyle(.plain)

                if !isDogProfile {
                    Button {
                        growthMeasurementEditor = .headCircumference
                    } label: {
                        GrowthMeasurementRow(
                            title: "Head circumference",
                            value: headCircumferenceDisplayText
                        )
                    }
                    .buttonStyle(.plain)
                }
                Picker(isDogProfile ? "Measured by" : "Measured at", selection: $growthSource) {
                    ForEach(GrowthMeasurementSource.allCases) {
                        Text($0.displayName(for: activeProfileType)).tag($0)
                    }
                }
                if !isDogProfile {
                    Picker("Reference sex", selection: $growthSex) {
                        ForEach(BabySex.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
            }
        case .temperature:
            Section("Temperature") {
                Picker("Unit", selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                TemperatureSlider(value: $temperatureValue, unit: temperatureUnit)

                LabeledContent("Exact value") {
                    HStack(spacing: 5) {
                        TextField(
                            "Temperature",
                            value: $temperatureValue,
                            format: .number.precision(.fractionLength(1))
                        )
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        Text(temperatureUnit.displayName)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Method", selection: $temperatureMethod) {
                    ForEach(temperatureMethods) { Text($0.displayName).tag($0) }
                }
            }
        case .activity:
            Section("Activity") {
                Picker("Activity", selection: $activityType) {
                    ForEach(ActivityType.allCases) {
                        Label($0.displayName, systemImage: $0.systemImage).tag($0)
                    }
                }
            }
        case .food:
            Section("Food") {
                TextField("Food type/name", text: $dogFoodName)
                HStack {
                    TextField("Amount", value: $dogFoodAmount, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $dogFoodUnit) {
                        ForEach(DogAmountUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                }
                Picker("Meal", selection: $dogMealType) {
                    ForEach(DogMealType.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Eaten", selection: $dogEatenAmount) {
                    ForEach(DogEatenAmount.allCases) { Text($0.displayName).tag($0) }
                }
            }
        case .water:
            Section("Water") {
                HStack {
                    TextField("Amount optional", value: $dogWaterAmount, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $dogWaterUnit) {
                        ForEach(DogWaterUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                }
            }
        case .treat:
            Section("Treat") {
                LabeledContent("Treat") {
                    TextField("Type or name", text: $dogTreatName)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Quantity") {
                    TextField("Optional", value: $dogTreatQuantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        case .potty:
            if isDogProfile {
                Section("Potty") {
                    Picker("Type", selection: $dogPottyType) {
                        ForEach(DogPottyType.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Location", selection: $dogPottyLocation) {
                        ForEach(DogPottyLocation.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Accident", isOn: $dogPottyAccident)
                    if dogPottyType.hasPee {
                        Picker("Pee amount", selection: $dogPeeAmount) {
                            ForEach(DiaperAmount.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("Pee color", selection: $dogPeeColor) {
                            ForEach(DogPeeColor.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    if dogPottyType.hasPoop {
                        Picker("Poop amount", selection: $dogPoopAmount) {
                            ForEach(DiaperAmount.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("Stool quality", selection: $dogStoolQuality) {
                            ForEach(DogStoolQuality.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("Poop color", selection: $dogPoopColor) {
                            ForEach(DogPoopColor.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                }
            } else {
                Section("Potty") {
                    Picker("Type", selection: $childPottyKind) {
                        ForEach(ChildPottyKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Location", selection: $childPottyLocation) {
                        ForEach(ChildPottyLocation.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Accident", isOn: $childPottyAccident)
                    if childPottyKind.hasPee {
                        Picker("Pee amount", selection: $peeAmount) {
                            ForEach(DiaperAmount.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    if childPottyKind.hasPoo {
                        Picker("Poo amount", selection: $pooAmount) {
                            ForEach(DiaperAmount.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("Color", selection: $pooColor) {
                            ForEach(PooColor.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("Texture", selection: $pooTexture) {
                            ForEach(PooTexture.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                }
            }
        case .walk:
            Section("Walk") {
                HStack {
                    TextField("Distance optional", value: $dogDistance, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $dogDistanceUnit) {
                        ForEach(DogDistanceUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                }
                Stepper("Pee count: \(dogPeeCount)", value: $dogPeeCount, in: 0...20)
                Stepper("Poop count: \(dogPoopCount)", value: $dogPoopCount, in: 0...20)
                Picker("Leash behavior", selection: $dogLeashBehavior) {
                    ForEach(DogLeashBehavior.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Weather optional", text: $dogWeather)
                Text("Walks are timer-capable, but Little Windows does not track GPS routes or request location permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .rest:
            Section("Sleep/Rest") {
                Picker("Rest type", selection: $dogRestType) {
                    ForEach(DogRestType.allCases) { Text($0.displayName).tag($0) }
                }
            }
        case .training:
            Section("Training") {
                Picker("Training type", selection: $dogTrainingType) {
                    ForEach(DogTrainingType.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Command or skill", text: $dogTrainingSkill)
                Picker("Outcome", selection: $dogTrainingOutcome) {
                    ForEach(DogTrainingOutcome.allCases) { Text($0.displayName).tag($0) }
                }
            }
        case .grooming:
            Section("Grooming") {
                Picker("Type", selection: $dogGroomingType) {
                    ForEach(DogGroomingType.allCases) { Text($0.displayName).tag($0) }
                }
            }
        case .symptom:
            Section("Symptom") {
                Picker("Symptom", selection: $dogSymptomType) {
                    ForEach(DogSymptomType.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Severity", selection: $dogSymptomSeverity) {
                    ForEach(DogSymptomSeverity.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Resolved", isOn: $dogSymptomResolved)
                Text("Little Windows tracks symptoms for your records and does not diagnose. Contact your vet if you're concerned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .vaccine:
            Section("Vaccine") {
                Picker("Vaccine", selection: $dogVaccineType) {
                    ForEach(DogVaccineType.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Has next due/expiration date", isOn: $dogHasVaccineDueDate)
                if dogHasVaccineDueDate {
                    DatePicker("Next due", selection: $dogVaccineDueDate, displayedComponents: .date)
                }
                TextField("Lot number optional", text: $dogVaccineLotNumber)
                TextField("Clinic/vet optional", text: $dogVaccineClinic)
            }
        case .glucose:
            Section("Glucose") {
                HStack {
                    TextField("Value", value: $dogGlucoseValue, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $dogGlucoseUnit) {
                        ForEach(DogGlucoseUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                }
                Picker("Relation to meal", selection: $dogGlucoseMealRelation) {
                    ForEach(DogMealRelation.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Glucose logs are for tracking only and are not interpreted medically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .custom:
            EmptyView()
        }
    }

    private func solidsSelectionButton(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(value)
    }

    private var weightDisplayText: String {
        guard weightPounds > 0 || weightOunces > 0 else { return "Add" }
        let ounces = weightOunces.formatted(.number.precision(.fractionLength(0...1)))
        return "\(weightPounds) lb \(ounces) oz"
    }

    private var heightDisplayText: String {
        guard heightFeet > 0 || heightInches > 0 else { return "Add" }
        let inches = heightInches.formatted(.number.precision(.fractionLength(0...1)))
        return "\(heightFeet) ft \(inches) in"
    }

    private var headCircumferenceDisplayText: String {
        guard let headCircumferenceInches, headCircumferenceInches > 0 else { return "Add" }
        return "\(headCircumferenceInches.formatted(.number.precision(.fractionLength(0...1)))) in"
    }

    private func growthMeasurementImperialValue(
        for kind: GrowthMeasurementEditorKind
    ) -> Double? {
        switch kind {
        case .height:
            let total = Double(heightFeet) * 12 + heightInches
            return total > 0 ? total : nil
        case .weight:
            let total = Double(weightPounds) + weightOunces / 16
            return total > 0 ? total : nil
        case .headCircumference:
            return headCircumferenceInches.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    private func saveGrowthMeasurement(
        _ kind: GrowthMeasurementEditorKind,
        imperialValue: Double?
    ) {
        let value = max(0, imperialValue ?? 0)
        switch kind {
        case .height:
            guard value > 0 else {
                heightFeet = 0
                heightInches = 0
                return
            }
            heightFeet = Int(value / 12)
            heightInches = roundedTenths(value.truncatingRemainder(dividingBy: 12))
            normalizeHeightParts()
        case .weight:
            guard value > 0 else {
                weightPounds = 0
                weightOunces = 0
                return
            }
            weightPounds = Int(value)
            weightOunces = roundedTenths((value - Double(weightPounds)) * 16)
            normalizeWeightParts()
        case .headCircumference:
            headCircumferenceInches = value > 0 ? roundedTenths(value) : nil
        }
    }

    private func roundedTenths(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private func normalizeHeightParts() {
        guard heightInches >= 12 else { return }
        heightFeet += Int(heightInches / 12)
        heightInches = roundedTenths(heightInches.truncatingRemainder(dividingBy: 12))
    }

    private func normalizeWeightParts() {
        guard weightOunces >= 16 else { return }
        weightPounds += Int(weightOunces / 16)
        weightOunces = roundedTenths(weightOunces.truncatingRemainder(dividingBy: 16))
    }

    private func save() {
        if type.supportsTimer, hasEndDate, endDate < startDate {
            validationMessage = "End time must be after the start time."
            return
        }
        if type == .medicine, medicineName.trimmingCharacters(in: .whitespaces).isEmpty {
            validationMessage = "Enter the medicine name."
            return
        }
        if type == .custom, title.trimmingCharacters(in: .whitespaces).isEmpty {
            validationMessage = "Enter a title for the custom event."
            return
        }
        if type == .activity, activityType == .custom,
           title.trimmingCharacters(in: .whitespaces).isEmpty {
            validationMessage = "Enter a title for the custom activity."
            return
        }
        if type == .feed, feedKind == .solid, !canLogSolidFeed {
            validationMessage = activeProfileType == .dog
                ? "Use the dog food log for this profile."
                : "Start the Solids workspace from the readiness preview before logging an early meal."
            return
        }
        if type == .feed, feedKind == .solid, selectedSolidFoodNames.isEmpty {
            validationMessage = "Choose at least one food for this solids meal."
            return
        }
        if activeProfileType == .dog, type == .glucose, dogGlucoseValue <= 0 {
            validationMessage = "Enter a glucose value."
            return
        }
        if type == .growth,
           weightPounds == 0, weightOunces == 0,
           heightFeet == 0, heightInches == 0,
           (headCircumferenceInches ?? 0) == 0 {
            validationMessage = "Enter at least one growth measurement."
            return
        }

        let wasActiveTimer = existingEvent?.isTimerDraft == true
        let event = existingEvent ?? BabyEvent(type: type)
        event.type = type
        event.profileTypeSnapshot = activeProfileType
        event.title = title.nilIfBlank
        if wasActiveTimer {
            EventTimerService.adjustStartDate(event, to: startDate)
        } else {
            event.startDate = startDate
        }
        event.endDate = type.supportsTimer && hasEndDate ? max(endDate, startDate) : nil
        event.startTimeZoneIdentifier = startTimeZone.identifier
        event.endTimeZoneIdentifier = type.supportsTimer && hasEndDate
            ? endTimeZone.identifier
            : nil
        event.caregiverName = caregiverName.nilIfBlank
        event.notes = notes.nilIfBlank
        event.sleepKind = type == .sleep ? sleepKind : nil
        event.feedKind = type == .feed ? feedKind : nil
        event.amountOz = type == .feed && feedKind == .bottle ? positiveAmountOz : nil
        if type == .pumping {
            event.amountOz = positiveAmountOz
        }
        event.foodDescription = type == .feed ? foodDescription.nilIfBlank : nil
        if type == .pumping {
            event.foodDescription = foodDescription.nilIfBlank
        }
        if type == .feed && feedKind == .solid {
            syncSolidFoodDetails(names: selectedSolidFoodNames)
            event.solidFoodDetails = solidFoodDetails
            let preferences = Set(solidFoodDetails.map(\.preference).filter { $0 != .unknown })
            event.solidReaction = preferences.count == 1 ? preferences.first : .unknown
            event.solidAllergenExposure = solidFoodDetails.contains { !$0.allergenIDs.isEmpty }
            event.solidSensitivityObserved = solidFoodDetails.contains { $0.suspectedReaction }
        } else {
            event.solidFoodDetailsJSON = nil
            event.solidReaction = nil
            event.solidAllergenExposure = nil
            event.solidSensitivityObserved = nil
        }
        event.solidTexture = type == .feed && feedKind == .solid ? solidTexture : nil
        event.solidFeedingStyle = type == .feed && feedKind == .solid ? solidFeedingStyle : nil
        if !wasActiveTimer {
            event.nursingSide = type == .nursing ? nursingSide : nil
            event.leftDurationSeconds = type == .nursing && nursingSide == .left && nursingMinutes > 0
                ? nursingMinutes * 60
                : nil
            event.rightDurationSeconds = type == .nursing && nursingSide == .right && nursingMinutes > 0
                ? nursingMinutes * 60
                : nil
        }
        event.diaperKind = type == .diaper ? diaperKind : nil
        event.diaperRash = type == .diaper && diaperRash ? true : nil
        event.childPottyKind = type == .potty && !isDogProfile ? childPottyKind : nil
        event.childPottyLocation = type == .potty && !isDogProfile ? childPottyLocation : nil
        event.childPottyAccident = type == .potty && !isDogProfile ? childPottyAccident : nil
        event.peeAmount = (type == .diaper && diaperKind.hasPee) || (type == .potty && !isDogProfile && childPottyKind.hasPee) ? peeAmount : nil
        event.pooAmount = (type == .diaper && diaperKind.hasPoo) || (type == .potty && !isDogProfile && childPottyKind.hasPoo) ? pooAmount : nil
        event.pooColor = (type == .diaper && diaperKind.hasPoo) || (type == .potty && !isDogProfile && childPottyKind.hasPoo) ? pooColor : nil
        event.pooTexture = (type == .diaper && diaperKind.hasPoo) || (type == .potty && !isDogProfile && childPottyKind.hasPoo) ? pooTexture : nil
        event.stoolColor = nil
        event.stoolTexture = nil
        event.bookTitle = nil
        event.medicineName = (type == .medicine || type == .vaccine) ? medicineName.nilIfBlank : nil
        event.dose = type == .medicine && dose > 0 ? dose : nil
        if type == .medicine, dose > 0 {
            if activeProfileType == .dog {
                event.doseUnit = dogMedicineUnit.rawValue
            } else {
                event.medicineUnit = medicineUnit
            }
        } else {
            event.doseUnit = nil
        }
        event.reason = type == .medicine ? reason.nilIfBlank : nil
        event.activityType = type == .activity ? activityType : nil
        event.heightFeet = type == .growth && heightFeet > 0 ? heightFeet : nil
        event.heightInches = type == .growth && heightInches > 0 ? heightInches : nil
        event.weightPounds = type == .growth && weightPounds > 0 ? weightPounds : nil
        event.weightOunces = type == .growth && weightOunces > 0 ? weightOunces : nil
        event.headCircumferenceInches = type == .growth && !isDogProfile
            ? headCircumferenceInches.flatMap { $0 > 0 ? $0 : nil }
            : nil
        event.weightKilograms = type == .growth && (weightPounds > 0 || weightOunces > 0)
            ? GrowthUnitConversion.poundsAndOuncesToKilograms(
                pounds: weightPounds,
                ounces: weightOunces
            )
            : nil
        event.lengthCentimeters = type == .growth && (heightFeet > 0 || heightInches > 0)
            ? GrowthUnitConversion.feetAndInchesToCentimeters(
                feet: heightFeet,
                inches: heightInches
            )
            : nil
        event.headCircumferenceCentimeters = type == .growth && !isDogProfile
            ? headCircumferenceInches.flatMap {
                $0 > 0 ? GrowthUnitConversion.inchesToCentimeters($0) : nil
            }
            : nil
        event.growthSexRawValue = type == .growth && !isDogProfile ? growthSex.rawValue : nil
        event.growthSource = type == .growth ? growthSource : nil
        event.temperatureCelsius = type == .temperature
            ? (temperatureUnit == .celsius ? temperatureValue : (temperatureValue - 32) * 5 / 9)
            : nil
        event.temperatureUnitRawValue = type == .temperature ? temperatureUnit.rawValue : nil
        event.temperatureMethod = type == .temperature ? temperatureMethod : nil
        event.dogDetails = activeProfileType == .dog ? dogDetailsForSave() : DogEventDetails()
        event.updatedAt = Date()
        if existingEvent == nil { modelContext.insert(event) }
        onSave(event)
        dismiss()
    }

    private func normalizeDogTemperatureMethod() {
        guard isDogProfile, type == .temperature, !temperatureMethods.contains(temperatureMethod) else { return }
        temperatureMethod = .rectal
    }

    private func dogDetailsForSave() -> DogEventDetails {
        var details = DogEventDetails()
        details.foodName = dogFoodName.nilIfBlank
        details.foodAmount = dogFoodAmount > 0 ? dogFoodAmount : nil
        details.foodUnit = dogFoodAmount > 0 ? dogFoodUnit : nil
        details.mealType = dogMealType
        details.eatenAmount = dogEatenAmount
        details.waterAmount = dogWaterAmount > 0 ? dogWaterAmount : nil
        details.waterUnit = dogWaterAmount > 0 ? dogWaterUnit : nil
        details.treatName = dogTreatName.nilIfBlank
        details.treatQuantity = dogTreatQuantity > 0 ? dogTreatQuantity : nil
        details.pottyType = dogPottyType
        details.pottyLocation = dogPottyLocation
        details.accident = dogPottyAccident
        details.peeAmount = dogPottyType.hasPee ? dogPeeAmount : nil
        details.peeColor = dogPottyType.hasPee ? dogPeeColor : nil
        details.poopAmount = dogPottyType.hasPoop ? dogPoopAmount : nil
        details.stoolQuality = dogPottyType.hasPoop ? dogStoolQuality : nil
        details.poopColor = dogPottyType.hasPoop ? dogPoopColor : nil
        details.distance = dogDistance > 0 ? dogDistance : nil
        details.distanceUnit = dogDistance > 0 ? dogDistanceUnit : nil
        details.peeCount = dogPeeCount > 0 ? dogPeeCount : nil
        details.poopCount = dogPoopCount > 0 ? dogPoopCount : nil
        details.leashBehavior = dogLeashBehavior
        details.weather = dogWeather.nilIfBlank
        details.restType = dogRestType
        details.trainingType = dogTrainingType
        details.trainingSkill = dogTrainingSkill.nilIfBlank
        details.trainingOutcome = dogTrainingOutcome
        details.groomingType = dogGroomingType
        details.medicineUnit = dogMedicineUnit
        details.medicineRoute = dogMedicineRoute
        details.vaccineType = dogVaccineType
        details.vaccineDueDate = dogHasVaccineDueDate ? dogVaccineDueDate : nil
        details.vaccineLotNumber = dogVaccineLotNumber.nilIfBlank
        details.vaccineClinic = dogVaccineClinic.nilIfBlank
        details.symptomType = dogSymptomType
        details.symptomSeverity = dogSymptomSeverity
        details.symptomResolved = dogSymptomResolved
        details.glucoseValue = dogGlucoseValue > 0 ? dogGlucoseValue : nil
        details.glucoseUnit = dogGlucoseUnit
        details.glucoseMealRelation = dogGlucoseMealRelation
        return details
    }

    private func refreshRecentMedicineNamesIfNeeded() {
        guard type == .medicine else {
            recentMedicineNames = []
            return
        }

        let medicineType = EventType.medicine.rawValue
        let descriptor: FetchDescriptor<BabyEvent>
        if let activeProfileID {
            descriptor = FetchDescriptor<BabyEvent>(
                predicate: #Predicate<BabyEvent> { value in
                    value.typeRawValue == medicineType && value.profileID == activeProfileID
                },
                sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<BabyEvent>(
                predicate: #Predicate<BabyEvent> { value in
                    value.typeRawValue == medicineType
                },
                sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
            )
        }
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 50
        let events = (try? modelContext.fetch(limitedDescriptor)) ?? []
        var seen = Set<String>()
        recentMedicineNames = events
            .filter {
                $0.type == .medicine &&
                    $0.matchesProfile(activeProfileID) &&
                    ($0.profileTypeSnapshot ?? activeProfileType) == activeProfileType
            }
            .compactMap(\.medicineName)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(5)
            .map { $0 }
    }
}

private enum GrowthMeasurementEditorKind: String, Identifiable {
    case height
    case weight
    case headCircumference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .height: "Height"
        case .weight: "Weight"
        case .headCircumference: "Head circumference"
        }
    }

    var imperialUnitTitle: String {
        switch self {
        case .height, .headCircumference: "in"
        case .weight: "lb"
        }
    }

    var metricUnitTitle: String {
        switch self {
        case .height, .headCircumference: "cm"
        case .weight: "kg"
        }
    }

    func metricValue(fromImperial value: Double) -> Double {
        switch self {
        case .height, .headCircumference:
            return value * GrowthUnitConversion.centimetersPerInch
        case .weight:
            return value * GrowthUnitConversion.kilogramsPerPound
        }
    }

    func imperialValue(fromMetric value: Double) -> Double {
        switch self {
        case .height, .headCircumference:
            return value / GrowthUnitConversion.centimetersPerInch
        case .weight:
            return value / GrowthUnitConversion.kilogramsPerPound
        }
    }
}

private enum GrowthMeasurementInputUnit: String, CaseIterable, Identifiable {
    case imperial
    case metric

    var id: String { rawValue }
}

private enum GrowthWeightInputPart {
    case pounds
    case ounces
}

private struct GrowthMeasurementRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(AppTheme.accent)
                .underline(value != "Add", color: AppTheme.accent.opacity(0.55))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct GrowthMeasurementInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: GrowthMeasurementEditorKind
    let onSave: (Double?) -> Void

    @State private var selectedUnit: GrowthMeasurementInputUnit
    @State private var draftText: String
    @State private var weightPoundsText: String
    @State private var weightOuncesText: String
    @State private var activeWeightInputPart: GrowthWeightInputPart

    init(
        kind: GrowthMeasurementEditorKind,
        initialImperialValue: Double?,
        onSave: @escaping (Double?) -> Void
    ) {
        self.kind = kind
        self.onSave = onSave
        _selectedUnit = State(initialValue: .imperial)
        _draftText = State(initialValue: Self.inputText(for: initialImperialValue))
        let weightParts = Self.weightInputParts(for: initialImperialValue)
        _weightPoundsText = State(
            initialValue: weightParts.map { String($0.pounds) } ?? ""
        )
        _weightOuncesText = State(
            initialValue: weightParts.map { Self.ouncesInputText(for: $0.ounces) } ?? ""
        )
        _activeWeightInputPart = State(initialValue: .pounds)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(kind.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
            }

            Picker("Unit", selection: $selectedUnit) {
                Text(kind.imperialUnitTitle).tag(GrowthMeasurementInputUnit.imperial)
                Text(kind.metricUnitTitle).tag(GrowthMeasurementInputUnit.metric)
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedUnit) { oldValue, newValue in
                convertDraft(from: oldValue, to: newValue)
            }

            measurementDisplay

            VStack(spacing: 14) {
                ForEach(keyRows, id: \.self) { row in
                    HStack(spacing: 34) {
                        ForEach(row, id: \.self) { key in
                            keypadButton(key)
                        }
                    }
                }
            }

            actionBar
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var measurementDisplay: some View {
        if kind == .weight, selectedUnit == .imperial {
            HStack(spacing: 10) {
                weightInputButton(
                    part: .pounds,
                    text: weightPoundsText,
                    unit: "lb",
                    accessibilityIdentifier: "growth-weight-pounds-input"
                )
                weightInputButton(
                    part: .ounces,
                    text: weightOuncesText,
                    unit: "oz",
                    accessibilityIdentifier: "growth-weight-ounces-input"
                )
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        } else {
            Text(displayText)
                .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(draftText.isEmpty ? Color.secondary.opacity(0.55) : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 72)
        }
    }

    private func weightInputButton(
        part: GrowthWeightInputPart,
        text: String,
        unit: String,
        accessibilityIdentifier: String
    ) -> some View {
        let isActive = activeWeightInputPart == part
        return Button {
            activeWeightInputPart = part
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(text.isEmpty ? "0" : text)
                    .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.55) : Color.primary)
                Text(unit)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isActive ? AppTheme.accent.opacity(0.13) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isActive ? AppTheme.accent.opacity(0.8) : Color.primary.opacity(0.1),
                        lineWidth: isActive ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(part == .pounds ? "Pounds" : "Ounces")
        .accessibilityValue(text.isEmpty ? "0" : text)
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)

            Button {
                onSave(imperialValue)
                dismiss()
            } label: {
                Text("Save")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("growth-measurement-save")
            .background(AppTheme.accent)
        }
        .background {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Color.primary.opacity(0.045)
                        .frame(width: proxy.size.width / 2)
                    AppTheme.accent
                }
            }
        }
        .overlay(alignment: .center) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 0.5)
                .padding(.vertical, 8)
        }
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var displayText: String {
        draftText.isEmpty ? "0.00" : draftText
    }

    private var imperialValue: Double? {
        if kind == .weight, selectedUnit == .imperial {
            return weightImperialValue
        }
        guard let value = Double(draftText), value > 0 else { return nil }
        switch selectedUnit {
        case .imperial:
            return value
        case .metric:
            return kind.imperialValue(fromMetric: value)
        }
    }

    private var keyRows: [[String]] {
        [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            [".", "0", "delete.left"]
        ]
    }

    private func keypadButton(_ key: String) -> some View {
        let isDisabled = kind == .weight
            && selectedUnit == .imperial
            && activeWeightInputPart == .pounds
            && key == "."
        return Button {
            handleKey(key)
        } label: {
            Group {
                if key == "delete.left" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 28, weight: .medium))
                } else {
                    Text(key)
                        .font(.system(size: 38, weight: .regular, design: .rounded).monospacedDigit())
                }
            }
            .foregroundStyle(isDisabled ? Color.secondary.opacity(0.25) : Color.primary)
            .frame(width: 74, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel(for: key))
        .accessibilityIdentifier(keypadAccessibilityIdentifier(for: key))
    }

    private func handleKey(_ key: String) {
        if kind == .weight, selectedUnit == .imperial {
            handleWeightKey(key)
            return
        }
        draftText = text(draftText, afterPressing: key, maximumFractionDigits: 2)
    }

    private func handleWeightKey(_ key: String) {
        switch activeWeightInputPart {
        case .pounds:
            weightPoundsText = text(
                weightPoundsText,
                afterPressing: key,
                maximumFractionDigits: 0
            )
        case .ounces:
            weightOuncesText = text(
                weightOuncesText,
                afterPressing: key,
                maximumFractionDigits: 1
            )
        }
    }

    private func text(
        _ currentText: String,
        afterPressing key: String,
        maximumFractionDigits: Int
    ) -> String {
        var updatedText = currentText
        switch key {
        case "delete.left":
            if !updatedText.isEmpty {
                updatedText.removeLast()
            }
        case ".":
            guard maximumFractionDigits > 0,
                  !updatedText.contains(".") else { return updatedText }
            updatedText = updatedText.isEmpty ? "0." : updatedText + "."
        default:
            if updatedText == "0" {
                updatedText = key
            } else if fractionalDigitCount(in: updatedText) < maximumFractionDigits
                        || !updatedText.contains(".") {
                updatedText.append(key)
            }
        }
        return updatedText
    }

    private func fractionalDigitCount(in text: String) -> Int {
        guard let decimalIndex = text.firstIndex(of: ".") else { return 0 }
        return text.distance(from: text.index(after: decimalIndex), to: text.endIndex)
    }

    private func convertDraft(
        from oldUnit: GrowthMeasurementInputUnit,
        to newUnit: GrowthMeasurementInputUnit
    ) {
        guard oldUnit != newUnit else { return }

        if kind == .weight {
            convertWeightDraft(from: oldUnit, to: newUnit)
            return
        }

        guard let value = Double(draftText), value > 0 else { return }

        let converted: Double
        switch (oldUnit, newUnit) {
        case (.imperial, .metric):
            converted = kind.metricValue(fromImperial: value)
        case (.metric, .imperial):
            converted = kind.imperialValue(fromMetric: value)
        case (.imperial, .imperial), (.metric, .metric):
            return
        }
        draftText = Self.inputText(for: converted)
    }

    private func convertWeightDraft(
        from oldUnit: GrowthMeasurementInputUnit,
        to newUnit: GrowthMeasurementInputUnit
    ) {
        switch (oldUnit, newUnit) {
        case (.imperial, .metric):
            guard let weightImperialValue else {
                draftText = ""
                return
            }
            draftText = Self.inputText(for: kind.metricValue(fromImperial: weightImperialValue))
        case (.metric, .imperial):
            guard let metricValue = Double(draftText), metricValue > 0 else {
                weightPoundsText = ""
                weightOuncesText = ""
                return
            }
            setWeightInputParts(fromImperialValue: kind.imperialValue(fromMetric: metricValue))
        case (.imperial, .imperial), (.metric, .metric):
            return
        }
    }

    private var weightImperialValue: Double? {
        let pounds = Double(weightPoundsText) ?? 0
        let ounces = Double(weightOuncesText) ?? 0
        let value = pounds + ounces / 16
        return value > 0 ? value : nil
    }

    private func setWeightInputParts(fromImperialValue value: Double) {
        guard let parts = Self.weightInputParts(for: value) else {
            weightPoundsText = ""
            weightOuncesText = ""
            return
        }
        weightPoundsText = String(parts.pounds)
        weightOuncesText = Self.ouncesInputText(for: parts.ounces)
    }

    private func accessibilityLabel(for key: String) -> String {
        key == "delete.left" ? "Delete" : key
    }

    private func keypadAccessibilityIdentifier(for key: String) -> String {
        switch key {
        case "delete.left": "growth-keypad-delete"
        case ".": "growth-keypad-decimal"
        default: "growth-keypad-\(key)"
        }
    }

    private static func inputText(for value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func ouncesInputText(for value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func weightInputParts(
        for imperialValue: Double?
    ) -> (pounds: Int, ounces: Double)? {
        guard let imperialValue, imperialValue > 0 else { return nil }
        var pounds = Int(imperialValue)
        var ounces = ((imperialValue - Double(pounds)) * 16 * 10).rounded() / 10
        if ounces >= 16 {
            pounds += 1
            ounces = 0
        }
        return (pounds, ounces)
    }
}

private extension GrowthMeasurementSource {
    func displayName(for profileType: CareProfileType) -> String {
        guard profileType == .dog else { return displayName }
        switch self {
        case .pediatrician:
            return "Vet"
        case .home:
            return "Home"
        case .other:
            return "Other"
        }
    }
}

private struct TemperatureSlider: View {
    @Binding var value: Double
    let unit: TemperatureUnit

    private let controlHeight: CGFloat = 250
    private let tubeWidth: CGFloat = 28
    private let bulbSize: CGFloat = 66

    private var range: ClosedRange<Double> {
        unit == .fahrenheit ? 90...110 : 32.2...43.3
    }

    private var normalizedValue: Double {
        min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    private var accentColor: Color {
        let elevatedThreshold = unit == .fahrenheit ? 100.4 : 38
        if value >= elevatedThreshold { return .red }
        if normalizedValue > 0.38 { return .orange }
        return .indigo
    }

    private var majorTicks: [Double] {
        unit == .fahrenheit
            ? [90, 95, 100, 105, 110]
            : [32, 34, 36, 38, 40, 42]
    }

    var body: some View {
        GeometryReader { proxy in
            let tubeTop: CGFloat = 20
            let bulbTop = controlHeight - bulbSize - 10
            let tubeBottom = bulbTop + 10
            let tubeHeight = tubeBottom - tubeTop
            let centerX = proxy.size.width * 0.42
            let fillHeight = max(tubeWidth / 2, tubeHeight * normalizedValue)
            let fillTop = tubeBottom - fillHeight

            ZStack(alignment: .topLeading) {
                tickScale(
                    centerX: centerX,
                    tubeTop: tubeTop,
                    tubeHeight: tubeHeight
                )

                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(width: tubeWidth + 14, height: tubeHeight + 12)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.9), lineWidth: 2)
                            .overlay {
                                Capsule()
                                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                                    .padding(2)
                            }
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .position(x: centerX, y: tubeTop + tubeHeight / 2)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .orange, .red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: tubeWidth, height: fillHeight)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.28))
                            .frame(width: 5)
                            .padding(.vertical, 7)
                            .padding(.leading, 5)
                    }
                    .position(x: centerX, y: fillTop + fillHeight / 2)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(0.75), accentColor],
                            center: .topLeading,
                            startRadius: 3,
                            endRadius: bulbSize * 0.7
                        )
                    )
                    .frame(width: bulbSize, height: bulbSize)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.9), lineWidth: 3)
                            .overlay {
                                Circle()
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                    .padding(3)
                            }
                    }
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(.white.opacity(0.35))
                            .frame(width: 15, height: 15)
                            .offset(x: 15, y: 11)
                    }
                    .shadow(color: accentColor.opacity(0.28), radius: 12, y: 5)
                    .position(x: centerX, y: bulbTop + bulbSize / 2)

                temperatureBadge
                    .position(
                        x: min(proxy.size.width - 66, centerX + 102),
                        y: max(42, fillTop)
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(
                            for: gesture.location.y,
                            tubeTop: tubeTop,
                            tubeBottom: tubeBottom
                        )
                    }
            )
        }
        .frame(height: controlHeight)
        .accessibilityElement()
        .accessibilityLabel("Temperature")
        .accessibilityValue(
            "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit.displayName)"
        )
        .accessibilityAdjustableAction { direction in
            let adjustment = direction == .increment ? 0.1 : -0.1
            value = min(range.upperBound, max(range.lowerBound, value + adjustment))
        }
    }

    private var temperatureBadge: some View {
        HStack(spacing: 3) {
            Text(value.formatted(.number.precision(.fractionLength(1))))
                .font(.title3.bold().monospacedDigit())
            Text(unit.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(accentColor.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    private func tickScale(
        centerX: CGFloat,
        tubeTop: CGFloat,
        tubeHeight: CGFloat
    ) -> some View {
        ForEach(majorTicks, id: \.self) { tick in
            let position = min(
                1,
                max(0, (tick - range.lowerBound) / (range.upperBound - range.lowerBound))
            )
            let y = tubeTop + tubeHeight * (1 - position)

            HStack(spacing: 7) {
                Text(tick.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                Capsule()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 18, height: 2)
            }
            .position(x: centerX - 46, y: y)
        }
    }

    private func updateValue(
        for y: CGFloat,
        tubeTop: CGFloat,
        tubeBottom: CGFloat
    ) {
        let clampedY = min(tubeBottom, max(tubeTop, y))
        let percentage = 1 - Double((clampedY - tubeTop) / (tubeBottom - tubeTop))
        let rawValue = range.lowerBound + percentage * (range.upperBound - range.lowerBound)
        value = (rawValue * 10).rounded() / 10
    }
}

private struct SolidFoodSelectionRow: View {
    let foodNames: [String]
    let onChooseFoods: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Foods", systemImage: "carrot.fill")
                    .font(.headline)
                Spacer()
                Text(foodNames.isEmpty ? "Required" : "\(foodNames.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if foodNames.isEmpty {
                Text("Choose at least one food from visual suggestions, recent entries, or your custom foods.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(foodNames, id: \.self) { name in
                            Text(name)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            Button(action: onChooseFoods) {
                Label(
                    foodNames.isEmpty ? "Choose Foods" : "Change Foods",
                    systemImage: "square.grid.2x2.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("solid-food.choose")
        }
        .padding(.vertical, 4)
    }
}

private struct SolidFoodDetailSummary: View {
    let details: [SolidFoodLogDetail]
    let edit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Per-food details").font(.headline)
            ForEach(details) { detail in
                Button { edit(detail.foodID) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detail.foodName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            HStack(spacing: 5) {
                                if detail.preference != .unknown { Text(detail.preference.displayName) }
                                if !detail.allergenIDs.isEmpty {
                                    Text("• \(detail.allergenIDs.count) allergen\(detail.allergenIDs.count == 1 ? "" : "s")")
                                }
                                if detail.suspectedReaction { Text("• Reaction noted") }
                            }
                            .font(.caption)
                            .foregroundStyle(detail.suspectedReaction ? .red : .secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SolidFoodLogDetailEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var detail: SolidFoodLogDetail
    @State private var showingPreferenceOptions = false
    @State private var showingSeverityOptions = false
    @State private var showingFollowUpOptions = false

    private let preferences: [SolidReaction] = [.loved, .liked, .neutral, .disliked, .unknown]

    var body: some View {
        Form {
            Section("Preference") {
                selectionButton(
                    title: "Response",
                    value: detail.preference.displayName,
                    systemImage: "face.smiling"
                ) {
                    showingPreferenceOptions = true
                }
                .accessibilityIdentifier("solid-reaction.preference")
            }

            Section("Serving") {
                TextField(
                    "Amount offered or eaten",
                    text: Binding(
                        get: { detail.servingAmount ?? "" },
                        set: {
                            let cleaned = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            detail.servingAmount = cleaned.isEmpty ? nil : cleaned
                        }
                    )
                )
                Text("Examples: 2 teaspoons thinned peanut butter, half an egg, or a few soft pieces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Food notes") {
                TextField(
                    "Texture, preparation, or what happened",
                    text: Binding(
                        get: { detail.notes ?? "" },
                        set: {
                            let cleaned = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            detail.notes = cleaned.isEmpty ? nil : cleaned
                        }
                    ),
                    axis: .vertical
                )
            }

            Section("Allergens actually served") {
                ForEach(SolidsAllergen.allCases) { allergen in
                    VStack(alignment: .leading, spacing: 6) {
                        Button { toggleAllergen(allergen.rawValue) } label: {
                            HStack {
                                Text(allergen.displayName).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: detail.allergenIDs.contains(allergen.rawValue)
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(detail.allergenIDs.contains(allergen.rawValue) ? .orange : .secondary)
                            }
                        }
                        .accessibilityIdentifier("solid-allergen.\(allergen.rawValue)")
                        if detail.allergenIDs.contains(allergen.rawValue) {
                            Toggle(
                                "Count as an introduction portion",
                                isOn: Binding(
                                    get: { detail.confirmedAllergenPortionIDs?.contains(allergen.rawValue) == true },
                                    set: { setConfirmedPortion($0, allergenID: allergen.rawValue) }
                                )
                            )
                            .font(.subheadline)
                            Text(SolidsReferenceCatalog.allergenGuidance(allergen).exampleServing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("For packaged or prepared foods, use the ingredient label rather than the food name alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Possible reaction") {
                Toggle("Reaction noticed", isOn: $detail.suspectedReaction)
                    .accessibilityIdentifier("solid-reaction.observed")
                if detail.suspectedReaction {
                    ForEach(SolidReactionSymptom.allCases) { symptom in
                        Button { toggleSymptom(symptom) } label: {
                            HStack {
                                Text(symptom.displayName).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: detail.symptoms.contains(symptom)
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(detail.symptoms.contains(symptom) ? .red : .secondary)
                            }
                        }
                    }
                    selectionButton(
                        title: "Severity",
                        value: detail.severity.displayName,
                        systemImage: "exclamationmark.triangle"
                    ) {
                        showingSeverityOptions = true
                    }
                    LabeledContent("Started after") {
                        TextField("Minutes", value: $detail.onsetMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Duration") {
                        TextField("Minutes", value: $detail.durationMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("What you did", text: $detail.responseNotes, axis: .vertical)
                    selectionButton(
                        title: "Follow-up",
                        value: detail.followUp.displayName,
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        showingFollowUpOptions = true
                    }
                }
            }

            if detail.suspectedReaction {
                Section("Urgent symptoms") {
                    Text("Trouble breathing, significant swelling, collapse, or rapidly worsening symptoms need emergency help. This log does not diagnose an allergy.")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(detail.foodName)
        .navigationBarTitleDisplayMode(.inline)
        .appActionSheet(
            isPresented: $showingPreferenceOptions,
            title: "Food response",
            message: "Choose how the child responded to this food.",
            systemImage: "face.smiling",
            tint: .orange,
            options: preferences.map { value in
                AppActionSheetOption(
                    title: value.displayName,
                    systemImage: preferenceSystemImage(value),
                    tint: .orange,
                    isSelected: detail.preference == value
                ) {
                    detail.preference = value
                }
            }
        )
        .appActionSheet(
            isPresented: $showingSeverityOptions,
            title: "Reaction severity",
            message: "Record the observed severity. This does not diagnose an allergy.",
            systemImage: "exclamationmark.triangle",
            tint: .red,
            options: SolidReactionSeverity.allCases.map { value in
                AppActionSheetOption(
                    title: value.displayName,
                    systemImage: severitySystemImage(value),
                    tint: value == .severe ? .red : .orange,
                    isSelected: detail.severity == value
                ) {
                    detail.severity = value
                }
            }
        )
        .appActionSheet(
            isPresented: $showingFollowUpOptions,
            title: "Reaction follow-up",
            message: "Choose the current follow-up status for this observation.",
            systemImage: "arrow.triangle.2.circlepath",
            tint: .orange,
            options: SolidReactionFollowUp.allCases.map { value in
                AppActionSheetOption(
                    title: value.displayName,
                    systemImage: followUpSystemImage(value),
                    tint: value == .avoidPendingAdvice ? .red : .orange,
                    isSelected: detail.followUp == value
                ) {
                    detail.followUp = value
                }
            }
        )
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
        .onChange(of: detail.suspectedReaction) { _, isOn in
            if !isOn {
                detail.symptoms = []
                detail.severity = .unknown
                detail.onsetMinutes = nil
                detail.durationMinutes = nil
                detail.responseNotes = ""
                detail.followUp = .none
            }
        }
    }

    private func toggleAllergen(_ id: String) {
        if let index = detail.allergenIDs.firstIndex(of: id) {
            detail.allergenIDs.remove(at: index)
            detail.confirmedAllergenPortionIDs?.removeAll { $0 == id }
        } else {
            if detail.confirmedAllergenPortionIDs == nil {
                detail.confirmedAllergenPortionIDs = []
            }
            detail.allergenIDs.append(id)
            detail.allergenIDs.sort()
        }
    }

    private func selectionButton(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(value)
    }

    private func preferenceSystemImage(_ value: SolidReaction) -> String {
        switch value {
        case .loved: "heart.fill"
        case .liked: "hand.thumbsup.fill"
        case .neutral: "minus.circle"
        case .disliked: "hand.thumbsdown.fill"
        case .sensitivity: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func severitySystemImage(_ value: SolidReactionSeverity) -> String {
        switch value {
        case .unknown: "questionmark.circle"
        case .mild: "exclamationmark.circle"
        case .moderate: "exclamationmark.triangle"
        case .severe: "exclamationmark.octagon.fill"
        }
    }

    private func followUpSystemImage(_ value: SolidReactionFollowUp) -> String {
        switch value {
        case .none: "minus.circle"
        case .monitoring: "eye.fill"
        case .resolved: "checkmark.circle.fill"
        case .discussWithClinician: "cross.case.fill"
        case .avoidPendingAdvice: "hand.raised.fill"
        }
    }

    private func setConfirmedPortion(_ confirmed: Bool, allergenID: String) {
        var ids = detail.confirmedAllergenPortionIDs ?? []
        ids.removeAll { $0 == allergenID }
        if confirmed { ids.append(allergenID) }
        detail.confirmedAllergenPortionIDs = ids.sorted()
    }

    private func toggleSymptom(_ symptom: SolidReactionSymptom) {
        if let index = detail.symptoms.firstIndex(of: symptom) {
            detail.symptoms.remove(at: index)
        } else {
            detail.symptoms.append(symptom)
        }
    }
}

private struct SolidFoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SolidFoodCatalogItem.name) private var customFoods: [SolidFoodCatalogItem]
    @Query(sort: \PhotoAttachment.createdAt, order: .reverse) private var photoAttachments: [PhotoAttachment]

    let recentFoodNames: [String]
    let onDone: ([String]) -> Void

    @State private var selection: SolidFoodPickerSelection
    @State private var effectiveSearchText = ""
    @State private var editorRoute: SolidFoodEditorRoute?
    @State private var foodPendingManagement: SolidFoodCatalogItem?
    @State private var foodPendingDeletion: SolidFoodCatalogItem?
    @State private var catalogWriter: SolidsCustomFoodWriter?
    @State private var deletionError: String?

    init(
        initialSelection: [String],
        recentFoodNames: [String],
        onDone: @escaping ([String]) -> Void
    ) {
        self.recentFoodNames = recentFoodNames
        self.onDone = onDone
        let solidFoodPhotoKind = PhotoAttachmentOwnerKind.solidFood.rawValue
        _photoAttachments = Query(FetchDescriptor<PhotoAttachment>(
            predicate: #Predicate { $0.ownerKindRawValue == solidFoodPhotoKind },
            sortBy: [SortDescriptor(\PhotoAttachment.createdAt, order: .reverse)]
        ))
        _selection = State(initialValue: SolidFoodPickerSelection(initialSelection))
    }

    var body: some View {
        let visibleQuickAddName = quickAddName
        let visibleRecentFoods = filteredRecentFoods
        let visibleCustomFoods = filteredCustomFoods
        let visibleReferenceFoods = filteredReferenceFoods
        let customFoodByNormalizedName = customFoods.reduce(
            into: [String: SolidFoodCatalogItem]()
        ) { result, food in
            result[food.normalizedName] = food
        }
        let photoDataByID = photoAttachments.reduce(into: [UUID: Data]()) { result, attachment in
            if let data = attachment.previewData { result[attachment.id] = data }
        }
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if let visibleQuickAddName {
                        Button {
                            selection.select(visibleQuickAddName)
                            effectiveSearchText = ""
                        } label: {
                            Label("Use “\(visibleQuickAddName)” for this feeding", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    if !visibleRecentFoods.isEmpty {
                        foodSection(title: "Recent foods") {
                            ForEach(visibleRecentFoods, id: \.self) { name in
                                let normalizedName = SolidFoodSelection.normalizedName(name)
                                if let customFood = customFoodByNormalizedName[normalizedName] {
                                    foodTile(
                                        for: name,
                                        emoji: visualEmoji(for: name),
                                        normalizedName: normalizedName,
                                        photoAttachmentID: customFood.photoAttachmentID,
                                        photoData: customFood.photoAttachmentID.flatMap { photoDataByID[$0] }
                                    )
                                } else {
                                    foodTile(
                                        for: name,
                                        emoji: visualEmoji(for: name),
                                        normalizedName: normalizedName
                                    )
                                }
                            }
                        }
                    }

                    foodSection(title: "My foods") {
                        addCustomFoodTile
                        ForEach(visibleCustomFoods) { food in
                            foodTile(
                                for: food.name,
                                emoji: visualEmoji(for: food.name),
                                normalizedName: food.normalizedName,
                                photoAttachmentID: food.photoAttachmentID,
                                photoData: food.photoAttachmentID.flatMap { photoDataByID[$0] },
                                managementAction: { foodPendingManagement = food }
                            )
                        }
                    }

                    if !visibleReferenceFoods.isEmpty {
                        foodDatabaseSection(visibleReferenceFoods)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 104)
            }
            .navigationTitle("Choose Foods")
            .navigationBarTitleDisplayMode(.inline)
            .debouncedSearch(text: $effectiveSearchText, prompt: "Search or enter a food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                SolidFoodPickerSelectionFooter(selection: selection) {
                    onDone(selection.names)
                    dismiss()
                }
            }
            .sheet(item: $editorRoute) { route in
                NavigationStack {
                    CustomSolidFoodEditorView(
                        item: route.item,
                        existingItems: customFoods,
                        existingPhoto: route.item.flatMap(photoAttachment(for:))
                    ) { oldName, newName in
                        replaceSelection(oldName: oldName, newName: newName)
                    }
                }
            }
            .appActionSheet(
                isPresented: Binding(
                    get: { foodPendingManagement != nil },
                    set: { if !$0 { foodPendingManagement = nil } }
                ),
                title: foodPendingManagement.map { "Manage \($0.name)" } ?? "Manage custom food",
                message: "Choose what you want to do with this custom food.",
                systemImage: "ellipsis",
                options: foodPendingManagement.map { food in
                    [
                        AppActionSheetOption(
                            title: "Edit food",
                            subtitle: "Update its name, serving guidance, allergens, or photo.",
                            systemImage: "pencil"
                        ) {
                            foodPendingManagement = nil
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                editorRoute = SolidFoodEditorRoute(item: food)
                            }
                        },
                        AppActionSheetOption(
                            title: "Delete food",
                            subtitle: "Past feeding entries will keep the food name.",
                            systemImage: "trash.fill",
                            tint: .red,
                            role: .destructive
                        ) {
                            foodPendingManagement = nil
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                foodPendingDeletion = food
                            }
                        }
                    ]
                } ?? [],
                cancelAction: { foodPendingManagement = nil }
            )
            .appActionSheet(
                isPresented: Binding(
                    get: { foodPendingDeletion != nil },
                    set: { if !$0 { foodPendingDeletion = nil } }
                ),
                title: "Delete custom food?",
                message: "Past feeding entries keep the food name. The custom photo will also be removed.",
                systemImage: "trash",
                tint: .red,
                options: foodPendingDeletion.map { food in
                    [AppActionSheetOption(
                        title: "Delete \(food.name)",
                        subtitle: "Remove this food and its custom photo.",
                        systemImage: "trash.fill",
                        tint: .red,
                        role: .destructive
                    ) {
                        let foodPendingDeletion = food
                        let itemID = foodPendingDeletion.id
                        let itemName = foodPendingDeletion.name
                        self.foodPendingDeletion = nil
                        Task {
                            if let error = await resolvedCatalogWriter().delete(itemID: itemID) {
                                deletionError = error
                                PersistenceService.recordLocalSaveFailure(error)
                            } else {
                                removeSelection(itemName)
                            }
                        }
                    }]
                } ?? [],
                cancelAction: { foodPendingDeletion = nil }
            )
            .alert("Couldn’t delete food", isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )) {
                Button("OK") { deletionError = nil }
            } message: {
                Text(deletionError ?? "")
            }
            .task { _ = await resolvedCatalogWriter() }
        }
    }

    private var quickAddName: String? {
        let name = SolidFoodSelection.cleanedName(effectiveSearchText)
        guard !name.isEmpty else { return nil }
        let normalizedName = SolidFoodSelection.normalizedName(name)
        let isKnownUserFood = recentFoodNames.contains {
            SolidFoodSelection.normalizedName($0) == normalizedName
        } || customFoods.contains { $0.normalizedName == normalizedName }
        return isKnownUserFood || SolidsReferenceCatalog.food(named: name) != nil ? nil : name
    }

    private var filteredRecentFoods: [String] {
        let query = SolidFoodSelection.normalizedName(effectiveSearchText)
        return recentFoodNames.filter {
            query.isEmpty || SolidFoodSelection.normalizedName($0).contains(query)
        }
    }

    private var filteredCustomFoods: [SolidFoodCatalogItem] {
        let query = SolidFoodSelection.normalizedName(effectiveSearchText)
        return customFoods.filter {
            query.isEmpty || $0.normalizedName.contains(query)
        }
    }

    private var filteredReferenceFoods: [SolidsReferenceFood] {
        SolidsReferenceCatalog.search(effectiveSearchText)
    }

    @ViewBuilder
    private func foodSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 12)],
                spacing: 12,
                content: content
            )
        }
    }

    private func foodDatabaseSection(_ foods: [SolidsReferenceFood]) -> some View {
        let foodsByCategory = Dictionary(grouping: foods, by: \.category)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Food database")
                    .font(.headline)
                Text("\(SolidsReferenceCatalog.foods.count) bundled foods with stable names for tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(SolidsFoodCategory.allCases) { category in
                let foods = foodsByCategory[category] ?? []
                if !foods.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 96), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(foods) { food in
                                foodTile(
                                    for: food.name,
                                    emoji: food.visualEmoji
                                )
                            }
                        }
                    }
                }
            }

            Text("Open Care > Solids > Food Database for age-specific preparation and safety guidance.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func foodTile(
        for name: String,
        emoji: String? = nil,
        normalizedName: String? = nil,
        photoAttachmentID: UUID? = nil,
        photoData: Data? = nil,
        managementAction: (() -> Void)? = nil
    ) -> some View {
        let normalizedName = normalizedName ?? SolidFoodSelection.normalizedName(name)
        return SolidFoodPickerTile(
            name: name,
            emoji: emoji,
            normalizedName: normalizedName,
            photoAttachmentID: photoAttachmentID,
            photoData: photoData,
            selection: selection,
            managementAction: managementAction
        )
    }

    private var addCustomFoodTile: some View {
        Button {
            editorRoute = SolidFoodEditorRoute(item: nil)
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
                    .frame(height: 76)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                Text("Custom food")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(minHeight: 32, alignment: .top)
            }
            .padding(7)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Creates a reusable food with an optional photo")
    }

    private func photoAttachment(for food: SolidFoodCatalogItem) -> PhotoAttachment? {
        guard let photoAttachmentID = food.photoAttachmentID else { return nil }
        return photoAttachments.first { $0.id == photoAttachmentID }
    }

    private func visualEmoji(for name: String) -> String {
        if let referenceFood = SolidsReferenceCatalog.food(named: name) {
            return referenceFood.visualEmoji
        }
        return SolidsFoodVisual.emoji(for: name)
    }

    private func removeSelection(_ name: String) {
        selection.remove(name)
    }

    private func replaceSelection(oldName: String?, newName: String) {
        selection.replace(oldName: oldName, newName: newName)
    }

    @MainActor
    private func resolvedCatalogWriter() async -> SolidsCustomFoodWriter {
        if let catalogWriter { return catalogWriter }
        let writer = await SolidsWriterPool.shared.customFoodWriter(for: modelContext.container)
        catalogWriter = writer
        return writer
    }

}

@MainActor
private final class SolidFoodPickerSelection: ObservableObject {
    private(set) var names: [String]
    private var normalizedNames: Set<String>
    @Published private(set) var selectedCount: Int
    let changes = PassthroughSubject<String, Never>()

    init(_ names: [String]) {
        self.names = names
        normalizedNames = Set(names.map(SolidFoodSelection.normalizedName))
        selectedCount = normalizedNames.count
    }

    func contains(_ normalizedName: String) -> Bool {
        normalizedNames.contains(normalizedName)
    }

    func toggle(_ name: String, normalizedName: String) {
        if normalizedNames.contains(normalizedName) {
            remove(name, normalizedName: normalizedName)
        } else {
            select(name, normalizedName: normalizedName)
        }
    }

    func select(_ name: String) {
        select(name, normalizedName: SolidFoodSelection.normalizedName(name))
    }

    func remove(_ name: String) {
        remove(name, normalizedName: SolidFoodSelection.normalizedName(name))
    }

    func replace(oldName: String?, newName: String) {
        guard let oldName else {
            select(newName)
            return
        }
        let oldNormalizedName = SolidFoodSelection.normalizedName(oldName)
        guard normalizedNames.contains(oldNormalizedName) else {
            select(newName)
            return
        }
        let newNormalizedName = SolidFoodSelection.normalizedName(newName)
        if let index = names.firstIndex(where: {
            SolidFoodSelection.normalizedName($0) == oldNormalizedName
        }) {
            names[index] = SolidFoodSelection.cleanedName(newName)
        }
        normalizedNames.remove(oldNormalizedName)
        normalizedNames.insert(newNormalizedName)
        selectedCount = normalizedNames.count
        changes.send(oldNormalizedName)
        changes.send(newNormalizedName)
    }

    private func select(_ name: String, normalizedName: String) {
        guard normalizedNames.insert(normalizedName).inserted else { return }
        names.append(SolidFoodSelection.cleanedName(name))
        selectedCount = normalizedNames.count
        changes.send(normalizedName)
    }

    private func remove(_ name: String, normalizedName: String) {
        guard normalizedNames.remove(normalizedName) != nil else { return }
        names.removeAll { SolidFoodSelection.normalizedName($0) == normalizedName }
        selectedCount = normalizedNames.count
        changes.send(normalizedName)
    }
}

private struct SolidFoodPickerSelectionFooter: View {
    @ObservedObject var selection: SolidFoodPickerSelection
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("\(selection.selectedCount) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Button(action: onDone) {
                Text("Use Foods")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("solid-food.use-selection")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct SolidFoodPickerTile: View {
    let name: String
    let emoji: String?
    let normalizedName: String
    let photoAttachmentID: UUID?
    let photoData: Data?
    let selection: SolidFoodPickerSelection
    let managementAction: (() -> Void)?

    @State private var isSelected: Bool

    init(
        name: String,
        emoji: String?,
        normalizedName: String,
        photoAttachmentID: UUID?,
        photoData: Data?,
        selection: SolidFoodPickerSelection,
        managementAction: (() -> Void)?
    ) {
        self.name = name
        self.emoji = emoji
        self.normalizedName = normalizedName
        self.photoAttachmentID = photoAttachmentID
        self.photoData = photoData
        self.selection = selection
        self.managementAction = managementAction
        _isSelected = State(initialValue: selection.contains(normalizedName))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button {
                selection.toggle(name, normalizedName: normalizedName)
                isSelected = selection.contains(normalizedName)
            } label: {
                VStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(height: 76)
                            .overlay { visual }
                            .clipped()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .background(Circle().fill(.background))
                            .padding(5)
                    }
                    Text(name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
                }
                .padding(7)
                .background(
                    isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityIdentifier("solid-food.option.\(normalizedName)")

            if let managementAction {
                Button(action: managementAction) {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .background)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage \(name)")
                .accessibilityIdentifier("solid-food.manage.\(normalizedName)")
            }
        }
        .onReceive(selection.changes.filter { $0 == normalizedName }) { _ in
            isSelected = selection.contains(normalizedName)
        }
    }

    @ViewBuilder
    private var visual: some View {
        if let photoAttachmentID,
           let photoData,
           let image = ThumbnailImageCache.image(
               attachmentID: photoAttachmentID,
               data: photoData
           ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let emoji {
            Text(emoji).font(.system(size: 43))
        } else {
            Image(systemName: "fork.knife")
                .font(.title)
                .foregroundStyle(Color.accentColor)
        }
    }
}

private struct SolidFoodEditorRoute: Identifiable {
    let id: UUID
    let item: SolidFoodCatalogItem?

    init(item: SolidFoodCatalogItem?) {
        id = item?.id ?? UUID()
        self.item = item
    }
}

struct CustomSolidFoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: SolidFoodCatalogItem?
    let existingItems: [SolidFoodCatalogItem]
    let existingPhoto: PhotoAttachment?
    let onSave: (String?, String) -> Void

    @State private var name: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoDraft: PhotoAttachmentDraft?
    @State private var removeExistingPhoto = false
    @State private var isImportingPhoto = false
    @State private var selectedAllergenIDs: Set<String>
    @State private var minimumAgeMonths: Int
    @State private var preparationNotes: String
    @State private var safetyNotes: String
    @State private var isMinimumAgeDrawerPresented = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var catalogWriter: SolidsCustomFoodWriter?

    init(
        item: SolidFoodCatalogItem?,
        existingItems: [SolidFoodCatalogItem],
        existingPhoto: PhotoAttachment?,
        onSave: @escaping (String?, String) -> Void
    ) {
        self.item = item
        self.existingItems = existingItems
        self.existingPhoto = existingPhoto
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _selectedAllergenIDs = State(initialValue: Set(item?.allergenIDs ?? []))
        _minimumAgeMonths = State(initialValue: item?.minimumAgeMonths ?? 6)
        _preparationNotes = State(initialValue: item?.preparationNotes ?? "")
        _safetyNotes = State(initialValue: item?.safetyNotes ?? "")
    }

    var body: some View {
        Form {
            Section("Food") {
                TextField("Food name", text: $name)
                    .textInputAutocapitalization(.words)
                if hasDuplicateName {
                    Label(
                        "A custom food with this name already exists.",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

            Section("Serving guidance") {
                Button { isMinimumAgeDrawerPresented = true } label: {
                    HStack(spacing: 12) {
                        Label("Minimum age", systemImage: "calendar.badge.clock")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(minimumAgeTitle)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                TextField("How to prepare", text: $preparationNotes, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Safety notes", text: $safetyNotes, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section("Major allergens") {
                ForEach(SolidsAllergen.allCases) { allergen in
                    Button {
                        if !selectedAllergenIDs.insert(allergen.rawValue).inserted {
                            selectedAllergenIDs.remove(allergen.rawValue)
                        }
                    } label: {
                        HStack {
                            Text(allergen.displayName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selectedAllergenIDs.contains(allergen.rawValue)
                                ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedAllergenIDs.contains(allergen.rawValue) ? .orange : .secondary)
                        }
                    }
                }
            }

            Section {
                if let previewAttachmentID,
                   let previewData,
                   let image = ThumbnailImageCache.image(
                    attachmentID: previewAttachmentID,
                    data: previewData
                   ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button(role: .destructive) {
                        photoDraft = nil
                        removeExistingPhoto = true
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                }

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        previewData == nil ? "Choose Photo" : "Replace Photo",
                        systemImage: "photo.badge.plus"
                    )
                }
                .disabled(isImportingPhoto)
            } header: {
                Text("Photo")
            } footer: {
                Text("Optional. The photo appears on this food's tile and syncs with your Little Windows data.")
            }
        }
        .navigationTitle(item == nil ? "New Custom Food" : "Edit Custom Food")
        .navigationBarTitleDisplayMode(.inline)
        .appActionSheet(
            isPresented: $isMinimumAgeDrawerPresented,
            title: "Minimum serving age",
            message: "Choose the earliest age this custom food guidance supports.",
            systemImage: "calendar.badge.clock",
            options: [6, 9, 12, 18].map { age in
                AppActionSheetOption(
                    title: minimumAgeTitle(for: age),
                    systemImage: age == 6 ? "figure.child" : "calendar",
                    isSelected: minimumAgeMonths == age
                ) {
                    minimumAgeMonths = age
                }
            }
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            importPhoto(from: newItem)
        }
        .alert("Couldn’t save food", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .task { _ = await resolvedCatalogWriter() }
    }

    private var cleanedName: String {
        SolidFoodSelection.cleanedName(name)
    }

    private var minimumAgeTitle: String {
        minimumAgeTitle(for: minimumAgeMonths)
    }

    private func minimumAgeTitle(for age: Int) -> String {
        age == 6 ? "Around 6 months" : "\(age)+ months"
    }

    private var hasDuplicateName: Bool {
        let normalizedName = SolidFoodSelection.normalizedName(cleanedName)
        guard !normalizedName.isEmpty else { return false }
        return existingItems.contains {
            $0.id != item?.id && $0.normalizedName == normalizedName
        }
    }

    private var canSave: Bool {
        !cleanedName.isEmpty && !hasDuplicateName && !isImportingPhoto && !isSaving
    }

    private var previewData: Data? {
        if let photoDraft {
            return photoDraft.thumbnailData ?? photoDraft.imageData
        }
        guard !removeExistingPhoto else { return nil }
        return existingPhoto?.previewData
    }

    private var previewAttachmentID: UUID? {
        if let photoDraft { return photoDraft.id }
        guard !removeExistingPhoto else { return nil }
        return existingPhoto?.id
    }

    private func importPhoto(from item: PhotosPickerItem) {
        Task {
            isImportingPhoto = true
            defer {
                isImportingPhoto = false
                selectedPhotoItem = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let draft = await Task.detached(priority: .userInitiated, operation: {
                      PhotoAttachmentImageProcessor.draft(from: data)
                  }).value else { return }
            photoDraft = draft
            removeExistingPhoto = false
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let oldName = item?.name
        let writer = await resolvedCatalogWriter()
        let result = await writer.save(SolidsCustomFoodWrite(
            itemID: item?.id,
            name: cleanedName,
            photoDraft: photoDraft,
            removeExistingPhoto: removeExistingPhoto,
            allergenIDs: selectedAllergenIDs.sorted(),
            minimumAgeMonths: minimumAgeMonths,
            preparationNotes: preparationNotes,
            safetyNotes: safetyNotes
        ))
        if let error = result.error {
            saveError = error
            PersistenceService.recordLocalSaveFailure(error)
            return
        }
        onSave(oldName, result.name ?? cleanedName)
        dismiss()
    }

    @MainActor
    private func resolvedCatalogWriter() async -> SolidsCustomFoodWriter {
        if let catalogWriter { return catalogWriter }
        let writer = await SolidsWriterPool.shared.customFoodWriter(for: modelContext.container)
        catalogWriter = writer
        return writer
    }
}
