import SwiftUI

/// A reusable metric display: label above a large number with unit.
struct MetricRow: View {
    let label: String
    let value: Int?
    let unit: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.5)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { "\($0)" } ?? "--")
                    .font(.system(size: 64, weight: .thin, design: .rounded))
                    .foregroundColor(valueColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: value)

                Text(unit)
                    .font(.title3)
                    .fontWeight(.light)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}
