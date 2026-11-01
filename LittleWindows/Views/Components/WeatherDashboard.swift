import SwiftData
import SwiftUI

struct WeatherCityPicker: View {
    fileprivate enum Route: Hashable {
        case outdoor
        case outdoorActivity(UUID)
    }
    @State private var path: [Route] = []
    var profileID: UUID? = nil
    @ObservedObject private var weather = DailyWeatherStore.shared
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingLocation = false
    @State private var heroVisible = true
    @State private var selectedDay: Date?
    @State private var participants: Set<UUID> = []
    @State private var initializedParticipants = false
    @State private var now = Date()
    @State private var windows: [OutdoorWindow] = []

    var body: some View {
        let _ = InteractionPerformanceAudit.count("weather.body")
        NavigationStack(path: Binding(get: { path }, set: { next in
            if next.count > path.count {
                switch next.last {
                case .outdoor: InteractionPerformanceAudit.begin("outdoor.open")
                case .outdoorActivity: InteractionPerformanceAudit.begin("activity.open")
                case nil: break
                }
            }
            path = next
        })) {
            List {
                Group {
                    if let failure = weather.locationFailure {
                        Text(failure.message).font(.caption).foregroundStyle(.secondary)
                        Button("Location options") { showingLocation = true }
                    }
                    if let surface = weather.surface {
                        WeatherCurrentCard(surface: surface, now: now, effectsEnabled: heroVisible && selectedDay == nil && !showingLocation && path.isEmpty)
                            .equatable()
                            .interactionScrollAudit("weather")
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: WeatherHeroVisibilityKey.self, value: geometry.frame(in: .named("weather.scroll")).maxY > 0)
                                }
                            }
                        if let failure = weather.failure { WeatherFailureText(failure: failure) }
                        if !surface.forecast.isFresh(at: now) {
                            Label("Showing an earlier forecast. Pull to refresh.", systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        WeatherOutlookPanel(surface: surface, now: now)
                        if let summary = surface.rainSummary(at: now), let minutes = surface.forecast.validMinutes(at: now) {
                            WeatherPanel(title: "Next hour", symbol: "cloud.rain.fill", tint: .blue, subtitle: "Precipitation, minute by minute") {
                                Text(summary)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                let points = minutes.map { WeatherPlotPoint(date: $0.date, value: surface.precipitationUnit == "in" ? $0.intensityMMPerHour / 25.4 : $0.intensityMMPerHour) }
                                WeatherForecastPlot(points: points, range: 0...max(0.01, points.map(\.value).max() ?? 0), title: "Precipitation intensity",
                                    unit: surface.precipitationUnit == "in" ? "in/h" : "mm/h", timeZone: surface.timeZone, bars: true)
                            }
                        }
                        WeatherOutdoorSection(surface: surface, participants: $participants, windows: windows)
                        WeatherPanel(title: "Next 48 hours", symbol: "clock.fill", subtitle: "Your day, hour by hour") {
                            if surface.forecast.detailedForecastPending == true {
                                ProgressView("Loading hourly forecast")
                            } else {
                                WeatherHourlyView(surface: surface, hours: Array(surface.forecast.hours.filter {
                                    $0.date.addingTimeInterval(3600) > now && $0.date < now.addingTimeInterval(48 * 3600)
                                })).equatable()
                            }
                        }
                        WeatherDailyForecastView(surface: surface, selectedDay: $selectedDay).equatable()
                        WeatherMetricsGrid(surface: surface, now: now)
                    } else {
                        ContentUnavailableView(weather.isLoading ? "Loading weather" : "Your local weather",
                            systemImage: "cloud.sun.fill",
                            description: Text("Choose a city or use your current location to see conditions and forecasts."))
                        if weather.isLoading { ProgressView() }
                        Button("Choose Location") { showingLocation = true }.buttonStyle(.borderedProminent)
                        if let failure = weather.failure { WeatherFailureText(failure: failure) }
                    }
                    NavigationLink(value: Route.outdoor) {
                        HStack(spacing: 12) {
                            WeatherSectionIcon(symbol: "slider.horizontal.3", tint: AppTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Outdoor Preferences").font(.subheadline.weight(.semibold))
                                Text("Activities & comfort for each profile").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .padding(16).modifier(WeatherSolidSurface())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weather.outdoor-preferences")
                    if let surface = weather.surface {
                        VStack(spacing: 6) {
                            WeatherDataCredit(attribution: surface.forecast.attribution, sourceDetailsOnly: true)
                                .tint(.blue).buttonStyle(.borderless)
                            Text("\(surface.updatedLabel(at: now)) · \(surface.timeZoneIdentifier)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 8)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 780).frame(maxWidth: .infinity)
            .coordinateSpace(name: "weather.scroll")
            .onPreferenceChange(WeatherHeroVisibilityKey.self) { heroVisible = $0 }
            .background(AppTheme.background)
            .navigationTitle("Weather")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .outdoor: OutdoorPreferencesView()
                case .outdoorActivity(let profileID): OutdoorActivitySelectionView(profileID: profileID)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("weather.dashboard.done") }
                ToolbarItem(placement: .primaryAction) {
                    Button("Location", systemImage: "location") { InteractionPerformanceAudit.begin("location.open"); showingLocation = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: Route.outdoor) {
                        Label("Outdoor Preferences", systemImage: "slider.horizontal.3")
                    }.accessibilityIdentifier("weather.outdoor-toolbar")
                }
            }
            .sheet(isPresented: $showingLocation) { WeatherLocationSettings() }
            .sheet(isPresented: Binding(get: { selectedDay != nil }, set: { if !$0 { selectedDay = nil } })) {
                if let day = selectedDay, let surface = weather.surface { WeatherDayDetail(surface: surface, date: day) }
            }
            .refreshable { now = Date(); await weather.refresh(force: true); refreshContext() }
            .task(id: weather.requestID) {
                now = Date()
                refreshContext()
                await weather.refresh(minuteSensitive: true)
                recalculate()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    if scenePhase == .active {
                        now = Date()
                        await weather.refresh(minuteSensitive: true)
                        refreshContext()
                    }
                }
            }
            .onChange(of: weather.snapshot) { _, _ in recalculate() }
            .onChange(of: weather.outdoorProfiles) { _, _ in initializeParticipants(); recalculate() }
            .onChange(of: profileID) { _, _ in initializedParticipants = false; participants = []; windows = []; initializeParticipants() }
            .onChange(of: participants) { _, _ in windows = []; recalculate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date(); Task { await weather.refresh(minuteSensitive: true); refreshContext() } }
            }
        }
        .tint(AppTheme.accent)
        .accessibilityIdentifier("weather.dashboard")
        .interactionPaintProbe("weather.open")
        .interactionPerformanceAudit()
    }

    private func refreshContext() {
        weather.updateContext(context)
        initializeParticipants()
        recalculate()
    }
    private func initializeParticipants() {
        guard !initializedParticipants, !weather.outdoorProfiles.isEmpty else { return }
        initializedParticipants = true
        if let id = profileID ?? ProfileService.shared.selectedProfileID ?? weather.surface?.selectedProfileID,
           weather.outdoorProfiles.contains(where: { $0.id == id }) { participants = [id] }
    }
    private func recalculate() {
        guard let surface = weather.surface else { windows = []; return }
        windows = [surface.outdoor(profileIDs: participants, day: now, now: now, previous: windows.first)].compactMap { $0 }
    }
    private func weekdayFormat(_ surface: WeatherSurfaceState) -> Date.FormatStyle {
        var f = Date.FormatStyle().weekday(.wide); f.timeZone = surface.timeZone; return f
    }

}

private struct WeatherOutlookPanel: View {
    let surface: WeatherSurfaceState
    let now: Date
    var body: some View {
        let s = surface
        WeatherPanel(title: "At a glance", symbol: "sparkles", tint: .orange) {
            Text(s.outlook(at: now)).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            let tonight = s.tonight(at: now)
            if let low = tonight.map(\.temperature).min(), let feels = tonight.map(\.feelsLike).min(), let rain = tonight.map(\.rainChance).max() {
                Divider()
                Text("Tonight · Low \(s.temperature(low)) · Feels like \(s.temperature(feels)) · \(Int(rain * 100))% precipitation")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WeatherOutdoorSection: View {
    let surface: WeatherSurfaceState
    @Binding var participants: Set<UUID>
    let windows: [OutdoorWindow]
    @Environment(\.dynamicTypeSize) private var typeSize
    private func weekdayFormat(_ s: WeatherSurfaceState) -> Date.FormatStyle {
        var f = Date.FormatStyle().weekday(.wide); f.timeZone = s.timeZone; return f
    }
    var body: some View {
        let s = surface
        if !s.profiles.isEmpty {
            WeatherPanel(title: "Outdoor time", symbol: "leaf.fill", tint: .green, subtitle: "A little fresh air, around today") {
                Menu {
                    Section("Choose one or more profiles") {
                        ForEach(s.profiles) { profile in
                            Button {
                                if participants.contains(profile.id) { participants.remove(profile.id) } else { participants.insert(profile.id) }
                            } label: { Label(profile.name, systemImage: participants.contains(profile.id) ? "checkmark.circle.fill" : "circle") }
                        }
                    }
                } label: {
                    outingSelectorLabel(s)
                }
                .buttonStyle(.plain)
                .tint(AppTheme.accent)
                .accessibilityLabel("Change outing profiles")
                .accessibilityValue(s.profiles.filter { participants.contains($0.id) }.map(\.name).joined(separator: ", "))
                .accessibilityHint("Choose one or more profiles for outdoor suggestions")
                .accessibilityIdentifier("weather.outdoor-participants")
                ForEach(windows) { window in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Today")
                                .font(.caption.weight(.bold)).foregroundStyle(.green)
                            if !typeSize.isAccessibilitySize {
                                Spacer()
                                Text(window.start.formatted(weekdayFormat(s))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Group {
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.time(window.start)); Text("to \(s.time(window.end))")
                                }
                            } else { Text("\(s.time(window.start))–\(s.time(window.end))") }
                        }.font(.system(.title3, design: .rounded, weight: .semibold))
                        Text(s.profiles.filter { participants.contains($0.id) }.map { "\($0.name) · \($0.preferences.activity)" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 8) {
                            Label("\(s.temperature(window.lowFeelsLike))–\(s.temperature(window.highFeelsLike)) feels like", systemImage: "thermometer.medium")
                            Label("Up to \(Int(window.rainChance * 100))% precipitation", systemImage: "drop.fill")
                            Label("Up to \(s.wind(window.windKPH))", systemImage: "wind")
                            Label("UV \(window.uv)", systemImage: "sun.max.fill")
                        }.font(.caption).foregroundStyle(.secondary)
                        if window.fitsSleepPlan && s.profiles.contains(where: { participants.contains($0.id) && !$0.predictedSleep.isEmpty }) {
                            Label("Fits around the current sleep estimate", systemImage: "moon.zzz.fill").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(s.profiles.filter { participants.contains($0.id) && $0.lastWalk != nil }) { p in
                            if let walk = p.lastWalk { Text("\(p.name) · Last walk \(walk.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.green.opacity(0.12), lineWidth: 1))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
    private func outingSelectorLabel(_ s: WeatherSurfaceState) -> some View {
        let names = participants.isEmpty ? "Choose profiles" : s.profiles.filter { participants.contains($0.id) }.map(\.name).joined(separator: ", ")
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Outing for", systemImage: "person.2.fill").font(.caption).foregroundColor(Color(uiColor: .secondaryLabel))
                    Text(names).font(.headline).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Change profiles")
                        Image(systemName: "chevron.up.chevron.down")
                    }.font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Outing for").font(.caption).foregroundColor(Color(uiColor: .secondaryLabel))
                        Text(names).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Text("Change").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).foregroundStyle(AppTheme.accent)
                }
            }
        }.padding(12).background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct WeatherMetricsGrid: View {
    let surface: WeatherSurfaceState
    let now: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSize
    private struct Metric: Identifiable {
        let title: String; let symbol: String; let value: String; let detail: String; let tint: Color
        var id: String { title }
    }
    private var metrics: [Metric] {
        let s = surface
        var result: [Metric] = []
        if let wind = s.forecast.windKPH { result.append(.init(title: "Wind", symbol: "wind", value: s.wind(wind), detail: s.forecast.gustKPH.map { "Gusts \(s.wind($0))" } ?? "Current conditions", tint: .teal)) }
        if let humidity = s.forecast.humidity { result.append(.init(title: "Humidity", symbol: "humidity.fill", value: "\(Int(humidity * 100))%", detail: "Current relative humidity", tint: .blue)) }
        if let uv = s.forecast.uv { result.append(.init(title: "UV index", symbol: "sun.max.fill", value: "\(uv)", detail: "Current UV index", tint: .orange)) }
        if let day = s.forecast.day(for: now, timeZone: s.timeZone) {
            result.append(.init(title: "Precipitation", symbol: "drop.fill", value: "\(Int(day.precipitationChance * 100))%", detail: day.precipitationMillimeters.map { "\(s.precipitation($0)) expected today" } ?? "Today's chance", tint: .cyan))
            if let rise = day.sunrise, let set = day.sunset { result.append(.init(title: "Sunset", symbol: "sunset.fill", value: s.time(set), detail: "Sunrise \(s.time(rise))", tint: .orange)) }
        }
        return result
    }
    var body: some View {
        let items = metrics
        let columns = typeSize.isAccessibilitySize ? 1 : horizontalSize == .regular ? 3 : 2
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + columns, items.count), id: \.self) { index in
                        let item = items[index]
                        WeatherPanel(title: item.title, symbol: item.symbol, tint: item.tint, compactHeader: true) {
                            Text(item.value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeatherHeroVisibilityKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Expansion changes only this card. A fixed stack avoids dynamic lazy-stack
/// placement cycles when the forecast changes height during a scroll gesture.
private struct WeatherDailyForecastView: View, Equatable {
    let surface: WeatherSurfaceState
    @Binding var selectedDay: Date?
    @State private var showTenDays = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.surface.forecast.days == rhs.surface.forecast.days && lhs.surface.fahrenheit == rhs.surface.fahrenheit
            && lhs.surface.timeZoneIdentifier == rhs.surface.timeZoneIdentifier
    }
    var body: some View {
        let _ = InteractionPerformanceAudit.count("daily.body")
        let s = surface
        WeatherPanel(title: showTenDays ? "10-day forecast" : "7-day forecast", symbol: "calendar", tint: .purple, subtitle: "Tap a day to explore") {
            let days = Array(s.forecast.days.prefix(showTenDays ? 10 : 7))
            let low = days.map(\.lowTemperatureCelsius).min() ?? 0
            let high = days.map(\.highTemperatureCelsius).max() ?? 1
            ForEach(days, id: \.date) { day in
                Button { InteractionPerformanceAudit.begin("day.open"); selectedDay = day.date } label: {
                    WeatherDailyRow(surface: s, day: day, low: low, high: high)
                }.buttonStyle(WeatherForecastButtonStyle())
                    .accessibilityHint("Opens this day's hourly forecast and conditions")
                    .accessibilityIdentifier("weather.forecast-day")
                if day.date != days.last?.date { Divider() }
            }
            if s.forecast.days.count > 7 {
                Button { InteractionPerformanceAudit.begin("daily.change"); showTenDays.toggle() } label: {
                    HStack {
                        Text(showTenDays ? "Show 7 days" : "Show 10 days")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showTenDays ? 180 : 0))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showTenDays)
                    }.font(.subheadline.weight(.semibold)).padding(12)
                        .background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
        .interactionPaintProbe("daily.change", revision: String(showTenDays), alignment: .bottomTrailing)
    }
}

struct WeatherPanel<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = AppTheme.accent
    var subtitle: String? = nil
    var compactHeader = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: compactHeader ? 8 : 10) {
                WeatherSectionIcon(symbol: symbol, tint: tint, size: compactHeader ? 24 : 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(compactHeader ? .subheadline.weight(.semibold) : .system(.headline, design: .rounded)).foregroundStyle(.primary)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(LinearGradient(colors: [tint.opacity(0.045), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        .modifier(WeatherSolidSurface())
    }
}

/// Weather cards sit on a grouped background; a solid adaptive surface avoids
/// stacking live backdrop filters for every forecast/metric panel.
private struct WeatherSolidSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }
}

private struct WeatherSectionIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.45, weight: .semibold))
            .symbolRenderingMode(.hierarchical).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: size / 3))
            .accessibilityHidden(true)
    }
}

private struct WeatherForecastButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.vertical, 4).padding(.horizontal, 2)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct WeatherCurrentCard: View, Equatable {
    let surface: WeatherSurfaceState
    let now: Date
    var effectsEnabled = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    static func == (lhs: Self, rhs: Self) -> Bool {
        let l = lhs.surface, r = rhs.surface
        return lhs.now == rhs.now && lhs.effectsEnabled == rhs.effectsEnabled && l.city == r.city
            && l.fahrenheit == r.fahrenheit && l.timeZoneIdentifier == r.timeZoneIdentifier
            && l.forecast.currentTemperatureCelsius == r.forecast.currentTemperatureCelsius
            && l.forecast.feelsLike == r.forecast.feelsLike && l.forecast.condition == r.forecast.condition
            && l.forecast.symbolName == r.forecast.symbolName && l.forecast.windKPH == r.forecast.windKPH
            && l.forecast.days == r.forecast.days
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(surface.city, systemImage: "location.fill")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(surface.temperature(surface.forecast.currentTemperatureCelsius))
                        .font(.system(size: typeSize.isAccessibilitySize ? 64 : 80, weight: .light, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                    Text(surface.forecast.condition).font(.headline)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    WeatherAtmosphere(symbol: surface.forecast.symbolName, windKPH: surface.forecast.windKPH ?? 0, enabled: effectsEnabled)
                        .frame(width: 144, height: 156)
                }
            }
            if let feels = surface.forecast.feelsLike {
                Text("Feels like \(surface.temperature(feels))").font(.subheadline).foregroundStyle(.secondary)
            }
            if let day = surface.forecast.day(for: now, timeZone: surface.timeZone) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 16))
                layout {
                    Label("High \(surface.temperature(day.highTemperatureCelsius))", systemImage: "arrow.up")
                    Label("Low \(surface.temperature(day.lowTemperatureCelsius))", systemImage: "arrow.down")
                }.font(.caption.weight(.semibold)).padding(.top, 8)
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [WeatherSceneConfiguration(symbol: surface.forecast.symbolName, windKPH: surface.forecast.windKPH ?? 0).tint.opacity(colorScheme == .dark ? 0.24 : 0.14), .cyan.opacity(0.04), AppTheme.surface], startPoint: .topTrailing, endPoint: .bottomLeading))
        }
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(AppTheme.accent.opacity(0.13), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("weather.current-conditions")
    }
    private var accessibilitySummary: String {
        var parts = [surface.city, surface.temperature(surface.forecast.currentTemperatureCelsius), surface.forecast.condition]
        if let feels = surface.forecast.feelsLike { parts.append("Feels like \(surface.temperature(feels))") }
        if let day = surface.forecast.day(for: now, timeZone: surface.timeZone) {
            parts.append("High \(surface.temperature(day.highTemperatureCelsius)), low \(surface.temperature(day.lowTemperatureCelsius))")
        }
        return parts.joined(separator: ", ")
    }
}

struct WeatherHourlyView: View, Equatable {
    let surface: WeatherSurfaceState
    let hours: [WeatherHour]
    @ScaledMetric(relativeTo: .caption2) private var columnWidth: CGFloat = 58
    @State private var feelsLike = false
    @State private var precipitation = false
    @State private var selectedDate: Date?
    @State private var scrolledDate: Date?
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hours == rhs.hours && lhs.surface.fahrenheit == rhs.surface.fahrenheit
            && lhs.surface.timeZoneIdentifier == rhs.surface.timeZoneIdentifier
    }
    var body: some View {
        let _ = InteractionPerformanceAudit.count("hourly.body")
        let now = Date()
        let values = hours.map(temperature).filter(\.isFinite)
        let domain = floor((values.min() ?? 0) - 3)...ceil((values.max() ?? 1) + 3)
        let range = precipitation ? 0...100 : domain
        let unit = precipitation ? "%" : surface.fahrenheit ? "°F" : "°C"
        let measure = precipitation ? "Precipitation chance" : feelsLike ? "Feels-like temperature" : "Temperature"
        let selected = hours.first { $0.date == selectedDate } ?? hours.first
        let _ = InteractionPerformanceAudit.count("hourly.domain")
        VStack(alignment: .leading, spacing: 12) {
            Picker("Forecast measure", selection: Binding(get: { precipitation }, set: { value in
                guard value != precipitation else { return }
                InteractionPerformanceAudit.begin("hourly.change"); precipitation = value
            })) {
                Text("Temperature").tag(false); Text("Precipitation").tag(true)
            }.pickerStyle(.segmented)
                .accessibilityIdentifier("weather.hourly.measure")
            if !precipitation {
                Toggle("Feels like", isOn: Binding(get: { feelsLike }, set: { value in
                    guard value != feelsLike else { return }
                    InteractionPerformanceAudit.begin("hourly.change"); feelsLike = value
                })).font(.caption).accessibilityIdentifier("weather.hourly.feels-like")
            }
            if let selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(measure + " · " + unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(dayLabel(selected.date)) · \(surface.time(selected.date))")
                            Spacer(minLength: 8)
                            Text(selectedValue(selected)).font(.system(.title3, design: .rounded, weight: .semibold))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(dayLabel(selected.date)) · \(surface.time(selected.date))")
                            Text(selectedValue(selected)).font(.system(.title3, design: .rounded, weight: .semibold))
                        }
                    }.font(.subheadline)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("weather.hourly.readout")
                Text("Swipe to explore hourly weather")
                    .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                HStack(alignment: .top, spacing: 10) {
                    WeatherPlotAxis(range: range, unit: unit)
                    ScrollView(.horizontal) {
                        VStack(spacing: 8) {
                            WeatherForecastPlot(points: hours.map { WeatherPlotPoint(date: $0.date, value: precipitation ? $0.rainChance * 100 : temperature($0)) },
                                range: range, title: measure, unit: unit, timeZone: surface.timeZone, bars: precipitation,
                                showsYAxis: false, showsTimeAxis: false,
                                selection: Binding(get: { selectedDate ?? hours.first?.date }, set: { selectedDate = $0 }), allowsSelection: true)
                                .frame(width: CGFloat(hours.count) * columnWidth)
                                .accessibilityIdentifier("weather.hourly.plot")
                            LazyHStack(alignment: .top, spacing: 0) {
                                ForEach(hours) { hour in
                                    Button { selectedDate = hour.date } label: {
                                        VStack(spacing: 6) {
                                            Text(dayLabel(hour.date)).font(.caption2).foregroundStyle(.secondary)
                                            Text(hour.date <= now && hour.date.addingTimeInterval(3600) > now ? "Now" : surface.time(hour.date)).font(.caption2)
                                            Image(systemName: hour.symbol).symbolRenderingMode(.multicolor)
                                            Text(surface.temperature(feelsLike ? hour.feelsLike : hour.temperature)).font(.subheadline.weight(.semibold))
                                            Text("\(Int(hour.rainChance * 100))%").font(.caption2).foregroundStyle(.blue)
                                        }.padding(.vertical, 10).frame(width: columnWidth)
                                            .background(AppTheme.accent.opacity(hour.date == selected.date ? 0.12 : 0.025), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(dayLabel(hour.date)), \(surface.time(hour.date)), \(hour.condition), \(surface.temperature(feelsLike ? hour.feelsLike : hour.temperature)), \(Int(hour.rainChance * 100))% precipitation")
                                    .accessibilityAddTraits(hour.date == selected.date ? .isSelected : [])
                                    .accessibilityIdentifier("weather.hourly.hour.\(hour.date.timeIntervalSince1970)")
                                    .id(hour.date)
                                }
                            }
                            .scrollTargetLayout()
                            .frame(width: CGFloat(hours.count) * columnWidth, alignment: .leading)
                        }
                    }
                    .scrollPosition(id: $scrolledDate, anchor: .center)
                    .onChange(of: scrolledDate) { _, date in
                        if let date, date != selectedDate { selectedDate = date }
                    }
                    .scrollIndicators(.hidden).accessibilityIdentifier("weather.hourly.scroll")
                }
            } else {
                Text("Hourly forecast unavailable for this day.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .interactionPaintProbe("hourly.change", revision: "\(precipitation)-\(feelsLike)")
    }
    private func selectedValue(_ hour: WeatherHour) -> String {
        precipitation ? "\(Int(hour.rainChance * 100))%" : surface.temperature(feelsLike ? hour.feelsLike : hour.temperature)
    }
    private func dayLabel(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = surface.timeZone
        if calendar.isDate(date, inSameDayAs: Date()) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(dayFormat)
    }
    private var dayFormat: Date.FormatStyle { var f = Date.FormatStyle().weekday(.abbreviated); f.timeZone = surface.timeZone; return f }
    private func temperature(_ hour: WeatherHour) -> Double {
        let celsius = feelsLike ? hour.feelsLike : hour.temperature
        return surface.fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }
}

private struct WeatherDailyRow: View {
    let surface: WeatherSurfaceState
    let day: TripDailyWeather
    let low: Double
    let high: Double
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(day.date.formatted(accessibleDateFormat), systemImage: day.symbolName).font(.headline)
                        Text("Low \(surface.temperature(day.lowTemperatureCelsius)) · High \(surface.temperature(day.highTemperatureCelsius))").font(.subheadline)
                        Text("\(Int(day.precipitationChance * 100))% precipitation").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else { regularRow }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(AppTheme.accent.opacity(0.65)).accessibilityHidden(true)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(day.date.formatted(accessibleDateFormat)), \(day.condition ?? "Forecast"), low \(surface.temperature(day.lowTemperatureCelsius)), high \(surface.temperature(day.highTemperatureCelsius)), \(Int(day.precipitationChance * 100))% precipitation")
    }
    private var regularRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(format)).font(.subheadline.weight(.medium))
                Text(day.date.formatted(dateFormat)).font(.caption2).foregroundStyle(.secondary)
            }.frame(width: 58, alignment: .leading)
            VStack(spacing: 3) {
                Image(systemName: day.symbolName).symbolRenderingMode(.multicolor)
                Text("\(Int(day.precipitationChance * 100))%").font(.caption2).foregroundStyle(.blue)
            }.frame(width: 38)
            Text(surface.temperature(day.lowTemperatureCelsius)).foregroundStyle(.secondary).frame(minWidth: 30, alignment: .trailing)
            Canvas { context, size in
                let span = max(1, high - low)
                let full = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: full, cornerRadius: 3), with: .color(AppTheme.accent.opacity(0.08)))
                let bar = CGRect(x: size.width * (day.lowTemperatureCelsius - low) / span, y: 0,
                    width: max(4, size.width * (day.highTemperatureCelsius - day.lowTemperatureCelsius) / span), height: size.height)
                context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .linearGradient(
                    Gradient(colors: [.cyan, AppTheme.accent, .orange]), startPoint: CGPoint(x: bar.minX, y: 0), endPoint: CGPoint(x: bar.maxX, y: 0)))
            }.frame(maxWidth: .infinity).frame(height: 5).accessibilityHidden(true)
            Text(surface.temperature(day.highTemperatureCelsius)).frame(minWidth: 30, alignment: .trailing)
        }
        .monospacedDigit().frame(minHeight: 44).accessibilityElement(children: .combine)
    }
    private var format: Date.FormatStyle { var f = Date.FormatStyle().weekday(.abbreviated); f.timeZone = surface.timeZone; return f }
    private var dateFormat: Date.FormatStyle { var f = Date.FormatStyle().month(.abbreviated).day(); f.timeZone = surface.timeZone; return f }
    private var accessibleDateFormat: Date.FormatStyle { var f = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day(); f.timeZone = surface.timeZone; return f }
}

