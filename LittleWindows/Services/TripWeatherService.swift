import CoreLocation
import Foundation
import MapKit
import WeatherKit

struct TripWeatherSnapshot: Equatable, Sendable {
    var summary: String
    var forecastDayCount: Int
    var tripDayCount: Int
    var lowTemperatureCelsius: Double
    var highTemperatureCelsius: Double
    var rainLikely: Bool
    var coldWeather: Bool
    var hotOrHighUV: Bool
    var dailyForecast: [TripDailyWeather]
    var legalPageURL: URL
    var lightMarkURL: URL
    var darkMarkURL: URL
    var legalAttributionText: String

    var hasPartialCoverage: Bool {
        forecastDayCount < tripDayCount
    }

    var coverageSummary: String {
        if hasPartialCoverage {
            return "Forecast available for \(forecastDayCount) of \(tripDayCount) trip days. Suggestions use only the available days."
        }
        return tripDayCount == 1
            ? "Forecast covers the trip day."
            : "Forecast covers all \(tripDayCount) trip days."
    }
}

struct TripDailyWeather: Equatable, Sendable {
    var date: Date
    var lowTemperatureCelsius: Double
    var highTemperatureCelsius: Double
    var precipitationChance: Double
    var uvIndex: Int
    var symbolName: String = "cloud.sun.fill"
}

struct TripWeatherAttribution: Equatable, Sendable {
    var legalPageURL: URL
    var lightMarkURL: URL
    var darkMarkURL: URL
    var legalAttributionText: String = ""
}

enum TripWeatherAvailability: Equatable, Sendable {
    case available
    case notYetAvailable
    case past
    case locationRequired
    case failed(TripWeatherFailure)
}

enum TripWeatherFailure: Equatable, Sendable {
    case appConfiguration
    case connection
    case serviceUnavailable
}

struct TripDestinationWeatherForecast: Equatable, Identifiable, Sendable {
    var window: TripDestinationWeatherWindow
    var snapshot: TripWeatherSnapshot?
    var availability: TripWeatherAvailability

    var id: UUID { window.id }
}

protocol TripWeatherForecastClient: Sendable {
    func dailyForecast(latitude: Double, longitude: Double) async throws -> [TripDailyWeather]
    func attribution() async throws -> TripWeatherAttribution
}

protocol TripDestinationSearchClient {
    func searchDestinations(matching query: String) async throws -> [TripDestinationSelection]
}

struct LiveTripWeatherForecastClient: TripWeatherForecastClient {
    func dailyForecast(latitude: Double, longitude: Double) async throws -> [TripDailyWeather] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let forecast = try await WeatherService.shared.weather(for: location, including: .daily)
        return forecast.forecast.map {
            TripDailyWeather(
                date: $0.date,
                lowTemperatureCelsius: $0.lowTemperature.converted(to: .celsius).value,
                highTemperatureCelsius: $0.highTemperature.converted(to: .celsius).value,
                precipitationChance: $0.precipitationChance,
                uvIndex: $0.uvIndex.value,
                symbolName: $0.symbolName
            )
        }
    }

    func attribution() async throws -> TripWeatherAttribution {
        let value = try await WeatherService.shared.attribution
        return TripWeatherAttribution(
            legalPageURL: value.legalPageURL,
            lightMarkURL: value.combinedMarkLightURL,
            darkMarkURL: value.combinedMarkDarkURL,
            legalAttributionText: value.legalAttributionText
        )
    }
}

struct LiveTripDestinationSearchClient: TripDestinationSearchClient {
    func searchDestinations(matching query: String) async throws -> [TripDestinationSelection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let response = try await MKLocalSearch(request: request).start()
        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            let coordinate = item.placemark.coordinate
            let key = String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
            guard seen.insert(key).inserted else { return nil }
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (name?.isEmpty == false ? name : nil) ?? trimmed
            let detailParts = [
                item.placemark.locality,
                item.placemark.administrativeArea,
                item.placemark.country
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveCompare(displayName) != .orderedSame }
            var uniqueDetailParts = [String]()
            for part in detailParts where !uniqueDetailParts.contains(where: {
                $0.localizedCaseInsensitiveCompare(part) == .orderedSame
            }) {
                uniqueDetailParts.append(part)
            }
            return TripDestinationSelection(
                name: displayName,
                detail: uniqueDetailParts.joined(separator: ", ").nilIfEmpty,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timeZoneIdentifier: item.placemark.timeZone?.identifier
            )
        }
        .prefix(8)
        .map { $0 }
    }
}

