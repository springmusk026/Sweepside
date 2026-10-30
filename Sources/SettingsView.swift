import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var store: SweepStore
    @AppStorage("sizeInMenuBar") private var sizeInMenuBar = true
    @State private var roots = Prefs.roots
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var copied = false

    private var linkCommand: String {
        let binary = Bundle.main.executableURL?.path ?? "/Applications/Sweepside.app/Contents/MacOS/Sweepside"
        let bin = FileManager.default.isWritableFile(atPath: "/opt/homebrew/bin") ? "/opt/homebrew/bin" : "/usr/local/bin"
        return "ln -sf '\(binary)' \(bin)/sweepside"
    }

    var body: some View {
        Form {
            Section {
                ForEach(roots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(abbreviate(root))
                        Spacer()
                        Button("Remove") { setRoots(roots.filter { $0 != root }) }
                            .disabled(roots.count == 1)
                    }
                }
                Button("Add Folder…", action: addFolder)
            } header: {
                Text("Scan folders")
            } footer: {
                Text("Sweepside never looks inside Library, Pictures, Music, Movies or the Trash, and never follows links.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Suggest projects untouched for", selection: $store.staleDays) {
                    ForEach([14, 30, 60, 90, 180], id: \.self) { Text("\($0) days").tag($0) }
                }
                Toggle(isOn: $store.permanentDelete) {
                    Text("Delete permanently instead of moving to the Trash")
                    Text("Frees the space right away. There's no Undo.")
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show space in idle projects in the menu bar", isOn: $sizeInMenuBar)
            }

            Section("Command line") {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Add `sweepside` to your PATH to scan and clean from Terminal:")
                    HStack {
                        Text(linkCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button(copied ? "Copied" : "Copy") {
                            store.copy(linkCommand)
                            copied = true
                            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                        }
                    }
                    Text("Then try `sweepside`, `sweepside --caches` or `sweepside clean`.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Version", value: CLI.version)
                LabeledContent("Source") {
                    Link("github.com/springmusk026/Sweepside", destination: URL(string: "https://github.com/springmusk026/Sweepside")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setRoots(_ new: [String]) {
        roots = new
        Prefs.roots = new
        store.scan()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map(\.path).filter { new in !roots.contains { new.hasPrefix($0 + "/") || new == $0 } }
        setRoots(roots + added)
    }
}
