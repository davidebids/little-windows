import SwiftUI

struct WatchNightLightView: View {
    var close: () -> Void

    // Adjust the rendered red intensity; watchOS manages display brightness and wake time.
    @State private var intensity = 0.6
    @State private var showsControls = true
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        ZStack {
            Color(red: intensity, green: 0, blue: 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { showsControls.toggle() }
                .accessibilityLabel("Red night light")
                .accessibilityValue("\(Int(intensity * 100)) percent")
                .accessibilityHint("Tap to show or hide controls. Turn the Digital Crown to dim.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showsControls.toggle() }
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: intensity = min(1, intensity + 0.1)
                    case .decrement: intensity = max(0.1, intensity - 0.1)
                    @unknown default: break
                    }
                }

            if showsControls && !isLuminanceReduced {
                VStack(spacing: 8) {
                    Text("Night Light")
                        .font(.headline)
                    Text("Turn Crown to dim")
                        .font(.caption2)
                    Button("Close", action: close)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.15), in: Capsule())
                        .accessibilityIdentifier("watch.night-light.close")
                }
                .padding(12)
                .foregroundStyle(.red)
                .background(.black, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .focusable()
        .digitalCrownRotation(
            $intensity,
            from: 0.1,
            through: 1,
            by: 0.05,
            sensitivity: .low,
            isHapticFeedbackEnabled: false
        )
        .accessibilityAction(named: Text("Close night light"), close)
        .task(id: showsControls) {
            guard showsControls && !voiceOverEnabled else { return }
            do {
                try await Task.sleep(for: .seconds(4))
                showsControls = false
            } catch {
                // A tap or dismissal cancels the pending hide.
            }
        }
    }
}
