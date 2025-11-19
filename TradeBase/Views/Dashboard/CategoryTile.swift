import SwiftUI

// Category fallback tile used when a lead has no photos.
// Shared so multiple views (Leads, Dashboard, etc.) can use it.
struct CategoryTile: View {
    let trade: TradeType?

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        switch trade {
        case .electrician:      return [Color.yellow.opacity(0.55), Color.orange.opacity(0.70)]
        case .plumber:          return [Color.cyan.opacity(0.60), Color.blue.opacity(0.70)]
        case .carpenter:        return [Color.brown.opacity(0.60), Color.orange.opacity(0.60)]
        case .roofer:           return [Color.gray.opacity(0.55), Color.blue.opacity(0.60)]
        case .painter:          return [Color.purple.opacity(0.60), Color.pink.opacity(0.60)]
        case .hvac:             return [Color.teal.opacity(0.60), Color.blue.opacity(0.65)]
        case .tiler:            return [Color.green.opacity(0.60), Color.teal.opacity(0.60)]
        case .landscaper:       return [Color.green.opacity(0.65), Color.mint.opacity(0.65)]
        case .generalBuilder:   return [TBTheme.brand, TBTheme.brandMuted]
        case .windowsAndDoors:  return [Color.indigo.opacity(0.60), Color.blue.opacity(0.65)]
        case .none:             return [TBTheme.brand, TBTheme.brandMuted]
        }
    }

    private var symbol: String {
        switch trade {
        case .electrician:      return "bolt.fill"
        case .plumber:          return "wrench.adjustable"
        case .carpenter:        return "hammer"
        case .roofer:           return "house.fill"
        case .painter:          return "paintbrush.pointed.fill"
        case .hvac:             return "fanblades"
        case .tiler:            return "square.grid.3x3.fill"
        case .landscaper:       return "leaf.fill"
        case .generalBuilder:   return "wrench.and.screwdriver"
        case .windowsAndDoors:  return "door.left.hand.closed"
        case .none:             return "wrench.and.screwdriver"
        }
    }
}
