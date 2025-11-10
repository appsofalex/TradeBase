//
//  AuthEntryView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import AuthenticationServices

struct AuthEntryView: View {
    enum Presentation {
        case onboarding      // first-time entry (no left control per request)
        case gatedModal      // presented from a feature gate (show native-like X at top-right)
    }

    @Environment(\.appState) private var state
    @Environment(\.dismiss) private var dismiss

    // Default keeps existing behavior in RootView and elsewhere.
    let presentation: Presentation

    // When true, the guest “Skip sign in for now” option is hidden.
    // Use this for the customer job-posting gate while in guest mode.
    let hideGuestSkip: Bool

    @State private var isLoading = false
    @State private var error: String?

    init(presentation: Presentation = .onboarding, hideGuestSkip: Bool = false) {
        self.presentation = presentation
        self.hideGuestSkip = hideGuestSkip
    }

    var body: some View {
        // Ensure a navigation container exists when we want a toolbar close button
        Group {
            if presentation == .gatedModal {
                NavigationStack { content }
            } else {
                content
            }
        }
    }

    // Extracted to keep layout identical in both modes
    private var content: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            // Content anchored toward the bottom like the reference screenshot.
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Centered headline: small "Welcome to" above large "TradeBase"
                VStack(spacing: 6) {
                    Text("Welcome to")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                    Text("TradeBase")
                        .font(.system(size: 52, weight: .heavy))
                        .foregroundStyle(TBTheme.offWhite)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                Spacer() // Push actions to the bottom

                // Helper copy just above the auth buttons
                Text("Sign up or log in using a service below")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TBTheme.offWhiteSecondary)
                    .padding(.horizontal)
                    .padding(.bottom, 10)

                VStack(spacing: 14) {
                    SocialButton(provider: .google, title: "Continue with Google") {
                        await social { try await state.signInWithGoogle() }
                    }
                    SocialButton(provider: .apple, title: "Continue with Apple", emphasis: .dark) {
                        await social { try await state.signInWithApple() }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 6)

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }

                // Guest option on unified entry (conditionally hidden for specific gates)
                if !hideGuestSkip {
                    Button {
                        Task {
                            isLoading = true
                            // Flip the handoff animation direction for guest continue
                            state.navigationDirection = .back
                            await state.continueAsGuest()
                            isLoading = false
                            if presentation == .gatedModal {
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Skip sign in for now")
                            .foregroundStyle(TBTheme.offWhite)
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 18)
                }

                // Provide breathing room above the home indicator
                Color.clear
                    .frame(height: 8)
                    .padding(.bottom, 6)
            }
            .overlay {
                if isLoading { ProgressView().controlSize(.large) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // We’re not pushing on a stack when arriving from role choice, so we provide our own back.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if presentation == .gatedModal {
                // Top-right circular X (system toolbar button with xmark image)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel("Close")
                }
            } else {
                // Show a native-looking back button that returns to the role picker
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // Simulate a back navigation by clearing the role
                        state.navigationDirection = .back
                        state.selectedRole = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        // Auto-dismiss this gated modal the moment any auth succeeds.
        .onChange(of: state.authProvider) { newProvider, _ in
            if presentation == .gatedModal, newProvider != nil {
                dismiss()
            }
        }
    }

    // MARK: - Social wrapper with cancel filtering

    private func social(_ action: @escaping () async throws -> Void) async {
        error = nil
               isLoading = true
        do {
            try await action()
            // Flip the handoff animation direction for Apple/Google success
            state.navigationDirection = .back
            if presentation == .gatedModal {
                dismiss()
            }
        } catch {
            if isUserCancelledAuth(error) {
                // Ignore user-initiated cancel
            } else {
                self.error = error.localizedDescription
            }
        }
        isLoading = false
    }

    // MARK: - Cancel filtering (matches LoginView)

    private func isUserCancelledAuth(_ error: Error) -> Bool {
        if let authErr = error as? ASAuthorizationError, authErr.code == .canceled { return true }
        if let webAuthErr = error as? ASWebAuthenticationSessionError, webAuthErr.code == .canceledLogin { return true }
        let ns = error as NSError
        if ns.domain == ASWebAuthenticationSessionError.errorDomain,
           ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return true }
        if case TwitterXAuthService.AuthError.userCanceled = error { return true }
        return false
    }
}

// MARK: - Helper view to place a control just below the top safe area, aligned leading
private struct SafeAreaInsetTopLeading<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack {
            content
                .padding(.leading, 16)
                .padding(.top, 12)
            Spacer()
        }
    }
}