private struct WeatherDayDetail: View {
    let surface: WeatherSurfaceState
    let date: Date
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let day = surface.forecast.day(for: date, timeZone: surface.timeZone) {
                        WeatherPanel(title: day.condition ?? "Forecast", symbol: day.symbolName, tint: .purple) {
                            Text("High \(surface.temperature(day.highTemperatureCelsius)) · Low \(surface.temperature(day.lowTemperatureCelsius))")
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Text("Precipitation chance \(Int(day.precipitationChance * 100))% · UV \(day.uvIndex)").font(.subheadline)
                            if let amount = day.precipitationMillimeters { Text("\(surface.precipitation(amount)) expected for the day").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    WeatherPanel(title: "Hour by hour", symbol: "clock.fill") {
                        WeatherHourlyView(surface: surface, hours: surface.forecast.hours.filter { calendar.isDate($0.date, inSameDayAs: date) })
                            .equatable()
                    }
                    WeatherDataCredit(attribution: surface.forecast.attribution, sourceDetailsOnly: true)
                }.padding().frame(maxWidth: 780).frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle(surface.dateLabel(date))
            .interactionPaintProbe("day.open")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("weather.day.done") } }
        }
        .interactionPerformanceAudit()
    }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = surface.timeZone; return c }
}

struct OutdoorPreferencesView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var weather = DailyWeatherStore.shared
    @State private var paintRevision = 0
    var body: some View {
        Form {
            Section {
                Text("These are editable comfort preferences. A suggested hour is an opportunity for an outing, not an exercise duration.")
            } footer: {
                if !weather.outdoorProfiles.isEmpty {
                    Text("Preferences are saved per profile and sync across your devices on the same Apple Account when iCloud sync is enabled.")
                }
            }
            ForEach(weather.outdoorProfiles) { profile in
                Section {
                    Toggle("Outdoor suggestions", isOn: boolean(profile))
                    NavigationLink(value: WeatherCityPicker.Route.outdoorActivity(profile.id)) {
                        LabeledContent("Activity") { Text(profile.preferences.activity) }
                    }
                    .accessibilityLabel("Activity for \(profile.name)")
                    .accessibilityValue(profile.preferences.activity)
                    .accessibilityHint("Choose an outdoor activity for this profile")
                    .accessibilityIdentifier("weather.outdoor-activity.\(profile.id)")
                    Stepper("Minimum feels like: \(temperature(profile.preferences.minimumCelsius))", value: number(profile, key: "minimum", current: profile.preferences.minimumCelsius), in: -40...profile.preferences.maximumCelsius, step: 1)
                    Stepper("Maximum feels like: \(temperature(profile.preferences.maximumCelsius))", value: number(profile, key: "maximum", current: profile.preferences.maximumCelsius), in: profile.preferences.minimumCelsius...50, step: 1)
                    Stepper("Rain chance up to \(Int(profile.preferences.maximumRainChance * 100))%", value: number(profile, key: "rain", current: profile.preferences.maximumRainChance), in: 0...1, step: 0.05)
                    Stepper("Wind/gusts up to \(wind(profile.preferences.maximumWindKPH))", value: number(profile, key: "wind", current: profile.preferences.maximumWindKPH), in: 0...120, step: 5)
                        .accessibilityIdentifier("weather.outdoor.wind.\(profile.id)")
                    Stepper("UV up to \(profile.preferences.maximumUV)", value: number(profile, key: "uv", current: Double(profile.preferences.maximumUV)), in: 0...15, step: 1)
                } header: { Text(profile.name) }
            }
            if weather.outdoorProfiles.isEmpty { Text("Add a care profile to personalize outdoor suggestions.") }
        }
        .navigationTitle("Outdoor Preferences")
        .interactionPaintProbe("outdoor.open")
        .interactionPaintProbe("outdoor.edit", revision: String(paintRevision))
        .interactionPaintProbe("activity.choose", revision: InteractionPerformanceAudit.enabled
            ? weather.outdoorProfiles.map { "\($0.id):\($0.preferences.activity)" }.joined(separator: "|") : "")
        .interactionPerformanceAudit()
        .task { weather.updateContext(context) }
    }
    private func save(_ p: OutdoorProfileContext, key: String, value: String) {
        InteractionPerformanceAudit.begin("outdoor.edit")
        paintRevision += 1
        CareTrackingPreferenceStore.update(profileID: p.id) { $0.set("outdoor." + key, value: [value]) }
    }
    private func boolean(_ p: OutdoorProfileContext) -> Binding<Bool> { Binding(get: { p.preferences.enabled }, set: { save(p, key: "enabled", value: String($0)) }) }
    private func number(_ p: OutdoorProfileContext, key: String, current: Double) -> Binding<Double> {
        Binding(get: {
            let value = p.preferences
            switch key {
            case "minimum": return value.minimumCelsius
            case "maximum": return value.maximumCelsius
            case "rain": return value.maximumRainChance
            case "wind": return value.maximumWindKPH
            case "uv": return Double(value.maximumUV)
            default: return current
            }
        }, set: { save(p, key: key, value: String($0)) })
    }
    private func wind(_ kph: Double) -> String {
        let value = weather.windUnit == "mph" ? kph / 1.609344 : kph
        return "\(Int(value.rounded())) \(weather.windUnit)"
    }
    private func temperature(_ c: Double) -> String { OutdoorTemperatureFormatting.string(c, unit: weather.temperatureUnit) }
}

