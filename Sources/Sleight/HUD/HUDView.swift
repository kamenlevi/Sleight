import SwiftUI

struct HUDView: View {
    var model: HUDModel

    private var symbolName: String {
        switch model.control {
        case .volume:
            if model.muted || model.value == 0 { return "speaker.slash.fill" }
            if model.value < 0.34 { return "speaker.wave.1.fill" }
            if model.value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .displayBrightness:
            return model.value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBrightness:
            return "keyboard.fill"
        case .none:
            return "circle.slash"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))

            if model.available {
                LevelBar(value: CGFloat(model.value))
                    .frame(height: 8)

                Text(Double(model.value), format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            } else {
                Text("Not available")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 22)
        .frame(width: 280, height: 58)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .padding(3)
    }
}

private struct LevelBar: View {
    let value: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(.primary)
                    .frame(width: max(geo.size.height, geo.size.width * value))
            }
        }
        .animation(.linear(duration: 0.05), value: value)
    }
}
