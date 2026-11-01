import CoreLocation
import Foundation
import WeatherKit

/// Shared by the app and weather widget. Never accesses care history or requests location permission.
enum WeatherForecastClient {
    private static let requests = WeatherForecastRequestCoordinator()
    static func fetch(latitude: Double, longitude: Double, now: Date = Date(), includeMinutes: Bool = true, onUpdate: (@Sendable (DailyWeatherSnapshot) async -> Void)? = nil) async throws -> DailyWeatherSnapshot {
        // The app store already shares its refresh task. Keep its progressive
        // stream structured so a city change cancels its requests and callbacks.
        if onUpdate != nil {
            return try await load(latitude: latitude, longitude: longitude, now: now, includeMinutes: includeMinutes, onUpdate: onUpdate)
        }
        return try await requests.fetch(key: "\(latitude),\(longitude)-minutes:\(includeMinutes)") {
            try await load(latitude: latitude, longitude: longitude, now: now, includeMinutes: includeMinutes, onUpdate: nil)
        }
    }
    private static func load(latitude: Double, longitude: Double, now: Date, includeMinutes: Bool, onUpdate: (@Sendable (DailyWeatherSnapshot) async -> Void)?) async throws -> DailyWeatherSnapshot {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        async let base = WeatherService.shared.weather(for: location, including: .current, .daily)
        async let hourlyData = WeatherService.shared.weather(for: location, including:
            .hourly(startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(10 * 86400)))
        async let legal = WeatherService.shared.attribution
        // Optional minute data loads concurrently without making the main forecast fail.
        async let minuteData = includeMinutes ? (try? await WeatherService.shared.weather(for: location, including: .minute, .availability)) : nil
        let ((current, daily), credit) = try await (base, legal)
        var result = DailyWeatherSnapshot(fetchedAt: now,
            currentTemperatureCelsius: current.temperature.converted(to: .celsius).value,
            symbolName: current.symbolName,
            days: daily.forecast.map { day in
                TripDailyWeather(date: day.date,
                    lowTemperatureCelsius: day.lowTemperature.converted(to: .celsius).value,
                    highTemperatureCelsius: day.highTemperature.converted(to: .celsius).value,
                    precipitationChance: day.precipitationChance, uvIndex: day.uvIndex.value,
                    symbolName: day.symbolName, condition: day.condition.description,
                    precipitationMillimeters: day.precipitationAmount.converted(to: .millimeters).value,
                    sunrise: day.sun.sunrise, sunset: day.sun.sunset)
            }, attribution: TripWeatherAttribution(legalPageURL: credit.legalPageURL,
                lightMarkURL: credit.combinedMarkLightURL, darkMarkURL: credit.combinedMarkDarkURL,
                legalAttributionText: credit.legalAttributionText))
        result.condition = current.condition.description
        result.feelsLike = current.apparentTemperature.converted(to: .celsius).value
        result.humidity = current.humidity
        result.windKPH = current.wind.speed.converted(to: .kilometersPerHour).value
        result.gustKPH = current.wind.gust?.converted(to: .kilometersPerHour).value
        result.uv = current.uvIndex.value
        result.expiresAt = current.metadata.expirationDate
        result.detailedForecastPending = true
        await onUpdate?(result)
        let hourly = try await hourlyData
        result.hours = hourly.forecast.map { hour in
            WeatherHour(date: hour.date, temperature: hour.temperature.converted(to: .celsius).value,
                feelsLike: hour.apparentTemperature.converted(to: .celsius).value,
                symbol: hour.symbolName, condition: hour.condition.description,
                rainChance: hour.precipitationChance,
                precipitationMillimeters: hour.precipitationAmount.converted(to: .millimeters).value,
                windKPH: hour.wind.speed.converted(to: .kilometersPerHour).value,
                gustKPH: hour.wind.gust?.converted(to: .kilometersPerHour).value,
                uv: hour.uvIndex.value, daylight: hour.isDaylight, precipitationType: hour.precipitation.description)
        }
        result.detailedForecastPending = false
        await onUpdate?(result)
        // Widgets do not display minute data and must not wait for that service.
        if !includeMinutes {
            result.minuteAvailability = "notRequested"
            result.minuteExpiresAt = now
            return result
        }
        // Neither the Today summary nor hourly views wait for optional minute data.
        let extra = await minuteData
        result.minuteFetchedAt = now
        if let (minute, availability) = extra {
            result.minuteAvailability = availability.minuteAvailability.rawValue
            result.minutes = minute?.forecast.map {
                WeatherMinute(date: $0.date, probability: $0.precipitationChance,
                    intensityMMPerHour: $0.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000,
                    type: $0.precipitation.description)
            }
            result.minuteExpiresAt = minute.map { min($0.metadata.expirationDate, now.addingTimeInterval(300)) }
        } else { result.minuteAvailability = "temporarilyUnavailable" }
        return result
    }
    static func refreshMinutes(in snapshot: DailyWeatherSnapshot, latitude: Double, longitude: Double, now: Date = Date()) async -> DailyWeatherSnapshot {
        var result = snapshot
        result.minuteFetchedAt = now
        result.minutes = nil
        result.minuteExpiresAt = now.addingTimeInterval(300)
        result.minuteAvailability = "temporarilyUnavailable"
        if let (minute, availability) = try? await WeatherService.shared.weather(for: CLLocation(latitude: latitude, longitude: longitude), including: .minute, .availability) {
            result.minuteAvailability = availability.minuteAvailability.rawValue
            result.minutes = minute?.forecast.map {
                WeatherMinute(date: $0.date, probability: $0.precipitationChance,
                    intensityMMPerHour: $0.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000,
                    type: $0.precipitation.description)
            }
            result.minuteExpiresAt = minute.map { min($0.metadata.expirationDate, now.addingTimeInterval(300)) } ?? now.addingTimeInterval(300)
        }
        return result
    }
}

/// Multiple widget configurations share a city's in-flight request, not its lifetime.
actor WeatherForecastRequestCoordinator {
    private var requests: [String: Task<DailyWeatherSnapshot, Error>] = [:]
    func fetch(key: String, operation: @escaping @Sendable () async throws -> DailyWeatherSnapshot) async throws -> DailyWeatherSnapshot {
        if let request = requests[key] { return try await request.value }
        let request = Task { try await operation() }
        requests[key] = request
        defer { requests[key] = nil }
        return try await request.value
    }
}