actor TripWeatherSnapshotCache {
    static let shared = TripWeatherSnapshotCache()

    private struct Entry {
        var snapshot: TripWeatherSnapshot
        var fetchedAt: Date
    }

    private var entries = [String: Entry]()

    func snapshot(for key: String, now: Date, maxAge: TimeInterval) -> TripWeatherSnapshot? {
        guard let entry = entries[key], now.timeIntervalSince(entry.fetchedAt) <= maxAge else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.snapshot
    }

    func store(_ snapshot: TripWeatherSnapshot, for key: String, fetchedAt: Date) {
        entries[key] = Entry(snapshot: snapshot, fetchedAt: fetchedAt)
    }

    func removeAll() {
        entries.removeAll()
    }
}

enum TripWeatherService {
    static let cacheDuration: TimeInterval = 30 * 60

    static func searchDestinations(
        matching query: String,
        client: any TripDestinationSearchClient = LiveTripDestinationSearchClient()
    ) async throws -> [TripDestinationSelection] {
        try Task.checkCancellation()
        let values = try await client.searchDestinations(matching: query)
        try Task.checkCancellation()
        return values
    }

    static func snapshot(
        for trip: PackingTrip,
        client: any TripWeatherForecastClient = LiveTripWeatherForecastClient(),
        cache: TripWeatherSnapshotCache = .shared,
        locale: Locale = .current,
        now: Date = Date(),
        forceRefresh: Bool = false
    ) async throws -> TripWeatherSnapshot? {
        guard let query = TripWeatherQuery(trip: trip) else { return nil }
        return try await snapshot(
            for: query,
            client: client,
            cache: cache,
            locale: locale,
            now: now,
            forceRefresh: forceRefresh
        )
    }

