// Finds cleanable folders and measures how much space deleting them would actually free.
//
// Walking: fts(3) over the scan folders, without following links or crossing volumes,
// stopping at every cleanable folder (so the walk never enters node_modules).
// Measuring: allocated blocks of every file, in parallel per folder. Files with more
// than one hard link (pnpm and uv link packages from a shared store) are counted as
// "shared": deleting this copy doesn't free them, so they're not promised as freed space.

import Darwin
import Foundation

struct Artifact: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    /// Folder name, or the cache's display name: "node_modules", "Xcode DerivedData".
    let name: String
    let ecosystem: String
    let regenerate: String
    /// Space freed by deleting it.
    var bytes: Int64 = 0
    /// Space in files hard-linked from elsewhere: not freed by deleting this copy.
    var shared: Int64 = 0
    var files: Int = 0
}

struct Project: Codable, Identifiable, Hashable {
    var id: String { path }
    /// The git root, or the folder holding the project's manifest.
    let path: String
    let name: String
    /// Latest sign of work: git activity or a change at the top of the project.
    let lastActive: Date
    var artifacts: [Artifact]

    var bytes: Int64 { artifacts.reduce(0) { $0 + $1.bytes } }

    func idle(now: Date) -> TimeInterval { now.timeIntervalSince(lastActive) }
}

struct ScanResult: Codable {
    var date = Date()
    var duration: TimeInterval = 0
    var folders = 0
    var projects: [Project] = []
    var caches: [Artifact] = []
}

enum Scanner {
    /// Folders smaller than this aren't worth a row.
    static let minimumBytes: Int64 = 1_000_000

    /// Scans `roots` for project folders and the home folder for shared caches.
    /// `progress` is called from background threads with the number of folders walked.
    static func scan(roots: [String], progress: ((Int) -> Void)? = nil) -> ScanResult {
        let start = Date()
        var folders = 0
        var found: [(artifact: Artifact, projectDir: String)] = []
        for root in roots {
            walk(root) { artifact, dir in found.append((artifact, dir)) } counted: {
                folders += 1
                if folders % 500 == 0 { progress?(folders) }
            }
        }

        let home = NSHomeDirectory()
        var caches = Rules.caches.compactMap { c -> Artifact? in
            let path = (home as NSString).appendingPathComponent(c.path)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return Artifact(path: path, name: c.name, ecosystem: c.ecosystem, regenerate: c.regenerate)
        }

        // Measure everything in parallel; sizing is most of the work
        var artifacts = found.map(\.artifact)
        let all = artifacts.count
        let combined = UnsafeMutableBufferPointer<Artifact>.allocate(capacity: all + caches.count)
        defer { combined.deallocate() }
        _ = combined.initialize(from: artifacts + caches)
        DispatchQueue.concurrentPerform(iterations: combined.count) { i in
            measure(&combined[i])
        }
        artifacts = Array(combined[0..<all])
        caches = Array(combined[all...]).filter { $0.bytes + $0.shared >= minimumBytes }

        // Group by project (the git root when there is one), leaving out folders too small to matter
        var groups: [String: [Artifact]] = [:]
        for (i, entry) in found.enumerated() where artifacts[i].bytes + artifacts[i].shared >= minimumBytes {
            groups[projectRoot(for: entry.projectDir), default: []].append(artifacts[i])
        }
        let projects = groups.map { root, items in
            Project(path: root, name: (root as NSString).lastPathComponent,
                    lastActive: lastActivity(root, artifacts: items),
                    artifacts: items.sorted { $0.bytes > $1.bytes })
        }
        .sorted { $0.bytes > $1.bytes }

        return ScanResult(date: Date(), duration: Date().timeIntervalSince(start), folders: folders,
                          projects: projects, caches: caches.sorted { $0.bytes > $1.bytes })
    }

    // MARK: Walking

