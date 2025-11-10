// NotificationBellView.swift
import SwiftUI

struct NotificationBellView: View {
    let unreadCount: Int
    var color: Color = TBTheme.offWhite

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                .imageScale(.large)
                .foregroundStyle(color)

            if unreadCount > 0 {
                Text("\(min(unreadCount, 99))")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                    .foregroundStyle(.white)
                    .offset(x: 8, y: -6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: unreadCount)
        .accessibilityLabel(unreadCount > 0 ? "Messages, \(unreadCount) unread" : "Messages")
    }
}
