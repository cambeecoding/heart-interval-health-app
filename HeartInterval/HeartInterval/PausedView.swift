import SwiftUI

struct PausedView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // Frozen elapsed time shown at top
                Text(formattedTime(viewModel.elapsedSeconds))
                    .font(.system(size: 22, weight: .light, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 56)

                Text("PAUSED")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(2)
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(.top, 6)

                if let phase = viewModel.intervalPhase {
                    intervalPausedInfo(phase: phase)
                        .padding(.top, 16)
                }

                Spacer()

                MetricRow(label: "Session avg", value: viewModel.totalAvgHR, unit: "bpm", valueColor: .yellow)
                    .padding(.bottom, 24)

                MetricRow(label: "Current", value: viewModel.currentHR, unit: "bpm", valueColor: .white.opacity(0.5))

                Spacer()

                HStack(spacing: 20) {
                    Button(action: { viewModel.endExercise() }) {
                        Text("END")
                            .font(.headline)
                            .frame(width: 120, height: 52)
                            .background(Color.red.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: { viewModel.continueExercise() }) {
                        Text("CONTINUE")
                            .font(.headline)
                            .frame(width: 140, height: 52)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }

    @ViewBuilder
    private func intervalPausedInfo(phase: IntervalPhase) -> some View {
        VStack(spacing: 4) {
            let label: String = {
                switch phase {
                case .warmup: return "WARM UP"
                case .work: return "WORK"
                case .rest: return "REST"
                case .finished: return "DONE"
                }
            }()
            let color: Color = {
                switch phase {
                case .warmup: return .orange
                case .work: return .green
                case .rest: return .cyan
                case .finished: return .white
                }
            }()

            Text(label)
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundColor(color)

            Text("\(viewModel.intervalCountdown)s remaining")
                .font(.caption)
                .foregroundColor(.white.opacity(0.35))

            if case .work(let round) = phase {
                Text("Round \(round) of \(viewModel.intervalConfig.rounds)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
