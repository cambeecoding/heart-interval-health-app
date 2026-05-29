import SwiftUI

struct ExerciseView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Elapsed time + progress ring ─────────────────────────
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                        .frame(width: 110, height: 110)

                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.secondsInWindow % viewModel.announcementInterval) / CGFloat(viewModel.announcementInterval))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: viewModel.secondsInWindow)

                    VStack(spacing: 2) {
                        Text(formattedTime(viewModel.elapsedSeconds))
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                            .foregroundColor(.white)

                        Text("next in \(max(0, viewModel.announcementInterval - (viewModel.secondsInWindow % viewModel.announcementInterval)))s")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.top, 56)

                Spacer()

                // ── Heart rate metrics ────────────────────────────────────
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
                } else {
                    VStack(spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.hrSource == .ble ? "antenna.radiowaves.left.and.right" : "heart.fill")
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
                    }
                    .padding(.bottom, 8)

                    MetricRow(label: "Current", value: viewModel.currentHR, unit: "bpm", valueColor: .white)
                        .padding(.bottom, 28)

                    MetricRow(label: "Last min", value: viewModel.lastMinuteAvgHR, unit: "bpm", valueColor: .yellow)
                }

                Spacer()

                // ── Controls ──────────────────────────────────────────────
                HStack(spacing: 16) {
                    // Interval toggle
                    Button(action: { viewModel.pauseExercise() }) {
                        Text("PAUSE")
                            .font(.headline)
                            .frame(width: 130, height: 44)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
