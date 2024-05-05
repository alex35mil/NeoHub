import AppKit
import SwiftUI
import KeyboardShortcuts
import NeoHubLib

final class EditorStore: ObservableObject {
    @Published private var editors: [EditorID:Editor]

    let switcherWindow: SwitcherWindowRef
    let activationManager: ActivationManager

    private var restartPoller: Timer?

    init(activationManager: ActivationManager, switcherWindow: SwitcherWindowRef) {
        self.editors = [:]
        self.switcherWindow = switcherWindow
        self.activationManager = activationManager

        KeyboardShortcuts.onKeyUp(for: .restartEditor) { [self] in
            self.restartActiveEditor()
        }
    }

    public enum SortTarget {
        case menubar
        case switcher
        case lastActiveEditor
    }

    public func getEditors() -> [Editor] {
        self.editors.values.map { $0 }
    }

    public func getEditors(sortedFor sortTarget: SortTarget) -> [Editor] {
        let editors = self.getEditors()

        switch sortTarget {
            case .menubar:
                return editors.sorted { $0.name > $1.name }
            case .lastActiveEditor:
                if let lastActiveEditor = editors.max(by: { $0.lastAcceessTime < $1.lastAcceessTime }) {
                    return [lastActiveEditor]
                } else {
                    return []
                }
            case .switcher:
                var sorted = editors.sorted { $0.lastAcceessTime > $1.lastAcceessTime }

                if
                    sorted.count > 1,
                    let firstEditor = sorted.first,
                    case .neovide(let prevEditor) = activationManager.activationTarget,
                    firstEditor.processIdentifier == prevEditor.processIdentifier
                {
                    // Swap the first editor with the second one
                    // so it would require just Enter to switch between two editors
                    sorted.swapAt(0, 1)
                }

                return sorted
        }
    }

    func runEditor(request: RunRequest) {
        log.info("Running an editor...")

        let editorID = switch request.path {
        case nil, "":
            EditorID(request.wd)
        case .some(let path):
            EditorID(
                URL(
                    fileURLWithPath: path,
                    relativeTo: request.wd
                )
            )
        }

        log.info("Editor ID: \(editorID)")

        let editorName = switch request.name {
        case nil, "":
            editorID.lastPathComponent
        case .some(let name):
            name
        }

        log.info("Editor name: \(editorName)")

        switch editors[editorID] {
            case .some(let editor):
                log.info("Editor at \(editorID) is already in the hub. Activating it.")
                editor.activate()
            case .none:
                log.info("No editors at \(editorID) found. Launching a new one.")

                do {
                    log.info("Running editor at \(request.wd.path)")

                    let process = Process()

                    process.executableURL = request.bin

                    let nofork = "--no-fork"

                    process.arguments = request.opts

                    if !process.arguments!.contains(nofork) {
                        process.arguments!.append(nofork)
                    }

                    if let path = request.path {
                        process.arguments!.append(path)
                    }

                    process.currentDirectoryURL = request.wd
                    process.environment = request.env

                    process.terminationHandler = { process in
                        DispatchQueue.main.async {
                            log.info("Removing editor from the hub")
                            self.editors.removeValue(forKey: editorID)
                        }
                    }

                    let currentApp = NSWorkspace.shared.frontmostApplication

                    try process.run()

                    activationManager.setActivationTarget(
                        currentApp: currentApp,
                        switcherWindow: self.switcherWindow,
                        editors: self.getEditors()
                    )

                    if process.isRunning {
                        log.info("Editor is launched at \(editorID) with PID \(process.processIdentifier)")

                        DispatchQueue.main.async {
                            self.editors[editorID] = Editor(
                                id: editorID,
                                name: editorName,
                                process: process,
                                request: request
                            )
                        }
                    } else {
                        throw ReportableError(
                            "Editor process is not running",
                            code: Int(process.terminationStatus),
                            meta: [
                                "EditorID": editorID,
                                "EditorPID": process.processIdentifier,
                                "EditorTerminationStatus": process.terminationStatus,
                                "EditorWorkingDirectory": request.wd,
                                "EditorBinary": request.bin,
                                "EditorPathArgument": request.path ?? "-",
                                "EditorOptions": request.opts,
                            ]
                        )
                    }
                } catch {
                    let error = ReportableError("Failed to run editor process", error: error)
                    log.error("\(error)")
                    FailedToRunEditorProcessNotification(error: error).send()
                }
        }
    }

