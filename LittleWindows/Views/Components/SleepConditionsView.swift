import SwiftUI

struct SleepConditionsFields: View {
    @Binding var draft: SleepConditionsDraft
    let date: Date
    let timeZone: TimeZone
    let allowsSleepSack: Bool
    let chooseWeatherCity: () -> Void
    var allowsForecastReplacement = false
    @ObservedObject private var weather = DailyWeatherStore.shared

    var body: some View {
        Section {
            Toggle("Automatic temperatures", isOn: Binding(
                get: { draft.usesAutomaticWeather },
                set: { enabled in
                    draft.usesAutomaticWeather = enabled
                    if enabled {
                        draft.highText = ""
                        draft.lowText = ""
                        fillAutomatically()
                        Task { await weather.refresh(); fillAutomatically() }
                    }
                }
            ))
            .accessibilityIdentifier("sleep.automatic-temperatures")
            if draft.usesAutomaticWeather {
                HStack {
                    Label("Outdoor", systemImage: "cloud.sun.fill")
                    Spacer()
                    if draft.details.outdoorHighCelsius != nil || draft.details.outdoorLowCelsius != nil {
                        Text("H \(draft.details.outdoorHighCelsius.map { OutdoorTemperatureFormatting.string($0, unit: draft.unit) } ?? "—")  L \(draft.details.outdoorLowCelsius.map { OutdoorTemperatureFormatting.string($0, unit: draft.unit) } ?? "—")")
                            .monospacedDigit()
                    } else if weather.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Not available").foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("sleep.automatic-summary")
                Button {
                    chooseWeatherCity()
                } label: {
                    Label(draft.provenance.weatherLocationName ?? weather.location?.name ?? "Use location or choose a city", systemImage: "location")
                }
                if let failure = weather.locationFailure {
                    Text(failure.message).font(.caption).foregroundStyle(.secondary)
                } else if let failure = weather.failure {
                    WeatherFailureText(failure: failure)
                }
                if let fetchedAt = draft.provenance.forecastFetchedAt {
                    Text("Forecast for \(OutdoorTemperatureFormatting.date(draft.provenance.weatherDate ?? date, timeZone: recordedTimeZone)) · saved \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !weather.isLoading {
                    Text("Temperatures fill automatically when this date's forecast is available. You can save sleep without them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let snapshot = weather.snapshot { WeatherDataCredit(attribution: snapshot.attribution) }
            } else {
                Picker("Units", selection: Binding(get: { draft.unit }, set: { draft.changeUnit(to: $0) })) {
                    ForEach(TemperatureUnit.allCases) { Text($0.displayName).tag($0) }
                }
                temperatureField("Outdoor high", text: $draft.highText, identifier: "sleep.outdoor-high")
                temperatureField("Outdoor low", text: $draft.lowText, identifier: "sleep.outdoor-low")
            }
        } header: {
            Text("Outdoor temperatures")
        } footer: {
            Text("Daily high and low for the sleep's start date. Forecast lows cover the calendar day.")
        }
        .task(id: "\(weather.requestID)|\(date.timeIntervalSince1970)") {
            if allowsForecastReplacement {
                draft.invalidateAutomaticWeather(for: date, locationName: weather.location?.name)
            }
            await weather.refresh()
            guard !Task.isCancelled else { return }
            fillAutomatically()
        }
        .onChange(of: weather.snapshot?.fetchedAt) { fillAutomatically() }
        .onChange(of: weather.temperatureUnit) { _, unit in draft.changeUnit(to: unit) }
        if allowsSleepSack {
            Section {
                SleepSackPicker(draft: $draft)
            } header: {
                Text("Sleep sack")
            } footer: {
                Text("Record the TOG rating from the sleep sack's label, or leave it blank if unknown.")
            }
        }
        if let message = draft.validationMessage {
            Section { Text(message).font(.caption).foregroundStyle(.red) }
        }
    }

    private func fillAutomatically() {
        guard draft.usesAutomaticWeather else { return }
        if allowsForecastReplacement {
            draft.invalidateAutomaticWeather(for: date, locationName: weather.location?.name)
        }
        let existing = draft.details
        draft.fillFromWeather(weather.cachedSleepConditions(for: date, preserving: existing))
    }

    private var recordedTimeZone: TimeZone {
        draft.provenance.weatherTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? timeZone
    }

    private func temperatureField(_ label: String, text: Binding<String>, identifier: String) -> some View {
        LabeledContent("\(label) (\(draft.unit.displayName))") {
            TextField("Optional", text: Binding(get: { text.wrappedValue }, set: { value in
                text.wrappedValue = value
                draft.usesAutomaticWeather = false
                draft.provenance.forecastFetchedAt = nil
                draft.provenance.weatherDate = date
                draft.provenance.weatherTimeZoneIdentifier = timeZone.identifier
            }))
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// Sleep context stays in the timer's save flow rather than a separate editor.
struct SleepTimerConditionsCard: View {
    @Binding var draft: SleepConditionsDraft
    let date: Date
    let timeZone: TimeZone
    let allowsSleepSack: Bool
    let chooseWeatherCity: () -> Void
    @ObservedObject private var weather = DailyWeatherStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if draft.usesAutomaticWeather {
                    Button(action: chooseWeatherCity) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                weatherLocation
                                Spacer(minLength: 4)
                                temperatures
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                weatherLocation
                                temperatures
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Change weather location")
                    .accessibilityIdentifier("sleep.automatic-summary")
                } else {
                    Label("Outdoor temperatures", systemImage: "cloud.sun.fill")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                }
                temperatureOptions
            }

            if draft.usesAutomaticWeather {
                if draft.provenance.forecastFetchedAt != nil, let snapshot = weather.snapshot {
                    WeatherDataCredit(attribution: snapshot.attribution, compact: true)
                }
            } else {
                Picker("Units", selection: Binding(get: { draft.unit }, set: { draft.changeUnit(to: $0) })) {
                    ForEach(TemperatureUnit.allCases) { Text($0.displayName).tag($0) }
                }
                temperatureField("Outdoor high", text: $draft.highText)
                temperatureField("Outdoor low", text: $draft.lowText)
            }

            if allowsSleepSack {
                Divider()
                SleepSackPicker(draft: $draft)
            }
            if let message = draft.validationMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .appSurface()
        .task(id: "\(weather.requestID)|\(date.timeIntervalSince1970)") {
            draft.invalidateAutomaticWeather(for: date, locationName: nil)
            fillAutomatically()
            await weather.refresh()
            guard !Task.isCancelled else { return }
            fillAutomatically()
        }
        .onChange(of: weather.snapshot?.fetchedAt) { fillAutomatically() }
        .onChange(of: weather.temperatureUnit) { _, unit in draft.changeUnit(to: unit) }
    }

    private var hasTemperatures: Bool {
        draft.details.outdoorHighCelsius != nil || draft.details.outdoorLowCelsius != nil
    }

    private var temperatureOptions: some View {
        Menu {
            if draft.usesAutomaticWeather {
                Button("Enter temperatures manually", systemImage: "pencil") {
                    draft.usesAutomaticWeather = false
                }
            } else {
                Button("Use automatic temperatures", systemImage: "cloud.sun") {
                    draft.highText = ""
                    draft.lowText = ""
                    draft.usesAutomaticWeather = true
                    fillAutomatically()
                    Task { await weather.refresh(); fillAutomatically() }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Temperature options")
        .accessibilityIdentifier("sleep.temperature-options")
    }

    private var weatherLocation: some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.sun.fill").foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.provenance.weatherLocationName ?? weather.location?.name ?? "Outdoor temperatures")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(weatherSubtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var weatherSubtitle: String {
        if hasTemperatures {
            "Outdoor · \(OutdoorTemperatureFormatting.date(draft.provenance.weatherDate ?? date, timeZone: recordedTimeZone))"
        } else if weather.isLoading {
            "Outdoor temperatures"
        } else {
            weather.isConfigured ? "Weather unavailable" : "Choose location"
        }
    }

    @ViewBuilder private var temperatures: some View {
        if hasTemperatures {
            Text("H \(draft.details.outdoorHighCelsius.map { OutdoorTemperatureFormatting.string($0, unit: draft.unit) } ?? "—")  L \(draft.details.outdoorLowCelsius.map { OutdoorTemperatureFormatting.string($0, unit: draft.unit) } ?? "—")")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        } else if weather.isLoading {
            ProgressView().controlSize(.small)
        }
    }

    private var recordedTimeZone: TimeZone {
        draft.provenance.weatherTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? timeZone
    }

    private func fillAutomatically() {
        guard draft.usesAutomaticWeather else { return }
        draft.fillFromWeather(weather.cachedSleepConditions(for: date, preserving: draft.details))
    }

    private func temperatureField(_ label: String, text: Binding<String>) -> some View {
        LabeledContent("\(label) (\(draft.unit.displayName))") {
            TextField("Optional", text: Binding(get: { text.wrappedValue }, set: { value in
                text.wrappedValue = value
                draft.provenance.forecastFetchedAt = nil
                draft.provenance.weatherDate = date
                draft.provenance.weatherTimeZoneIdentifier = recordedTimeZone.identifier
            }))
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
        }
    }
}

/// One choice records both sleep sack use and thickness, including unknown TOG.
private struct SleepSackPicker: View {
    @Binding var draft: SleepConditionsDraft
    @State private var showsCustomTOG = false
    @State private var showingSelection = false
    private static let ratings: [Double] = [0.2, 0.5, 1, 1.5, 2.5, 3.5]

    private enum Choice: Hashable {
        case notLogged, noSack, unknownTOG, rating(Double), custom
    }

    var body: some View {
        Button { showingSelection = true } label: {
            HStack {
                Text("Sleep sack").foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(selectedTitle).foregroundStyle(AppTheme.accent)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sleep sack")
        .accessibilityValue(selectedTitle)
        .accessibilityIdentifier("sleep.sack-usage")
        .appActionSheet(
            isPresented: $showingSelection,
            title: "Sleep sack",
            message: "Choose the TOG rating from the label, or record no sleep sack.",
            systemImage: "tshirt",
            options: selectionOptions
        )
        if selection.wrappedValue == .custom {
            LabeledContent("Thickness (TOG)") {
                TextField("Unknown", text: $draft.togText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("sleep.sack-tog")
            }
        }
    }

    private var selectedTitle: String {
        switch selection.wrappedValue {
        case .notLogged: "Not logged"
        case .noSack: "No sleep sack"
        case .unknownTOG: "Used · TOG unknown"
        case .rating(let rating): "\(rating.formatted()) TOG"
        case .custom:
            SleepConditionsDraft.number(draft.togText).map { "\($0.formatted()) TOG" } ?? "Other TOG"
        }
    }

    private var selectionOptions: [AppActionSheetOption] {
        [option("Not logged", choice: .notLogged, symbol: "minus.circle"),
         option("No sleep sack", choice: .noSack, symbol: "nosign")]
        + Self.ratings.map { option("\($0.formatted()) TOG", choice: .rating($0)) }
        + [option("Used · TOG unknown", choice: .unknownTOG, symbol: "questionmark.circle"),
           option("Other TOG…", choice: .custom, symbol: "pencil")]
    }

    private func option(_ title: String, choice: Choice, symbol: String = "tshirt") -> AppActionSheetOption {
        AppActionSheetOption(
            title: title, systemImage: symbol,
            isSelected: selection.wrappedValue == choice
        ) { selection.wrappedValue = choice }
    }

    private var selection: Binding<Choice> {
        Binding(get: {
            switch draft.sackUsage {
            case .notLogged: return .notLogged
            case .notUsed: return .noSack
            case .used:
                if showsCustomTOG { return .custom }
                guard let rating = SleepConditionsDraft.number(draft.togText) else {
                    return draft.togText.isEmpty ? .unknownTOG : .custom
                }
                return Self.ratings.contains(rating) ? .rating(rating) : .custom
            }
        }, set: { choice in
            showsCustomTOG = choice == .custom
            switch choice {
            case .notLogged:
                draft.sackUsage = .notLogged
                draft.togText = ""
            case .noSack:
                draft.sackUsage = .notUsed
                draft.togText = ""
            case .unknownTOG:
                draft.sackUsage = .used
                draft.togText = ""
            case .rating(let rating):
                draft.sackUsage = .used
                draft.togText = rating.formatted(.number.grouping(.never))
            case .custom:
                draft.sackUsage = .used
                draft.togText = ""
            }
        })
    }
}
