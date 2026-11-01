import XCTest
import SwiftUI
import WidgetKit
import SwiftData
import CoreLocation
import Accessibility
@testable import LittleWindows

final class WeatherForecastTests: XCTestCase {
    private let zone = TimeZone(secondsFromGMT: 0)!
    private var now: Date { ISO8601DateFormatter().date(from: "2026-10-31T09:00:00Z")! }
    @MainActor
    func testHourlyEqualitySkipsProfileEditsButRetainsForecastAndUnitChanges() {
        let original = state()
        let view = WeatherHourlyView(surface: original, hours: original.forecast.hours)
        var changed = original; changed.profiles[0].preferences.activity = "Picnic"
        XCTAssertEqual(view, WeatherHourlyView(surface: changed, hours: changed.forecast.hours))
        changed.fahrenheit.toggle()
        XCTAssertNotEqual(view, WeatherHourlyView(surface: changed, hours: changed.forecast.hours))
        changed = original; changed.forecast.hours[0].temperature += 1
        XCTAssertNotEqual(view, WeatherHourlyView(surface: changed, hours: changed.forecast.hours))
        changed = original; changed.timeZoneIdentifier = "America/New_York"
        XCTAssertNotEqual(view, WeatherHourlyView(surface: changed, hours: changed.forecast.hours))
    }
    func testLightweightPlotsRetainNativeAudioGraphDataAndExcludeInvalidSamples() throws {
        let points = [WeatherPlotPoint(date: now, value: 10), WeatherPlotPoint(date: now.addingTimeInterval(3600), value: 25),
            WeatherPlotPoint(date: now.addingTimeInterval(7200), value: .nan)]
        let descriptor = WeatherPlotAccessibility(points: points, range: 0...100, title: "Precipitation chance", unit: "%", timeZone: zone, bars: true).makeChartDescriptor()
        XCTAssertEqual(descriptor.series.count, 1)
        XCTAssertEqual(descriptor.series[0].dataPoints.count, 2)
        XCTAssertFalse(descriptor.series[0].isContinuous)
        XCTAssertEqual(descriptor.yAxis?.range, 0...100)
        let x = try XCTUnwrap(descriptor.xAxis as? AXNumericDataAxisDescriptor)
        XCTAssertEqual(x.range.lowerBound, now.timeIntervalSince1970)
        XCTAssertGreaterThan(x.range.upperBound, x.range.lowerBound)
    }
    func testPlotSelectionMatchesVisibleColumnsAndRejectsInvalidSamples() {
        let points = (0..<4).map { WeatherPlotPoint(date: now.addingTimeInterval(Double($0) * 3600), value: Double($0)) }
        XCTAssertEqual(WeatherPlotPoint.nearest(to: 0, width: 232, in: points), points[0])
        XCTAssertEqual(WeatherPlotPoint.nearest(to: 87, width: 232, in: points), points[1])
        XCTAssertEqual(WeatherPlotPoint.nearest(to: 232, width: 232, in: points), points[3])
        XCTAssertEqual(WeatherPlotPoint.nearest(to: -20, width: 232, in: points), points[0])
        XCTAssertEqual(WeatherPlotPoint.nearest(to: 300, width: 232, in: points), points[3])
        XCTAssertNil(WeatherPlotPoint.nearest(to: 20, width: 0, in: points))
        XCTAssertNil(WeatherPlotPoint.nearest(to: .nan, width: 232, in: points))
        XCTAssertNil(WeatherPlotPoint.nearest(to: 20, width: 232, in: []))
        XCTAssertNil(WeatherPlotPoint.nearest(to: 20, width: 232, in: [.init(date: now, value: .nan)]))
    }
    @MainActor
    func testWeatherPlotLayoutsAtNarrowWidthAndAccessibilitySizes() throws {
        let samples = (0..<60).map { WeatherPlotPoint(date: now.addingTimeInterval(Double($0) * 60), value: $0 < 30 ? Double($0) / 10 : 0) }
        for size in [DynamicTypeSize.large, .accessibility3] {
            let plot = WeatherForecastPlot(points: samples, range: 0...3, title: "Precipitation intensity", unit: "mm/h", timeZone: zone, bars: true)
                .padding(16).frame(width: 288).background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, size)
            let renderer = ImageRenderer(content: plot); renderer.scale = 3
            let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
            attachment.name = "Narrow precipitation plot \(size)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    private func state() -> WeatherSurfaceState {
        var s = WeatherPreviewData.make(now: now)
        s.timeZoneIdentifier = zone.identifier
        s.forecast.days[0].sunrise = now.addingTimeInterval(-3600)
        s.forecast.days[0].sunset = now.addingTimeInterval(9 * 3600)
        s.forecast.hours = (0..<9).map { offset in
            WeatherHour(date: now.addingTimeInterval(Double(offset) * 3600), temperature: 18, feelsLike: 18,
                symbol: "sun.max", condition: "Clear", rainChance: 0.1, precipitationMillimeters: 0,
                windKPH: 10, gustKPH: 15, uv: 3, daylight: true)
        }
        return s
    }
    @MainActor
    func testWidgetLayoutsRenderForAllSupportedSizes() throws {
        let sizes: [(WidgetFamily, CGFloat, CGFloat)] = [(.systemSmall, 158, 158), (.systemMedium, 338, 158), (.systemLarge, 338, 354), (.accessoryRectangular, 172, 76)]
        for (family, width, height) in sizes {
            let s = state()
            let entry = WeatherWidgetEntry(date: now, weather: s.widgetSnapshot(profileID: s.profiles[0].id, now: now), profileID: s.profiles[0].id)
            let view = WeatherWidgetView(entry: entry, familyOverride: family)
                .padding(12).frame(width: width, height: height)
                .background(Color(red: 0.09, green: 0.08, blue: 0.24)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width)
            XCTAssertEqual(image.size.height, height)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Weather widget \(family)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    @MainActor
    func testWeatherCurrentCardRendersConditionsAndAccessibleAppearance() throws {
        let variants: [(String, ColorScheme, DynamicTypeSize)] = [
            ("cloud.sun.fill", .light, .large), ("cloud.rain.fill", .light, .large),
            ("cloud.snow.fill", .dark, .large), ("wind", .dark, .large),
            ("cloud.sun.fill", .light, .accessibility3)]
        for (symbol, scheme, textSize) in variants {
            var s = state(); s.forecast.symbolName = symbol
            s.forecast.condition = ["cloud.rain.fill": "Rain", "cloud.snow.fill": "Snow", "wind": "Windy"][symbol] ?? "Partly Cloudy"
            let view = WeatherCurrentCard(surface: s, now: now, effectsEnabled: false)
                .padding(16).frame(width: 390).background(AppTheme.background)
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, textSize)
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 390)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Current conditions \(symbol) \(scheme) \(textSize)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testWeatherArtworkPreservesConditionWithWindAndNightVariants() {
        XCTAssertEqual(WeatherMotionKind(symbol: "cloud.snow.fill", windKPH: 50), .snow)
        XCTAssertEqual(WeatherMotionKind(symbol: "cloud.rain.fill", windKPH: 50), .rain)
        XCTAssertEqual(WeatherMotionKind(symbol: "cloud.bolt.rain.fill", windKPH: 50), .storm)
        XCTAssertEqual(WeatherMotionKind(symbol: "sun.max.fill", windKPH: 50), .sun)
        XCTAssertEqual(WeatherMotionKind(symbol: "cloud.moon.fill", windKPH: 0), .clouds)
        XCTAssertEqual(WeatherMotionKind(symbol: "sun.haze.fill", windKPH: 0), .fog)
        XCTAssertTrue(WeatherSceneConfiguration(symbol: "cloud.moon.rain.fill", windKPH: 12).night)
        XCTAssertFalse(WeatherSceneConfiguration(symbol: "cloud.sun.fill", windKPH: 12).night)
        XCTAssertEqual(WeatherSceneConfiguration(symbol: "wind", windKPH: .nan).wind, 0)
        XCTAssertEqual(WeatherSceneConfiguration(symbol: "wind", windKPH: 100).wind, 1)
    }
    @MainActor
    func testWeatherArtworkRendersDistinctFramesForEachConditionAndAppearance() throws {
        let symbols = ["sun.max.fill", "cloud.sun.fill", "cloud.fill", "cloud.rain.fill", "cloud.snow.fill", "wind", "moon.stars.fill", "cloud.moon.fill", "cloud.bolt.rain.fill", "cloud.fog.fill"]
        for scheme in [ColorScheme.light, .dark] {
            let gallery = VStack(spacing: 12) {
                ForEach(0..<5) { row in
                    HStack(spacing: 12) {
                        ForEach(0..<2) { column in
                            let symbol = symbols[row * 2 + column]
                            VStack {
                                WeatherAtmosphereArtwork(configuration: .init(symbol: symbol, windKPH: 32), time: 4)
                                    .frame(width: 150, height: 156)
                                Text(symbol).font(.caption2)
                            }.frame(width: 178).padding(.vertical, 8).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                }
            }.padding(16).background(AppTheme.background).environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: gallery); renderer.scale = 2
            let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
            attachment.name = "Weather artwork gallery \(scheme)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        for symbol in symbols {
            let configuration = WeatherSceneConfiguration(symbol: symbol, windKPH: 32)
            func pixels(_ time: Double) throws -> Data {
                let renderer = ImageRenderer(content: WeatherAtmosphereArtwork(configuration: configuration, time: time).frame(width: 144, height: 156))
                return try XCTUnwrap(renderer.uiImage?.pngData())
            }
            XCTAssertEqual(try pixels(4), try pixels(4), "Static artwork must be deterministic")
            XCTAssertNotEqual(try pixels(4), try pixels(5), "\(symbol) must animate through distinct frames")
        }
    }
    func testWindowRequiresFullHourAndAllParticipantLimits() {
        var s = state()
        let id = s.profiles[0].id
        XCTAssertEqual(s.outdoor(profileIDs: [id], day: now, now: now)?.end.timeIntervalSince(now), 3600)
        s.profiles[0].preferences.maximumWindKPH = 14
        XCTAssertNil(s.outdoor(profileIDs: [id], day: now, now: now))
        XCTAssertNil(state().outdoor(profileIDs: [], day: now, now: now))
        XCTAssertNil(state().outdoor(profileIDs: [UUID()], day: now, now: now))
    }
    func testGroupUsesIntersectionAndDisabledProfileSuppressesSuggestion() {
        var s = state(); var dog = s.profiles[0]; dog.id = UUID(); dog.type = "dog"
        dog.preferences.maximumRainChance = 0.05; s.profiles.append(dog)
        XCTAssertNil(s.outdoor(profileIDs: Set(s.profiles.map(\.id)), day: now, now: now))
        s.profiles[0].preferences.enabled = false
        XCTAssertNil(s.outdoor(profileIDs: [s.profiles[0].id], day: now, now: now))
    }
    func testFullHourImmediatelyAvailableBeforeSunsetIsNotLostToRounding() {
        var s = state()
        let start = now.addingTimeInterval(61)
        s.forecast.days[0].sunset = start.addingTimeInterval(3600)
        let window = s.outdoor(profileIDs: [s.profiles[0].id], day: now, now: start)
        XCTAssertEqual(window?.start, start)
        XCTAssertEqual(window?.end, s.forecast.days[0].sunset)
    }
    func testGapsAndShortDaylightNeverBecomeAnHour() {
        var s = state(); let id = s.profiles[0].id
        s.forecast.hours = [s.forecast.hours[0]]
        XCTAssertNil(s.outdoor(profileIDs: [id], day: now, now: now.addingTimeInterval(60)))
        s = state(); s.forecast.days[0].sunset = now.addingTimeInterval(3599)
        XCTAssertNil(s.outdoor(profileIDs: [id], day: now, now: now))
    }
    func testKnownBusyIntervalsExcludeAndSleepOnlyRanks() {
        var s = state(); let id = s.profiles[0].id
        s.profiles[0].busy = [.init(start: now, end: now.addingTimeInterval(3600))]
        XCTAssertGreaterThanOrEqual(s.outdoor(profileIDs: [id], day: now, now: now)!.start, now.addingTimeInterval(3600))
        s.profiles[0].busy = []
        s.profiles[0].predictedSleep = [.init(start: now, end: now.addingTimeInterval(9 * 3600))]
        XCTAssertNotNil(s.outdoor(profileIDs: [id], day: now, now: now))
    }
    func testStaleForecastAndExpiredRainAreSuppressed() {
        let s = state()
        XCTAssertNil(s.forecast.validMinutes(at: now.addingTimeInterval(301)))
        XCTAssertNil(s.outdoor(profileIDs: [s.profiles[0].id], day: now, now: now.addingTimeInterval(1801)))
        XCTAssertNotNil(s.forecast.validMinutes(at: now))
    }
    func testMinuteSummaryIncludesPossibleEndOnlyWhenCovered() {
        let s = state()
        XCTAssertTrue(s.rainSummary(at: now)?.contains("May ease around") == true)
        var continuous = s
        continuous.forecast.minutes = (0..<60).map { WeatherMinute(date: now.addingTimeInterval(Double($0) * 60), probability: 0.8, intensityMMPerHour: 1, type: "Rain") }
        XCTAssertFalse(continuous.rainSummary(at: now)?.contains("May ease") == true)
    }
    func testDryMinuteForecastDiffersFromExpectedSnowAndUnavailableData() {
        var s = state()
        s.forecast.minutes = [.init(date: now, probability: 0, intensityMMPerHour: 0, type: "Rain")]
        XCTAssertEqual(s.rainSummary(at: now), "Staying dry")
        XCTAssertFalse(s.forecast.validMinutes(at: now)!.contains { $0.hasExpectedPrecipitation })
        s.forecast.minutes = [.init(date: now, probability: 0.29, intensityMMPerHour: 1, type: "Rain")]
        XCTAssertEqual(s.rainSummary(at: now), "Staying dry")
        s.forecast.minutes = [.init(date: now, probability: 0.3, intensityMMPerHour: 1, type: "Snow")]
        XCTAssertTrue(s.forecast.validMinutes(at: now)!.contains { $0.hasExpectedPrecipitation })
        XCTAssertTrue(s.rainSummary(at: now)?.contains("snow possible") == true)
        s.forecast.minuteAvailability = "unsupported"
        XCTAssertNil(s.rainSummary(at: now))
        XCTAssertNil(s.forecast.validMinutes(at: now))
    }
    func testRainOutlookUsesPrecipitationTypeAndDoesNotDescribePastTiming() {
        var s = state()
        s.forecast.hours[0].rainChance = 0.7
        s.forecast.hours[0].precipitationType = "Snow"
        XCTAssertTrue(s.outlook(at: now.addingTimeInterval(600)).contains("Snow possible this hour"))
    }
    func testSmallForecastChangeRetainsValidSuggestion() {
        var s = state(); let id = s.profiles[0].id
        let previous = s.outdoor(profileIDs: [id], day: now, now: now)!
        s.forecast.hours[0].windKPH += 1
        XCTAssertEqual(s.outdoor(profileIDs: [id], day: now, now: now, previous: previous)?.start, previous.start)
    }
    func testOutdoorPreferencesMergeIndependentlyAndKeepActivityOverrides() {
        var first = CareTrackingPreferences(); var second = CareTrackingPreferences()
        first.set("outdoor.minimum", value: ["12"], now: now)
        second.set("outdoor.wind", value: ["20"], now: now)
        second.set("outdoor.activity", value: ["Walk"], now: now)
        let p = first.merging(second).outdoorPreferences(type: "dog")
        XCTAssertEqual(p.minimumCelsius, 12); XCTAssertEqual(p.maximumWindKPH, 20); XCTAssertEqual(p.activity, "Walk")
    }
    @MainActor
    func testExpandedActivitiesFollowProfileAndAgeWithoutReplacingSavedPreferences() throws {
        let container = try makeContainer(), defaults = try isolatedDefaults()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let baby = CareProfile(name: "Test Child", birthDate: calendar.date(byAdding: .month, value: -11, to: now))
        let toddler = CareProfile(name: "Sibling", birthDate: calendar.date(byAdding: .month, value: -24, to: now))
        let child = CareProfile(name: "Sample Child", birthDate: calendar.date(byAdding: .month, value: -48, to: now))
        let dog = CareProfile(profileType: .dog, name: "Test Dog")
        let adult = CareProfile(profileType: .adult, name: "Test Adult")
        for profile in [baby, toddler, child, dog, adult] { container.mainContext.insert(profile) }
        var saved = CareTrackingPreferences()
        saved.set("outdoor.activity", value: ["Blanket play"], now: now)
        saved.set("outdoor.wind", value: ["15"], now: now)
        defaults.set(try JSONEncoder().encode(saved), forKey: CareTrackingPreferenceStore.key(baby.id))
        try container.mainContext.save()
        func capture(_ profile: CareProfile) throws -> OutdoorProfileContext {
            try XCTUnwrap(OutdoorContextService.capture(context: container.mainContext, now: now, timeZone: zone,
                includeSchedule: false, defaults: defaults).first { $0.id == profile.id })
        }
        let infant = try capture(baby)
        XCTAssertTrue(infant.activities.contains("Blanket play"))
        XCTAssertFalse(infant.activities.contains("Playground"))
        XCTAssertFalse(try capture(toddler).activities.contains("Bike ride"))
        XCTAssertTrue(try capture(child).activities.contains("Bike ride"))
        XCTAssertTrue(try capture(dog).activities.contains("Sniff walk"))
        XCTAssertFalse(try capture(dog).activities.contains("Stroller walk"))
        XCTAssertTrue(try capture(adult).activities.contains("Gardening"))
        XCTAssertFalse(try capture(adult).activities.contains("Dog park"))
        XCTAssertEqual(infant.preferences.activity, "Blanket play")
        XCTAssertEqual(infant.preferences.maximumWindKPH, 15)
        baby.birthDate = calendar.date(byAdding: .month, value: -12, to: now)
        try container.mainContext.save()
        let older = try capture(baby)
        XCTAssertTrue(older.activities.contains("Playground"))
        XCTAssertEqual(older.preferences, infant.preferences)
        XCTAssertTrue(OutdoorActivity.pickerOptions(older.activities, selected: older.preferences.activity).contains("Blanket play"))
    }
    func testActivityPickerPreservesUnknownSyncedSelectionsAndCommonChoicesFirst() {
        let choices = OutdoorActivity.pickerOptions(["Walk", "Fetch", "Walk"], selected: "Future activity")
        XCTAssertEqual(choices, ["Walk", "Fetch", "Future activity"])
        XCTAssertEqual(OutdoorActivity.options(type: "dog", ageMonths: nil).first, .walk)
        XCTAssertEqual(OutdoorActivity.options(type: "child", ageMonths: 0).first, .strollerWalk)
        XCTAssertEqual(OutdoorActivity.options(type: "child", ageMonths: nil).first, .outdoorTime)
        XCTAssertEqual(OutdoorActivity.options(type: "adult", ageMonths: nil).first, .outdoorTime)
    }
    func testEveryExpandedActivityKeepsEditedWeatherLimitsAndSnapshotCompatibility() throws {
        for activity in OutdoorActivity.allCases {
            var s = state(); let id = s.profiles[0].id
            s.profiles[0].preferences.activity = activity.rawValue
            XCTAssertNotNil(s.outdoor(profileIDs: [id], day: now, now: now), activity.rawValue)
            let decoded = try JSONDecoder().decode(WeatherSurfaceState.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(decoded.watchSnapshot(profileID: id, now: now).profiles.first?.preferences.activity, activity.rawValue)
            XCTAssertEqual(decoded.widgetSnapshot(profileID: id, now: now).profiles.first?.preferences.activity, activity.rawValue)
            s.profiles[0].preferences.maximumWindKPH = 14
            XCTAssertNil(s.outdoor(profileIDs: [id], day: now, now: now), activity.rawValue)
        }
    }
    func testCanonicalUnitsDoNotChangeComfortLimits() {
        var s = state(); let original = s.profiles[0].preferences
        s.fahrenheit = false; s.windUnit = "km/h"; s.precipitationUnit = "mm"
        XCTAssertEqual(s.profiles[0].preferences, original)
        XCTAssertEqual(s.temperature(20), "20°")
        s.fahrenheit = true
        XCTAssertEqual(s.temperature(20), "68°")
    }
    func testSnapshotRoundTripAndOlderWatchPayloadCompatibility() throws {
        let s = state()
        XCTAssertEqual(try JSONDecoder().decode(WeatherSurfaceState.self, from: JSONEncoder().encode(s)), s)
        var watch = WatchCompanionState.empty; watch.weather = s
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(watch)) as? [String: Any])
        object.removeValue(forKey: "weather")
        let old = try JSONDecoder().decode(WatchCompanionState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.weather)
        XCTAssertTrue(AppNavigationPolicy.isHouseholdRoute(URL(string: "littlewindows://weather")!))
    }
    func testTonightUsesOvernightHoursAndLocationCalendar() {
        var s = state(); s.timeZoneIdentifier = "America/Los_Angeles"
        let night = ISO8601DateFormatter().date(from: "2026-11-01T01:00:00Z")!
        s.forecast.hours = (0..<15).map { offset in WeatherHour(date: night.addingTimeInterval(Double(offset) * 3600), temperature: 12, feelsLike: 11, symbol: "moon", condition: "Clear", rainChance: 0, precipitationMillimeters: 0, windKPH: 2, uv: 0, daylight: false) }
        XCTAssertEqual(s.tonight(at: now).first?.date, night)
        XCTAssertEqual(s.tonight(at: night.addingTimeInterval(1800)).first?.date, night)
        s.forecast.hours.remove(at: 5)
        XCTAssertTrue(s.tonight(at: now).isEmpty)
    }
    func testConflictingCloudLimitsPreserveDisabledStateAndNewestBound() {
        var p = CareTrackingPreferences()
        p.set("outdoor.enabled", value: ["false"], now: now)
        p.set("outdoor.activity", value: ["Walk"], now: now)
        p.set("outdoor.maximum", value: ["15"], now: now)
        p.set("outdoor.minimum", value: ["20"], now: now.addingTimeInterval(1))
        p.set("outdoor.rain", value: ["nan"], now: now)
        p.set("outdoor.wind", value: ["999"], now: now)
        p.set("outdoor.uv", value: ["-1"], now: now)
        let value = p.outdoorPreferences(type: "adult")
        XCTAssertFalse(value.enabled)
        XCTAssertEqual(value.activity, "Walk")
        XCTAssertEqual(value.minimumCelsius, 20)
        XCTAssertEqual(value.maximumCelsius, 20)
        XCTAssertEqual(value.maximumRainChance, 0.3)
        XCTAssertEqual(value.maximumWindKPH, 120)
        XCTAssertEqual(value.maximumUV, 0)
        XCTAssertTrue(value.isValid)
        XCTAssertFalse(p.needsSystemReconciliation(comparedTo: CareTrackingPreferences()))
    }
    func testMissingOrStaleProfileContextCannotProduceSuggestionFromFreshWidgetForecast() {
        var s = state(); let id = s.profiles[0].id
        s.profiles[0].contextUpdatedAt = nil
        XCTAssertNil(s.outdoor(profileIDs: [id], day: now, now: now))
        s.profiles[0].contextUpdatedAt = now.addingTimeInterval(-1800)
        XCTAssertNil(s.outdoor(profileIDs: [id], day: now, now: now))
        s.profiles[0].contextUpdatedAt = now.addingTimeInterval(61)
        XCTAssertNil(s.outdoor(profileIDs: [id], day: now, now: now))
    }
    func testWindowCanStartAtIrregularAppointmentEndBeforeSunset() {
        var s = state(); let id = s.profiles[0].id
        let end = now.addingTimeInterval(601)
        s.profiles[0].busy = [.init(start: now, end: end)]
        s.forecast.days[0].sunset = end.addingTimeInterval(3600)
        XCTAssertEqual(s.outdoor(profileIDs: [id], day: now, now: now)?.start, end)
    }
    func testInvalidForecastValuesNeverQualify() {
        for kind in 0..<4 {
            var s = state(); s.forecast.hours = [s.forecast.hours[0]]
            if kind == 0 { s.forecast.hours[0].gustKPH = .nan }
            if kind == 1 { s.forecast.hours[0].windKPH = -1 }
            if kind == 2 { s.forecast.hours[0].rainChance = -0.1 }
            if kind == 3 { s.forecast.hours[0].uv = -1 }
            XCTAssertNil(s.outdoor(profileIDs: [s.profiles[0].id], day: now, now: now))
        }
    }
    func testWidgetForecastMergeKeepsLatestSettingsAndOnlyMatchesSameLocation() {
        var primary = state(); primary.manualLatitude = 1; primary.manualLongitude = 2
        var widget = primary; widget.forecast.fetchedAt = now.addingTimeInterval(60)
        widget.fahrenheit = !primary.fahrenheit; widget.profiles = []
        let merged = primary.mergingWidgetForecast(widget)
        XCTAssertEqual(merged.forecast, widget.forecast)
        XCTAssertEqual(merged.fahrenheit, primary.fahrenheit)
        XCTAssertEqual(merged.profiles, primary.profiles)
        widget.manualLongitude = 3
        XCTAssertEqual(primary.mergingWidgetForecast(widget), primary)
        widget = primary; widget.timeZoneIdentifier = "America/Los_Angeles"
        widget.forecast.fetchedAt = now.addingTimeInterval(60)
        XCTAssertEqual(primary.mergingWidgetForecast(widget), primary)
        primary.manualLatitude = nil; primary.manualLongitude = nil
        XCTAssertEqual(primary.mergingWidgetForecast(widget), primary)
    }
    func testMinuteAvailabilityExpiryAndOrdering() {
        var forecast = state().forecast
        forecast.minutes = forecast.minutes?.reversed()
        let minutes = forecast.validMinutes(at: now)!
        XCTAssertEqual(minutes.map(\.date), minutes.map(\.date).sorted())
        forecast.minuteAvailability = "unsupported"
        XCTAssertNil(forecast.validMinutes(at: now))
        XCTAssertFalse(forecast.needsMinuteRefresh(at: now.addingTimeInterval(600)))
        forecast.minuteAvailability = "temporarilyUnavailable"
        XCTAssertTrue(forecast.needsMinuteRefresh(at: now.addingTimeInterval(301)))
        forecast.minuteAvailability = "available"; forecast.fetchedAt = now.addingTimeInterval(61)
        XCTAssertNil(forecast.validMinutes(at: now))
    }
    func testTimelineIncludesIndependentContextMinuteAndForecastExpiries() {
        var s = state()
        s.forecast.minuteExpiresAt = now.addingTimeInterval(123)
        s.forecast.expiresAt = now.addingTimeInterval(777)
        s.profiles[0].contextUpdatedAt = now.addingTimeInterval(-100)
        let dates = WeatherTimelinePolicy.entryDates(state: s, profileID: s.profiles[0].id, now: now)
        XCTAssertTrue(dates.contains(now.addingTimeInterval(123)))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(777)))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(1700)))
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
        XCTAssertTrue(dates.allSatisfy { $0 >= now && $0 <= now.addingTimeInterval(6 * 3600) })
    }
    func testTomorrowIsNotSuggestedWhenTodayHasNoWindow() {
        var s = state(); let tomorrow = now.addingTimeInterval(86400)
        var day = s.forecast.days[0]; day.date = tomorrow
        day.sunrise = tomorrow; day.sunset = tomorrow.addingTimeInterval(9 * 3600)
        s.forecast.days = [day]
        s.forecast.hours = s.forecast.hours.map { var h = $0; h.date = h.date.addingTimeInterval(86400); return h }
        let id = s.profiles[0].id
        XCTAssertNotNil(s.outdoor(profileIDs: [id], day: tomorrow, now: now))
        XCTAssertNil(s.nextOutdoorWindow(profileID: id, now: now))
        XCTAssertNil(s.watchSnapshot(profileID: id, now: now).nextOutdoorWindow(profileID: id, now: now))
        XCTAssertNil(s.widgetSnapshot(profileID: id, now: now).nextOutdoorWindow(profileID: id, now: now))
    }
    func testPartialHourlyOutlookDoesNotClaimTwelveHours() {
        let s = state()
        XCTAssertTrue(s.outlook(at: now).contains("available hourly forecast"))
        XCTAssertFalse(s.outlook(at: now).contains("12 hours"))
        XCTAssertFalse(s.outlook(at: now).contains("64°–64°"))
    }
    @MainActor
    func testInjectedUnitsAndUnconfiguredProfileMetadata() async throws {
        let defaults = try isolatedDefaults()
        defaults.set("km/h", forKey: "weather.windUnit"); defaults.set("mm", forKey: "weather.precipitationUnit")
        let store = DailyWeatherStore(defaults: defaults)
        XCTAssertEqual(store.windUnit, "km/h"); XCTAssertEqual(store.precipitationUnit, "mm")
        let container = try makeContainer()
        let profile = CareProfile(profileType: .adult, name: "Test Adult")
        container.mainContext.insert(profile); try container.mainContext.save()
        var preferences = CareTrackingPreferences(); preferences.set("outdoor.enabled", value: ["false"])
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(profile.id))
        store.updateContext(container.mainContext)
        for _ in 0..<50 where store.outdoorProfiles.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.outdoorProfiles.map(\.id), [profile.id])
        XCTAssertFalse(store.outdoorProfiles.first?.preferences.enabled ?? true)
        XCTAssertNil(store.outdoorProfiles.first?.contextUpdatedAt)
        XCTAssertNil(store.surface)
        store.refreshProfilePreferences()
        XCTAssertFalse(store.outdoorProfiles.first?.preferences.enabled ?? true)
    }
    @MainActor
    func testAppointmentCaptureScopesBeforeLimitAndSkipsPastOrUnknownIntervals() throws {
        let container = try makeContainer(); let context = container.mainContext
        let profile = CareProfile(profileType: .dog, name: "Test Dog")
        context.insert(profile)
        for index in 0..<505 {
            context.insert(DoctorAppointment(profileID: UUID(), title: "Test Appointment", startDate: now.addingTimeInterval(Double(index)), endDate: now.addingTimeInterval(3600)))
        }
        let start = now.addingTimeInterval(7200), end = now.addingTimeInterval(10800)
        context.insert(DoctorAppointment(profileID: profile.id, title: "Test Appointment", startDate: start, endDate: end))
        context.insert(DoctorAppointment(profileID: profile.id, title: "Past Appointment", startDate: now.addingTimeInterval(-7200), endDate: now.addingTimeInterval(-3600)))
        context.insert(DoctorAppointment(profileID: profile.id, title: "Unknown Duration", startDate: start))
        try context.save()
        let profiles = OutdoorContextService.capture(context: context, now: now, timeZone: zone, defaults: try isolatedDefaults())
        XCTAssertEqual(profiles.first?.busy, [.init(start: start, end: end)])
        XCTAssertNotNil(profiles.first?.contextUpdatedAt)
    }
    @MainActor
    func testAutomaticFailuresBackOffAndManualRetryStillWorks() async throws {
        let defaults = try isolatedDefaults(); let client = AuditWeatherClient(snapshot: state().forecast)
        let store = DailyWeatherStore(defaults: defaults, client: client)
        store.select(TripDestinationSelection(name: "Test City", latitude: 1, longitude: 2, timeZoneIdentifier: "UTC"))
        await client.setFailure(true)
        await store.refresh(); await store.refresh(); await store.refresh()
        let automaticCount = await client.count()
        XCTAssertEqual(automaticCount, 1)
        await client.setFailure(false); await store.refresh(force: true)
        let finalCount = await client.count()
        XCTAssertEqual(finalCount, 2); XCTAssertNotNil(store.snapshot); XCTAssertNil(store.failure)
    }
    @MainActor
    func testCurrentLocationMoveKeepsOldForecastWithOldCityUntilSuccess() async throws {
        let defaults = try isolatedDefaults(); let client = AuditWeatherClient(snapshot: state().forecast)
        let locator = AuditLocationClient()
        let store = DailyWeatherStore(defaults: defaults, client: client, locationClient: locator)
        await store.useCurrentLocation()
        XCTAssertEqual(store.location?.name, "First City")
        locator.city = "Second City"; await client.setFailure(true)
        await store.refresh(force: true)
        XCTAssertEqual(store.location?.name, "First City"); XCTAssertNotNil(store.snapshot)
        await client.setFailure(false); await store.refresh(force: true)
        XCTAssertEqual(store.location?.name, "Second City")
        XCTAssertNil(defaults.data(forKey: DailyWeatherStore.locationKey))
        XCTAssertNil(store.surface?.manualLatitude)
    }
    @MainActor
    func testMinuteSensitiveRefreshAndBackgroundRequestDoesNotAcquireLocation() async throws {
        let defaults = try isolatedDefaults(); let client = AuditWeatherClient(snapshot: state().forecast)
        let locator = AuditLocationClient()
        let store = DailyWeatherStore(defaults: defaults, client: client, locationClient: locator)
        await store.useCurrentLocation()
        let firstCount = locator.requests
        await store.refresh(now: now.addingTimeInterval(301), minuteSensitive: true, resolveCurrentLocation: false)
        let requests = await client.count()
        XCTAssertEqual(requests, 2); XCTAssertEqual(locator.requests, firstCount)
        let freshDefaults = try isolatedDefaults(); freshDefaults.set(true, forKey: DailyWeatherStore.currentLocationKey)
        let unloaded = DailyWeatherStore(defaults: freshDefaults, client: client, locationClient: locator)
        await unloaded.refresh(force: true, resolveCurrentLocation: false)
        XCTAssertEqual(locator.requests, firstCount)
        XCTAssertNil(unloaded.snapshot)
    }
    @MainActor
    func testPerProfileSleepContextRespectsPauseAndDestinationBedtime() throws {
        let container = try makeContainer(), defaults = try isolatedDefaults()
        let child = CareProfile(profileType: .child, name: "Test Child")
        let dog = CareProfile(profileType: .dog, name: "Test Dog")
        container.mainContext.insert(child); container.mainContext.insert(dog)
        for day in 1...3 {
            let start = now.addingTimeInterval(-Double(day) * 86400 + 11 * 3600)
            let event = CareEvent(profileID: child.id, type: .sleep, startDate: start, endDate: start.addingTimeInterval(8 * 3600))
            event.startTimeZoneIdentifier = "UTC"; event.sleepKind = .nightSleep
            container.mainContext.insert(event)
        }
        let walk = CareEvent(profileID: dog.id, type: .walk, startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(-1800))
        container.mainContext.insert(walk); try container.mainContext.save()
        let destination = TimeZone(identifier: "America/Los_Angeles")!
        let contexts = OutdoorContextService.capture(context: container.mainContext, now: now, timeZone: destination, defaults: defaults)
        let captured = try XCTUnwrap(contexts.first { $0.id == child.id })
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = destination
        XCTAssertTrue(captured.predictedSleep.contains { calendar.component(.hour, from: $0.start) == 20 })
        XCTAssertEqual(contexts.first { $0.id == dog.id }?.lastWalk, walk.startDate)
        var preferences = CareTrackingPreferences(); preferences.set("paused.sleep", value: ["true"])
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(child.id))
        preferences = CareTrackingPreferences(); preferences.set("paused.walk", value: ["true"])
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(dog.id))
        let paused = OutdoorContextService.capture(context: container.mainContext, now: now, timeZone: destination, defaults: defaults)
        XCTAssertTrue(try XCTUnwrap(paused.first { $0.id == child.id }).predictedSleep.isEmpty)
        XCTAssertNil(paused.first { $0.id == dog.id }?.lastWalk)
    }
    func testOlderWeatherContextStillDecodesWithoutProducingUnverifiedOuting() throws {
        let s = state()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        profiles[0].removeValue(forKey: "contextUpdatedAt"); object["profiles"] = profiles
        let decoded = try JSONDecoder().decode(WeatherSurfaceState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.forecast, s.forecast)
        XCTAssertNil(decoded.outdoor(profileIDs: [decoded.profiles[0].id], day: now, now: now))
        var watch = WatchCompanionState.empty; watch.weather = s
        XCTAssertFalse(watch.hasSameContent(as: .empty))
    }
    func testCompactWatchPayloadPreservesOutingsAndKeepsForecastSmall() throws {
        var full = WeatherPreviewData.make(now: now)
        full.manualLatitude = 1; full.manualLongitude = 2
        let id = full.profiles[0].id
        for _ in 0..<20 { var profile = full.profiles[0]; profile.id = UUID(); full.profiles.append(profile) }
        let compact = full.watchSnapshot(profileID: id, now: now)
        XCTAssertLessThanOrEqual(compact.forecast.hours.count, 49)
        XCTAssertLessThanOrEqual(compact.forecast.days.count, 2)
        XCTAssertEqual(compact.profiles.map(\.id), [id])
        XCTAssertNil(compact.manualLatitude); XCTAssertNil(compact.manualLongitude)
        XCTAssertNotNil(full.nextOutdoorWindow(profileID: id, now: now))
        XCTAssertEqual(compact.nextOutdoorWindow(profileID: id, now: now), full.nextOutdoorWindow(profileID: id, now: now))
        let tomorrow = now.addingTimeInterval(86400)
        XCTAssertNotNil(full.outdoor(profileIDs: [id], day: tomorrow, now: now))
        XCTAssertEqual(compact.outdoor(profileIDs: [id], day: tomorrow, now: now), full.outdoor(profileIDs: [id], day: tomorrow, now: now))
        let bytes = try JSONEncoder().encode(compact).count
        XCTAssertLessThan(bytes, 32_000, "Leave ample room for the companion's care state")
        XCTAssertTrue(full.watchSnapshot(profileID: nil, now: now).profiles.isEmpty)
        print("Compact Watch weather bytes: \(bytes)")
    }
    @MainActor
    func testContextReadsAreReusedForComfortEditsAndRefreshedForTrackingChanges() async throws {
        let defaults = try isolatedDefaults(), container = try makeContainer(), probe = WeatherContextProbe()
        let profile = state().profiles[0]
        let store = DailyWeatherStore(defaults: defaults, captureContext: { _, date, _, _, _ in probe.capture(profile, at: date) })
        for _ in 0..<50 { store.updateContext(container.mainContext, now: now) }
        for _ in 0..<100 where store.outdoorProfiles.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(probe.count, 1)
        XCTAssertFalse(probe.usedMainThread)
        var preferences = CareTrackingPreferences(); preferences.set("outdoor.wind", value: ["19"])
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(profile.id))
        XCTAssertFalse(store.refreshProfilePreferences())
        for _ in 0..<50 { store.updateContext(container.mainContext, now: now.addingTimeInterval(60)) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(store.outdoorProfiles.first?.preferences.maximumWindKPH, 19)
        preferences.set("paused.sleep", value: ["true"])
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(profile.id))
        XCTAssertTrue(store.refreshProfilePreferences())
        let refreshed = now.addingTimeInterval(61)
        store.updateContext(container.mainContext, now: refreshed)
        for _ in 0..<100 where store.outdoorProfiles.first?.contextUpdatedAt != refreshed { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(probe.count, 2)
        XCTAssertEqual(store.outdoorProfiles.first?.contextUpdatedAt, refreshed)
        store.updateContext(container.mainContext, now: refreshed.addingTimeInterval(301))
        for _ in 0..<100 where probe.count < 3 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(probe.count, 3)
    }
    @MainActor
    func testCareChangesDuringContextReadCoalesceWithoutParallelHistoryReads() async throws {
        let defaults = try isolatedDefaults(), container = try makeContainer(), probe = WeatherContextProbe(delay: 0.15)
        let profile = state().profiles[0]
        let store = DailyWeatherStore(defaults: defaults, captureContext: { _, date, _, _, _ in probe.capture(profile, at: date) })
        store.updateContext(container.mainContext, now: now)
        for _ in 0..<100 where probe.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        let updated = now.addingTimeInterval(1)
        for _ in 0..<50 { store.updateContext(container.mainContext, force: true, now: updated) }
        for _ in 0..<100 where store.outdoorProfiles.first?.contextUpdatedAt != updated { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(probe.count, 2)
        XCTAssertEqual(probe.maximumConcurrent, 1)
        XCTAssertEqual(store.outdoorProfiles.first?.contextUpdatedAt, updated)
    }
    @MainActor
    func testMinuteRefreshAvoidsFullForecastAndRepeatedLocationFixes() async throws {
        let defaults = try isolatedDefaults(), client = MinuteOnlyWeatherClient(snapshot: state().forecast), locator = AuditLocationClient()
        let store = DailyWeatherStore(defaults: defaults, client: client, locationClient: locator)
        await store.useCurrentLocation()
        await store.refresh(now: now.addingTimeInterval(301), minuteSensitive: true)
        await store.refresh(now: now.addingTimeInterval(302), minuteSensitive: true)
        await store.refresh(now: now.addingTimeInterval(550), minuteSensitive: true)
        let counts = await client.counts()
        XCTAssertEqual(counts.full, 1); XCTAssertEqual(counts.minute, 1)
        XCTAssertEqual(locator.requests, 1)
        XCTAssertEqual(store.snapshot?.fetchedAt, now)
        XCTAssertEqual(store.snapshot?.minuteFetchedAt, now.addingTimeInterval(301))
        await store.refresh(force: true, now: now.addingTimeInterval(550))
        let forced = await client.counts()
        XCTAssertEqual(forced.full, 2)
        XCTAssertEqual(locator.requests, 2)
    }
    func testMinuteFreshnessUsesItsOwnClockWithoutRefreshingBaseForecast() {
        var snapshot = state().forecast
        snapshot.minuteFetchedAt = now.addingTimeInterval(301)
        snapshot.minuteExpiresAt = now.addingTimeInterval(601)
        snapshot.minutes = snapshot.minutes?.map { var minute = $0; minute.date = minute.date.addingTimeInterval(301); return minute }
        XCTAssertFalse(snapshot.needsMinuteRefresh(at: now.addingTimeInterval(550)))
        XCTAssertNotNil(snapshot.validMinutes(at: now.addingTimeInterval(350)))
        XCTAssertTrue(snapshot.needsMinuteRefresh(at: now.addingTimeInterval(601)))
        XCTAssertEqual(snapshot.fetchedAt, now)
    }
    func testConcurrentForecastRequestsShareOneFlightAndFailuresCanRetry() async throws {
        let coordinator = WeatherForecastRequestCoordinator(), client = CountingForecastOperation(snapshot: state().forecast)
        let results = try await withThrowingTaskGroup(of: DailyWeatherSnapshot.self) { group in
            for _ in 0..<20 { group.addTask { try await coordinator.fetch(key: "test-city") { try await client.run() } } }
            var results: [DailyWeatherSnapshot] = []
            for try await result in group { results.append(result) }
            return results
        }
        let firstCount = await client.count
        XCTAssertEqual(firstCount, 1); XCTAssertEqual(results.count, 20)
        await client.setFailure(true)
        do { _ = try await coordinator.fetch(key: "test-city") { try await client.run() }; XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? URLError, URLError(.notConnectedToInternet)) }
        await client.setFailure(false)
        _ = try await coordinator.fetch(key: "test-city") { try await client.run() }
        let finalCount = await client.count
        XCTAssertEqual(finalCount, 3)
    }
    func testWidgetTimelineSkipsEmptyAndExpiredOutdoorRenders() {
        XCTAssertEqual(WeatherTimelinePolicy.entryDates(state: nil, profileID: nil, now: now), [now])
        var s = state(); let id = s.profiles[0].id
        let active = WeatherTimelinePolicy.entryDates(state: s, profileID: id, now: now)
        XCTAssertTrue(active.contains(now.addingTimeInterval(900)))
        XCTAssertFalse(active.contains(now.addingTimeInterval(2700)))
        s.profiles[0].contextUpdatedAt = nil
        let idle = WeatherTimelinePolicy.entryDates(state: s, profileID: id, now: now)
        XCTAssertFalse(idle.contains(now.addingTimeInterval(900)))
        XCTAssertTrue(idle.contains(now.addingTimeInterval(3600)))
        XCTAssertTrue(idle.contains(now.addingTimeInterval(1800)))
        XCTAssertLessThanOrEqual(idle.count, 10)
    }
    func testMergedParticipantSchedulesPreserveExactFirstFreeHour() {
        var s = state(); var other = s.profiles[0]; other.id = UUID()
        s.profiles[0].busy = [.init(start: now, end: now.addingTimeInterval(601))]
        let firstFree = now.addingTimeInterval(1234)
        other.busy = [.init(start: now.addingTimeInterval(500), end: firstFree)]
        s.profiles.append(other); s.forecast.days[0].sunset = firstFree.addingTimeInterval(3600)
        XCTAssertEqual(s.outdoor(profileIDs: Set(s.profiles.map(\.id)), day: now, now: now)?.start, firstFree)
    }
    func testCompactWidgetPayloadPreservesOutingAndThreeDayRows() throws {
        let full = WeatherPreviewData.make(now: now), id = WeatherPreviewData.profileID
        let compact = full.widgetSnapshot(profileID: id, now: now)
        XCTAssertEqual(compact.forecast.days.count, 3)
        XCTAssertLessThanOrEqual(compact.forecast.hours.count, 49)
        XCTAssertNil(compact.forecast.minutes)
        XCTAssertEqual(compact.nextOutdoorWindow(profileID: id, now: now), full.nextOutdoorWindow(profileID: id, now: now))
        let fullBytes = try JSONEncoder().encode(full).count, compactBytes = try JSONEncoder().encode(compact).count
        XCTAssertLessThan(compactBytes, fullBytes / 3)
    }
    func testMinuteOnlyChangesDoNotReloadWidgetsButAnyProfileOrUnitsChangeDoes() {
        let original = state()
        var changed = original
        changed.forecast.minutes = nil
        changed.forecast.minuteAvailability = "temporarilyUnavailable"
        changed.forecast.minuteFetchedAt = now.addingTimeInterval(300)
        changed.forecast.minuteExpiresAt = now.addingTimeInterval(600)
        XCTAssertTrue(changed.hasSameWidgetContent(as: original))
        changed.fahrenheit.toggle()
        XCTAssertFalse(changed.hasSameWidgetContent(as: original))
        changed = original; changed.profiles[0].preferences.maximumWindKPH += 1
        XCTAssertFalse(changed.hasSameWidgetContent(as: original))
        changed = original; changed.forecast.currentTemperatureCelsius += 1
        XCTAssertFalse(changed.hasSameWidgetContent(as: original))
    }
    func testCompactSurfacesKeepTomorrowAndThreeDailyRowsAcrossMidnight() throws {
        let late = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-31T23:50:00Z"))
        var full = WeatherPreviewData.make(now: late)
        full.timeZoneIdentifier = zone.identifier
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let midnight = calendar.startOfDay(for: late)
        full.forecast.days = full.forecast.days.enumerated().map { offset, original in
            var day = original; day.date = midnight.addingTimeInterval(Double(offset) * 86400)
            day.sunrise = day.date.addingTimeInterval(7 * 3600); day.sunset = day.date.addingTimeInterval(18 * 3600)
            return day
        }
        full.forecast.hours = full.forecast.hours.map { original in
            var hour = original; let clockHour = calendar.component(.hour, from: hour.date)
            hour.daylight = (7..<18).contains(clockHour); hour.feelsLike = 18; hour.uv = 0
            return hour
        }
        let id = full.profiles[0].id, later = late.addingTimeInterval(900)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: later))
        let expected = full.outdoor(profileIDs: [id], day: tomorrow, now: later)
        XCTAssertNotNil(expected)
        let watch = full.watchSnapshot(profileID: id, now: late)
        let widget = full.widgetSnapshot(profileID: id, now: late)
        XCTAssertEqual(watch.outdoor(profileIDs: [id], day: tomorrow, now: later), expected)
        XCTAssertEqual(widget.outdoor(profileIDs: [id], day: tomorrow, now: later), expected)
        let todayWindow = try XCTUnwrap(full.nextOutdoorWindow(profileID: id, now: later))
        XCTAssertTrue(calendar.isDate(todayWindow.start, inSameDayAs: later))
        XCTAssertEqual(watch.nextOutdoorWindow(profileID: id, now: later), todayWindow)
        XCTAssertEqual(widget.nextOutdoorWindow(profileID: id, now: later), todayWindow)
        XCTAssertEqual(widget.forecast.days.filter { $0.date >= calendar.startOfDay(for: later) }.count, 3)
    }
    @MainActor
    func testCurrentConditionsPublishBeforeSlowDetailsFinish() async throws {
        let client = ProgressiveWeatherProbe(full: state().forecast)
        let store = DailyWeatherStore(defaults: try isolatedDefaults(), client: client)
        store.select(TripDestinationSelection(name: "Test City", latitude: 1, longitude: 2, timeZoneIdentifier: "UTC"))
        let refresh = Task { await store.refresh(now: now) }
        for _ in 0..<100 where store.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.snapshot?.currentTemperatureCelsius, state().forecast.currentTemperatureCelsius)
        XCTAssertEqual(store.snapshot?.detailedForecastPending, true)
        XCTAssertTrue(store.snapshot?.hours.isEmpty == true)
        XCTAssertTrue(store.isLoading)
        await client.release()
        await refresh.value
        XCTAssertFalse(store.snapshot?.hours.isEmpty ?? true)
        XCTAssertEqual(store.snapshot?.detailedForecastPending, false)
        XCTAssertFalse(store.isLoading)
    }
    @MainActor
    func testIncompleteCurrentForecastRetriesEvenWhenCurrentConditionsAreFresh() async throws {
        let clock = Date(), full = WeatherPreviewData.make(now: Date()).forecast
        let client = ProgressiveWeatherProbe(full: full, failDetails: true)
        let store = DailyWeatherStore(defaults: try isolatedDefaults(), client: client)
        store.select(TripDestinationSelection(name: "Test City", latitude: 1, longitude: 2, timeZoneIdentifier: "UTC"))
        await client.release()
        await store.refresh(now: clock)
        XCTAssertTrue(try XCTUnwrap(store.snapshot).isFresh(at: clock))
        XCTAssertEqual(store.snapshot?.detailedForecastPending, true)
        XCTAssertNotNil(store.failure)
        await store.refresh(now: Date().addingTimeInterval(61))
        let count = await client.count
        XCTAssertEqual(count, 2, "Current-only data must not suppress the missing detailed forecast")
        await store.refresh(now: Date().addingTimeInterval(61))
        let backedOffCount = await client.count
        XCTAssertEqual(backedOffCount, 2, "A successful current phase must not reset repeated detail-failure backoff")
        await store.refresh(now: Date().addingTimeInterval(121))
        let retriedCount = await client.count
        XCTAssertEqual(retriedCount, 3)
    }
    @MainActor
    func testLateProgressiveResultsCannotRestoreAChangedLocation() async throws {
        let client = ProgressiveWeatherProbe(full: state().forecast)
        let store = DailyWeatherStore(defaults: try isolatedDefaults(), client: client)
        store.select(TripDestinationSelection(name: "First City", latitude: 1, longitude: 2, timeZoneIdentifier: "UTC"))
        let refresh = Task { await store.refresh(now: now) }
        for _ in 0..<100 where store.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
        store.select(TripDestinationSelection(name: "Second City", latitude: 3, longitude: 4, timeZoneIdentifier: "UTC"))
        await client.release()
        await refresh.value
        XCTAssertEqual(store.location?.name, "Second City")
        XCTAssertNil(store.snapshot)
    }
    @MainActor
    func testCityNameLookupDoesNotDelayWeatherAndCannotRenameANewSelection() async throws {
        let naming = SlowCityNameProbe()
        let store = DailyWeatherStore(defaults: try isolatedDefaults(), client: AuditWeatherClient(snapshot: state().forecast), locationClient: naming)
        await store.useCurrentLocation()
        XCTAssertNotNil(store.snapshot)
        XCTAssertEqual(store.location?.name, "Current location")
        XCTAssertEqual(naming.positionRequests, 1)
        XCTAssertEqual(naming.legacyCityRequests, 0)
        store.select(TripDestinationSelection(name: "Selected City", latitude: 3, longitude: 4, timeZoneIdentifier: "UTC"))
        await naming.gate.release()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.location?.name, "Selected City")
        XCTAssertNil(store.snapshot)
    }
    @MainActor
    func testResolvedCityNameArrivesAfterCurrentConditions() async throws {
        let naming = SlowCityNameProbe()
        let defaults = try isolatedDefaults()
        let store = DailyWeatherStore(defaults: defaults, client: AuditWeatherClient(snapshot: state().forecast), locationClient: naming)
        await store.useCurrentLocation()
        XCTAssertNotNil(store.snapshot)
        await naming.gate.release()
        for _ in 0..<100 where store.location?.name != "Resolved City" { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.location?.name, "Resolved City")
        XCTAssertNil(defaults.data(forKey: DailyWeatherStore.locationKey))
        XCTAssertNil(store.surface?.manualLatitude)
    }
    func testOnlyRecentUsableSystemLocationsCanAvoidAnotherFix() {
        let clock = Date()
        func position(age: TimeInterval, accuracy: Double) -> CLLocation {
            CLLocation(coordinate: .init(latitude: 0, longitude: 0), altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: clock.addingTimeInterval(-age))
        }
        XCTAssertTrue(LiveWeatherLocationClient.isUsableRecentPosition(position(age: 30, accuracy: 5000), now: clock))
        XCTAssertFalse(LiveWeatherLocationClient.isUsableRecentPosition(position(age: 121, accuracy: 100), now: clock))
        XCTAssertFalse(LiveWeatherLocationClient.isUsableRecentPosition(position(age: -61, accuracy: 100), now: clock))
        XCTAssertFalse(LiveWeatherLocationClient.isUsableRecentPosition(position(age: 0, accuracy: -1), now: clock))
        XCTAssertFalse(LiveWeatherLocationClient.isUsableRecentPosition(position(age: 0, accuracy: 10_001), now: clock))
    }
    @MainActor
    func testFreshCompleteForecastStaysVisibleDuringEarlyRefreshPhase() async throws {
        let client = ProgressiveWeatherProbe(full: state().forecast)
        let store = DailyWeatherStore(defaults: try isolatedDefaults(), client: client)
        store.select(TripDestinationSelection(name: "Test City", latitude: 1, longitude: 2, timeZoneIdentifier: "UTC"))
        await client.release()
        await store.refresh(now: now)
        await client.blockDetailsAgain()
        let refresh = Task { await store.refresh(force: true, now: now) }
        for _ in 0..<100 {
            if await client.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.snapshot?.detailedForecastPending, false)
        XCTAssertEqual(store.snapshot?.hours, state().forecast.hours)
        await client.release()
        await refresh.value
    }
    @MainActor
    func testConcurrentRefreshesShareTheSameProgressiveWeatherRequest() async throws {
        let client = ProgressiveWeatherProbe(full: state().forecast), clock = now
        let store = DailyWeatherStore(defaults: try isolatedDefaults(), client: client)
        store.select(TripDestinationSelection(name: "Test City", latitude: 1, longitude: 2, timeZoneIdentifier: "UTC"))
        let refreshes = Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<20 { group.addTask { await store.refresh(now: clock) } }
            }
        }
        for _ in 0..<100 where store.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
        let count = await client.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.snapshot?.detailedForecastPending, true)
        await client.release()
        await refreshes.value
    }
    @MainActor
    func testMovingCityCanShowNewCurrentConditionsBeforeItsDetails() async throws {
        let client = ProgressiveWeatherProbe(full: state().forecast), locator = AuditLocationClient()
        let store = DailyWeatherStore(defaults: try isolatedDefaults(), client: client, locationClient: locator)
        await client.release()
        await store.useCurrentLocation()
        XCTAssertEqual(store.location?.name, "First City")
        await client.blockDetailsAgain()
        locator.city = "Second City"; locator.latitude = 3; locator.longitude = 4
        let refresh = Task { await store.refresh(force: true, now: now) }
        for _ in 0..<100 where store.snapshot?.detailedForecastPending != true { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.location?.name, "Second City")
        XCTAssertEqual(store.snapshot?.detailedForecastPending, true)
        await client.release()
        await refresh.value
        XCTAssertEqual(store.location?.name, "Second City")
    }
    @MainActor
    func testOutdoorHistoryQueryPreservesPredictionWhileReadingOnlyRelevantRows() throws {
        let container = try makeContainer()
        let child = CareProfile(name: "Test Child", birthDate: now.addingTimeInterval(-180 * 86400))
        let other = CareProfile(name: "Sibling", birthDate: child.birthDate)
        container.mainContext.insert(child); container.mainContext.insert(other)
        for day in 0..<14 {
            for hour in [2, 6, 11, 20] {
                let start = now.addingTimeInterval(-Double(day * 24 + hour) * 3600)
                let event = CareEvent(profileID: child.id, type: .sleep, startDate: start, endDate: start.addingTimeInterval(3600))
                event.sleepKind = hour == 20 ? .nightSleep : .nap
                container.mainContext.insert(event)
            }
        }
        for index in 0..<1200 {
            let start = now.addingTimeInterval(-Double(index + 1) * 900)
            container.mainContext.insert(CareEvent(profileID: child.id, type: index % 2 == 0 ? .diaper : .feed,
                startDate: start, endDate: start.addingTimeInterval(60)))
        }
        container.mainContext.insert(CareEvent(profileID: child.id, type: .nursing, startDate: now.addingTimeInterval(-60), endDate: now))
        container.mainContext.insert(CareEvent(profileID: other.id, type: .sleep, startDate: now.addingTimeInterval(-60), endDate: now))
        try container.mainContext.save()
        let id = child.id, cutoff = now.addingTimeInterval(-14 * 86400), clock = now
        var original = FetchDescriptor<CareEvent>(predicate: #Predicate {
            $0.profileID == id && $0.startDate >= cutoff && $0.startDate <= clock
        }, sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        original.fetchLimit = 1500
        let all = EventVisibilityStore.visibleEvents(in: try container.mainContext.fetch(original))
        let relevant = OutdoorContextService.sleepContextEvents(context: container.mainContext, profileID: id, now: now, settings: .default)
        XCTAssertLessThan(relevant.count, all.count / 10)
        XCTAssertEqual(Set(relevant.filter { $0.type == .sleep }.map(\.id)), Set(all.filter { $0.type == .sleep }.map(\.id)))
        XCTAssertTrue(relevant.allSatisfy { $0.profileID == id })
        let before = try XCTUnwrap(SleepPredictionEngine.predict(profile: child, events: all, records: [], now: now))
        let after = try XCTUnwrap(SleepPredictionEngine.predict(profile: child, events: relevant, records: [], now: now))
        XCTAssertEqual(before.predictedStart, after.predictedStart)
        XCTAssertEqual(before.predictedWindowStart, after.predictedWindowStart)
        XCTAssertEqual(before.predictedWindowEnd, after.predictedWindowEnd)
        XCTAssertEqual(before.confidence, after.confidence)
        XCTAssertEqual(before.explanation, after.explanation)
        let timer = ContinuousClock()
        var originalTime: Duration = .zero, filteredTime: Duration = .zero
        for _ in 0..<5 {
            originalTime += try timer.measure {
                let context = ModelContext(container)
                let rows = try context.fetch(original)
                _ = rows.reduce(0) { $0 + ($1.isPredictionSleepBlock ? 1 : 0) }
            }
            filteredTime += timer.measure {
                _ = OutdoorContextService.sleepContextEvents(context: ModelContext(container), profileID: id, now: now, settings: .default)
            }
        }
        print("Outdoor history audit: rows \(all.count) -> \(relevant.count); five fresh-context reads \(originalTime) -> \(filteredTime)")
        var disabled = PredictionSettings.default
        disabled.feedAdjustmentEnabled = false; disabled.nursingAdjustmentEnabled = false
        let sleepOnly = OutdoorContextService.sleepContextEvents(context: container.mainContext, profileID: id, now: now, settings: disabled)
        XCTAssertTrue(sleepOnly.allSatisfy { $0.type == .sleep })
        // Unrelated recent volume must not displace older sleep history.
        for index in 0..<1600 {
            container.mainContext.insert(CareEvent(profileID: id, type: .diaper, startDate: now.addingTimeInterval(-Double(index)), endDate: now))
        }
        try container.mainContext.save()
        let crowded = OutdoorContextService.sleepContextEvents(context: ModelContext(container), profileID: id, now: now, settings: .default)
        XCTAssertEqual(Set(crowded.map(\.id)), Set(relevant.map(\.id)))
    }

    func testWatchWeatherUpdatesPreserveCareAndRejectLateSnapshots() throws {
        let coordinator = WatchStatePublicationCoordinator()
        var care = WatchCompanionState.empty
        care.generatedAt = now; care.selectedProfileID = state().profiles[0].id
        var sent: [WatchCompanionState] = []
        let deliver: (WatchCompanionState) -> Bool = { sent.append($0); return true }
        XCTAssertTrue(coordinator.publish(care, now: now, deliver: deliver))
        XCTAssertTrue(coordinator.publishWeather(state(), now: now.addingTimeInterval(1), deliver: deliver))
        let weatherUpdate = try XCTUnwrap(sent.last)
        XCTAssertEqual(weatherUpdate.activeTimers, care.activeTimers)
        XCTAssertEqual(weatherUpdate.todayMetrics, care.todayMetrics)
        XCTAssertNotNil(weatherUpdate.weather)
        XCTAssertNotEqual(weatherUpdate.revision, care.revision)
        // A care build started before the weather update still carries valid care.
        care.generatedAt = now.addingTimeInterval(0.5); care.selectedProfileID = UUID()
        XCTAssertTrue(coordinator.publish(care, now: now.addingTimeInterval(2), deliver: deliver))
        XCTAssertEqual(sent.last?.selectedProfileID, care.selectedProfileID)
        XCTAssertEqual(sent.last?.weather?.selectedProfileID, care.selectedProfileID)
        XCTAssertTrue(sent.last?.weather?.profiles.isEmpty == true)
        let count = sent.count
        var older = care; older.generatedAt = now.addingTimeInterval(-1)
        older.selectedProfileID = UUID()
        XCTAssertTrue(coordinator.publish(older, force: true, now: now, deliver: deliver))
        XCTAssertEqual(sent.count, count)
        XCTAssertTrue(coordinator.publishWeather(nil, now: now.addingTimeInterval(3), deliver: deliver))
        care.generatedAt = now.addingTimeInterval(4); care.weather = state()
        XCTAssertTrue(coordinator.publish(care, now: now.addingTimeInterval(4), deliver: deliver))
        XCTAssertNil(sent.last?.weather)
    }

    func testWatchWeatherBeforeInitialCareAndFailedDeliveryAreRetried() throws {
        let coordinator = WatchStatePublicationCoordinator()
        XCTAssertFalse(coordinator.publishWeather(state(), now: now, deliver: { _ in XCTFail("No care yet"); return true }))
        var care = WatchCompanionState.empty; care.generatedAt = now
        care.selectedProfileID = state().profiles[0].id
        XCTAssertFalse(coordinator.publish(care, now: now, deliver: { _ in false }))
        XCTAssertNil(coordinator.currentState)
        XCTAssertTrue(coordinator.publish(care, now: now, deliver: { XCTAssertNotNil($0.weather); return true }))
        XCTAssertTrue(coordinator.publishWeather(nil, now: now, deliver: { _ in false }))
        XCTAssertNotNil(coordinator.currentState?.weather)
        XCTAssertTrue(coordinator.publishWeather(nil, now: now, deliver: { XCTAssertNil($0.weather); return true }))
        XCTAssertNil(coordinator.currentState?.weather)
    }

    @MainActor
    func testBackgroundHomeSummaryMatchesRulesAndReflectsSavedEditsAndDeletes() async throws {
        let container = try makeContainer(), reader = TodayHomeSummaryReader()
        let householdID = UUID(), otherID = UUID()
        let list = HomeTodoList(householdID: householdID, name: "Test Tasks")
        let task = HomeTodoItem(householdID: householdID, todoListID: list.id, title: "Test task", updatedAt: now)
        let otherList = HomeTodoList(householdID: otherID, name: "Other Tasks")
        let otherTask = HomeTodoItem(householdID: otherID, todoListID: otherList.id, title: "Other task")
        for value in [list, otherList] { container.mainContext.insert(value) }
        for value in [task, otherTask] { container.mainContext.insert(value) }
        try container.mainContext.save()
        let expected = TodayHomeSummaryService.summary(householdID: householdID, currentCaregiverName: "",
            todoLists: [list], todoItems: [task], shoppingLists: [], shoppingItems: [], inventoryItems: [],
            mealPrepItems: [], mealPrepUsages: [], packingTrips: [], packingItems: [], itineraryItems: [],
            returnRequests: [], returnItems: [], returnPackages: [], reminders: [], now: now)
        let first = try await reader.read(container: container, householdID: householdID,
            currentCaregiverName: "", caregiverIdentifier: "", familySyncEnabled: false, now: now)
        XCTAssertEqual(first, expected)
        task.title = "Updated task"; task.updatedAt = now.addingTimeInterval(1)
        try container.mainContext.save()
        let edited = try await reader.read(container: container, householdID: householdID,
            currentCaregiverName: "", caregiverIdentifier: "", familySyncEnabled: false, now: now)
        XCTAssertEqual(edited?.sections.first { $0.category == .todos }?.items.first?.title, "Updated task")
        container.mainContext.delete(task); try container.mainContext.save()
        let deleted = try await reader.read(container: container, householdID: householdID,
            currentCaregiverName: "", caregiverIdentifier: "", familySyncEnabled: false, now: now)
        XCTAssertTrue(deleted?.sections.first { $0.category == .todos }?.items.isEmpty == true)
        let care = CareEvent(type: .diaper, startDate: now)
        container.mainContext.insert(care); try container.mainContext.save()
        XCTAssertFalse(TodayHomeSummaryReader.isRelevantSave(Notification(name: ModelContext.didSave,
            userInfo: [ModelContext.NotificationKey.insertedIdentifiers: [care.persistentModelID]])))
        XCTAssertTrue(TodayHomeSummaryReader.isRelevantSave(Notification(name: ModelContext.didSave,
            userInfo: [ModelContext.NotificationKey.updatedIdentifiers: [list.persistentModelID]])))
        XCTAssertTrue(TodayHomeSummaryReader.isRelevantSave(Notification(name: ModelContext.didSave)))
    }

    func testConcurrentWatchPublicationsStayOrderedAndDoNotOverlapDelivery() {
        let coordinator = WatchStatePublicationCoordinator()
        let probe = WatchDeliveryAuditProbe()
        let clock = now
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            var state = WatchCompanionState.empty
            state.generatedAt = clock.addingTimeInterval(Double(index))
            state.selectedProfileID = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))
            _ = coordinator.publish(state, force: true, now: clock, deliver: probe.deliver)
        }
        XCTAssertEqual(probe.maximumConcurrent, 1)
        XCTAssertEqual(coordinator.currentState?.generatedAt, clock.addingTimeInterval(99))
        XCTAssertEqual(coordinator.currentState?.selectedProfileID?.uuidString, "00000000-0000-0000-0000-000000000100")
    }

    @MainActor
    func testBackgroundSummarySnoozeReadsCannotLoseConcurrentUserEdits() throws {
        let defaults = try isolatedDefaults(), clock = now
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let key = "test-\(index)"
            HouseholdAttentionSnoozeStore.snooze(sourceKey: key, until: clock.addingTimeInterval(3600), now: clock, defaults: defaults)
            MedicationSnoozeStateStore.markSnoozed(occurrenceKey: key, until: clock.addingTimeInterval(3600), now: clock, defaults: defaults)
            _ = HouseholdAttentionSnoozeStore.activeSnoozes(now: clock, defaults: defaults)
            _ = MedicationSnoozeStateStore.activeOccurrenceKeys(now: clock, defaults: defaults)
        }
        XCTAssertEqual(HouseholdAttentionSnoozeStore.activeSnoozes(now: clock, defaults: defaults).count, 100)
        XCTAssertEqual(MedicationSnoozeStateStore.activeOccurrenceKeys(now: clock, defaults: defaults).count, 100)
    }

    @MainActor
    func testInstallationRecapturesContextEvenAfterARecentPreliminaryRead() async throws {
        let defaults = try isolatedDefaults(), container = try makeContainer()
        let probe = WeatherContextProbe(delay: 0.005), profile = state().profiles[0], clock = Date()
        let store = DailyWeatherStore(defaults: defaults, captureContext: { _, date, _, _, _ in probe.capture(profile, at: date) })
        store.updateContext(container.mainContext, now: clock)
        for _ in 0..<100 where store.outdoorProfiles.first?.contextUpdatedAt != clock { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(probe.count, 1)
        store.install(container: container)
        for _ in 0..<100 where probe.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(probe.count, 2, "Installation must not reuse a capture from before bootstrap finished")
        XCTAssertEqual(probe.maximumConcurrent, 1)
    }

    @MainActor private func isolatedDefaults() throws -> UserDefaults {
        let suite = "WeatherAudit-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
    @MainActor private func makeContainer() throws -> ModelContainer {
        let schema = PersistenceService.schema
        let configuration = ModelConfiguration("WeatherAudit-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

}

private actor AuditWeatherClient: DailyWeatherClient {
    private let snapshot: DailyWeatherSnapshot
    private var failure = false
    private var requests = 0
    init(snapshot: DailyWeatherSnapshot) { self.snapshot = snapshot }
    func setFailure(_ value: Bool) { failure = value }
    func count() -> Int { requests }
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot {
        requests += 1
        if failure { throw URLError(.notConnectedToInternet) }
        return snapshot
    }
}
@MainActor private final class AuditLocationClient: WeatherLocationClient {
    var city = "First City"
    var latitude = 1.0, longitude = 2.0
    var requests = 0
    func currentCity(requestAuthorization: Bool) async throws -> TripDestinationSelection {
        requests += 1
        return TripDestinationSelection(name: city, latitude: latitude, longitude: longitude, timeZoneIdentifier: "UTC")
    }
    func resolveCity(_ location: TripDestinationSelection) async throws -> TripDestinationSelection { location }
}

private final class WeatherContextProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0, concurrent = 0, maximum = 0
    private var main = false
    private let delay: TimeInterval
    init(delay: TimeInterval = 0.04) { self.delay = delay }
    var count: Int { lock.withLock { reads } }
    var maximumConcurrent: Int { lock.withLock { maximum } }
    var usedMainThread: Bool { lock.withLock { main } }
    func capture(_ profile: OutdoorProfileContext, at now: Date) -> [OutdoorProfileContext] {
        lock.withLock { reads += 1; concurrent += 1; maximum = max(maximum, concurrent); main = main || Thread.isMainThread }
        Thread.sleep(forTimeInterval: delay)
        var result = profile; result.contextUpdatedAt = now
        lock.withLock { concurrent -= 1 }
        return [result]
    }
}
private actor MinuteOnlyWeatherClient: DailyWeatherClient {
    let snapshot: DailyWeatherSnapshot
    private var full = 0, minute = 0
    init(snapshot: DailyWeatherSnapshot) { self.snapshot = snapshot }
    func counts() -> (full: Int, minute: Int) { (full, minute) }
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot { full += 1; return snapshot }
    func refreshMinutes(in snapshot: DailyWeatherSnapshot, latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot {
        minute += 1
        var result = snapshot
        result.minuteFetchedAt = snapshot.fetchedAt.addingTimeInterval(301)
        result.minuteExpiresAt = snapshot.fetchedAt.addingTimeInterval(601)
        return result
    }
}
private actor CountingForecastOperation {
    let snapshot: DailyWeatherSnapshot
    private(set) var count = 0
    private var failure = false
    init(snapshot: DailyWeatherSnapshot) { self.snapshot = snapshot }
    func setFailure(_ value: Bool) { failure = value }
    func run() async throws -> DailyWeatherSnapshot {
        count += 1
        try await Task.sleep(for: .milliseconds(50))
        if failure { throw URLError(.notConnectedToInternet) }
        return snapshot
    }
}

private actor ForecastTestGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
private actor ProgressiveWeatherProbe: DailyWeatherClient {
    let full: DailyWeatherSnapshot
    let failDetails: Bool
    private var gate = ForecastTestGate()
    private(set) var count = 0
    init(full: DailyWeatherSnapshot, failDetails: Bool = false) { self.full = full; self.failDetails = failDetails }
    func release() async { await gate.release() }
    func blockDetailsAgain() { gate = ForecastTestGate() }
    func fetch(latitude: Double, longitude: Double) async throws -> DailyWeatherSnapshot { full }
    func fetch(latitude: Double, longitude: Double, onUpdate: @escaping @Sendable (DailyWeatherSnapshot) async -> Void) async throws -> DailyWeatherSnapshot {
        count += 1
        var current = full; current.hours = []; current.minutes = nil; current.detailedForecastPending = true
        await onUpdate(current)
        await gate.wait()
        if failDetails { throw URLError(.notConnectedToInternet) }
        var complete = full; complete.detailedForecastPending = false
        await onUpdate(complete)
        return complete
    }
}
@MainActor private final class SlowCityNameProbe: WeatherLocationClient {
    let gate = ForecastTestGate()
    var positionRequests = 0, legacyCityRequests = 0
    func currentPosition(requestAuthorization: Bool) async throws -> TripDestinationSelection {
        positionRequests += 1
        return TripDestinationSelection(name: "Current location", latitude: 1, longitude: 2, timeZoneIdentifier: "UTC")
    }
    func currentCity(requestAuthorization: Bool) async throws -> TripDestinationSelection {
        legacyCityRequests += 1
        throw WeatherLocationFailure.unavailable
    }
    func resolveCity(_ location: TripDestinationSelection) async throws -> TripDestinationSelection {
        await gate.wait()
        var result = location; result.name = "Resolved City"
        return result
    }
}

private final class WatchDeliveryAuditProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0, maximum = 0
    var maximumConcurrent: Int { lock.withLock { maximum } }
    func deliver(_ state: WatchCompanionState) -> Bool {
        lock.withLock { active += 1; maximum = max(maximum, active) }
        Thread.sleep(forTimeInterval: 0.001)
        lock.withLock { active -= 1 }
        return true
    }
}
