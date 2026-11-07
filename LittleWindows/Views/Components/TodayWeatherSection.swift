import SwiftUI
import SwiftData

/// Compact weather context presented with the Today greeting.
struct TodayWeatherHeader: View {
    @ObservedObject private var weather = DailyWeatherStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    let chooseCity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: chooseCity) {
                HStack(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { cityLabel; temperatureSummary }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 5) { cityLabel; temperatureSummary }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 44, alignment: .leading)
                .background(AppTheme.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .appSurface(cornerRadius: 14)
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open weather forecast")
            .accessibilityValue(weather.snapshot?.detailedForecastPending == true ? "Updating forecast" : "")
            .accessibilityIdentifier("today.weather.header")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task(id: weather.requestID) {
            weather.updateContext(modelContext)
            await weather.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30 * 60)) } catch { return }
                if scenePhase == .active { await weather.refresh() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { weather.updateContext(modelContext); await weather.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)) { _ in weather.updateContext(modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: SystemIntegrationReconciler.reconciliationRequestedNotification)) { _ in weather.updateContext(modelContext) }
        .contextMenu {
            Button("Weather location", systemImage: "location") { chooseCity() }
        }
    }

    private var cityLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: weather.snapshot?.symbolName ?? (weather.usesCurrentLocation ? "location.fill" : "cloud.sun.fill"))
                .font(.subheadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.accent)
                .fixedSize()
                .accessibilityHidden(true)
            Text(weather.location?.name ?? (weather.usesCurrentLocation ? "Current location" : "Set weather location"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var temperatureSummary: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            temperatureSummary(at: timeline.date)
        }
    }

    @ViewBuilder private func temperatureSummary(at now: Date) -> some View {
        if let snapshot = weather.snapshot,
           let day = snapshot.day(for: now, timeZone: weather.timeZone) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(OutdoorTemperatureFormatting.string(snapshot.currentTemperatureCelsius, unit: weather.temperatureUnit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("H \(OutdoorTemperatureFormatting.string(day.highTemperatureCelsius, unit: weather.temperatureUnit))  L \(OutdoorTemperatureFormatting.string(day.lowTemperatureCelsius, unit: weather.temperatureUnit))")
                    .font(.caption2)
                if !snapshot.isFresh(at: now) { Text("Earlier").font(.caption2) }
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.weather.temperatures")
        } else if weather.isLoading {
            ProgressView().controlSize(.mini)
        } else if weather.locationFailure != nil || weather.failure != nil {
            Text("Weather unavailable").font(.caption2)
        }
    }
}

struct WeatherLocationSettings: View {
    @ObservedObject private var weather = DailyWeatherStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var results = [TripDestinationSelection]()
    @State private var isSearching = false
    @State private var searchFailed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Temperature units", selection: $weather.temperatureUnit) {
                        Text("°F").tag(TemperatureUnit.fahrenheit)
                            .accessibilityLabel("Fahrenheit")
                        Text("°C").tag(TemperatureUnit.celsius)
                            .accessibilityLabel("Celsius")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("weather.temperature-unit")
                } header: {
                    Text("Temperature units")
                } footer: {
                    Text("Used for outdoor temperatures on Today and sleep logs.")
                }
                Section("Units") {
                    Picker("Wind", selection: $weather.windUnit) {
                        Text("mph").tag("mph"); Text("km/h").tag("km/h")
                    }
                    Picker("Precipitation", selection: $weather.precipitationUnit) {
                        Text("Inches").tag("in"); Text("Millimeters").tag("mm")
                    }
                }
                Section {
                    Button {
                        Task {
                            await weather.useCurrentLocation()
                            if weather.locationFailure == nil, weather.location != nil { dismiss() }
                        }
                    } label: {
                        HStack {
                            Label("Use current location", systemImage: "location.fill")
                            Spacer()
                            if weather.isLoading, weather.usesCurrentLocation { ProgressView() }
                        }
                    }
                    .disabled(weather.isLoading && weather.usesCurrentLocation)
                    .accessibilityIdentifier("weather.use-current-location")
                    if let failure = weather.locationFailure {
                        Text(failure.message).font(.caption).foregroundStyle(.secondary)
                        if failure == .denied {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                } footer: {
                    Text("Use your approximate location while the app is open, or choose a city below. Sleep temperatures fill automatically when a forecast is available.")
                }
                Section("Choose a city") {
                    TextField("Search city or ZIP code", text: $query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("weather.city-search")
                    if isSearching { ProgressView("Searching") }
                    if searchFailed { Text("Search couldn't connect. Please try again.").foregroundStyle(.secondary) }
                    if !isSearching, !searchFailed, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, results.isEmpty {
                        Text("No matching cities. Try a nearby city or ZIP code.").foregroundStyle(.secondary)
                    }
                    ForEach(results) { result in
                        Button {
                            weather.select(result)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.name)
                                if let detail = result.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if weather.isConfigured {
                    Section("Selected location") {
                        if let location = weather.location {
                            LabeledContent(weather.usesCurrentLocation ? "Current location" : "City", value: location.name)
                        }
                        if let snapshot = weather.snapshot {
                            Text("Updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                            WeatherDataCredit(attribution: snapshot.attribution)
                        }
                        if let failure = weather.failure { WeatherFailureText(failure: failure) }
                        Button("Turn off weather", role: .destructive) {
                            weather.select(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Location")
            .interactionPaintProbe("units.edit", revision: weather.temperatureUnit.rawValue)
            .interactionPaintProbe("location.open")
            .interactionPerformanceAudit()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task(id: query) {
                results = []
                searchFailed = false
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    isSearching = false
                    return
                }
                isSearching = true
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    let values = try await WeatherCitySearch.search(query)
                    try Task.checkCancellation()
                    results = values.filter(\.supportsWeather)
                    isSearching = false
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    searchFailed = true
                    isSearching = false
                }
            }
        }
    }
}

struct WeatherFailureText: View {
    let failure: TripWeatherFailure
    var body: some View {
        Text(message).font(.caption).foregroundStyle(.secondary)
    }
    private var message: String {
        switch failure {
        case .appConfiguration: "Weather isn't available in this app build. You can still enter sleep temperatures manually."
        case .connection: "Weather couldn't connect. Check your connection; the app will try again automatically."
        case .serviceUnavailable: "Weather is temporarily unavailable. The app will try again automatically."
        }
    }
}

struct WeatherDataCredit: View {
    let attribution: TripWeatherAttribution
    var compact = false
    var sourceDetailsOnly = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAttribution = false

    var body: some View {
        HStack {
            if !sourceDetailsOnly {
                AsyncImage(url: colorScheme == .dark ? attribution.darkMarkURL : attribution.lightMarkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text("Apple Weather").font(.caption2)
                }
                .frame(width: 80, height: 18)
                .accessibilityLabel("Apple Weather")
                if !compact { Spacer() }
            }
            Button { showingAttribution = true } label: {
                if compact {
                    Image(systemName: "info.circle").font(.caption2)
                } else {
                    Text(sourceDetailsOnly ? "Data sources" : "About weather data").font(.caption)
                }
            }
            .accessibilityLabel(sourceDetailsOnly ? "Data sources" : "About weather data")
        }
        .sheet(isPresented: $showingAttribution) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weather data provided by Apple Weather").font(.headline)
                        Text(attribution.legalAttributionText.isEmpty ? "Forecast and current conditions provided by Apple Weather." : attribution.legalAttributionText)
                        Link("Weather data sources", destination: attribution.legalPageURL)
                    }
                    .padding()
                }
                .navigationTitle("Data Sources")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAttribution = false } } }
            }
        }
    }
}
