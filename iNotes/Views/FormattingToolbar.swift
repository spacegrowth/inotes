import SwiftUI

struct FormattingToolbar: View {
    @ObservedObject var editorState: EditorState

    var body: some View {
        HStack(spacing: 2) {
            toolbarIcon(icon: "bold", isActive: editorState.isBold) {
                editorState.toggleBold()
            }
            toolbarIcon(icon: "italic", isActive: editorState.isItalic) {
                editorState.toggleItalic()
            }
            toolbarIcon(icon: "underline", isActive: editorState.isUnderlined) {
                editorState.toggleUnderline()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            headingIcon("H1", level: .h1)
            headingIcon("H2", level: .h2)
            headingIcon("H3", level: .h3)

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            toolbarIcon(icon: "list.bullet", isActive: editorState.isBulletList) {
                editorState.toggleBulletList()
            }
            toolbarIcon(icon: "checklist", isActive: editorState.isTodoItem) {
                editorState.toggleTodo()
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private func refocusEditor() {
        if let textView = editorState.textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    private func toolbarIcon(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: isActive ? .bold : .regular))
            .foregroundColor(isActive ? .primary : .secondary)
            .frame(width: 24, height: 24)
            .background(isActive ? Color.primary.opacity(0.12) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture {
                action()
                refocusEditor()
            }
    }

    private func headingIcon(_ title: String, level: HeadingLevel) -> some View {
        let isActive = editorState.currentHeading == level
        return Text(title)
            .font(.system(size: 11, weight: isActive ? .bold : .medium))
            .foregroundColor(isActive ? .primary : .secondary)
            .frame(width: 24, height: 24)
            .background(isActive ? Color.primary.opacity(0.12) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture {
                // Check state at tap time, not render time
                let currentlyActive = editorState.currentHeading == level
                editorState.applyHeading(currentlyActive ? .body : level)
                refocusEditor()
            }
    }
}
