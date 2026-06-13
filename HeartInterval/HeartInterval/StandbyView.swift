import SwiftUI

struct StandbyView: View {
    @ObservedObject var viewModel: ExerciseViewModel
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 40)

                    // ── Mode toggle ──────────────────────────────────────
                    modeToggle
                        .padding(.horizontal, 40)

                    Spacer().frame(height: 12)

                    HStack {
                        Spacer()
                        Text("BeatZone")
                            .font(.title)
                            .fontWeight(.light)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                    }
                    .overlay(alignment: .trailing) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 36, height: 36)
                        }
                        .padding(.trailing, 16)
                    }

                    let ble   = viewModel.bleSourceStatus
                    let watch = viewModel.watchSourceStatus

                    VStack(spacing: 4) {
                        if !ble.message.isEmpty {
                            StatusRow(message: ble.message, isReady: ble.isReady)
                        }
                        if !watch.message.isEmpty {
                            StatusRow(message: watch.message, isReady: watch.isReady)
                        }
                        if viewModel.shouldShowSourceInstruction {
                            Text("Start a workout on your Apple Watch or Garmin,\nor put your HR monitor in broadcast mode")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.35))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 6)

                    Spacer().frame(height: 24)

                    // ── Mode-specific config ─────────────────────────────
                    if viewModel.trainingMode == .zone {
                        ZonePicker(
                            zones: viewModel.heartRateZones,
                            selected: $viewModel.selectedZone
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    } else {
                        IntervalStandbySection(viewModel: viewModel)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // ── Workout type (per-exercise) ─────────────────────
                    WorkoutTypeRow(selected: $viewModel.selectedActivityType)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Start button ─────────────────────────────────────
                    Button(action: { viewModel.startExercise() }) {
                        Text("START")
                            .font(.headline)
                            .frame(width: 160, height: 52)
                            .background(viewModel.trainingMode == .zone ? Color.blue : Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(TrainingMode.allCases, id: \.rawValue) { mode in
                Button(action: { viewModel.trainingMode = mode }) {
                    Text(mode == .zone ? "Zone" : "Intervals")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(viewModel.trainingMode == mode
                            ? (mode == .zone ? Color.blue : Color.orange)
                            : Color.clear)
                        .foregroundColor(viewModel.trainingMode == mode
                            ? .white : .white.opacity(0.5))
                }
            }
        }
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Status row

private struct StatusRow: View {
    let message: String
    let isReady: Bool
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(isReady ? .green.opacity(0.8) : .orange.opacity(0.7))
    }
}

// MARK: - Zone picker (Z1-Z4 only)

private struct ZonePicker: View {
    let zones: HeartRateZones
    @Binding var selected: Int

    private let selectableCount = 4
    private let colors: [Color] = [.green, .yellow, .orange, .red]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<selectableCount, id: \.self) { i in
                    Button(action: { selected = i }) {
                        VStack(spacing: 2) {
                            Text(HeartRateZones.names[i])
                                .font(.system(size: 10, weight: .medium))
                            Text("\(zones[i].minBPM)-\(zones[i].maxBPM)")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selected == i ? colors[i].opacity(0.25) : Color.white.opacity(0.06))
                        .foregroundColor(selected == i ? colors[i] : .white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selected == i ? colors[i].opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Workout type picker

private struct WorkoutTypeRow: View {
    @Binding var selected: WorkoutActivityType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workout type")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))

            HStack(spacing: 6) {
                ForEach(WorkoutActivityType.allCases, id: \.rawValue) { type in
                    Button(action: { selected = type }) {
                        Text(type.label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(selected == type ? Color.blue : Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

