// TradeTypeSelectionView.swift
import SwiftUI

struct TradeTypeSelectionView: View {
    @Binding var selection: TradeType?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            List {
                ForEach(TradeType.allCases) { type in
                    HStack(spacing: 12) {
                        Text(type.displayName)
                            .foregroundStyle(TBTheme.offWhite)
                        Spacer()
                        if selection == type {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(TBTheme.brand)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = type
                        dismiss()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Select category")
        .navigationBarTitleDisplayMode(.inline)
    }
}
