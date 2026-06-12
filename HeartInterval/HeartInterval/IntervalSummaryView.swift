import SwiftUI

struct IntervalSummaryView: View {
    @ObservedObject var viewModel: ExerciseViewModel
    let summary: SessionSummary

    private var data: IntervalSessionData { summary.intervalData! }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

                    // Duration + label
                    Text(formattedTime(summary.durationSeconds))
                        .font(.system(size: 22, weight: .light, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))

                    Text("INTERVAL SESSION")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(2)
                        .padding(.top, 4)

                    Text("\(data.config.rounds) rounds · \(data.config.workDuration)s/\(data.config.restDuration)s · \(summary.activityType.label)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.top, 2)

                    // Stats row
                    HStack(spacing: 0) {
                        statCell(value: summary.avgHR, label: "avg bpm", color: .yellow)
                        statCell(value: peakHR, label: "peak bpm", color: .red)
                        statCell(value: avgRecovery, label: "avg recovery", color: .cyan)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    // HR graph with interval bands
                    HRGraph(
                        samples: summary.samples,
                        minZone: summary.minHR,
                        maxZone: summary.maxHR,
                        sessionStart: summary.startDate,
                        sessionEnd: summary.endDate
                    )
                    .frame(height: 180)
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 24)

                    // Peak HR per round
                    if !data.rounds.isEmpty {
                        peakHRChart
                            .padding(.horizontal, 24)
                    }

                    Spacer().frame(height: 20)

                    // Recovery card
                    if data.rounds.count > 1 {
                        recoveryCard
                            .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: 120)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.08))

                VStack(spacing: 12) {
                    if let error = viewModel.summaryError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    Button(action: { viewModel.saveAndDismiss(summary: summary) }) {
                        Group {
                            if viewModel.isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save to Health")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(viewModel.isSaving)
                    .padding(.horizontal, 40)

                    Button(action: { viewModel.dismissSummary() }) {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .disabled(viewModel.isSaving)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                }
                .padding(.top, 12)
                .background(Color.black)
            }
        }
    }

    // MARK: - Stats

    private var peakHR: Int? {
        let peaks = data.rounds.map(\.peakHR).filter { $0 > 0 }
        guard let max = peaks.max() else { return nil }
        return Int(max.rounded())
    }

    private var avgRecovery: Int? {
        let drops = data.rounds.compactMap(\.recoveryDrop)
        guard !drops.isEmpty else { return nil }
        return Int((drops.reduce(0, +) / Double(drops.count)).rounded())
    }

    private func statCell(value: Int?, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value.map { "\($0)" } ?? "--")
                .font(.system(size: 22, weight: .light, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Peak HR chart

    private var peakHRChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PEAK HR PER ROUND")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.5)

            let peaks = data.rounds.map(\.peakHR)
            let maxPeak = peaks.max() ?? 1
            let minPeak = peaks.min() ?? 0
            let range = max(maxPeak - minPeak, 10)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(data.rounds, id: \.roundNumber) { round in
                    VStack(spacing: 2) {
                        Text("\(Int(round.peakHR.rounded()))")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.5))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.7))
                            .frame(height: max(4, CGFloat((round.peakHR - minPeak + range * 0.1) / (range * 1.2)) * 70))

                        Text("R\(round.roundNumber)")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90)
        }
    }

    // MARK: - Recovery card

    private var recoveryCard: some View {
        let drops = data.rounds.compactMap(\.recoveryDrop)
        let best = drops.enumerated().max(by: { $0.element < $1.element })
        let worst = drops.enumerated().min(by: { $0.element < $1.element })

        let firstHalf = Array(drops.prefix(drops.count / 2))
        let secondHalf = Array(drops.suffix(drops.count / 2))
        let firstAvg = firstHalf.isEmpty ? 0.0 : firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.isEmpty ? 0.0 : secondHalf.reduce(0, +) / Double(secondHalf.count)

        return VStack(alignment: .leading, spacing: 6) {
            Text("RECOVERY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)

            VStack(alignment: .leading, spacing: 3) {
                if let avg = avgRecovery {
                    recoveryLine("Avg drop per rest:", highlight: "−\(avg) bpm", color: .cyan)
                }
                if let b = best, let w = worst {
                    HStack(spacing: 0) {
                        Text("Best: R\(b.offset + 1) ")
                            .foregroundColor(.white.opacity(0.4))
                        Text("−\(Int(b.element.rounded())) bpm")
                            .foregroundColor(.cyan)
                        Text(" · Worst: R\(w.offset + 1) ")
                            .foregroundColor(.white.opacity(0.4))
                        Text("−\(Int(w.element.rounded())) bpm")
                            .foregroundColor(.orange)
                    }
                    .font(.system(size: 11))
                }
                if !firstHalf.isEmpty && !secondHalf.isEmpty {
                    HStack(spacing: 0) {
                        Text("First half avg: ")
                            .foregroundColor(.white.opacity(0.4))
                        Text("−\(Int(firstAvg.rounded())) bpm")
                            .foregroundColor(.cyan)
                        Text(" · Last half avg: ")
                            .foregroundColor(.white.opacity(0.4))
                        Text("−\(Int(secondAvg.rounded())) bpm")
                            .foregroundColor(.orange)
                    }
                    .font(.system(size: 11))
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func recoveryLine(_ label: String, highlight: String, color: Color) -> some View {
        HStack(spacing: 0) {
            Text(label + " ")
                .foregroundColor(.white.opacity(0.4))
            Text(highlight)
                .foregroundColor(color)
                .fontWeight(.medium)
        }
        .font(.system(size: 11))
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
