import SwiftUI
import KeyboardShortcuts

struct Key {
    static let ESC: UInt16 = 53
    static let TAB: UInt16 = 48
    static let ENTER: UInt16 = 36
    static let ARROW_UP: UInt16 = 126
    static let ARROW_DOWN: UInt16 = 125
    static let BACKSPACE: UInt16 = 51
    static let COMMA: UInt16 = 43
    static let W: UInt16 = 13
    static let Q: UInt16 = 12
}

private final class KeyboardEventHandler: ObservableObject {
    var monitor: Any?
}

struct Layout {
    static let windowWidth: Int = 600
    static let windowHeight: Int = 320
    static let titleOriginalHight: Int = 28
    static let titleAdjustment: Int = titleOriginalHight - searchFieldVerticalPadding
    static let horisontalPadding: Int = 20
    static let searchFieldFontSize: Int = 20
    static let resultsFontSize: Int = 16
    static let searchFieldVerticalPadding: Int = 20
    static let resultItemOuterPadding: Int = 6
    static let resultItemInnerPadding: CGFloat = CGFloat(horisontalPadding - resultItemOuterPadding)
    static let resultsBottomPadding: Int = 20
    static let bottomBarVerticalPadding: Int = 6
    static let bottomBarHorizontalPadding: CGFloat = CGFloat(horisontalPadding - bottomBarButtonTrailingPadding)
    static let bottomBarFontSize: Int = 12
    static let bottomBarShortcutFontSize: Int = bottomBarFontSize + 3
    static let bottomBarButtonVerticalPadding: Int = 2
    static let bottomBarButtonLeadingPadding: Int = 8
    static let bottomBarButtonTrailingPadding: Int = 2

    static let resultsContainerHeight: CGFloat = CGFloat(
        windowHeight
        - (searchFieldVerticalPadding * 2 + searchFieldFontSize)
        - (bottomBarVerticalPadding * 2 + bottomBarFontSize + bottomBarButtonVerticalPadding * 2)
        - 16 // magic number b/c I didn't consider something in the calculation above
    )
}

final class SwitcherWindow: ObservableObject {
    private let editorStore: EditorStore
    private let settingsWindow: RegularWindow<SettingsView>
    private let selfRef: SwitcherWindowRef
    private let activationManager: ActivationManager

    private var window: NSWindow!

    @Published private var hidden: Bool = true

