import PDFKit
import SwiftUI
import WebKit

struct PreviewPane: View {
    let posterURL: URL?
    let request: PosterRequest
    let selectedTheme: PosterTheme?
    let openPoster: () -> Void
    let revealPoster: () -> Void
    let exportPoster: () -> Void
    let openLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Poster Preview", systemImage: "photo")
                    .font(AppDesign.panelTitleFont)
                    .foregroundStyle(AppDesign.inkBlue)

                Spacer()

                if posterURL != nil {
                    Button {
                        openPoster()
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                    .buttonLift()
                    .help("Open the generated poster in the default app.")

                    Button {
                        revealPoster()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                    .buttonLift()
                    .help("Reveal the generated poster in Finder.")

                    Button {
                        exportPoster()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                    .buttonLift()
                    .help("Save a copy of the generated poster somewhere else.")
                }

                Button {
                    openLibrary()
                } label: {
                    Label("Library", systemImage: "rectangle.stack")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                .buttonLift()
                .help("Open the local generated poster library.")
            }

            posterPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .appPanel()
    }

    @ViewBuilder
    private var posterPreview: some View {
        if let posterURL {
            VStack(spacing: 12) {
                PosterRenderedPreview(url: posterURL, request: request)

                Text(posterURL.lastPathComponent)
                    .font(AppDesign.metadataFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
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
                                .font(.title2)
                                .foregroundStyle(selectedTheme?.textColor ?? AppDesign.inkBlue)
                                .lineLimit(1)

                            Text("PNG previews appear here. SVG and PDF outputs are saved to posters/.")
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

private struct PosterRenderedPreview: View {
    let url: URL
    let request: PosterRequest

    private var aspectRatio: CGFloat {
        let dimensions = request.effectiveDimensions ?? (request.width, request.height)
        guard dimensions.height > 0 else { return 3 / 4 }
        return CGFloat(dimensions.width / dimensions.height)
    }

    var body: some View {
        preview
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: 540, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(url.pathExtension.uppercased()) generated poster preview for \(request.posterCity)")
    }

    @ViewBuilder
    private var preview: some View {
        switch url.pathExtension.lowercased() {
        case "png":
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                UnsupportedPreview(url: url, message: "PNG preview unavailable")
            }
        case "pdf":
            PDFPosterPreview(url: url)
                .id(url)
        case "svg":
            SVGPosterPreview(url: url)
                .id(url)
        default:
            UnsupportedPreview(url: url, message: "\(url.pathExtension.uppercased()) saved")
        }
    }
}

private struct PDFPosterPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        view.autoScales = true
    }
}

private struct SVGPosterPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
    }
}

private struct UnsupportedPreview: View {
    let url: URL
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.largeTitle)
                .foregroundStyle(AppDesign.clearBlue)

            Text(message)
                .font(.title3)
                .foregroundStyle(AppDesign.inkBlue)

            Text(url.lastPathComponent)
                .font(AppDesign.metadataFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.panelFill)
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
