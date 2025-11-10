// DocumentPreview.swift
import SwiftUI
import QuickLook
import UIKit

struct DocumentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// A SwiftUI wrapper that overlays a top-right "X" close button over the document preview.
struct DocumentPreviewWithClose: View {
    let url: URL

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DocumentPreview(url: url)
                .ignoresSafeArea()
            OverlayCloseButton()
                .padding(.top, 12)
                .padding(.trailing, 12)
        }
    }
}

private struct OverlayCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .contentShape(Circle())
        .padding(4)
    }
}
