// View+FullWidthCardRow.swift
import SwiftUI

extension View {
    /// Styles a List row to span full width and renders the content inside a card-like background.
    func fullWidthCardRow(
        cornerRadius: CGFloat = 20,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 6
    ) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(radius: 1)
            .listRowInsets(EdgeInsets())                 // remove default List insets so it can be truly full-width
            .listRowSeparator(.hidden)                   // optional: hide separators to match card look
            .listRowBackground(Color.clear)              // let parent background show through
            .padding(.horizontal, horizontalPadding)     // outer margin so the card doesn’t touch screen edges
            .padding(.vertical, verticalPadding)
    }
}
