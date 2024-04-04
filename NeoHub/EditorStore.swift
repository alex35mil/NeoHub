import AppKit
import SwiftUI
import KeyboardShortcuts
import NeoHubLib

final class EditorStore: ObservableObject {
    @Published private var editors: [EditorID:Editor]

    let switcherWindow: SwitcherWindowRef
    let activationManager: ActivationManager

    init(activationManager: ActivationManager, switcherWindow: SwitcherWindowRef) {
        self.editors = [:]
        self.switcherWindow = switcherWindow
        self.activationManager = activationManager
    }

    public enum SortTarget {
        case menubar
        case switcher
    }

    public func getEditors() -> [Editor] {
        self.editors.values.map { $0 }
    }

    public func getEditors(sortedFor sortTarget: SortTarget) -> [Editor] {
        let editors = self.getEditors()

        switch sortTarget {
            case .menubar:
                return editors.sorted { $0.name > $1.name }
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

    func runEditor(req: RunRequest) {
        log.info("Running an editor...")

        let editorID = switch req.path {
        case nil, "":
            EditorID(req.wd)
        case .some(let path):
            EditorID(
                URL(
                    fileURLWithPath: path,
                    relativeTo: req.wd
                )
            )
        }

        log.info("Editor ID: \(editorID)")

        let editorName = switch req.name {
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
                    log.info("Running editor at \(req.wd.path)")

                    let process = Process()

                    process.executableURL = req.bin

                    let nofork = "--no-fork"

                    process.arguments = req.opts

                    if !process.arguments!.contains(nofork) {
                        process.arguments!.append(nofork)
                    }

                    if let path = req.path {
                        process.arguments!.append(path)
                    }

                    process.currentDirectoryURL = req.wd
                    process.environment = req.env

                    process.terminationHandler = { process in
                        DispatchQueue.main.async {
                            log.info("Removing editor from the hub")
                            self.editors[editorID] = nil
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
                                process: process
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
                                "EditorWorkingDirectory": req.wd,
                                "EditorBinary": req.bin,
                                "EditorPathArgument": req.path ?? "-",
                                "EditorOptions": req.opts,
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

    func quitAllEditors() async {
        await withTaskGroup(of: Void.self) { group in
            for (_, editor) in self.editors {
                group.addTask { editor.quit() }
            }
        }
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

    init(id: EditorID, name: String, process: Process) {
        self.id = id
        self.name = name
        self.process = process
        self.lastAcceessTime = Date()
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
