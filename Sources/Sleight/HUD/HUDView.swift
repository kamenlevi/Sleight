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

            if model.available {
                LevelBar(value: CGFloat(model.value))
                    .frame(height: 8)

                Text(Double(model.value), format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.8))
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
        // No background here: the capsule bezel is a native masked
        // NSVisualEffectView behind this view (see HUDController.makePanel).
    }
}

private struct LevelBar: View {
    let value: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                // Experiment: at exactly 0%, show no fill at all (not even the
                // minimum rounded dot), so 0 reads as truly empty.
                Capsule()
                    .fill(.primary)
                    .frame(width: value <= 0 ? 0 : max(geo.size.height, geo.size.width * value))
            }
        }
        // Animation is driven explicitly by HUDController (withAnimation), so a
        // fresh popup can appear at its value with no travel while a visible
        // one glides. No implicit animation here.
    }
}
