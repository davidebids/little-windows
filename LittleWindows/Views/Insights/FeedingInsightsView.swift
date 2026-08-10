import Charts
import SwiftUI

struct FeedingInsightsView: View {
    let snapshot: InsightsSnapshot
    let solids: SolidsReportSnapshot?
    let openSolidsTracker: () -> Void
    let openAllergens: () -> Void

    @ObservedObject private var router = DeepLinkRouter.shared
    @State private var selectedMode = FeedingInsightsMode.milk

    private var availableModes: [FeedingInsightsMode] {
        solids == nil ? [.milk, .patterns] : [.milk, .solids, .patterns]
    }

    private var bottleMetrics: [InsightMetric] {
        metrics(named: ["Bottle ounces", "Average bottle"])
    }

    private var nursingMetrics: [InsightMetric] {
        metrics(named: [
            "Nursing sessions / day",
            "Nursing time",
            "Left nursing",
            "Right nursing"
        ])
    }

    private var patternMetrics: [InsightMetric] {
        metrics(named: [
            "All feeding sessions / day",
            "Time between feeding sessions",
            "Feeds followed by sleep"
        ])
    }

    private var milkTrends: [InsightTrend] {
        trends(named: ["Bottle intake", "Nursing balance"])
    }

    private var patternTrends: [InsightTrend] {
        trends(named: ["All feeding sessions", "Feeding before sleep"])
    }

    var body: some View {
        Group {
            modePicker

            switch selectedMode {
            case .milk:
                milkSection
            case .solids:
                if let solids {
                    solidsSection(solids)
                } else {
                    modeUnavailable
                }
            case .patterns:
                patternsSection
            }
        }
        .onChange(of: solids == nil) { _, solidsUnavailable in
            if solidsUnavailable && selectedMode == .solids {
                selectedMode = .milk
            } else if !solidsUnavailable {
                applyPendingMode()
            }
        }
        .onAppear(perform: applyPendingMode)
        .onReceive(router.$pendingFeedingInsightsMode.compactMap { $0 }) { _ in
            applyPendingMode()
        }
    }

    private func applyPendingMode() {
        guard let mode = router.pendingFeedingInsightsMode else { return }
        guard availableModes.contains(mode) else { return }
        router.pendingFeedingInsightsMode = nil
        selectedMode = mode
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a feeding view")
                    .font(.headline)
                Text("Milk feeds, solids, and combined timing patterns use different measures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Feeding view", selection: $selectedMode) {
                ForEach(availableModes) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("insights.feeding.mode")
        }
        .padding(16)
        .appSurface()
    }

