import SwiftUI

struct ExerciseView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {

                    // ── Elapsed time + progress ring ──────────────────────
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 5)
                            .frame(width: 84, height: 84)

                        Circle()
                            .trim(from: 0, to: CGFloat(viewModel.elapsedSeconds % viewModel.announcementInterval) / CGFloat(viewModel.announcementInterval))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 84, height: 84)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: viewModel.elapsedSeconds)

                        VStack(spacing: 1) {
                            Text(formattedTime(viewModel.elapsedSeconds))
                                .font(.system(size: 22, weight: .light, design: .monospaced))
                                .foregroundColor(.white)
                            Text("next \(max(0, viewModel.announcementInterval - (viewModel.elapsedSeconds % viewModel.announcementInterval)))s")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.horizontal, 40)

                    // ── Heart rate ────────────────────────────────────────
                    if viewModel.currentHR == nil {
                        VStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                            Text("Waiting for heart rate…")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.45))
                            Text("Garmin: enable Broadcast in Activity\nApple Watch: start a workout")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.25))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .padding(.vertical, 12)
                    } else {
                        let hr = viewModel.currentHR ?? 0

                        // Source badge
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.hrSource == .ble
                                  ? "antenna.radiowaves.left.and.right" : "heart.fill")
                                .font(.caption2)
                            Text(viewModel.hrSource == .ble ? "Bluetooth HR" : "Apple Health")
                                .font(.caption2)
                            if let age = viewModel.secondsSinceLastHR, age > 15 {
                                Text("· \(age)s ago")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .foregroundColor(.white.opacity(0.35))

                        if viewModel.hrSource == .ble || viewModel.bleStatus.contains("disconnected") {
                            Text(viewModel.bleStatus)
                                .font(.caption2)
                                .foregroundColor(viewModel.bleStatus == "HR monitor connected"
                                    ? .green.opacity(0.7) : .orange.opacity(0.7))
                        }

                        // Speedometer gauge
                        HRSpeedometer(
                            currentHR: hr,
                            avgHR: viewModel.totalAvgHR,
                            minZone: viewModel.minHR,
                            maxZone: viewModel.maxHR
                        )
                        .frame(width: 260, height: 170)
                        .padding(.top, 4)

                        // Intensity hint
                        if hr < viewModel.minHR {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.caption2.weight(.semibold))
                                Text("up the intensity")
                                    .font(.caption2)
                            }
                            .foregroundColor(.orange.opacity(0.85))
                        } else if hr > viewModel.maxHR {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.caption2.weight(.semibold))
                                Text("decrease intensity")
                                    .font(.caption2)
                            }
                            .foregroundColor(.red.opacity(0.85))
                        } else {
                            Color.clear.frame(height: 16)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.08))
                Button(action: { viewModel.pauseExercise() }) {
                    Text("PAUSE")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                }
                .background(Color.black)
            }
        }
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - HR Speedometer

private struct HRSpeedometer: View {
    let currentHR: Int
    let avgHR: Int?
    let minZone: Int
    let maxZone: Int

    private let startAngle: Double = 225
    private let endAngle: Double = -45
    private var sweepAngle: Double { startAngle - endAngle }

    private var scaleMin: Int {
        max(40, min(minZone - 30, currentHR - 10))
    }

    private var scaleMax: Int {
        min(220, max(maxZone + 30, currentHR + 10))
    }

    private func angle(for bpm: Int) -> Double {
        let range = Double(scaleMax - scaleMin)
        guard range > 0 else { return startAngle }
        let fraction = Double(bpm - scaleMin) / range
        return startAngle - fraction * sweepAngle
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.75)
            let radius = min(size.width, size.height * 1.3) / 2 - 10

            let minZoneAngle = angle(for: minZone)
            let maxZoneAngle = angle(for: maxZone)
            let needleAngle  = angle(for: currentHR)

            // Track: below zone (orange)
            drawArc(context: context, center: center, radius: radius,
                    from: startAngle, to: minZoneAngle,
                    color: .orange.opacity(0.25), lineWidth: 12)

