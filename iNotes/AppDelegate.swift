import Cocoa
import SwiftUI
import Carbon.HIToolbox

private let kHotKeyNotification = Notification.Name("iNotesHotKeyPressed")

private func hotKeyHandler(_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    NotificationCenter.default.post(name: kHotKeyNotification, object: nil)
    return noErr
}

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyablePanel!
    private let store = NotesStore()
    private var eventMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var shortcutWindow: NSWindow?

    private var currentKeyCode: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: "hotkeyKeyCode")).nonZero ?? UInt32(kVK_ANSI_1) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "hotkeyKeyCode") }
    }
    private var currentModifiers: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers")).nonZero ?? UInt32(cmdKey | shiftKey) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "hotkeyModifiers") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hostingView = NSHostingController(rootView: ContentView(store: store))
        hostingView.view.frame = NSRect(x: 0, y: 0, width: 360, height: 420)

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSApp.effectiveAppearance
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.isFloatingPanel = true
        panel.contentViewController = hostingView

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 10
        panel.contentView?.layer?.masksToBounds = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHotKey), name: kHotKeyNotification, object: nil
        )
        installCarbonHandler()
        registerHotKey(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        unregisterHotKey()
    }

    // MARK: - Status Item Click

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let shortcutLabel = "Shortcut: \(ShortcutRecorderView.shortcutString(keyCode: currentKeyCode, modifiers: currentModifiers))"
        let shortcutItem = NSMenuItem(title: shortcutLabel, action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem(title: "Change Shortcut...", action: #selector(openShortcutRecorder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit iNotes", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openShortcutRecorder() {
        if shortcutWindow != nil {
            shortcutWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let recorder = ShortcutRecorderView(
            currentKeyCode: currentKeyCode,
            currentModifiers: currentModifiers,
            onSave: { [weak self] keyCode, modifiers in
                self?.updateHotKey(keyCode: keyCode, modifiers: modifiers)
                self?.shortcutWindow?.close()
                self?.shortcutWindow = nil
            },
            onCancel: { [weak self] in
                self?.shortcutWindow?.close()
                self?.shortcutWindow = nil
            }
        )

        let hostingController = NSHostingController(rootView: recorder)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "iNotes Shortcut"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        shortcutWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Carbon Global Hotkey

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID(signature: OSType(0x494E4F54), id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func updateHotKey(keyCode: UInt32, modifiers: UInt32) {
        unregisterHotKey()
        currentKeyCode = keyCode
        currentModifiers = modifiers
        registerHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    @objc private func handleHotKey() {
        togglePanel()
    }

    // MARK: - Panel Toggle

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
            stopClickMonitor()
        } else {
            positionPanel()
            panel.appearance = NSApp.effectiveAppearance
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            focusEditor()
            startClickMonitor()
        }
    }

    private func focusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let contentView = self?.panel.contentView else { return }
            if let textView = self?.findTextView(in: contentView) {
                self?.panel.makeFirstResponder(textView)
            }
        }
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func positionPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth = panel.frame.width
        let x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panel.frame.height - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startClickMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.panel.orderOut(nil)
            self.stopClickMonitor()
        }
    }

    private func stopClickMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

extension UInt32 {
    var nonZero: UInt32? { self == 0 ? nil : self }
}
