import Foundation
import SwiftData

extension CareTrackingPreferences {
    func outdoorPreferences(type: String) -> OutdoorPreferences {
        var p = OutdoorPreferences.defaults(for: type)
        func number(_ key: String, _ fallback: Double) -> Double { fields["outdoor." + key]?.value.first.flatMap(Double.init) ?? fallback }
        p.enabled = fields["outdoor.enabled"]?.value.first != "false"
        p.activity = fields["outdoor.activity"]?.value.first ?? p.activity
        p.minimumCelsius = number("minimum", p.minimumCelsius).finiteClamped(to: -40...50, fallback: p.minimumCelsius)
        p.maximumCelsius = number("maximum", p.maximumCelsius).finiteClamped(to: -40...50, fallback: p.maximumCelsius)
        if p.minimumCelsius > p.maximumCelsius {
            if let minimum = fields["outdoor.minimum"], let maximum = fields["outdoor.maximum"], minimum.isNewer(than: maximum) {
                p.maximumCelsius = p.minimumCelsius
            } else { p.minimumCelsius = p.maximumCelsius }
        }
        p.maximumRainChance = number("rain", p.maximumRainChance).finiteClamped(to: 0...1, fallback: p.maximumRainChance)
        p.maximumWindKPH = number("wind", p.maximumWindKPH).finiteClamped(to: 0...120, fallback: p.maximumWindKPH)
        p.maximumUV = Int(number("uv", Double(p.maximumUV)).finiteClamped(to: 0...15, fallback: Double(p.maximumUV)))
        return p
    }
}

private extension Double {
    func finiteClamped(to range: ClosedRange<Double>, fallback: Double) -> Double {
        isFinite ? min(max(self, range.lowerBound), range.upperBound) : fallback
    }
}

