import Charts
import SwiftUI

struct WatchWeatherView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    @State private var showingSources = false
    var body: some View {
        Group {
            if let weather = connectivity.state.weather { content(weather) }
            else { ContentUnavailableView("No forecast", systemImage: "cloud.sun", description: Text("Choose a location in the iPhone app.")) }
        }
        .navigationTitle("Weather")
        .onChange(of: connectivity.state.weather == nil) { _, missing in if missing { showingSources = false } }
        .sheet(isPresented: $showingSources) {
            if let weather = connectivity.state.weather { sources(weather) }
        }
    }
    private func content(_ weather: WeatherSurfaceState) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(weather.city).font(.headline)
                    Label(weather.temperature(weather.forecast.currentTemperatureCelsius), systemImage: weather.forecast.symbolName)
                        .font(.largeTitle).symbolRenderingMode(.multicolor)
                    if let feels = weather.forecast.feelsLike { Text("Feels like \(weather.temperature(feels))").font(.caption) }
                    Text(weather.outlook(at: now)).font(.caption)
                    if let rain = weather.rainSummary(at: now) { Text(rain).font(.caption).foregroundStyle(.cyan) }
                    let hours = Array(weather.forecast.hours.filter { $0.date.addingTimeInterval(3600) > now }.prefix(6))
                    if !hours.isEmpty {
                        Chart(hours) { hour in
                            LineMark(x: .value("Time", hour.date), y: .value("Temperature", weather.fahrenheit ? hour.temperature * 9 / 5 + 32 : hour.temperature))
                                .foregroundStyle(.indigo).interpolationMethod(.monotone)
                        }.frame(height: 85).chartXAxis(.hidden)
                        ForEach(hours) { hour in
                            HStack {
                                Text(weather.time(hour.date))
                                Image(systemName: hour.symbol).symbolRenderingMode(.multicolor)
                                Spacer(minLength: 2)
                                Text(weather.temperature(hour.temperature))
                                Text("\(Int(hour.rainChance * 100))%").foregroundStyle(.cyan)
                            }.font(.caption2).accessibilityElement(children: .combine)
                        }
                    }
                    if let id = connectivity.state.selectedProfileID,
                       let window = weather.nextOutdoorWindow(profileID: id, now: now) {
                        Divider()
                        Text("Outdoor time today").font(.caption.weight(.semibold))
                        Text("\(weather.time(window.start))–\(weather.time(window.end))").font(.headline)
                        Text("Feels like \(weather.temperature(window.lowFeelsLike))–\(weather.temperature(window.highFeelsLike)) · \(Int(window.rainChance * 100))% precipitation · Wind \(weather.wind(window.windKPH)) · UV \(window.uv)").font(.caption2)
                    }
                    Text(weather.updatedLabel(at: now)).font(.caption2).foregroundStyle(.secondary)
                    if !weather.forecast.isFresh(at: now) { Text("Earlier forecast · Open the iPhone app to update.").font(.caption2).foregroundStyle(.secondary) }
                    Button("Data sources", systemImage: "info.circle") { showingSources = true }
                        .font(.caption2)
                }.padding(.horizontal, 4)
            }
        }
        .refreshable { connectivity.requestRefresh() }
    }
    private func sources(_ weather: WeatherSurfaceState) -> some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Apple Weather").font(.headline)
                        Text(weather.forecast.attribution.legalAttributionText.isEmpty
                            ? "Forecast and current conditions provided by Apple Weather."
                            : weather.forecast.attribution.legalAttributionText)
                        Link("Data sources", destination: weather.forecast.attribution.legalPageURL)
                    }
                }
                .navigationTitle("Data Sources")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSources = false } } }
            }
    }
}
