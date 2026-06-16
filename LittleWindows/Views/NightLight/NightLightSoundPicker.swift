import SwiftUI

struct NightLightSoundPicker: View {
    @ObservedObject var viewModel: NightLightViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Menu {
                ForEach(NightLightSound.allCases) { sound in
                    Button {
                        viewModel.selectSound(sound)
                    } label: {
                        Label(sound.displayName, systemImage: sound.systemImage)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.settings.selectedSound.systemImage)
                        .foregroundStyle(.orange)
                    Text(viewModel.settings.selectedSound.displayName)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(14)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            }

            if viewModel.settings.selectedSound != .none {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.white.opacity(0.55))
                    Slider(
                        value: $viewModel.settings.soundVolume,
                        in: 0...0.7
                    )
                    .tint(.orange)
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .onChange(of: viewModel.settings.soundVolume) { _, volume in
                    viewModel.updateSoundVolume(volume)
                }

                Button {
                    viewModel.toggleSoundPreview()
                } label: {
                    Label(
                        viewModel.previewingSound == viewModel.settings.selectedSound
                            ? "Stop Preview"
                            : "Preview",
                        systemImage: viewModel.previewingSound == viewModel.settings.selectedSound
                            ? "stop.fill"
                            : "play.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let status = viewModel.audioService.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let previewingSound = viewModel.previewingSound {
                Label(
                    "Previewing \(previewingSound.displayName). Choose another sound to compare.",
                    systemImage: "speaker.wave.2.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text("Choose a sound to hear a 10-second preview before starting.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }
}
