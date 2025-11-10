//
//  FilterSheet.swift
//  TradeBase
//

import SwiftUI

struct FilterSheet: View {
    @Binding var filter: MarketFilter
    var onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Radius") {
                    Slider(value: Binding(
                        get: { filter.radiusKm },
                        set: { filter.radiusKm = $0 }
                    ), in: 5...100, step: 5) {
                        Text("Radius")
                    }
                    HStack {
                        Text("Up to")
                        Spacer()
                        Text("\(Int(filter.radiusKm)) km")
                    }
                }
                Section("Trade") {
                    Picker("Trade", selection: Binding(
                        get: { filter.trade },
                        set: { filter.trade = $0 }
                    )) {
                        Text("Any").tag(TradeType?.none)
                        ForEach(TradeType.allCases) { t in
                            Text(t.displayName).tag(TradeType?.some(t))
                        }
                    }
                }
                Section("Options") {
                    Toggle("Instant book only", isOn: Binding(
                        get: { filter.instantBookOnly },
                        set: { filter.instantBookOnly = $0 }
                    ))
                    Toggle("Verified only", isOn: Binding(
                        get: { filter.verifiedOnly },
                        set: { filter.verifiedOnly = $0 }
                    ))
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
