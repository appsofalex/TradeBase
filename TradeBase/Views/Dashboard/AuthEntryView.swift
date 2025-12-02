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
        case onboarding
        case gatedModal
    }

    @Environment(\.appState) private var state
    @Environment(\.dismiss) private var dismiss

    let presentation: Presentation
    let hideGuestSkip: Bool

    @State private var isLoading = false
    @State private var error: String?

    init(presentation: Presentation = .onboarding, hideGuestSkip: Bool = false) {
        self.presentation = presentation
        self.hideGuestSkip = hideGuestSkip
    }

    var body: some View {
        Group {
            if presentation == .gatedModal {
                NavigationStack { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Removed the spacer here so the logo sits at the very top.
                
                Image("logowithoutbg")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 90)
                    .padding(.top, 10) // Small padding to avoid touching the island directly
                    .offset(y: -20) // Move logo slightly higher without affecting layout flow
                    .accessibilityLabel("TradeBase Logo")
                
                // Added spacer to push the title down significantly, centering it between logo and footer
                Spacer()

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
                .offset(y: -40) // Shift headline up slightly

                Spacer()

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

                if !hideGuestSkip {
                    Button {
                        Task {
                            isLoading = true
                            state.navigationDirection = .forward
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

                Color.clear
                    .frame(height: 8)
                    .padding(.bottom, 6)
            }
            .overlay {
                if isLoading { ProgressView().controlSize(.large) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if presentation == .gatedModal {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
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
        // Dismiss the gated modal only after successful authentication.
        .onChange(of: state.isAuthenticated) { newValue, _ in
            if presentation == .gatedModal, newValue {
                dismiss()
            }
        }
    }

    private func social(_ action: @escaping () async throws -> Void) async {
        error = nil
        isLoading = true
        do {
            try await action()
            if presentation == .gatedModal {
                dismiss()
            }
        } catch {
            if isUserCancelledAuth(error) {
                // ignore
            } else {
                self.error = error.localizedDescription
            }
        }
        isLoading = false
    }

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

// MARK: - Helper view
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
