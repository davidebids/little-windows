import Foundation

struct TripDailyWeather: Codable, Hashable, Sendable {
    var date: Date
    var lowTemperatureCelsius: Double
    var highTemperatureCelsius: Double
    var precipitationChance: Double
    var uvIndex: Int
    var symbolName: String = "cloud.sun.fill"
    var condition: String? = nil
    var precipitationMillimeters: Double? = nil
    var sunrise: Date? = nil
    var sunset: Date? = nil
}

struct TripWeatherAttribution: Codable, Hashable, Sendable {
    var legalPageURL: URL
    var lightMarkURL: URL
    var darkMarkURL: URL
    var legalAttributionText: String = ""
}

struct WeatherHour: Codable, Hashable, Identifiable, Sendable {
    var date: Date
    var temperature: Double
    var feelsLike: Double
    var symbol: String
    var condition: String
    var rainChance: Double
    var precipitationMillimeters: Double
    var windKPH: Double
    var gustKPH: Double?
    var uv: Int
    var daylight: Bool
    var precipitationType: String? = nil
    var id: Date { date }
}

struct WeatherMinute: Codable, Hashable, Identifiable, Sendable {
    var date: Date
    var probability: Double
    var intensityMMPerHour: Double
    var type: String
    var id: Date { date }
}

struct DailyWeatherSnapshot: Codable, Hashable, Sendable {
    var fetchedAt: Date
    var currentTemperatureCelsius: Double
    var symbolName: String
    var days: [TripDailyWeather]
    var attribution: TripWeatherAttribution
    var condition: String = ""
    var feelsLike: Double? = nil
    var humidity: Double? = nil
    var windKPH: Double? = nil
    var gustKPH: Double? = nil
    var uv: Int? = nil
    var hours: [WeatherHour] = []
    var minutes: [WeatherMinute]? = nil
    var minuteAvailability: String = "unsupported"
    var expiresAt: Date? = nil
    var minuteExpiresAt: Date? = nil
    var minuteFetchedAt: Date? = nil
    var detailedForecastPending: Bool? = nil

    func day(for date: Date, timeZone: TimeZone) -> TripDailyWeather? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    func isFresh(at now: Date) -> Bool {
        fetchedAt <= now.addingTimeInterval(60) && now < min(expiresAt ?? fetchedAt.addingTimeInterval(1800), fetchedAt.addingTimeInterval(1800))
    }
    func needsMinuteRefresh(at now: Date) -> Bool {
        guard minuteAvailability != "unsupported" else { return false }
        let retrieved = minuteFetchedAt ?? fetchedAt
        return now >= min(minuteExpiresAt ?? retrieved.addingTimeInterval(300), retrieved.addingTimeInterval(300))
    }
    func validMinutes(at now: Date) -> [WeatherMinute]? {
        guard minuteAvailability == "available", !needsMinuteRefresh(at: now),
              (minuteFetchedAt ?? fetchedAt) <= now.addingTimeInterval(60), let minutes else { return nil }
        let future = minutes.filter {
            $0.date >= now.addingTimeInterval(-60) && $0.date <= now.addingTimeInterval(3600)
                && $0.probability.isFinite && (0...1).contains($0.probability)
                && $0.intensityMMPerHour.isFinite && $0.intensityMMPerHour >= 0
        }.sorted { $0.date < $1.date }
        return future.isEmpty ? nil : future
    }

}

/// Raw values retain the existing synced activity names and snapshot format.
enum OutdoorActivity: String, CaseIterable, Sendable {
    case outdoorTime = "Outdoor time"
    case walk = "Walk"
    case strollerWalk = "Stroller walk"
    case gentleOutdoorTime = "Gentle outdoor time"
    case parkVisit = "Park visit"
    case natureWalk = "Nature walk"
    case picnic = "Picnic"
    case blanketPlay = "Blanket play"
    case storyTimeOutside = "Story time outside"
    case playground = "Playground"
    case outdoorPlay = "Outdoor play"
    case bubbles = "Bubbles"
    case ballGames = "Ball games"
    case gardenPlay = "Garden play"
    case outdoorArt = "Outdoor art"
    case bikeRide = "Bike ride"
    case scooterRide = "Scooter ride"
    case hike = "Hike"
    case sniffWalk = "Sniff walk"
    case fetch = "Fetch"
    case dogPark = "Dog park"
    case training = "Training"
    case yardTime = "Yard time"
    case run = "Run"
    case gardening = "Gardening"
    case outdoorExercise = "Outdoor exercise"
    case outdoorReading = "Outdoor reading"