/// A lazy navigation destination avoids the native popup picker's first-open
/// presentation work. Reads use the published profile values, never history.
private struct OutdoorActivitySelectionView: View {
    let profileID: UUID
    @ObservedObject private var weather = DailyWeatherStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let profile = weather.outdoorProfiles.first(where: { $0.id == profileID }) {
                Section(profile.name) {
                    ForEach(OutdoorActivity.pickerOptions(profile.activities, selected: profile.preferences.activity), id: \.self) { activity in
                        Button {
                            if activity != profile.preferences.activity {
                                InteractionPerformanceAudit.begin("activity.choose")
                                CareTrackingPreferenceStore.update(profileID: profile.id) {
                                    $0.set("outdoor.activity", value: [activity])
                                }
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Text(activity).foregroundStyle(.primary)
                                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 12)
                                if activity == profile.preferences.activity {
                                    Image(systemName: "checkmark").foregroundStyle(AppTheme.accent)
                                        .accessibilityHidden(true)
                                }
                            }.contentShape(Rectangle())
                        }
                        .accessibilityLabel(activity)
                        .accessibilityAddTraits(activity == profile.preferences.activity ? .isSelected : [])
                        .accessibilityIdentifier("weather.activity-choice.\(activity)")
                    }
                }
            } else {
                ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle",
                    description: Text("Return to Outdoor Preferences to choose an active profile."))
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("weather.activity-list")
        .interactionPaintProbe("activity.open")
        .interactionPerformanceAudit()
    }
}