enum OutdoorContextService {
    static func capture(context: ModelContext, now: Date = Date(), timeZone: TimeZone = .current,
                        includeSchedule: Bool = true, defaults: UserDefaults = .standard) -> [OutdoorProfileContext] {
        let fetched = (try? context.fetch(FetchDescriptor<CareProfile>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        var seen = Set<UUID>()
        let profiles = fetched.filter { seen.insert($0.id).inserted }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let cutoff = now.addingTimeInterval(-14 * 86400)
        let until = calendar.date(byAdding: .day, value: 3, to: now) ?? now.addingTimeInterval(3 * 86400)
        let settings = predictionSettings(defaults: defaults)
        return profiles.map { profile in
            let id = profile.id
            let type = profile.profileType.rawValue
            let preferences = CareTrackingPreferenceStore.preferences(profileID: id, defaults: defaults)
            let months = profile.birthDate.map { calendar.dateComponents([.month], from: $0, to: now).month ?? 0 }
            let activities = OutdoorActivity.options(type: type, ageMonths: months).map(\.rawValue)
            var sleep: [WeatherBusyInterval] = []
            var busy: [WeatherBusyInterval] = []
            var lastWalk: Date?
            var scheduleComplete = false
            if includeSchedule && preferences.outdoorPreferences(type: type).enabled {
                var appointmentQuery = FetchDescriptor<DoctorAppointment>(predicate: #Predicate {
                    $0.profileID == id && !$0.isCompleted && $0.startDate < until && ($0.endDate ?? now) > now
                }, sortBy: [SortDescriptor(\.startDate)])
                appointmentQuery.fetchLimit = 501
                if let appointments = try? context.fetch(appointmentQuery), appointments.count < 501 {
                    busy = appointments.compactMap {
                        guard let end = $0.endDate, end > $0.startDate else { return nil }
                        return WeatherBusyInterval(start: $0.startDate, end: end)
                    }
                    scheduleComplete = true
                }
                if preferences.allowsPrompts(.sleepPlan), profile.profileType == .child {
                    let events = sleepContextEvents(context: context, profileID: id, now: now, settings: settings)
                    var recordsQuery = FetchDescriptor<SleepPredictionRecord>(predicate: #Predicate {
                        $0.profileID == id && $0.generatedAt >= cutoff
                    }, sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])
                    recordsQuery.fetchLimit = 200
                    let records = (try? context.fetch(recordsQuery)) ?? []
                    if let prediction = SleepPredictionEngine.predict(profile: profile, events: events, records: records, now: now, calendar: calendar, settings: settings),
                       prediction.confidenceLabel != .low, prediction.predictedWindowEnd > now {
                        sleep.append(.init(start: prediction.predictedWindowStart, end: prediction.predictedWindowEnd))
                    }
                    if events.contains(where: { $0.isSleepBlock && $0.isTimerRunning }) {
                        sleep.append(.init(start: now, end: now.addingTimeInterval(3600)))
                    }
                    let nights = events.filter { $0.isPredictionSleepBlock && !$0.isTimerDraft && $0.sleepKind == .nightSleep && $0.endDate != nil }
                    let eveningMinutes = nights.map { event -> Int in
                        var logged = calendar; logged.timeZone = event.startTimeZone
                        return logged.component(.hour, from: event.startDate) * 60 + logged.component(.minute, from: event.startDate)
                    }.filter { $0 >= 16 * 60 }.sorted()
                    if eveningMinutes.count >= 3 {
                        let minute = eveningMinutes[eveningMinutes.count / 2]
                        for offset in 0...1 {
                            if let day = calendar.date(byAdding: .day, value: offset, to: now),
                               let bedtime = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                               let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) {
                                sleep.append(.init(start: bedtime, end: end))
                            }
                        }
                    }
                }
                if preferences.allows(.walk) {
                    var query = FetchDescriptor<CareEvent>(predicate: #Predicate {
                        $0.profileID == id && $0.typeRawValue == "walk" && $0.startDate <= now && $0.endDate != nil
                    }, sortBy: [SortDescriptor(\.startDate, order: .reverse)])
                    query.fetchLimit = 20
                    lastWalk = EventVisibilityStore.visibleEvents(in: (try? context.fetch(query)) ?? []).first?.startDate
                }
            }
            var outdoor = preferences.outdoorPreferences(type: type)
            if preferences.fields["outdoor.activity"] == nil { outdoor.activity = activities.first ?? "Outdoor time" }
            return OutdoorProfileContext(id: id, name: profile.name, type: type, activities: activities,
                preferences: outdoor, busy: busy, predictedSleep: sleep, lastWalk: lastWalk,
                contextUpdatedAt: scheduleComplete ? Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 300) * 300) : nil)
        }
    }

    /// Only sleep history and the predictor's recent feeding confidence signal
    /// contribute to this context. Filtering in the store avoids faulting every
    /// diaper, measurement, and activity, and keeps those rows from displacing sleep.
    static func sleepContextEvents(context: ModelContext, profileID: UUID, now: Date,
                                   settings: PredictionSettings) -> [CareEvent] {
        let cutoff = now.addingTimeInterval(-14 * 86400)
        let recentCareCutoff = now.addingTimeInterval(-90 * 60)
        var sleepQuery = FetchDescriptor<CareEvent>(predicate: #Predicate {
            $0.profileID == profileID && $0.typeRawValue == "sleep" &&
                $0.startDate <= now && ($0.startDate >= cutoff || $0.endDate == nil)
        }, sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        sleepQuery.fetchLimit = 1500
        var events = (try? context.fetch(sleepQuery)) ?? []
        let feedType = settings.feedAdjustmentEnabled ? "feed" : ""
        let nursingType = settings.nursingAdjustmentEnabled ? "nursing" : ""
        if !feedType.isEmpty || !nursingType.isEmpty {
            var careQuery = FetchDescriptor<CareEvent>(predicate: #Predicate {
                $0.profileID == profileID && $0.startDate >= recentCareCutoff && $0.startDate <= now &&
                    ($0.typeRawValue == feedType || $0.typeRawValue == nursingType)
            }, sortBy: [SortDescriptor(\.startDate, order: .reverse)])
            careQuery.fetchLimit = 100
            events += (try? context.fetch(careQuery)) ?? []
        }
        return EventVisibilityStore.visibleEvents(in: events).sorted { $0.startDate > $1.startDate }
    }

    private static func predictionSettings(defaults: UserDefaults) -> PredictionSettings {
        func enabled(_ key: String) -> Bool { defaults.object(forKey: key) == nil || defaults.bool(forKey: key) }
        func positive(_ key: String) -> Double? { let value = defaults.double(forKey: key); return value.isFinite && value > 0 ? value : nil }
        return PredictionSettings(feedAdjustmentEnabled: enabled("feedAdjustmentEnabled"),
            nursingAdjustmentEnabled: enabled("nursingAdjustmentEnabled"), bedtimePredictionEnabled: enabled("bedtimePredictionEnabled"),
            customBaselineMinimum: positive("customWakeMinimum"), customBaselineMaximum: positive("customWakeMaximum"))
    }
}