    static func options(type: String, ageMonths: Int?) -> [Self] {
        switch type {
        case "dog":
            return [.walk, .outdoorPlay, .sniffWalk, .fetch, .dogPark, .training, .yardTime, .parkVisit, .hike]
        case "child":
            if let ageMonths, (0..<12).contains(ageMonths) {
                return [.strollerWalk, .outdoorTime, .parkVisit, .natureWalk, .picnic, .blanketPlay, .storyTimeOutside]
            }
            let shared: [Self] = [.outdoorTime, .walk, .strollerWalk, .playground, .outdoorPlay,
                .parkVisit, .natureWalk, .picnic, .bubbles, .ballGames, .gardenPlay, .outdoorArt, .storyTimeOutside]
            // Age is used to curate choices, not to infer developmental ability.
            return ageMonths.map { $0 >= 36 } == true ? shared + [.bikeRide, .scooterRide, .hike] : shared
        default:
            return [.outdoorTime, .walk, .gentleOutdoorTime, .parkVisit, .natureWalk, .picnic,
                .run, .hike, .bikeRide, .gardening, .outdoorExercise, .outdoorReading]
        }
    }

    static func pickerOptions(_ activities: [String], selected: String) -> [String] {
        // Retain selections from an earlier age group or a newer synced client.
        var seen = Set<String>()
        return (activities + [selected]).filter { seen.insert($0).inserted }
    }

    /// Activities only break ties between hours that already meet every edited
    /// comfort limit. Choosing an activity never changes those limits.
    static func rankingPenalty(activity: String, rain: Double, wind: Double, uv: Int, warmth: Double) -> Double {
        guard let activity = Self(rawValue: activity) else { return warmth / 8 }
        switch activity {
        case .playground, .outdoorPlay, .blanketPlay, .storyTimeOutside, .picnic, .bubbles,
             .ballGames, .gardenPlay, .outdoorArt, .fetch, .dogPark, .training, .gardening, .outdoorReading:
            return rain * 8 + Double(uv) / 3
        case .walk, .strollerWalk, .natureWalk, .sniffWalk, .hike, .run, .bikeRide, .scooterRide, .outdoorExercise:
            return wind / 15 + warmth / 6
        case .outdoorTime, .gentleOutdoorTime, .parkVisit, .yardTime:
            return warmth / 8
        }
    }
}

struct OutdoorPreferences: Codable, Hashable, Sendable {
    var enabled = true
    var activity = "Outdoor time"
    var minimumCelsius = 10.0
    var maximumCelsius = 27.0
    var maximumRainChance = 0.3
    var maximumWindKPH = 25.0
    var maximumUV = 5

    static func defaults(for type: String) -> Self {
        var value = Self()
        value.activity = type == "dog" ? "Walk" : type == "child" ? "Stroller walk" : "Outdoor time"
        return value
    }
    var isValid: Bool {
        minimumCelsius.isFinite && maximumCelsius.isFinite && minimumCelsius <= maximumCelsius
            && (-40...50).contains(minimumCelsius) && (-40...50).contains(maximumCelsius)
            && maximumRainChance.isFinite && (0...1).contains(maximumRainChance)
            && maximumWindKPH.isFinite && (0...120).contains(maximumWindKPH) && (0...15).contains(maximumUV)
    }
}

struct WeatherBusyInterval: Codable, Hashable, Sendable {
    var start: Date
    var end: Date
    func overlaps(_ start: Date, _ end: Date) -> Bool { self.start < end && self.end > start }
}

struct OutdoorProfileContext: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var type: String
    var activities: [String]
    var preferences: OutdoorPreferences
    var busy: [WeatherBusyInterval] = []
    var predictedSleep: [WeatherBusyInterval] = []
    var lastWalk: Date? = nil
    var contextUpdatedAt: Date? = nil
}

struct OutdoorWindow: Codable, Hashable, Identifiable, Sendable {
    var start: Date
    var end: Date
    var lowFeelsLike: Double
    var highFeelsLike: Double
    var rainChance: Double
    var windKPH: Double
    var uv: Int
    var fitsSleepPlan: Bool
    var id: Date { start }
}

