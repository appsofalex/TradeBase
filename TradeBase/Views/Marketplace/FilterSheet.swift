//
//  FilterSheet.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct FilterSheet: View {
    @Binding var filter: MarketFilter
    var onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Local text backing for the pay input so we can keep it on one line and parse to Decimal
    @State private var payText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Radius (unchanged)
                Section {
                    Text("Radius")
                        .font(.headline)
                        .foregroundStyle(TBTheme.offWhite)
                    Slider(
                        value: Binding(get: { filter.radiusKm }, set: { filter.radiusKm = $0 }),
                        in: 1...100,
                        step: 1
                    ) { Text("Radius") }
                    Text("\(Int(filter.radiusKm)) km")
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                }

                // Trade: single-line row with label and dropdown menu beside it
                Section {
                    HStack {
                        Text("Trade")
                            .font(.headline)
                            .foregroundStyle(TBTheme.offWhite)
                        Spacer()
                        Picker("", selection: Binding(get: { filter.trade }, set: { filter.trade = $0 })) {
                            Text("Any").tag(TradeType?.none)
                            ForEach(TradeType.allCases) { trade in
                                Text(trade.displayName).tag(TradeType?.some(trade))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(TBTheme.brand)
                    }
                }

                // Pay: single-line row; only the numeric text is green, no colored background
                Section {
                    HStack {
                        Text("Pay")
                            .font(.headline)
                            .foregroundStyle(TBTheme.offWhite)
                        Spacer()
                        HStack(spacing: 6) {
                            Text("£")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TBTheme.offWhiteSecondary)
                            TextField("0", text: $payText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(TBTheme.brand) // numbers only are green
                                .onChange(of: payText) { _, newValue in
                                    updateMinPay(from: newValue)
                                }
                                .frame(minWidth: 40)
                        }
                    }
                }

                // Options (unchanged)
                Section {
                    Text("Options")
                        .font(.headline)
                        .foregroundStyle(TBTheme.offWhite)
                    Toggle("Instant book only",
                           isOn: Binding(get: { filter.instantBookOnly }, set: { filter.instantBookOnly = $0 }))
                    Toggle("Verified only",
                           isOn: Binding(get: { filter.verifiedOnly }, set: { filter.verifiedOnly = $0 }))
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss() // Minimize/close the sheet after applying
                    }
                }
            }
        }
        .onAppear {
            // Seed the pay text from the current filter value
            if let min = filter.minPay {
                payText = NSDecimalNumber(decimal: min).stringValue
            } else {
                payText = ""
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func updateMinPay(from text: String) {
        // Keep only digits and decimal separator; simple sanitization
        let allowed = Set("0123456789.,")
        let cleaned = String(text.filter { allowed.contains($0) })

        // Normalize comma to dot for Decimal(string:) parsing
        let normalized = cleaned.replacingOccurrences(of: ",", with: ".")

        if normalized.isEmpty {
            filter.minPay = nil
            return
        }

        if let dec = Decimal(string: normalized) {
            filter.minPay = dec
        } else {
            // If parsing fails, don’t update the filter; user may still be typing
        }
    }
}
