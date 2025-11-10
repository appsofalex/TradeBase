import SwiftUI

struct CertificationRow: View {
    let cert: Certification
    var onTap: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: cert.fileURL == nil ? "doc" : "doc.text")
                .foregroundStyle(TBTheme.brand)

            VStack(alignment: .leading, spacing: 2) {
                Text(cert.title)
                    .font(.headline)
                    .foregroundStyle(TBTheme.title)

                HStack(spacing: 0) {
                    Text(cert.issuer)
                    Text(" • ")
                    // Render as a plain string to avoid any locale grouping (e.g., "2,025")
                    Text("\(cert.year)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Preview", systemImage: "eye")
            }
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            // Keep only Rename here; the red destructive Delete is provided by the parent view.
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}
