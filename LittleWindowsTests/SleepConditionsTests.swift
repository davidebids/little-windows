import SwiftData
import XCTest
@testable import LittleWindows

final class SleepConditionsTests: XCTestCase {
    func testOptionalFieldsAndExplicitNoSleepSackAreDistinct() {
        XCTAssertTrue(SleepConditions().isEmpty)
        XCTAssertFalse(SleepConditions(usedSleepSack: false).isEmpty)
        XCTAssertEqual(SleepConditions(usedSleepSack: false).summary, "No sleep sack")
        XCTAssertTrue(SleepConditions(usedSleepSack: true).isValid)
    }

    func testOutdoorRangesAllowFreezingAndRejectInvalidHighLowAndTOG() {
        XCTAssertTrue(SleepConditions(outdoorHighCelsius: 0, outdoorLowCelsius: -15).isValid)
        XCTAssertFalse(SleepConditions(outdoorHighCelsius: 5, outdoorLowCelsius: 10).isValid)
        XCTAssertFalse(SleepConditions(outdoorHighCelsius: .infinity).isValid)
        XCTAssertFalse(SleepConditions(outdoorLowCelsius: -101).isValid)
        XCTAssertFalse(SleepConditions(usedSleepSack: false, sleepSackTOG: 2.5).isValid)
        XCTAssertFalse(SleepConditions(usedSleepSack: true, sleepSackTOG: -1).isValid)
    }

    func testDraftConvertsUnitsWithoutChangingMeaning() throws {
        var draft = SleepConditionsDraft(SleepConditions(outdoorHighCelsius: 20, outdoorLowCelsius: -10), unit: .celsius)
        draft.changeUnit(to: .fahrenheit)
        XCTAssertEqual(try XCTUnwrap(SleepConditionsDraft.number(draft.highText)), 68, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(SleepConditionsDraft.number(draft.lowText)), 14, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(draft.details.outdoorLowCelsius), -10, accuracy: 0.01)
        draft.changeUnit(to: .celsius)
        XCTAssertEqual(try XCTUnwrap(draft.details.outdoorHighCelsius), 20, accuracy: 0.01)
    }

    func testWeatherUnitsDefaultToLocaleAndRespectSavedChoice() throws {
        let name = "WeatherUnitsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(OutdoorTemperatureSettings.preferredUnit(defaults: defaults, locale: Locale(identifier: "en_US")), .fahrenheit)
        XCTAssertEqual(OutdoorTemperatureSettings.preferredUnit(defaults: defaults, locale: Locale(identifier: "en_GB")), .celsius)
        defaults.set(TemperatureUnit.celsius.rawValue, forKey: OutdoorTemperatureSettings.unitKey)
        XCTAssertEqual(OutdoorTemperatureSettings.preferredUnit(defaults: defaults, locale: Locale(identifier: "en_US")), .celsius)
        defaults.set("invalid", forKey: OutdoorTemperatureSettings.unitKey)
        XCTAssertEqual(OutdoorTemperatureSettings.preferredUnit(defaults: defaults, locale: Locale(identifier: "en_US")), .fahrenheit)
    }

    @MainActor
    func testWeatherUnitChoicePersistsWithoutChangingForecastValues() async throws {
        let name = "WeatherUnitsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshot = makeSnapshot(days: [TripDailyWeather(date: Date(), lowTemperatureCelsius: -5, highTemperatureCelsius: 20, precipitationChance: 0, uvIndex: 1)])
        let client = StubDailyWeatherClient(snapshot: snapshot)
        let store = DailyWeatherStore(defaults: defaults, client: client)
        store.select(TripDestinationSelection(name: "Sample City", latitude: 1, longitude: 2))
        await store.refresh()
        store.temperatureUnit = .fahrenheit
        store.temperatureUnit = .celsius
        let restored = DailyWeatherStore(defaults: defaults, client: client)
        XCTAssertEqual(restored.temperatureUnit, .celsius)
        XCTAssertEqual(store.snapshot?.days.first?.lowTemperatureCelsius, -5)
        XCTAssertEqual(store.snapshot?.days.first?.highTemperatureCelsius, 20)
        XCTAssertEqual(store.snapshot?.fetchedAt, snapshot.fetchedAt)
        let requests = await client.requestCount()
        XCTAssertEqual(requests, 1, "Changing display units must not request another forecast.")
    }

