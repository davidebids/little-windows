import SwiftUI
import WidgetKit

struct WeatherWidgetEntry: TimelineEntry {
    var date: Date
    var weather: WeatherSurfaceState?
    var profileID: UUID?
}
struct WeatherWidgetView: View {
    let entry: WeatherWidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    var body: some View {
        Group {
            if let weather = entry.weather {
                content(weather)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "cloud.sun.fill").font(.headline).accessibilityHidden(true)
                    Text("Choose a weather location in Little Windows.").font(.caption)
                }
            }
        }
        .widgetURL(destination)
    }
    private var destination: URL {
        var c = URLComponents(string: "littlewindows://weather")!
        if let id = entry.profileID { c.queryItems = [URLQueryItem(name: "profile", value: id.uuidString)] }
        return c.url!
    }
    @ViewBuilder private func content(_ w: WeatherSurfaceState) -> some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: w.forecast.symbolName)
                    Text(w.temperature(w.forecast.currentTemperatureCelsius)).font(.headline)
                    Text(w.city).font(.caption).lineLimit(1)
                }
                Text(w.forecast.isFresh(at: entry.date) ? w.forecast.condition : w.updatedLabel(at: entry.date)).font(.caption).lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: family == .systemMedium ? 4 : 8) {
                if family == .systemMedium {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.city).font(.caption.weight(.semibold)).lineLimit(1)
                            if let feels = w.forecast.feelsLike { Text("Feels like \(w.temperature(feels))").font(.system(size: 9)) }
                        }
                        Spacer(minLength: 0)
                        Text(w.temperature(w.forecast.currentTemperatureCelsius)).font(.system(size: 30, weight: .light, design: .rounded))
                        Image(systemName: w.forecast.symbolName).font(.title2).symbolRenderingMode(.multicolor).widgetAccentable()
                    }
                } else {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(w.city).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(w.temperature(w.forecast.currentTemperatureCelsius)).font(.system(size: family == .systemSmall ? 35 : 32, weight: .light, design: .rounded))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: w.forecast.symbolName).font(.title2).symbolRenderingMode(.multicolor).widgetAccentable()
                    }
                }
                if family == .systemSmall {
                    if let feels = w.forecast.feelsLike { Text("Feels like \(w.temperature(feels))").font(.caption2) }
                    if let day = w.forecast.day(for: entry.date, timeZone: w.timeZone) {
                        Text("H \(w.temperature(day.highTemperatureCelsius))  L \(w.temperature(day.lowTemperatureCelsius))").font(.caption2)
                    }
                } else {
                    hourly(w)
                    if let id = entry.profileID, let window = w.nextOutdoorWindow(profileID: id, now: entry.date) {
                        let name = w.profiles.first { $0.id == id }?.name ?? "Outdoor time"
                        Label("\(name) · \(w.time(window.start))–\(w.time(window.end))", systemImage: "sun.max")
                            .font(.caption2.weight(.semibold)).lineLimit(family == .systemMedium ? 1 : 2)
                    } else if family == .systemMedium {
                        Text(w.outlook(at: entry.date)).font(.caption2).lineLimit(1)
                    }
                    if family == .systemLarge {
                        Text(w.outlook(at: entry.date)).font(.caption).lineLimit(2)
                        ForEach(Array(w.forecast.days.filter { $0.date >= calendar(w).startOfDay(for: entry.date) }.prefix(3)), id: \.date) { day in
                            HStack {
                                Text(day.date.formatted(dayFormat(w))).frame(width: 40, alignment: .leading)
                                Image(systemName: day.symbolName).symbolRenderingMode(.multicolor)
                                Text("\(Int(day.precipitationChance * 100))%").foregroundStyle(.cyan)
                                Spacer()
                                Text("\(w.temperature(day.lowTemperatureCelsius)) / \(w.temperature(day.highTemperatureCelsius))")
                            }.font(.caption)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Text(w.forecast.isFresh(at: entry.date) ? w.updatedLabel(at: entry.date) : "Earlier forecast").lineLimit(1)
                    Spacer(minLength: 0)
                    Link(destination: w.forecast.attribution.legalPageURL) {
                        Image(systemName: "info.circle")
                    }.accessibilityLabel("Data sources")
                }.font(.system(size: 8)).foregroundStyle(.secondary)
            }.foregroundStyle(.white)
        }
    }
    private func hourly(_ w: WeatherSurfaceState) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(w.forecast.hours.filter { $0.date.addingTimeInterval(3600) > entry.date }.prefix(6))) { hour in
                VStack(spacing: family == .systemMedium ? 2 : 3) {
                    Text(w.time(hour.date)).font(.system(size: 8))
                    Image(systemName: hour.symbol).symbolRenderingMode(.multicolor).font(.caption2)
                    Text(w.temperature(hour.temperature)).font(.caption2.weight(.semibold))
                    Text("\(Int(hour.rainChance * 100))%").font(.system(size: 8)).foregroundStyle(.cyan)
                }.frame(maxWidth: .infinity)
            }
        }
    }
    private func calendar(_ w: WeatherSurfaceState) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = w.timeZone; return c }
    private func dayFormat(_ w: WeatherSurfaceState) -> Date.FormatStyle { var f = Date.FormatStyle().weekday(.abbreviated); f.timeZone = w.timeZone; return f }
}
