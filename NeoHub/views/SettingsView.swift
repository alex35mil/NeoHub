import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

struct SettingsView: View {
    static let defaultWidth: CGFloat = 400

    @ObservedObject var cli: CLI

    @State var runningCLIAction: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image("EditorIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.gray)
                Text("NeoHub").font(.title)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("Launch at Login")
                    Spacer()
                    LaunchAtLogin.Toggle("").toggleStyle(SwitchToggleStyle())
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider().padding(.horizontal)

                HStack {
                    Text("Toggle Editor Selector")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .toggleSwitcher)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                HStack {
                    Text("Toggle Last Active Editor")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .toggleLastActiveEditor)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider().padding(.horizontal)

                HStack {
                    Text("Restart Active Editor")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .restartEditor)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .settingsGroup()
            Text("CLI").font(.title)
            VStack(spacing: 20) {
                switch cli.status {
                    case .ok:
                        VStack(spacing: 10) {
                            if self.runningCLIAction {
                                InstallationView.Spinner()
                            } else {
                                Image(systemName: "gear.badge.checkmark")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.green, Color.gray)
                                    .font(.system(size: 32))
                                Text("Installed")
                            }
                        }
                        Divider()
                        VStack(spacing: 10) {
                            Button("Uninstall") {
                                self.runningCLIAction = true
                                cli.perform(.uninstall) { _, _ in
                                    self.runningCLIAction = false
                                }
                            }
                            .buttonStyle(LinkButtonStyle())
                            .disabled(self.runningCLIAction)
                            .focusable()
                            InstallationView.ButtonNote()
                        }
                    case .error(reason: .notInstalled):
                        VStack(spacing: 10) {
                            if self.runningCLIAction {
                                InstallationView.Spinner()
                            } else {
                                Image(systemName: "gear.badge.xmark")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.red, Color.gray)
                                    .font(.system(size: 32))
                                Text("Not Installed")
                            }
                        }
                        VStack(spacing: 10) {
                            Button("Install") {
                                self.runningCLIAction = true
                                cli.perform(.install) { _, _ in
                                    self.runningCLIAction = false
                                }
                            }
                            .disabled(self.runningCLIAction)
                            .focusable()
                            InstallationView.ButtonNote()
                        }
                    case .error(reason: .versionMismatch):
                        VStack(spacing: 10) {
                            if self.runningCLIAction {
                                InstallationView.Spinner()
                            } else {
                                Image(systemName: "gear.badge")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.yellow, Color.gray)
                                    .font(.system(size: 32))
                                Text("Needs Update")
                            }
                        }
                        VStack(spacing: 20) {
                            Button("Update") {
                                self.runningCLIAction = true
                                cli.perform(.install) { _, _ in
                                    self.runningCLIAction = false
                                }
                            }
                            .disabled(self.runningCLIAction)
                            .focusable()
                            Divider()
                            Button("Uninstall") {
                                self.runningCLIAction = true
                                cli.perform(.uninstall) { _, _ in
                                    self.runningCLIAction = false
                                }
                            }
                            .buttonStyle(LinkButtonStyle())
                            .disabled(self.runningCLIAction)
                            .focusable()
                            InstallationView.ButtonNote()
                        }
                    case .error(reason: .unexpectedError(let error)):
                        VStack(spacing: 10) {
                            Image(systemName: "gear.badge.xmark")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.red, Color.gray)
                                .font(.system(size: 32))
                            Text("Unexpected Error")
                        }
                        Button("Create an Issue on GitHub") {
                            BugReporter.report(ReportableError("CLI failed to report a status", error: error))
                        }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .settingsGroup()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

}
