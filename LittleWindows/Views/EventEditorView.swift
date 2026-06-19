import SwiftData
import SwiftUI

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var recentEvents: [BabyEvent]
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @StateObject private var profileService = ProfileService.shared

    let existingEvent: BabyEvent?
    let onSave: (BabyEvent) -> Void

    @State private var type: EventType
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasEndDate: Bool
    @State private var caregiverName: String
    @State private var notes: String
    @State private var sleepKind: SleepKind
    @State private var feedKind: FeedKind
    @State private var amountOz: Double
    @State private var foodDescription: String
    @State private var nursingSide: NursingSide
    @State private var nursingMinutes: Double
    @State private var diaperKind: DiaperKind
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
    @State private var validationMessage: String?

    init(type: EventType, event: BabyEvent? = nil, onSave: @escaping (BabyEvent) -> Void) {
        var descriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { value in
                value.typeRawValue == "medicine"
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        _recentEvents = Query(descriptor)

        existingEvent = event
        self.onSave = onSave
        let selectedType = event?.type ?? type
        _type = State(initialValue: selectedType)
        _title = State(initialValue: event?.title ?? "")
        _startDate = State(initialValue: event?.startDate ?? Date())
        _endDate = State(initialValue: event?.endDate ?? Date())
        _hasEndDate = State(initialValue: selectedType.supportsTimer && (event == nil || event?.endDate != nil))
        _caregiverName = State(initialValue: event?.caregiverName ?? "")
        _notes = State(initialValue: event?.notes ?? "")
        _sleepKind = State(initialValue: event?.sleepKind ?? .nap)
        _feedKind = State(initialValue: event?.feedKind ?? .bottle)
        _amountOz = State(initialValue: event?.amountOz ?? 0)
        _foodDescription = State(initialValue: event?.foodDescription ?? "")
        _nursingSide = State(initialValue: event?.nursingSide ?? .left)
        _nursingMinutes = State(initialValue: (event?.totalNursingDurationSeconds ?? 0) / 60)
        _diaperKind = State(initialValue: event?.diaperKind ?? .wet)
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
    }

    private var selectedProfile: CareProfile? {
        profileService.selectedProfile(in: profiles)
    }

    private var activeProfileType: CareProfileType {
        existingEvent?.profileTypeSnapshot ?? selectedProfile?.profileType ?? .child
    }

    var body: some View {
        Form {
            Section("Event") {
                Picker("Type", selection: $type) {
                    ForEach(EventType.cases(for: activeProfileType)) { type in
                        Label(type.displayName, systemImage: type.systemImage).tag(type)
                    }
                }
                if type == .custom || (type == .activity && activityType == .custom) {
                    TextField("Title", text: $title)
                }
                DatePicker("Start", selection: $startDate)
                if type.supportsTimer {
                    Toggle("Has ended", isOn: $hasEndDate)
                }
                if type.supportsTimer, hasEndDate {
                    DatePicker("End", selection: $endDate, in: startDate...)
                }
                TextField("Caregiver", text: $caregiverName)
            }

            eventSpecificFields

            Section("Notes") {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(existingEvent == nil ? "Add Event" : "Edit Event")
        .navigationBarTitleDisplayMode(.inline)
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
            }
        case .feed:
            Section("Feed") {
                Picker("Kind", selection: $feedKind) {
                    ForEach(FeedKind.allCases) { Text($0.displayName).tag($0) }
                }
                if feedKind == .bottle {
                    TextField("Amount (oz)", value: $amountOz, format: .number)
                        .keyboardType(.decimalPad)
                }
                TextField("Food or details", text: $foodDescription)
            }
        case .nursing:
            Section("Nursing") {
                Picker("Side", selection: $nursingSide) {
                    ForEach(NursingSide.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Duration (minutes)", value: $nursingMinutes, format: .number)
                    .keyboardType(.decimalPad)
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
                }
            }
        case .medicine:
            Section("Medicine") {
                TextField("Medicine name", text: $medicineName)
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
                LabeledContent("Weight") {
                    HStack {
                        TextField("lb", value: $weightPounds, format: .number)
                            .keyboardType(.numberPad)
                        Text("lb")
                        TextField("oz", value: $weightOunces, format: .number)
                            .keyboardType(.decimalPad)
                        Text("oz")
                    }
                    .multilineTextAlignment(.trailing)
                }
                LabeledContent("Height") {
                    HStack {
                        TextField("ft", value: $heightFeet, format: .number)
                            .keyboardType(.numberPad)
                        Text("ft")
                        TextField("in", value: $heightInches, format: .number)
                            .keyboardType(.decimalPad)
                        Text("in")
                    }
                    .multilineTextAlignment(.trailing)
                }
                LabeledContent("Head circumference") {
                    HStack {
                        TextField(
                            "Optional",
                            value: $headCircumferenceInches,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        Text("in")
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Measured at", selection: $growthSource) {
                    ForEach(GrowthMeasurementSource.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                Picker("Reference sex", selection: $growthSex) {
                    ForEach(BabySex.allCases) {
                        Text($0.displayName).tag($0)
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
                    ForEach(TemperatureMethod.allCases) { Text($0.displayName).tag($0) }
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
                TextField("Treat type/name", text: $dogTreatName)
                TextField("Quantity optional", value: $dogTreatQuantity, format: .number)
                    .keyboardType(.decimalPad)
            }
        case .potty:
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
        event.caregiverName = caregiverName.nilIfBlank
        event.notes = notes.nilIfBlank
        event.sleepKind = type == .sleep ? sleepKind : nil
        event.feedKind = type == .feed ? feedKind : nil
        event.amountOz = type == .feed && feedKind == .bottle && amountOz > 0 ? amountOz : nil
        event.foodDescription = type == .feed ? foodDescription.nilIfBlank : nil
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
        event.peeAmount = type == .diaper && diaperKind.hasPee ? peeAmount : nil
        event.pooAmount = type == .diaper && diaperKind.hasPoo ? pooAmount : nil
        event.pooColor = type == .diaper && diaperKind.hasPoo ? pooColor : nil
        event.pooTexture = type == .diaper && diaperKind.hasPoo ? pooTexture : nil
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
        event.headCircumferenceInches = type == .growth
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
        event.headCircumferenceCentimeters = type == .growth
            ? headCircumferenceInches.flatMap {
                $0 > 0 ? GrowthUnitConversion.inchesToCentimeters($0) : nil
            }
            : nil
        event.growthSexRawValue = type == .growth ? growthSex.rawValue : nil
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

    private var recentMedicineNames: [String] {
        var seen = Set<String>()
        return recentEvents
            .filter { $0.type == .medicine }
            .compactMap(\.medicineName)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(5)
            .map { $0 }
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
