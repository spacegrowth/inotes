import AppKit
import SwiftUI

enum HeadingLevel: Int, CaseIterable {
    case body = 0
    case h1 = 1
    case h2 = 2
    case h3 = 3

    var fontSize: CGFloat {
        switch self {
        case .body: return 13
        case .h1: return 22
        case .h2: return 18
        case .h3: return 15
        }
    }

    var fontWeight: NSFont.Weight {
        switch self {
        case .body: return .regular
        case .h1, .h2, .h3: return .bold
        }
    }
}

@MainActor
class EditorState: ObservableObject {
    weak var textView: NSTextView?

    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderlined = false
    @Published var currentHeading: HeadingLevel = .body
    @Published var isBulletList = false
    @Published var isTodoItem = false

    // Larger font for checkbox characters
    static let checkboxFont = defaultFont(size: 18)

    func updateFromSelection() {
        guard let textView = textView,
              let textStorage = textView.textStorage,
              textStorage.length > 0 else {
            if let textView = textView {
                let attrs = textView.typingAttributes
                updateState(from: attrs)
            }
            return
        }

        let attrs: [NSAttributedString.Key: Any]
        let selRange = textView.selectedRange()
        if selRange.length > 0 && selRange.location < textStorage.length {
            attrs = textStorage.attributes(at: selRange.location, effectiveRange: nil)
        } else if selRange.location > 0 && selRange.location <= textStorage.length {
            attrs = textStorage.attributes(at: selRange.location - 1, effectiveRange: nil)
        } else {
            attrs = textView.typingAttributes
        }
        updateState(from: attrs)
    }

