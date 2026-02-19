import SwiftUI

struct TabBarView: View {
    @Binding var selectedIndex: Int
    @Binding var notes: [Note]
    @State private var editingIndex: Int? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(notes.enumerated()), id: \.offset) { index, _ in
                TabItemView(
                    title: $notes[index].title,
                    isSelected: selectedIndex == index,
                    isEditing: Binding(
                        get: { editingIndex == index },
                        set: { editing in editingIndex = editing ? index : nil }
                    ),
                    onSelect: { selectedIndex = index }
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

struct TabItemView: View {
    @Binding var title: String
    let isSelected: Bool
    @Binding var isEditing: Bool
    let onSelect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            if isEditing {
                TextField("", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit { isEditing = false }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { isEditing = false }
                    }
                    .onAppear { isFocused = true }
            } else {
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
        }
        .foregroundColor(isSelected ? Color(nsColor: NSColor(white: 0.25, alpha: 1.0)) : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onSelect()
            isEditing = true
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
    }
}
