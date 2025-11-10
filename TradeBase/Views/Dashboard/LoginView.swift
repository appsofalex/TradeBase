//
//  LoginView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 24)
                    Text("Welcome back")
                        .font(.largeTitle.bold())
                        .foregroundStyle(TBTheme.offWhite)
                        .padding(.top, 12)

                    Text("Use Apple or Google to sign in")
                        .foregroundStyle(TBTheme.offWhiteSecondary)

                    VStack(spacing: 14) {
                        SocialButton(provider: .google, title: "Continue with Google") {
                            await social {
                                try await state.signInWithGoogle()
                                dismiss()
                            }
                        }
                        SocialButton(provider: .apple, title: "Continue with Apple", emphasis: .dark) {
                            await social {
                                try await state.signInWithApple()
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }

                    Spacer(minLength: 24)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 1) // keeps the home indicator space tidy
            }
            .overlay { if isLoading { ProgressView().controlSize(.large) } }
        }
        // Always-visible top-right close button
        .overlay(alignment: .topTrailing) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(TBTheme.offWhite)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.28))
                                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
            .ignoresSafeArea(edges: .top) // place within safe area padding above content
        }
    }

    private func social(_ run: @escaping () async throws -> Void) async {
        errorMessage = nil
        isLoading = true
        do {
            try await run()
        } catch {
            if isUserCancelledAuth(error) {
                // Don’t show an error for user-initiated cancel.
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    // MARK: - Cancel filtering

    private func isUserCancelledAuth(_ error: Error) -> Bool {
        if let authErr = error as? ASAuthorizationError, authErr.code == .canceled {
            return true
        }
        if let webAuthErr = error as? ASWebAuthenticationSessionError, webAuthErr.code == .canceledLogin {
            return true
        }
        let ns = error as NSError
        if ns.domain == ASWebAuthenticationSessionError.errorDomain,
           ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return true
        }
        if case TwitterXAuthService.AuthError.userCanceled = error {
            return true
        }
        return false
    }
}
