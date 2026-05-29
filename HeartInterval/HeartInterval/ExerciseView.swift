import SwiftUI

struct ExerciseView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ScrollView ensures content never gets clipped on any screen size
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {

                    // ── Elapsed time + progress ring ──────────────────────
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 5)
                            .frame(width: 84, height: 84)

                        Circle()
                            .trim(from: 0, to: CGFloat(viewModel.secondsInWindow % viewModel.announcementInterval) / CGFloat(viewModel.announcementInterval))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 84, height: 84)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: viewModel.secondsInWindow)

                        VStack(spacing: 1) {
                            Text(formattedTime(viewModel.elapsedSeconds))
                                .font(.system(size: 22, weight: .light, design: .monospaced))
                                .foregroundColor(.white)
                            Text("next \(max(0, viewModel.announcementInterval - (viewModel.secondsInWindow % viewModel.announcementInterval)))s")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.horizontal, 40)

                    // ── Heart rate metrics ────────────────────────────────
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
                        let hrColor: Color = hr > viewModel.maxHR ? .red
                                           : hr < viewModel.minHR ? .orange
                                           : .green

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

                        // Current BPM — large, zone-coloured
                        VStack(spacing: 4) {
                            Text("\(hr)")
                                .font(.system(size: 56, weight: .thin, design: .rounded))
                                .foregroundColor(hrColor)
                                .animation(.easeInOut(duration: 0.3), value: hr)
                                .contentTransition(.numericText())
                            Text("bpm")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.3))

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
                                // Reserve height so layout doesn't jump
                                Color.clear.frame(height: 16)
                            }
                        }

                        // Zone scale
                        HRZoneBar(minHR: viewModel.minHR,
                                  maxHR: viewModel.maxHR,
                                  currentHR: hr)
                            .padding(.horizontal, 32)

                        // Session average
                        MetricRow(label: "Session avg",
                                  value: viewModel.totalAvgHR,
                                  unit: "bpm",
                                  valueColor: .yellow)
                    }
                }
                .padding(.top, 16)
                // Bottom padding ensures content clears the pinned button
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity)
            }
        }
        // PAUSE button pinned above safe area — always visible on every device
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

// MARK: - HR Zone Bar

private struct HRZoneBar: View {
    let minHR: Int
    let maxHR: Int
    let currentHR: Int

    private let trackH:  CGFloat = 4
    private let labelW:  CGFloat = 36   // inset on each side for min/max labels
    private let pointerH: CGFloat = 10  // height of the downward tick below the track

    private func fraction(trackW: CGFloat) -> CGFloat {
        let span = maxHR - minHR
        guard span > 0 else { return 0.5 }
        return min(max(CGFloat(currentHR - minHR) / CGFloat(span), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let trackW = totalW - labelW * 2
            let f      = fraction(trackW: trackW)
            let tickX  = labelW + f * trackW   // x-centre of the tick

            ZStack(alignment: .leading) {

                // ── Background track ──────────────────────────────────────
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: trackW, height: trackH)
                    .offset(x: labelW, y: 0)

                // ── Tick / pointer ────────────────────────────────────────
                // A thin vertical line dropping below the track
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2, height: trackH + pointerH)
                    .offset(x: tickX - 1, y: 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentHR)

                // ── Min label — flush left ────────────────────────────────
                Text("\(minHR)")
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: labelW, alignment: .leading)
                    .offset(x: 0, y: -1)

                // ── Max label — flush right ───────────────────────────────
                Text("\(maxHR)")
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: labelW, alignment: .trailing)
                    .offset(x: totalW - labelW, y: -1)
            }
        }
        .frame(height: trackH + pointerH + 4)
    }
}
