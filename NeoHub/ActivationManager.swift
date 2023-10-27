import AppKit

final class ActivationManager {
    private(set) var priorApp: NSRunningApplication?

    public func setPriorApp(_ app: NSRunningApplication) {
        self.priorApp = app
    }

    public func activatePriorApp() {
        if let app = self.priorApp {
            app.activate()
        }
    }
}
