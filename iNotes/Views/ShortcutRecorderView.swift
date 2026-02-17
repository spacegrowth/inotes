import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    @State private var keyCode: UInt32
    @State private var modifiers: UInt32
    @State private var isRecording = false
    @State private var displayString: String
    var onSave: (UInt32, UInt32) -> Void
    var onCancel: () -> Void

    init(currentKeyCode: UInt32, currentModifiers: UInt32, onSave: @escaping (UInt32, UInt32) -> Void, onCancel: @escaping () -> Void) {
        _keyCode = State(initialValue: currentKeyCode)
        _modifiers = State(initialValue: currentModifiers)
        _displayString = State(initialValue: ShortcutRecorderView.shortcutString(keyCode: currentKeyCode, modifiers: currentModifiers))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Shortcut")
                .font(.headline)

            Text(isRecording ? "Press new shortcut..." : displayString)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .frame(width: 220, height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1))
                .onTapGesture { isRecording = true }

            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(keyCode, modifiers) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRecording)
            }
        }
        .padding(24)
        .frame(width: 280)
        .background(KeyEventHandler(isRecording: $isRecording, onKeyDown: { event in
            let carbonMods = carbonModifiers(from: event.modifierFlags)
            guard carbonMods != 0 else { return }
            keyCode = UInt32(event.keyCode)
            modifiers = carbonMods
            displayString = ShortcutRecorderView.shortcutString(keyCode: keyCode, modifiers: modifiers)
            isRecording = false
        }))
    }

    static func shortcutString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Minus): "-",
            UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Grave): "`",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥", UInt32(kVK_Delete): "⌫",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        return names[keyCode] ?? "?"
    }
}

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var mods: UInt32 = 0
    if flags.contains(.command) { mods |= UInt32(cmdKey) }
    if flags.contains(.shift) { mods |= UInt32(shiftKey) }
    if flags.contains(.option) { mods |= UInt32(optionKey) }
    if flags.contains(.control) { mods |= UInt32(controlKey) }
    return mods
}

struct KeyEventHandler: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyDown = onKeyDown
        view.isRecordingRef = { self.isRecording }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.isRecordingRef = { self.isRecording }
    }

    class KeyCaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?
        var isRecordingRef: (() -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let isRecording = self.isRecordingRef, isRecording() else {
                        return event
                    }
                    self.onKeyDown?(event)
                    return nil
                }
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}
