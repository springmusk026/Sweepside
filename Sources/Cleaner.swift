// Moves folders to the Trash (or deletes them), and undoes that.
// Before touching anything it checks the folder again: still a real directory (not a
// link), still named as scanned, and inside a scan folder or one of the known caches.

import Darwin
import Foundation

struct Cleaned: Codable, Equatable {
    let original: String
    /// Where it went in the Trash; nil when deleted permanently.
    var trashed: String?
    let bytes: Int64
}

struct CleanReport: Codable, Equatable {
    var items: [Cleaned] = []
    var failures: [String] = []      // "path: reason"
    var permanent = false
    var date = Date()

    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var inTrash: [Cleaned] { items.filter { $0.trashed != nil } }
}

enum Cleaner {
    static func clean(_ artifacts: [Artifact], roots: [String], permanent: Bool) -> CleanReport {
        var report = CleanReport(permanent: permanent)
        for a in artifacts {
            if let problem = unsafeReason(a, roots: roots) {
                report.failures.append("\(a.path): \(problem)")
                continue
            }
            let url = URL(fileURLWithPath: a.path)
            do {
                if permanent {
                    try remove(url)
                    report.items.append(Cleaned(original: a.path, trashed: nil, bytes: a.bytes))
                } else {
                    report.items.append(Cleaned(original: a.path, trashed: try trash(url), bytes: a.bytes))
                }
            } catch {
                report.failures.append("\(a.path): \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Puts trashed folders back where they were. Returns the ones restored.
    static func undo(_ report: CleanReport) -> [Cleaned] {
        report.inTrash.filter { item in
            guard let trashed = item.trashed, !FileManager.default.fileExists(atPath: item.original) else { return false }
            return (try? FileManager.default.moveItem(atPath: trashed, toPath: item.original)) != nil
        }
    }

    /// Permanently deletes what an earlier clean moved to the Trash, and only that.
    static func emptyFromTrash(_ report: CleanReport) -> Int64 {
        var freed: Int64 = 0
        for item in report.inTrash {
            guard let trashed = item.trashed, trashed.contains("/.Trash") else { continue }
            if (try? remove(URL(fileURLWithPath: trashed))) != nil { freed += item.bytes }
        }
        return freed
    }

    /// Why a folder must not be touched, or nil if it's fine.
    static func unsafeReason(_ a: Artifact, roots: [String]) -> String? {
        var st = stat()
        guard lstat(a.path, &st) == 0 else { return "no longer exists" }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return "not a folder (a link or file now)" }
        let home = NSHomeDirectory()
        let isCache = Rules.caches.contains { (home as NSString).appendingPathComponent($0.path) == a.path }
        if isCache { return nil }
        guard (a.path as NSString).lastPathComponent == a.name else { return "renamed since the scan" }
        let inside = roots.contains { root in a.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") }
        return inside ? nil : "outside the scan folders"
    }

    /// Moves a folder to the Trash. Moving a folder needs write permission on the folder
    /// itself, so a read-only one (Go's module cache, a `chmod -R a-w` vendor) gets it first.
    private static func trash(_ url: URL) throws -> String? {
        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        } catch {
            var st = stat()
            guard lstat(url.path, &st) == 0, st.st_mode & S_IWUSR == 0 else { throw error }
            chmod(url.path, st.st_mode | S_IWUSR)
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        }
        return trashed?.path
    }

    /// Deletes a folder, making read-only contents writable first if needed
    /// (Go's module cache is read-only on purpose).
    private static func remove(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            makeWritable(url.path)
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func makeWritable(_ path: String) {
        path.withCString { cPath in
            var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cPath), nil]
            defer { free(paths[0]) }
            guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return }
            defer { fts_close(fts) }
            while let entry = fts_read(fts) {
                let info = Int32(entry.pointee.fts_info)
                guard info == FTS_D || info == FTS_F, let st = entry.pointee.fts_statp?.pointee else { continue }
                chmod(entry.pointee.fts_path, st.st_mode | S_IWUSR | (info == FTS_D ? S_IXUSR | S_IRUSR : 0))
            }
        }
    }
}
