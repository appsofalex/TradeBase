// JobPostedSuccessView.swift
import SwiftUI
import UIKit

struct JobPostedSuccessView: View {
    var title: String = "Your job is live!"
    var message: String = "Tradespeople can now see your job. We’ll notify you as they show interest."
    var tips: [String] = [
        "Keep your phone nearby — we’ll send notifications when tradespeople reach out.",
        "Check profiles and reviews before accepting.",
        "Respond promptly to messages to secure a booking.",
        "Add more photos if anything changes."
    ]
    var primaryActionTitle: String = "View my job"
    var primaryAction: () -> Void
    var secondaryActionTitle: String? = "Done"
    var secondaryAction: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var animateIn = false

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            VStack(spacing: 20) {
                // Big animated checkmark
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TBTheme.brand)
                    .font(.system(size: 96, weight: .semibold))
                    .scaleEffect(animateIn ? 1.0 : 0.6)
                    .opacity(animateIn ? 1.0 : 0.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75, blendDuration: 0.2), value: animateIn)
                    .padding(.top, 16)

                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(TBTheme.title)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(TBTheme.subtext)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                // Tips list
                if !tips.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(tips, id: \.self) { tip in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(TBTheme.brandMuted)
                                Text(tip)
                                    .foregroundStyle(TBTheme.title)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 6)
                    .frame(maxWidth: 520, alignment: .leading)
                }

                Spacer(minLength: 16)

                // Actions
                VStack(spacing: 12) {
                    PillButton(title: primaryActionTitle, style: .brand) {
                        primaryAction()
                    }
                    if let secondaryActionTitle, let secondaryAction {
                        PillButton(title: secondaryActionTitle, style: .light) {
                            secondaryAction()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            // Success haptic + animate in
            #if os(iOS)
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
            #endif
            animateIn = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(message)")
    }
}
