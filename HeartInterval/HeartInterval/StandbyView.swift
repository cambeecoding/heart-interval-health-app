import SwiftUI

struct StandbyView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    private let speakOptions:   [(label: String, value: Int)] = [
        ("Off", 0), ("30s", 30), ("1 min", 60), ("2 min", 120), ("3 min", 180)
    ]
    private let summaryOptions: [(label: String, value: Int)] = [
        ("Off", 0), ("2 min", 120), ("3 min", 180), ("5 min", 300), ("10 min", 600)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("BeatZone")
                    .font(.title)
                    .fontWeight(.light)
                    .foregroundColor(.white.opacity(0.6))

                let ble   = viewModel.bleSourceStatus
                let watch = viewModel.watchSourceStatus

                VStack(spacing: 4) {
                    if !ble.message.isEmpty {
                        StatusRow(message: ble.message, isReady: ble.isReady)
                    }
                    if !watch.message.isEmpty {
                        StatusRow(message: watch.message, isReady: watch.isReady)
                    }
                    if viewModel.shouldShowSourceInstruction {
                        Text("Start a workout on your Apple Watch or Garmin,\nor put your HR monitor in broadcast mode")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 6)

                Spacer().frame(height: 32)

                // ── Announcement settings ─────────────────────────────────
                VStack(spacing: 14) {
                    AnnouncementPickerRow(
                        label: "Speak every",
                        options: speakOptions,
                        selected: $viewModel.speakInterval
                    )
                    AnnouncementPickerRow(
                        label: "Summary every",
                        options: summaryOptions,
                        selected: $viewModel.summaryInterval
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

                // ── HR zone slider ────────────────────────────────────────
                HRRangeSlider(range: 80...180, low: $viewModel.minHR, high: $viewModel.maxHR)
                    .padding(.bottom, 28)

                Button(action: { viewModel.startExercise() }) {
                    Text("START")
                        .font(.headline)
                        .frame(width: 160, height: 52)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
        }
    }
}

// MARK: - Status row

private struct StatusRow: View {
    let message: String
    let isReady: Bool
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(isReady ? .green.opacity(0.8) : .orange.opacity(0.7))
    }
}

// MARK: - Picker row

private struct AnnouncementPickerRow: View {
    let label: String
    let options: [(label: String, value: Int)]
    @Binding var selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))

            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    Button(action: { selected = option.value }) {
                        Text(option.label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(selected == option.value ? Color.blue : Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}
