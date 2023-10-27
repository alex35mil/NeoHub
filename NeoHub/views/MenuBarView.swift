import SwiftUI

struct MenuBarIcon: View {
    private let icon: NSImage

    init() {
        let icon: NSImage = NSImage(named: "MenuBarIcon")!

        let ratio = icon.size.height / icon.size.width
        icon.size.height = 15
        icon.size.width = 15 / ratio

        self.icon = icon
    }

    var body: some View {
        Image(nsImage: icon)
    }
}


struct MenuBarView: View {
    @ObservedObject var cli: CLI
    @ObservedObject var editorStore: EditorStore

    let settingsWindow: RegularWindow<SettingsView>
    let aboutWindow: RegularWindow<AboutView>

    var body: some View {
        let editors = editorStore.getEditors()

        Group {
            if editors.count == 0 {
                Text("No editors").font(.headline)
            } else {
                Text("Editors").font(.headline)
                ForEach(editors) { editor in
                    Button(editor.name) { editor.activate() }
                }
            }
            switch cli.status {
                case .error(reason:.notInstalled):
                    Divider()
                    Button("⚠️ Install CLI") {
                        cli.perform(.install) { result, status in
                            Self.showCLIInstallationAlert(with: (result, status))
                        }
                    }
                case .error(reason: .versionMismatch):
                    Divider()
                    Button("⚠️ Update CLI") {
                        cli.perform(.install) { result, status in
                            Self.showCLIInstallationAlert(with: (result, status))
                        }
                    }
                case .error(reason: .unexpectedError(_)):
                    Divider()
                    Button("❗ CLI Error") { settingsWindow.open() }
                case .ok:
                    EmptyView()
            }
            Divider()
            Button("Settings") { settingsWindow.open() }
            Button("About") { aboutWindow.open() }
            Divider()
            Button("Quit All Editors") { Task { await editorStore.quitAllEditors() } }.disabled(editors.count == 0)
            Button("Quit NeoHub") { NSApplication.shared.terminate(nil) }
        }
    }

    static func showCLIInstallationAlert(with response: (result: Result<Void, CLIInstallationError>, status: CLIStatus)) {
        switch response.result {
            case .success(()):
                let alert = NSAlert()

                alert.messageText = "Boom!"
                alert.informativeText = "The CLI is ready to roll 🚀"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")

                alert.runModal()

            case .failure(.userCanceledOperation): ()

            case .failure(.failedToCreateAppleScript):
                let alert = NSAlert()

                alert.messageText = "Oh no!"
                alert.informativeText = "There was an issue during installation."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Report")
                alert.addButton(withTitle: "Dismiss")

                switch alert.runModal() {
                    case .alertFirstButtonReturn:
                        let error = ReportableError("Failed to build installation Apple Script")
                        BugReporter.report(error)
                    default: ()
                }

            case .failure(.failedToExecuteAppleScript(error: let error)):
                let alert = NSAlert()

                alert.messageText = "Oh no!"
                alert.informativeText = "There was an issue during installation."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Report")
                alert.addButton(withTitle: "Dismiss")

                switch alert.runModal() {
                    case .alertFirstButtonReturn:
                        let error = ReportableError(
                            "Failed to execute installation Apple Script",
                            meta: error as? [String: Any]
                        )
                        BugReporter.report(error)
                    default: ()
                }
        }
    }
}
