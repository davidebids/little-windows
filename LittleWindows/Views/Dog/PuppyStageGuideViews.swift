import SwiftData
import SwiftUI

struct PuppyStageGuideCard: View {
    let profile: CareProfile
    let guide: PuppyStageGuide
    var onDismiss: () -> Void
    var onRead: () -> Void
    var onAddMilestone: () -> Void
    var onLogTraining: () -> Void
    var isTrainingTimerActive = false

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

            HStack(spacing: 8) {
                Button(action: onRead) {
                    PuppyStageGuideActionLabel(
                        title: "Read guide",
                        systemImage: "book.pages.fill"
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .accessibilityIdentifier("puppy-stage-guide.read")

                Button(action: onAddMilestone) {
                    PuppyStageGuideActionLabel(
                        title: "Add milestone",
                        systemImage: "heart.fill"
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("puppy-stage-guide.add-milestone")

                Button(action: onLogTraining) {
                    PuppyStageGuideActionLabel(
                        title: isTrainingTimerActive ? "Training active" : "Log training",
                        systemImage: isTrainingTimerActive ? "timer" : "graduationcap.fill"
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .disabled(isTrainingTimerActive)
                .accessibilityIdentifier("puppy-stage-guide.log-training")
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

private struct PuppyStageGuideActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 20)
            Text(title)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        .contentShape(Rectangle())
    }
}

struct PuppyStageGuideDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PuppyStageGuideReadState.updatedAt) private var readStates: [PuppyStageGuideReadState]
    let guide: PuppyStageGuide
    let profile: CareProfile?
    let showsCloseButton: Bool
    @State private var editorRoute: EventEditorRoute?
    @State private var selectedMilestoneTemplate: MilestoneTemplate?

    init(guide: PuppyStageGuide, profile: CareProfile?, showsCloseButton: Bool = false) {
        self.guide = guide
        self.profile = profile
        self.showsCloseButton = showsCloseButton
        let selectedProfileID = profile?.id
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        _readStates = Query(FetchDescriptor<PuppyStageGuideReadState>(
            predicate: #Predicate { $0.profileID == selectedProfileID },
            sortBy: [SortDescriptor(\PuppyStageGuideReadState.updatedAt)]
        ))
    }

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
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .accessibilityIdentifier("puppy-stage-guide.close")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            NavigationStack {
                EventEditorView(type: route.type, event: route.event) { event in
                    event.profileID = event.profileID ?? profile?.id
                    event.profileTypeSnapshot = .dog
                    _ = PersistenceService.save(context: modelContext)
                }
            }
        }
        .sheet(item: $selectedMilestoneTemplate) { template in
            NavigationStack {
                MilestoneEditorView(template: template, profileID: profile?.id)
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
