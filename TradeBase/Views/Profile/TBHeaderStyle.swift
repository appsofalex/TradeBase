import SwiftUI

struct TBLargeHeader: ViewModifier {
    let top: CGFloat
    let horizontal: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .frame(maxWidth: .infinity, alignment: .leading)
            // Use safe-area inset so the header can sit close to the Dynamic Island like Profile
            .padding(.top, top)
            .padding(.horizontal, horizontal)
            .padding(.bottom, 2)
    }
}

extension View {
    // Adjusted default horizontal inset from 18 -> 16 to align headers uniformly to the left.
    // You can still override: .tbLargeHeader(horizontal: 18) if needed on a specific screen.
    func tbLargeHeader(top: CGFloat = 10, horizontal: CGFloat = 16) -> some View {
        self.modifier(TBLargeHeader(top: top, horizontal: horizontal))
    }
}
