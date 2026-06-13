import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ExerciseViewModel
    @Environment(\.dismiss) private var dismiss

    private let speakOptions: [(label: String, value: Int)] = [
        ("Off", 0), ("30s", 30), ("1 min", 60), ("2 min", 120), ("3 min", 180)
    ]
    private let summaryOptions: [(label: String, value: Int)] = [
        ("Off", 0), ("2 min", 120), ("3 min", 180), ("5 min", 300), ("10 min", 600)
    ]
    private let countdownOptions: [(label: String, value: Int)] = [
        ("Off", 0), ("3s", 3), ("5s", 5)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {

                        // ── Profile ─────────────────────────────────────
                        SettingsSection(title: "Profile") {
                            VStack(spacing: 12) {
                                StepperField(label: "Age",
                                             value: Binding(
                                                get: { viewModel.userAge ?? 30 },
                                                set: { viewModel.userAge = $0 }
                                             ),
                                             range: 10...100,
                                             display: viewModel.userAge != nil ? "\(viewModel.userAge!)" : "--")

                                StepperField(label: "Resting HR",
                                             value: Binding(
                                                get: { viewModel.restingHR ?? 60 },
                                                set: { viewModel.restingHR = $0 }
                                             ),
                                             range: 30...120,
                                             display: viewModel.restingHR != nil ? "\(viewModel.restingHR!) bpm" : "--")

                                Button(action: { viewModel.fetchProfileFromHealthKit() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "heart.fill")
                                            .font(.caption2)
                                        Text("Read from Apple Health")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                        }

                        // ── Heart Rate Zones ────────────────────────────
                        SettingsSection(title: "Heart Rate Zones") {
                            VStack(spacing: 10) {
                                ZoneEditor(zones: $viewModel.heartRateZones)

                                if viewModel.userAge != nil && viewModel.restingHR != nil {
                                    Button(action: {
                                        viewModel.autoCalculateZones()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "wand.and.stars")
                                                .font(.caption2)
                                            Text("Auto-calculate (Karvonen)")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.blue)
                                    }

                                    if viewModel.zonesAutoSet {
                                        Text("Based on age \(viewModel.userAge!), resting HR \(viewModel.restingHR!) — tap zones to adjust")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                } else {
                                    Text("Set age and resting HR above to auto-calculate")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.35))
                                }
                            }
                        }

                        // ── Announcements ───────────────────────────────
                        SettingsSection(title: "Announcements") {
                            VStack(spacing: 14) {
                                SettingsPickerRow(
                                    label: "Speak every",
                                    options: speakOptions,
                                    selected: $viewModel.speakInterval
                                )
                                SettingsPickerRow(
                                    label: "Summary every",
                                    options: summaryOptions,
                                    selected: $viewModel.summaryInterval
                                )
                            }
                        }

                        // ── General ─────────────────────────────────────
                        SettingsSection(title: "General") {
                            SettingsPickerRow(
                                label: "Start countdown",
                                options: countdownOptions,
                                selected: $viewModel.startCountdown
                            )
                        }

                        Spacer().frame(height: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Section container

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)

            VStack(spacing: 12) {
                content
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Zone editor (all 5 zones, highest first)

private struct ZoneEditor: View {
    @Binding var zones: HeartRateZones

    private let colors: [Color] = [.green, .yellow, .orange, .red, .purple]

    private var scaleMin: Int { max(40, zones[0].minBPM - 10) }
    private var scaleMax: Int { min(220, zones[4].maxBPM + 5) }

    var body: some View {
        VStack(spacing: 2) {
            ForEach((0..<5).reversed(), id: \.self) { i in
                ZoneRow(
                    zone: zones[i],
                    color: colors[i],
                    number: i + 1,
                    name: HeartRateZones.names[i],
                    scaleMin: scaleMin,
                    scaleMax: scaleMax,
                    onMinChange: { zones.setMin($0, forZone: i) },
                    onMaxChange: { zones.setMax($0, forZone: i) }
                )
            }

            HStack {
                Text("\(scaleMin)")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Text("\(scaleMax) bpm")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }
}

private struct ZoneRow: View {
    let zone: HRZone
    let color: Color
    let number: Int
    let name: String
    let scaleMin: Int
    let scaleMax: Int
    let onMinChange: (Int) -> Void
    let onMaxChange: (Int) -> Void

    private var barStart: CGFloat {
        let range = CGFloat(scaleMax - scaleMin)
        guard range > 0 else { return 0 }
        return CGFloat(zone.minBPM - scaleMin) / range
    }

    private var barWidth: CGFloat {
        let range = CGFloat(scaleMax - scaleMin)
        guard range > 0 else { return 0 }
        return CGFloat(zone.maxBPM - zone.minBPM) / range
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text("Z\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 22)

                Text(name)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 62, alignment: .leading)

                Spacer()

                Button(action: { onMinChange(zone.minBPM - 1) }) {
                    Image(systemName: "minus").font(.system(size: 9, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .foregroundColor(.white.opacity(0.4))

                Text("\(zone.minBPM)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 28)

                Button(action: { onMinChange(zone.minBPM + 1) }) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .foregroundColor(.white.opacity(0.4))

                Text("-")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))

                Button(action: { onMaxChange(zone.maxBPM - 1) }) {
                    Image(systemName: "minus").font(.system(size: 9, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .foregroundColor(.white.opacity(0.4))

                Text("\(zone.maxBPM)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 28)

                Button(action: { onMaxChange(zone.maxBPM + 1) }) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .foregroundColor(.white.opacity(0.4))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))

                    Capsule()
                        .fill(color.opacity(0.4))
                        .frame(width: max(4, geo.size.width * barWidth))
                        .offset(x: geo.size.width * barStart)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stepper field

private struct StepperField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let display: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            HStack(spacing: 12) {
                Button(action: { value = max(range.lowerBound, value - 1) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .foregroundColor(.white.opacity(0.6))

                Text(display)
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(.white)
                    .frame(minWidth: 50)

                Button(action: { value = min(range.upperBound, value + 1) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Picker row

private struct SettingsPickerRow: View {
    let label: String
    let options: [(label: String, value: Int)]
    @Binding var selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))

            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    Button(action: { selected = option.value }) {
                        Text(option.label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(selected == option.value ? Color.blue : Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}
