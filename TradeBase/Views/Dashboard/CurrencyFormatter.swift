//
//  CurrencyFormatter.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

func currency(_ money: Money) -> String {
    // Convert Decimal to a Double safely for formatting purposes.
    // For display, minor precision loss is acceptable; underlying model keeps Decimal.
    let amountAsDouble = (money.amount as NSDecimalNumber).doubleValue

    // Try using the modern FormatStyle API with ISO currency codes where available.
    if #available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *) {
        // Pass the ISO 4217 code directly.
        return amountAsDouble.formatted(.currency(code: money.currency))
    }

    // Fallback to NumberFormatter for older platforms or invalid codes.
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency

    // Best-effort mapping: if money.currency is an ISO 4217 code, try to set it.
    // Note: Not all platforms honor currencyCode while also setting locale symbol.
    formatter.currencyCode = money.currency

    // If the currency symbol can't be resolved from the code, you can optionally
    // set a default symbol for GBP to keep UI consistent.
    if money.currency.uppercased() == "GBP" && (formatter.currencySymbol?.isEmpty ?? true) {
        formatter.currencySymbol = "£"
    }

    return formatter.string(from: NSNumber(value: amountAsDouble)) ?? "\(money.amount)"
}
