import AppKit
import SwiftUI

/// The clipboard History window: searches every kept entry. Double-click (or Return) copies an entry
/// back onto the clipboard.
struct ClipboardHistoryView: View {
    let clipboard: ClipboardProvider
    /// Called after an entry is copied, so the window can get out of the way.
    let didCopy: () -> Void

    @State private var query = ""
    @State private var selection: UUID?

    private var results: [ClipboardEntry] {
        clipboard.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $query, prompt: Text("Search clipboard history"))
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .onSubmit(copySelection)

            Divider()

            if results.isEmpty {
                Text(clipboard.history.isEmpty ? "Nothing copied yet." : "No matches.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results, selection: $selection) { entry in
                    ClipboardHistoryRow(entry: entry, thumbnail: clipboard.thumbnails[entry.id])
                        .tag(entry.id)
                        .contextMenu { menu(for: entry) }
                }
                .contextMenu(forSelectionType: UUID.self) { _ in
                } primaryAction: { ids in
                    if let id = ids.first { copy(id) }
                }
                .task(id: query) { clipboard.loadThumbnails(for: Array(results.prefix(50))) }
            }

            Divider()

            HStack {
                Text(results.count == 1 ? "1 item" : "\(results.count) items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Unpinned") { clipboard.clearHistory(includingPinned: false) }
                    .disabled(!clipboard.history.entries.contains { !$0.isPinned })
            }
            .padding(10)
        }
        .frame(width: 440, height: 480)
    }

    @ViewBuilder
    private func menu(for entry: ClipboardEntry) -> some View {
        Button("Copy") { copy(entry.id) }
        Button(entry.isPinned ? "Unpin" : "Pin") { clipboard.setPinned(!entry.isPinned, for: entry.id) }
        Divider()
        Button("Delete", role: .destructive) { clipboard.delete(entry.id) }
    }

    private func copySelection() {
        if let id = selection ?? results.first?.id { copy(id) }
    }

    private func copy(_ id: UUID) {
        clipboard.copy(id)
        didCopy()
    }
}

private struct ClipboardHistoryRow: View {
    let entry: ClipboardEntry
    let thumbnail: Data?

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.preview)
                    .font(entry.kind == .code ? .body.monospaced() : .body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if let name = entry.sourceName { Text(name) }
                    Text(entry.copiedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail, let image = NSImage(data: thumbnail) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if case .color(let color, _) = entry.content {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
        } else {
            Image(systemName: entry.kind.symbolName)
                .foregroundStyle(.secondary)
        }
    }
}
