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
                    .frame(height: 200)
                    .padding(.horizontal, 16)

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
    private let leftMargin: CGFloat = 36
    private let bottomMargin: CGFloat = 22

    private var yBounds: (min: Double, max: Double) {
        let bpms = samples.map(\.bpm)
        let dataMin = bpms.min() ?? Double(minZone)
        let dataMax = bpms.max() ?? Double(maxZone)
        let lo = min(dataMin, Double(minZone))
        let hi = max(dataMax, Double(maxZone))
        let padding = max(10, (hi - lo) * 0.15)
        return (max(40, lo - padding), min(220, hi + padding))
    }

    private var yTicks: [Int] {
        let bounds = yBounds
        let range = bounds.max - bounds.min
        let step: Int
        if range <= 30 { step = 5 }
        else if range <= 60 { step = 10 }
        else { step = 20 }

        let first = Int((bounds.min / Double(step)).rounded(.up)) * step
        let last  = Int((bounds.max / Double(step)).rounded(.down)) * step
        return stride(from: first, through: last, by: step).map { $0 }
    }

    private func xTimeTicks(totalDuration: TimeInterval) -> [(label: String, fraction: Double)] {
        guard totalDuration > 0 else { return [] }
        let step: TimeInterval
        if totalDuration <= 120 { step = 30 }
        else if totalDuration <= 300 { step = 60 }
        else if totalDuration <= 900 { step = 120 }
        else { step = 300 }

        var ticks: [(String, Double)] = []
        var t: TimeInterval = 0
        while t <= totalDuration {
            let mins = Int(t) / 60
            let secs = Int(t) % 60
            let label = secs == 0 ? "\(mins)m" : "\(mins):\(String(format: "%02d", secs))"
            ticks.append((label, t / totalDuration))
            t += step
        }
        return ticks
    }

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let bounds = yBounds
            let totalDuration = sessionEnd.timeIntervalSince(sessionStart)
            let plotW = size.width - leftMargin
            let plotH = size.height - bottomMargin

            func xOf(_ date: Date) -> CGFloat {
                guard totalDuration > 0 else { return leftMargin }
                return leftMargin + CGFloat(date.timeIntervalSince(sessionStart) / totalDuration) * plotW
            }

            func yOf(_ bpm: Double) -> CGFloat {
                let range = bounds.max - bounds.min
                guard range > 0 else { return plotH / 2 }
                return CGFloat((bounds.max - bpm) / range) * plotH
            }

            // Y axis line
            var yAxis = Path()
            yAxis.move(to: CGPoint(x: leftMargin, y: 0))
            yAxis.addLine(to: CGPoint(x: leftMargin, y: plotH))
            context.stroke(yAxis, with: .color(.white.opacity(0.2)),
                           style: StrokeStyle(lineWidth: 1))

            // X axis line
            var xAxis = Path()
            xAxis.move(to: CGPoint(x: leftMargin, y: plotH))
            xAxis.addLine(to: CGPoint(x: size.width, y: plotH))
            context.stroke(xAxis, with: .color(.white.opacity(0.2)),
                           style: StrokeStyle(lineWidth: 1))

            // Y axis ticks and gridlines
            for bpm in yTicks {
                let y = yOf(Double(bpm))
                guard y >= 0, y <= plotH else { continue }

                // Gridline
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: leftMargin, y: y))
                gridLine.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(gridLine, with: .color(.white.opacity(0.06)),
                               style: StrokeStyle(lineWidth: 0.5))

                // Label
                context.draw(
                    Text("\(bpm)").font(.system(size: 9, weight: .light)).foregroundStyle(Color.white.opacity(0.4)),
                    at: CGPoint(x: leftMargin - 4, y: y), anchor: .trailing
                )
            }

            // X axis ticks
            for tick in xTimeTicks(totalDuration: totalDuration) {
                let x = leftMargin + CGFloat(tick.fraction) * plotW
                context.draw(
                    Text(tick.label).font(.system(size: 9, weight: .light)).foregroundStyle(Color.white.opacity(0.4)),
                    at: CGPoint(x: x, y: plotH + 4), anchor: .top
                )

                // Small tick mark
                var tickMark = Path()
                tickMark.move(to: CGPoint(x: x, y: plotH))
                tickMark.addLine(to: CGPoint(x: x, y: plotH + 3))
                context.stroke(tickMark, with: .color(.white.opacity(0.2)),
                               style: StrokeStyle(lineWidth: 0.5))
            }

            // Zone band
            let zoneTop = yOf(Double(maxZone))
            let zoneBot = yOf(Double(minZone))
            context.fill(
                Path(CGRect(x: leftMargin, y: zoneTop, width: plotW, height: zoneBot - zoneTop)),
                with: .color(.green.opacity(0.1))
            )

            // Zone boundary dashed lines
            for y in [zoneTop, zoneBot] {
                guard y >= 0, y <= plotH else { continue }
                var line = Path()
                line.move(to: CGPoint(x: leftMargin, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.green.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            // Zone labels on right edge
            if zoneTop >= 0, zoneTop <= plotH {
                context.draw(
                    Text("\(maxZone)").font(.system(size: 9, weight: .medium)).foregroundStyle(Color.green.opacity(0.6)),
                    at: CGPoint(x: size.width - 2, y: zoneTop - 1), anchor: .bottomTrailing
                )
            }
            if zoneBot >= 0, zoneBot <= plotH {
                context.draw(
                    Text("\(minZone)").font(.system(size: 9, weight: .medium)).foregroundStyle(Color.green.opacity(0.6)),
                    at: CGPoint(x: size.width - 2, y: zoneBot + 1), anchor: .topTrailing
                )
            }

            // HR line segments
            guard samples.count >= 2 else {
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
                    context.stroke(seg, with: .color(.white.opacity(0.3)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                } else {
                    context.stroke(seg, with: .color(segmentColor(bpm: prev.bpm)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }

            // Terminal dots
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
