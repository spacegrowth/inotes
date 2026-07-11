import SwiftUI

/// Thin, secondary-style status row for the bottom of the editor: a live
/// word/char count over the note's plain markdown source, and a relative
/// "edited N ago" timestamp from `lastModified`.
struct StatusFooterView: View {
    let text: String
    let lastModified: Date

    /// Ticks so the relative timestamp keeps advancing ("2m ago" → "3m ago")
    /// even while the user isn't typing.
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var wordCount: Int { TextEditorLogic.wordCount(text) }
    private var charCount: Int { TextEditorLogic.charCount(text) }

    private var relativeStatus: String {
        let interval = now.timeIntervalSince(lastModified)
        if interval < 5 { return "edited just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "edited \(formatter.localizedString(for: lastModified, relativeTo: now))"
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(wordCount) words · \(charCount) chars")
            Spacer()
            Text(relativeStatus)
        }
        .font(.system(size: 9))
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .onReceive(timer) { now = $0 }
        .onAppear { now = Date() }
    }
}
