import Foundation
import SwiftUI

final class WindowCounter {
    private var counter: UInt8

    init() {
        self.counter = 0
    }

    var now: UInt8 { self.counter }

    func inc() {
        self.counter += 1
    }

    func dec() {
        if self.counter > 0 {
            self.counter -= 1
        }
    }
}

final class RegularWindow<Content: View> {
    var window: NSWindow?
    var observer: NSObjectProtocol?

    let title: String?
    let width: CGFloat
    let content: () -> Content
    let windowCounter: WindowCounter

    init(title: String? = nil, width: CGFloat, content: @escaping () -> Content, windowCounter: WindowCounter) {
        self.window = nil
        self.title = title
        self.width = width
        self.content = content
        self.windowCounter = windowCounter
    }

    func open() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: self.width, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        if let title = self.title {
            window.title = title
        }

        window.contentView = NSHostingView(rootView: self.content())

        window.isReleasedWhenClosed = false

        // We want Settigs and other non-Switcher windows to be Cmd+Tab'able, so temporarily making app regular
        NSApp.setActivationPolicy(.regular)

        window.styleMask.remove(.resizable)

        // Ensuring that the window gets activated
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // When window gets closed, reverting the app to the accessory type
        self.observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { [weak self] notification in
            self?.onClose(notification)
        }

        self.window = window

        self.windowCounter.inc()
    }

    func isSameWindow(_ window: NSWindow) -> Bool {
        self.window == window
    }

    func close() {
        if let window = self.window {
            window.close()
        }
    }

    private func onClose(_ notification: Notification) {
        if windowCounter.now == 1 {
            NSApp.setActivationPolicy(.accessory)
        }
        windowCounter.dec()
        self.cleanUp()
    }

    private func cleanUp() {
        self.window = nil
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    deinit { self.cleanUp() }
}

final class RegularWindowRef<Content: View> {
    private var window: RegularWindow<Content>?

    func set(_ window: RegularWindow<Content>) {
        self.window = window
    }

    func isSameWindow(_ window: NSWindow) -> Bool {
        if let win = self.window {
            return win.isSameWindow(window)
        } else {
            return false
        }
    }

    func close() {
        if let window = self.window {
            window.close()
        }
    }
}