    @ViewBuilder
    private var milkSection: some View {
        sectionHeader(
            title: "Bottle feeding",
            subtitle: "Volume from bottle feed logs only.",
            systemImage: "waterbottle.fill",
            tint: .orange
        )
        .accessibilityIdentifier("insights.feeding.bottle")

        InsightMetricGrid(metrics: bottleMetrics)

        InsightChartCard(
            title: "Bottle ounces per day",
            subtitle: "Logged bottle volume only",
            isEmpty: snapshot.dailyFeeding.allSatisfy { $0.bottleOunces == 0 }
        ) {
            Chart(snapshot.dailyFeeding) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Ounces", point.bottleOunces)
                )
                .foregroundStyle(.orange.gradient)
                .cornerRadius(4)
            }
        }

        sectionHeader(
            title: "Nursing",
            subtitle: "Grouped nursing sessions and logged time by side.",
            systemImage: "figure.and.child.holdinghands",
            tint: .pink
        )
        .accessibilityIdentifier("insights.feeding.nursing")

        InsightMetricGrid(metrics: nursingMetrics)

        InsightChartCard(
            title: "Nursing left vs right",
            subtitle: "Total logged minutes by side",
            isEmpty: snapshot.nursingSideMinutes.allSatisfy { $0.value == 0 }
        ) {
            Chart(snapshot.nursingSideMinutes) { item in
                BarMark(
                    x: .value("Side", item.category),
                    y: .value("Minutes", item.value)
                )
                .foregroundStyle(by: .value("Side", item.category))
                .cornerRadius(6)
            }
            .chartForegroundStyleScale(["Left": Color.pink, "Right": Color.purple])
        }

        InsightObservationsCard(
            title: "Milk-feeding changes",
            systemImage: "chart.line.uptrend.xyaxis",
            trends: milkTrends
        )
    }

    @ViewBuilder
    private var patternsSection: some View {
        sectionHeader(
            title: "All feeding patterns",
            subtitle: "This view intentionally combines bottle, nursing, and solids. Logs within 45 minutes are grouped as one feeding session.",
            systemImage: "point.3.connected.trianglepath.dotted",
            tint: .indigo
        )
        .accessibilityIdentifier("insights.feeding.patterns")

        InsightMetricGrid(metrics: patternMetrics)

        InsightObservationsCard(
            title: "Combined feeding changes",
            systemImage: "chart.line.uptrend.xyaxis",
            trends: patternTrends
        )

        InsightChartCard(
            title: "All feeding sessions per day",
            subtitle: "Bottle, nursing, and solids combined",
            isEmpty: snapshot.dailyFeeding.allSatisfy { $0.careSessions == 0 }
        ) {
            Chart(snapshot.dailyFeeding) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Sessions", point.careSessions)
                )
                .foregroundStyle(.indigo.gradient)
                .cornerRadius(4)
            }
        }

        InsightChartCard(
            title: "Feeding-to-sleep interval",
            subtitle: "Time from any feeding session to sleep",
            isEmpty: snapshot.feedToSleepBuckets.allSatisfy { $0.value == 0 }
        ) {
            Chart(snapshot.feedToSleepBuckets) { item in
                BarMark(
                    x: .value("Interval", item.category),
                    y: .value("Sleeps", item.value)
                )
                .foregroundStyle(.purple.gradient)
                .cornerRadius(5)
            }
        }

        InsightChartCard(
            title: "All feeding by time of day",
            subtitle: "Bottle, nursing, and solids combined",
            isEmpty: snapshot.feedingHourBuckets.allSatisfy { $0.value == 0 }
        ) {
            Chart(snapshot.feedingHourBuckets) { item in
                BarMark(
                    x: .value("Time", item.category),
                    y: .value("Sessions", item.value)
                )
                .foregroundStyle(.teal.gradient)
                .cornerRadius(5)
            }
        }
    }

    private var modeUnavailable: some View {
        ContentUnavailableView(
            "Solids insights unavailable",
            systemImage: "fork.knife.circle",
            description: Text("Choose another feeding view.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
        .appSurface()
    }

    private func sectionHeader(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }

    private func metrics(named names: Set<String>) -> [InsightMetric] {
        snapshot.feedingMetrics.filter { names.contains($0.title) }
    }

    private func trends(named names: Set<String>) -> [InsightTrend] {
        snapshot.feedingTrends.filter { names.contains($0.metricName) }
    }

    @ViewBuilder
    private func solidsSection(_ solids: SolidsReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Solids", systemImage: "carrot.fill")
                .font(.title3.bold())
                .foregroundStyle(.orange)
            Text("Food variety and exposure details from the selected reporting period.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appSurface()

        InsightMetricGrid(metrics: solidsMetrics(solids))

        if solids.foodCount > 0 {
            sectionHeader(
                title: "Estimated nutrients",
                subtitle: "Calculated from amounts eaten and saved nutrition snapshots. No daily target is applied.",
                systemImage: "chart.bar.doc.horizontal.fill",
                tint: .teal
            )

            if solids.quantifiedFoodCount > 0 {
                InsightMetricGrid(metrics: nutrientMetrics(solids))

                InsightChartCard(
                    title: "Estimated iron by day",
                    subtitle: "Milligrams from quantified solid-food logs",
                    isEmpty: solids.daily.allSatisfy { ($0.nutrients.ironMilligrams ?? 0) == 0 }
                ) {
                    Chart(solids.daily) { point in
                        BarMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Iron (mg)", point.nutrients.ironMilligrams ?? 0)
                        )
                        .foregroundStyle(.teal.gradient)
                        .cornerRadius(4)
                    }
                }
            }

            Text(nutritionCoverageText(solids))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appSurface()
        }

        InsightChartCard(
            title: "Solids by day",
            subtitle: "Logged meals and foods first tried",
            isEmpty: solids.mealCount == 0,
            emptyMessage: "Log a solids meal to begin the feeding report."
        ) {
            Chart(solids.daily) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Count", point.meals)
                )
                .foregroundStyle(by: .value("Type", "Meals"))
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Count", point.newFoods)
                )
                .foregroundStyle(by: .value("Type", "New foods"))
            }
            .chartForegroundStyleScale(["Meals": Color.orange, "New foods": Color.teal])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Explore the details")
                .font(.headline)
            HStack(spacing: 10) {
                Button(action: openSolidsTracker) {
                    Label("Solids tracker", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("reports.feeding.solids-tracker")

                Button(action: openAllergens) {
                    Label("Allergens", systemImage: "allergens")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.feeding.allergens")
            }
            Text("Counts reflect logged observations only. They do not establish tolerance or diagnose a reaction.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .appSurface()
    }

    private func nutritionCoverageText(_ solids: SolidsReportSnapshot) -> String {
        let partialCount = max(0, solids.quantifiedFoodCount - solids.completeNutritionFoodCount)
        let unquantifiedCount = max(0, solids.foodCount - solids.quantifiedFoodCount)
        var sentences = [
            "Nutrition coverage: \(solids.completeNutritionFoodCount) of \(solids.foodCount) logged food entries included all eight tracked nutrients."
        ]
        if partialCount > 0 {
            sentences.append("\(partialCount) included only the nutrient values available in its saved manual label.")
        }
        if unquantifiedCount > 0 {
            sentences.append("\(unquantifiedCount) could not be quantified from the saved amount and nutrition data.")
        }
        sentences.append("Built-in foods include all eight nutrients once an eaten amount is recorded. Custom foods require a manual label, and blank label fields remain uncounted.")
        return sentences.joined(separator: " ")
    }

    private func solidsMetrics(_ solids: SolidsReportSnapshot) -> [InsightMetric] {
        [
            InsightMetric(
                title: "Solid meals",
                value: "\(solids.mealCount)",
                interpretation: "Logged solids feed events in this period.",
                systemImage: "fork.knife"
            ),
            InsightMetric(
                title: "Unique foods",
                value: "\(solids.uniqueFoodCount)",
                interpretation: "Different foods attached to those meals.",
                systemImage: "square.grid.2x2.fill"
            ),
            InsightMetric(
                title: "New foods",
                value: "\(solids.newFoodCount)",
                interpretation: "Foods first logged during this period.",
                systemImage: "sparkles"
            ),
            InsightMetric(
                title: "Allergen exposures",
                value: "\(solids.allergenExposureCount)",
                interpretation: "Distinct allergen-and-meal observations.",
                systemImage: "allergens"
            ),
            InsightMetric(
                title: "Reaction notes",
                value: "\(solids.reactionObservationCount)",
                interpretation: "Food-level suspected reactions recorded in this period.",
                systemImage: "exclamationmark.triangle.fill"
            )
        ]
    }

    private func nutrientMetrics(_ solids: SolidsReportSnapshot) -> [InsightMetric] {
        let values = solids.nutrients
        return [
            nutrientMetric("Energy", values.energyKilocalories, "kcal", "flame.fill"),
            nutrientMetric("Protein", values.proteinGrams, "g", "leaf.fill"),
            nutrientMetric("Iron", values.ironMilligrams, "mg", "drop.fill"),
            nutrientMetric("Zinc", values.zincMilligrams, "mg", "circle.hexagongrid.fill"),
            nutrientMetric("Calcium", values.calciumMilligrams, "mg", "bone.fill"),
            nutrientMetric("Vitamin C", values.vitaminCMilligrams, "mg", "sun.max.fill"),
            nutrientMetric("Fiber", values.fiberGrams, "g", "leaf.circle.fill"),
            nutrientMetric("Fat", values.fatGrams, "g", "circle.fill")
        ]
    }

    private func nutrientMetric(
        _ title: String,
        _ value: Double?,
        _ unit: String,
        _ systemImage: String
    ) -> InsightMetric {
        InsightMetric(
            title: title,
            value: value.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) \(unit)" } ?? "–",
            interpretation: "Estimated total from quantified solid-food logs in this period.",
            systemImage: systemImage
        )
    }
}
