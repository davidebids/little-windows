import Combine
import CoreLocation
import Foundation
import WeatherKit
import SwiftData
import WidgetKit

protocol DailyWeatherClient: Sendable {
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot
    func fetch(latitude: Double, longitude: Double, onUpdate: @escaping @Sendable (DailyWeatherSnapshot) async -> Void) async throws -> DailyWeatherSnapshot
    func refreshMinutes(in snapshot: DailyWeatherSnapshot, latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot
}
extension DailyWeatherClient {
    func fetch(latitude: Double, longitude: Double, onUpdate: @escaping @Sendable (DailyWeatherSnapshot) async -> Void) async throws -> DailyWeatherSnapshot {
        try await fetch(latitude: latitude, longitude: longitude)
    }
    func refreshMinutes(in snapshot: DailyWeatherSnapshot, latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot {
        try await fetch(latitude: latitude, longitude: longitude)
    }
}

struct LiveDailyWeatherClient: DailyWeatherClient {
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot {
        try await WeatherForecastClient.fetch(latitude: latitude, longitude: longitude)
    }
    func fetch(latitude: Double, longitude: Double, onUpdate: @escaping @Sendable (DailyWeatherSnapshot) async -> Void) async throws -> DailyWeatherSnapshot {
        try await WeatherForecastClient.fetch(latitude: latitude, longitude: longitude, onUpdate: onUpdate)
    }
    func refreshMinutes(in snapshot: DailyWeatherSnapshot, latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot {
        await WeatherForecastClient.refreshMinutes(in: snapshot, latitude: latitude, longitude: longitude)
    }
}

/// A chosen city is saved locally. Current-location coordinates stay in memory.
@MainActor
final class DailyWeatherStore: ObservableObject {
    static let shared = DailyWeatherStore()
    static let locationKey = "todayWeatherLocation"
    static let currentLocationKey = "todayWeatherUsesCurrentLocation"
    @Published private(set) var location: TripDestinationSelection?
    @Published private(set) var usesCurrentLocation: Bool
    @Published private(set) var snapshot: DailyWeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var failure: TripWeatherFailure?
    @Published private(set) var locationFailure: WeatherLocationFailure?
    @Published var temperatureUnit: TemperatureUnit {
        didSet {
            guard temperatureUnit != oldValue else { return }
            InteractionPerformanceAudit.begin("units.edit")
            defaults.set(temperatureUnit.rawValue, forKey: OutdoorTemperatureSettings.unitKey); publishSurface()
        }
    }
    @Published var windUnit: String {
        didSet { defaults.set(windUnit, forKey: "weather.windUnit"); publishSurface() }
    }
    @Published var precipitationUnit: String {
        didSet { defaults.set(precipitationUnit, forKey: "weather.precipitationUnit"); publishSurface() }
    }
    @Published private(set) var outdoorProfiles: [OutdoorProfileContext] = []

    typealias ContextCapture = @Sendable (ModelContainer, Date, TimeZone, Bool, UserDefaults) -> [OutdoorProfileContext]
    private let captureContext: ContextCapture
    private var contextRequest: ContextRequest?
    private var contextGeneration: UInt64 = 0
    private var capturedContextGeneration: UInt64?
    private var lastContextCapture: Date?
    private var contextPolicies: [UUID: String] = [:]
    private static let surfaceQueue = DispatchQueue(label: "LittleWindows.weather-surface", qos: .utility)
    private var surfaceWrite: WeatherSurfaceWriteRequest?
    private struct ContextRequest {
        let container: ModelContainer
        let now: Date
        let zone: TimeZone
        let includeSchedule: Bool
        var key: String { "\(ObjectIdentifier(container))-\(zone.identifier)-\(includeSchedule)" }
    }
    private var subscriptions = Set<AnyCancellable>()
    private var installedContainer: ModelContainer?
    private var consecutiveFailures = 0
    private var nextAutomaticAttempt: Date = .distantPast