    private func updateState(from attrs: [NSAttributedString.Key: Any]) {
        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            isBold = traits.contains(.bold)
            isItalic = traits.contains(.italic)
            currentHeading = headingLevel(for: font.pointSize)
        } else {
            isBold = false
            isItalic = false
            currentHeading = .body
        }
        isUnderlined = (attrs[.underlineStyle] as? Int ?? 0) != 0
        isBulletList = checkBulletListAtCursor()
        isTodoItem = checkTodoAtCursor()
    }

    private func headingLevel(for size: CGFloat) -> HeadingLevel {
        if size >= 20 { return .h1 }
        if size >= 16 { return .h2 }
        if size >= 14.5 { return .h3 }
        return .body
    }

    private func checkBulletListAtCursor() -> Bool {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return false }
        let string = textStorage.string as NSString
        let paraRange = string.paragraphRange(for: textView.selectedRange())
        let paraText = string.substring(with: paraRange)
        return paraText.hasPrefix("• ") || paraText.hasPrefix("    ◦ ") || paraText.hasPrefix("        ▪ ")
    }

    private func checkTodoAtCursor() -> Bool {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return false }
        let string = textStorage.string as NSString
        let paraRange = string.paragraphRange(for: textView.selectedRange())
        let paraText = string.substring(with: paraRange)
        return paraText.hasPrefix("☐ ") || paraText.hasPrefix("☑ ")
    }

    // MARK: - Formatting Actions

    func toggleBold() {
        guard let textView = textView else { return }
        let range = textView.selectedRange()
        if range.length > 0 {
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            textView.textStorage?.beginEditing()
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                guard let font = value as? NSFont else { return }
                let newFont = toggleBoldTrait(on: font)
                textView.textStorage?.addAttribute(.font, value: newFont, range: attrRange)
            }
            textView.textStorage?.endEditing()
            undoManager?.endUndoGrouping()
            textView.didChangeText()
        } else {
            let font = textView.typingAttributes[.font] as? NSFont ?? defaultFont()
            textView.typingAttributes[.font] = toggleBoldTrait(on: font)
        }
        updateFromSelection()
    }

    func toggleItalic() {
        guard let textView = textView else { return }
        let range = textView.selectedRange()
        if range.length > 0 {
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            textView.textStorage?.beginEditing()
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                guard let font = value as? NSFont else { return }
                let newFont = toggleItalicTrait(on: font)
                textView.textStorage?.addAttribute(.font, value: newFont, range: attrRange)
            }
            textView.textStorage?.endEditing()
            undoManager?.endUndoGrouping()
            textView.didChangeText()
        } else {
            let font = textView.typingAttributes[.font] as? NSFont ?? defaultFont()
            textView.typingAttributes[.font] = toggleItalicTrait(on: font)
        }
        updateFromSelection()
    }

    func toggleUnderline() {
        guard let textView = textView else { return }
        let range = textView.selectedRange()
        if range.length > 0 {
            let current = textView.textStorage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
            let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            textView.textStorage?.addAttribute(.underlineStyle, value: newValue, range: range)
            undoManager?.endUndoGrouping()
            textView.didChangeText()
        } else {
            let current = textView.typingAttributes[.underlineStyle] as? Int ?? 0
            textView.typingAttributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        }
        updateFromSelection()
    }

    func applyHeading(_ level: HeadingLevel) {
        guard let textView = textView else { return }
        let range = paragraphRange(in: textView)
        let newFont: NSFont
        if level == .body {
            newFont = defaultFont()
        } else {
            newFont = defaultBoldFont(size: level.fontSize)
        }
        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()
        textView.textStorage?.addAttribute(.font, value: newFont, range: range)
        undoManager?.endUndoGrouping()
        textView.typingAttributes[.font] = newFont
        currentHeading = level
        textView.didChangeText()
    }

    func toggleBulletList() {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        let range = paragraphRange(in: textView)
        let string = textStorage.string as NSString
        let paragraphText = string.substring(with: range)

        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()

        if isBulletList {
            let lines = paragraphText.components(separatedBy: "\n")
            var newText = ""
            for (i, line) in lines.enumerated() {
                var cleaned = line
                for level in ["        ▪ ", "    ◦ ", "• "] {
                    if cleaned.hasPrefix(level) {
                        cleaned = String(cleaned.dropFirst(level.count))
                        break
                    }
                }
                newText += cleaned
                if i < lines.count - 1 { newText += "\n" }
            }
            if textView.shouldChangeText(in: range, replacementString: newText) {
                textStorage.replaceCharacters(in: range, with: newText)
                textView.didChangeText()
            }
        } else {
            let lines = paragraphText.components(separatedBy: "\n")
            var newText = ""
            for (i, line) in lines.enumerated() {
                if !line.isEmpty {
                    newText += "• " + line
                } else {
                    newText += line
                }
                if i < lines.count - 1 { newText += "\n" }
            }
            if textView.shouldChangeText(in: range, replacementString: newText) {
                textStorage.replaceCharacters(in: range, with: newText)
                textView.didChangeText()
            }
        }

        undoManager?.endUndoGrouping()
        updateFromSelection()
    }

    func toggleTodo() {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        let range = paragraphRange(in: textView)
        let string = textStorage.string as NSString
        let paragraphText = string.substring(with: range)

        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()

        if isTodoItem {
            // Remove todo prefix from each line
            let lines = paragraphText.components(separatedBy: "\n")
            var newText = ""
            for (i, line) in lines.enumerated() {
                var cleaned = line
                if cleaned.hasPrefix("☐ ") || cleaned.hasPrefix("☑ ") {
                    cleaned = String(cleaned.dropFirst(2))
                }
                newText += cleaned
                if i < lines.count - 1 { newText += "\n" }
            }
            if textView.shouldChangeText(in: range, replacementString: newText) {
                textStorage.replaceCharacters(in: range, with: newText)
                let newRange = NSRange(location: range.location, length: (newText as NSString).length)
                textStorage.addAttribute(.strikethroughStyle, value: 0, range: newRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.black, range: newRange)
                textView.didChangeText()
            }
        } else {
            // Add todo prefix to each line with larger checkbox font
            let lines = paragraphText.components(separatedBy: "\n")
            // Do plain text replacement
            var newText = ""
            for (i, line) in lines.enumerated() {
                if !line.isEmpty {
                    newText += "☐ " + line
                } else {
                    newText += line
                }
                if i < lines.count - 1 { newText += "\n" }
            }
            if textView.shouldChangeText(in: range, replacementString: newText) {
                textStorage.replaceCharacters(in: range, with: newText)
                // Now apply larger font to each checkbox character
                let newString = textStorage.string as NSString
                let newRange = NSRange(location: range.location, length: (newText as NSString).length)
                let fullParaRange = newString.paragraphRange(for: newRange)
                applyCheckboxFont(in: fullParaRange, textStorage: textStorage)
                textView.didChangeText()
            }
        }

        undoManager?.endUndoGrouping()
        updateFromSelection()
    }

    /// Toggle checkbox at a specific paragraph location (called on click)
    func toggleCheckboxAt(_ paraStart: Int) {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        let string = textStorage.string as NSString
        let paraRange = string.paragraphRange(for: NSRange(location: paraStart, length: 0))
        let paraText = string.substring(with: paraRange)

        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()

        if paraText.hasPrefix("☐ ") {
            // Check it: ☐ → ☑, strikethrough, gray, push to bottom
            let checkboxRange = NSRange(location: paraRange.location, length: 1)
            textStorage.replaceCharacters(in: checkboxRange, with: "☑")

            // Re-fetch paragraph range after replacement
            let newParaRange = string.paragraphRange(for: NSRange(location: paraRange.location, length: 0))

            // Apply strikethrough to content (not checkbox)
            if newParaRange.length > 2 {
                let contentRange = NSRange(location: newParaRange.location + 2, length: newParaRange.length - 2)
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }
            // Gray out entire line
            textStorage.addAttribute(.foregroundColor, value: NSColor.gray, range: newParaRange)
            // Keep checkbox font large
            let cbRange = NSRange(location: newParaRange.location, length: 1)
            textStorage.addAttribute(.font, value: Self.checkboxFont, range: cbRange)

            textView.didChangeText()

            // Push to bottom
            let updatedParaRange = (textStorage.string as NSString).paragraphRange(for: NSRange(location: paraRange.location, length: 0))
            pushCompletedToBottom(paraRange: updatedParaRange, in: textView)

        } else if paraText.hasPrefix("☑ ") {
            // Uncheck it: ☑ → ☐, remove strikethrough, restore color
            let checkboxRange = NSRange(location: paraRange.location, length: 1)
            textStorage.replaceCharacters(in: checkboxRange, with: "☐")

            let newParaRange = string.paragraphRange(for: NSRange(location: paraRange.location, length: 0))
            textStorage.addAttribute(.strikethroughStyle, value: 0, range: newParaRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.black, range: newParaRange)
            // Keep checkbox font large
            let cbRange = NSRange(location: newParaRange.location, length: 1)
            textStorage.addAttribute(.font, value: Self.checkboxFont, range: cbRange)

            textView.didChangeText()
        }

        undoManager?.endUndoGrouping()
        updateFromSelection()
    }

    private func pushCompletedToBottom(paraRange: NSRange, in textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }

        // Capture the attributed line
        let lineAttr = NSMutableAttributedString(attributedString: textStorage.attributedSubstring(from: paraRange))

        // Strip trailing newline from the captured line
        if lineAttr.string.hasSuffix("\n") {
            lineAttr.deleteCharacters(in: NSRange(location: lineAttr.length - 1, length: 1))
        }

        // Delete the original line (including its newline)
        textStorage.deleteCharacters(in: paraRange)

        // Build insertion: newline if needed + the line
        let insertion = NSMutableAttributedString()
        let endStr = textStorage.string
        if !endStr.isEmpty && !endStr.hasSuffix("\n") {
            insertion.append(NSAttributedString(string: "\n", attributes: [
                .font: defaultFont(),
                .foregroundColor: NSColor.black
            ]))
        }
        insertion.append(lineAttr)

        textStorage.insert(insertion, at: textStorage.length)
        textView.didChangeText()
    }

    /// Apply larger font to checkbox characters (☐/☑) in a range
    func applyCheckboxFont(in range: NSRange, textStorage: NSTextStorage) {
        let string = textStorage.string as NSString
        string.enumerateSubstrings(in: range, options: .byParagraphs) { para, paraRange, _, _ in
            guard let para = para else { return }
            if para.hasPrefix("☐") || para.hasPrefix("☑") {
                let cbRange = NSRange(location: paraRange.location, length: 1)
                textStorage.addAttribute(.font, value: Self.checkboxFont, range: cbRange)
            }
        }
    }

    // MARK: - Helpers

    private func toggleBoldTrait(on font: NSFont) -> NSFont {
        let manager = NSFontManager.shared
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) {
            return manager.convert(font, toNotHaveTrait: .boldFontMask)
        } else {
            return manager.convert(font, toHaveTrait: .boldFontMask)
        }
    }

    private func toggleItalicTrait(on font: NSFont) -> NSFont {
        let manager = NSFontManager.shared
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.italic) {
            return manager.convert(font, toNotHaveTrait: .italicFontMask)
        } else {
            return manager.convert(font, toHaveTrait: .italicFontMask)
        }
    }

    private func paragraphRange(in textView: NSTextView) -> NSRange {
        let string = textView.string as NSString
        return string.paragraphRange(for: textView.selectedRange())
    }
}