    init(
        editorStore: EditorStore,
        settingsWindow: RegularWindow<SettingsView>,
        selfRef: SwitcherWindowRef,
        activationManager: ActivationManager
    ) {
        self.editorStore = editorStore
        self.settingsWindow = settingsWindow
        self.selfRef = selfRef
        self.activationManager = activationManager

        let contentView = SwitcherView(
            editorStore: editorStore,
            switcherWindow: self,
            settingsWindow: settingsWindow,
            activationManager: activationManager
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(rootView: contentView)

        window.setFrameAutosaveName(APP_NAME)
        window.isReleasedWhenClosed = false

        window.level = .floating
        window.collectionBehavior = .canJoinAllSpaces

        window.hasShadow = true
        window.isOpaque = false

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.showsToolbarButton = false

        let titleAdjustment = CGFloat(Layout.titleAdjustment)
        window.contentView!.frame = window.contentView!.frame.offsetBy(dx: 0, dy: titleAdjustment)
        window.contentView!.frame.size.height -= titleAdjustment

        window.isMovableByWindowBackground = true

        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.center()

        KeyboardShortcuts.onKeyDown(for: .toggleLastActiveEditor) { [self] in
            self.handleLastActiveEditorToggle()
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSwitcher) { [self] in
            self.handleSwitcherToggle()
        }
    }

    private func handleLastActiveEditorToggle() {
        let editors = editorStore.getEditors(sortedFor: .lastActiveEditor)

        if !editors.isEmpty {
            let editor = editors.first!
            let application = NSRunningApplication(processIdentifier: editor.processIdentifier)
            switch NSWorkspace.shared.frontmostApplication {
                case .some(let app):
                    if app.processIdentifier == editor.processIdentifier {
                        application?.hide()
                    } else {
                        activationManager.setActivationTarget(
                            currentApp: app,
                            switcherWindow: self.selfRef,
                            editors: editors
                        )
                        application?.activate()
                    }
                case .none:
                    let application = NSRunningApplication(processIdentifier: editor.processIdentifier)
                    application?.hide()
            }
        } else {
            self.toggle()
        }
    }

    private func handleSwitcherToggle() {
        let editors = editorStore.getEditors()

        if editors.count == 1 {
            let editor = editors.first!

            switch NSWorkspace.shared.frontmostApplication {
                case .some(let app):
                    if app.processIdentifier == editor.processIdentifier {
                        activationManager.activateTarget()
                        activationManager.setActivationTarget(
                            currentApp: app,
                            switcherWindow: self.selfRef,
                            editors: editors
                        )
                    } else {
                        activationManager.setActivationTarget(
                            currentApp: app,
                            switcherWindow: self.selfRef,
                            editors: editors
                        )
                        editor.activate()
                    }
                case .none:
                    editor.activate()
            }
        } else {
            self.toggle()
        }
    }

    private func toggle() {
        if window.isVisible {
            self.hide()
        } else {
            self.show()
        }
    }

    private func show() {
        activationManager.setActivationTarget(
            currentApp: NSWorkspace.shared.frontmostApplication,
            switcherWindow: self.selfRef,
            editors: self.editorStore.getEditors()
        )

        self.hidden = false

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func hide() {
        if self.hidden {
            return
        }

        self.hidden = true
        window.orderOut(nil)

        let currentApp = NSWorkspace.shared.frontmostApplication
        if currentApp?.bundleIdentifier == APP_BUNDLE_ID {
            activationManager.activateTarget()
        }
    }

    public func isHidden() -> Bool {
        return self.hidden
    }

    public func isSameWindow(_ window: NSWindow) -> Bool {
        self.window == window
    }
}

struct SwitcherView: View {
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    private enum State {
        case noEditors
        case oneEditor
        case manyEditors
    }

    private var state: State? {
        if switcherWindow.isHidden() {
            return nil
        }

        let editors = editorStore.getEditors()

        switch editors.count {
            case 0:
                return .noEditors
            case 1:
                return .oneEditor
            default:
                return .manyEditors
        }
    }

    var body: some View {
        Group {
            switch state {
                case .noEditors:
                    SwitcherEmptyView(
                        switcherWindow: self.switcherWindow,
                        settingsWindow: self.settingsWindow
                    )
                case .oneEditor, .manyEditors:
                    SwitcherListView(
                        editorStore: self.editorStore,
                        switcherWindow: self.switcherWindow,
                        settingsWindow: self.settingsWindow,
                        activationManager: self.activationManager
                    )
                case .none:
                    EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SwitcherEmptyView: View {
    @ObservedObject var switcherWindow: SwitcherWindow

    let settingsWindow: RegularWindow<SettingsView>

    @StateObject private var keyboard = KeyboardEventHandler()

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 26) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            VStack(spacing: 6) {
                Text("No Neovide instances in NeoHub")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                Text("Use CLI to launch some")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            Button("Close") { switcherWindow.hide() }.focused($focused)
        }
        .onAppear {
            log.trace("SwitcherEmptyView: appears")

            self.focused = true

            self.keyboard.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                    case Key.ESC:
                        switcherWindow.hide()
                        return nil
                    case Key.COMMA where event.modifierFlags.contains(.command):
                        switcherWindow.hide()
                        settingsWindow.open()
                        return nil
                    case Key.W where event.modifierFlags.contains(.command):
                        switcherWindow.hide()
                        return nil
                    default:
                        break
                }
                return event
            }
        }
        .onDisappear() {
            log.trace("SwitcherEmptyView: disappears")
            if let monitor = keyboard.monitor {
                log.trace("SwitcherEmptyView: removing monitor")
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

struct SwitcherListView: View {
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    @StateObject private var keyboard = KeyboardEventHandler()

    @State private var searchText = ""
    @State private var selectedIndex: Int = 0

    @FocusState private var focused: Bool

    var body: some View {
        let editors = self.filterEditors()

        VStack(spacing: 0) {
            Form {
                TextField("Search", text: $searchText, prompt: Text("Search..."))
                    .font(.system(size: CGFloat(Layout.searchFieldFontSize)))
                    .textFieldStyle(PlainTextFieldStyle())
                    .labelsHidden()
                    .focused($focused)
                    .padding(.horizontal, CGFloat(Layout.horisontalPadding))
                    .padding(.bottom, CGFloat(Layout.searchFieldVerticalPadding))
                    .onChange(of: searchText) { _ in
                        selectedIndex = 0
                    }
            }
            Divider().padding(.bottom, CGFloat(Layout.resultItemOuterPadding))
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(editors.enumerated()), id: \.1.id) { index, editor in
                        Button(action: { editor.activate() }) {
                            HStack(spacing: 16) {
                                Image("EditorIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .foregroundColor(.gray)
                                Text(editor.name).font(.system(size: CGFloat(Layout.resultsFontSize)))
                                Spacer()
                                Text(editor.displayPath)
                                    .font(.system(size: CGFloat(Layout.resultsFontSize)))
                                    .foregroundColor(.gray)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(maxWidth: .infinity)
                        .padding(Layout.resultItemInnerPadding)
                        .background(
                            Color.gray.opacity(selectedIndex == index ? 0.1 : 0.0)
                        )
                        .cornerRadius(6)
                        .focusable(false)
                    }
                }
                .padding(.horizontal, CGFloat(Layout.resultItemOuterPadding))
                .padding(.bottom, CGFloat(Layout.resultsBottomPadding))
            }
            .frame(height: Layout.resultsContainerHeight)
            HStack(spacing: 5) {
                Spacer()
                BottomBarButton(text: "Quit Selected", shortcut: ["⌘", "⌫"], action: { self.quitSelectedEditor() })
                BottomBarButton(text: "Quit All", shortcut: ["⌘", "Q"], action: { self.quitAllEditors() })
            }
            .padding(.vertical, CGFloat(Layout.bottomBarVerticalPadding))
            .padding(.horizontal, CGFloat(Layout.bottomBarHorizontalPadding))
            .background(Color.black.opacity(0.1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            log.trace("SwitcherListView: appears")

            self.focused = true

            self.keyboard.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                    case Key.ARROW_UP:
                        if selectedIndex > 0 {
                            selectedIndex -= 1
                        }
                        return nil
                    case Key.ARROW_DOWN:
                        if selectedIndex < self.filterEditors().count - 1 {
                            selectedIndex += 1
                        }
                        return nil
                    case Key.TAB:
                        selectedIndex = (selectedIndex + 1) % self.filterEditors().count
                        return nil
                    case Key.ENTER:
                        let editors = self.filterEditors()
                        if editors.indices.contains(selectedIndex) {
                            let editor = editors[selectedIndex]
                            editor.activate()
                        }
                        return nil
                    case Key.BACKSPACE where event.modifierFlags.contains(.command):
                        self.quitSelectedEditor()
                        return nil
                    case Key.ESC:
                        switcherWindow.hide()
                        return nil
                    case Key.COMMA where event.modifierFlags.contains(.command):
                        switcherWindow.hide()
                        settingsWindow.open()
                        return nil
                    case Key.W where event.modifierFlags.contains(.command):
                        switcherWindow.hide()
                        return nil
                    case Key.Q where event.modifierFlags.contains(.command):
                        self.quitAllEditors()
                        return nil
                    default:
                        break
                }
                return event
            }
        }
        .onDisappear() {
            log.trace("SwitcherListView: disappears")
            if let monitor = keyboard.monitor {
                log.trace("SwitcherListView: removing monitor")
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    func filterEditors() -> [Editor] {
        editorStore.getEditors(sortedFor: .switcher).filter { editor in
            searchText.isEmpty
            || editor.name.contains(searchText)
            || editor.displayPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    func quitSelectedEditor() {
        let editors = self.filterEditors()
        if editors.indices.contains(selectedIndex) {
            let editor = editors[selectedIndex]
            let totalEditors = editors.count

            if totalEditors == selectedIndex + 1 && selectedIndex != 0 {
                selectedIndex -= 1
            }

            if totalEditors == 1 {
                activationManager.activateTarget()
            }

            editor.quit()
        }
    }

    func quitAllEditors() {
        Task {
            activationManager.activateTarget()
            await editorStore.quitAllEditors()
        }
    }

    struct BottomBarButton: View {
        let text: String
        let shortcut: [Character]
        let action: () -> Void

        private static let background = Color.clear

        @State private var background: Color = Self.background

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(text)
                        .foregroundColor(.gray)
                    HStack(spacing: 2) {
                        ForEach(shortcut, id: \.self) { key in
                            Text(String(key))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .font(.system(size: CGFloat(Layout.bottomBarShortcutFontSize), design: .monospaced))
                                .foregroundColor(.gray)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(2)
                        }
                    }
                }
            }
            .font(.system(size: CGFloat(Layout.bottomBarFontSize)))
            .buttonStyle(PlainButtonStyle())
            .padding(.vertical, CGFloat(Layout.bottomBarButtonVerticalPadding))
            .padding(.leading, CGFloat(Layout.bottomBarButtonLeadingPadding))
            .padding(.trailing, CGFloat(Layout.bottomBarButtonTrailingPadding))
            .background(background)
            .cornerRadius(3)
            .focusable(false)
            .onHover(perform: { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    background = hovering ? Color.white.opacity(0.1) : Self.background
                }
            })
        }
    }
}

final class SwitcherWindowRef {
    private var window: SwitcherWindow?

    init(window: SwitcherWindow? = nil) {
        self.window = window
    }

    func set(_ window: SwitcherWindow) {
        self.window = window
    }

    func isSameWindow(_ window: NSWindow) -> Bool {
        if let win = self.window {
            return win.isSameWindow(window)
        } else {
            return false
        }
    }
}