enum OutdoorWindowEngine {
    /// Comfort preferences are user choices, not medical or exercise limits.
    static func suggestion(weather: DailyWeatherSnapshot, profiles: [OutdoorProfileContext], day: Date,
                           timeZone: TimeZone, now: Date, previous: OutdoorWindow? = nil) -> OutdoorWindow? {
        guard weather.isFresh(at: now), !profiles.isEmpty,
              profiles.allSatisfy({ profile in
                  guard let captured = profile.contextUpdatedAt else { return false }
                  return profile.preferences.enabled && profile.preferences.isValid && captured <= now.addingTimeInterval(60) && now.timeIntervalSince(captured) < 1800
              }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let daily = weather.day(for: day, timeZone: timeZone),
              let sunrise = daily.sunrise, let sunset = daily.sunset else { return nil }
        let first = max(now, dayStart, sunrise)
        let last = min(dayEnd, sunset)
        guard last.timeIntervalSince(first) >= 3600 else { return nil }
        let hours = weather.hours.filter { $0.date < last && $0.date.addingTimeInterval(3600) > first }.sorted { $0.date < $1.date }
        let minimum = profiles.map { $0.preferences.minimumCelsius }.max()!
        let maximum = profiles.map { $0.preferences.maximumCelsius }.min()!
        guard minimum <= maximum else { return nil }
        let rainLimit = profiles.map { $0.preferences.maximumRainChance }.min()!
        let windLimit = profiles.map { $0.preferences.maximumWindKPH }.min()!
        let uvLimit = profiles.map { $0.preferences.maximumUV }.min()!
        let midpoint = profiles.map { ($0.preferences.minimumCelsius + $0.preferences.maximumCelsius) / 2 }.reduce(0, +) / Double(profiles.count)
        let busy = mergedIntervals(profiles.flatMap(\.busy), from: first, through: last)
        let sleep = mergedIntervals(profiles.flatMap(\.predictedSleep), from: first, through: last)
        var candidates: [(OutdoorWindow, Double)] = []
        var starts = [first]
        var rounded = Date(timeIntervalSince1970: ceil(first.timeIntervalSince1970 / 900) * 900)
        while rounded.addingTimeInterval(3600) <= last {
            starts.append(rounded)
            rounded = rounded.addingTimeInterval(900)
        }
        starts += busy.map(\.end)
        if let previous { starts.append(previous.start) }
        for start in Set(starts).sorted() where start >= first && start.addingTimeInterval(3600) <= last {
            let end = start.addingTimeInterval(3600)
            guard !busy.contains(where: { $0.overlaps(start, end) }) else { continue }
            let covered = hours.filter { $0.date < end && $0.date.addingTimeInterval(3600) > start }
            var cursor = start
            var valid = !covered.isEmpty
            for hour in covered {
                if hour.date > cursor || !hour.daylight { valid = false; break }
                cursor = max(cursor, min(end, hour.date.addingTimeInterval(3600)))
                if !hour.feelsLike.isFinite || !hour.rainChance.isFinite || !hour.windKPH.isFinite
                    || !(0...1).contains(hour.rainChance) || hour.windKPH < 0 || hour.uv < 0
                    || hour.gustKPH.map({ !$0.isFinite || $0 < 0 }) == true
                    || hour.feelsLike < minimum || hour.feelsLike > maximum
                    || hour.rainChance > rainLimit || max(hour.windKPH, hour.gustKPH ?? 0) > windLimit
                    || hour.uv > uvLimit { valid = false; break }
            }
            if valid && cursor >= end {
                let fitsSleep = !sleep.contains { $0.overlaps(start, end) }
                let rain = covered.map(\.rainChance).max() ?? 0
                let wind = covered.map { max($0.windKPH, $0.gustKPH ?? 0) }.max() ?? 0
                let uv = covered.map(\.uv).max() ?? 0
                let value = OutdoorWindow(start: start, end: end,
                    lowFeelsLike: covered.map(\.feelsLike).min() ?? 0,
                    highFeelsLike: covered.map(\.feelsLike).max() ?? 0,
                    rainChance: rain, windKPH: wind, uv: uv, fitsSleepPlan: fitsSleep)
                // Weather comfort first; reliable sleep planning gently breaks ties.
                let warmth = abs((value.lowFeelsLike + value.highFeelsLike) / 2 - midpoint)
                let activityScore = profiles.map { profile in
                    OutdoorActivity.rankingPenalty(activity: profile.preferences.activity,
                        rain: rain, wind: wind, uv: uv, warmth: warmth)
                }.reduce(0, +) / Double(profiles.count)
                let score = rain * 20 + wind / 10 + Double(uv) / 3 + warmth / 5 + activityScore + (fitsSleep ? 0 : 2)
                candidates.append((value, score))
            }
        }
        guard let best = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        if let previous, let retained = candidates.first(where: { $0.0.start == previous.start }), retained.1 <= best.1 + 1 { return retained.0 }
        return best.0
    }
    private static func mergedIntervals(_ values: [WeatherBusyInterval], from start: Date, through end: Date) -> [WeatherBusyInterval] {
        let relevant = values.filter { $0.start < end && $0.end > start && $0.end > $0.start }.sorted { $0.start < $1.start }
        var result: [WeatherBusyInterval] = []
        for value in relevant {
            if let last = result.last, value.start <= last.end {
                result[result.count - 1].end = max(last.end, value.end)
            } else { result.append(value) }
        }
        return result
    }
}

struct WeatherSurfaceState: Codable, Hashable, Sendable {
    var city: String
    var timeZoneIdentifier: String
    var fahrenheit: Bool
    var windUnit: String
    var precipitationUnit: String
    var forecast: DailyWeatherSnapshot
    var selectedProfileID: UUID?
    var profiles: [OutdoorProfileContext]
    // Only manually selected city coordinates may be persisted for widget refresh.
    var manualLatitude: Double? = nil
    var manualLongitude: Double? = nil
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
    func mergingWidgetForecast(_ cached: WeatherSurfaceState?) -> WeatherSurfaceState {
        guard let cached, manualLatitude != nil, manualLongitude != nil,
              city == cached.city, timeZoneIdentifier == cached.timeZoneIdentifier,
              manualLatitude == cached.manualLatitude, manualLongitude == cached.manualLongitude,
              cached.forecast.fetchedAt > forecast.fetchedAt else { return self }
        var result = self
        result.forecast = cached.forecast
        return result
    }
    /// The companion presents six hours and today's outing.
    /// Avoid sending the phone's ten-day forecast and unrelated profile schedules.
    func watchSnapshot(profileID: UUID?, now: Date) -> WeatherSurfaceState {
        var result = self
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        // Keep forecast coverage across midnight so cached surfaces can plan the new day.
        let planningDay = calendar.startOfDay(for: now.addingTimeInterval(1800))
        let end = calendar.date(byAdding: .day, value: 2, to: planningDay) ?? now.addingTimeInterval(49 * 3600)
        result.selectedProfileID = profileID
        result.manualLatitude = nil; result.manualLongitude = nil
        result.forecast.hours = forecast.hours.filter { $0.date.addingTimeInterval(3600) > now && $0.date < end }
        result.forecast.days = forecast.days.filter { $0.date >= today && $0.date < end }
        result.forecast.minutes = forecast.validMinutes(at: now)
        result.profiles = profiles.filter { $0.id == profileID }.map { profile in
            var value = profile
            value.busy = profile.busy.filter { $0.start < end && $0.end > now }
            value.predictedSleep = profile.predictedSleep.filter { $0.start < end && $0.end > now }
            return value
        }
        return result
    }
    /// Widget views use six hours, today's outing, and three daily rows.
    func widgetSnapshot(profileID: UUID?, now: Date) -> WeatherSurfaceState {
        var result = watchSnapshot(profileID: profileID, now: now)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: now)
        let lastTimelineDay = calendar.startOfDay(for: now.addingTimeInterval(6 * 3600))
        let end = calendar.date(byAdding: .day, value: 3, to: lastTimelineDay) ?? now.addingTimeInterval(4 * 86400)
        result.forecast.days = forecast.days.filter { $0.date >= start && $0.date < end }
        result.forecast.minutes = nil
        result.forecast.minuteAvailability = "unsupported"
        result.forecast.minuteExpiresAt = nil
        result.forecast.minuteFetchedAt = nil
        return result
    }
    func hasSameWidgetContent(as other: WeatherSurfaceState?) -> Bool {
        guard var other else { return false }
        var current = self
        current.forecast.minutes = nil; other.forecast.minutes = nil
        current.forecast.minuteAvailability = ""; other.forecast.minuteAvailability = ""
        current.forecast.minuteExpiresAt = nil; other.forecast.minuteExpiresAt = nil
        current.forecast.minuteFetchedAt = nil; other.forecast.minuteFetchedAt = nil
        return current == other
    }
    func nextOutdoorWindow(profileID: UUID, now: Date) -> OutdoorWindow? {
        outdoor(profileIDs: [profileID], day: now, now: now)
    }
    func dateLabel(_ date: Date) -> String {
        var format = Date.FormatStyle().month(.abbreviated).day(); format.timeZone = timeZone
        return date.formatted(format)
    }
    func updatedLabel(at now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let date = forecast.fetchedAt
        return calendar.isDate(date, inSameDayAs: now) ? "Updated \(time(date))" : "Updated \(dateLabel(date)) · \(time(date))"
    }
    func temperature(_ celsius: Double) -> String {
        guard celsius.isFinite, abs(celsius) < 1000 else { return "—" }
        return "\(Int((fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded()))°"
    }
    func wind(_ kph: Double) -> String {
        guard kph.isFinite, (0...1000).contains(kph) else { return "—" }
        return "\(Int((windUnit == "mph" ? kph / 1.609344 : kph).rounded())) \(windUnit)"
    }
    func precipitation(_ mm: Double) -> String {
        let value = precipitationUnit == "in" ? mm / 25.4 : mm
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(precipitationUnit)"
    }
    func time(_ date: Date) -> String {
        { var format = Date.FormatStyle(date: .omitted, time: .shortened); format.timeZone = timeZone; return date.formatted(format) }()
    }
    func outdoor(profileIDs: Set<UUID>, day: Date, now: Date, previous: OutdoorWindow? = nil) -> OutdoorWindow? {
        let selected = profiles.filter { profileIDs.contains($0.id) }
        guard selected.count == profileIDs.count else { return nil }
        return OutdoorWindowEngine.suggestion(weather: forecast, profiles: selected, day: day, timeZone: timeZone, now: now, previous: previous)
    }
    func outlook(at now: Date) -> String {
        let upcoming = forecast.hours.filter { $0.date.addingTimeInterval(3600) > now && $0.date < now.addingTimeInterval(12 * 3600) }.sorted { $0.date < $1.date }
        guard let first = upcoming.first else { return forecast.condition }
        let horizon = now.addingTimeInterval(12 * 3600)
        let period = Self.covers(upcoming, from: now, through: horizon) ? "over the next 12 hours" : "in the available hourly forecast"
        let rain = upcoming.first { $0.rainChance >= 0.4 }
        let gust = upcoming.map { max($0.windKPH, $0.gustKPH ?? 0) }.max() ?? 0
        if let rain {
            let type = rain.precipitationType.flatMap { $0.lowercased() == "none" ? nil : $0.capitalized } ?? "Precipitation"
            let timing = rain.date <= now ? "this hour" : "around \(time(rain.date))"
            return "\(type) possible \(timing); feels like \(temperature(rain.feelsLike))."
        }
        if gust >= 30 { return "Wind up to \(wind(gust)) \(period)." }
        if let peak = upcoming.max(by: { $0.uv < $1.uv }), peak.uv >= 6 { return "UV peaks at \(peak.uv) around \(time(peak.date))." }
        if let last = upcoming.last, last.feelsLike < first.feelsLike - 3 { return "\(first.condition), becoming cooler; feels like \(temperature(last.feelsLike)) by \(time(last.date))." }
        let low = temperature(upcoming.map(\.feelsLike).min() ?? first.feelsLike)
        let high = temperature(upcoming.map(\.feelsLike).max() ?? first.feelsLike)
        return "\(first.condition) with feels-like temperatures of \(low == high ? low : low + "–" + high) \(period)."
    }
    func rainSummary(at now: Date) -> String? {
        guard let minutes = forecast.validMinutes(at: now) else { return nil }
        guard let first = minutes.first(where: { $0.intensityMMPerHour > 0 && $0.probability >= 0.3 }) else { return "Staying dry" }
        let offset = max(0, Int(first.date.timeIntervalSince(now) / 60))
        let timing = offset <= 1 ? "now" : "in about \(offset) minutes"
        let intensity = first.intensityMMPerHour < 2.5 ? "Light" : first.intensityMMPerHour < 7.5 ? "Moderate" : "Heavy"
        var summary = "\(intensity) \(first.type.lowercased()) possible \(timing)."
        if let dry = minutes.first(where: { $0.date > first.date && ($0.intensityMMPerHour <= 0 || $0.probability < 0.3) }) {
            summary += " May ease around \(time(dry.date))."
        }
        return summary
    }
    func tonight(at now: Date) -> [WeatherHour] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        guard let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) else { return [] }
        let start = max(now, evening)
        let hours = forecast.hours.filter { $0.date.addingTimeInterval(3600) > start && $0.date < morning }.sorted { $0.date < $1.date }
        return Self.covers(hours, from: start, through: morning) ? hours : []
    }
    private static func covers(_ hours: [WeatherHour], from start: Date, through end: Date) -> Bool {
        guard start < end else { return false }
        var cursor = start
        for hour in hours {
            guard hour.date <= cursor else { return false }
            cursor = max(cursor, hour.date.addingTimeInterval(3600))
        }
        return cursor >= end
    }
}

