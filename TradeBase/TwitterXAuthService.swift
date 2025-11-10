//
//  TwitterXAuthService.swift
//  TradeBase
//
//  Created by Alex Walters on 19/09/2025.
//

import Foundation
import AuthenticationServices
import UIKit
import Security
import CommonCrypto

@MainActor
enum TwitterXAuthService {

    struct Tokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let tokenType: String?
        let scope: String?
    }

    struct User: Codable {
        let id: String
        let name: String
        let username: String?
        let profileImageURL: URL?
    }

    // MARK: - Configuration

    // Provided by you
    static let clientID = "N3VDUS1lYmpFNXhqSFA4bHB4Q3k6MTpjaQ"
    static let redirectURI = "tradebase://auth/x/callback"
    static let callbackScheme = "tradebase"

    // Scopes to request
    static let scopes = ["users.read", "tweet.read", "offline.access"]

    // Endpoints
    static let authorizeURL = URL(string: "https://twitter.com/i/oauth2/authorize")!
    static let tokenURL = URL(string: "https://api.twitter.com/2/oauth2/token")!
    static let meURL = URL(string: "https://api.twitter.com/2/users/me?user.fields=profile_image_url")!

    // State/callback plumbing
    private static var pendingSession: ASWebAuthenticationSession?
    private static var pendingState: String?
    private static var continuation: CheckedContinuation<URL, Error>?

    // MARK: - Public API

    static func signIn() async throws -> (Tokens, User?) {
        let (code, verifier) = try await authorize()
        let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier)
        // Fetch lightweight profile (optional)
        let user = try await fetchMe(accessToken: tokens.accessToken)
        // Persist tokens
        try persist(tokens: tokens)
        return (tokens, user)
    }

    static func signOut() {
        KeychainStore.remove("x_access_token")
        KeychainStore.remove("x_refresh_token")
    }

    // Called from TradeBaseApp.onOpenURL
    static func handleRedirectURL(_ url: URL) {
        // Resume continuation if the scheme matches
        guard url.scheme?.lowercased() == callbackScheme else { return }
        continuation?.resume(returning: url)
        continuation = nil
    }

    // MARK: - OAuth steps

    private static func authorize() async throws -> (code: String, verifier: String) {
        let state = randomURLSafeString(length: 32)
        let verifier = randomURLSafeString(length: 64)
        let challenge = codeChallenge(from: verifier)

        var comps = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        let authURL = comps.url!

        pendingState = state

        let callbackURL = try await startWebAuth(url: authURL)

        // Validate state and extract code
        guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
            throw AuthError.invalidCallback
        }
        if let error = items.first(where: { $0.name == "error" })?.value {
            if error == "access_denied" {
                throw AuthError.userCanceled
            }
            throw AuthError.authorizationFailed(error)
        }
        guard
            let code = items.first(where: { $0.name == "code" })?.value,
            let returnedState = items.first(where: { $0.name == "state" })?.value,
            returnedState == state
        else {
            throw AuthError.stateMismatch
        }
        return (code, verifier)
    }

    private static func exchangeCodeForTokens(code: String, verifier: String) async throws -> Tokens {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "code": code
        ]
        req.httpBody = urlEncoded(bodyParams).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.network }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(text)")
        }

        struct TokenResponse: Decodable {
            let token_type: String
            let expires_in: Int?
            let access_token: String
            let scope: String?
            let refresh_token: String?
        }
        let decoder = JSONDecoder()
        let tr = try decoder.decode(TokenResponse.self, from: data)
        return Tokens(
            accessToken: tr.access_token,
            refreshToken: tr.refresh_token,
            expiresIn: tr.expires_in,
            tokenType: tr.token_type,
            scope: tr.scope
        )
    }

    private static func fetchMe(accessToken: String) async throws -> User? {
        var req = URLRequest(url: meURL)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else { return nil }

        struct MeResponse: Decodable {
            struct DataObj: Decodable {
                let id: String
                let name: String
                let username: String?
                let profile_image_url: String?
            }
            let data: DataObj
        }
        let me = try JSONDecoder().decode(MeResponse.self, from: data).data
        return User(
            id: me.id,
            name: me.name,
            username: me.username,
            profileImageURL: me.profile_image_url.flatMap(URL.init(string:))
        )
    }

    private static func persist(tokens: Tokens) throws {
        try KeychainStore.set(Data(tokens.accessToken.utf8), for: "x_access_token")
        if let rt = tokens.refreshToken {
            try KeychainStore.set(Data(rt.utf8), for: "x_refresh_token")
        }
    }

    // MARK: - ASWebAuthenticationSession

    private static func startWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                pendingSession = nil
                pendingState = nil
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    cont.resume(throwing: AuthError.userCanceled)
                    continuation = nil
                    return
                }
                if let error {
                    cont.resume(throwing: error)
                    continuation = nil
                    return
                }
                guard let callbackURL else {
                    cont.resume(throwing: AuthError.invalidCallback)
                    continuation = nil
                    return
                }
                cont.resume(returning: callbackURL)
                continuation = nil
            }
            session.prefersEphemeralWebBrowserSession = true
            // Present from key window if possible
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first(where: { $0.isKeyWindow }) {
                session.presentationContextProvider = SimplePresentationContextProvider(anchor: window)
            }
            pendingSession = session
            session.start()
        }
    }

    // MARK: - Utilities & errors

    enum AuthError: LocalizedError, Equatable {
        case userCanceled
        case invalidCallback
        case stateMismatch
        case authorizationFailed(String)
        case tokenExchangeFailed(String)
        case network

        var errorDescription: String? {
            switch self {
            case .userCanceled: return "Sign in was canceled."
            case .invalidCallback: return "Invalid redirect back from X."
            case .stateMismatch: return "Security check failed (state mismatch)."
            case .authorizationFailed(let s): return "Authorization failed: \(s)"
            case .tokenExchangeFailed(let s): return "Token exchange failed: \(s)"
            case .network: return "Network error."
            }
        }
    }

    private static func urlEncoded(_ params: [String: String]) -> String {
        params.map { k, v in
            let kE = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let vE = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(kE)=\(vE)"
        }.joined(separator: "&")
    }

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if result == errSecSuccess {
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        } else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
    }

    private static func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Presentation context

private final class SimplePresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var anchorWindow: UIWindow?
    init(anchor: UIWindow) { self.anchorWindow = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchorWindow ?? ASPresentationAnchor()
    }
}

