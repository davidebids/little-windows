import AppIntents
import SwiftData
import XCTest
@testable import LittleWindows

@MainActor
final class VoiceLoggingTests: XCTestCase {
    private let now = Date()

    private func store() throws -> ModelContainer {
        let schema = PersistenceService.schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(
            "VoiceLoggingTests-\(UUID())", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )])
    }

    private func profile(_ type: CareProfileType, in container: ModelContainer) throws -> CareProfile {
        let profile = CareProfile(name: type == .child ? "Test Child" : "Test Adult", birthDate: now.addingTimeInterval(-180 * 86_400))
        profile.profileType = type
        container.mainContext.insert(profile)
        try container.mainContext.save()
        return profile
    }

    private func events(in container: ModelContainer) throws -> [CareEvent] {
        try ModelContext(container).fetch(FetchDescriptor<CareEvent>())
    }

    func testBottleUsesExplicitProfileTimeAndMilliliters() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try profile(.adult, in: container)
        let when = now.addingTimeInterval(-600)
        let request = VoiceCareLog(profileID: child.id, kind: .bottle, date: when, value: 120, unit: .milliliters)
        let reply = try await VoiceLoggingService.log(request, in: container, now: now)
        let event = try XCTUnwrap(events(in: container).first)
        XCTAssertEqual(event.profileID, child.id)
        XCTAssertEqual(event.feedKind, .bottle)
        XCTAssertEqual(event.startDate, when)
        XCTAssertEqual(try XCTUnwrap(event.amountOz), 120 / 29.5735295625, accuracy: 0.000001)
        XCTAssertTrue(reply.contains("Test Child"))
        XCTAssertTrue(reply.contains("fluid ounces"))
    }

    func testRetryOfSameRequestDoesNotCreateSecondEvent() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let request = VoiceCareLog(profileID: child.id, kind: .diaper, date: now, diaperKind: .both)
        _ = try await VoiceLoggingService.log(request, in: container, now: now)
        let reply = try await VoiceLoggingService.log(request, in: container, now: now)
        XCTAssertEqual(try events(in: container).count, 1)
        XCTAssertTrue(reply.contains("Already saved"))
    }

    func testCareLogCatalogCoversChildCategoriesAndAllSupportedActivities() {
        let childTypes = Set(VoiceCareKind.allCases.filter { $0.supports(.child) }.map(\.eventType))
        // Managed medication doses use their dedicated confirmed voice intent.
        XCTAssertEqual(childTypes.union([.medicine]), Set(EventType.cases(for: .child)))
        for type in [CareProfileType.child, .adult] {
            XCTAssertEqual(
                Set(VoiceCareKind.allCases.filter { $0.supports(type) }.compactMap(\.activityType)),
                Set(ActivityType.cases(for: type))
            )
        }
        XCTAssertEqual(Set(VoiceCareKind.allCases.compactMap(\.diaperKind)), Set(DiaperKind.allCases))
        XCTAssertEqual(Set(VoiceCareKind.allCases.compactMap(\.pottyKind)), Set(ChildPottyKind.allCases))
        XCTAssertEqual(Set(VoiceCareKind.allCases.compactMap(\.feedKind)), Set(FeedKind.allCases))
        XCTAssertFalse(VoiceCareKind.allCases.contains { $0.supports(.dog) })
    }

    func testEveryCareKindSavesACompletedEntryAndSupportsLastEntryLookup() async throws {
        for type in [CareProfileType.child, .adult] {
            let container = try store()
            let target = try profile(type, in: container)
            target.birthDate = now.addingTimeInterval(-300 * 86_400)
            try container.mainContext.save()
            for kind in VoiceCareKind.allCases where kind.supports(type) {
                var request = VoiceCareLog(profileID: target.id, kind: kind, date: now.addingTimeInterval(-60))
                switch kind {
                case .bottle, .pumping: request.value = 90; request.unit = .milliliters
                case .diaper: request.diaperKind = .both
                case .potty: request.pottyKind = .both
                case .sleep: request.durationMinutes = 10; request.sleepKind = .nap
                case .nursing: request.durationMinutes = 10; request.nursingSide = .left
                case .temperature: request.value = 37; request.unit = .celsius
                case .weight: request.value = 8; request.unit = .kilograms
                case .height: request.value = 70; request.unit = .centimeters
                case .headCircumference: request.value = 44; request.unit = .centimeters
                case .bloodPressure: request.value = 120; request.secondValue = 80
                case .heartRate: request.value = 70
                case .respiratoryRate: request.value = 16
                case .oxygenSaturation: request.value = 98
                case .glucose: request.value = 100; request.unit = .milligramsPerDeciliter
                case .pain: request.value = 0
                case .symptom, .activity, .note, .otherFeed: request.text = "Test entry"
                case .solidMeal: request.text = "Banana"
                default: break
                }
                let reply = try await VoiceLoggingService.log(request, in: container, now: now)
                let saved = try XCTUnwrap(events(in: container).first { $0.id == request.id }, kind.title)
                XCTAssertEqual(saved.profileID, target.id, kind.title)
                XCTAssertEqual(saved.type, kind.eventType, kind.title)
                XCTAssertEqual(saved.endDate, request.date, kind.title)
                XCTAssertFalse(saved.isTimerDraft, kind.title)
                XCTAssertFalse(saved.isTimerRunning, kind.title)
                XCTAssertTrue(reply.contains(target.name), kind.title)
                if let diaper = kind.diaperKind { XCTAssertEqual(saved.diaperKind, diaper) }
                if let potty = kind.pottyKind { XCTAssertEqual(saved.childPottyKind, potty) }
                if let activity = kind.activityType { XCTAssertEqual(saved.activityType, activity) }
                if let feed = kind.feedKind { XCTAssertEqual(saved.feedKind, feed) }
                let last = try VoiceLoggingService.last(kind: kind, profileID: target.id, in: container)
                XCTAssertFalse(last.contains("There is no recorded"), kind.title)
            }
        }
    }

    func testPresetDiapersPreserveDetailsWithoutAskingForAType() async throws {
        for kind in [VoiceCareKind.wetDiaper, .dirtyDiaper, .mixedDiaper] {
            let container = try store()
            let child = try profile(.child, in: container)
            let preset = try XCTUnwrap(kind.diaperKind)
            let request = VoiceCareLog(
                profileID: child.id, kind: kind, date: now.addingTimeInterval(-600), notes: "Test note",
                peeAmount: preset.hasPee ? .big : nil, pooAmount: preset.hasPoo ? .little : nil,
                pooColor: preset.hasPoo ? .brown : nil, pooTexture: preset.hasPoo ? .soft : nil, diaperRash: true
            )
            let reply = try await VoiceLoggingService.log(request, in: container, now: now)
            let event = try XCTUnwrap(events(in: container).first)
            XCTAssertEqual(event.diaperKind, preset)
            XCTAssertEqual(event.peeAmount, request.peeAmount)
            XCTAssertEqual(event.pooAmount, request.pooAmount)
            XCTAssertEqual(event.pooColor, request.pooColor)
            XCTAssertEqual(event.pooTexture, request.pooTexture)
            XCTAssertEqual(event.diaperRash, true)
            XCTAssertEqual(event.notes, "Test note")
            XCTAssertEqual(event.startDate, request.date)
            XCTAssertEqual(event.endDate, request.date)
            XCTAssertTrue(reply.contains(preset == .wet ? "pee" : preset == .dirty ? "poo" : "mixed"))
        }
    }

    func testConflictingOrIncompatibleEliminationDetailsNeverSave() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let requests = [
            VoiceCareLog(profileID: child.id, kind: .wetDiaper, date: now, diaperKind: .dirty),
            VoiceCareLog(profileID: child.id, kind: .wetDiaper, date: now, pooTexture: .hard),
            VoiceCareLog(profileID: child.id, kind: .dirtyDiaper, date: now, peeAmount: .big),
            VoiceCareLog(profileID: child.id, kind: .pottyPee, date: now, pottyKind: .poo),
            VoiceCareLog(profileID: child.id, kind: .potty, date: now),
            VoiceCareLog(profileID: child.id, kind: .pottyPoop, date: now, pottyLocation: .accident, pottyAccident: false),
            VoiceCareLog(profileID: child.id, kind: .bigPee, date: now, peeAmount: .little),
            VoiceCareLog(profileID: child.id, kind: .mediumPoo, date: now, pooAmount: .big),
            VoiceCareLog(profileID: child.id, kind: .bigMixedDiaper, date: now, peeAmount: .little)
        ]
        for request in requests {
            do { _ = try await VoiceLoggingService.log(request, in: container, now: now); XCTFail("Conflicting details saved") }
            catch { XCTAssertTrue(error is VoiceLoggingError) }
        }
        XCTAssertTrue(try events(in: container).isEmpty)
    }

    func testSpokenAmountPresetsPersistAllSizesAndMixedAmountsStayIndependent() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        for kind in VoiceCareKind.allCases where kind.diaperAmount != nil {
            let request = VoiceCareLog(profileID: child.id, kind: kind, date: now)
            let reply = try await VoiceLoggingService.log(request, in: container, now: now)
            let event = try XCTUnwrap(events(in: container).first { $0.id == request.id })
            let diaper = try XCTUnwrap(kind.diaperKind)
            XCTAssertEqual(event.diaperKind, diaper)
            XCTAssertEqual(event.peeAmount, diaper.hasPee ? kind.diaperAmount : nil)
            XCTAssertEqual(event.pooAmount, diaper.hasPoo ? kind.diaperAmount : nil)
            XCTAssertTrue(reply.contains(try XCTUnwrap(kind.diaperAmount).rawValue))
        }
        let mixed = VoiceCareLog(
            profileID: child.id, kind: .mixedDiaper, date: now,
            peeAmount: .big, pooAmount: .medium, pooColor: .green, pooTexture: .seedy
        )
        let reply = try await VoiceLoggingService.log(mixed, in: container, now: now)
        let event = try XCTUnwrap(events(in: container).first { $0.id == mixed.id })
        XCTAssertEqual(event.peeAmount, .big)
        XCTAssertEqual(event.pooAmount, .medium)
        XCTAssertEqual(event.pooColor, .green)
        XCTAssertEqual(event.pooTexture, .seedy)
        XCTAssertTrue(reply.contains("pee big"))
        XCTAssertTrue(reply.contains("poo medium green seedy"))
        XCTAssertNil(event.notes)
    }

    func testGenericDiaperFollowUpKeepsBothTypeAndAmountFromOneAnswer() throws {
        let container = try store()
        let child = try profile(.child, in: container)
        for answer in VoiceDiaperEntry.allCases {
            let intent = LogCareByVoiceIntent()
            intent.kind = .diaper
            intent.diaperEntry = answer
            let resolved = try intent.resolvedEntryKind()
            XCTAssertEqual(resolved, answer.kind)
            let event = try VoiceLoggingService.makeEvent(VoiceCareLog(profileID: child.id, kind: resolved, date: now), profile: child, now: now)
            XCTAssertEqual(event.diaperKind, answer.kind.diaperKind)
            if answer.kind.diaperKind?.hasPee == true { XCTAssertEqual(event.peeAmount, answer.kind.diaperAmount) }
            if answer.kind.diaperKind?.hasPoo == true { XCTAssertEqual(event.pooAmount, answer.kind.diaperAmount) }
        }
        let conflicting = LogCareByVoiceIntent()
        conflicting.kind = .wetDiaper
        conflicting.diaperEntry = .bigPoo
        XCTAssertThrowsError(try conflicting.resolvedEntryKind())
    }

    func testLastPeeAndPooIncludeMixedDiapersAndRespectTheRequestedAmount() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: child.id, kind: .mediumPoo, date: now.addingTimeInterval(-120)), in: container, now: now)
        _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: child.id, kind: .mixedDiaper, date: now.addingTimeInterval(-60), peeAmount: .big, pooAmount: .little), in: container, now: now)
        XCTAssertTrue(try VoiceLoggingService.last(kind: .wetDiaper, profileID: child.id, in: container).contains("mixed"))
        XCTAssertTrue(try VoiceLoggingService.last(kind: .dirtyDiaper, profileID: child.id, in: container).contains("mixed"))
        XCTAssertTrue(try VoiceLoggingService.last(kind: .mediumPoo, profileID: child.id, in: container).contains("poo, medium"))
    }

    func testPottyLocationAndAccidentAreKeptSeparateFromDiapers() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await VoiceLoggingService.log(VoiceCareLog(
            profileID: child.id, kind: .pottyBoth, date: now,
            pottyLocation: .trainingPants, pottyAccident: true, peeAmount: .little, pooTexture: .formed
        ), in: container, now: now)
        let event = try XCTUnwrap(events(in: container).first)
        XCTAssertEqual(event.type, .potty)
        XCTAssertEqual(event.childPottyKind, .both)
        XCTAssertEqual(event.childPottyLocation, .trainingPants)
        XCTAssertEqual(event.childPottyAccident, true)
        XCTAssertEqual(event.peeAmount, .little)
        XCTAssertEqual(event.pooTexture, .formed)
        XCTAssertNil(event.diaperKind)
        let adult = try profile(.adult, in: container)
        XCTAssertThrowsError(try VoiceLoggingService.makeEvent(VoiceCareLog(profileID: adult.id, kind: .pottyPee, date: now), profile: adult, now: now))
    }

    func testGrowthMeasurementsUseCanonicalUnitsAndRejectWrongUnitsAndProfiles() throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let height = try VoiceLoggingService.makeEvent(VoiceCareLog(profileID: child.id, kind: .height, date: now, value: 20, unit: .inches), profile: child, now: now)
        XCTAssertEqual(try XCTUnwrap(height.lengthCentimeters), 50.8, accuracy: 0.00001)
        let head = try VoiceLoggingService.makeEvent(VoiceCareLog(profileID: child.id, kind: .headCircumference, date: now, value: 40, unit: .centimeters), profile: child, now: now)
        XCTAssertEqual(head.headCircumferenceCentimeters, 40)
        let weight = try VoiceLoggingService.makeEvent(VoiceCareLog(profileID: child.id, kind: .weight, date: now, value: 3500, unit: .grams), profile: child, now: now)
        XCTAssertEqual(weight.weightKilograms, 3.5)
        let ounces = try VoiceLoggingService.makeEvent(VoiceCareLog(profileID: child.id, kind: .weight, date: now, value: 16, unit: .weightOunces), profile: child, now: now)
        XCTAssertEqual(try XCTUnwrap(ounces.weightKilograms), 0.45359237, accuracy: 0.000001)
        for (kind, unit) in [(VoiceCareKind.height, VoiceCareUnit.kilograms), (.weight, .ounces), (.headCircumference, .milliliters)] {
            XCTAssertThrowsError(try VoiceLoggingService.makeEvent(VoiceCareLog(profileID: child.id, kind: kind, date: now, value: 10, unit: unit), profile: child, now: now))
        }
        let adult = try profile(.adult, in: container)
        XCTAssertThrowsError(try VoiceLoggingService.makeEvent(VoiceCareLog(profileID: adult.id, kind: .headCircumference, date: now, value: 40, unit: .centimeters), profile: adult, now: now))
    }

    func testLastPooAndHeightIgnoreManyNewerEntriesOfOtherSubtypes() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: child.id, kind: .dirtyDiaper, date: now.addingTimeInterval(-600)), in: container, now: now)
        _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: child.id, kind: .height, date: now.addingTimeInterval(-600), value: 70, unit: .centimeters), in: container, now: now)
        for index in 0..<105 {
            for kind in [VoiceCareKind.wetDiaper, .weight] {
                let request = VoiceCareLog(profileID: child.id, kind: kind, date: now.addingTimeInterval(-Double(index)), value: kind == .weight ? 8 : nil, unit: kind == .weight ? .kilograms : nil)
                container.mainContext.insert(try VoiceLoggingService.makeEvent(request, profile: child, now: now))
            }
        }
        try container.mainContext.save()
        XCTAssertTrue(try VoiceLoggingService.last(kind: .dirtyDiaper, profileID: child.id, in: container).contains("Diaper: poo"))
        XCTAssertTrue(try VoiceLoggingService.last(kind: .height, profileID: child.id, in: container).contains("27.6 in"))
    }

    func testSolidMealVoiceLogHonorsReadinessAndCreatesLinkedFoodRecords() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        child.birthDate = now.addingTimeInterval(-30 * 86_400)
        try container.mainContext.save()
        do {
            _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: child.id, kind: .solidMeal, date: now, text: "Banana"), in: container, now: now)
            XCTFail("Solids readiness gate bypassed")
        } catch { XCTAssertTrue(error is VoiceLoggingError) }
        XCTAssertTrue(try events(in: container).isEmpty)
        child.birthDate = now.addingTimeInterval(-300 * 86_400)
        try container.mainContext.save()
        let request = VoiceCareLog(profileID: child.id, kind: .solidMeal, date: now, text: "Banana")
        _ = try await VoiceLoggingService.log(request, in: container, now: now)
        let items = try ModelContext(container).fetch(FetchDescriptor<SolidFoodEventItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.profileID, child.id)
        XCTAssertEqual(items.first?.eventID, request.id)
        XCTAssertEqual(items.first?.foodNameSnapshot, "Banana")
        _ = try await VoiceLoggingService.undo(profileID: child.id, in: container, now: now)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<SolidFoodEventItem>()).isEmpty)
    }

    func testMissingAndInvalidValuesNeverWriteAnEvent() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let requests = [
            VoiceCareLog(profileID: child.id, kind: .bottle, date: now, value: 120),
            VoiceCareLog(profileID: child.id, kind: .bottle, date: now, value: .nan, unit: .milliliters),
            VoiceCareLog(profileID: child.id, kind: .bottle, date: now, value: -1, unit: .ounces),
            VoiceCareLog(profileID: child.id, kind: .bottle, date: now, value: 5, unit: .pounds),
            VoiceCareLog(profileID: child.id, kind: .diaper, date: now),
            VoiceCareLog(profileID: child.id, kind: .sleep, date: now, durationMinutes: 0, sleepKind: .nap),
            VoiceCareLog(profileID: child.id, kind: .nursing, date: now, durationMinutes: 5),
            VoiceCareLog(profileID: child.id, kind: .note, date: now, text: "   ")
        ]
        for request in requests {
            do {
                _ = try await VoiceLoggingService.log(request, in: container, now: now)
                XCTFail("Invalid request was saved: \(request.kind)")
            } catch { XCTAssertTrue(error is VoiceLoggingError) }
        }
        XCTAssertTrue(try events(in: container).isEmpty)
    }

    func testAdultBloodPressureIncludesOptionalPulse() async throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        let reply = try await VoiceLoggingService.log(VoiceCareLog(
            profileID: adult.id, kind: .bloodPressure, date: now, value: 128, secondValue: 78, pulse: 65
        ), in: container, now: now)
        let details = try XCTUnwrap(events(in: container).first).healthObservationDetails
        XCTAssertEqual(details.systolicBloodPressure, 128)
        XCTAssertEqual(details.diastolicBloodPressure, 78)
        XCTAssertEqual(details.heartRateBPM, 65)
        XCTAssertTrue(reply.contains("128/78"))
    }

    func testAdultReadingsAndUnitConversions() throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        let temperature = try VoiceLoggingService.makeEvent(VoiceCareLog(
            profileID: adult.id, kind: .temperature, date: now, value: 98.6, unit: .fahrenheit
        ), profile: adult, now: now)
        XCTAssertEqual(try XCTUnwrap(temperature.temperatureCelsius), 37, accuracy: 0.0001)
        let weight = try VoiceLoggingService.makeEvent(VoiceCareLog(
            profileID: adult.id, kind: .weight, date: now, value: 150, unit: .pounds
        ), profile: adult, now: now)
        XCTAssertEqual(try XCTUnwrap(weight.weightKilograms), 68.0388555, accuracy: 0.000001)
        let glucose = try VoiceLoggingService.makeEvent(VoiceCareLog(
            profileID: adult.id, kind: .glucose, date: now, value: 5.5, unit: .millimolesPerLiter
        ), profile: adult, now: now)
        XCTAssertEqual(glucose.healthObservationDetails.bloodGlucoseUnit, .millimolesPerLiter)
        XCTAssertEqual(glucose.healthObservationDetails.bloodGlucoseValue, 5.5)
    }

    func testScoresAndIntegerReadingsRejectTruncationAndImpossiblePercentages() throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        for (kind, value) in [(VoiceCareKind.pain, -1.0), (.pain, 11), (.pain, 2.5), (.oxygenSaturation, 101), (.heartRate, 65.5), (.respiratoryRate, .infinity)] {
            XCTAssertThrowsError(try VoiceLoggingService.makeEvent(VoiceCareLog(
                profileID: adult.id, kind: kind, date: now, value: value
            ), profile: adult, now: now))
        }
        let noPain = try VoiceLoggingService.makeEvent(VoiceCareLog(
            profileID: adult.id, kind: .pain, date: now, value: 0, text: "Knee"
        ), profile: adult, now: now)
        XCTAssertEqual(noPain.healthObservationDetails.painScore, 0)
        XCTAssertEqual(noPain.healthObservationDetails.painLocation, "Knee")
    }

    func testCompletedNursingUsesAnIntervalEndingAtRequestedTime() throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let event = try VoiceLoggingService.makeEvent(VoiceCareLog(
            profileID: child.id, kind: .nursing, date: now, durationMinutes: 12, nursingSide: .right
        ), profile: child, now: now)
        XCTAssertEqual(event.startDate, now.addingTimeInterval(-720))
        XCTAssertEqual(event.endDate, now)
        XCTAssertEqual(event.rightDurationSeconds, 720)
        XCTAssertEqual(event.leftDurationSeconds, 0)
        XCTAssertFalse(event.isTimerDraft)
    }

    func testProfileTypeAndFutureTimeAreValidatedBeforeSaving() async throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        for request in [
            VoiceCareLog(profileID: adult.id, kind: .bottle, date: now, value: 4, unit: .ounces),
            VoiceCareLog(profileID: adult.id, kind: .pain, date: now.addingTimeInterval(60), value: 3),
            VoiceCareLog(profileID: UUID(), kind: .note, date: now, text: "Test note")
        ] {
            do { _ = try await VoiceLoggingService.log(request, in: container, now: now); XCTFail("Invalid profile or date accepted") }
            catch { XCTAssertTrue(error is VoiceLoggingError) }
        }
        adult.isArchived = true
        try container.mainContext.save()
        do {
            _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: adult.id, kind: .note, date: now, text: "Test"), in: container, now: now)
            XCTFail("Archived profile accepted")
        } catch { XCTAssertTrue(error is VoiceLoggingError) }
        XCTAssertTrue(try events(in: container).isEmpty)
    }

    func testLastBottleSearchDoesNotReturnSolidsOrAnotherProfile() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: child.id, kind: .bottle, date: now.addingTimeInterval(-600), value: 4, unit: .ounces), in: container, now: now)
        for n in 0..<105 {
            let solid = CareEvent(profileID: child.id, type: .feed, startDate: now.addingTimeInterval(-Double(n)), endDate: now)
            solid.feedKind = .solid
            container.mainContext.insert(solid)
        }
        try container.mainContext.save()
        let result = try VoiceLoggingService.last(kind: .bottle, profileID: child.id, in: container)
        XCTAssertTrue(result.contains("4 fluid ounces"))
    }

    func testUndoOnlyRemovesTheUnchangedVoiceEntryForThatProfile() async throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: adult.id, kind: .pain, date: now, value: 3), in: container, now: now)
        let manual = CareEvent(profileID: adult.id, type: .custom, startDate: now, endDate: now)
        container.mainContext.insert(manual)
        try container.mainContext.save()
        _ = try await VoiceLoggingService.undo(profileID: adult.id, in: container, now: now)
        let remaining = try events(in: container)
        XCTAssertEqual(remaining.map(\.id), [manual.id])
    }

    func testUndoRejectsAnEditedOrExpiredEntry() async throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        _ = try await VoiceLoggingService.log(VoiceCareLog(profileID: adult.id, kind: .note, date: now, text: "Test note"), in: container, now: now)
        let context = ModelContext(container)
        let event = try XCTUnwrap(context.fetch(FetchDescriptor<CareEvent>()).first)
        event.notes = "Edited note"
        event.updatedAt = now.addingTimeInterval(2)
        try context.save()
        for time in [now, now.addingTimeInterval(601)] {
            do { _ = try await VoiceLoggingService.undo(profileID: adult.id, in: container, now: time); XCTFail("Unsafe undo accepted") }
            catch { XCTAssertTrue(error is VoiceLoggingError) }
        }
        XCTAssertEqual(try events(in: container).count, 1)
    }

    func testSleepTimerCanStartPauseResumeAndFinishWithoutAnotherProfilesTimerChanging() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let adult = try profile(.adult, in: container)
        _ = try await VoiceLoggingService.manageTimer(action: .start, kind: .sleep, profileID: child.id, sleepKind: .nap, at: now, in: container, now: now)
        _ = try await VoiceLoggingService.manageTimer(action: .start, kind: .sleep, profileID: adult.id, sleepKind: .nightSleep, at: now, in: container, now: now)
        _ = try await VoiceLoggingService.manageTimer(action: .pause, kind: .sleep, profileID: child.id, at: now.addingTimeInterval(60), in: container, now: now.addingTimeInterval(60))
        _ = try await VoiceLoggingService.manageTimer(action: .resume, kind: .sleep, profileID: child.id, at: now.addingTimeInterval(120), in: container, now: now.addingTimeInterval(120))
        _ = try await VoiceLoggingService.manageTimer(action: .finish, kind: .sleep, profileID: child.id, at: now.addingTimeInterval(180), in: container, now: now.addingTimeInterval(180))
        let entries = try events(in: container)
        let saved = try XCTUnwrap(entries.first { $0.profileID == child.id })
        XCTAssertFalse(saved.isTimerDraft)
        XCTAssertEqual(saved.duration, 120)
        XCTAssertTrue(try XCTUnwrap(entries.first { $0.profileID == adult.id }).isTimerRunning)
    }

    func testNursingSwitchAndPumpingFinishPreserveDetails() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await VoiceLoggingService.manageTimer(action: .start, kind: .nursing, profileID: child.id, side: .left, at: now, in: container, now: now)
        _ = try await VoiceLoggingService.manageTimer(action: .switchSide, kind: .nursing, profileID: child.id, at: now.addingTimeInterval(60), in: container, now: now.addingTimeInterval(60))
        _ = try await VoiceLoggingService.manageTimer(action: .finish, kind: .nursing, profileID: child.id, at: now.addingTimeInterval(180), in: container, now: now.addingTimeInterval(180))
        let nursing = try XCTUnwrap(events(in: container).first)
        XCTAssertEqual(nursing.leftDurationSeconds, 60)
        XCTAssertEqual(nursing.rightDurationSeconds, 120)
        _ = try await VoiceLoggingService.manageTimer(action: .start, kind: .pumping, profileID: child.id, at: now, in: container, now: now)
        _ = try await VoiceLoggingService.manageTimer(action: .finish, kind: .pumping, profileID: child.id, amount: 90, unit: .milliliters, at: now.addingTimeInterval(300), in: container, now: now.addingTimeInterval(300))
        let pump = try XCTUnwrap(events(in: container).first { $0.type == .pumping })
        XCTAssertEqual(try XCTUnwrap(pump.amountOz), 90 / 29.5735295625, accuracy: 0.000001)
        XCTAssertFalse(pump.isTimerDraft)
    }

    private func nursing(
        _ action: VoiceTimerAction, side: NursingSide? = nil, seconds: Double = 0,
        continueExisting: Bool = false, profileID: UUID, container: ModelContainer
    ) async throws -> String {
        let date = now.addingTimeInterval(seconds)
        return try await VoiceLoggingService.manageTimer(
            action: action, kind: .nursing, profileID: profileID, side: side,
            continueExistingNursing: continueExisting, at: date, in: container, now: date
        )
    }

    func testLeftAndRightVoiceStartsContinueTheSameRunningNursingSession() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await nursing(.start, side: .left, continueExisting: true, profileID: child.id, container: container)
        let originalID = try XCTUnwrap(events(in: container).first?.id)
        _ = try await nursing(.start, side: .right, seconds: 60, continueExisting: true, profileID: child.id, container: container)
        _ = try await nursing(.start, side: .left, seconds: 180, continueExisting: true, profileID: child.id, container: container)
        var entries = try events(in: container)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, originalID)
        XCTAssertEqual(entries[0].activeNursingSide, .left)
        XCTAssertTrue(entries[0].isTimerRunning)
        XCTAssertEqual(entries[0].timerElapsed(at: now.addingTimeInterval(240)), 240)
        _ = try await nursing(.finish, seconds: 240, profileID: child.id, container: container)
        entries = try events(in: container)
        XCTAssertEqual(entries[0].leftDurationSeconds, 120)
        XCTAssertEqual(entries[0].rightDurationSeconds, 120)
        XCTAssertEqual(entries[0].duration, 240)
    }

    func testRightStartAndRepeatedToggleKeepBothSideDurations() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await nursing(.start, side: .right, profileID: child.id, container: container)
        _ = try await nursing(.switchSide, seconds: 60, profileID: child.id, container: container)
        XCTAssertEqual(try events(in: container).first?.activeNursingSide, .left)
        _ = try await nursing(.switchSide, seconds: 120, profileID: child.id, container: container)
        XCTAssertEqual(try events(in: container).first?.activeNursingSide, .right)
        _ = try await nursing(.finish, seconds: 180, profileID: child.id, container: container)
        let event = try XCTUnwrap(events(in: container).first)
        XCTAssertEqual(event.leftDurationSeconds, 60)
        XCTAssertEqual(event.rightDurationSeconds, 120)
        XCTAssertEqual(event.duration, 180)
    }

    func testExplicitSwitchToRightDoesNotAccidentallyToggleBackToLeft() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await nursing(.start, side: .left, profileID: child.id, container: container)
        _ = try await nursing(.switchSide, side: .right, seconds: 60, profileID: child.id, container: container)
        _ = try await nursing(.switchSide, side: .right, seconds: 120, profileID: child.id, container: container)
        XCTAssertEqual(try events(in: container).first?.activeNursingSide, .right)
        _ = try await nursing(.finish, seconds: 180, profileID: child.id, container: container)
        let event = try XCTUnwrap(events(in: container).first)
        XCTAssertEqual(event.leftDurationSeconds, 60)
        XCTAssertEqual(event.rightDurationSeconds, 120)
    }

    func testStartingTheOtherSideResumesPausedNursingWithoutCountingThePause() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await nursing(.start, side: .left, continueExisting: true, profileID: child.id, container: container)
        _ = try await nursing(.pause, seconds: 60, profileID: child.id, container: container)
        _ = try await nursing(.start, side: .right, seconds: 180, continueExisting: true, profileID: child.id, container: container)
        _ = try await nursing(.finish, seconds: 240, profileID: child.id, container: container)
        let entries = try events(in: container)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].leftDurationSeconds, 60)
        XCTAssertEqual(entries[0].rightDurationSeconds, 60)
        XCTAssertEqual(entries[0].duration, 120)
    }

    func testSwitchKeepsTheLiveSnapshotAndOtherChildsTimerCorrect() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let sibling = try profile(.child, in: container)
        _ = try await nursing(.start, side: .left, profileID: child.id, container: container)
        _ = try await nursing(.start, side: .left, profileID: sibling.id, container: container)
        XCTAssertEqual(try VoiceLoggingService.runningNursingProfileIDs(in: container), [child.id, sibling.id])
        _ = try await nursing(.switchSide, seconds: 60, profileID: child.id, container: container)
        let entries = try events(in: container)
        let event = try XCTUnwrap(entries.first { $0.profileID == child.id })
        XCTAssertEqual(entries.first { $0.profileID == sibling.id }?.activeNursingSide, .left)
        let snapshot = WidgetSnapshotService.makeSnapshot(
            profileID: child.id, profileType: .child, profileBirthDate: child.birthDate,
            babyName: child.name, events: [event], prediction: nil, now: now.addingTimeInterval(90)
        )
        XCTAssertEqual(snapshot.activeTimer?.activeNursingSide, .right)
        XCTAssertEqual(snapshot.activeTimer?.leftDurationSeconds, 60)
        XCTAssertEqual(snapshot.activeTimer?.rightDurationSeconds, 30)
        XCTAssertEqual(snapshot.activeTimer?.resolvedElapsedSeconds, 90)
        XCTAssertEqual(snapshot.activeTimer?.resolvedIsRunning, true)
    }

    func testSideSwitchRejectsMissingPausedAndStaleTimersWithoutCreatingEntries() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        do {
            _ = try await nursing(.switchSide, profileID: child.id, container: container)
            XCTFail("Switch should not create a new timer")
        } catch { XCTAssertTrue(error is VoiceLoggingError) }
        XCTAssertTrue(try events(in: container).isEmpty)
        _ = try await nursing(.start, side: .left, profileID: child.id, container: container)
        _ = try await nursing(.switchSide, seconds: 120, profileID: child.id, container: container)
        do {
            _ = try await nursing(.switchSide, seconds: 60, profileID: child.id, container: container)
            XCTFail("Stale switch should be rejected")
        } catch { XCTAssertTrue(error is VoiceLoggingError) }
        _ = try await nursing(.pause, seconds: 180, profileID: child.id, container: container)
        do {
            _ = try await nursing(.switchSide, seconds: 240, profileID: child.id, container: container)
            XCTFail("Paused timer must be resumed explicitly")
        } catch { XCTAssertTrue(error is VoiceLoggingError) }
        XCTAssertEqual(try VoiceLoggingService.runningNursingProfileIDs(in: container), [])
        let entries = try events(in: container)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].activeNursingSide, .right)
        XCTAssertEqual(entries[0].leftDurationSeconds, 120)
        XCTAssertEqual(entries[0].rightDurationSeconds, 60)
    }

    func testTimerCatalogCoversEveryChildTimerEventAndActivityType() {
        let supported = VoiceTimerKind.allCases.filter { $0.supports(.child) }
        let actualEventTypes = Set(supported.map(\.eventType))
        let expectedEventTypes = Set(EventType.cases(for: .child).filter(\.supportsTimer))
        XCTAssertEqual(actualEventTypes, expectedEventTypes)
        XCTAssertEqual(Set(supported.compactMap(\.activityType)), Set(ActivityType.cases(for: .child)))
        XCTAssertEqual(Set(supported.compactMap(\.sleepKind)), Set(SleepKind.allCases))
        XCTAssertEqual(Set(supported.compactMap(\.nursingSide)), Set(NursingSide.allCases))
        XCTAssertEqual(Set(supported.compactMap(\.feedKind)), Set(FeedKind.allCases))
        XCTAssertFalse(VoiceTimerKind.allCases.contains { $0.supports(.dog) })
    }

    func testEveryBabyTimerSupportsTheCompleteLifecycle() async throws {
        for kind in VoiceTimerKind.allCases where kind.supports(.child) {
            let container = try store()
            let child = try profile(.child, in: container)
            child.birthDate = now.addingTimeInterval(-300 * 86_400)
            try container.mainContext.save()
            func perform(_ action: VoiceTimerAction, _ seconds: Double, adjustedStart: Date? = nil) async throws {
                _ = try await VoiceLoggingService.manageTimer(
                    action: action, timerKind: kind, profileID: child.id,
                    side: kind.nursingSide ?? (kind == .nursing ? .left : nil),
                    sleepKind: kind == .sleep ? .nap : nil,
                    amount: action == .finish && (kind == .bottle || kind == .pumping) ? 90 : nil,
                    unit: action == .finish && (kind == .bottle || kind == .pumping) ? .milliliters : nil,
                    name: kind.needsName ? "Test timer" : nil,
                    adjustedStart: adjustedStart,
                    at: now.addingTimeInterval(seconds), in: container, now: now.addingTimeInterval(seconds)
                )
            }
            try await perform(.start, 0)
            let originalID = try XCTUnwrap(events(in: container).first?.id, kind.title)
            try await perform(.pause, 60)
            var event = try XCTUnwrap(events(in: container).first)
            XCTAssertFalse(event.isTimerRunning, kind.title)
            XCTAssertEqual(event.timerElapsed(at: now.addingTimeInterval(100)), 60, kind.title)
            try await perform(.resume, 120)
            try await perform(.adjustStart, 150, adjustedStart: now.addingTimeInterval(-60))
            event = try XCTUnwrap(events(in: container).first)
            XCTAssertEqual(event.startDate, now.addingTimeInterval(-60), kind.title)
            try await perform(.reset, 180)
            event = try XCTUnwrap(events(in: container).first)
            XCTAssertEqual(event.id, originalID, kind.title)
            XCTAssertEqual(event.startDate, now.addingTimeInterval(180), kind.title)
            XCTAssertEqual(event.timerElapsed(at: now.addingTimeInterval(180)), 0, kind.title)
            XCTAssertTrue(event.isTimerRunning, kind.title)
            try await perform(.finish, 240)
            event = try XCTUnwrap(events(in: container).first)
            XCTAssertFalse(event.isTimerDraft, kind.title)
            XCTAssertEqual(event.duration, 60, kind.title)
            XCTAssertEqual(event.type, kind.eventType, kind.title)
            XCTAssertEqual(event.activityType, kind.activityType, kind.title)
            if let preset = kind.sleepKind { XCTAssertEqual(event.sleepKind, preset, kind.title) }
            if let feed = kind.feedKind { XCTAssertEqual(event.feedKind, feed, kind.title) }
            if kind == .bottle || kind == .pumping {
                XCTAssertEqual(try XCTUnwrap(event.amountOz), 90 / 29.5735295625, accuracy: 0.000001, kind.title)
            }
            try await perform(.start, 250)
            try await perform(.discard, 300)
            XCTAssertEqual(try events(in: container).count, 1, kind.title)
            XCTAssertTrue(try VoiceLoggingService.timerOptions(in: container).isEmpty, kind.title)
        }
    }

    func testActivityCommandsCannotMutateAnotherActivitySubtype() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await VoiceLoggingService.manageTimer(action: .start, timerKind: .tummyTime, profileID: child.id, at: now, in: container, now: now)
        for action in [VoiceTimerAction.start, .pause, .resume, .finish, .reset, .discard, .adjustStart] {
            do {
                _ = try await VoiceLoggingService.manageTimer(
                    action: action, timerKind: .bath, profileID: child.id,
                    adjustedStart: now, at: now.addingTimeInterval(60), in: container, now: now.addingTimeInterval(60)
                )
                XCTFail("Bath command changed tummy time: \(action)")
            } catch { XCTAssertTrue(error is VoiceLoggingError) }
        }
        let event = try XCTUnwrap(events(in: container).first)
        XCTAssertTrue(event.isTimerRunning)
        XCTAssertEqual(event.activityType, .tummyTime)
        XCTAssertEqual(try events(in: container).count, 1)
    }

    func testTimerSelectionIncludesAllProfilesAndSeparatesRunningFromPaused() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let sibling = try profile(.child, in: container)
        _ = try await VoiceLoggingService.manageTimer(action: .start, timerKind: .nap, profileID: child.id, at: now, in: container, now: now)
        _ = try await VoiceLoggingService.manageTimer(action: .start, timerKind: .pumping, profileID: sibling.id, at: now, in: container, now: now)
        _ = try await VoiceLoggingService.manageTimer(action: .pause, timerKind: .nap, profileID: child.id, at: now.addingTimeInterval(60), in: container, now: now.addingTimeInterval(60))
        XCTAssertEqual(try VoiceLoggingService.timerOptions(action: .pause, in: container).map(\.profileID), [sibling.id])
        XCTAssertEqual(try VoiceLoggingService.timerOptions(action: .resume, in: container).map(\.profileID), [child.id])
        XCTAssertEqual(try VoiceLoggingService.timerOptions(action: .finish, in: container).count, 2)
        XCTAssertEqual(try VoiceLoggingService.timerOptions(profileID: child.id, action: .finish, in: container).count, 1)
        let statuses = try VoiceLoggingService.timerOptions(now: now.addingTimeInterval(90), in: container)
        XCTAssertEqual(statuses.first { $0.profileID == child.id }?.elapsedSeconds, 60)
        XCTAssertEqual(statuses.first { $0.profileID == sibling.id }?.elapsedSeconds, 90)
    }

    func testResetDiscardAndCorrectionRejectAChangedSelection() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await VoiceLoggingService.manageTimer(action: .start, timerKind: .tummyTime, profileID: child.id, at: now, in: container, now: now)
        let chosen = try XCTUnwrap(VoiceLoggingService.timerOptions(in: container).first)
        _ = try await VoiceLoggingService.manageTimer(action: .pause, timerKind: .tummyTime, profileID: child.id, at: now.addingTimeInterval(60), in: container, now: now.addingTimeInterval(60))
        for action in [VoiceTimerAction.reset, .discard, .adjustStart] {
            do {
                _ = try await VoiceLoggingService.manageTimer(
                    action: action, timerKind: .tummyTime, profileID: child.id,
                    eventID: chosen.id, expectedUpdatedAt: chosen.updatedAt, adjustedStart: now,
                    at: now.addingTimeInterval(120), in: container, now: now.addingTimeInterval(120)
                )
                XCTFail("Stale confirmed action accepted: \(action)")
            } catch { XCTAssertTrue(error is VoiceLoggingError) }
        }
        let event = try XCTUnwrap(events(in: container).first)
        XCTAssertTrue(event.isTimerDraft)
        XCTAssertFalse(event.isTimerRunning)
        XCTAssertEqual(event.timerAccumulatedSeconds, 60)
        XCTAssertEqual(event.startDate, now)
    }

    func testNativeVerbSelectorsResolveExactlyOneActionAndKind() throws {
        for kind in VoiceTimerKind.allCases {
            for action in [VoiceTimerAction.pause, .resume, .finish, .reset, .discard, .adjustStart] {
                let intent = ManageCareTimerByVoiceIntent()
                switch action {
                case .pause: intent.pauseTimer = kind
                case .resume: intent.resumeTimer = kind
                case .finish: intent.finishTimer = kind
                case .reset: intent.resetTimer = kind
                case .discard: intent.discardTimer = kind
                case .adjustStart: intent.correctTimer = kind
                default: XCTFail("Unexpected selector")
                }
                let selected = try intent.selection()
                XCTAssertEqual(selected.0, action)
                XCTAssertEqual(selected.1, kind)
            }
        }
        let conflicting = ManageCareTimerByVoiceIntent()
        conflicting.pauseTimer = .pumping
        conflicting.discardTimer = .nap
        XCTAssertThrowsError(try conflicting.selection())
        let wrongVerb = ManageCareTimerByVoiceIntent()
        wrongVerb.pauseTimer = .tummyTime
        wrongVerb.action = .discard
        XCTAssertThrowsError(try wrongVerb.selection())
    }

    func testFinishingABottleValidatesSuppliedAmountsAndCanLeaveAnUnknownAmountBlank() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        _ = try await VoiceLoggingService.manageTimer(action: .start, timerKind: .bottle, profileID: child.id, at: now, in: container, now: now)
        for amount in [90.0, -1, .nan] {
            do {
                _ = try await VoiceLoggingService.manageTimer(
                    action: .finish, timerKind: .bottle, profileID: child.id, amount: amount,
                    at: now.addingTimeInterval(60), in: container, now: now.addingTimeInterval(60)
                )
                XCTFail("Invalid supplied amount saved")
            } catch { XCTAssertTrue(error is VoiceLoggingError) }
        }
        let event = try XCTUnwrap(events(in: container).first)
        XCTAssertTrue(event.isTimerRunning)
        XCTAssertNil(event.amountOz)
        _ = try await VoiceLoggingService.manageTimer(
            action: .finish, timerKind: .bottle, profileID: child.id,
            at: now.addingTimeInterval(60), in: container, now: now.addingTimeInterval(60)
        )
        let saved = try XCTUnwrap(events(in: container).first)
        XCTAssertFalse(saved.isTimerDraft)
        XCTAssertNil(saved.amountOz)
    }

    func testLegacyUntypedFeedAndActivityDraftsRemainControllable() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        for type in [EventType.feed, .activity] {
            let draft = try XCTUnwrap(EventTimerService.start(type: type, caregiverName: "Caregiver", events: [], context: container.mainContext, profileID: child.id, profileType: .child, at: now))
            try container.mainContext.save()
            let option = try XCTUnwrap(VoiceLoggingService.timerOptions(in: container).first { $0.id == draft.id })
            _ = try await VoiceLoggingService.manageTimer(action: .pause, timerKind: option.kind, profileID: child.id, eventID: draft.id, at: now.addingTimeInterval(60), in: container, now: now.addingTimeInterval(60))
            XCTAssertFalse(try XCTUnwrap(events(in: container).first { $0.id == draft.id }).isTimerRunning)
        }
    }

    func testSolidMealTimerDoesNotBypassTheExistingReadinessGate() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        child.birthDate = now.addingTimeInterval(-30 * 86_400)
        try container.mainContext.save()
        do {
            _ = try await VoiceLoggingService.manageTimer(action: .start, timerKind: .solidMeal, profileID: child.id, name: "Test meal", at: now, in: container, now: now)
            XCTFail("Solids readiness gate bypassed")
        } catch { XCTAssertTrue(error is VoiceLoggingError) }
        XCTAssertTrue(try events(in: container).isEmpty)
    }

    func testConcurrentTimerStartsCannotCreateDuplicateTimers() async throws {
        let container = try store()
        let child = try profile(.child, in: container)
        async let first: String? = try? VoiceLoggingService.manageTimer(action: .start, kind: .sleep, profileID: child.id, sleepKind: .nap, at: now, in: container, now: now)
        async let second: String? = try? VoiceLoggingService.manageTimer(action: .start, kind: .sleep, profileID: child.id, sleepKind: .nap, at: now, in: container, now: now)
        let results = await [first, second]
        XCTAssertEqual(results.compactMap { $0 }.count, 1)
        XCTAssertEqual(try events(in: container).count, 1)
    }

    func testMedicationPlanRevalidationAndDuplicateDoseProtection() throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        let medication = Medication(profileID: adult.id, name: "Test Medication")
        container.mainContext.insert(medication)
        let regimen = MedicationRegimen(profileID: adult.id, medicationID: medication.id, scheduleKind: .daily, startDate: now.addingTimeInterval(-86_400), doseAmount: 1, doseUnit: "tablet", doseTimes: [MedicationDoseTime(hour: 0, minute: 0)])
        container.mainContext.insert(regimen)
        try container.mainContext.save()
        let plan = try VoiceLoggingService.medicationPlan(medicationID: medication.id, profileID: adult.id, at: now, in: container, now: now)
        let occurrence = try XCTUnwrap(plan.occurrences.first)
        _ = try VoiceLoggingService.recordMedication(plan: plan, occurrenceKey: occurrence.occurrenceKey, status: .taken, at: now, in: container, now: now)
        let retry = try VoiceLoggingService.recordMedication(plan: plan, occurrenceKey: occurrence.occurrenceKey, status: .taken, at: now, in: container, now: now)
        XCTAssertTrue(retry.contains("already"))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MedicationDoseRecord>()), 1)
        XCTAssertThrowsError(try VoiceLoggingService.recordMedication(plan: plan, occurrenceKey: occurrence.occurrenceKey, status: .skipped, at: now, in: container, now: now))
        regimen.updatedAt = now.addingTimeInterval(1)
        try container.mainContext.save()
        XCTAssertThrowsError(try VoiceLoggingService.recordMedication(plan: plan, occurrenceKey: nil, status: .taken, at: now, in: container, now: now))
    }

    func testMedicationCannotBeLoggedForAnotherProfile() throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        let child = try profile(.child, in: container)
        let med = Medication(profileID: adult.id, name: "Test Medication")
        container.mainContext.insert(med)
        try container.mainContext.save()
        XCTAssertThrowsError(try VoiceLoggingService.medicationPlan(medicationID: med.id, profileID: child.id, at: now, in: container, now: now))
    }

    func testAsNeededMedicationRespectsTheSavedDailyLimit() throws {
        let container = try store()
        let adult = try profile(.adult, in: container)
        let med = Medication(profileID: adult.id, name: "Test Medication")
        let regimen = MedicationRegimen(
            profileID: adult.id, medicationID: med.id, scheduleKind: .asNeeded,
            startDate: now.addingTimeInterval(-86_400), doseAmount: 1, doseUnit: "tablet", maximumDosesPerDay: 1
        )
        container.mainContext.insert(med)
        container.mainContext.insert(regimen)
        try container.mainContext.save()
        var plan = try VoiceLoggingService.medicationPlan(medicationID: med.id, profileID: adult.id, at: now, in: container, now: now)
        _ = try VoiceLoggingService.recordMedication(plan: plan, occurrenceKey: nil, status: .taken, at: now, in: container, now: now)
        plan = try VoiceLoggingService.medicationPlan(medicationID: med.id, profileID: adult.id, at: now, in: container, now: now)
        XCTAssertThrowsError(try VoiceLoggingService.recordMedication(plan: plan, occurrenceKey: nil, status: .taken, at: now, in: container, now: now))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MedicationDoseRecord>()), 1)
    }

    func testAPlanChangedDuringConfirmationCannotRecordADose() throws {
        let container = try store()
        let child = try profile(.child, in: container)
        let med = Medication(profileID: child.id, name: "Test Medication")
        let regimen = MedicationRegimen(
            profileID: child.id, medicationID: med.id, scheduleKind: .daily,
            startDate: now.addingTimeInterval(-86_400), doseAmount: 1, doseUnit: "mL",
            doseTimes: [MedicationDoseTime(hour: 0, minute: 0)]
        )
        container.mainContext.insert(med)
        container.mainContext.insert(regimen)
        try container.mainContext.save()
        let plan = try VoiceLoggingService.medicationPlan(medicationID: med.id, profileID: child.id, at: now, in: container, now: now)
        let occurrence = try XCTUnwrap(plan.occurrences.first)
        regimen.doseAmount = 2
        regimen.updatedAt = now.addingTimeInterval(1)
        try container.mainContext.save()
        XCTAssertThrowsError(try VoiceLoggingService.recordMedication(
            plan: plan, occurrenceKey: occurrence.occurrenceKey, status: .taken, at: now, in: container, now: now
        ))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<MedicationDoseRecord>()), 0)
    }
}
