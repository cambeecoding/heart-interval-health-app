import SwiftUI

struct WatchIntervalView: View {
    @ObservedObject var viewModel: WatchViewModel

    var body: some View {
        VStack(spacing: 4) {
            // Phase badge
            Text(phaseLabel)
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(phaseColor.opacity(0.15))
                .foregroundColor(phaseColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Countdown
            Text("\(viewModel.intervalCountdown)")
                .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                .foregroundColor(phaseColor)

            // Round
            if let phase = viewModel.intervalPhase {
                Text(roundText(phase))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }

            // Round dots
            if viewModel.intervalRound > 0 {
                roundDots
                    .padding(.top, 2)
            }

            // HR
            if let bpm = viewModel.currentBPM {
                Text("\(Int(bpm.rounded()))")
                    .font(.system(size: 20, weight: .light, design: .rounded))
                    .foregroundColor(hrColor)
                    .padding(.top, 4)
                Text("bpm")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    private var phaseLabel: String {
        switch viewModel.intervalPhase {
        case "warmup": return "WARM UP"
        case "work": return "WORK"
        case "rest": return "REST"
        case "finished": return "DONE"
        default: return ""
        }
    }

    private var phaseColor: Color {
        switch viewModel.intervalPhase {
        case "warmup": return .orange
        case "work": return .green
        case "rest": return .cyan
        case "finished": return .white
        default: return .white
        }
    }

    private var hrColor: Color {
        switch viewModel.intervalPhase {
        case "work": return .red
        case "rest": return .cyan
        default: return .white.opacity(0.7)
        }
    }

    private func roundText(_ phase: String) -> String {
        switch phase {
        case "warmup": return "until intervals"
        case "work": return "Round \(viewModel.intervalRound)"
        case "rest": return "Rest"
        case "finished": return "Complete"
        default: return ""
        }
    }

    @ViewBuilder
    private var roundDots: some View {
        let total = max(1, viewModel.intervalTotalRounds)
        HStack(spacing: 3) {
            ForEach(1...total, id: \.self) { i in
                Circle()
                    .fill(i < viewModel.intervalRound ? .green
                        : i == viewModel.intervalRound ? .orange
                        : Color.white.opacity(0.12))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
