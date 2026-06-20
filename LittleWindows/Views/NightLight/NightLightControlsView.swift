import SwiftUI

struct NightLightControlsView: View {
    @ObservedObject var viewModel: NightLightViewModel
    @State private var showingShapes = false
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 14 : 20) {
            brightnessControls
            if !compact {
                colorControls
                shapeAndGlowControls
                animationControls
                soundControls
                timerControls
                comfortNote
            } else {
                compactControls
            }
        }
        .sheet(isPresented: $showingShapes) {
            NightLightShapePicker(selection: $viewModel.settings.selectedShape)
                .onDisappear { viewModel.settingsDidChange() }
        }
    }

    private var brightnessControls: some View {
        NightLightPanel(title: "Brightness", systemImage: "sun.max.fill") {
            HStack(spacing: 12) {
                Button(action: viewModel.dimmer) {
                    Label("Dimmer", systemImage: "minus")
                }
                .buttonStyle(NightLightSmallButtonStyle())

                Slider(
                    value: $viewModel.settings.brightness,
                    in: 0.03...0.8
                )
                .tint(viewModel.settings.resolvedColor)
                .onChange(of: viewModel.settings.brightness) { _, _ in
                    viewModel.settingsDidChange()
                }

                Button(action: viewModel.brighter) {
                    Label("Brighter", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(NightLightSmallButtonStyle())
                .accessibilityLabel("Brighter")
            }

            HStack(spacing: 8) {
                quickBrightness("Dim", 0.1)
                quickBrightness("Medium", 0.28)
                quickBrightness("Bright", 0.52)
                Toggle("Extra Soft", isOn: $viewModel.settings.extraSoft)
                    .toggleStyle(.button)
                    .tint(.orange.opacity(0.75))
                    .font(.caption.weight(.semibold))
                    .onChange(of: viewModel.settings.extraSoft) { _, _ in
                        viewModel.settingsDidChange()
                    }
            }
        }
    }

    private var colorControls: some View {
        NightLightPanel(title: "Color", systemImage: "paintpalette.fill") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(NightLightColor.allCases) { option in
                        Button {
                            viewModel.settings.selectedColor = option
                            viewModel.settings.selectedPreset = nil
                            viewModel.settingsDidChange()
                        } label: {
                            VStack(spacing: 7) {
                                Circle()
                                    .fill(
                                        option == .custom
                                            ? viewModel.settings.resolvedColor
                                            : option.color
                                    )
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if viewModel.settings.selectedColor == option {
                                            Circle().stroke(.white, lineWidth: 3)
                                        }
                                    }
                                Text(option.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .frame(width: 62)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.settings.selectedColor == .custom {
                ColorPicker(
                    "Custom light color",
                    selection: Binding(
                        get: { viewModel.settings.resolvedColor },
                        set: { color in
                            viewModel.settings.customColorHex = color.hexString
                            viewModel.settingsDidChange()
                        }
                    ),
                    supportsOpacity: false
                )
                .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Softness")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    Text("\(Int(viewModel.settings.softness * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.58))
                }
                Slider(value: $viewModel.settings.softness, in: 0.3...1)
                    .tint(.orange)
                    .onChange(of: viewModel.settings.softness) { _, _ in
                        viewModel.settingsDidChange()
                    }
            }
        }
    }

    private var shapeAndGlowControls: some View {
        NightLightPanel(title: "Light Style", systemImage: "circle.hexagongrid.fill") {
            Button {
                showingShapes = true
            } label: {
                HStack {
                    if viewModel.settings.selectedShape == .fullScreenGlow {
                        Image(systemName: "rectangle.inset.filled")
                            .foregroundStyle(.orange)
                    } else {
                        NightLightShapeView(
                            shape: viewModel.settings.selectedShape,
                            color: .orange,
                            softness: 0.3
                        )
                        .frame(width: 22, height: 22)
                    }
                    Text(viewModel.settings.selectedShape.displayName)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    Spacer()
                    Text("30+ shapes")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NightLightGlowMode.allCases) { mode in
                        Button {
                            viewModel.settings.glowMode = mode
                            viewModel.settings.selectedPreset = nil
                            viewModel.settingsDidChange()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: mode.systemImage)
                                    .font(.headline)
                                Text(mode.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(
                                viewModel.settings.glowMode == mode
                                    ? Color.black
                                    : Color.white.opacity(0.78)
                            )
                            .frame(width: 92, height: 66)
                            .background(
                                viewModel.settings.glowMode == mode
                                    ? Color.white
                                    : Color.white.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var animationControls: some View {
        NightLightPanel(title: "Breathing", systemImage: "wind") {
            Toggle(
                "Gentle breathing animation",
                isOn: $viewModel.settings.breathingAnimationEnabled
            )
            .tint(.orange)
            .foregroundStyle(.white)
            .onChange(of: viewModel.settings.breathingAnimationEnabled) { _, _ in
                viewModel.settingsDidChange()
            }

            if viewModel.settings.breathingAnimationEnabled {
                HStack {
                    Picker("Speed", selection: $viewModel.settings.breathingSpeed) {
                        ForEach(NightLightBreathingSpeed.allCases) { speed in
                            Text(speed.displayName).tag(speed)
                        }
                    }
                    Picker(
                        "Intensity",
                        selection: $viewModel.settings.breathingIntensity
                    ) {
                        ForEach(NightLightBreathingIntensity.allCases) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .onChange(of: viewModel.settings.breathingSpeed) { _, _ in
                    viewModel.settingsDidChange()
                }
                .onChange(of: viewModel.settings.breathingIntensity) { _, _ in
                    viewModel.settingsDidChange()
                }
            }
        }
    }

    private var soundControls: some View {
        NightLightPanel(title: "Ambient Sound", systemImage: "speaker.wave.2.fill") {
            NightLightSoundPicker(viewModel: viewModel)
        }
    }

    private var timerControls: some View {
        NightLightPanel(title: "Sleep Timer", systemImage: "timer") {
            NightLightTimerPicker(viewModel: viewModel)
            Toggle(
                "Keep screen awake while active",
                isOn: $viewModel.settings.keepScreenAwake
            )
            .tint(.orange)
            .foregroundStyle(.white)
            .onChange(of: viewModel.settings.keepScreenAwake) { _, _ in
                viewModel.settingsDidChange()
            }
        }
    }

    private var compactControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    viewModel.lightEnabled.toggle()
                } label: {
                    Label(
                        viewModel.lightEnabled ? "Light On" : "Sound Only",
                        systemImage: viewModel.lightEnabled ? "lightbulb.fill" : "lightbulb.slash"
                    )
                }
                .buttonStyle(NightLightSmallButtonStyle())

                Button {
                    viewModel.settings.breathingAnimationEnabled.toggle()
                    viewModel.settingsDidChange()
                } label: {
                    Label(
                        viewModel.settings.breathingAnimationEnabled ? "Breathing On" : "Breathing Off",
                        systemImage: "wind"
                    )
                }
                .buttonStyle(NightLightSmallButtonStyle())

                if viewModel.timerService.isRunning {
                    Label(viewModel.timerService.remainingText, systemImage: "timer")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            if viewModel.settings.selectedSound != .none {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.settings.selectedSound.systemImage)
                        .foregroundStyle(.orange)
                    Text(viewModel.settings.selectedSound.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { viewModel.settings.soundVolume },
                            set: { viewModel.updateSoundVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(.orange)
                    .opacity(viewModel.isSoundMuted ? 0.48 : 1)
                    .accessibilityLabel(
                        "\(viewModel.settings.selectedSound.displayName) volume"
                    )
                    .accessibilityValue(
                        viewModel.isSoundMuted
                            ? "Muted"
                            : "\(Int(viewModel.settings.soundVolume * 100)) percent"
                    )

                    Button {
                        viewModel.toggleSoundMuted()
                    } label: {
                        Image(
                            systemName: viewModel.isSoundMuted
                                ? "speaker.slash.fill"
                                : "speaker.wave.2.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            viewModel.isSoundMuted
                                ? Color.white.opacity(0.72)
                                : Color.orange
                        )
                        .frame(width: 40, height: 40)
                        .background(
                            viewModel.isSoundMuted
                                ? Color.white.opacity(0.08)
                                : Color.orange.opacity(0.14),
                            in: Circle()
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        viewModel.isSoundMuted
                            ? "Unmute ambient sound"
                            : "Mute ambient sound"
                    )
                    .accessibilityHint(
                        viewModel.isSoundMuted
                            ? "Restores the selected volume"
                            : "Keeps the selected volume for later"
                    )
                }

            }
        }
    }

    private var comfortNote: some View {
        Group {
            if viewModel.settings.selectedColor.isBrightWhite
                && viewModel.settings.brightness > 0.35 {
                Label(
                    "Bright light may feel more stimulating at night.",
                    systemImage: "moon.zzz.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("A comfort and convenience tool, without sleep or medical claims.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func quickBrightness(
        _ title: String,
        _ value: Double
    ) -> some View {
        Button(title) {
            viewModel.settings.brightness = value
            viewModel.settingsDidChange()
        }
        .font(.caption2.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.65))
    }
}

struct NightLightPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            content
        }
        .padding(17)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct NightLightSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                .white.opacity(configuration.isPressed ? 0.16 : 0.08),
                in: Capsule()
            )
    }
}

private extension Color {
    var hexString: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}
