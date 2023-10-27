import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

struct InstallationView: View {
    static let defaultWidth: CGFloat = 400

    enum Status {
        case ok
        case notInstalled(progress: Progress)
        case versionMismatch(progress: Progress)
        case unexpectedError(Error)

        init(from cliStatus: CLIStatus) {
            switch cliStatus {
                case .ok:
                    self = .ok
                case .error(reason: .notInstalled):
                    self = .notInstalled(progress: .zero)
                case .error(reason: .versionMismatch):
                    self = .versionMismatch(progress: .zero)
                case .error(reason: .unexpectedError(let error)):
                    self = .unexpectedError(error)
            }
        }
    }

    enum Progress: Equatable {
        case zero
        case busy
        case error(CLIInstallationError)

        static func == (lhs: InstallationView.Progress, rhs: InstallationView.Progress) -> Bool {
            switch (lhs, rhs) {
                case (.zero, .zero): true
                case (.busy, .busy): true
                case (.error(_), .error(_)): true
                default: false
            }
        }
    }

    let cli: CLI
    let installationWindow: RegularWindowRef<Self>

    @State var status: Status

    init(cli: CLI, installationWindow: RegularWindowRef<Self>) {
        self.cli = cli
        self.installationWindow = installationWindow
        self.status = Status(from: cli.status)
    }

    var body: some View {
        VStack(spacing: 20) {
            switch self.status {
                case .ok:
                    Text("CLI is installed").font(.title)
                case .notInstalled(_):
                    Text("Install CLI").font(.title)
                case .versionMismatch(_):
                    Text("Update CLI").font(.title)
                case .unexpectedError(_):
                    Text("Unexpected Error").font(.title)
            }
            VStack(spacing: 20) {
                switch self.status {
                    case .ok:
                        VStack(spacing: 20) {
                            Image(systemName: "gear.badge.checkmark")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.green, Color.gray)
                                .font(.system(size: 32))
                            Text("Open your terminal and try to run `neohub` command")
                            Button("Close") { installationWindow.close() }
                        }
                    case .notInstalled(let progress):
                        VStack(spacing: 10) {
                            Image(systemName: "gear")
                                .foregroundStyle(Color.gray)
                                .font(.system(size: 32))
                            Text("In order to manage Neovide instances through NeoHub, you will need the NeoHub CLI.")
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("After successful installation, the `neohub` command should become available in your shell. Use it instead of `neovide` to launch editors.")
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)

                            switch progress {
                                case .zero:
                                    EmptyView()
                                case .busy:
                                    Spinner()
                                case .error(.userCanceledOperation):
                                    EmptyView()
                                case .error(.failedToCreateAppleScript):
                                    VStack {
                                        Text("Something went wrong").foregroundColor(.red)
                                        Button("Report") {
                                            let error = ReportableError("Failed to build installation Apple Script")
                                            BugReporter.report(error)
                                        }
                                    }
                                case .error(.failedToExecuteAppleScript(error: let error)):
                                    VStack {
                                        Text("Something went wrong").foregroundColor(.red)
                                        Button("Report") {
                                            let error = ReportableError(
                                                "Failed to execute installation Apple Script",
                                                meta: error as? [String: Any]
                                            )
                                            BugReporter.report(error)
                                        }
                                    }
                            }
                        }
                        VStack(spacing: 10) {
                            Button("Install") {
                                self.status = .notInstalled(progress: .busy)
                                cli.perform(.install) { result, _ in
                                    switch result {
                                        case .success(()):
                                            self.status = .ok
                                        case .failure(let error):
                                            self.status = .notInstalled(progress: .error(error))
                                    }
                                }
                            }
                            .disabled(progress == .busy)
                            ButtonNote()
                        }
                    case .versionMismatch(let progress):
                        VStack(spacing: 10) {
                            Image(systemName: "gear.badge")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.yellow, Color.gray)
                                .font(.system(size: 32))
                            Text("NeoHub CLI needs to be updated.")

                            switch progress {
                                case .zero:
                                    EmptyView()
                                case .busy:
                                    Spinner()
                                case .error(.userCanceledOperation):
                                    EmptyView()
                                case .error(.failedToCreateAppleScript):
                                    VStack {
                                        Text("Something went wrong").foregroundColor(.red)
                                        Button("Report") {
                                            let error = ReportableError("Failed to build installation Apple Script")
                                            BugReporter.report(error)
                                        }
                                    }
                                case .error(.failedToExecuteAppleScript(error: let error)):
                                    VStack {
                                        Text("Something went wrong").foregroundColor(.red)
                                        Button("Report") {
                                            let error = ReportableError(
                                                "Failed to execute installation Apple Script",
                                                meta: error as? [String: Any]
                                            )
                                            BugReporter.report(error)
                                        }
                                    }
                            }
                        }
                        VStack(spacing: 10) {
                            Button("Update") {
                                self.status = .versionMismatch(progress: .busy)
                                cli.perform(.install) { result, _ in
                                    switch result {
                                        case .success(()):
                                            self.status = .ok
                                        case .failure(let error):
                                            self.status = .versionMismatch(progress: .error(error))
                                    }
                                }
                            }
                            .disabled(progress == .busy)
                            ButtonNote()
                        }
                    case .unexpectedError(let error):
                        VStack(spacing: 20) {
                            VStack(spacing: 10) {
                                Image(systemName: "gear.badge.xmark")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.red, Color.gray)
                                    .font(.system(size: 32))
                                Text("Something went terribly wrong.")
                                Text("Please create an issue in the GitHub repo.")
                            }
                            Button("Create an Issue") {
                                BugReporter.report(ReportableError("CLI failed to report a status", error: error))
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    NSApplication.shared.terminate(nil)
                                }
                            }
                        }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .settingsGroup()
        }
        .padding(.horizontal, 20)
        .padding(
            .vertical,
            {
                // FIXME: Multiline Text produces odd paddings around window content
                switch self.status {
                    case
                            .unexpectedError(_):
                        return 50
                    case
                            .versionMismatch(progress: .busy):
                        return 40
                    case
                            .versionMismatch(progress: .zero),
                            .versionMismatch(progress: .error(_)):
                        return 30
                    case
                            .ok,
                            .notInstalled(progress: .error(.failedToExecuteAppleScript(_))):
                        return 20
                    case
                            .notInstalled(_):
                        return 10
                }
            }()
        )
        .frame(maxWidth: .infinity)
    }

    struct Spinner: View {
        var body: some View {
            ProgressView("Working...").progressViewStyle(CircularProgressViewStyle())
        }
    }

    struct ButtonNote: View {
        var body: some View {
            Text(
                """
                In the dialog box that appears,
                you will need to enter an administrator password
                """
            )
            .font(.caption2)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
