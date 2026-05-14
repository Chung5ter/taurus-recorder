import SwiftUI

extension View {
    @ViewBuilder
    func recorderGlassSurface(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func recorderPrimaryButtonStyle(isDestructive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(isDestructive ? Color.red : nil)
        } else {
            buttonStyle(.borderedProminent)
                .tint(isDestructive ? Color.red : nil)
        }
    }

    @ViewBuilder
    func recorderSecondaryButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