    func testWeatherAndSleepSummariesConvertUnitsWithoutChangingRecord() {
        let conditions = SleepConditions(outdoorHighCelsius: 20, outdoorLowCelsius: -5, usedSleepSack: true, sleepSackTOG: 2.5)
        XCTAssertEqual(OutdoorTemperatureFormatting.string(0, unit: .fahrenheit), "32°F")
        XCTAssertEqual(OutdoorTemperatureFormatting.string(-5, unit: .celsius), "-5°C")
        XCTAssertTrue(conditions.formattedSummary(unit: .fahrenheit).contains("68°F"))
        XCTAssertTrue(conditions.formattedSummary(unit: .celsius).contains("20°C"))
        XCTAssertEqual(conditions.outdoorHighCelsius, 20)
        XCTAssertEqual(conditions.outdoorLowCelsius, -5)
        XCTAssertEqual(conditions.sleepSackTOG, 2.5)
    }

    func testDraftRejectsMalformedNumbersAndPreservesBlankUnknownFields() {
        var draft = SleepConditionsDraft(unit: .celsius)
        XCTAssertTrue(draft.details.isEmpty)
        draft.highText = "warm"
        XCTAssertNotNil(draft.validationMessage)
        draft.highText = "0"
        draft.lowText = "-5"
        XCTAssertNil(draft.validationMessage)
        XCTAssertEqual(draft.details.outdoorHighCelsius, 0)
        draft.sackUsage = .used
        draft.togText = "thick"
        XCTAssertNotNil(draft.validationMessage)
        draft.togText = ""
        XCTAssertNil(draft.validationMessage)
        XCTAssertNil(draft.details.sleepSackTOG)
    }

    func testChoosingNoSackClearsTOGAndRemovingTemperaturesClearsProvenance() {
        var draft = SleepConditionsDraft(sampleConditions, unit: .celsius)
        draft.sackUsage = .notUsed
        XCTAssertEqual(draft.details.usedSleepSack, false)
        XCTAssertNil(draft.details.sleepSackTOG)
        draft.highText = ""
        draft.lowText = ""
        XCTAssertNil(draft.details.weatherDate)
        XCTAssertNil(draft.details.weatherLocationName)
        XCTAssertNil(draft.details.forecastFetchedAt)
    }

