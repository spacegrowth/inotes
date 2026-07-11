import SwiftUI
import AppKit

/// Posted (synchronously) when the app is about to terminate so the editor
/// Coordinator can flush its pending debounced save before `store.save()`.
extension Notification.Name {
    static let iNotesFlushPendingEncode = Notification.Name("iNotesFlushPendingEncode")
}

// Default font helpers (Menlo monospace base).
func defaultFont(size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont(name: "Menlo-Regular", size: size)
        ?? NSFont(name: "Menlo", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

func defaultBoldFont(size: CGFloat = 13) -> NSFont {
    NSFont(name: "Menlo-Bold", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
}

/// NSTextView whose `string` IS the markdown source. It never rewrites the
/// source to render styling — `MarkdownStyler` paints attributes on top. The
/// overrides here keep list/checkbox editing ergonomic while leaving the
/// characters as plain, saveable markdown.
class RichNoteTextView: NSTextView {
    weak var editorState: EditorState?

    // MARK: - Cursor: pointing hand over checkboxes

    // NSTextView continuously restores the I-beam through its own cursor-rect
    // machinery, which clobbers any `addCursorRect(_:cursor:)` we register in
    // `resetCursorRects`. The cursor must instead be set at the responder level
    // in `cursorUpdate(with:)`, which is where NSTextView decides the cursor
    // during mouse tracking. A `.cursorUpdate` tracking area guarantees it fires
    // across the whole text area.

    private var cursorTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = cursorTrackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseMoved],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let boxRect = checkboxBoxRect(at: point), boxRect.contains(point) {
            NSCursor.pointingHand.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    /// The on-screen rect of the checkbox box for the line under `point`, in view
    /// coordinates, or `nil` when that line is not a checkbox. Uses the same
    /// `MarkerLayoutManager.checkboxBoxRect` geometry the box is drawn with, and
    /// the same box+space width as the click target in `mouseDown`.
    private func checkboxBoxRect(at point: NSPoint) -> NSRect? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return nil }
        let string = self.string as NSString
        guard string.length > 0 else { return nil }

        let charIndex = characterIndexForInsertion(at: point)
        guard charIndex <= string.length else { return nil }
        let paraRange = string.paragraphRange(for: NSRange(location: min(charIndex, string.length - 1), length: 0))
        let line = string.substring(with: paraRange).replacingOccurrences(of: "\n", with: "")
        guard let box = TextEditorLogic.checkbox(ofLine: line) else { return nil }

        let boxCell = NSRange(location: paraRange.location + box.indent, length: 1)
        let boxGlyph = layoutManager.glyphRange(forCharacterRange: boxCell, actualCharacterRange: nil)
        let cellRect = layoutManager.boundingRect(forGlyphRange: boxGlyph, in: textContainer)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: boxGlyph.location, effectiveRange: nil)
        var rect = MarkerLayoutManager.checkboxBoxRect(cellRect: cellRect, lineRect: lineRect)
        rect.size.width = max(rect.size.width, cellRect.size.width * 2)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect
    }

    // MARK: - Key handling (Cmd+B/I/U, undo/redo)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let hasShift = event.modifierFlags.contains(.shift)

        switch chars {
        case "b": editorState?.toggleBold(); return true
        case "i": editorState?.toggleItalic(); return true
        case "u": editorState?.toggleUnderline(); return true
        case "z":
            if hasShift { undoManager?.redo() } else { undoManager?.undo() }
            return true
        case "f":
            showFindBar()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Cmd+F: find bar

    /// Show the built-in `NSTextFinder` find bar. `performTextFinderAction`
    /// dispatches purely on `sender.tag`, so a throwaway menu item carrying
    /// the "show find interface" tag is enough to trigger it programmatically.
    private func showFindBar() {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        performTextFinderAction(item)
    }

    // MARK: - Mouse: checkbox toggle

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        let string = self.string as NSString

        if charIndex <= string.length, string.length > 0 {
            let paraRange = string.paragraphRange(for: NSRange(location: min(charIndex, string.length - 1), length: 0))
            let line = string.substring(with: paraRange).replacingOccurrences(of: "\n", with: "")
            if let box = TextEditorLogic.checkbox(ofLine: line) {
                let clickOffset = charIndex - paraRange.location
                // The marker's syntax is collapsed to zero width on screen, so
                // the whole `- [ ] ` maps to ~2 visible cells (box + space).
                // Any insertion index within the 6-char marker (offset <
                // markerRange.length) is a click on the box region → toggle;
                // the first content char (offset == length) places the caret.
                if clickOffset < box.markerRange.length {
                    editorState?.toggleCheckboxAt(paraRange.location)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Enter: continue / end lists

    override func insertNewline(_ sender: Any?) {
        let string = self.string as NSString
        let cursor = selectedRange().location
        let paraRange = string.paragraphRange(for: NSRange(location: cursor, length: 0))
        let line = string.substring(with: paraRange).replacingOccurrences(of: "\n", with: "")

        // Empty list item → clear the marker and end the list.
        if TextEditorLogic.isEmptyListItem(line) {
            let markerLen = TextEditorLogic.listMarkerLength(of: line)
            let removeRange = NSRange(location: paraRange.location, length: min(markerLen, paraRange.length))
            if shouldChangeText(in: removeRange, replacementString: "") {
                textStorage?.replaceCharacters(in: removeRange, with: "")
                didChangeText()
            }
            return
        }

        // Non-empty list item → continue with the same prefix on a new line.
        if let prefix = TextEditorLogic.listContinuationPrefix(for: line) {
            super.insertText("\n" + prefix, replacementRange: selectedRange())
            return
        }

        super.insertNewline(sender)
    }

    // MARK: - Tab / Shift-Tab: indent list items

    override func insertTab(_ sender: Any?) {
        if adjustIndent(by: TextEditorLogic.indentUnit) { return }
        super.insertText(String(repeating: " ", count: TextEditorLogic.indentUnit),
                         replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        if adjustIndent(by: -TextEditorLogic.indentUnit) { return }
        super.insertBacktab(sender)
    }

    /// Add/remove one indent unit of leading spaces on a list line. Returns
    /// false (no-op) when the current line is not a list item.
    private func adjustIndent(by delta: Int) -> Bool {
        let string = self.string as NSString
        let cursor = selectedRange().location
        let paraRange = string.paragraphRange(for: NSRange(location: cursor, length: 0))
        let line = string.substring(with: paraRange).replacingOccurrences(of: "\n", with: "")

        let isList = TextEditorLogic.checkbox(ofLine: line) != nil
            || TextEditorLogic.bullet(ofLine: line) != nil
        guard isList else { return false }

        let indent = TextEditorLogic.leadingSpaces(of: line)
        if delta > 0 {
            let insertRange = NSRange(location: paraRange.location, length: 0)
            let spaces = String(repeating: " ", count: delta)
            if shouldChangeText(in: insertRange, replacementString: spaces) {
                textStorage?.replaceCharacters(in: insertRange, with: spaces)
                setSelectedRange(NSRange(location: cursor + delta, length: 0))
                didChangeText()
            }
        } else {
            let remove = min(-delta, indent)
            guard remove > 0 else { return true }
            let removeRange = NSRange(location: paraRange.location, length: remove)
            if shouldChangeText(in: removeRange, replacementString: "") {
                textStorage?.replaceCharacters(in: removeRange, with: "")
                setSelectedRange(NSRange(location: max(paraRange.location, cursor - remove), length: 0))
                didChangeText()
            }
        }
        return true
    }
}

// MARK: - NoteEditorView

struct NoteEditorView: NSViewRepresentable {
    @Binding var text: String
    var noteID: UUID
    @ObservedObject var editorState: EditorState

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay          // overlay: doesn't eat text width
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let oldTextView = scrollView.documentView as! NSTextView
        let textContainer = oldTextView.textContainer!
        // Swap in a layout manager that draws list markers as pretty glyphs
        // (•/◦/▪, ☐/☑) without altering the source characters or layout.
        textContainer.replaceLayoutManager(MarkerLayoutManager())
        let richTextView = RichNoteTextView(frame: oldTextView.frame, textContainer: textContainer)
        richTextView.editorState = editorState
        scrollView.documentView = richTextView

        let textView = richTextView
        // --- Vertical scrolling / resize fix ---
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.isRichText = true          // allow attribute styling
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.insertionPointColor = .black
        textView.typingAttributes = Self.defaultAttributes
        textView.delegate = context.coordinator

        loadText(into: textView)
        context.coordinator.currentNoteID = noteID
        context.coordinator.activeBinding = _text
        editorState.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? RichNoteTextView else { return }

        if context.coordinator.currentNoteID != noteID {
            // Switching notes: flush the OUTGOING note's pending save first.
            context.coordinator.flushPendingEncode(deferWrite: true)
            context.coordinator.activeBinding = _text
            context.coordinator.currentNoteID = noteID
            context.coordinator.isUpdating = true
            loadText(into: textView)
            textView.typingAttributes = Self.defaultAttributes
            context.coordinator.isUpdating = false
            editorState.textView = textView
            editorState.updateFromSelection()
        }
    }

    private func loadText(into textView: NSTextView) {
        textView.string = text
        textView.typingAttributes = Self.defaultAttributes
        if let ts = textView.textStorage {
            MarkdownStyler.apply(to: ts)
        }
    }

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont(), .foregroundColor: NSColor.black]
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditorView
        var currentNoteID: UUID?
        var isUpdating = false

        /// Binding for the currently-loaded note, pinned to its index (see
        /// `ContentView`). The debounced save writes through this so a flush
        /// after a note switch still targets the right note.
        var activeBinding: Binding<String>?

        /// Coalesces persistence of the plain-text source so the store save
        /// isn't thrashed on every keystroke.
        private var saveTimer: Timer?
        private weak var pendingTextView: NSTextView?
        private let saveDelay: TimeInterval = 0.3

        init(_ parent: NoteEditorView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(flushOnTerminate),
                name: .iNotesFlushPendingEncode, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            flushPendingEncode()
        }

        @objc private func flushOnTerminate() { flushPendingEncode() }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }

            // Live-restyle the (already-updated) source on every edit.
            if let ts = textView.textStorage {
                MarkdownStyler.apply(to: ts)
            }
            textView.typingAttributes = NoteEditorView.defaultAttributes

            // Persistence of the plain string is debounced.
            pendingTextView = textView
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
                self?.flushPendingEncode()
            }
        }

        /// Write the pending text view's source through the pinned binding.
        /// Safe to call repeatedly; no-ops when nothing is pending.
        func flushPendingEncode(deferWrite: Bool = false) {
            saveTimer?.invalidate()
            saveTimer = nil
            guard let textView = pendingTextView else { return }
            pendingTextView = nil

            let value = textView.string
            let binding = activeBinding
            if deferWrite {
                DispatchQueue.main.async { binding?.wrappedValue = value }
            } else {
                binding?.wrappedValue = value
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.editorState.updateFromSelection()
        }
    }
}
