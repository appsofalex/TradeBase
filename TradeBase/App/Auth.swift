// AppState+Auth.swift

import Foundation
import AuthenticationServices
import GoogleSignIn
import UIKit
import ObjectiveC

extension AppState {

    // MARK: - Google

    @MainActor
    func signInWithGoogle() async throws {
        guard let presenter = Self.topViewController() else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to find a presenter for Google Sign-In."])
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            let user = result.user

            // Persist a stable Google user identifier for identity building.
            if let userID = user.userID, !userID.isEmpty {
                UserDefaults.standard.set(userID, forKey: "google_user_id")
            } else if let idToken = user.idToken?.tokenString {
                // Optional: parse "sub" claim from ID token if userID is unavailable.
                if let sub = Self.googleSubjectClaim(fromIDToken: idToken) {
                    UserDefaults.standard.set(sub, forKey: "google_user_id")
                }
            }

            // Update app auth state
            self.authProvider = .google
            self.authEmail = user.profile?.email
            // NOTE: We do NOT set isAuthenticated = true yet to prevent Task cancellation.
            
            // Hydrate identity-scoped data immediately
            await load()
            
            // Now that loading is done, we can update state and navigate.
            self.isAuthenticated = true
            self.navigationDirection = .forward
        } catch {
            let ns = error as NSError
            // Map Google "canceled" to ASAuthorizationError.canceled so UI suppresses it.
            if ns.domain == "com.google.GIDSignIn", ns.code == -5 {
                throw ASAuthorizationError(.canceled)
            }
            throw error
        }
    }

    private static func googleSubjectClaim(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadB64 = String(parts[1])
        let normalized = payloadB64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padLen = 4 - (normalized.count % 4)
        let padded = normalized + (padLen < 4 ? String(repeating: "=", count: padLen) : "")
        guard let data = Data(base64Encoded: padded),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else { return nil }
        return sub
    }

    // MARK: - Apple

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
        UserDefaults.standard.set(userID, forKey: "apple_user_id")
        
        // Capture email (only provided first time or after revoke)
        let emailToSet = appleCred.email

        // Robust name capture and restore
        let freshNameKey = "apple_name_fresh_capture"
        var capturedName: String?
        if let fullName = appleCred.fullName {
            let formatter = PersonNameComponentsFormatter()
            var nameString = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
            if nameString.isEmpty {
                let given = fullName.givenName ?? ""
                let family = fullName.familyName ?? ""
                nameString = "\(given) \(family)".trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !nameString.isEmpty {
                capturedName = nameString
                // Save to disk for later recovery (survives load() overwrites and view transitions)
                UserDefaults.standard.set(nameString, forKey: freshNameKey)
            }
        }

        // Use an unstructured Task to decouple the update sequence from the View's lifecycle.
        let updateTask = Task { @MainActor in
            // Apply immediately to in-memory state so UI can reflect it even before hydration
            if let email = emailToSet {
                self.authEmail = email
            }
            self.authProvider = .apple
            if let name = capturedName {
                self.profile.name = name
            }

            // Hydrate (may overwrite profile). That's OK; we will re-apply the fresh capture.
            await load()

            // Force-restore fresh name if present
            if let recoveredName = UserDefaults.standard.string(forKey: freshNameKey), !recoveredName.isEmpty {
                self.profile.name = recoveredName
                // Only now that we've applied it to the active profile, remove the key
                UserDefaults.standard.removeObject(forKey: freshNameKey)
            }

            // Finalize State
            self.isAuthenticated = true
            self.navigationDirection = .forward
        }
        
        _ = try await updateTask.value
    }

    // MARK: - Email Sign Up

    @MainActor
    func signUp(name: String, email: String, password: String) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Auth", code: -3, userInfo: [NSLocalizedDescriptionKey: "Name is required."])
        }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Auth", code: -4, userInfo: [NSLocalizedDescriptionKey: "Email is required."])
        }
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Auth", code: -5, userInfo: [NSLocalizedDescriptionKey: "Password is required."])
        }
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailTest = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        guard emailTest.evaluate(with: email) else {
            throw NSError(domain: "Auth", code: -6, userInfo: [NSLocalizedDescriptionKey: "Please enter a valid email address."])
        }

        // Simulated successful sign-up
        self.profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authProvider = .email
        self.authEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Delay state change until after load to mimic the safe pattern
        // self.isAuthenticated = true // Moved down
        
        // Forward push for email sign-up as well
        // self.navigationDirection = .forward // Moved down

        await load()
        
        // Finalize
        self.isAuthenticated = true
        self.navigationDirection = .forward
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
            return UIApplication.shared.windows.first ?? ASPresentationAnchor()
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

