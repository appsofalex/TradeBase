//
//  AuthComponents.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import AuthenticationServices

// MARK: - Pill Buttons

struct PillButton: View {
    enum Style { case light, brand }
    var title: String
    var style: Style = .brand
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(style == .light ? .black.opacity(0.85) : .white)
                .background(
                    Capsule()
                        .fill(style == .light ? Color.white : TBTheme.brand)
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pill TextFields

struct PillTextField: View {
    var systemImage: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textContentType(.oneTimeCode) // prevents auto-fill banner overlap issues
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
        .foregroundStyle(TBTheme.title)
    }
}

struct PillSecureField: View {
    var systemImage: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            SecureField(placeholder, text: $text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
        .foregroundStyle(TBTheme.title)
    }
}

// MARK: - Social Buttons

enum SocialProvider {
    case apple, google, custom(String)
}

struct SocialButton: View {
    enum Emphasis { case light, dark }
    var provider: SocialProvider
    var title: String
    var emphasis: Emphasis = .light
    var action: () async throws -> Void

    @State private var isLoading = false
    @State private var localError: String?

    var body: some View {
        Button {
            Task {
                isLoading = true
                localError = nil
                do {
                    try await action()
                } catch {
                    if !isUserCancelledAuth(error) {
                        localError = error.localizedDescription
                    }
                }
                isLoading = false
            }
        } label: {
            ZStack {
                // Leading icon + trailing spinner
                HStack(spacing: 12) {
                    providerIcon
                        .frame(width: 20, height: 20)
                    Spacer()
                    if isLoading { ProgressView().tint(emphasis == .dark ? .white : .black) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)

                // Centered title
                Text(title)
                    .font(.headline)
                    .foregroundStyle(emphasis == .dark ? .white : .black.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(emphasis == .dark ? Color.black : Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if let localError {
                Text(localError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch provider {
        case .apple:
            // Sign-up screen uses the standard appleLogo
            Image("appleLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        case .google:
            Image("googleLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        case .custom(let systemName):
            Image(systemName: systemName)
                .resizable()
                .scaledToFit()
        }
    }
}

struct SocialIconButton: View {
    var provider: SocialProvider
    var action: () async throws -> Void
    @State private var loading = false
    @State private var localError: String?

    private let visualSizeGoogle: CGFloat = 24   // baseline visual size
    private let visualSizeApple: CGFloat = 30    // larger to offset intrinsic padding
    private let visualSizeX: CGFloat = 28        // matches previous tweak

    var body: some View {
        Button {
            Task {
                loading = true
                localError = nil
                do {
                    try await action()
                } catch {
                    if !isUserCancelledAuth(error) {
                        localError = error.localizedDescription
                    }
                }
                loading = false
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 64, height: 44)
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 4)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if loading {
                    ProgressView().tint(.black)
                } else {
                    icon
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if let localError {
                Text(localError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch provider {
        case .apple:
            Image("appleLogo2")
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: visualSizeApple, height: visualSizeApple)
        case .google:
            Image("googleLogo")
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: visualSizeGoogle, height: visualSizeGoogle)
        case .custom(let name):
            if name.lowercased() == "xmark" {
                Image("XLogo")
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: visualSizeX, height: visualSizeX)
            } else {
                Image(systemName: name)
                    .imageScale(.large)
                    .foregroundStyle(.black)
            }
        }
    }
}

// MARK: - Divider

struct DividerWithText: View {
    var text: String
    var body: some View {
        HStack {
            Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1)
            Text(text)
                .foregroundStyle(TBTheme.offWhiteSecondary)
                .padding(.horizontal, 8)
            Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1)
        }
    }
}

// MARK: - Shared cancel filtering for social buttons

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
