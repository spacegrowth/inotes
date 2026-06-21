import SwiftUI
import AppKit

/// Posted (synchronously) when the app is about to terminate so the editor
/// Coordinator can flush its pending debounced RTF encode before `store.save()`.
extension Notification.Name {
    static let iNotesFlushPendingEncode = Notification.Name("iNotesFlushPendingEncode")
}

// Default font helper
func defaultFont(size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont(name: "Menlo-Regular", size: size)
        ?? NSFont(name: "Menlo", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

func defaultBoldFont(size: CGFloat = 13) -> NSFont {
    NSFont(name: "Menlo-Bold", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
}

class RichNoteTextView: NSTextView {
    weak var editorState: EditorState?

    // MARK: - Cursor rects for checkboxes

    override func resetCursorRects() {
        super.resetCursorRects()

        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let string = self.string as NSString
        guard string.length > 0 else { return }

        // Find all checkbox characters and add pointing hand cursor rects
        var searchRange = NSRange(location: 0, length: string.length)
        while searchRange.location < string.length {
            let paraRange = string.paragraphRange(for: NSRange(location: searchRange.location, length: 0))
            let paraText = string.substring(with: paraRange)

            if TextEditorLogic.isTodoParagraph(paraText) {
                // Get the glyph rect for the checkbox character
                let cbRange = NSRange(location: paraRange.location, length: 1)
                let glyphRange = layoutManager.glyphRange(forCharacterRange: cbRange, actualCharacterRange: nil)
                var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                rect.origin.x += textContainerInset.width
                rect.origin.y += textContainerInset.height
                // Make the hit area a bit wider for easier clicking
                rect.size.width = max(rect.size.width, 20)
                addCursorRect(rect, cursor: .pointingHand)
            }

            searchRange.location = NSMaxRange(paraRange)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        // Refresh cursor rects when text changes
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Key handling

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        let hasShift = event.modifierFlags.contains(.shift)

        switch chars {
        case "b":
            editorState?.toggleBold()
            return true
        case "i":
            editorState?.toggleItalic()
            return true
        case "u":
            editorState?.toggleUnderline()
            return true
        case "t":
            if hasShift {
                editorState?.toggleTodo()
                return true
            }
            return super.performKeyEquivalent(with: event)
        case "z":
            if hasShift {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        let string = self.string as NSString

        if charIndex < string.length {
            let paraRange = string.paragraphRange(for: NSRange(location: charIndex, length: 0))
            let paraText = string.substring(with: paraRange)

            if TextEditorLogic.isTodoParagraph(paraText) {
                let clickOffsetInPara = charIndex - paraRange.location
                if clickOffsetInPara <= 1 {
                    editorState?.toggleCheckboxAt(paraRange.location)
                    return
                }
            }
        }

        super.mouseDown(with: event)
    }

    // MARK: - Newline handling

    override func insertNewline(_ sender: Any?) {
        let string = self.string as NSString
        let cursorLocation = selectedRange().location
        let paraRange = string.paragraphRange(for: NSRange(location: cursorLocation, length: 0))
        let paraText = string.substring(with: paraRange)

        // Handle todo lines
        if TextEditorLogic.isTodoParagraph(paraText) {
            let content = paraText.replacingOccurrences(of: "\n", with: "")
            if content == "☐" || content == "☐ " {
                let removeRange = NSRange(location: paraRange.location, length: min(2, paraRange.length))
                if shouldChangeText(in: removeRange, replacementString: "") {
                    textStorage?.replaceCharacters(in: removeRange, with: "")
                    didChangeText()
                }
                return
            }
            let insertRange = selectedRange()
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: defaultFont(),
                .foregroundColor: NSColor.black,
                .strikethroughStyle: 0
            ]
            let cbAttrs: [NSAttributedString.Key: Any] = [
                .font: EditorState.checkboxFont,
                .foregroundColor: NSColor.black,
                .strikethroughStyle: 0
            ]
            let attrInsertion = NSMutableAttributedString()
            attrInsertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
            attrInsertion.append(NSAttributedString(string: "☐", attributes: cbAttrs))
            attrInsertion.append(NSAttributedString(string: " ", attributes: bodyAttrs))
            let insertion = "\n☐ "
            if shouldChangeText(in: insertRange, replacementString: insertion) {
                textStorage?.replaceCharacters(in: insertRange, with: attrInsertion)
                setSelectedRange(NSRange(location: insertRange.location + (insertion as NSString).length, length: 0))
                typingAttributes = bodyAttrs
                didChangeText()
            }
            return
        }

        let level = TextEditorLogic.bulletLevel(of: paraText)

        if level > 0 {
            let prefix = TextEditorLogic.bulletPrefix(for: level)
            let content = paraText.replacingOccurrences(of: "\n", with: "")
            if content == String(prefix.dropLast()) || content == prefix {
                let prefixLen = TextEditorLogic.bulletPrefixLength(of: paraText, level: level)
                let removeRange = NSRange(location: paraRange.location, length: min(prefixLen, paraRange.length))
                if shouldChangeText(in: removeRange, replacementString: "") {
                    textStorage?.replaceCharacters(in: removeRange, with: "")
                    didChangeText()
                }
                return
            }
            let insertion = "\n" + prefix
            super.insertText(insertion, replacementRange: selectedRange())
            return
        }

        super.insertNewline(sender)
    }

    // MARK: - Tab handling

    override func insertTab(_ sender: Any?) {
        let string = self.string as NSString
        let cursorLocation = selectedRange().location
        let paraRange = string.paragraphRange(for: NSRange(location: cursorLocation, length: 0))
        let paraText = string.substring(with: paraRange)
        let level = TextEditorLogic.bulletLevel(of: paraText)

        if level > 0 && level < TextEditorLogic.bulletLevels.count {
            let oldPrefixLen = TextEditorLogic.bulletPrefixLength(of: paraText, level: level)
            let newPrefix = TextEditorLogic.bulletPrefix(for: level + 1)
            let replaceRange = NSRange(location: paraRange.location, length: oldPrefixLen)
            if shouldChangeText(in: replaceRange, replacementString: newPrefix) {
                textStorage?.replaceCharacters(in: replaceRange, with: newPrefix)
                let newCursor = cursorLocation - oldPrefixLen + (newPrefix as NSString).length
                setSelectedRange(NSRange(location: newCursor, length: 0))
                didChangeText()
            }
            return
        }

        super.insertText("    ", replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        let string = self.string as NSString
        let cursorLocation = selectedRange().location
        let paraRange = string.paragraphRange(for: NSRange(location: cursorLocation, length: 0))
        let paraText = string.substring(with: paraRange)
        let level = TextEditorLogic.bulletLevel(of: paraText)

        if level > 1 {
            let oldPrefixLen = TextEditorLogic.bulletPrefixLength(of: paraText, level: level)
            let newPrefix = TextEditorLogic.bulletPrefix(for: level - 1)
            let replaceRange = NSRange(location: paraRange.location, length: oldPrefixLen)
            if shouldChangeText(in: replaceRange, replacementString: newPrefix) {
                textStorage?.replaceCharacters(in: replaceRange, with: newPrefix)
                let newCursor = max(paraRange.location + (newPrefix as NSString).length,
                                    cursorLocation - oldPrefixLen + (newPrefix as NSString).length)
                setSelectedRange(NSRange(location: newCursor, length: 0))
                didChangeText()
            }
            return
        }

        super.insertBacktab(sender)
    }

    // MARK: - Auto bullet on "- "

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)

        guard let str = string as? String, str == " " else { return }
        let fullString = self.string as NSString
        let cursorLocation = selectedRange().location
        let paraRange = fullString.paragraphRange(for: NSRange(location: cursorLocation, length: 0))
        let paraText = fullString.substring(with: paraRange)

        if TextEditorLogic.shouldConvertDashToBullet(paraText) {
            let dashRange = NSRange(location: paraRange.location, length: 2)
            if shouldChangeText(in: dashRange, replacementString: "• ") {
                textStorage?.replaceCharacters(in: dashRange, with: "• ")
                setSelectedRange(NSRange(location: paraRange.location + 2, length: 0))
                didChangeText()
            }
        }
    }
}

// MARK: - NoteEditorView

struct NoteEditorView: NSViewRepresentable {
    @Binding var rtfData: Data
    var noteID: UUID
    @ObservedObject var editorState: EditorState

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let oldTextView = scrollView.documentView as! NSTextView
        let textContainer = oldTextView.textContainer!
        let richTextView = RichNoteTextView(frame: oldTextView.frame, textContainer: textContainer)
        richTextView.editorState = editorState
        richTextView.autoresizingMask = [.width, .height]
        scrollView.documentView = richTextView

        let textView = richTextView
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.insertionPointColor = .black
        textView.typingAttributes = Self.defaultAttributes
        textView.delegate = context.coordinator

        loadRTFData(into: textView)
        context.coordinator.currentNoteID = noteID
        context.coordinator.activeBinding = _rtfData
        editorState.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? RichNoteTextView else { return }

        if context.coordinator.currentNoteID != noteID {
            // Switching notes: flush any pending RTF encode for the OUTGOING note
            // (through its pinned binding) before rebinding, so the last few
            // keystrokes are never lost.
            context.coordinator.flushPendingEncode(deferWrite: true)
            context.coordinator.activeBinding = _rtfData
            context.coordinator.currentNoteID = noteID
            context.coordinator.isUpdating = true
            loadRTFData(into: textView)
            textView.typingAttributes = Self.defaultAttributes
            context.coordinator.isUpdating = false
            editorState.textView = textView
            editorState.updateFromSelection()
        }
    }

    private func loadRTFData(into textView: NSTextView) {
        if !rtfData.isEmpty,
           let attrStr = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attrStr)
        } else {
            textView.string = ""
            textView.typingAttributes = Self.defaultAttributes
        }
    }

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: defaultFont(),
            .foregroundColor: NSColor.black
        ]
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditorView
        var currentNoteID: UUID?
        var isUpdating = false

        /// Binding for the note that is currently loaded, pinned to that note's
        /// index (see `ContentView`). The debounced encode writes through this so
        /// a flush triggered after a note switch still targets the right note.
        var activeBinding: Binding<Data>?

        /// Coalesces the (expensive) full-document RTF serialization so it runs
        /// once after the user pauses, instead of on every keystroke.
        private var encodeTimer: Timer?
        private weak var pendingTextView: NSTextView?
        private let encodeDelay: TimeInterval = 0.3

        init(_ parent: NoteEditorView) {
            self.parent = parent
            super.init()
            // App termination: flush the pending encode synchronously so the
            // last <0.3s of typing is captured before `store.save()`.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(flushOnTerminate),
                name: .iNotesFlushPendingEncode,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            // View teardown: persist any pending edit so nothing is lost.
            flushPendingEncode()
        }

        /// Notification entry point for the terminate flush. Runs synchronously
        /// on the posting (main) thread, so the binding write completes before
        /// `applicationWillTerminate` calls `store.save()`.
        @objc private func flushOnTerminate() {
            flushPendingEncode()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }

            // On-screen text is already updated by NSTextView; only the RTF
            // re-encode is debounced.
            pendingTextView = textView
            encodeTimer?.invalidate()
            encodeTimer = Timer.scheduledTimer(withTimeInterval: encodeDelay, repeats: false) { [weak self] _ in
                self?.flushPendingEncode()
            }
        }

        /// Serialize the pending text view to RTF and write it through the
        /// pinned `activeBinding`. Safe to call repeatedly; no-ops when nothing
        /// is pending.
        ///
        /// When called from inside SwiftUI's view-update pass (the note-switch in
        /// `updateNSView`), pass `deferWrite: true` so the `@Published` mutation
        /// is moved off the current update cycle. The outgoing binding is
        /// captured first, so the deferred write still targets the correct note
        /// even though `activeBinding` is reassigned right after.
        func flushPendingEncode(deferWrite: Bool = false) {
            encodeTimer?.invalidate()
            encodeTimer = nil
            guard let textView = pendingTextView,
                  let textStorage = textView.textStorage else { return }
            pendingTextView = nil

            let range = NSRange(location: 0, length: textStorage.length)
            guard let data = try? textStorage.data(from: range,
                                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return }
            let binding = activeBinding
            if deferWrite {
                DispatchQueue.main.async { binding?.wrappedValue = data }
            } else {
                binding?.wrappedValue = data
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.editorState.updateFromSelection()
        }
    }
}
