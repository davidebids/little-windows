import SwiftUI

struct NightLightTimerPicker: View {
    @ObservedObject var viewModel: NightLightViewModel
    @State private var customMinutes = 25

    private let options = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.timerService.isRunning {
                HStack {
                    Label(
                        viewModel.timerService.remainingText,
                        systemImage: "timer"
                    )
                    .font(.title3.monospacedDigit().weight(.semibold))
                    Spacer()
                    Button("Cancel", role: .destructive) {
                        viewModel.cancelTimer()
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        timerButton(title: "Off", minutes: nil)
                        ForEach(options, id: \.self) { minutes in
                            timerButton(title: "\(minutes)m", minutes: minutes)
                        }
                    }
                }

                HStack {
                    Stepper(
                        "Custom: \(customMinutes) min",
                        value: $customMinutes,
                        in: 1...120,
                        step: 5
                    )
                    Button("Set") {
                        viewModel.startTimer(minutes: customMinutes)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
            }
        }
    }

    private func timerButton(
        title: String,
        minutes: Int?
    ) -> some View {
        Button(title) {
            viewModel.settings.sleepTimerMinutes = minutes
            if let minutes, viewModel.isActive {
                viewModel.startTimer(minutes: minutes)
            } else if minutes == nil {
                viewModel.cancelTimer()
                viewModel.settingsDidChange()
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(
            viewModel.settings.sleepTimerMinutes == minutes ? .black : .white
        )
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            viewModel.settings.sleepTimerMinutes == minutes
                ? Color.white
                : Color.white.opacity(0.08),
            in: Capsule()
        )
    }
}
