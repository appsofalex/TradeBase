//
//  CurrencyCatalog.swift
//  TradeBase
//

import Foundation

struct CurrencyOption: Identifiable, Hashable {
    var code: String
    var symbol: String
    var localizedName: String
    var id: String { code }
}

enum CurrencyCatalog {
    // Pinned favorites at the top, in order
    private static let pinned = ["GBP", "EUR", "USD"]

    // Single, fixed English locale for all user-facing currency names/symbols
    private static let englishLocale = Locale(identifier: "en_GB")

    // Build once and cache
    static let all: [CurrencyOption] = {
        // Gather unique currency codes from all available locales
        var seen = Set<String>()
        var codes: [String] = []

        for id in Locale.availableIdentifiers {
            let loc = Locale(identifier: id)
            if let code = loc.currencyCode, !code.isEmpty, !seen.contains(code) {
                seen.insert(code)
                codes.append(code)
            }
        }

        // Ensure pinned exist even if not discovered via locales (defensive)
        for code in pinned where !seen.contains(code) {
            seen.insert(code)
            codes.append(code)
        }

        // Build options using the fixed English locale for name and symbol
        let options: [CurrencyOption] = codes.map { code in
            let name = englishLocale.localizedString(forCurrencyCode: code) ?? code
            let symbol = symbol(for: code, in: englishLocale)
            return CurrencyOption(code: code, symbol: symbol, localizedName: name)
        }

        // Sort: pinned first (in given order), then A–Z by code
        let pinnedSet = Set(pinned)
        return options.sorted { lhs, rhs in
            switch (pinnedSet.contains(lhs.code), pinnedSet.contains(rhs.code)) {
            case (true, false): return true
            case (false, true): return false
            default: return lhs.code < rhs.code
            }
        }
    }()

    static func symbol(for code: String) -> String {
        // Try to find in our list
        if let opt = all.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) {
            return opt.symbol
        }
        // Fallback with fixed English locale
        return symbol(for: code, in: englishLocale)
    }

    // MARK: - Internals

    private static func symbol(for code: String, in locale: Locale) -> String {
        // Prefer NumberFormatter with fixed locale
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.locale = locale
        nf.currencyCode = code.uppercased()

        if let sym = nf.currencySymbol, !sym.isEmpty, sym != code.uppercased() {
            return sym
        }
        // Final fallback to a small hand map, then code
        switch code.uppercased() {
        case "GBP": return "£"
        case "EUR": return "€"
        case "USD": return "$"
        default:    return code.uppercased()
        }
    }
}

private extension Locale {
    // Keep if you need it elsewhere; not used now for names/symbols
    func currencySymbol(for code: String) -> String? {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.locale = self
        nf.currencyCode = code
        return nf.currencySymbol
    }
}
