// What Sweepside may clean. Every rule is a folder a tool regenerates on its own
// (`npm install`, `cargo build`, the next Xcode build), and each is checked against a
// marker so a folder that merely has the same name is left alone: `target` only counts
// next to a Cargo.toml or pom.xml, `.venv` only with a pyvenv.cfg inside.

import Foundation

struct Rule {
    let name: String
    let ecosystem: String
    /// Any of these next to the folder ("*.csproj" matches by extension).
    var markers: [String] = []
    /// Any of these inside the folder.
    var inside: [String] = []
    /// What happens after cleaning, shown in the panel.
    var regenerate: String
}

enum Rules {
    static let projects: [Rule] = [
        Rule(name: "node_modules", ecosystem: "Node", markers: ["package.json"], regenerate: "npm install"),
        Rule(name: ".next", ecosystem: "Next.js", markers: ["package.json"], regenerate: "next build"),
        Rule(name: ".nuxt", ecosystem: "Nuxt", markers: ["package.json"], regenerate: "nuxt dev"),
        Rule(name: ".output", ecosystem: "Nuxt", markers: ["nuxt.config.ts", "nuxt.config.js"], regenerate: "nuxt build"),
        Rule(name: ".svelte-kit", ecosystem: "SvelteKit", markers: ["package.json"], regenerate: "vite dev"),
        Rule(name: ".astro", ecosystem: "Astro", markers: ["package.json"], regenerate: "astro dev"),
        Rule(name: ".turbo", ecosystem: "Turborepo", markers: ["package.json"], regenerate: "turbo run"),
        Rule(name: ".parcel-cache", ecosystem: "Parcel", markers: ["package.json"], regenerate: "parcel"),
        Rule(name: ".angular", ecosystem: "Angular", markers: ["angular.json"], regenerate: "ng serve"),
        Rule(name: ".expo", ecosystem: "Expo", markers: ["package.json"], regenerate: "expo start"),
        Rule(name: ".docusaurus", ecosystem: "Docusaurus", markers: ["package.json"], regenerate: "docusaurus start"),
        Rule(name: ".venv", ecosystem: "Python", inside: ["pyvenv.cfg"], regenerate: "uv sync / pip install"),
        Rule(name: "venv", ecosystem: "Python", inside: ["pyvenv.cfg"], regenerate: "pip install"),
        Rule(name: "env", ecosystem: "Python", inside: ["pyvenv.cfg"], regenerate: "pip install"),
        Rule(name: ".tox", ecosystem: "Python", markers: ["tox.ini", "pyproject.toml", "setup.py"], regenerate: "tox"),
        Rule(name: "target", ecosystem: "Rust", markers: ["Cargo.toml"], regenerate: "cargo build"),
        Rule(name: "target", ecosystem: "Maven", markers: ["pom.xml"], regenerate: "mvn package"),
        Rule(name: "build", ecosystem: "Gradle", markers: ["build.gradle", "build.gradle.kts"], regenerate: "gradle build"),
        Rule(name: ".gradle", ecosystem: "Gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], regenerate: "gradle build"),
        Rule(name: ".build", ecosystem: "Swift", markers: ["Package.swift"], regenerate: "swift build"),
        Rule(name: "DerivedData", ecosystem: "Xcode", markers: ["*.xcodeproj", "*.xcworkspace"], regenerate: "the next Xcode build"),
        Rule(name: "Pods", ecosystem: "CocoaPods", markers: ["Podfile"], regenerate: "pod install"),
        Rule(name: ".dart_tool", ecosystem: "Flutter", markers: ["pubspec.yaml"], regenerate: "flutter pub get"),
        Rule(name: "build", ecosystem: "Flutter", markers: ["pubspec.yaml"], regenerate: "flutter build"),
        Rule(name: "vendor", ecosystem: "PHP", markers: ["composer.json"], regenerate: "composer install"),
        Rule(name: "_build", ecosystem: "Elixir", markers: ["mix.exs"], regenerate: "mix compile"),
        Rule(name: "deps", ecosystem: "Elixir", markers: ["mix.exs"], regenerate: "mix deps.get"),
        Rule(name: ".zig-cache", ecosystem: "Zig", markers: ["build.zig"], regenerate: "zig build"),
        Rule(name: "zig-out", ecosystem: "Zig", markers: ["build.zig"], regenerate: "zig build"),
        Rule(name: ".stack-work", ecosystem: "Haskell", markers: ["stack.yaml"], regenerate: "stack build"),
        Rule(name: "dist-newstyle", ecosystem: "Haskell", markers: ["cabal.project", "*.cabal"], regenerate: "cabal build"),
        Rule(name: "elm-stuff", ecosystem: "Elm", markers: ["elm.json"], regenerate: "elm make"),
        Rule(name: "obj", ecosystem: ".NET", markers: ["*.csproj", "*.fsproj", "*.sln"], regenerate: "dotnet build"),
        Rule(name: "bin", ecosystem: ".NET", markers: ["*.csproj", "*.fsproj"], regenerate: "dotnet build"),
        Rule(name: ".terraform", ecosystem: "Terraform", inside: ["providers"], regenerate: "terraform init"),
    ]

    /// Names Sweepside never walks into, even when they aren't cleanable here
    /// (a node_modules without package.json is still not where projects live).
    static let neverDescend: Set<String> = ["node_modules", ".git", ".hg", ".svn", "Pods", "DerivedData"]

    /// Bundles that look like folders but are documents or apps.
    static let packageExtensions: Set<String> = ["app", "photoslibrary", "musiclibrary", "tvlibrary", "fcpbundle",
                                                 "logicx", "band", "framework", "bundle", "xcarchive", "imovielibrary",
                                                 "photoboothlibrary", "aplibrary", "sparsebundle"]

    /// Home folders that hold media or apps, not code.
    static let skippedHomeFolders = ["Library", ".Trash", "Applications", "Pictures", "Music", "Movies"]

    /// Shared caches outside projects. Never selected by default: they make builds and
    /// installs faster, and cleaning them is a deliberate choice.
    struct Cache {
        let name: String
        let path: String   // relative to home
        let ecosystem: String
        let regenerate: String
    }

    static let caches: [Cache] = [
        Cache(name: "Xcode DerivedData", path: "Library/Developer/Xcode/DerivedData", ecosystem: "Xcode", regenerate: "Rebuilt on the next build"),
        Cache(name: "iOS DeviceSupport", path: "Library/Developer/Xcode/iOS DeviceSupport", ecosystem: "Xcode", regenerate: "Copied again when you connect a device"),
        Cache(name: "Simulator caches", path: "Library/Developer/CoreSimulator/Caches", ecosystem: "Xcode", regenerate: "Rebuilt by the Simulator"),
        Cache(name: "Homebrew downloads", path: "Library/Caches/Homebrew", ecosystem: "Homebrew", regenerate: "Downloaded again when needed"),
        Cache(name: "npm cache", path: ".npm/_cacache", ecosystem: "Node", regenerate: "Downloaded again by npm"),
        Cache(name: "pnpm store", path: "Library/pnpm/store", ecosystem: "Node", regenerate: "Downloaded again by pnpm"),
        Cache(name: "Yarn cache", path: "Library/Caches/Yarn", ecosystem: "Node", regenerate: "Downloaded again by Yarn"),
        Cache(name: "Bun cache", path: ".bun/install/cache", ecosystem: "Node", regenerate: "Downloaded again by Bun"),
        Cache(name: "node-gyp headers", path: "Library/Caches/node-gyp", ecosystem: "Node", regenerate: "Downloaded again by node-gyp"),
        Cache(name: "pip cache", path: "Library/Caches/pip", ecosystem: "Python", regenerate: "Downloaded again by pip"),
        Cache(name: "uv cache", path: ".cache/uv", ecosystem: "Python", regenerate: "Downloaded again by uv"),
        Cache(name: "Poetry cache", path: "Library/Caches/pypoetry", ecosystem: "Python", regenerate: "Downloaded again by Poetry"),
        Cache(name: "Hugging Face downloads", path: ".cache/huggingface", ecosystem: "AI models", regenerate: "Models download again, which can be slow"),
        Cache(name: "Cargo registry", path: ".cargo/registry", ecosystem: "Rust", regenerate: "Downloaded again by Cargo"),
        Cache(name: "Go modules", path: "go/pkg/mod", ecosystem: "Go", regenerate: "Downloaded again by go"),
        Cache(name: "Go build cache", path: "Library/Caches/go-build", ecosystem: "Go", regenerate: "Rebuilt by go"),
        Cache(name: "Gradle caches", path: ".gradle/caches", ecosystem: "Gradle", regenerate: "Downloaded again by Gradle"),
        Cache(name: "Maven repository", path: ".m2/repository", ecosystem: "Maven", regenerate: "Downloaded again by Maven"),
        Cache(name: "CocoaPods cache", path: "Library/Caches/CocoaPods", ecosystem: "CocoaPods", regenerate: "Downloaded again by pod install"),
        Cache(name: "Playwright browsers", path: "Library/Caches/ms-playwright", ecosystem: "Testing", regenerate: "npx playwright install"),
        Cache(name: "Puppeteer browsers", path: ".cache/puppeteer", ecosystem: "Testing", regenerate: "Downloaded again by Puppeteer"),
        Cache(name: "Electron downloads", path: "Library/Caches/electron", ecosystem: "Node", regenerate: "Downloaded again by Electron"),
    ]
}