    func testForecastUsesRequestedCalendarDateAcrossMidnightAndTimeZones() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -8 * 3600))
        let day = TripDailyWeather(date: Date(timeIntervalSince1970: 28_800), lowTemperatureCelsius: 5, highTemperatureCelsius: 18, precipitationChance: 0, uvIndex: 1)
        let snapshot = makeSnapshot(days: [day])
        XCTAssertNotNil(snapshot.day(for: Date(timeIntervalSince1970: 50_000), timeZone: timeZone))
        XCTAssertNil(snapshot.day(for: Date(timeIntervalSince1970: 28_799), timeZone: timeZone))
        XCTAssertNil(snapshot.day(for: Date(timeIntervalSince1970: 115_200), timeZone: timeZone))
    }

    @MainActor
    func testDetachedCopiesAndTimerPersistenceRetainSleepConditions() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        context.insert(profile)
        let event = CareEvent(profileID: profile.id, type: .sleep)
        event.profileTypeSnapshot = .child
        event.sleepKind = .nightSleep
        event.sleepConditions = sampleConditions
        context.insert(event)
        try context.save()
        let draft = EventMutationService.detachedTimerCopy(event)
        XCTAssertEqual(draft.sleepConditions, sampleConditions)
        var changedConditions = sampleConditions
        changedConditions.usedSleepSack = false
        changedConditions.sleepSackTOG = nil
        draft.sleepConditions = changedConditions
        XCTAssertEqual(event.sleepConditions, sampleConditions)
        let persisted = await EventMutationService.persistStandaloneEvent(draft, container: container)
        XCTAssertTrue(persisted)
        let verification = ModelContext(container)
        let saved = try XCTUnwrap(verification.fetch(FetchDescriptor<CareEvent>()).first)
        XCTAssertEqual(saved.profileID, profile.id)
        XCTAssertEqual(saved.sleepConditions, changedConditions)
    }

    @MainActor
    func testSleepConditionsRoundTripThroughBackupWithoutChangingBodyTemperature() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = CareProfile(name: "Test Child", birthDate: Date(), sex: .unknown)
        context.insert(profile)
        let event = CareEvent(profileID: profile.id, type: .sleep)
        event.profileTypeSnapshot = .child
        event.sleepKind = .nightSleep
        event.sleepConditions = sampleConditions
        context.insert(event)
        let bodyTemperature = CareEvent(profileID: profile.id, type: .temperature)
        bodyTemperature.temperatureCelsius = 37
        context.insert(bodyTemperature)
        try context.save()
        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(backup, context: context)
        let imported = try context.fetch(FetchDescriptor<CareEvent>())
        XCTAssertEqual(imported.first { $0.type == .sleep }?.sleepConditions, sampleConditions)
        XCTAssertEqual(imported.first { $0.type == .sleep }?.profileID, profile.id)
        XCTAssertEqual(imported.first { $0.type == .temperature }?.temperatureCelsius, 37)
    }

    @MainActor
    func testOldBackupsWithoutSleepConditionsStillImport() throws {
        let container = try makeContainer()
        let event = CareEvent(type: .sleep)
        container.mainContext.insert(event)
        try container.mainContext.save()
        let backup = try DataExportImportService.exportData(context: container.mainContext)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var events = try XCTUnwrap(json["events"] as? [[String: Any]])
        for i in events.indices { events[i].removeValue(forKey: "sleepConditionsData") }
        json["events"] = events
        let legacy = try JSONSerialization.data(withJSONObject: json)
        try DataExportImportService.importData(legacy, context: container.mainContext)
        XCTAssertNil(try container.mainContext.fetch(FetchDescriptor<CareEvent>()).first?.sleepConditions)
    }

    @MainActor
    func testMalformedSleepPayloadRejectedBeforeReplacingStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let event = CareEvent(type: .sleep)
        context.insert(event)
        try context.save()
        let backup = try DataExportImportService.exportData(context: context)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var events = try XCTUnwrap(json["events"] as? [[String: Any]])
        events[0]["sleepConditionsData"] = Data("invalid".utf8).base64EncodedString()
        json["events"] = events
        XCTAssertThrowsError(try DataExportImportService.importData(JSONSerialization.data(withJSONObject: json), context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareEvent>()).first?.id, event.id)
    }

    @MainActor
    func testWeatherCachesRefreshesAndRemovesLocation() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SleepConditionsTests-\(UUID().uuidString)"))
        let now = Date()
        var snapshot = makeSnapshot(days: [TripDailyWeather(date: now, lowTemperatureCelsius: 5, highTemperatureCelsius: 18, precipitationChance: 0, uvIndex: 1)])
        snapshot.fetchedAt = now
        let client = StubDailyWeatherClient(snapshot: snapshot)
        let store = DailyWeatherStore(defaults: defaults, client: client)
        store.select(TripDestinationSelection(name: "Sample City", latitude: 1, longitude: 2, timeZoneIdentifier: TimeZone.current.identifier))
        await store.refresh(now: now)
        await store.refresh(now: now)
        var count = await client.requestCount()
        XCTAssertEqual(count, 1)
        await store.refresh(force: true, now: now)
        count = await client.requestCount()
        XCTAssertEqual(count, 2)
        XCTAssertNotNil(store.snapshot)
        XCTAssertNotNil(defaults.data(forKey: DailyWeatherStore.locationKey))
        store.select(nil)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(defaults.data(forKey: DailyWeatherStore.locationKey))
    }

    func testAutofillPopulatesTemperaturesAndPreservesSleepSack() throws {
        let now = Date()
        let location = TripDestinationSelection(name: "Sample City", latitude: 1, longitude: 2, timeZoneIdentifier: TimeZone.current.identifier)
        let snapshot = makeSnapshot(days: [TripDailyWeather(date: now, lowTemperatureCelsius: 4, highTemperatureCelsius: 18, precipitationChance: 0, uvIndex: 1)])
        let result = try XCTUnwrap(SleepWeatherAutofill.merging(SleepConditions(usedSleepSack: true, sleepSackTOG: 2.5), date: now, snapshot: snapshot, location: location))
        XCTAssertEqual(result.outdoorHighCelsius, 18)
        XCTAssertEqual(result.outdoorLowCelsius, 4)
        XCTAssertEqual(result.sleepSackTOG, 2.5)
        XCTAssertEqual(result.weatherLocationName, "Sample City")
        XCTAssertEqual(result.automaticallyUsesWeather, true)
    }

    func testAutofillDoesNotReplaceRecordedWeatherOrManualOptOut() {
        let now = Date()
        let location = TripDestinationSelection(name: "Another City", latitude: 1, longitude: 2)
        let snapshot = makeSnapshot(days: [TripDailyWeather(date: now, lowTemperatureCelsius: 1, highTemperatureCelsius: 9, precipitationChance: 0, uvIndex: 1)])
        XCTAssertEqual(SleepWeatherAutofill.merging(sampleConditions, date: now, snapshot: snapshot, location: location), sampleConditions)
        let manual = SleepConditions(automaticallyUsesWeather: false)
        XCTAssertFalse(manual.isEmpty)
        XCTAssertEqual(SleepWeatherAutofill.merging(manual, date: now, snapshot: snapshot, location: location), manual)
        XCTAssertNil(SleepWeatherAutofill.merging(nil, date: now.addingTimeInterval(-3 * 86400), snapshot: snapshot, location: location))
    }

    func testNewDraftDateOrCityChangeClearsAutomaticWeatherAndKeepsSack() {
        var draft = SleepConditionsDraft(sampleConditions, unit: .celsius)
        draft.invalidateAutomaticWeather(for: Date(timeIntervalSince1970: 200_000), locationName: "Sample City")
        XCTAssertNil(draft.details.outdoorHighCelsius)
        XCTAssertEqual(draft.details.sleepSackTOG, 2.5)
        XCTAssertTrue(draft.usesAutomaticWeather)
        var cityDraft = SleepConditionsDraft(sampleConditions, unit: .celsius)
        cityDraft.invalidateAutomaticWeather(for: Date(timeIntervalSince1970: 1_000), locationName: "Another City")
        XCTAssertNil(cityDraft.details.outdoorLowCelsius)
        var manual = sampleConditions
        manual.automaticallyUsesWeather = false
        var manualDraft = SleepConditionsDraft(manual, unit: .celsius)
        manualDraft.invalidateAutomaticWeather(for: Date(), locationName: "Another City")
        XCTAssertEqual(manualDraft.details.outdoorHighCelsius, 19)
    }

    func testSavingMovedTimerCannotRestoreWeatherFromAnotherDay() {
        let stored = sampleConditions
        let incoming = SleepConditions(usedSleepSack: false)
        let sameDay = stored.weatherDate!
        let anotherDay = sameDay.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(
            SleepWeatherAutofill.preservingCapturedWeather(from: stored, in: incoming, for: anotherDay),
            incoming
        )
        let sameDayResult = SleepWeatherAutofill.preservingCapturedWeather(from: stored, in: incoming, for: sameDay)
        XCTAssertEqual(sameDayResult?.outdoorHighCelsius, stored.outdoorHighCelsius)
        XCTAssertEqual(sameDayResult?.usedSleepSack, false)
    }

    func testCityNamingUsesLocalityInsteadOfPostalResultTitle() {
        XCTAssertEqual(WeatherCityNaming.name(locality: "Sample City", district: "Sample County", region: "CA", fallback: "90000"), "Sample City")
        XCTAssertEqual(WeatherCityNaming.name(locality: nil, district: "Sample County", region: "CA", fallback: "90000-1234"), "Sample County")
        XCTAssertEqual(WeatherCityNaming.name(locality: nil, district: nil, region: nil, fallback: "90000"), "Selected city")
        XCTAssertTrue(WeatherCityNaming.isPostalCode(" 90000-1234 "))
        XCTAssertFalse(WeatherCityNaming.isPostalCode("Sample City"))
    }

    @MainActor
    func testSavedZIPLabelIsResolvedAndPersistedAsCity() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SleepWeatherZIP-\(UUID().uuidString)"))
        let place = StubWeatherLocationClient()
        let store = DailyWeatherStore(defaults: defaults, client: StubDailyWeatherClient(snapshot: makeSnapshot(days: [])), locationClient: place)
        store.select(TripDestinationSelection(name: "90000", latitude: 1, longitude: 2))
        await store.refresh()
        XCTAssertEqual(store.location?.name, "Sample City")
        let saved = try JSONDecoder().decode(TripDestinationSelection.self, from: XCTUnwrap(defaults.data(forKey: DailyWeatherStore.locationKey)))
        XCTAssertEqual(saved.name, "Sample City")
        defaults.removeObject(forKey: DailyWeatherStore.locationKey)
        defaults.removeObject(forKey: DailyWeatherStore.currentLocationKey)
    }

    @MainActor
    func testCurrentLocationIsOptInAndDoesNotPersistCoordinates() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SleepWeatherLocation-\(UUID().uuidString)"))
        let place = StubWeatherLocationClient()
        let store = DailyWeatherStore(defaults: defaults, client: StubDailyWeatherClient(snapshot: makeSnapshot(days: [])), locationClient: place)
        await store.refresh()
        XCTAssertTrue(place.authorizationRequests.isEmpty)
        await store.useCurrentLocation()
        XCTAssertEqual(place.authorizationRequests, [true])
        XCTAssertTrue(store.usesCurrentLocation)
        XCTAssertEqual(store.location?.name, "Sample City")
        XCTAssertNil(defaults.data(forKey: DailyWeatherStore.locationKey))
        await store.refresh(force: true)
        XCTAssertEqual(place.authorizationRequests, [true, false])
        store.select(TripDestinationSelection(name: "Manual City", latitude: 3, longitude: 4))
        XCTAssertFalse(store.usesCurrentLocation)
        store.select(nil)
        defaults.removeObject(forKey: DailyWeatherStore.currentLocationKey)
    }

    @MainActor
    func testDeniedLocationLeavesManualCityChoiceAvailable() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SleepWeatherDenied-\(UUID().uuidString)"))
        let place = StubWeatherLocationClient()
        place.failure = .denied
        let store = DailyWeatherStore(defaults: defaults, client: StubDailyWeatherClient(snapshot: makeSnapshot(days: [])), locationClient: place)
        await store.useCurrentLocation()
        XCTAssertEqual(store.locationFailure, .denied)
        XCTAssertFalse(store.isLoading)
        store.select(TripDestinationSelection(name: "Manual City", latitude: 3, longitude: 4))
        XCTAssertNil(store.locationFailure)
        XCTAssertFalse(store.usesCurrentLocation)
        XCTAssertEqual(store.location?.name, "Manual City")
        store.select(nil)
        defaults.removeObject(forKey: DailyWeatherStore.currentLocationKey)
    }

    @MainActor
    func testLateWeatherMergeKeepsLatestSackAndSurvivesStaleTimerSnapshot() async throws {
        let container = try makeContainer()
        let event = CareEvent(profileID: UUID(), type: .sleep)
        event.sleepKind = .nightSleep
        event.sleepConditions = SleepConditions(usedSleepSack: false)
        let first = EventMutationService.timerPersistenceRequest(for: event)
        let persisted = await EventMutationService.persistTimerMutation(first, container: container)
        XCTAssertTrue(persisted)
        let stale = EventMutationService.timerPersistenceRequest(for: event)
        var conditions = sampleConditions
        conditions.weatherDate = event.startDate
        await EventMutationService.fillSleepWeather(eventID: event.id, profileID: event.profileID, startDate: event.startDate, conditions: conditions, container: container)
        let staleSaved = await EventMutationService.persistTimerMutation(stale, container: container)
        XCTAssertTrue(staleSaved)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<CareEvent>()).first)
        XCTAssertEqual(saved.sleepConditions?.outdoorHighCelsius, 19)
        XCTAssertEqual(saved.sleepConditions?.usedSleepSack, false)
        XCTAssertNil(saved.sleepConditions?.sleepSackTOG)
    }

    @MainActor
    func testLateWeatherCannotModifyMovedManualOrDeletedSleep() async throws {
        let container = try makeContainer()
        let event = CareEvent(profileID: UUID(), type: .sleep)
        event.sleepKind = .nightSleep
        event.sleepConditions = SleepConditions(usedSleepSack: false, automaticallyUsesWeather: false)
        let first = EventMutationService.timerPersistenceRequest(for: event)
        _ = await EventMutationService.persistTimerMutation(first, container: container)
        await EventMutationService.fillSleepWeather(eventID: event.id, profileID: event.profileID, startDate: event.startDate, conditions: sampleConditions, container: container)
        var saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<CareEvent>()).first)
        XCTAssertNil(saved.sleepConditions?.outdoorHighCelsius)
        event.sleepConditions = nil
        _ = await EventMutationService.persistTimerMutation(EventMutationService.timerPersistenceRequest(for: event), container: container)
        await EventMutationService.fillSleepWeather(eventID: event.id, profileID: UUID(), startDate: event.startDate, conditions: sampleConditions, container: container)
        await EventMutationService.fillSleepWeather(eventID: event.id, profileID: event.profileID, startDate: event.startDate.addingTimeInterval(-3600), conditions: sampleConditions, container: container)
        saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<CareEvent>()).first)
        XCTAssertNil(saved.sleepConditions)
        _ = await EventMutationService.persistTimerMutation(EventMutationService.timerPersistenceRequest(for: event, deleting: true), container: container)
        await EventMutationService.fillSleepWeather(eventID: event.id, profileID: event.profileID, startDate: event.startDate, conditions: sampleConditions, container: container)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<CareEvent>()).isEmpty)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = PersistenceService.schema
        let config = ModelConfiguration("SleepConditionsTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private var sampleConditions: SleepConditions {
        SleepConditions(outdoorHighCelsius: 19, outdoorLowCelsius: 6, weatherDate: Date(timeIntervalSince1970: 1_000), weatherTimeZoneIdentifier: "UTC", weatherLocationName: "Sample City", forecastFetchedAt: Date(timeIntervalSince1970: 900), usedSleepSack: true, sleepSackTOG: 2.5)
    }

    private func makeSnapshot(days: [TripDailyWeather]) -> DailyWeatherSnapshot {
        DailyWeatherSnapshot(fetchedAt: Date(), currentTemperatureCelsius: 12, symbolName: "sun.max.fill", days: days, attribution: TripWeatherAttribution(legalPageURL: URL(string: "https://example.com/legal")!, lightMarkURL: URL(string: "https://example.com/light")!, darkMarkURL: URL(string: "https://example.com/dark")!))
    }
}

private actor StubDailyWeatherClient: DailyWeatherClient {
    let snapshot: DailyWeatherSnapshot
    private var requests = 0
    init(snapshot: DailyWeatherSnapshot) { self.snapshot = snapshot }
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot {
        requests += 1
        return snapshot
    }
    func requestCount() -> Int { requests }
}

@MainActor
private final class StubWeatherLocationClient: WeatherLocationClient {
    var authorizationRequests = [Bool]()
    var failure: WeatherLocationFailure?
    func currentCity(requestAuthorization: Bool) async throws -> TripDestinationSelection {
        authorizationRequests.append(requestAuthorization)
        if let failure { throw failure }
        return TripDestinationSelection(name: "Sample City", latitude: 1, longitude: 2, timeZoneIdentifier: TimeZone.current.identifier)
    }
    func resolveCity(_ location: TripDestinationSelection) async throws -> TripDestinationSelection {
        var result = location
        result.name = "Sample City"
        return result
    }
}
