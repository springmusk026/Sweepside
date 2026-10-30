// The app's state: the last scan (saved, so the panel opens instantly), what's selected,
// and the last clean (for Undo and "Free it now").

import AppKit
import SwiftUI

enum Prefs {
    static var roots: [String] {
        get { UserDefaults.standard.stringArray(forKey: "roots") ?? [NSHomeDirectory()] }
        set { UserDefaults.standard.set(newValue, forKey: "roots") }
    }

    static var staleDays: Int {
        let days = UserDefaults.standard.integer(forKey: "staleDays")
        return days > 0 ? days : 30
    }
}

@MainActor
final class SweepStore: ObservableObject {
    @Published private(set) var result: ScanResult?
    @Published private(set) var scanning = false
    @Published private(set) var progress = 0
    @Published var selected: Set<String> = []          // artifact paths
    @Published private(set) var report: CleanReport?
    @Published private(set) var freedFromTrash = false
    @Published private(set) var disk: (free: Int64, total: Int64)?
    @Published private(set) var now = Date()

    @AppStorage("staleDays") var staleDays = 30 { didSet { selectDefaults() } }
    @AppStorage("permanentDelete") var permanentDelete = false

    private let demo: Bool
    private var timer: Task<Void, Never>?

    /// With `result`, a fixed demo store for snapshots.
    init(demo result: ScanResult? = nil, disk: (Int64, Int64)? = nil, report: CleanReport? = nil,
         freed: Bool = false, scanning: Bool = false) {
        self.demo = result != nil || scanning
        if result != nil || scanning {
            self.result = result
            self.disk = disk
            self.report = report
            self.freedFromTrash = freed
            self.scanning = scanning
            self.progress = scanning ? 18_342 : 0
            selectDefaults()
            return
        }
        self.result = Self.load()
        self.disk = Scanner.disk()
        selectDefaults()
        // Rescan when the saved scan is over 6 hours old, and every 6 hours after
        timer = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.result.map({ Date().timeIntervalSince($0.date) > 6 * 3600 }) ?? true { self.scan() }
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    var staleInterval: TimeInterval { TimeInterval(staleDays) * 86_400 }

    var stale: [Project] { (result?.projects ?? []).filter { $0.idle(now: now) >= staleInterval } }
    var active: [Project] { (result?.projects ?? []).filter { $0.idle(now: now) < staleInterval } }
    var caches: [Artifact] { result?.caches ?? [] }

    var allArtifacts: [Artifact] { (result?.projects ?? []).flatMap(\.artifacts) + caches }
    var selectedArtifacts: [Artifact] { allArtifacts.filter { selected.contains($0.path) } }
    var selectedBytes: Int64 { selectedArtifacts.reduce(0) { $0 + $1.bytes } }
    var staleBytes: Int64 { stale.reduce(0) { $0 + $1.bytes } }

    // MARK: Scanning

    func scan() {
        guard !scanning, !demo else { return }
        scanning = true
        progress = 0
        let roots = Prefs.roots
        // The store lives as long as the app, so these tasks hold it strongly
        Task.detached(priority: .utility) {
            let result = Scanner.scan(roots: roots) { count in
                Task { @MainActor in self.progress = count }
            }
            Self.save(result)
            await MainActor.run {
                withAnimation(Motion.spring) {
                    self.result = result
                    self.now = Date()
                    self.disk = Scanner.disk()
                    self.scanning = false
                    self.selectDefaults()
                }
            }
        }
    }

    /// Projects idle past the threshold are selected; caches never are.
    func selectDefaults() {
        selected = Set(stale.flatMap(\.artifacts).map(\.path))
    }

    // MARK: Selection

    func isSelected(_ project: Project) -> Bool? {
        let picked = project.artifacts.filter { selected.contains($0.path) }.count
        return picked == 0 ? false : picked == project.artifacts.count ? true : nil
    }

    func toggle(_ project: Project) {
        let paths = project.artifacts.map(\.path)
        if isSelected(project) == true { selected.subtract(paths) } else { selected.formUnion(paths) }
    }

    func toggle(_ artifact: Artifact) {
        if selected.contains(artifact.path) { selected.remove(artifact.path) } else { selected.insert(artifact.path) }
    }

    func setAll(_ projects: [Project], _ on: Bool) {
        let paths = projects.flatMap(\.artifacts).map(\.path)
        if on { selected.formUnion(paths) } else { selected.subtract(paths) }
    }

    // MARK: Cleaning

    func cleanSelected() {
        let items = selectedArtifacts
        guard !items.isEmpty else { return }
        let permanent = permanentDelete
        let roots = Prefs.roots
        Task.detached(priority: .userInitiated) {
            let report = Cleaner.clean(items, roots: roots, permanent: permanent)
            await self.finish(report)
        }
    }

    private func finish(_ report: CleanReport) {
        let gone = Set(report.items.map(\.original))
        withAnimation(Motion.spring) {
            self.report = report
            freedFromTrash = false
            remove(gone)
            disk = Scanner.disk()
        }
    }

    func undo() {
        guard let report else { return }
        _ = Cleaner.undo(report)
        withAnimation(Motion.spring) { self.report = nil }
        scan()
    }

    func freeNow() {
        guard let report else { return }
        Task.detached(priority: .userInitiated) {
            _ = Cleaner.emptyFromTrash(report)
            await MainActor.run {
                withAnimation(Motion.spring) {
                    self.freedFromTrash = true
                    self.disk = Scanner.disk()
                }
            }
        }
    }

    func dismissReport() {
        withAnimation(Motion.spring) { report = nil }
    }

    private func remove(_ paths: Set<String>) {
        guard var result else { return }
        result.projects = result.projects.compactMap { p in
            var p = p
            p.artifacts.removeAll { paths.contains($0.path) }
            return p.artifacts.isEmpty ? nil : p
        }
        result.caches.removeAll { paths.contains($0.path) }
        self.result = result
        selected.subtract(paths)
        if !demo { Self.save(result) }
    }

    // MARK: Misc

    func reveal(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func tick() { now = Date() }

    // MARK: Persistence

    nonisolated static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sweepside", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-scan.json")
    }

    nonisolated static func save(_ result: ScanResult) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(result).write(to: saveURL, options: .atomic)
    }

    nonisolated static func load() -> ScanResult? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: saveURL)).flatMap { try? decoder.decode(ScanResult.self, from: $0) }
    }
}
