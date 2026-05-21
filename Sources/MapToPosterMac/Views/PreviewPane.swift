import SwiftUI

struct PreviewPane: View {
    let posterURL: URL?
    let request: PosterRequest
    let selectedTheme: PosterTheme?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Poster Preview", systemImage: "photo")
                .font(.headline)
                .foregroundStyle(AppDesign.inkBlue)

            posterPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .appPanel()
    }

    @ViewBuilder
    private var posterPreview: some View {
        if let posterURL, posterURL.pathExtension.lowercased() == "png", let image = NSImage(contentsOf: posterURL) {
            VStack(spacing: 12) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
                    .shadow(radius: 18, y: 10)
                    .accessibilityLabel("Generated poster preview for \(request.posterCity)")

                Text(posterURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    selectedTheme?.backgroundColor.opacity(0.95) ?? .white.opacity(0.9),
                                    AppDesign.mistBlue.opacity(0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    MapSketch(theme: selectedTheme)

                    VStack {
                        Spacer()

                        VStack(spacing: 8) {
                            Text(request.posterCity.isEmpty ? "Poster Preview" : request.posterCity)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(selectedTheme?.textColor ?? AppDesign.inkBlue)
                                .lineLimit(1)

                            Text("Generate a PNG to preview it here. SVG and PDF outputs are still saved to posters/.")
                                .font(.callout)
                                .foregroundStyle(AppDesign.inkBlue.opacity(0.72))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 290)
                        }
                        .padding(24)
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .frame(maxWidth: 420)
                .overlay {
                    RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.82), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Preview placeholder for \(request.locationQuery)")
            }
        }
    }
}

private struct MapSketch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let theme: PosterTheme?

    var body: some View {
        Group {
            if reduceMotion {
                sketch(t: 0)
            } else {
                TimelineView(.periodic(from: .now, by: 1 / 24)) { timeline in
                    sketch(t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func sketch(t: TimeInterval) -> some View {
        Canvas { context, size in
            let color = theme?.roadColor ?? AppDesign.clearBlue

            for index in 0..<18 {
                var path = Path()
                let baseY = size.height * (0.12 + Double(index) * 0.043)
                let drift = sin(t * 0.55 + Double(index)) * 6
                path.move(to: CGPoint(x: size.width * 0.10, y: baseY + drift))
                path.addCurve(
                    to: CGPoint(x: size.width * 0.90, y: baseY - drift),
                    control1: CGPoint(x: size.width * 0.34, y: baseY - 22 + drift),
                    control2: CGPoint(x: size.width * 0.62, y: baseY + 24 - drift)
                )
                context.stroke(path, with: .color(color.opacity(0.74)), lineWidth: index.isMultiple(of: 5) ? 2.0 : 0.9)
            }

            for index in 0..<10 {
                var path = Path()
                let baseX = size.width * (0.16 + Double(index) * 0.075)
                path.move(to: CGPoint(x: baseX, y: size.height * 0.10))
                path.addCurve(
                    to: CGPoint(x: baseX + CGFloat(sin(t + Double(index)) * 12), y: size.height * 0.76),
                    control1: CGPoint(x: baseX + 18, y: size.height * 0.34),
                    control2: CGPoint(x: baseX - 18, y: size.height * 0.52)
                )
                context.stroke(path, with: .color(color.opacity(0.44)), lineWidth: index.isMultiple(of: 3) ? 1.6 : 0.8)
            }
        }
    }
}
