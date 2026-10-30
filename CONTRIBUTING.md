# Contributing

Thanks for helping. Sweepside is small on purpose: one SwiftUI app, no dependencies, no Xcode project.

## Build and run

```sh
./build.sh              # build, install to ~/Applications and launch
./build.sh --no-install # build into build/ only
```

You need the Xcode command line tools (Swift 6) and macOS 14 or later.

## Adding a build folder or cache

Most contributions will be this, in `Sources/Rules.swift`:

- **A project folder**: add a `Rule` to `Rules.projects` with the folder name and a **marker** that proves
  it belongs to that toolchain: a file next to it (`markers: ["Cargo.toml"]`, or `"*.csproj"` by extension)
  or a file inside it (`inside: ["pyvenv.cfg"]`). Only add folders the toolchain fully regenerates.
  Never add a rule without a marker; that's what keeps lookalike folders safe.
- **A shared cache**: add a `Cache` to `Rules.caches` with its path relative to the home folder.

Check it against a real project:

```sh
build/Sweepside.app/Contents/MacOS/Sweepside --in ~/path/to/project
```

## Design changes

The panel is built from the tokens in `Sources/Design.swift` (shared with Portside). Render every state
in light and dark with demo data and look at them before opening a PR:

```sh
build/Sweepside.app/Contents/MacOS/Sweepside --snapshot /tmp/sweepside-shots
build/Sweepside.app/Contents/MacOS/Sweepside --demo-gif docs/demo.gif
```

## Safety rules

Sweepside deletes things, so these stay true: it only offers folders a tool regenerates, checked against
a marker; it moves to the Trash by default; it re-checks every folder right before touching it (still a
real folder, still inside a scan folder); and it never follows links.
