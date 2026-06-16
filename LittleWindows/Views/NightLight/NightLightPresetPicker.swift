import SwiftUI

struct NightLightPresetPicker: View {
    @ObservedObject var viewModel: NightLightViewModel
    var startsImmediately = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(NightLightPresetService.presets) { preset in
                    Button {
                        if startsImmediately {
                            viewModel.start(preset: preset.id)
                        } else {
                            viewModel.applyPreset(preset.id)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: preset.systemImage)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(preset.color.color)
                                .frame(width: 42, height: 42)
                                .background(
                                    preset.color.color.opacity(0.16),
                                    in: Circle()
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        .frame(width: 142, alignment: .leading)
                        .padding(16)
                        .background(
                            viewModel.settings.selectedPreset == preset.id
                                ? Color.white.opacity(0.13)
                                : Color.white.opacity(0.065),
                            in: RoundedRectangle(cornerRadius: 22)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(
                                    viewModel.settings.selectedPreset == preset.id
                                        ? preset.color.color.opacity(0.62)
                                        : .white.opacity(0.08),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
