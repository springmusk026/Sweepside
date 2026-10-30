// The command line. Run the app binary with arguments, or link it as `sweepside`:
//   sweepside                  projects with cleanable folders, biggest first
//   sweepside --caches         shared developer caches too
//   sweepside clean            move folders of projects idle 30+ days to the Trash
//   sweepside --json           the scan as JSON

import Foundation

enum CLI {
    static func wants(_ args: [String]) -> Bool {
        let invokedAs = (args.first.map { ($0 as NSString).lastPathComponent } ?? "")
        let flags = args.dropFirst().filter { !$0.hasPrefix("-psn") && !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") }
        return invokedAs == "sweepside" || flags.contains { ["--json", "--caches", "--help", "-h", "clean", "--version", "--in", "--stale"].contains($0) }
    }

    static func run(_ argv: [String]) -> Int32 {
        let args = Array(argv.dropFirst())
        let style = Style(enabled: isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil)
        if args.contains("--help") || args.contains("-h") { print(help); return 0 }
        if args.contains("--version") { print("sweepside \(version)"); return 0 }

        let staleDays = value(after: "--stale", in: args).flatMap(Int.init) ?? Prefs.staleDays
        let roots = values(after: "--in", in: args).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        let scanRoots = roots.isEmpty ? Prefs.roots : roots
        let interactive = isatty(STDERR_FILENO) != 0

        let result = Scanner.scan(roots: scanRoots) { count in
            if interactive { FileHandle.standardError.write(Data("\r\u{1B}[2KScanning… \(count) folders".utf8)) }
        }
        if interactive { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }

        if args.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write((try? encoder.encode(result)) ?? Data("{}".utf8))
            print()
            return 0
        }

        let now = Date()
        let stale = result.projects.filter { $0.idle(now: now) >= TimeInterval(staleDays) * 86_400 }
        let withCaches = args.contains("--caches")

        if args.contains("clean") {
            let projects = args.contains("--all") ? result.projects : stale
            let items = projects.flatMap(\.artifacts) + (withCaches ? result.caches : [])
            guard !items.isEmpty else {
                print("Nothing to clean: no projects idle for \(staleDays)+ days\(withCaches ? " and no caches" : "").")
                return 0
            }
            let permanent = args.contains("--permanent")
            print(table(projects, now: now, style: style))
            if withCaches { print(); print(cacheTable(result.caches, style: style)) }
            let total = items.reduce(0) { $0 + $1.bytes }
            print()
            if !args.contains("--yes") {
                print("\(permanent ? "Permanently delete" : "Move to the Trash") \(items.count) folders, \(fmtBytes(total))? [y/N] ", terminator: "")
                guard let answer = readLine(), answer.lowercased().hasPrefix("y") else { print("Nothing changed."); return 1 }
            }
            let report = Cleaner.clean(items, roots: scanRoots, permanent: permanent)
            print(permanent ? "Freed \(style.bold(fmtBytes(report.bytes)))." :
                    "Moved \(style.bold(fmtBytes(report.bytes))) to the Trash. Empty the Trash to get the space back.")
            for failure in report.failures { FileHandle.standardError.write(Data("skipped \(failure)\n".utf8)) }
            return report.failures.isEmpty ? 0 : 1
        }

        if result.projects.isEmpty && !withCaches {
            print("No build folders over 1 MB in \(scanRoots.map(abbreviate).joined(separator: ", ")).")
            return 0
        }
        if !result.projects.isEmpty { print(table(result.projects, now: now, style: style, staleDays: staleDays)) }
        if withCaches && !result.caches.isEmpty { print(); print(cacheTable(result.caches, style: style)) }
        print()
        let staleBytes = stale.reduce(0) { $0 + $1.bytes }
        if staleBytes > 0 {
            print("\(style.bold(fmtBytes(staleBytes))) in \(stale.count) project\(stale.count == 1 ? "" : "s") untouched for \(staleDays)+ days. "
                  + "Run \(style.bold("sweepside clean")) to move it to the Trash.")
        } else {
            print("No projects untouched for \(staleDays)+ days.")
        }
        if !withCaches && !result.caches.isEmpty {
            print(style.dim("Plus \(fmtBytes(result.caches.reduce(0) { $0 + $1.bytes })) in shared caches: sweepside --caches"))
        }
        return 0
    }

    static func table(_ projects: [Project], now: Date, style: Style, staleDays: Int? = nil) -> String {
        let rows = projects.map { p -> [String] in
            let idle = p.idle(now: now)
            return [fmtBytes(p.bytes), idle < 86_400 ? "today" : fmtIdle(idle), p.name,
                    p.artifacts.map(\.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", "),
                    abbreviate(p.path)]
        }
        let header = ["SIZE", "IDLE", "PROJECT", "FOLDERS", "WHERE"]
        return render(header, rows, style: style) { i, cell, row in
            switch i {
            case 0: return style.bold(cell)
            case 1:
                let stale = staleDays.map { projects[row].idle(now: now) >= TimeInterval($0) * 86_400 } ?? true
                return stale ? style.yellow(cell) : style.dim(cell)
            case 4: return style.dim(cell)
            default: return cell
            }
        }
    }

    static func cacheTable(_ caches: [Artifact], style: Style) -> String {
        let rows = caches.map { [fmtBytes($0.bytes), $0.name, abbreviate($0.path)] }
        return render(["SIZE", "CACHE", "WHERE"], rows, style: style) { i, cell, _ in
            i == 0 ? style.bold(cell) : i == 2 ? style.dim(cell) : cell
        }
    }

    private static func render(_ header: [String], _ rows: [[String]], style: Style,
                               cell: (Int, String, Int) -> String) -> String {
        let widths = header.indices.map { i in ([header[i]] + rows.map { $0[i] }).map(\.count).max() ?? 0 }
        func pad(_ s: String, _ i: Int) -> String {
            i == header.count - 1 ? s : i == 0 ? String(repeating: " ", count: widths[i] - s.count) + s
                : s.padding(toLength: widths[i], withPad: " ", startingAt: 0)
        }
        var lines = [header.indices.map { style.dim(pad(header[$0], $0)) }.joined(separator: "  ")]
        for (r, row) in rows.enumerated() {
            lines.append(row.indices.map { cell($0, pad(row[$0], $0), r) }.joined(separator: "  "))
        }
        return lines.joined(separator: "\n")
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    private static func values(after flag: String, in args: [String]) -> [String] {
        args.indices.filter { args[$0] == flag && $0 + 1 < args.count }.map { args[$0 + 1] }
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static let help = """
    sweepside: find and clean what's eating your disk as a developer

      sweepside                   projects with build folders (node_modules, .venv, target…), biggest first
      sweepside --caches          shared caches too (Xcode DerivedData, Homebrew, npm, pip, Cargo…)
      sweepside clean             move folders of projects idle 30+ days to the Trash (asks first)
          --stale <days>          idle threshold (default 30, or what you set in the app)
          --all                   every project, idle or not
          --caches                include shared caches
          --permanent             delete instead of moving to the Trash
          --yes                   don't ask
      sweepside --in <folder>     scan this folder instead of the app's scan folders (repeatable)
      sweepside --json            the scan as JSON

    Run without arguments from Finder or Spotlight for the menu bar app.
    """

    struct Style {
        let enabled: Bool
        private func wrap(_ code: String, _ s: String) -> String { enabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
        func bold(_ s: String) -> String { wrap("1", s) }
        func dim(_ s: String) -> String { wrap("2", s) }
        func yellow(_ s: String) -> String { wrap("33", s) }
    }
}
