import SwiftUI

@MainActor
@Observable
final class VisualizerModel {
    var touches: [Touch] = []
}

/// Live view of raw trackpad contacts — instant confidence that every touch
/// is registering, and a handy way to practice the gestures.
struct VisualizerView: View {
    @State private var model = VisualizerModel()

    private let touchColors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .yellow, .red]

    var body: some View {
        VStack(spacing: 16) {
            Text("Touch the trackpad — every contact shows up here in real time.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.quaternary.opacity(0.5))
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.tertiary, lineWidth: 1)

                    ForEach(model.touches) { touch in
                        let diameter = CGFloat(28 + touch.size * 26)
                        Circle()
                            .fill(touchColors[abs(Int(touch.id)) % touchColors.count].gradient)
                            .frame(width: diameter, height: diameter)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                            .position(
                                x: CGFloat(touch.x) * geo.size.width,
                                // Trackpad origin is bottom-left; flip for the view.
                                y: (1 - CGFloat(touch.y)) * geo.size.height
                            )
                            .shadow(radius: 4)
                    }
                }
            }
            .aspectRatio(1.6, contentMode: .fit)

            HStack {
                Circle()
                    .fill(TouchStream.shared.deviceCount > 0 ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(TouchStream.shared.deviceCount > 0
                     ? "\(model.touches.count) active \(model.touches.count == 1 ? "touch" : "touches")"
                     : "No multitouch device detected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openMenagerie()
                } label: {
                    Label("Menagerie — this, as a game", systemImage: "fish")
                }
                .help("Cardboard creatures that live under your fingers — koi, fireflies, puppets. Opens Menagerie (or its download page).")
            }
        }
        .padding(24)
        .onAppear {
            GestureCoordinator.shared.visualizerSink = { frame in
                let touches = frame.touches
                Task { @MainActor in
                    model.touches = touches
                }
            }
        }
        .onDisappear {
            GestureCoordinator.shared.visualizerSink = nil
        }
    }

    /// Menagerie is this visualizer grown into a toy — a separate app by the
    /// same author. Opening it via its URL scheme both launches it and brings
    /// the games window forward if it's already running (and tells it it was
    /// opened from Sleight); older builds without the scheme are launched
    /// directly, and with no install at all we point at the download page.
    private func openMenagerie() {
        let fromSleight = URL(string: "menagerie://from-sleight")!
        if NSWorkspace.shared.urlForApplication(toOpen: fromSleight) != nil {
            NSWorkspace.shared.open(fromSleight)
        } else if let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.kamenlevi.menagerie") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--from-sleight"]
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        } else {
            NSWorkspace.shared.open(
                URL(string: "https://github.com/kamenlevi/Menagerie/releases/latest")!)
        }
    }
}
