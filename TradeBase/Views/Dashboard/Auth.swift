// AppState+Auth.swift

import Foundation
import AuthenticationServices
import GoogleSignIn
import UIKit
import ObjectiveC

extension AppState {

    // Google

    @MainActor
    func signInWithGoogle() async throws {
        guard let presenter = Self.topViewController() else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to find a presenter for Google Sign-In."])
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            let user = result.user

            // Persist a stable Google subject/userID if provided
            if let subject = user.userID, !subject.isEmpty {
                UserDefaults.standard.set(subject, forKey: "google_user_id")
            }

            // Update app auth state
            self.authProvider = .google
            self.authEmail = user.profile?.email
            self.isAuthenticated = true

            // Hydrate state for this identity (loads profile/inbox, mirrors to CloudKit if available).
            await load()
        } catch {
            let ns = error as NSError
            // Map Google "canceled" to ASAuthorizationError.canceled so UI suppresses it.
            if ns.domain == "com.google.GIDSignIn", ns.code == -5 {
                throw ASAuthorizationError(.canceled)
            }
            throw error
        }
    }

    // Apple

    @MainActor
    func signInWithApple() async throws {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let credential = try await Self.performAppleSignIn(request: request)

        guard let appleCred = credential as? ASAuthorizationAppleIDCredential else {
            throw NSError(domain: "Auth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credentials."])
        }

        let userID = appleCred.user

        // Persist a stable Apple user identifier for identity building.
        try? KeychainStore.set(Data(userID.utf8), for: "apple_user_id")
        UserDefaults.standard.set(userID, forKey: "apple_user_id")

        // Email is only provided on first grant.
        if let email = appleCred.email {
            self.authEmail = email
        }

        self.authProvider = .apple
        self.isAuthenticated = true
    }

    // MARK: - Private helpers

    @MainActor
    private static func performAppleSignIn(request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationCredential {
        try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleAuthDelegate { result in
                switch result {
                case .success(let credential):
                    continuation.resume(returning: credential)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            // Retain delegate for the lifetime of the request.
            objc_setAssociatedObject(controller, &AppleAuthDelegate.assocKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.performRequests()
        }
    }

    private final class AppleAuthDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        static var assocKey: UInt8 = 0
        private let completion: (Result<ASAuthorizationCredential, Error>) -> Void

        init(completion: @escaping (Result<ASAuthorizationCredential, Error>) -> Void) {
            self.completion = completion
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
            return ASPresentationAnchor()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            completion(.success(authorization.credential))
            objc_setAssociatedObject(controller, &Self.assocKey, nil, .OBJC_ASSOCIATION_ASSIGN)
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            completion(.failure(error))
            objc_setAssociatedObject(controller, &Self.assocKey, nil, .OBJC_ASSOCIATION_ASSIGN)
        }
    }

    @MainActor
    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseVC: UIViewController? = base ?? {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window.rootViewController
            }
            return UIApplication.shared.windows.first?.rootViewController
        }()

        if let nav = baseVC as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = baseVC as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = baseVC?.presentedViewController {
            return topViewController(base: presented)
        }
        return baseVC
    }
}
