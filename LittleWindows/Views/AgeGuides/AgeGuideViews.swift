import SwiftData
import SwiftUI

struct AgeGuideFeatureCard: View {
    let guide: AgeGuide
    let babyName: String
    let isCurrent: Bool
    let isUnread: Bool
    var reachedDate: Date?
    var onDismiss: (() -> Void)?
    var onAddMilestone: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: guide.isCheckpointAge ? "checklist.checked" : "sparkles")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(MilestonePalette.accent.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(isCurrent ? "\(babyName) at \(guide.ageLabel)" : guide.title)
                            .font(.headline)
                        if isUnread {
                            Text("NEW")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.pink, in: Capsule())
                        }
                    }
                    Text(guide.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let reachedDate {
                        Text("Reached \(guide.ageLabel.lowercased()) on \(reachedDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MilestonePalette.accent)
                    }
                }

                Spacer()

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss age guide card")
                }
            }

            Text(guide.overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 10) {
                Label("\(guide.milestonePrompts.count) prompts", systemImage: "heart.text.clipboard.fill")
                Label(guide.isCheckpointAge ? "Checkpoint age" : "Monthly guide", systemImage: "calendar")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if let onAddMilestone {
                Button(action: onAddMilestone) {
                    Label("Add a \(guide.ageLabel.lowercased()) milestone", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(MilestonePalette.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.pink.opacity(0.16), Color.indigo.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.pink.opacity(0.14), lineWidth: 0.8)
        }
    }
}

struct AgeGuidesListView: View {
    let guides: [AgeGuide]
    let currentMonth: Int?
    let readStates: [AgeGuideReadState]

    var body: some View {
        List {
            Section {
                ForEach(guides) { guide in
                    NavigationLink {
                        AgeGuideDetailView(guide: guide)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: guide.isCheckpointAge ? "checklist.checked" : "calendar")
                                .foregroundStyle(guide.ageMonth == currentMonth ? MilestonePalette.accent : .secondary)
                                .frame(width: 34, height: 34)
                                .background(Color.primary.opacity(0.05), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(guide.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(statusText(for: guide))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Guides are general parent education and memory prompts, not medical advice.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(MilestonePalette.background)
        .navigationTitle("Age Guides")
    }

    private func statusText(for guide: AgeGuide) -> String {
        if guide.ageMonth == currentMonth {
            return "This month"
        }
        if readStates.contains(where: { $0.guideID == guide.id && $0.firstOpenedAt != nil }) {
            return "Read"
        }
        if let currentMonth, guide.ageMonth > currentMonth {
            return "Coming up"
        }
        return guide.isCheckpointAge ? "Checkpoint guide" : "Monthly guide"
    }
}

struct AgeGuideDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @Query(sort: \AgeGuideReadState.updatedAt) private var readStates: [AgeGuideReadState]

    let guide: AgeGuide

    @State private var selectedTemplate: MilestoneTemplate?
    @StateObject private var profileService = ProfileService.shared

    private var profile: BabyProfile? { profileService.selectedProfile(in: profiles) }
    private var babyName: String { profile?.name ?? "Baby" }
    private var scopedReadStates: [AgeGuideReadState] {
        readStates.filter { $0.matchesProfile(profile?.id) }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section("Overview") {
                Text(guide.overview)
                    .font(.body)
            }

            Section("Development topics") {
                ForEach(guide.developmentalTopics) { topic in
                    AgeGuideTopicRow(topic: topic)
                }
            }

            if !guide.playIdeas.isEmpty {
                bulletSection("Play ideas", systemImage: "sparkles", values: guide.playIdeas)
            }
            if !guide.sleepNotes.isEmpty {
                bulletSection("Sleep and routine", systemImage: "moon.stars.fill", values: guide.sleepNotes)
            }
            if !guide.feedingNotes.isEmpty {
                bulletSection("Feeding notes", systemImage: "fork.knife", values: guide.feedingNotes)
            }
            if !guide.careNotes.isEmpty {
                bulletSection("Care notes", systemImage: "heart.text.square.fill", values: guide.careNotes)
            }
            if !guide.safetyNotes.isEmpty {
                bulletSection("Safety notes", systemImage: "shield.lefthalf.filled", values: guide.safetyNotes)
            }

            Section("Milestone prompts") {
                ForEach(guide.milestonePrompts) { prompt in
                    AgeGuidePromptRow(prompt: prompt) {
                        selectedTemplate = prompt.milestoneTemplate
                    }
                }
            }

            Section("Sources and note") {
                ForEach(guide.sourceReferences) { source in
                    if let url = source.sourceURL {
                        Link(destination: url) {
                            sourceLabel(source)
                        }
                    } else {
                        sourceLabel(source)
                    }
                }
                Text(guide.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MilestonePalette.background)
        .navigationTitle(guide.ageLabel)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTemplate) { template in
            NavigationStack {
                MilestoneEditorView(template: template)
            }
        }
        .task {
            AgeGuideService.shared.markGuideRead(
                guide,
                in: modelContext,
                readStates: scopedReadStates,
                profileID: profile?.id
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(guide.isCheckpointAge ? "Checkpoint age guide" : "Monthly guide", systemImage: guide.isCheckpointAge ? "checklist.checked" : "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MilestonePalette.accent)

            Text("\(babyName) at \(guide.ageLabel)")
                .font(.title2.bold())

            if let profile,
               let reachedDate = AgeGuideService.shared.monthlyBirthdayDate(
                for: profile,
                ageMonth: guide.ageMonth
               ) {
                Text("Reached this age on \(reachedDate.formatted(date: .abbreviated, time: .omitted)). \(babyName) is \(DateFormatting.age(from: profile.birthDate)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.pink.opacity(0.18), Color.orange.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private func bulletSection(
        _ title: String,
        systemImage: String,
        values: [String]
    ) -> some View {
        Section {
            ForEach(values, id: \.self) { value in
                Label(value, systemImage: systemImage)
            }
        } header: {
            Text(title)
        }
    }

    private func sourceLabel(_ source: ContentSourceReference) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(source.sourceName)
                .font(.subheadline.weight(.semibold))
            if let notes = source.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AgeGuideTopicRow: View {
    let topic: AgeGuideTopic

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: topic.category.systemImage)
                .foregroundStyle(MilestonePalette.accent)
                .frame(width: 34, height: 34)
                .background(Color.pink.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.subheadline.weight(.semibold))
                Text(topic.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(topic.category.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MilestonePalette.accent)
            }
        }
    }
}

private struct AgeGuidePromptRow: View {
    let prompt: MilestonePrompt
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(prompt.title, systemImage: prompt.suggestedCategory.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prompt.suggestedCategory.tint)
            Text(prompt.promptText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: action) {
                Label("Add milestone", systemImage: "plus.circle.fill")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(prompt.suggestedCategory.tint)
        }
        .padding(.vertical, 4)
    }
}
