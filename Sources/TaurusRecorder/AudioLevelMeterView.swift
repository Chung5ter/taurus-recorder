import TaurusRecorderCore
import SwiftUI

struct AudioLevelMeterView: View {
    let reading: MeterReading
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(statusText, systemImage: reading.isSilent ? "speaker.slash" : "speaker.wave.2.fill")
                    .foregroundStyle(reading.isSilent ? .secondary : .primary)
                Spacer()
                Text(String(format: "Peak %.2f", reading.peak))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .quaternaryLabelColor))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(meterColor)
                        .frame(width: max(4, proxy.size.width * CGFloat(reading.normalizedLevel)))
                }
            }
            .frame(height: 14)
            .accessibilityLabel(statusText)
        }
    }

    private var meterColor: Color {
        if reading.isSilent {
            return .gray
        }
        if reading.normalizedLevel > 0.82 {
            return .orange
        }
        return .green
    }
}