enum WeatherTimelinePolicy {
    static func entryDates(state: WeatherSurfaceState?, profileID: UUID?, now: Date) -> [Date] {
        var dates = [now]
        let horizon = now.addingTimeInterval(6 * 3600)
        if let state {
            let forecast = state.forecast
            if let profileID, let profile = state.profiles.first(where: { $0.id == profileID }),
               profile.preferences.enabled, let captured = profile.contextUpdatedAt,
               captured <= now.addingTimeInterval(60), forecast.isFresh(at: now) {
                let until = min(horizon, captured.addingTimeInterval(1800),
                    forecast.expiresAt ?? forecast.fetchedAt.addingTimeInterval(1800), forecast.fetchedAt.addingTimeInterval(1800))
                for offset in 1...24 {
                    let date = now.addingTimeInterval(Double(offset) * 900)
                    if date < until { dates.append(date) }
                }
            }
            dates += forecast.hours.map(\.date)
            dates += [forecast.expiresAt, forecast.minuteExpiresAt, forecast.fetchedAt.addingTimeInterval(1800)].compactMap { $0 }
            dates += state.profiles.compactMap { $0.contextUpdatedAt?.addingTimeInterval(1800) }
            if let profileID, let window = state.nextOutdoorWindow(profileID: profileID, now: now) {
                dates += [window.start.addingTimeInterval(1), window.end]
            }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = state.timeZone
            if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) { dates.append(midnight) }
        }
        return Array(Set(dates.filter { $0 >= now && $0 <= horizon })).sorted()
    }
}

