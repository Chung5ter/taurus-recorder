import TaurusRecorderCore
import SwiftUI

struct WaveformView: View {
    let points: [WaveformPoint]
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Waveform", systemImage: "waveform")
                Spacer()
                Text(isActive ? "Live" : "Ready")
                    .foregroundStyle(isActive ? .green : .secondary)
            }
            .font(.callout)

            Canvas { context, size in
                drawCenterLine(context: context, size: size)

                guard !points.isEmpty else {
                    drawEmptyState(context: context, size: size)
                    return
                }

                let visiblePoints = points.suffix(max(Int(size.width), 1))
                let columnWidth = max(size.width / CGFloat(visiblePoints.count), 1)
                let centerY = size.height / 2

                for (index, point) in visiblePoints.enumerated() {
                    let x = CGFloat(index) * columnWidth
                    let minY = centerY - CGFloat(point.maximum) * centerY
                    let maxY = centerY - CGFloat(point.minimum) * centerY
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: minY))
                    path.addLine(to: CGPoint(x: x, y: maxY))
                    context.stroke(path, with: .color(waveformColor), lineWidth: max(columnWidth, 1))
                }
            }
            .frame(height: 150)
            .padding(10)
            .recorderGlassSurface(cornerRadius: 16, interactive: true)
        }
    }

    private func drawCenterLine(context: GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(path, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)
    }

    private func drawEmptyState(context: GraphicsContext, size: CGSize) {
        let lineCount = 8
        for index in 0..<lineCount {
            let x = size.width * CGFloat(index + 1) / CGFloat(lineCount + 1)
            var path = Path()
            path.move(to: CGPoint(x: x, y: size.height * 0.34))
            path.addLine(to: CGPoint(x: x, y: size.height * 0.66))
            context.stroke(path, with: .color(Color(nsColor: .separatorColor).opacity(0.45)), lineWidth: 1)
        }
    }

    private var waveformColor: Color {
        isActive ? .accentColor : Color(nsColor: .secondaryLabelColor)
    }
}
