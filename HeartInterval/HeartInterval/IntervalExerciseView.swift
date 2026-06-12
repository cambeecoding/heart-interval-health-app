import SwiftUI

struct IntervalExerciseView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {

                    // Phase badge
                    phaseBadge
                        .padding(.top, 16)

                    // Round counter
                    roundLabel
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))

                    // Countdown
                    Text("\(viewModel.intervalCountdown)")
                        .font(.system(size: 80, weight: .ultraLight, design: .rounded))
                        .foregroundColor(phaseColor)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: viewModel.intervalCountdown)

                    Text("seconds remaining")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(phaseColor)
                                .frame(width: geo.size.width * progressFraction)
                                .animation(.linear(duration: 1), value: viewModel.intervalCountdown)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 60)

                    // Round dots
                    roundDots
                        .padding(.top, 4)

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 8)

                    // HR display
                    hrSourceBadge

                    if let hr = viewModel.currentHR {
                        Text("\(hr)")
                            .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: viewModel.currentHR)

                        Text("bpm")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.3))

                        if let avg = viewModel.totalAvgHR {
                            Text("avg \(avg)")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(.yellow.opacity(0.7))
                        }
                    } else {
                        Text("--")
                            .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Waiting for heart rate…")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.3))
                    }

                    Text(formattedTime(viewModel.elapsedSeconds) + " elapsed")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.top, 4)
                }
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.08))
                VStack(spacing: 6) {
                    Button(action: { viewModel.skipInterval() }) {
                        Text("SKIP →")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button(action: { viewModel.pauseExercise() }) {
                        Text("PAUSE")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
                .background(Color.black)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var phaseBadge: some View {
        if let phase = viewModel.intervalPhase {
            Text(phaseLabel(phase))
                .font(.system(size: 13, weight: .bold))
                .tracking(3)
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
                .background(phaseColor.opacity(0.15))
                .foregroundColor(phaseColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var roundLabel: some View {
        if let phase = viewModel.intervalPhase {
            switch phase {
            case .warmup:
                Text("Intervals start after warm-up")
            case .work(let round):
                Text("Round \(round) of \(viewModel.intervalConfig.rounds)")
            case .rest(let round):
                Text("Rest before round \(round + 1)")
            case .finished:
                Text("Complete")
            }
        }
    }

    private var roundDots: some View {
        HStack(spacing: 5) {
            ForEach(1...viewModel.intervalConfig.rounds, id: \.self) { round in
                Circle()
                    .fill(dotColor(for: round))
                    .frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder
    private var hrSourceBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: hrSourceIcon)
                .font(.caption2)
            Text(hrSourceLabel)
                .font(.caption2)
        }
        .foregroundColor(.white.opacity(0.3))
    }

    // MARK: - Helpers

    private var phaseColor: Color {
        guard let phase = viewModel.intervalPhase else { return .white }
        switch phase {
        case .warmup: return .orange
        case .work: return .green
        case .rest: return .cyan
        case .finished: return .white
        }
    }

    private func phaseLabel(_ phase: IntervalPhase) -> String {
        switch phase {
        case .warmup: return "WARM UP"
        case .work: return "WORK"
        case .rest: return "REST"
        case .finished: return "DONE"
        }
    }

    private var progressFraction: CGFloat {
        let duration: Int
        switch viewModel.intervalPhase {
        case .warmup: duration = viewModel.intervalConfig.warmupDuration
        case .work: duration = viewModel.intervalConfig.workDuration
        case .rest: duration = viewModel.intervalConfig.restDuration
        default: duration = 1
        }
        guard duration > 0 else { return 0 }
        return CGFloat(duration - viewModel.intervalCountdown) / CGFloat(duration)
    }

    private func dotColor(for round: Int) -> Color {
        guard let phase = viewModel.intervalPhase else { return Color.white.opacity(0.1) }
        switch phase {
        case .work(let current):
            if round < current { return .green }
            if round == current { return .orange }
            return Color.white.opacity(0.1)
        case .rest(let current):
            if round <= current { return .green }
            return Color.white.opacity(0.1)
        case .warmup:
            return Color.white.opacity(0.1)
        case .finished:
            return .green
        }
    }

    private var hrSourceIcon: String {
        switch viewModel.hrSource {
        case .ble: return "antenna.radiowaves.left.and.right"
        case .watch: return "applewatch"
        case .healthKit, .none: return "heart.fill"
        }
    }

    private var hrSourceLabel: String {
        switch viewModel.hrSource {
        case .ble: return "Bluetooth HR"
        case .watch: return "Apple Watch"
        case .healthKit, .none: return "Apple Health"
        }
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