enum WeatherSurfaceCache {
    static let filename = "weather-surface-v1.json"
    static var url: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.debidia.LittleWindows")?.appendingPathComponent(filename) }
    static var widgetForecastURL: URL? { url?.deletingLastPathComponent().appendingPathComponent("widget-weather-forecast-v1.json") }
    static func read() -> WeatherSurfaceState? {
        guard let primary = decode(url) else { return nil }
        return primary.mergingWidgetForecast(decode(widgetForecastURL))
    }
    private static func decode(_ url: URL?) -> WeatherSurfaceState? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WeatherSurfaceState.self, from: data)
    }
    static func write(_ state: WeatherSurfaceState?) {
        guard let url else { return }
        if let state, let data = try? JSONEncoder().encode(state) { try? data.write(to: url, options: .atomic) }
        else {
            try? FileManager.default.removeItem(at: url)
            if let widgetForecastURL { try? FileManager.default.removeItem(at: widgetForecastURL) }
        }
    }
}

#if DEBUG
enum WeatherPreviewData {
    static let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static func make(now: Date = Date()) -> WeatherSurfaceState {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current
        let start = c.date(bySetting: .minute, value: 0, of: now)!
        let dayStart = c.startOfDay(for: now)
        let days = (0..<10).map { offset -> TripDailyWeather in
            let date = c.date(byAdding: .day, value: offset, to: dayStart)!
            return TripDailyWeather(date: date, lowTemperatureCelsius: 11 + Double(offset % 3), highTemperatureCelsius: 22 + Double(offset % 4), precipitationChance: offset == 2 ? 0.65 : 0.1, uvIndex: 4,
                symbolName: offset == 2 ? "cloud.rain.fill" : "cloud.sun.fill", condition: offset == 2 ? "Rain" : "Partly Cloudy", precipitationMillimeters: offset == 2 ? 4 : 0,
                sunrise: c.date(bySettingHour: 7, minute: 0, second: 0, of: date), sunset: c.date(bySettingHour: 18, minute: 30, second: 0, of: date))
        }
        var forecast = DailyWeatherSnapshot(fetchedAt: now, currentTemperatureCelsius: 19, symbolName: "cloud.sun.fill", days: days,
            attribution: TripWeatherAttribution(legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!, lightMarkURL: URL(string: "https://weatherkit.apple.com/assets/branding/en/Apple_Weather_mark_Light.svg")!, darkMarkURL: URL(string: "https://weatherkit.apple.com/assets/branding/en/Apple_Weather_mark_Dark.svg")!))
        forecast.condition = "Partly Cloudy"; forecast.feelsLike = 18; forecast.humidity = 0.64; forecast.windKPH = 12; forecast.gustKPH = 18; forecast.uv = 3
        #if targetEnvironment(simulator)
        if enabled, ProcessInfo.processInfo.environment["LITTLE_WINDOWS_UI_TESTING"] == "1",
           let symbol = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_WEATHER_SCENE"],
           let condition = ["sun.max.fill": "Clear", "cloud.rain.fill": "Rain", "cloud.snow.fill": "Snow",
                            "cloud.bolt.rain.fill": "Thunderstorms", "wind": "Windy", "moon.stars.fill": "Clear" ][symbol] {
            forecast.symbolName = symbol; forecast.condition = condition
        }
        #endif
        for offset in 0..<240 {
            let date = start.addingTimeInterval(Double(offset) * 3600)
            let hour = c.component(.hour, from: date)
            let phase: Double = Double(hour - 8) / 24.0 * Double.pi * 2.0
            let temperature: Double = 17.0 + sin(phase) * 5.0
            let daylight = hour >= 7 && hour < 19
            let symbol = daylight ? "cloud.sun.fill" : "cloud.moon.fill"
            let uv = hour >= 10 && hour <= 16 ? 4 : 0
            let value = WeatherHour(date: date, temperature: temperature, feelsLike: temperature - 1,
                symbol: symbol, condition: "Partly Cloudy", rainChance: 0.1,
                precipitationMillimeters: 0, windKPH: 12, gustKPH: 18, uv: uv, daylight: daylight)
            forecast.hours.append(value)
        }
        var minutes: [WeatherMinute] = []
        for offset in 0..<60 {
            let rainy = offset > 20 && offset < 40
            minutes.append(WeatherMinute(date: now.addingTimeInterval(Double(offset) * 60),
                probability: rainy ? 0.5 : 0, intensityMMPerHour: rainy ? 1.5 : 0, type: "Rain"))
        }
        forecast.minutes = minutes
        forecast.minuteAvailability = "available"; forecast.minuteExpiresAt = now.addingTimeInterval(300); forecast.expiresAt = now.addingTimeInterval(1800)
        let profile = OutdoorProfileContext(id: profileID, name: "Sample Child", type: "child", activities: OutdoorActivity.options(type: "child", ageMonths: 6).map(\.rawValue), preferences: .defaults(for: "child"), contextUpdatedAt: now)
        return WeatherSurfaceState(city: "Sample City", timeZoneIdentifier: c.timeZone.identifier, fahrenheit: true, windUnit: "mph", precipitationUnit: "in", forecast: forecast, selectedProfileID: profileID, profiles: [profile])
    }
    static var slowDetailsEnabled: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["LITTLE_WINDOWS_WEATHER_SLOW_DETAILS"] == "1"
        #else
        false
        #endif
    }
    static var enabled: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["LITTLE_WINDOWS_WEATHER_PREVIEW"] == "1" || CommandLine.arguments.contains("--weather-preview")
        #else
        false
        #endif
    }
}
#endif
