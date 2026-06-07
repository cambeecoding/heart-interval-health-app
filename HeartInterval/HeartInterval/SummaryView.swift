import SwiftUI

struct SummaryView: View {
    @ObservedObject var viewModel: ExerciseViewModel
    let summary: SessionSummary

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

                    Text(formattedTime(summary.durationSeconds))
                        .font(.system(size: 22, weight: .light, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))

                    Text("SESSION COMPLETE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(2)
                        .padding(.top, 4)

                    Spacer().frame(height: 36)

                    MetricRow(
                        label: "Session avg",
                        value: summary.avgHR,
                        unit: "bpm",
                        valueColor: .yellow
                    )

                    Spacer().frame(height: 40)

                    HRGraph(
                        samples: summary.samples,
                        minZone: summary.minHR,
                        maxZone: summary.maxHR,
                        sessionStart: summary.startDate,
                        sessionEnd: summary.endDate
                    )
                    .frame(height: 180)
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 32)

                    ZoneDistributionBar(summary: summary)
                        .padding(.horizontal, 32)

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

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - HR Graph

struct HRGraph: View {
    let samples: [HRSample]
    let minZone: Int
    let maxZone: Int
    let sessionStart: Date
    let sessionEnd: Date

    private let sparseGap: TimeInterval = 5

    private var yBounds: (min: Double, max: Double) {
        let bpms = samples.map(\.bpm)
        let dataMin = bpms.min() ?? Double(minZone)
        let dataMax = bpms.max() ?? Double(maxZone)
        let lo = max(40,  min(dataMin, Double(minZone)) - 15)
        let hi = min(220, max(dataMax, Double(maxZone)) + 15)
        return (lo, hi)
    }

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let bounds = yBounds
            let totalDuration = sessionEnd.timeIntervalSince(sessionStart)

            func xOf(_ date: Date) -> CGFloat {
                guard totalDuration > 0 else { return 0 }
                return CGFloat(date.timeIntervalSince(sessionStart) / totalDuration) * size.width
            }

            func yOf(_ bpm: Double) -> CGFloat {
                let range = bounds.max - bounds.min
                guard range > 0 else { return size.height / 2 }
                return CGFloat((bounds.max - bpm) / range) * size.height
            }

            // Zone band
            let zoneTop = yOf(Double(maxZone))
            let zoneBot = yOf(Double(minZone))
            context.fill(
                Path(CGRect(x: 0, y: zoneTop, width: size.width, height: zoneBot - zoneTop)),
                with: .color(.green.opacity(0.12))
            )

            // Zone boundary dashed lines
            for y in [zoneTop, zoneBot] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.green.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            // Zone labels
            context.draw(
                Text("\(maxZone) bpm").font(.caption2).foregroundStyle(Color.green.opacity(0.65)),
                at: CGPoint(x: 4, y: zoneTop - 2), anchor: .bottomLeading
            )
            context.draw(
                Text("\(minZone) bpm").font(.caption2).foregroundStyle(Color.green.opacity(0.65)),
                at: CGPoint(x: 4, y: zoneBot + 2), anchor: .topLeading
            )

            // HR line segments
            guard samples.count >= 2 else {
                // Single sample: draw a dot
                if let s = samples.first {
                    let x = xOf(s.date)
                    let y = yOf(s.bpm)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                        with: .color(segmentColor(bpm: s.bpm))
                    )
                }
                return
            }

            for i in 1..<samples.count {
                let prev = samples[i - 1]
                let curr = samples[i]
                let gap  = curr.date.timeIntervalSince(prev.date)

                var seg = Path()
                seg.move(to: CGPoint(x: xOf(prev.date), y: yOf(prev.bpm)))
                seg.addLine(to: CGPoint(x: xOf(curr.date), y: yOf(curr.bpm)))

                if gap > sparseGap {
                    // Sparse gap: dashed white line
                    context.stroke(seg, with: .color(.white.opacity(0.3)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                } else {
                    // Dense: solid line coloured by zone
                    context.stroke(seg, with: .color(segmentColor(bpm: prev.bpm)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }

            // Terminal dots (first and last sample)
            for s in [samples.first!, samples.last!] {
                let x = xOf(s.date)
                let y = yOf(s.bpm)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                    with: .color(segmentColor(bpm: s.bpm))
                )
            }
        }
    }

    private func segmentColor(bpm: Double) -> Color {
        if bpm > Double(maxZone) { return Color.red.opacity(0.85) }
        if bpm < Double(minZone) { return Color.orange.opacity(0.85) }
        return Color.green.opacity(0.85)
    }
}

// MARK: - Zone distribution bar

private struct ZoneDistributionBar: View {
    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIME IN ZONE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.5)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))

                    HStack(spacing: 0) {
                        if summary.belowFraction > 0 {
                            Rectangle()
                                .fill(Color.orange.opacity(0.8))
                                .frame(width: geo.size.width * CGFloat(summary.belowFraction))
                        }
                        if summary.inZoneFraction > 0 {
                            Rectangle()
                                .fill(Color.green.opacity(0.8))
                                .frame(width: geo.size.width * CGFloat(summary.inZoneFraction))
                        }
                        if summary.aboveFraction > 0 {
                            Rectangle()
                                .fill(Color.red.opacity(0.8))
                                .frame(width: geo.size.width * CGFloat(summary.aboveFraction))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 16)

            HStack {
                if summary.belowFraction > 0 {
                    zoneStat(pct: summary.belowFraction, label: "below", color: .orange)
                }
                Spacer()
                zoneStat(pct: summary.inZoneFraction, label: "in zone", color: .green)
                Spacer()
                if summary.aboveFraction > 0 {
                    zoneStat(pct: summary.aboveFraction, label: "above", color: .red)
                }
            }
        }
    }

    private func zoneStat(pct: Double, label: String, color: Color) -> some View {
        Text("\(Int((pct * 100).rounded()))% \(label)")
            .font(.caption2)
            .foregroundColor(color.opacity(0.9))
    }
}