    private static func walk(_ root: String, found: (Artifact, String) -> Void, counted: () -> Void) {
        let home = NSHomeDirectory()
        let skipped = Set(Rules.skippedHomeFolders.map { (home as NSString).appendingPathComponent($0) })
        let fm = FileManager.default

        root.withCString { cRoot in
            var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cRoot), nil]
            defer { free(paths[0]) }
            guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_NOSTAT | FTS_XDEV, nil) else { return }
            defer { fts_close(fts) }

            while let entry = fts_read(fts) {
                let info = Int32(entry.pointee.fts_info)
                // FTS_NOSTAT leaves non-directories as FTS_NSOK; only directories matter
                guard info == FTS_D else { continue }
                counted()
                let path = String(cString: entry.pointee.fts_path)
                if entry.pointee.fts_level == 0 { continue }
                let name = (path as NSString).lastPathComponent
                let parent = (path as NSString).deletingLastPathComponent

                if skipped.contains(path) { fts_set(fts, entry, FTS_SKIP); continue }

                if let rule = Rules.projects.first(where: { $0.name == name && matches($0, path: path, parent: parent, fm: fm) }) {
                    found(Artifact(path: path, name: name, ecosystem: rule.ecosystem, regenerate: rule.regenerate), parent)
                    fts_set(fts, entry, FTS_SKIP)
                    continue
                }
                if Rules.neverDescend.contains(name) || name.hasPrefix(".")
                    || Rules.packageExtensions.contains((name as NSString).pathExtension.lowercased()) {
                    fts_set(fts, entry, FTS_SKIP)
                }
            }
        }
    }

    private static func matches(_ rule: Rule, path: String, parent: String, fm: FileManager) -> Bool {
        if !rule.inside.isEmpty {
            return rule.inside.contains { access((path as NSString).appendingPathComponent($0), F_OK) == 0 }
        }
        let exact = rule.markers.filter { !$0.hasPrefix("*") }
        if exact.contains(where: { access((parent as NSString).appendingPathComponent($0), F_OK) == 0 }) { return true }
        let suffixes = rule.markers.filter { $0.hasPrefix("*") }.map { String($0.dropFirst()) }
        guard !suffixes.isEmpty, let names = try? fm.contentsOfDirectory(atPath: parent) else { return false }
        return names.contains { n in suffixes.contains { n.hasSuffix($0) } }
    }

    // MARK: Measuring

    static func measure(_ artifact: inout Artifact) {
        var bytes: Int64 = 0, shared: Int64 = 0, files = 0
        var seen = Set<UInt64>()   // hard-linked inodes, counted once
        artifact.path.withCString { cPath in
            var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cPath), nil]
            defer { free(paths[0]) }
            guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
            defer { fts_close(fts) }
            while let entry = fts_read(fts) {
                let info = Int32(entry.pointee.fts_info)
                guard info != FTS_DP, info != FTS_DNR, info != FTS_ERR, info != FTS_NS,
                      let st = entry.pointee.fts_statp?.pointee else { continue }
                let size = Int64(st.st_blocks) * 512
                if info == FTS_F || info == FTS_SL { files += 1 }
                if info == FTS_F && st.st_nlink > 1 {
                    if seen.insert(UInt64(st.st_ino)).inserted { shared += size }
                } else {
                    bytes += size
                }
            }
        }
        artifact.bytes = bytes
        artifact.shared = shared
        artifact.files = files
    }

    // MARK: Projects

    /// The nearest enclosing git repository, else the folder itself. Stops at the home folder.
    static func projectRoot(for dir: String) -> String {
        let home = NSHomeDirectory()
        var current = dir
        while current.count > home.count && current != "/" {
            if access((current as NSString).appendingPathComponent(".git"), F_OK) == 0 { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return dir
    }

    /// The most recent change among git's own bookkeeping and the files at the top of the
    /// project and of each folder holding an artifact, ignoring the artifacts themselves.
    static func lastActivity(_ root: String, artifacts: [Artifact]) -> Date {
        var latest = Date.distantPast
        func consider(_ path: String) {
            var st = stat()
            if lstat(path, &st) == 0 {
                let date = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                if date > latest { latest = date }
            }
        }
        for file in [".git/index", ".git/logs/HEAD", ".git/FETCH_HEAD", ".git/HEAD"] {
            consider((root as NSString).appendingPathComponent(file))
        }
        let excluded = Set(artifacts.map(\.path))
        let dirs = Set([root] + artifacts.map { ($0.path as NSString).deletingLastPathComponent })
        for dir in dirs {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name != ".DS_Store" && name != ".git" {
                let path = (dir as NSString).appendingPathComponent(name)
                if !excluded.contains(path) { consider(path) }
            }
        }
        return latest == .distantPast ? Date() : latest
    }

    /// Free and total space on the volume holding the home folder.
    static func disk() -> (free: Int64, total: Int64)? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }
}
