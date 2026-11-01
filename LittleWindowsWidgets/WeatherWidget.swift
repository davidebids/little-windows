import AppIntents
import SwiftUI
import WidgetKit

struct WeatherWidgetProfile: AppEntity {
    var id: String
    var name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Care profile"
    static var defaultQuery = WeatherWidgetProfileQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct WeatherWidgetProfileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WeatherWidgetProfile] {
        let profiles = try await suggestedEntities()
        return identifiers.map { id in
            profiles.first { $0.id == id } ?? WeatherWidgetProfile(id: id, name: "Unavailable profile")
        }
    }
    func suggestedEntities() async throws -> [WeatherWidgetProfile] {
        WeatherSurfaceCache.read()?.profiles.map { WeatherWidgetProfile(id: $0.id.uuidString, name: $0.name) } ?? []
    }
}
struct WeatherWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Weather"
    static var description = IntentDescription("Show the weather and an optional profile's outdoor time.")
    @Parameter(title: "Outdoor profile", description: "Leave empty to follow the selected profile.") var profile: WeatherWidgetProfile?
}
struct WeatherWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WeatherWidgetEntry { .init(date: Date(), weather: nil, profileID: nil) }
    func snapshot(for configuration: WeatherWidgetConfiguration, in context: Context) async -> WeatherWidgetEntry {
        let state = WeatherSurfaceCache.read()
        let now = Date(), profileID = resolvedProfile(configuration, state)
        return .init(date: now, weather: state?.widgetSnapshot(profileID: profileID, now: now), profileID: profileID)
    }
    func timeline(for configuration: WeatherWidgetConfiguration, in context: Context) async -> Timeline<WeatherWidgetEntry> {
        var state = WeatherSurfaceCache.read()
        let now = Date()
        // A widget may refresh a manually chosen city without accessing care data
        // or requesting location permission. Current-location fixes remain foreground-only.
        if let original = state, (!original.forecast.isFresh(at: now) || (original.forecast.detailedForecastPending == true && now.timeIntervalSince(original.forecast.fetchedAt) >= 60)),
           let latitude = original.manualLatitude, let longitude = original.manualLongitude,
           let forecast = try? await WeatherForecastClient.fetch(latitude: latitude, longitude: longitude, includeMinutes: false) {
            if let latest = WeatherSurfaceCache.read(), latest.city == original.city,
               latest.manualLatitude == latitude, latest.manualLongitude == longitude,
               latest.timeZoneIdentifier == original.timeZoneIdentifier {
                var refreshed = original
                refreshed.forecast = forecast
                state = latest.mergingWidgetForecast(refreshed)
                // Separate cache avoids replacing the app's preference/context snapshot.
                if let state, let data = try? JSONEncoder().encode(state), let url = widgetForecastURL { try? data.write(to: url, options: .atomic) }
            } else { state = WeatherSurfaceCache.read() }
        }
        let profileID = resolvedProfile(configuration, state)
        let presentation = state?.widgetSnapshot(profileID: profileID, now: now)
        let entries = WeatherTimelinePolicy.entryDates(state: presentation, profileID: profileID, now: now).map {
            WeatherWidgetEntry(date: $0, weather: presentation, profileID: profileID)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(state?.forecast.detailedForecastPending == true ? 60 : 1800)))
    }
    private func resolvedProfile(_ configuration: WeatherWidgetConfiguration, _ state: WeatherSurfaceState?) -> UUID? {
        if let configured = configuration.profile { return UUID(uuidString: configured.id) }
        return state?.selectedProfileID
    }
    private var widgetForecastURL: URL? { WeatherSurfaceCache.widgetForecastURL }
}
struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LittleWindows.Weather", intent: WeatherWidgetConfiguration.self, provider: WeatherWidgetProvider()) { entry in
            WeatherWidgetView(entry: entry)
                .containerBackground(for: .widget) { LittleWindowsWidgetStyle.background }
        }
        .configurationDisplayName("Weather & Outdoor Time")
        .description("Current conditions, hourly weather, and personalized outdoor opportunities.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
