// Sweepside: a menu bar app that finds what's eating a developer's disk (node_modules,
// virtualenvs, build folders, Xcode DerivedData, package caches) and cleans it, starting
// with projects you haven't touched in a while. Moves to the Trash by default; works offline.

import SwiftUI

@main
struct SweepsideApp: App {
    @StateObject private var store = SweepStore()
    @AppStorage("sizeInMenuBar") private var sizeInMenuBar = true

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            PanelSnapshot.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--demo-gif"), i + 1 < args.count {
            DemoReel.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if CLI.wants(args) { exit(CLI.run(args)) }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            MenuBarLabel(bytes: store.staleBytes, scanning: store.scanning, showSize: sizeInMenuBar)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store).tint(.sweep)
        }
    }
}

/// The status item, drawn as one template image so it follows the menu bar's colors.
/// Shows the space in idle projects once it's worth mentioning (1 GB).
struct MenuBarLabel: View {
    let bytes: Int64
    var scanning = false
    var showSize = true

    var body: some View {
        Image(nsImage: rendered)
    }

    var text: String? {
        guard showSize, bytes >= 1_000_000_000 else { return nil }
        let (value, unit) = splitBytes(bytes)
        return "\(value) \(unit)"
    }

    var content: some View {
        HStack(spacing: 4) {
            MenuGlyph(full: bytes >= 1_000_000_000, scanning: scanning).frame(width: 16, height: 16)
            if let text {
                Text(text).font(.system(size: 13, weight: .medium).monospacedDigit())
            }
        }
        .padding(.vertical, 1)
    }

    private var rendered: NSImage {
        let renderer = ImageRenderer(content: content.foregroundStyle(.black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = text.map { "Sweepside, \($0) to clean" } ?? "Sweepside"
        return image
    }
}

/// A broom: solid bristles when there's something worth cleaning, outlined when there isn't.
/// (No frame: inside the family's rounded square it read as a ticked checkbox.)
struct MenuGlyph: View {
    let full: Bool
    var scanning = false

    var body: some View {
        Canvas { ctx, size in
            let u = size.width / 16
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            var handle = Path()
            handle.move(to: pt(14, 2))
            handle.addLine(to: pt(9.2, 6.8))
            ctx.stroke(handle, with: .foreground, style: StrokeStyle(lineWidth: 1.7 * u, lineCap: .round))
            // Bristles: a fan widening away from the handle, split into strands
            var head = Path()
            head.addLines([pt(7.4, 5.6), pt(10.4, 8.6), pt(6.4, 14.4), pt(1.6, 9.6)])
            head.closeSubpath()
            if full || scanning {
                ctx.fill(head, with: .foreground)
                ctx.blendMode = .clear
                for (from, to) in [((8.0, 7.2), (3.3, 11.4)), ((9.0, 8.2), (5.0, 12.9))] {
                    var cut = Path()
                    cut.move(to: pt(from.0, from.1))
                    cut.addLine(to: pt(to.0, to.1))
                    ctx.stroke(cut, with: .color(.black), lineWidth: 0.7 * u)
                }
            } else {
                ctx.stroke(head, with: .foreground, style: StrokeStyle(lineWidth: 1.2 * u, lineJoin: .round))
            }
        }
    }
}
