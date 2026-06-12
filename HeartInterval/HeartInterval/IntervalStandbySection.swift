import SwiftUI

struct IntervalStandbySection: View {
    @ObservedObject var viewModel: ExerciseViewModel

    private let presets: [(label: String, config: IntervalConfig)] = [
        ("Tabata 20/10", .tabata),
        ("30/30", .thirtyThirty),
        ("PT 50/20", .pt),
        ("EMOM", .emom),
        ("Long 3m/1m", .long),
    ]

    var body: some View {
        VStack(spacing: 12) {
            StepperRow(label: "Work", value: $viewModel.intervalConfig.workDuration,
                       range: 5...300, step: 5, color: .green, format: formatSeconds)
            StepperRow(label: "Rest", value: $viewModel.intervalConfig.restDuration,
                       range: 5...300, step: 5, color: .cyan, format: formatSeconds)
            StepperRow(label: "Rounds", value: $viewModel.intervalConfig.rounds,
                       range: 1...50, step: 1, color: .white, format: { "\($0)" })
            StepperRow(label: "Warm-up", value: $viewModel.intervalConfig.warmupDuration,
                       range: 0...600, step: 30, color: .orange,
                       format: { $0 == 0 ? "Off" : formatSeconds($0) },
                       sublabel: "optional")

            Text("Total: \(formatTime(viewModel.intervalConfig.totalDuration))")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.35))

            // Presets
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))

                HStack(spacing: 5) {
                    ForEach(presets, id: \.label) { preset in
                        Button(action: { viewModel.intervalConfig = preset.config }) {
                            Text(preset.label)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(viewModel.intervalConfig == preset.config
                                    ? Color.orange.opacity(0.2) : Color.white.opacity(0.06))
                                .foregroundColor(viewModel.intervalConfig == preset.config
                                    ? .orange : .white.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(viewModel.intervalConfig == preset.config
                                            ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }

    private func formatSeconds(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m \(r)s"
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Stepper row

private struct StepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let color: Color
    let format: (Int) -> String
    var sublabel: String? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                if let sub = sublabel {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Button(action: { value = max(range.lowerBound, value - step) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .foregroundColor(.white.opacity(0.6))

                Text(format(value))
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(color)
                    .frame(minWidth: 40)

                Button(action: { value = min(range.upperBound, value + step) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }
}