    func install(container: ModelContainer) {
        installedContainer = container
        subscriptions.removeAll()
        // The preference store posts this notification on MainActor. Apply an
        // edit synchronously once, so controls need no duplicate refresh/read.
        NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)
            .sink { [weak self] notification in
                guard let self, let container = self.installedContainer else { return }
                let policyChanged = self.refreshProfilePreferences(profileID: notification.object as? UUID)
                self.updateContext(container.mainContext, force: policyChanged)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: SystemIntegrationReconciler.reconciliationRequestedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let container = self.installedContainer else { return }
                self.updateContext(container.mainContext, force: true)
            }.store(in: &subscriptions)
        ProfileService.shared.$selectedProfileID.dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.publishSurface() }
            }.store(in: &subscriptions)
        updateContext(container.mainContext, force: true)
    }

    /// Comfort edits reuse the captured schedule. Tracking resumes invalidate it.
    @discardableResult
    func refreshProfilePreferences(invalidateContext: Bool = true, profileID: UUID? = nil) -> Bool {
        let ids = Set(outdoorProfiles.map(\.id))
        var policies = contextPolicies.filter { ids.contains($0.key) }
        let profiles = outdoorProfiles.map { profile in
            if let profileID, profile.id != profileID { return profile }
            var updated = profile
            let stored = CareTrackingPreferenceStore.preferences(profileID: profile.id, defaults: defaults)
            updated.preferences = stored.outdoorPreferences(type: profile.type)
            if stored.fields["outdoor.activity"] == nil { updated.preferences.activity = profile.activities.first ?? "Outdoor time" }
            let sleep = stored.allowsPrompts(.sleepPlan), walk = stored.allows(.walk)
            policies[profile.id] = "\(updated.preferences.enabled)-\(sleep)-\(walk)"
            if !sleep { updated.predictedSleep = [] }
            if !walk { updated.lastWalk = nil }
            return updated
        }
        let changed = !contextPolicies.isEmpty && policies != contextPolicies
        contextPolicies = policies
        if changed && invalidateContext { contextGeneration &+= 1 }
        if outdoorProfiles != profiles { outdoorProfiles = profiles }
        publishSurface()
        return changed
    }

