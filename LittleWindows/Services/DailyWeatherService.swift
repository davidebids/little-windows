import Combine
import CoreLocation
import Foundation
import WeatherKit

struct DailyWeatherSnapshot: Sendable {
    var fetchedAt: Date
    var currentTemperatureCelsius: Double
    var symbolName: String
    var days: [TripDailyWeather]
    var attribution: TripWeatherAttribution

    func day(for date: Date, timeZone: TimeZone) -> TripDailyWeather? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

protocol DailyWeatherClient: Sendable {
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot
}

struct LiveDailyWeatherClient: DailyWeatherClient {
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        async let weather = WeatherService.shared.weather(for: location, including: .current, .daily)
        async let attribution = LiveTripWeatherForecastClient().attribution()
        let ((current, daily), legal) = try await (weather, attribution)
        return DailyWeatherSnapshot(
            fetchedAt: Date(),
            currentTemperatureCelsius: current.temperature.converted(to: .celsius).value,
            symbolName: current.symbolName,
            days: daily.forecast.map {
                TripDailyWeather(
                    date: $0.date,
                    lowTemperatureCelsius: $0.lowTemperature.converted(to: .celsius).value,
                    highTemperatureCelsius: $0.highTemperature.converted(to: .celsius).value,
                    precipitationChance: $0.precipitationChance,
                    uvIndex: $0.uvIndex.value,
                    symbolName: $0.symbolName
                )
            },
            attribution: legal
        )
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
        didSet { defaults.set(temperatureUnit.rawValue, forKey: OutdoorTemperatureSettings.unitKey) }
    }
    private let defaults: UserDefaults
    private let client: any DailyWeatherClient
    private let locationClient: any WeatherLocationClient
    private var revision = UUID()
    private var refreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        client: any DailyWeatherClient = LiveDailyWeatherClient(),
        locationClient: (any WeatherLocationClient)? = nil
    ) {
        self.defaults = defaults
        self.client = client
        self.locationClient = locationClient ?? LiveWeatherLocationClient()
        temperatureUnit = OutdoorTemperatureSettings.preferredUnit(defaults: defaults)
        usesCurrentLocation = defaults.bool(forKey: Self.currentLocationKey)
        if !usesCurrentLocation {
            location = defaults.data(forKey: Self.locationKey).flatMap {
                try? JSONDecoder().decode(TripDestinationSelection.self, from: $0)
            }
        }
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

    func refresh(force: Bool = false, now: Date = Date(), requestAuthorization: Bool = false) async {
        guard isConfigured else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        if !force, let snapshot, now.timeIntervalSince(snapshot.fetchedAt) >= 0,
           now.timeIntervalSince(snapshot.fetchedAt) < 30 * 60,
           snapshot.day(for: now, timeZone: timeZone) != nil { return }
        let request = revision
        isLoading = true
        let task = Task { @MainActor in
            await self.load(request: request, requestAuthorization: requestAuthorization)
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
              Date().timeIntervalSince(snapshot.fetchedAt) < 30 * 60 else { return existing }
        return SleepWeatherAutofill.merging(existing, date: date, snapshot: snapshot, location: location)
    }

    func sleepConditions(for date: Date, preserving existing: SleepConditions?) async -> SleepConditions? {
        guard SleepWeatherAutofill.needsTemperatures(existing) else { return existing }
        await refresh()
        return cachedSleepConditions(for: date, preserving: existing)
    }

    private func load(request: UUID, requestAuthorization: Bool) async {
        do {
            if usesCurrentLocation {
                let city = try await locationClient.currentCity(requestAuthorization: requestAuthorization)
                try Task.checkCancellation()
                guard request == revision else { return }
                location = city
            } else if let selected = location, WeatherCityNaming.isPostalCode(selected.name) {
                if let resolved = try? await locationClient.resolveCity(selected) {
                    try Task.checkCancellation()
                    guard request == revision else { return }
                    location = resolved
                    saveManualCity()
                }
            }
            guard let latitude = location?.latitude, let longitude = location?.longitude else { return }
            locationFailure = nil
            let value = try await client.fetch(latitude: latitude, longitude: longitude)
            try Task.checkCancellation()
            guard request == revision else { return }
            snapshot = value
            failure = nil
        } catch is CancellationError {
            return
        } catch let error as WeatherLocationFailure {
            guard request == revision else { return }
            locationFailure = error
        } catch {
            guard request == revision else { return }
            failure = TripWeatherService.failureReason(for: error)
        }
    }

    private func saveManualCity() {
        if let location, let data = try? JSONEncoder().encode(location) {
            defaults.set(data, forKey: Self.locationKey)
        } else {
            defaults.removeObject(forKey: Self.locationKey)
        }
    }

    private func resetRequest() {
        revision = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        snapshot = nil
        failure = nil
        locationFailure = nil
        isLoading = false
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
