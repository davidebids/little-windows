import SwiftData
import SwiftUI

struct PuppyStageGuideCard: View {
    let profile: CareProfile
    let guide: PuppyStageGuide
    var onDismiss: () -> Void
    var onRead: () -> Void
    var onAddMilestone: () -> Void
    var onLogTraining: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("\(profile.name)'s Stage", systemImage: "pawprint.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                    Text("\(profile.name) at \(guide.title)")
                        .font(.title3.bold())
                    Text(guide.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("Read guide", systemImage: "book.pages.fill", action: onRead)
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                Button("Add milestone", systemImage: "heart.fill", action: onAddMilestone)
                    .buttonStyle(.bordered)
                Button("Log training", systemImage: "graduationcap.fill", action: onLogTraining)
                    .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(15)
        .background(
            LinearGradient(
                colors: [Color.teal.opacity(0.16), Color.orange.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.teal.opacity(0.16), lineWidth: 0.5)
        }
    }
}

struct PuppyStageGuideDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PuppyStageGuideReadState.updatedAt) private var readStates: [PuppyStageGuideReadState]
    let guide: PuppyStageGuide
    let profile: CareProfile?
    @State private var editorRoute: EventEditorRoute?
    @State private var selectedMilestoneTemplate: MilestoneTemplate?

    private var scopedReadStates: [PuppyStageGuideReadState] {
        readStates.filter { $0.matchesProfile(profile?.id) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Puppy Stage Guide", systemImage: "pawprint.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                    Text(profile.map { "\($0.name) at \(guide.title)" } ?? guide.title)
                        .font(.title2.bold())
                    Text(guide.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(guide.overview)
                        .font(.body)
                        .padding(.top, 4)
                }
                .listRowBackground(Color.teal.opacity(0.08))
            }

            Section("Topics") {
                ForEach(guide.topics) { topic in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(topic.category.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.teal)
                        Text(topic.title)
                            .font(.headline)
                        Text(topic.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Milestone prompts") {
                ForEach(guide.milestonePrompts) { prompt in
                    Button {
                        selectedMilestoneTemplate = MilestoneTemplate(
                            title: prompt.title,
                            category: prompt.suggestedCategory
                        )
                    } label: {
                        Label(prompt.title, systemImage: "heart.fill")
                    }
                }
            }

            Section("Training prompts") {
                ForEach(guide.trainingPrompts) { prompt in
                    Button {
                        editorRoute = EventEditorRoute(type: .training)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(prompt.title, systemImage: "graduationcap.fill")
                            Text(prompt.promptText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !guide.careNotes.isEmpty {
                Section("Care notes") {
                    ForEach(guide.careNotes, id: \.self) { Text($0) }
                }
            }

            if !guide.vetCareNotes.isEmpty {
                Section("Vet care") {
                    ForEach(guide.vetCareNotes, id: \.self) { Text($0) }
                }
            }

            Section("Safety note") {
                Text("This guide is general tracking support, not veterinary diagnosis or a substitute for your veterinarian or trainer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorRoute) { route in
            NavigationStack {
                EventEditorView(type: route.type, event: route.event) { event in
                    event.profileID = event.profileID ?? profile?.id
                    event.profileTypeSnapshot = .dog
                    try? modelContext.save()
                }
            }
        }
        .sheet(item: $selectedMilestoneTemplate) { template in
            NavigationStack {
                MilestoneEditorView(template: template)
            }
        }
        .task {
            PuppyStageGuideService.shared.markGuideRead(
                guide,
                in: modelContext,
                readStates: scopedReadStates,
                profileID: profile?.id
            )
        }
    }
}
