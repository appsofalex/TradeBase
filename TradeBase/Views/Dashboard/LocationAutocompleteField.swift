// LocationAutocompleteField.swift
import SwiftUI
import MapKit

struct LocationAutocompleteField: View {
    @Binding var text: String
    var placeholder: String = "City or postcode"
    var regionBias: MKCoordinateRegion? = nil
    var onSelected: (LocationSearchService.LocationResult) -> Void

    @StateObject private var search = LocationSearchService()
    @FocusState private var focused: Bool
    @State private var isResolving = false

    // We overlay the suggestions below the field and cap the height to 6 rows.
    @State private var fieldHeight: CGFloat = 0
    private let maxVisibleRows: Int = 6
    private let rowHeight: CGFloat = 56

    private struct HeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The input stays in the normal layout (keeps your screen centered).
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.words)
                        .focused($focused)
                        .onChange(of: text) { _, newValue in
                            search.query = newValue
                        }
                    if !text.isEmpty {
                        Button {
                            text = ""
                            search.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
                    }
                )
            }

            // Overlayed, scrollable suggestions that do not push surrounding layout.
            if focused && !text.isEmpty && !search.suggestions.isEmpty {
                let visibleHeight = min(CGFloat(search.suggestions.count) * rowHeight,
                                        CGFloat(maxVisibleRows) * rowHeight)

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(search.suggestions, id: \.self) { s in
                            Button {
                                Task { await pick(s) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title)
                                        .foregroundStyle(TBTheme.title)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    if !s.subtitle.isEmpty {
                                        Text(s.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .frame(height: rowHeight) // uniform row height
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.2)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: visibleHeight) // cap to 6 rows; scroll beyond
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 6)
                .offset(y: fieldHeight + 8) // appear just under the field
                .zIndex(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onPreferenceChange(HeightPreferenceKey.self) { fieldHeight = $0 }
        .onAppear {
            search.regionBias = regionBias
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            let result = try await search.resolve(completion)
            // Prefer locality (city), else use completion title.
            text = result.locality ?? result.title
            focused = false
            onSelected(result)
            // Clear suggestions
            search.suggestions = []
        } catch {
            // Fallback: set title anyway
            text = completion.title
            focused = false
            search.suggestions = []
        }
    }
}
