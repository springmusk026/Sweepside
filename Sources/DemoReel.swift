import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// `Sweepside --demo-gif <file.gif>` renders the README animation from the real panel and
/// demo data: pick idle projects one by one, move them to the Trash, free the space.
/// Frames are drawn like snapshots (final states) and crossfaded.
enum DemoReel {
    private struct Shot {
        let store: SweepStore
        let hold: Double
        var fade = true
    }

    @MainActor
    static func write(to url: URL) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let stale = Demo.result.projects.filter { $0.idle(now: Date()) >= 30 * 86_400 }
        let report = CleanReport(items: stale.flatMap(\.artifacts).map {
            Cleaned(original: $0.path, trashed: "/x/.Trash/\($0.name)", bytes: $0.bytes)
        })

        // Selection builds up one project at a time
        var shots: [Shot] = []
        for count in 0...stale.count {
            let store = Demo.store()
            store.selected = Set(stale.prefix(count).flatMap(\.artifacts).map(\.path))
            shots.append(Shot(store: store, hold: count == 0 ? 1.4 : count == stale.count ? 1.6 : 0.42, fade: false))
        }
        shots += [
            Shot(store: Demo.store(report: report, without: true), hold: 2.0),
            Shot(store: Demo.store(report: report, without: true, freed: true), hold: 3.0),
        ]

        let images = shots.map { render($0.store) }
        guard let first = images.first, let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, images.count * 4, nil) else { return }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

        func add(_ image: CGImage, _ delay: Double) {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        }
        add(first, shots[0].hold)
        for i in 1..<images.count {
            if shots[i].fade {
                for step in 1...3 { add(blend(images[i - 1], images[i], Double(step) / 4), 0.04) }
            }
            add(images[i], shots[i].hold)
        }
        CGImageDestinationFinalize(destination)
    }

    /// The panel hanging under a menu bar, on a plain backdrop, at a fixed canvas size.
    @MainActor
    private static func render(_ store: SweepStore) -> CGImage {
        let panel = PanelView()
            .environmentObject(store)
            .environment(\.isSnapshot, true)
            .environment(\.flatGlow, true)
            .environment(\.colorScheme, .dark)
            .background(Color(white: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))

        let scene = VStack(spacing: 6) {
            menuBar(bytes: store.staleBytes)
            HStack {
                Spacer()
                panel.padding(.trailing, 28)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 490, height: 600, alignment: .top)
        .clipped()   // a long list runs off the bottom, like a cropped screenshot (a fade would band)
        .background(backdrop)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: scene)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        return image!
    }

    private static let backdrop = Color(white: 0.085)

    private static func menuBar(bytes: Int64) -> some View {
        HStack(spacing: 16) {
            Spacer()
            MenuBarLabel(bytes: bytes).content
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.18)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Thu 9:41 AM").font(.system(size: 13, weight: .medium))
        }
        .font(.system(size: 14))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color.black.opacity(0.35))
    }

    private static func blend(_ a: CGImage, _ b: CGImage, _ t: Double) -> CGImage {
        let ctx = CGContext(data: nil, width: a.width, height: a.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: a.width, height: a.height)
        ctx.draw(a, in: rect)
        ctx.setAlpha(t)
        ctx.draw(b, in: rect)
        return ctx.makeImage()!
    }
}
