import AppKit
import SwiftUI
import KeyboardShortcuts

let APP_NAME = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
let APP_VERSION = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
let APP_BUILD = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as! String
let APP_BUNDLE_ID = Bundle.main.bundleIdentifier!

extension KeyboardShortcuts.Name {
    static let toggleSwitcher = Self(
        "toggleSwitcher",
        default: .init(.n, modifiers: [.command, .control])
    )

    static let restartEditor = Self("restartEditor")
}

@main
struct NeoHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var app

    var body: some Scene {
        MenuBarExtra(
            content: {
                MenuBarView(
                    cli: app.cli,
                    editorStore: app.editorStore,
                    settingsWindow: app.settingsWindow,
                    aboutWindow: app.aboutWindow
                )
            },
            label: { MenuBarIcon() }
        )
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let cli: CLI
    let editorStore: EditorStore
    let server: SocketServer
    let switcherWindow: SwitcherWindow
    let installationWindow: RegularWindow<InstallationView>
    let settingsWindow: RegularWindow<SettingsView>
    let aboutWindow: RegularWindow<AboutView>
    let windowCounter: WindowCounter
    let activationManager: ActivationManager

    override init() {
        let cli = CLI()
        let windowCounter = WindowCounter()
        let activationManager = ActivationManager()

        let switcherWindowRef = SwitcherWindowRef()
        let installationWindowRef = RegularWindowRef<InstallationView>()

        let editorStore = EditorStore(
            activationManager: activationManager,
            switcherWindow: switcherWindowRef
        )

        self.cli = cli
        self.server = SocketServer(store: editorStore)
        self.editorStore = editorStore
        self.settingsWindow = RegularWindow(
            width: SettingsView.defaultWidth,
            content: { SettingsView(cli: cli) },
            windowCounter: windowCounter
        )
        self.aboutWindow = RegularWindow(
            width: AboutView.defaultWidth,
            content: { AboutView() },
            windowCounter: windowCounter
        )
        self.switcherWindow = SwitcherWindow(
            editorStore: editorStore,
            settingsWindow: settingsWindow,
            selfRef: switcherWindowRef,
            activationManager: activationManager
        )
        self.windowCounter = windowCounter
        self.activationManager = activationManager

        self.installationWindow = RegularWindow(
            title: APP_NAME,
            width: InstallationView.defaultWidth,
            content: {
                InstallationView(
                    cli: cli,
                    installationWindow: installationWindowRef
                )
            },
            windowCounter: windowCounter
        )

        switcherWindowRef.set(self.switcherWindow)
        installationWindowRef.set(self.installationWindow)

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("Application launched")

        log.info("Registering notification manager...")
        NotificationManager.shared.registerDelegate()

        log.info("Starting socket server...")
        self.server.start()

        log.info("Updating CLI status...")
        self.cli.updateStatusOnLaunch { status in
            if case .error(_) = status {
                self.installationWindow.open()
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        log.trace("Application became inactive")
        switcherWindow.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("Application is about to terminate")
        server.stop()
    }
}