    func restartActiveEditor() {
        log.info("Restarting the active editor...")

        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            log.info("There is no active app. Canceling restart.")
            return
        }

        guard let editor = self.editors.first(where: { id, editor in editor.processIdentifier == activeApp.processIdentifier })?.value else {
            log.info("The active app is not an editor. Canceling restart.")
            return
        }

        log.info("Quiting the editor")

        editor.quit()

        // Termination handler should remove the editor from the store,
        // so we should wait for that, then re-run the editor
        log.info("Starting polling until the old editor is removed from the store")

        let timeout = TimeInterval(5)
        let startTime = Date()

        self.restartPoller = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { [weak self] _ in
            log.trace("Starting the iteration...")

            guard let self = self else { return }

            log.trace("We have self. Checking the store.")
            if self.editors[editor.id] == nil {
                log.info("The old editor removed from the store. Starting the new instance.")
                self.invalidateRestartPoller()
                self.runEditor(request: editor.request)
            } else if -startTime.timeIntervalSinceNow > timeout {
                log.error("The editor wasn't removed from the store within the timeout. Canceling the restart.")
                self.invalidateRestartPoller()

                let alert = NSAlert()

                alert.messageText = "Failed to restart the editor"
                alert.informativeText = "Please, report the issue on GitHub."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Report")
                alert.addButton(withTitle: "Dismiss")

                switch alert.runModal() {
                    case .alertFirstButtonReturn:
                        let error = ReportableError("Failed to restart the editor")
                        BugReporter.report(error)
                    default: ()
                }

                return
            }
        }
    }


    func quitAllEditors() async {
        await withTaskGroup(of: Void.self) { group in
            for (_, editor) in self.editors {
                group.addTask { editor.quit() }
            }
        }
    }

    private func invalidateRestartPoller() {
        log.debug("Stopping the restart poller")
        self.restartPoller?.invalidate()
    }

    deinit {
        self.invalidateRestartPoller()
    }
}

struct EditorID {
    private let loc: URL

    init(_ loc: URL) {
        self.loc = loc
    }

    public var path: String {
        loc.path(percentEncoded: false)
    }

    public var lastPathComponent: String {
        loc.lastPathComponent
    }
}

extension EditorID: Identifiable {
    var id: URL { self.loc }
}

extension EditorID: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(loc)
    }
}

extension EditorID: Equatable {
    static func == (lhs: EditorID, rhs: EditorID) -> Bool {
        return lhs.loc == rhs.loc
    }
}

extension EditorID: CustomStringConvertible {
    var description: String { self.path }
}

final class Editor: Identifiable {
    let id: EditorID
    let name: String

    private let process: Process
    private(set) var lastAcceessTime: Date
    private(set) var request: RunRequest

    init(id: EditorID, name: String, process: Process, request: RunRequest) {
        self.id = id
        self.name = name
        self.process = process
        self.lastAcceessTime = Date()
        self.request = request
    }

    var displayPath: String {
        let fullPath = self.id.path
        let pattern = "^/Users/[^/]+/"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            log.warning("Invalid display path regular expression.")
            return fullPath
        }

        let range = NSRange(fullPath.startIndex..., in: fullPath)
        let result = regex.stringByReplacingMatches(
            in: fullPath,
            options: [],
            range: range,
            withTemplate: "~/"
        )

        return result
    }

    var processIdentifier: Int32 {
        self.process.processIdentifier
    }

    private func runningEditor() -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: process.processIdentifier)!
    }

    func activate() {
        guard let app = self.runningEditor() else {
            let error = ReportableError("Failed to get Neovide NSRunningApplication instance")
            log.error("\(error)")
            FailedToGetRunningEditorAppNotification(error: error).send()
            return
        }

        DispatchQueue.main.async {
            // We have to activate NeoHub first so macOS would allow to activate Neovide
            NSApp.activate(ignoringOtherApps: true)

            let activated = app.activate()
            if !activated {
                let error = ReportableError("Failed to activate Neovide instance")
                log.error("\(error)")
                FailedToActivateEditorAppNotification(error: error).send()
            } else {
                self.lastAcceessTime = Date()
            }
        }
    }

    func quit() {
        log.info("Terminating editor...")
        process.terminate()
    }
}