    private var contextTask: Task<Void, Never>?
    func updateContext(_ context: ModelContext, force: Bool = false, now: Date = Date()) {
        // Headers can appear during bootstrap. The shared store starts history
        // reads only after installation has supplied the finalized container.
        guard defaults !== UserDefaults.standard || installedContainer != nil else { return }
        let request = ContextRequest(container: context.container, now: now, zone: timeZone, includeSchedule: isConfigured)
        if force || request.key != contextRequest?.key { contextGeneration &+= 1 }
        contextRequest = request
        // A single reader starts immediately and coalesces requests during an active read.
        guard contextTask == nil else { return }
        if capturedContextGeneration == contextGeneration, let lastContextCapture,
           now >= lastContextCapture, now.timeIntervalSince(lastContextCapture) < 300 { return }
        contextTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let request = contextRequest else { break }
                let generation = contextGeneration
                let capture = captureContext, preferenceDefaults = defaults
                var profiles = await Task.detached(priority: .utility) {
                    capture(request.container, request.now, request.zone, request.includeSchedule, preferenceDefaults)
                }.value
                guard generation == contextGeneration else { continue }
                #if DEBUG
                if WeatherPreviewData.enabled && profiles.isEmpty { profiles = WeatherPreviewData.make().profiles }
                #endif
                if outdoorProfiles != profiles { outdoorProfiles = profiles }
                lastContextCapture = request.now
                capturedContextGeneration = generation
                // Read the latest preferences after the background work, so a
                // comfort edit made during that read cannot be overwritten.
                refreshProfilePreferences(invalidateContext: false)
                break
            }
            contextTask = nil
        }
    }
    var surface: WeatherSurfaceState? {
        guard let snapshot, let location else { return nil }
        return WeatherSurfaceState(city: location.name, timeZoneIdentifier: timeZone.identifier,
            fahrenheit: temperatureUnit == .fahrenheit, windUnit: windUnit, precipitationUnit: precipitationUnit,
            forecast: snapshot, selectedProfileID: ProfileService.shared.selectedProfileID, profiles: outdoorProfiles,
            manualLatitude: usesCurrentLocation ? nil : location.latitude,
            manualLongitude: usesCurrentLocation ? nil : location.longitude)
    }
    private func publishSurface() {
        guard defaults === UserDefaults.standard else { return }
        let current = surface
        guard current != lastPublishedSurface else { return }
        lastPublishedSurface = current
        surfaceWrite?.cancel()
        let write = WeatherSurfaceWriteRequest()
        surfaceWrite = write
        Self.surfaceQueue.async { [weak self] in
            guard !write.isCancelled else { return }
            WeatherSurfaceCache.write(current)
            WatchConnectivityService.shared.publishWeather(current)
            Task { @MainActor [weak self] in
                guard let self, self.lastPublishedSurface == current else { return }
                let widgetChanged = current.map { !$0.hasSameWidgetContent(as: self.lastWidgetSurface) } ?? (self.lastWidgetSurface != nil)
                if widgetChanged {
                    self.lastWidgetSurface = current
                    WidgetCenter.shared.reloadTimelines(ofKind: "LittleWindows.Weather")
                }
            }
        }
    }
    private let defaults: UserDefaults
    private let client: any DailyWeatherClient
    private let locationClient: any WeatherLocationClient
    private var revision = UUID()
    private var refreshTask: Task<Void, Never>?
    private var lastPublishedSurface: WeatherSurfaceState?
    private var lastWidgetSurface: WeatherSurfaceState?

    init(
        defaults: UserDefaults = .standard,
        client: any DailyWeatherClient = LiveDailyWeatherClient(),
        locationClient: (any WeatherLocationClient)? = nil,
        captureContext: @escaping ContextCapture = { container, now, zone, includeSchedule, defaults in
            OutdoorContextService.capture(context: ModelContext(container), now: now, timeZone: zone, includeSchedule: includeSchedule, defaults: defaults)
        }
    ) {
        self.defaults = defaults
        self.captureContext = captureContext
        #if DEBUG
        self.client = WeatherPreviewData.slowDetailsEnabled ? SlowDetailsPreviewClient() : client
        #else
        self.client = client
        #endif
        self.locationClient = locationClient ?? LiveWeatherLocationClient()
        temperatureUnit = OutdoorTemperatureSettings.preferredUnit(defaults: defaults)
        let defaultWind = Locale.current.measurementSystem == .us ? "mph" : "km/h"
        let defaultPrecipitation = Locale.current.measurementSystem == .us ? "in" : "mm"
        let savedWind = defaults.string(forKey: "weather.windUnit") ?? defaultWind
        let savedPrecipitation = defaults.string(forKey: "weather.precipitationUnit") ?? defaultPrecipitation
        windUnit = ["mph", "km/h"].contains(savedWind) ? savedWind : defaultWind
        precipitationUnit = ["in", "mm"].contains(savedPrecipitation) ? savedPrecipitation : defaultPrecipitation
        usesCurrentLocation = defaults.bool(forKey: Self.currentLocationKey)
        if !usesCurrentLocation {
            location = defaults.data(forKey: Self.locationKey).flatMap {
                try? JSONDecoder().decode(TripDestinationSelection.self, from: $0)
            }
        }
        let cached = defaults === UserDefaults.standard ? WeatherSurfaceCache.read() : nil
        lastPublishedSurface = cached
        lastWidgetSurface = cached
        if isConfigured, let cached,
           usesCurrentLocation || (cached.city == location?.name && cached.manualLatitude == location?.latitude && cached.manualLongitude == location?.longitude) {
            snapshot = cached.forecast
            outdoorProfiles = cached.profiles
            if usesCurrentLocation {
                location = TripDestinationSelection(name: cached.city, timeZoneIdentifier: cached.timeZoneIdentifier)
            }
        }
        #if DEBUG
        if WeatherPreviewData.enabled {
            let preview = WeatherPreviewData.make()
            location = TripDestinationSelection(name: preview.city, latitude: 0, longitude: 0, timeZoneIdentifier: preview.timeZoneIdentifier)
            snapshot = preview.forecast
            outdoorProfiles = preview.profiles
            usesCurrentLocation = false
        } else if WeatherPreviewData.slowDetailsEnabled {
            let preview = WeatherPreviewData.make()
            location = TripDestinationSelection(name: preview.city, latitude: 0, longitude: 0, timeZoneIdentifier: preview.timeZoneIdentifier)
            snapshot = nil
            usesCurrentLocation = false
        }
        #endif
    }

    var isConfigured: Bool { usesCurrentLocation || location != nil }
    var requestID: String { "\(usesCurrentLocation)-\(location?.id ?? "none")" }
    var timeZone: TimeZone {
        location?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    func select(_ location: TripDestinationSelection?) {
        resetRequest()
        usesCurrentLocation = false
        defaults.set(false, forKey: Self.currentLocationKey)
        self.location = location
        saveManualCity()
    }

    func useCurrentLocation() async {
        resetRequest()
        usesCurrentLocation = true
        defaults.set(true, forKey: Self.currentLocationKey)
        defaults.removeObject(forKey: Self.locationKey)
        location = nil
        await refresh(force: true, requestAuthorization: true)
    }

    func refresh(force: Bool = false, now: Date = Date(), requestAuthorization: Bool = false, minuteSensitive: Bool = false, resolveCurrentLocation: Bool = true) async {
        #if DEBUG
        if WeatherPreviewData.enabled { return }
        #endif
        guard isConfigured else { return }
        if usesCurrentLocation && !resolveCurrentLocation && location?.supportsWeather != true { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        if !force {
            guard now >= nextAutomaticAttempt else { return }
            if let snapshot, snapshot.detailedForecastPending != true, snapshot.isFresh(at: now),
               !minuteSensitive || !snapshot.needsMinuteRefresh(at: now) { return }
        }
        let request = revision
        isLoading = true
        let task = Task { @MainActor in
            if !force, defaults === UserDefaults.standard {
                let cached = await Task.detached(priority: .utility) { WeatherSurfaceCache.read() }.value
                guard request == revision else { return }
                if let cached, cached.city == location?.name, cached.timeZoneIdentifier == timeZone.identifier,
                   usesCurrentLocation || (cached.manualLatitude == location?.latitude && cached.manualLongitude == location?.longitude),
                   cached.forecast.fetchedAt > (snapshot?.fetchedAt ?? .distantPast) { snapshot = cached.forecast }
                if let snapshot, snapshot.detailedForecastPending != true, snapshot.isFresh(at: now), !minuteSensitive || !snapshot.needsMinuteRefresh(at: now) { return }
            }
            await self.load(request: request, requestAuthorization: requestAuthorization, resolveCurrentLocation: resolveCurrentLocation,
                            minuteOnlyIfFresh: minuteSensitive && !force, now: now)
        }
        refreshTask = task
        await task.value
        if request == revision {
            refreshTask = nil
            isLoading = false
        }
    }

    func cachedSleepConditions(for date: Date, preserving existing: SleepConditions?) -> SleepConditions? {
        guard let snapshot, let location,
              snapshot.isFresh(at: Date()) else { return existing }
        return SleepWeatherAutofill.merging(existing, date: date, snapshot: snapshot, location: location)
    }

    func sleepConditions(for date: Date, preserving existing: SleepConditions?) async -> SleepConditions? {
        guard SleepWeatherAutofill.needsTemperatures(existing) else { return existing }
        await refresh()
        return cachedSleepConditions(for: date, preserving: existing)
    }

    private func load(request: UUID, requestAuthorization: Bool, resolveCurrentLocation: Bool, minuteOnlyIfFresh: Bool, now: Date) async {
        do {
            var requestedLocation = location
            let minuteOnly = minuteOnlyIfFresh && location?.supportsWeather == true && snapshot?.isFresh(at: now) == true
                && snapshot?.needsMinuteRefresh(at: now) == true && snapshot?.detailedForecastPending != true
            if usesCurrentLocation && resolveCurrentLocation && !minuteOnly {
                requestedLocation = try await locationClient.currentPosition(requestAuthorization: requestAuthorization)
                if let requestedLocation { resolveCurrentCityName(requestedLocation, request: request) }
            } else if let selected = location, WeatherCityNaming.isPostalCode(selected.name) {
                requestedLocation = (try? await locationClient.resolveCity(selected)) ?? selected
            }
            try Task.checkCancellation()
            guard request == revision, let chosen = requestedLocation,
                  let latitude = chosen.latitude, let longitude = chosen.longitude else { return }
            // Keep cached conditions attached to their original city until the
            // replacement forecast succeeds. A failed location move must not relabel them.
            if snapshot == nil { location = chosen }
            locationFailure = nil
            let value: DailyWeatherSnapshot
            if minuteOnly, let snapshot, location?.id == chosen.id {
                value = try await client.refreshMinutes(in: snapshot, latitude: latitude, longitude: longitude)
            } else {
                value = try await client.fetch(latitude: latitude, longitude: longitude) { [weak self] update in
                    await self?.receiveForecast(update, location: chosen, request: request, now: now)
                }
            }
            try Task.checkCancellation()
            guard request == revision else { return }
            receiveForecast(value, location: chosen, request: request, now: now)
        } catch is CancellationError {
            return
        } catch let error as WeatherLocationFailure {
            guard request == revision else { return }
            locationFailure = error
            deferAutomaticRetry()
        } catch {
            guard request == revision else { return }
            failure = TripWeatherService.failureReason(for: error)
            deferAutomaticRetry()
        }
    }

    private var cityNameTask: Task<Void, Never>?
    private var resolvedCurrentCity: TripDestinationSelection?
    private var cityNameRequest = UUID()

    private func resolveCurrentCityName(_ position: TripDestinationSelection, request: UUID) {
        guard position.name == "Current location" else { return }
        cityNameTask?.cancel()
        cityNameRequest = UUID()
        let nameRequest = cityNameRequest
        resolvedCurrentCity = nil
        cityNameTask = Task { @MainActor in
            guard let resolved = try? await locationClient.resolveCity(position), !Task.isCancelled,
                  request == revision, nameRequest == cityNameRequest else { return }
            resolvedCurrentCity = resolved
            if location?.id == position.id {
                location = resolved
                if let installedContainer { updateContext(installedContainer.mainContext) }
                publishSurface()
            }
        }
    }

    private func receiveForecast(_ value: DailyWeatherSnapshot, location chosen: TripDestinationSelection, request: UUID, now: Date) {
        guard request == revision else { return }
        // Keep a complete, still-valid cached forecast while a refresh's early
        // current-only phase is in flight. A cold launch can show that phase now.
        if value.detailedForecastPending == true, location?.id == chosen.id, let snapshot,
           snapshot.detailedForecastPending != true, snapshot.isFresh(at: now) { return }
        location = usesCurrentLocation && resolvedCurrentCity?.id == chosen.id ? resolvedCurrentCity : chosen
        if !usesCurrentLocation { saveManualCity() }
        snapshot = value
        failure = nil
        if value.detailedForecastPending != true {
            consecutiveFailures = 0
            nextAutomaticAttempt = .distantPast
        }
        if let installedContainer { updateContext(installedContainer.mainContext) }
        publishSurface()
    }

    private func deferAutomaticRetry() {
        consecutiveFailures = min(consecutiveFailures + 1, 4)
        nextAutomaticAttempt = Date().addingTimeInterval(60 * pow(2, Double(consecutiveFailures - 1)))
    }

    private func saveManualCity() {
        if let location, let data = try? JSONEncoder().encode(location) {
            defaults.set(data, forKey: Self.locationKey)
        } else {
            defaults.removeObject(forKey: Self.locationKey)
        }
    }

    private func resetRequest() {
        cityNameTask?.cancel()
        cityNameTask = nil
        resolvedCurrentCity = nil
        cityNameRequest = UUID()
        revision = UUID()
        nextAutomaticAttempt = .distantPast
        consecutiveFailures = 0
        refreshTask?.cancel()
        refreshTask = nil
        snapshot = nil
        failure = nil
        locationFailure = nil
        isLoading = false
        publishSurface()
    }
}

enum SleepWeatherAutofill {
    static func preservingCapturedWeather(
        from stored: SleepConditions?, in incoming: SleepConditions?, for date: Date? = nil
    ) -> SleepConditions? {
        guard needsTemperatures(incoming), let stored,
              stored.outdoorHighCelsius != nil || stored.outdoorLowCelsius != nil else { return incoming }
        if let date, let weatherDate = stored.weatherDate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = stored.weatherTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            guard calendar.isDate(weatherDate, inSameDayAs: date) else { return incoming }
        }
        var value = incoming ?? SleepConditions()
        value.outdoorHighCelsius = stored.outdoorHighCelsius
        value.outdoorLowCelsius = stored.outdoorLowCelsius
        value.weatherDate = stored.weatherDate
        value.weatherTimeZoneIdentifier = stored.weatherTimeZoneIdentifier
        value.weatherLocationName = stored.weatherLocationName
        value.forecastFetchedAt = stored.forecastFetchedAt
        value.automaticallyUsesWeather = true
        return value
    }

    static func needsTemperatures(_ existing: SleepConditions?) -> Bool {
        existing?.automaticallyUsesWeather != false
            && existing?.outdoorHighCelsius == nil && existing?.outdoorLowCelsius == nil
    }

    static func merging(
        _ existing: SleepConditions?, date: Date,
        snapshot: DailyWeatherSnapshot, location: TripDestinationSelection
    ) -> SleepConditions? {
        guard needsTemperatures(existing) else { return existing }
        let timeZone = location.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        guard let day = snapshot.day(for: date, timeZone: timeZone) else { return existing }
        var value = existing ?? SleepConditions()
        value.outdoorHighCelsius = day.highTemperatureCelsius
        value.outdoorLowCelsius = day.lowTemperatureCelsius
        value.weatherDate = day.date
        value.weatherTimeZoneIdentifier = timeZone.identifier
        value.weatherLocationName = location.name
        value.forecastFetchedAt = snapshot.fetchedAt
        value.automaticallyUsesWeather = true
        return value.isValid ? value : existing
    }
}

#if DEBUG
private struct SlowDetailsPreviewClient: DailyWeatherClient {
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot {
        WeatherPreviewData.make().forecast
    }
    func fetch(latitude: Double, longitude: Double, onUpdate: @escaping @Sendable (DailyWeatherSnapshot) async -> Void) async throws -> DailyWeatherSnapshot {
        let full = WeatherPreviewData.make().forecast
        var current = full
        current.hours = []; current.minutes = nil; current.detailedForecastPending = true
        await onUpdate(current)
        try await Task.sleep(for: .seconds(10))
        return full
    }
}
#endif

/// Cancels superseded writes that have not started. The serial queue preserves
/// ordering for a write already in progress, including clearing disabled weather.
private final class WeatherSurfaceWriteRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
