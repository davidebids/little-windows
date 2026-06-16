import XCTest
import SwiftData
import SwiftUI
@testable import LittleWindows

final class SleepPredictionEngineTests: XCTestCase {
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
            babyName: "Ethan",
            leadMinutes: 10
        )

        XCTAssertEqual(copy.title, "Nap window soon")
        XCTAssertTrue(copy.body.contains("estimated"))
        XCTAssertFalse(copy.body.contains("needs to"))
    }

    @MainActor
    func testProfileMigrationCreatesEthanAndAssignsLegacyRecords() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let legacyEvent = BabyEvent(type: .feed, startDate: Date())
        let legacyMilestone = MilestoneEntry(
            title: "First smile",
            date: Date(),
            category: .social
        )
        context.insert(legacyEvent)
        context.insert(legacyMilestone)
        try context.save()

        ProfileMigrationService.ensureProfilesAndAssignments(context: context)

        let profiles = try context.fetch(FetchDescriptor<BabyProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Ethan")
        XCTAssertEqual(legacyEvent.profileID, profiles.first?.id)
        XCTAssertEqual(legacyMilestone.profileID, profiles.first?.id)
    }

    @MainActor
    func testProfileSelectionFallsBackToActiveChild() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let ethan = BabyProfile(name: "Ethan", birthDate: Date(), sex: .male)
        let sibling = BabyProfile(name: "Sibling", birthDate: Date(), sex: .unknown)
        context.insert(ethan)
        context.insert(sibling)
        try context.save()

        ProfileService.shared.switchProfile(ethan)
        ethan.isArchived = true

        let selected = ProfileService.shared.ensureSelection(in: [ethan, sibling])
        XCTAssertEqual(selected?.id, sibling.id)
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
        let event = BabyEvent(
            profileID: profileID,
            type: .sleep,
            startDate: Date(timeIntervalSinceReferenceDate: 1_000)
        )

        let snapshot = WidgetSnapshotService.activeSnapshot(
            event: event,
            profileID: profileID,
            babyName: "Ethan",
            additionalActiveCount: 0,
            now: Date(timeIntervalSinceReferenceDate: 1_300)
        )

        XCTAssertEqual(snapshot.profileID, profileID)
        XCTAssertEqual(snapshot.profileName, "Ethan")
        XCTAssertTrue(snapshot.stopURL.absoluteString.contains("/profile/\(profileID.uuidString)/"))
    }

    @MainActor
    func testProfileIDsRoundTripThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let ethan = BabyProfile(name: "Ethan", birthDate: Date(), sex: .male)
        let sibling = BabyProfile(name: "Sibling", birthDate: Date(), sex: .unknown)
        context.insert(ethan)
        context.insert(sibling)
        let event = BabyEvent(
            profileID: sibling.id,
            type: .diaper,
            startDate: Date(timeIntervalSinceReferenceDate: 1_000)
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

        let importedEvents = try context.fetch(FetchDescriptor<BabyEvent>())
        let importedAppointments = try context.fetch(FetchDescriptor<DoctorAppointment>())
        XCTAssertEqual(importedEvents.first?.profileID, sibling.id)
        XCTAssertEqual(importedAppointments.first?.profileID, sibling.id)
    }

    @MainActor
    func testDogProfilesAreSelectableFamilyProfiles() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let ethan = BabyProfile(name: "Ethan", birthDate: Date(), sex: .male)
        let meso = BabyProfile(
            profileType: .dog,
            name: "Meso",
            birthDate: Date().addingTimeInterval(-12 * 7 * 24 * 60 * 60),
            sex: .female,
            displayColor: "teal",
            species: "dog",
            breed: "Mini Goldendoodle"
        )
        context.insert(ethan)
        context.insert(meso)
        try context.save()

        ProfileService.shared.switchProfile(meso)

        XCTAssertEqual(ProfileService.shared.selectedProfile(in: [ethan, meso])?.id, meso.id)
        XCTAssertEqual(ProfileService.shared.allActiveProfiles(in: [ethan, meso]).map(\.id), [ethan.id, meso.id])
        XCTAssertEqual(meso.profileSubtitle, "Mini Goldendoodle")
    }

    func testDogEventDetailsDriveTimelineSummaries() {
        var pottyDetails = DogEventDetails()
        pottyDetails.pottyType = .poop
        pottyDetails.pottyLocation = .walk
        pottyDetails.stoolQuality = .normal
        pottyDetails.poopColor = .brown
        let potty = BabyEvent(type: .potty, startDate: Date(), endDate: Date())
        potty.profileTypeSnapshot = .dog
        potty.dogDetails = pottyDetails

        XCTAssertEqual(potty.displayTitle, "Potty: poop, walk, normal, brown")

        var walkDetails = DogEventDetails()
        walkDetails.distance = 1.2
        walkDetails.distanceUnit = .miles
        walkDetails.peeCount = 1
        walkDetails.poopCount = 1
        walkDetails.leashBehavior = .pulled
        let walk = BabyEvent(
            type: .walk,
            startDate: Date(timeIntervalSinceReferenceDate: 1_000),
            endDate: Date(timeIntervalSinceReferenceDate: 1_000 + 34 * 60)
        )
        walk.profileTypeSnapshot = .dog
        walk.dogDetails = walkDetails

        XCTAssertTrue(walk.displayTitle.contains("34m"))
        XCTAssertTrue(walk.displayTitle.contains("1.2 mi"))
        XCTAssertTrue(walk.displayTitle.contains("pulled"))
    }

    @MainActor
    func testPuppyStageGuideMatchesDogAgeAndPersistsReadState() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let meso = BabyProfile(
            profileType: .dog,
            name: "Meso",
            birthDate: Date().addingTimeInterval(-12 * 7 * 24 * 60 * 60),
            sex: .female
        )
        context.insert(meso)
        let guide = try XCTUnwrap(PuppyStageGuideService.shared.currentGuide(for: meso))

        XCTAssertEqual(guide.stageKey, "stage_12_weeks")

        PuppyStageGuideService.shared.markGuideRead(
            guide,
            in: context,
            readStates: [],
            profileID: meso.id
        )

        let states = try context.fetch(FetchDescriptor<PuppyStageGuideReadState>())
        XCTAssertEqual(states.first?.profileID, meso.id)
        XCTAssertEqual(states.first?.guideID, guide.id)
        XCTAssertNotNil(states.first?.firstOpenedAt)
    }

    @MainActor
    func testDogProfileAndDogDetailsRoundTripThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let meso = BabyProfile(
            profileType: .dog,
            name: "Meso",
            birthDate: Date(timeIntervalSinceReferenceDate: 1_000),
            sex: .female,
            adoptionDate: Date(timeIntervalSinceReferenceDate: 2_000),
            species: "dog",
            breed: "Mini Goldendoodle",
            coatColor: "Apricot"
        )
        context.insert(meso)
        var details = DogEventDetails()
        details.foodName = "Chicken and rice"
        details.foodAmount = 4
        details.foodUnit = .ounces
        details.mealType = .dinner
        details.eatenAmount = .most
        let food = BabyEvent(
            profileID: meso.id,
            type: .food,
            startDate: Date(timeIntervalSinceReferenceDate: 3_000)
        )
        food.profileTypeSnapshot = .dog
        food.dogDetails = details
        context.insert(food)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)

        let importedProfiles = try context.fetch(FetchDescriptor<BabyProfile>())
        let importedDog = try XCTUnwrap(importedProfiles.first { $0.profileType == .dog })
        XCTAssertEqual(importedDog.breed, "Mini Goldendoodle")
        XCTAssertEqual(importedDog.coatColor, "Apricot")

        let importedEvent = try XCTUnwrap(try context.fetch(FetchDescriptor<BabyEvent>()).first { $0.type == .food })
        XCTAssertEqual(importedEvent.profileID, meso.id)
        XCTAssertEqual(importedEvent.profileTypeSnapshot, .dog)
        XCTAssertEqual(importedEvent.dogDetails.foodName, "Chicken and rice")
        XCTAssertEqual(importedEvent.dogDetails.eatenAmount, .most)
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

    func testDayTimelinePlacesOverlappingEventsInSeparateColumns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let sleep = BabyEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(9 * 3600),
            endDate: day.addingTimeInterval(10 * 3600)
        )
        let feed = BabyEvent(
            type: .feed,
            startDate: day.addingTimeInterval(9.5 * 3600),
            endDate: day.addingTimeInterval(9.75 * 3600)
        )
        let diaper = BabyEvent(
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
        let diaper = BabyEvent(
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

    @MainActor
    func testDeepLinkRouterOpensHistoryTab() {
        let router = DeepLinkRouter.shared
        router.route(URL(string: "littlewindows://history")!)
        XCTAssertEqual(router.selectedTab, .history)
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
        let event = BabyEvent(
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
    func testLiveActivityStopActiveCommandPausesPrimaryTimerDraft() async throws {
        let container = try makeInMemoryContainer()
        let event = BabyEvent(
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
        XCTAssertLessThanOrEqual(target - statistics.weightedMedian, 24)
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

    @MainActor
    func testBundledHuckleberryHistoryImportsWithoutActiveTimers() throws {
        let schema = Schema([
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let data = try SampleData.bundledHuckleberryHistory()
        try DataExportImportService.importData(data, context: container.mainContext)

        let events = try container.mainContext.fetch(FetchDescriptor<BabyEvent>())
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
            container.mainContext.fetch(FetchDescriptor<BabyProfile>()).first
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
    func testLegacyHuckleberryGrowthMigrationRecoversMeasurements() throws {
        let schema = Schema([
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let profile = BabyProfile(name: "Ethan", birthDate: SampleData.defaultBirthDate)
        container.mainContext.insert(profile)
        let event = BabyEvent(
            type: .custom,
            title: "Growth",
            startDate: profile.birthDate,
            endDate: profile.birthDate,
            notes: "Weight: 8.6lbs.oz\nLength: 1.68ft.in\nHead: 14.2in\nBirth visit"
        )
        container.mainContext.insert(event)
        try container.mainContext.save()

        XCTAssertEqual(
            try LegacyHuckleberryGrowthMigration.migrate(in: container.mainContext),
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
        let schema = Schema([
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        try DataExportImportService.importData(
            SampleData.bundledHuckleberryHistory(),
            context: container.mainContext
        )
        let profile = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<BabyProfile>()).first
        )
        let events = try container.mainContext.fetch(FetchDescriptor<BabyEvent>())

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
        let first = BabyEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(9 * 3600),
            endDate: day.addingTimeInterval(10 * 3600)
        )
        first.sleepKind = .nap
        let second = BabyEvent(
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
        let first = BabyEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(7 * 3600),
            endDate: day.addingTimeInterval(8 * 3600)
        )
        first.sleepKind = .nightSleep
        let second = BabyEvent(
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

        let evening = BabyEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(20 * 3600),
            endDate: day.addingTimeInterval(23 * 3600)
        )
        evening.sleepKind = .nightSleep
        let morning = BabyEvent(
            type: .sleep,
            startDate: nextDay.addingTimeInterval(1 * 3600),
            endDate: nextDay.addingTimeInterval(6 * 3600)
        )
        morning.sleepKind = .nightSleep
        let nap = BabyEvent(
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

    func testNightSleepScoreUsesNightSleepSegmentsAndWakeGaps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        let firstSegment = BabyEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(20 * 3600),
            endDate: nextDay
        )
        firstSegment.sleepKind = .nightSleep
        let secondSegment = BabyEvent(
            type: .sleep,
            startDate: nextDay.addingTimeInterval(30 * 60),
            endDate: nextDay.addingTimeInterval(4 * 3600)
        )
        secondSegment.sleepKind = .nightSleep
        let nap = BabyEvent(
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

    func testInsightsCustomDateRangeIncludesBothSelectedDaysOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 1)
        )!
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let thirdDay = calendar.date(byAdding: .day, value: 2, to: firstDay)!
        let events = [firstDay, secondDay, thirdDay].map { day in
            let event = BabyEvent(
                type: .sleep,
                startDate: day.addingTimeInterval(10 * 3600),
                endDate: day.addingTimeInterval(11 * 3600)
            )
            event.sleepKind = .nap
            return event
        }

        let snapshot = InsightsAnalyticsService.snapshot(
            profileName: "Ethan",
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
            profileName: "Ethan",
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

    func testInsightsBedtimeExtractionIgnoresEarlyMorningSegments() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let end = calendar.date(byAdding: .day, value: 2, to: day)!
        let evening = BabyEvent(
            type: .sleep,
            startDate: day.addingTimeInterval(20 * 3600),
            endDate: day.addingTimeInterval(23 * 3600)
        )
        evening.sleepKind = .nightSleep
        let earlyMorning = BabyEvent(
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
        let nursing = BabyEvent(
            type: .nursing,
            startDate: now,
            endDate: now.addingTimeInterval(10 * 60)
        )
        nursing.nursingSide = .left
        let sleep = BabyEvent(
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
        let wet = BabyEvent(type: .diaper, startDate: day.addingTimeInterval(3600), endDate: nil)
        wet.diaperKind = .wet
        let both = BabyEvent(type: .diaper, startDate: day.addingTimeInterval(7200), endDate: nil)
        both.diaperKind = .both
        let tummy = BabyEvent(
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
        let bath = BabyEvent(type: .activity, startDate: Date())
        bath.activityType = .bath
        let nursing = BabyEvent(type: .nursing, startDate: Date())
        nursing.nursingSide = .left
        nursing.activeNursingSide = .left
        let sleep = BabyEvent(type: .sleep, startDate: Date())
        sleep.sleepKind = .nap

        XCTAssertEqual(
            EventTimerService.primaryActiveEvent(in: [bath, nursing, sleep])?.id,
            sleep.id
        )
        XCTAssertEqual(
            EventTimerService.primaryActiveEvent(in: [bath, nursing])?.id,
            nursing.id
        )
    }

    @MainActor
    func testWidgetSnapshotIncludesPrimaryTimerAndAdditionalCount() {
        let start = Date().addingTimeInterval(-600)
        let sleep = BabyEvent(type: .sleep, startDate: start)
        sleep.sleepKind = .nap
        let bath = BabyEvent(type: .activity, startDate: start)
        bath.activityType = .bath

        let snapshot = WidgetSnapshotService.makeSnapshot(
            babyName: "Ethan",
            events: [bath, sleep],
            prediction: nil
        )

        XCTAssertEqual(snapshot.activeTimer?.id, sleep.id)
        XCTAssertEqual(snapshot.activeTimer?.eventLabel, "Sleeping")
        XCTAssertEqual(snapshot.activeTimer?.additionalActiveCount, 1)
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
            babyName: "Ethan",
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
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let start = Date().addingTimeInterval(-300)
        let event = BabyEvent(type: .nursing, startDate: start)
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
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let start = Date().addingTimeInterval(-300)
        let event = BabyEvent(type: .nursing, startDate: start)
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
        let event = BabyEvent(
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
            babyName: "Ethan",
            additionalActiveCount: 0,
            now: now
        )

        XCTAssertEqual(result, correctedStart)
        XCTAssertEqual(event.startDate, correctedStart)
        XCTAssertEqual(snapshot.startDate, correctedStart)
        XCTAssertEqual(now.timeIntervalSince(event.startDate), 420, accuracy: 0.001)
    }

    @MainActor
    func testActiveTimerStartCannotMoveIntoFuture() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let event = BabyEvent(
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
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let now = Date(timeIntervalSinceReferenceDate: 300_000)
        let originalStart = now.addingTimeInterval(-120)
        let correctedStart = now.addingTimeInterval(-300)
        let event = BabyEvent(type: .nursing, startDate: originalStart)
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
        let tummy = BabyEvent(type: .custom)
        tummy.typeRawValue = "tummyTime"
        let reading = BabyEvent(type: .custom)
        reading.typeRawValue = "reading"
        let bath = BabyEvent(type: .custom)
        bath.typeRawValue = "bath"

        XCTAssertEqual(tummy.type, .activity)
        XCTAssertEqual(tummy.activityType, .tummyTime)
        XCTAssertEqual(reading.activityType, .storyTime)
        XCTAssertEqual(bath.activityType, .bath)
    }

    func testRichDiaperAndMedicineTimelineSummaries() {
        let diaper = BabyEvent(type: .diaper)
        diaper.diaperKind = .both
        diaper.peeAmount = .big
        diaper.pooAmount = .little
        diaper.pooColor = .brown

        let medicine = BabyEvent(type: .medicine)
        medicine.medicineName = "Tylenol"
        medicine.dose = 2.5
        medicine.medicineUnit = .milliliters

        XCTAssertEqual(diaper.displayTitle, "Diaper: mixed — pee big, poo little brown")
        XCTAssertEqual(medicine.displayTitle, "Medicine: Tylenol, 2.5 mL")
    }

    func testTemperatureStoresCanonicalCelsiusAndConvertsForDisplay() {
        let event = BabyEvent(type: .temperature)
        event.temperatureCelsius = 37
        event.temperatureUnit = .fahrenheit
        event.temperatureMethod = .forehead

        XCTAssertEqual(event.temperatureValue(in: .fahrenheit) ?? 0, 98.6, accuracy: 0.001)
        XCTAssertEqual(event.temperatureValue(in: .celsius) ?? 0, 37, accuracy: 0.001)
        XCTAssertEqual(event.displayTitle, "Temperature: 98.6°F, forehead")
    }

    @MainActor
    func testActivityTimerSnapshotUsesSpecificSubtype() {
        let bath = BabyEvent(type: .activity, startDate: Date())
        bath.activityType = .bath

        let snapshot = WidgetSnapshotService.activeSnapshot(
            event: bath,
            babyName: "Ethan",
            additionalActiveCount: 0
        )

        XCTAssertEqual(snapshot.typeRawValue, EventType.activity.rawValue)
        XCTAssertEqual(snapshot.eventLabel, "Bath")
        XCTAssertEqual(snapshot.systemImage, "bathtub.fill")
    }

    func testGrowthTemperatureAndActivityInsightsUseNewFields() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let growth = BabyEvent(type: .growth, startDate: day)
        growth.weightPounds = 14
        growth.weightOunces = 8
        growth.heightFeet = 2
        growth.heightInches = 1.5
        let temperature = BabyEvent(type: .temperature, startDate: day.addingTimeInterval(60))
        temperature.temperatureCelsius = 37
        let outdoor = BabyEvent(
            type: .activity,
            startDate: day.addingTimeInterval(120),
            endDate: day.addingTimeInterval(42 * 60 + 120)
        )
        outdoor.activityType = .outdoorPlay

        let snapshot = InsightsAnalyticsService.snapshot(
            profileName: "Ethan",
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
        let profile = BabyProfile(name: "Ethan", birthDate: birthDate, sex: .male)
        let event = BabyEvent(
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
        let profile = BabyProfile(name: "Ethan", birthDate: birthDate)

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
        XCTAssertEqual(summaries.last?.title, "Ethan is 100 days old!")
    }

    func testAutomaticMilestoneSummaryAggregatesCareGrowthAndActivities() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let birthDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))
        )
        let profile = BabyProfile(
            name: "Ethan",
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

        let sleepOne = BabyEvent(
            type: .sleep,
            startDate: try date(day: 5, hour: 9),
            endDate: try date(day: 5, hour: 10)
        )
        let sleepTwo = BabyEvent(
            type: .sleep,
            startDate: try date(day: 6, hour: 20),
            endDate: try date(day: 6, hour: 22)
        )
        let draftSleep = BabyEvent(
            type: .sleep,
            startDate: try date(day: 7, hour: 9)
        )

        let nursingOne = BabyEvent(
            type: .nursing,
            startDate: try date(day: 10, hour: 10),
            endDate: try date(day: 10, hour: 10, minute: 20)
        )
        nursingOne.leftDurationSeconds = 20 * 60
        let nursingTwo = BabyEvent(
            type: .nursing,
            startDate: try date(day: 10, hour: 10, minute: 30),
            endDate: try date(day: 10, hour: 10, minute: 45)
        )
        nursingTwo.rightDurationSeconds = 15 * 60
        let nursingThree = BabyEvent(
            type: .nursing,
            startDate: try date(day: 11, hour: 10),
            endDate: try date(day: 11, hour: 10, minute: 10)
        )
        nursingThree.leftDurationSeconds = 10 * 60

        let pump = BabyEvent(
            type: .custom,
            title: "Pump",
            startDate: try date(day: 20, hour: 8),
            endDate: try date(day: 20, hour: 8, minute: 15)
        )
        let diaperOne = BabyEvent(type: .diaper, startDate: try date(day: 4))
        let diaperTwo = BabyEvent(type: .diaper, startDate: try date(day: 8))

        let growth = BabyEvent(type: .growth, startDate: try date(day: 90))
        growth.weightKilograms = 5

        let tummyOne = BabyEvent(
            type: .activity,
            startDate: try date(day: 30, hour: 9),
            endDate: try date(day: 30, hour: 9, minute: 10)
        )
        tummyOne.activityType = .tummyTime
        let tummyTwo = BabyEvent(
            type: .activity,
            startDate: try date(day: 31, hour: 9),
            endDate: try date(day: 31, hour: 9, minute: 10)
        )
        tummyTwo.activityType = .tummyTime
        let bath = BabyEvent(
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
                    sleepOne, sleepTwo, draftSleep,
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
    func testMilestonesRoundTripThroughJSONBackup() throws {
        let schema = Schema([
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let birthDate = Date(timeIntervalSince1970: 1_767_225_600)
        let milestoneDate = birthDate.addingTimeInterval(21 * 24 * 60 * 60)
        let photoID = UUID()

        context.insert(BabyProfile(name: "Ethan", birthDate: birthDate))
        context.insert(MilestoneEntry(
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
    }

    @MainActor
    func testAppointmentsRoundTripThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let birthDate = Date(timeIntervalSince1970: 1_767_225_600)
        let startDate = birthDate.addingTimeInterval(180 * 24 * 60 * 60 + 9 * 60 * 60)
        let growthID = UUID()
        let temperatureID = UUID()

        context.insert(BabyProfile(name: "Ethan", birthDate: birthDate))
        context.insert(DoctorAppointment(
            title: "6-month wellness check",
            appointmentType: .wellnessCheck,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(30 * 60),
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

    @MainActor
    func testMonthlyAgeGuideServiceFindsCurrentGuideAndPrompts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let birthDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31))!
        let profile = BabyProfile(name: "Ethan", birthDate: birthDate)
        let service = AgeGuideService(calendar: calendar)

        let guide = try XCTUnwrap(service.currentAgeGuide(for: profile, now: now))

        XCTAssertEqual(guide.ageMonth, 4)
        XCTAssertFalse(guide.milestonePrompts.isEmpty)
        XCTAssertTrue(guide.sourceReferences.contains { $0.sourceName.contains("CDC") })
        XCTAssertEqual(service.allAgeGuides().map(\.ageMonth), Array(2...12))
        XCTAssertTrue(try XCTUnwrap(service.ageGuide(for: 9)).isCheckpointAge)
        XCTAssertTrue(try XCTUnwrap(service.ageGuide(for: 12)).isCheckpointAge)
    }

    @MainActor
    func testAgeGuideReadStateRoundTripsThroughJSONBackup() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let openedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let notifiedAt = openedAt.addingTimeInterval(-60 * 60)

        context.insert(BabyProfile(name: "Ethan", birthDate: SampleData.defaultBirthDate))
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

    private func wavSamples(for sound: NightLightSound) throws -> [Double] {
        let data = NightLightAudioService.generatedWAVData(for: sound)
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

    private func rmsWindows(_ samples: [Double], windowSize: Int) -> [Double] {
        stride(from: 0, to: samples.count - windowSize, by: windowSize).map { start in
            rms(Array(samples[start..<start + windowSize]))
        }
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
