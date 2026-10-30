import SwiftUI

enum Tab: String, CaseIterable { case projects, caches }

/// Forces a state when rendering snapshots.
struct PanelPreview {
    var tab: Tab = .projects
    var hovered: String? = nil
}

struct PanelView: View {
    var preview: PanelPreview? = nil
    @EnvironmentObject private var store: SweepStore
    @State private var tab = Tab.projects
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.openSettings) private var openSettings
    @AppStorage("freedTotal") private var freedTotal = 0.0

    private var shownTab: Tab { preview?.tab ?? tab }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header.entrance(0)
            Group {
                if let report = store.report { ReportCard(report: report) } else { hero }
            }
            .entrance(1)
            if store.result != nil {
                Segmented(items: [
                    .init(value: Tab.projects, title: "Projects  \(store.result?.projects.count ?? 0)"),
                    .init(value: Tab.caches, title: "Caches  \(store.caches.count)"),
                ], selection: Binding(get: { shownTab }, set: { tab = $0 }), stretch: true, small: true)
                .entrance(2)
                if isSnapshot {
                    list
                } else {
                    ViewThatFits(in: .vertical) {
                        list
                        ScrollView { list }.scrollIndicators(.never)
                    }
                    .frame(maxHeight: 400)
                }
            }
            footer.entrance(4)
        }
        .padding(Space.m)
        .frame(width: 380)
        .onAppear {
            store.tick()
            if let date = store.result?.date, Date().timeIntervalSince(date) > 3600 { store.scan() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.xs) {
            if store.scanning {
                StatusDot(color: .live, active: !isSnapshot)
                // The first scan shows the count in the hero card instead
                Text(store.result == nil ? "Scanning…" : "Scanning… \(store.progress.formatted()) folders")
                    .contentTransition(.numericText())
            } else if let result = store.result {
                StatusDot(color: .secondary, hollow: true)
                Text("Scanned \(fmtAgo(result.date, now: store.now)) · \(result.folders.formatted()) folders")
            } else {
                StatusDot(color: .secondary, hollow: true)
                Text("Not scanned yet")
            }
            Spacer()
            CircleButton(icon: "arrow.clockwise", help: "Scan again") { store.scan() }
                .disabled(store.scanning)
            CircleButton(icon: "gearshape", help: "Settings") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .font(Typo.heading)
        .foregroundStyle(.secondary)
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        if store.result == nil {
            scanningHero
        } else {
            selectionHero
        }
    }

    /// The first scan: the folder count is the number that's moving.
    private var scanningHero: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.scanning ? "Scanning" : "Not scanned yet").font(Typo.heading).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(store.progress.formatted()).font(Typo.hero).contentTransition(.numericText())
                    Text("folders").font(Typo.unit).foregroundStyle(.secondary)
                }
                Text(store.scanning ? "Looking for build folders and caches. Nothing is changed."
                                    : "Find build folders and caches you can clean.")
                    .font(Typo.caption).foregroundStyle(.secondary)
            }
            if !store.scanning {
                PrimaryPill(title: "Scan now", icon: "magnifyingglass") { store.scan() }
            }
        }
    }

    private var selectionHero: some View {
        let bytes = store.selectedBytes
        let projects = (store.result?.projects ?? []).filter { store.isSelected($0) != false }.count
        let caches = store.caches.filter { store.selected.contains($0.path) }.count
        let inGB = bytes >= 1_000_000_000
        return Card(glow: bytes > 0 ? .sweep : nil) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected to clean").font(Typo.heading).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    AnimatedNumber(value: Double(bytes) / (inGB ? 1e9 : 1e6)) {
                        inGB ? String(format: "%.1f", $0) : String(format: "%.0f", $0)
                    }
                    .font(Typo.hero)
                    .foregroundStyle(bytes > 0 ? Color.primary : Color.secondary)
                    Text(inGB ? "GB" : "MB").font(Typo.unit).foregroundStyle(.secondary)
                }
                Text(selectionSummary(projects: projects, caches: caches))
                    .font(Typo.caption).foregroundStyle(.secondary)
            }
            if let disk = store.disk {
                DiskLine(free: disk.free, total: disk.total, freeing: bytes)
            }
            PrimaryPill(title: store.permanentDelete ? "Delete permanently" : "Move to Trash",
                        detail: bytes > 0 ? fmtBytes(bytes) : nil, icon: "trash") {
                store.cleanSelected()
            }
            .disabled(bytes == 0 || store.scanning)
        }
    }

    private func selectionSummary(projects: Int, caches: Int) -> String {
        if store.result == nil { return store.scanning ? "Looking for build folders and caches…" : "Scan to find build folders and caches." }
        if projects == 0 && caches == 0 {
            return store.stale.isEmpty ? "Nothing untouched for \(store.staleDays)+ days. Pick anything below."
                                       : "Nothing selected. Pick projects below."
        }
        var parts: [String] = []
        if projects > 0 { parts.append(projects == 1 ? "1 project" : "\(projects) projects") }
        if caches > 0 { parts.append(caches == 1 ? "1 cache" : "\(caches) caches") }
        return parts.joined(separator: " and ") + ". All of it regenerates when you need it."
    }

    // MARK: Lists

    @ViewBuilder private var list: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            switch shownTab {
            case .projects:
                if (store.result?.projects ?? []).isEmpty {
                    EmptyCard(text: "No build folders over 1 MB in \(Prefs.roots.map(abbreviate).joined(separator: ", ")).")
                } else {
                    if !store.stale.isEmpty {
                        ProjectSection(title: "Untouched for \(store.staleDays)+ days", projects: store.stale, hovered: preview?.hovered)
                    }
                    if !store.active.isEmpty {
                        ProjectSection(title: "Active recently", projects: store.active, hovered: preview?.hovered)
                    }
                }
            case .caches:
                if store.caches.isEmpty {
                    EmptyCard(text: "No developer caches over 1 MB.")
                } else {
                    CacheSection(caches: store.caches, hovered: preview?.hovered)
                }
            }
        }
        .entrance(3)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Space.xs) {
            if freedTotal > 0 {
                Text("\(fmtBytes(Int64(freedTotal))) freed with Sweepside so far")
                    .font(Typo.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            FooterButton(title: "Quit", icon: nil) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

// MARK: - Pieces

/// The disk, as a dotted track of space used, and what cleaning would leave free.
struct DiskLine: View {
    let free: Int64
    let total: Int64
    let freeing: Int64

    var body: some View {
        let used = Double(total - free) / Double(max(total, 1))
        let low = Double(free) / Double(max(total, 1)) < 0.1
        VStack(alignment: .leading, spacing: Space.xxs) {
            Animated(target: used) { DotTrack(value: $0, tint: low ? .caution : Color.primary.opacity(0.55), dots: 40, size: 3.5) }
            HStack(spacing: 0) {
                Text("\(fmtBytes(free)) free").foregroundStyle(low ? Color.caution : .secondary)
                if freeing > 0 {
                    Text("  →  ").foregroundStyle(.tertiary)
                    Text("\(fmtBytes(free + freeing)) after").foregroundStyle(Color.sweep)
                }
                Spacer()
                Text("of \(fmtBytes(total))").foregroundStyle(.tertiary)
            }
            .font(Typo.mono)
        }
    }
}

struct ProjectSection: View {
    let title: String
    let projects: [Project]
    var hovered: String? = nil
    @EnvironmentObject private var store: SweepStore

    var body: some View {
        let allOn = projects.allSatisfy { store.isSelected($0) == true }
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xxs) {
                Text(title).font(Typo.heading).foregroundStyle(.secondary)
                Text(fmtBytes(projects.reduce(0) { $0 + $1.bytes })).font(Typo.mono).foregroundStyle(.tertiary)
                Spacer()
                Button(allOn ? "Select none" : "Select all") {
                    withAnimation(Motion.quick) { store.setAll(projects, !allOn) }
                }
                .buttonStyle(.plain)
                .font(Typo.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.xxs)
            Card(padding: 0, spacing: 0) {
                ForEach(Array(projects.enumerated()), id: \.element.id) { i, project in
                    if i > 0 { Rectangle().fill(Color.hairline).frame(height: 0.5).padding(.leading, 36) }
                    ProjectRow(project: project, forceHover: hovered == project.id)
                }
            }
        }
    }
}

struct ProjectRow: View {
    let project: Project
    var forceHover = false
    @EnvironmentObject private var store: SweepStore
    @State private var hovering = false

    var body: some View {
        let state = store.isSelected(project)
        let shared = project.artifacts.reduce(0) { $0 + $1.shared }
        HStack(alignment: .top, spacing: Space.s) {
            Check(state: state).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.xs) {
                    Text(project.name).font(Typo.title).lineLimit(1)
                    Spacer(minLength: Space.xs)
                    Text(fmtBytes(project.bytes))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(state == false ? Color.secondary : Color.primary)
                }
                HStack(spacing: 0) {
                    Text(abbreviate((project.path as NSString).deletingLastPathComponent))
                        .lineLimit(1).truncationMode(.middle)
                    Text("  ·  ").foregroundStyle(.tertiary)
                    Text(idleText).fixedSize()
                    Spacer(minLength: Space.xs)
                    if hovering || forceHover {
                        Button { store.reveal(project.path) } label: {
                            Image(systemName: "folder").font(.system(size: 10.5))
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }
                }
                .font(Typo.mono)
                .foregroundStyle(.secondary)
                .frame(height: 14)
                (Text(project.artifacts.map { "\($0.name) \(fmtBytes($0.bytes))" }.joined(separator: "  ·  "))
                 + Text(shared > 50_000_000 ? "  ·  +\(fmtBytes(shared)) shared" : "").foregroundColor(Color.primary.opacity(0.3)))
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(help(shared))
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background((hovering || forceHover) ? Color.surface : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { withAnimation(Motion.quick) { store.toggle(project) } }
        .contextMenu {
            Button("Show in Finder") { store.reveal(project.path) }
            Button("Copy Path") { store.copy(project.path) }
            Divider()
            ForEach(project.artifacts) { a in
                Toggle("\(a.name) (\(fmtBytes(a.bytes)))", isOn: Binding(get: { store.selected.contains(a.path) },
                                                                        set: { _ in store.toggle(a) }))
            }
        }
    }

    private var idleText: String {
        let idle = project.idle(now: store.now)
        return idle < 86_400 ? "active today" : "idle \(fmtIdle(idle))"
    }

    private func help(_ shared: Int64) -> String {
        var lines = project.artifacts.map { "\(abbreviate($0.path)): \(fmtBytes($0.bytes)), regenerate with \($0.regenerate)" }
        if shared > 0 {
            lines.append("\(fmtBytes(shared)) more is hard-linked from a shared store (pnpm, uv), so deleting this copy doesn't free it.")
        }
        return lines.joined(separator: "\n")
    }
}

struct CacheSection: View {
    let caches: [Artifact]
    var hovered: String? = nil
    @EnvironmentObject private var store: SweepStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Shared caches make installs and builds faster. Clean them when you need the space.")
                .font(Typo.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xxs)
            Card(padding: 0, spacing: 0) {
                ForEach(Array(caches.enumerated()), id: \.element.id) { i, cache in
                    if i > 0 { Rectangle().fill(Color.hairline).frame(height: 0.5).padding(.leading, 36) }
                    CacheRow(cache: cache, forceHover: hovered == cache.id)
                }
            }
        }
    }
}

struct CacheRow: View {
    let cache: Artifact
    var forceHover = false
    @EnvironmentObject private var store: SweepStore
    @State private var hovering = false

    var body: some View {
        let on = store.selected.contains(cache.path)
        let slow = cache.ecosystem == "AI models"
        HStack(alignment: .top, spacing: Space.s) {
            Check(state: on).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cache.name).font(Typo.title).lineLimit(1)
                    Text(cache.ecosystem).font(Typo.caption).foregroundStyle(.secondary)
                    Spacer(minLength: Space.xs)
                    Text(fmtBytes(cache.bytes))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                }
                HStack {
                    Text(cache.regenerate).font(Typo.caption).foregroundStyle(slow ? Color.caution : .secondary).lineLimit(1)
                    Spacer()
                    if hovering || forceHover {
                        Button { store.reveal(cache.path) } label: { Image(systemName: "folder").font(.system(size: 10.5)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Show in Finder")
                    }
                }
                .frame(height: 14)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background((hovering || forceHover) ? Color.surface : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { withAnimation(Motion.quick) { store.toggle(cache) } }
        .help(abbreviate(cache.path))
    }
}

/// After cleaning: what happened, with Undo and "Free it now" while it's in the Trash.
struct ReportCard: View {
    let report: CleanReport
    @EnvironmentObject private var store: SweepStore
    @AppStorage("freedTotal") private var freedTotal = 0.0

    var body: some View {
        let freed = report.permanent || store.freedFromTrash
        Card(glow: .live) {
            VStack(alignment: .leading, spacing: 2) {
                Text(freed ? "Freed" : "Moved to the Trash").font(Typo.heading).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    let (value, unit) = splitBytes(report.bytes)
                    Text(value).font(Typo.hero)
                    Text(unit).font(Typo.unit).foregroundStyle(.secondary)
                }
                Text(freed ? "The space is yours again." : "The space comes back once these leave the Trash.")
                    .font(Typo.caption).foregroundStyle(.secondary)
                if !report.failures.isEmpty {
                    Text(report.failures.count == 1 ? "1 folder was skipped." : "\(report.failures.count) folders were skipped.")
                        .font(Typo.caption).foregroundStyle(Color.caution)
                        .help(report.failures.joined(separator: "\n"))
                }
            }
            if let disk = store.disk { DiskLine(free: disk.free, total: disk.total, freeing: 0) }
            HStack(spacing: Space.xs) {
                if !freed {
                    PrimaryPill(title: "Free it now", icon: "bolt.fill") { store.freeNow() }
                        .help("Deletes these folders from the Trash, and nothing else in it")
                    FooterButton(title: "Undo", icon: "arrow.uturn.backward") { store.undo() }
                }
                Spacer()
                FooterButton(title: "Done", icon: nil) { store.dismissReport() }
            }
        }
        .onAppear { if report.permanent { freedTotal += Double(report.bytes) } }
        .onChange(of: store.freedFromTrash) { _, now in if now { freedTotal += Double(report.bytes) } }
    }
}

struct EmptyCard: View {
    let text: String
    var body: some View {
        Card { Text(text).font(Typo.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
}

/// A round checkbox: filled when selected, a dash when partly selected.
struct Check: View {
    let state: Bool?   // nil: partly

    var body: some View {
        ZStack {
            Circle()
                .fill(state == false ? Color.clear : Color.sweep)
                .overlay(Circle().strokeBorder(state == false ? Color.secondary.opacity(0.45) : Color.sweep, lineWidth: 1.2))
            Image(systemName: state == nil ? "minus" : "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
                .opacity(state == false ? 0 : 1)
        }
        .frame(width: 16, height: 16)
        .animation(Motion.quick, value: state)
        .accessibilityAddTraits(state == true ? .isSelected : [])
    }
}

struct FooterButton: View {
    let title: String
    let icon: String?
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xxs + 2) {
                if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
                Text(title)
            }
            .font(Typo.caption.weight(.medium))
            .foregroundStyle(tint ?? (hovering ? .primary : .secondary))
            .padding(.horizontal, Space.xs)
            .frame(height: 24)
            .background(Capsule().fill(hovering ? Color.surface : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
    }
}
