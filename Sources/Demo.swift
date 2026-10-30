import Foundation

/// Made-up projects and caches for screenshots: reproducible and private.
enum Demo {
    static let disk: (Int64, Int64) = (61_400_000_000, 494_380_000_000)

    @MainActor
    static func store(report: CleanReport? = nil, without cleaned: Bool = false, freed: Bool = false) -> SweepStore {
        var r = result
        if cleaned {
            r.projects = r.projects.filter { $0.idle(now: Date()) < 30 * 86_400 }
        }
        // Space comes back once it leaves the Trash
        let free = freed ? disk.0 + staleBytes : disk.0
        return SweepStore(demo: r, disk: (free, disk.1), report: report, freed: freed)
    }

    static var staleBytes: Int64 {
        result.projects.filter { $0.idle(now: Date()) >= 30 * 86_400 }.reduce(0) { $0 + $1.bytes }
    }

    static var result: ScanResult {
        let home = NSHomeDirectory()
        let now = Date()
        func days(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        func a(_ dir: String, _ name: String, _ eco: String, _ gb: Double, shared: Double = 0, regen: String = "") -> Artifact {
            Artifact(path: "\(home)/\(dir)/\(name)", name: name, ecosystem: eco, regenerate: regen,
                     bytes: Int64(gb * 1e9), shared: Int64(shared * 1e9), files: Int(gb * 40_000))
        }
        func p(_ dir: String, _ idle: Double, _ items: [Artifact]) -> Project {
            Project(path: "\(home)/\(dir)", name: (dir as NSString).lastPathComponent, lastActive: days(idle), artifacts: items)
        }
        let projects = [
            p("Projects/old/shop-redesign", 212, [a("Projects/old/shop-redesign", "node_modules", "Node", 1.84, regen: "npm install"),
                                                  a("Projects/old/shop-redesign", ".next", "Next.js", 0.62, regen: "next build")]),
            p("Projects/ml/sentiment", 97, [a("Projects/ml/sentiment", ".venv", "Python", 4.71, regen: "uv sync")]),
            p("Projects/rust/raytracer", 64, [a("Projects/rust/raytracer", "target", "Rust", 3.27, regen: "cargo build")]),
            p("Projects/hackathon-2025", 341, [a("Projects/hackathon-2025", "node_modules", "Node", 0.94, regen: "npm install"),
                                               a("Projects/hackathon-2025/ios", "Pods", "CocoaPods", 0.41, regen: "pod install")]),
            p("Projects/blog", 45, [a("Projects/blog", "node_modules", "Node", 0.38, shared: 0.52, regen: "pnpm install")]),
            p("Projects/acme", 0.2, [a("Projects/acme", "node_modules", "Node", 2.12, regen: "pnpm install"),
                                     a("Projects/acme/apps/web", ".next", "Next.js", 0.88, regen: "next build"),
                                     a("Projects/acme/api", ".venv", "Python", 0.71, regen: "uv sync")]),
            p("Projects/Portside", 2, [a("Projects/Portside", ".build", "Swift", 0.33, regen: "swift build")]),
        ].sorted { $0.bytes > $1.bytes }
        let caches = [
            Artifact(path: "\(home)/Library/Developer/Xcode/DerivedData", name: "Xcode DerivedData", ecosystem: "Xcode",
                     regenerate: "Rebuilt on the next build", bytes: 11_600_000_000),
            Artifact(path: "\(home)/Library/Developer/Xcode/iOS DeviceSupport", name: "iOS DeviceSupport", ecosystem: "Xcode",
                     regenerate: "Copied again when you connect a device", bytes: 6_060_000_000),
            Artifact(path: "\(home)/.cache/huggingface", name: "Hugging Face downloads", ecosystem: "AI models",
                     regenerate: "Models download again, which can be slow", bytes: 5_200_000_000),
            Artifact(path: "\(home)/Library/pnpm/store", name: "pnpm store", ecosystem: "Node",
                     regenerate: "Downloaded again by pnpm", bytes: 2_310_000_000),
            Artifact(path: "\(home)/Library/Caches/Homebrew", name: "Homebrew downloads", ecosystem: "Homebrew",
                     regenerate: "Downloaded again when needed", bytes: 1_240_000_000),
        ]
        return ScanResult(date: now.addingTimeInterval(-180), duration: 2.4, folders: 48_213, projects: projects, caches: caches)
    }
}