    static func forecasts(
        for trip: PackingTrip,
        client: any TripWeatherForecastClient = LiveTripWeatherForecastClient(),
        cache: TripWeatherSnapshotCache = .shared,
        locale: Locale = .current,
        now: Date = Date(),
        forceRefresh: Bool = false
    ) async -> [TripDestinationWeatherForecast] {
        guard trip.weatherSuggestionsEnabled else { return [] }
        let windows = trip.destinationWeatherWindows
        return await withTaskGroup(
            of: (Int, TripDestinationWeatherForecast).self,
            returning: [TripDestinationWeatherForecast].self
        ) { group in
            for (index, window) in windows.enumerated() {
                guard let query = TripWeatherQuery(
                    window: window,
                    tripTimeZone: trip.tripTimeZone
                ) else {
                    group.addTask {
                        (index, TripDestinationWeatherForecast(
                            window: window,
                            snapshot: nil,
                            availability: .locationRequired
                        ))
                    }
                    continue
                }
                group.addTask {
                    do {
                        let value = try await snapshot(
                            for: query,
                            client: client,
                            cache: cache,
                            locale: locale,
                            now: now,
                            forceRefresh: forceRefresh
                        )
                        let today = TripDayKey(date: now, timeZone: query.destinationTimeZone)
                        let availability: TripWeatherAvailability
                        if value != nil {
                            availability = .available
                        } else if query.endDay < today {
                            availability = .past
                        } else {
                            availability = .notYetAvailable
                        }
                        return (index, TripDestinationWeatherForecast(
                            window: window,
                            snapshot: value,
                            availability: availability
                        ))
                    } catch is CancellationError {
                        return (index, TripDestinationWeatherForecast(
                            window: window,
                            snapshot: nil,
                            availability: .failed(.serviceUnavailable)
                        ))
                    } catch {
                        return (index, TripDestinationWeatherForecast(
                            window: window,
                            snapshot: nil,
                            availability: .failed(failureReason(for: error))
                        ))
                    }
                }
            }
            var indexed = [(Int, TripDestinationWeatherForecast)]()
            for await value in group {
                indexed.append(value)
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func failureReason(for error: Error) -> TripWeatherFailure {
        if let weatherError = error as? WeatherError,
           weatherError == .permissionDenied {
            return .appConfiguration
        }

        let nsError = error as NSError
        if error is URLError || nsError.domain == NSURLErrorDomain {
            return .connection
        }

        let configurationDetails = [
            nsError.domain,
            nsError.localizedDescription,
            nsError.localizedFailureReason ?? "",
            nsError.localizedRecoverySuggestion ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        let configurationTerms = [
            "authorization",
            "authentication",
            "entitlement",
            "jwt",
            "permission"
        ]
        if configurationTerms.contains(where: configurationDetails.contains) {
            return .appConfiguration
        }

        return .serviceUnavailable
    }

    private static func snapshot(
        for query: TripWeatherQuery,
        client: any TripWeatherForecastClient,
        cache: TripWeatherSnapshotCache,
        locale: Locale,
        now: Date,
        forceRefresh: Bool
    ) async throws -> TripWeatherSnapshot? {
        if !forceRefresh,
           let cached = await cache.snapshot(for: query.cacheKey, now: now, maxAge: cacheDuration) {
            return cached
        }
        try Task.checkCancellation()
        async let forecast = client.dailyForecast(
            latitude: query.latitude,
            longitude: query.longitude
        )
        async let attribution = client.attribution()
        let (days, attributionValue) = try await (forecast, attribution)
        try Task.checkCancellation()
        guard let value = makeSnapshot(
            query: query,
            days: days,
            attribution: attributionValue,
            locale: locale
        ) else {
            return nil
        }
        await cache.store(value, for: query.cacheKey, fetchedAt: now)
        return value
    }

    static func makeSnapshot(
        query: TripWeatherQuery,
        days: [TripDailyWeather],
        attribution: TripWeatherAttribution,
        locale: Locale
    ) -> TripWeatherSnapshot? {
        let relevantDays = days
            .filter {
                let key = TripDayKey(date: $0.date, timeZone: query.destinationTimeZone)
                return key >= query.startDay && key <= query.endDay
            }
            .sorted { $0.date < $1.date }
        guard !relevantDays.isEmpty else { return nil }
        let forecastDayCount = Set(relevantDays.map {
            TripDayKey(date: $0.date, timeZone: query.destinationTimeZone)
        }).count
        let low = relevantDays.map(\.lowTemperatureCelsius).min() ?? 0
        let high = relevantDays.map(\.highTemperatureCelsius).max() ?? 0
        let rain = relevantDays.contains { $0.precipitationChance >= 0.35 }
        let highUV = relevantDays.contains { $0.uvIndex >= 6 }
        let unit: UnitTemperature = locale.measurementSystem == .us ? .fahrenheit : .celsius
        let displayedLow = Measurement(value: low, unit: UnitTemperature.celsius)
            .converted(to: unit).value
        let displayedHigh = Measurement(value: high, unit: UnitTemperature.celsius)
            .converted(to: unit).value
        let temperatureRange = "\(Int(displayedLow.rounded()))–\(Int(displayedHigh.rounded()))\(unit.symbol)"
        let rainText = rain ? " Rain is possible." : ""
        return TripWeatherSnapshot(
            summary: "Forecast range \(temperatureRange).\(rainText)",
            forecastDayCount: forecastDayCount,
            tripDayCount: query.tripDayCount,
            lowTemperatureCelsius: low,
            highTemperatureCelsius: high,
            rainLikely: rain,
            coldWeather: low <= 8,
            hotOrHighUV: high >= 27 || highUV,
            dailyForecast: relevantDays,
            legalPageURL: attribution.legalPageURL,
            lightMarkURL: attribution.lightMarkURL,
            darkMarkURL: attribution.darkMarkURL,
            legalAttributionText: attribution.legalAttributionText
        )
    }
}

struct TripWeatherQuery: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var startDay: TripDayKey
    var endDay: TripDayKey
    var destinationTimeZoneIdentifier: String

    init?(trip: PackingTrip) {
        guard trip.weatherSuggestionsEnabled,
              let window = trip.destinationWeatherWindows.first else {
            return nil
        }
        self.init(window: window, tripTimeZone: trip.tripTimeZone)
    }

    init?(window: TripDestinationWeatherWindow, tripTimeZone: TimeZone) {
        guard let latitude = window.destination.latitude,
              let longitude = window.destination.longitude else {
            return nil
        }
        self.latitude = latitude
        self.longitude = longitude
        self.startDay = TripDayKey(date: window.startDate, timeZone: tripTimeZone)
        self.endDay = TripDayKey(date: window.endDate, timeZone: tripTimeZone)
        self.destinationTimeZoneIdentifier = window.destination.timeZoneIdentifier
            ?? tripTimeZone.identifier
    }

    var destinationTimeZone: TimeZone {
        TimeZone(identifier: destinationTimeZoneIdentifier) ?? .current
    }

    var tripDayCount: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = destinationTimeZone
        guard let startDate = calendar.date(from: startDay.dateComponents),
              let endDate = calendar.date(from: endDay.dateComponents),
              let interval = calendar.dateComponents([.day], from: startDate, to: endDate).day else {
            return 1
        }
        return max(1, interval + 1)
    }

    var cacheKey: String {
        String(format: "%.5f|%.5f|%@|%@|%@", latitude, longitude, startDay.description, endDay.description, destinationTimeZoneIdentifier)
    }
}

struct TripDayKey: Comparable, CustomStringConvertible, Equatable, Hashable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
    }

    static func < (lhs: TripDayKey, rhs: TripDayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
