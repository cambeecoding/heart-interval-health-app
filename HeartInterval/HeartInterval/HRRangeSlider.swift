import SwiftUI

struct HRRangeSlider: View {
    let range: ClosedRange<Int>
    @Binding var low: Int
    @Binding var high: Int

    @State private var trackWidth: CGFloat = 0
    @State private var lowStart: Int = 0
    @State private var highStart: Int = 0

    private let labelW: CGFloat  = 52
    private let handleD: CGFloat = 28
    private let step: Int        = 5
    private var pad: CGFloat     { labelW / 2 }
    private var span: CGFloat    { CGFloat(range.upperBound - range.lowerBound) }

    private func fraction(for value: Int) -> CGFloat {
        CGFloat(value - range.lowerBound) / span
    }

    private func bpm(from fraction: CGFloat) -> Int {
        let clamped = min(max(fraction, 0), 1)
        let raw = range.lowerBound + Int((clamped * span).rounded())
        return Int((Double(raw) / Double(step)).rounded()) * step
    }

    private func xPos(for value: Int, trackW: CGFloat) -> CGFloat {
        pad + fraction(for: value) * trackW
    }

    private func bpmAt(x: CGFloat, trackW: CGFloat) -> Int {
        bpm(from: (x - pad) / trackW)
    }

    var body: some View {
        GeometryReader { geo in
            let totalW: CGFloat = geo.size.width
            let trackW: CGFloat = totalW - pad * 2

            let lowX  = xPos(for: low,  trackW: trackW)
            let highX = xPos(for: high, trackW: trackW)

            ZStack(alignment: .leading) {

                // ── Max label: above the high handle ──────────────────────
                Text("\(high)")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: labelW, alignment: .center)
                    .offset(x: highX - labelW / 2, y: 0)

                // ── Background track ──────────────────────────────────────
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: trackW, height: 6)
                    .offset(x: pad, y: 36)

                // ── Active range fill ─────────────────────────────────────
                Capsule()
                    .fill(Color.blue)
                    .frame(width: max(0, highX - lowX), height: 6)
                    .offset(x: lowX, y: 36)

                // ── Low handle ────────────────────────────────────────────
                Circle()
                    .fill(Color.white)
                    .frame(width: handleD, height: handleD)
                    .shadow(color: .black.opacity(0.25), radius: 4)
                    .offset(x: lowX - handleD / 2, y: 36 - handleD / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if abs(v.translation.width) < 0.5 && abs(v.translation.height) < 0.5 {
                                    lowStart = low
                                }
                                let startX = xPos(for: lowStart, trackW: trackW)
                                let proposed = bpmAt(x: startX + v.translation.width, trackW: trackW)
                                low = min(max(proposed, range.lowerBound), high - step)
                            }
                    )

                // ── High handle ───────────────────────────────────────────
                Circle()
                    .fill(Color.white)
                    .frame(width: handleD, height: handleD)
                    .shadow(color: .black.opacity(0.25), radius: 4)
                    .offset(x: highX - handleD / 2, y: 36 - handleD / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if abs(v.translation.width) < 0.5 && abs(v.translation.height) < 0.5 {
                                    highStart = high
                                }
                                let startX = xPos(for: highStart, trackW: trackW)
                                let proposed = bpmAt(x: startX + v.translation.width, trackW: trackW)
                                high = min(max(proposed, low + step), range.upperBound)
                            }
                    )

                // ── Min label: below the low handle ───────────────────────
                Text("\(low)")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: labelW, alignment: .center)
                    .offset(x: lowX - labelW / 2, y: 72)

                // ── Range endpoint hints ───────────────────────────────────
                Text("\(range.lowerBound)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: labelW, alignment: .center)
                    .offset(x: 0, y: 90)

                Text("bpm")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: totalW, alignment: .center)
                    .offset(x: 0, y: 90)

                Text("\(range.upperBound)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: labelW, alignment: .center)
                    .offset(x: totalW - labelW, y: 90)
            }
            .onAppear { trackWidth = totalW }
            .onChange(of: totalW) { _, newW in trackWidth = newW }
        }
        .frame(height: 108)
        .padding(.horizontal, 16)
    }
}
