import SwiftUI

struct NightLightView: View {
    @ObservedObject private var router = DeepLinkRouter.shared
    @StateObject private var viewModel = NightLightViewModel()

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.022, blue: 0.045)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    presets
                    NightLightControlsView(viewModel: viewModel)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Night Light")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(
            Color(red: 0.025, green: 0.022, blue: 0.045),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Settings")
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $viewModel.isActive) {
            NightLightFullScreenView(viewModel: viewModel)
        }
        .task { consumePendingCommand() }
        .onChange(of: router.pendingNightLightCommand) { _, _ in
            consumePendingCommand()
        }
        .onDisappear {
            viewModel.stopSoundPreview()
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                RadialGradient(
                    colors: [
                        viewModel.settings.resolvedColor.opacity(0.48),
                        viewModel.settings.resolvedColor.opacity(0.12),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 170
                )
                NightLightShapeView(
                    shape: viewModel.settings.selectedShape,
                    color: viewModel.settings.resolvedColor,
                    softness: viewModel.settings.softness
                )
                .frame(width: 132, height: 132)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)

            VStack(spacing: 6) {
                Text("A softer way into the room")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Dim, warm light with optional sound and a gentle fade timer.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.start()
            } label: {
                Label("Start", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.white, Color(red: 1, green: 0.83, blue: 0.58)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            }
            .buttonStyle(.plain)

            Text("Starts with the color, style, sound, and timer selected below.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("One-tap presets")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("Tap to start")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
            }
            NightLightPresetPicker(
                viewModel: viewModel,
                startsImmediately: true
            )
        }
    }

    private func consumePendingCommand() {
        guard let command = router.consumeNightLightCommand() else { return }
        switch command {
        case .open:
            break
        case .start(let preset):
            viewModel.start(preset: preset)
        case .stop:
            viewModel.stop()
        }
    }
}
