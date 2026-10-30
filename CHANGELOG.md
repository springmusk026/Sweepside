# Changelog

## 1.0 (2026-10-30)

First release.

- Finds build folders in your projects: node_modules, .venv, target, .next, Pods, DerivedData, .gradle and 30 more, each checked against its project file so lookalike folders are left alone
- Groups them by project and suggests the ones you haven't touched in 30 days (configurable)
- Shared developer caches: Xcode DerivedData and DeviceSupport, Homebrew, npm, pnpm, pip, uv, Cargo, Go, Gradle, Maven, Playwright and more
- Honest sizes: files hard-linked from a shared store (pnpm, uv) aren't counted as space you'll get back
- Moves to the Trash by default, with Undo, and "Free it now" to delete just those items from the Trash
- Disk bar showing free space now and after cleaning
- `sweepside` command line: list, `--caches`, `clean`, `--json`
- Universal app (Apple silicon and Intel)
