import AppKit

enum ActivationTarget {
    case neohub(NonSwitcherWindow)
    case neovide(Editor)
    case other(NSRunningApplication)
}

struct NonSwitcherWindow {
    let window: NSWindow

    init?(_ window: NSWindow, switcherWindow: SwitcherWindowRef) {
        guard !switcherWindow.isSameWindow(window) else { return nil }
        self.window = window
    }

    func activate() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class ActivationManager {
    private(set) var activationTarget: ActivationTarget?

    public func setActivationTarget(
        currentApp: NSRunningApplication?,
        switcherWindow: SwitcherWindowRef,
        editors: [Editor]
    ) {
        let nextActivationTarget = currentApp.flatMap { app in
            if app.bundleIdentifier == APP_BUNDLE_ID {
                if
                    let currentWindow = NSApplication.shared.mainWindow,
                    let nonSwitcherWindow = NonSwitcherWindow(currentWindow, switcherWindow: switcherWindow)
                {
                    return ActivationTarget.neohub(nonSwitcherWindow)
                } else {
                    return nil
                }
            }

            if let editor = editors.first(where: { editor in editor.processIdentifier == app.processIdentifier }) {
                return .neovide(editor)
            }

            return .other(app)
        }

        self.activationTarget = nextActivationTarget
    }

    public func activateTarget() {
        switch self.activationTarget {
            case nil: ()
            case .neohub(let window): window.activate()
            case .neovide(let editor): editor.activate()
            case .other(let app): app.activate()
        }
    }
}