            // Track: in zone (green)
            drawArc(context: context, center: center, radius: radius,
                    from: minZoneAngle, to: maxZoneAngle,
                    color: .green.opacity(0.3), lineWidth: 12)

            // Track: above zone (red)
            drawArc(context: context, center: center, radius: radius,
                    from: maxZoneAngle, to: endAngle,
                    color: .red.opacity(0.25), lineWidth: 12)

            // Zone boundary ticks
            for bpm in [minZone, maxZone] {
                let a = angle(for: bpm) * .pi / 180
                let inner = radius - 10
                let outer = radius + 10
                var tick = Path()
                tick.move(to: CGPoint(
                    x: center.x + cos(a) * inner,
                    y: center.y - sin(a) * inner
                ))
                tick.addLine(to: CGPoint(
                    x: center.x + cos(a) * outer,
                    y: center.y - sin(a) * outer
                ))
                context.stroke(tick, with: .color(.white.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1.5))
            }

            // Zone boundary labels
            let minA = minZoneAngle * .pi / 180
            let maxA = maxZoneAngle * .pi / 180
            let labelR = radius + 18

            context.draw(
                Text("\(minZone)").font(.system(size: 10, weight: .light)).foregroundStyle(Color.white.opacity(0.5)),
                at: CGPoint(x: center.x + cos(minA) * labelR, y: center.y - sin(minA) * labelR)
            )
            context.draw(
                Text("\(maxZone)").font(.system(size: 10, weight: .light)).foregroundStyle(Color.white.opacity(0.5)),
                at: CGPoint(x: center.x + cos(maxA) * labelR, y: center.y - sin(maxA) * labelR)
            )

            // Scale end labels
            let scaleMinA = angle(for: scaleMin) * .pi / 180
            let scaleMaxA = angle(for: scaleMax) * .pi / 180

            context.draw(
                Text("\(scaleMin)").font(.system(size: 9, weight: .light)).foregroundStyle(Color.white.opacity(0.3)),
                at: CGPoint(x: center.x + cos(scaleMinA) * (radius + 16),
                            y: center.y - sin(scaleMinA) * (radius + 16))
            )
            context.draw(
                Text("\(scaleMax)").font(.system(size: 9, weight: .light)).foregroundStyle(Color.white.opacity(0.3)),
                at: CGPoint(x: center.x + cos(scaleMaxA) * (radius + 16),
                            y: center.y - sin(scaleMaxA) * (radius + 16))
            )

            // Needle
            let nA = needleAngle * .pi / 180
            let needleColor: Color = currentHR > maxZone ? .red
                                   : currentHR < minZone ? .orange
                                   : .green

            var needle = Path()
            needle.move(to: CGPoint(
                x: center.x + cos(nA) * (radius - 20),
                y: center.y - sin(nA) * (radius - 20)
            ))
            needle.addLine(to: CGPoint(
                x: center.x + cos(nA) * (radius + 4),
                y: center.y - sin(nA) * (radius + 4)
            ))
            context.stroke(needle, with: .color(needleColor),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // Needle tip dot
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x + cos(nA) * (radius + 4) - 4,
                    y: center.y - sin(nA) * (radius + 4) - 4,
                    width: 8, height: 8
                )),
                with: .color(needleColor)
            )
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentHR)
        .overlay {
            // Centre text overlay
            VStack(spacing: 2) {
                let hrColor: Color = currentHR > maxZone ? .red
                                   : currentHR < minZone ? .orange
                                   : .green

                Text("\(currentHR)")
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundColor(hrColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: currentHR)

                Text("bpm")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))

                if let avg = avgHR {
                    Text("avg \(avg)")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.yellow.opacity(0.7))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: avg)
                }
            }
            .offset(y: 16)
        }
    }

    private func drawArc(context: GraphicsContext, center: CGPoint, radius: CGFloat,
                         from: Double, to: Double, color: Color, lineWidth: CGFloat) {
        var arc = Path()
        arc.addArc(center: center, radius: radius,
                   startAngle: .degrees(-from), endAngle: .degrees(-to),
                   clockwise: false)
        context.stroke(arc, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
