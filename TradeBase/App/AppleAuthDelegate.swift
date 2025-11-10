// AppleAuthDelegate.swift
import Foundation
import AuthenticationServices
import UIKit

final class AppleAuthDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    typealias SuccessHandler = (ASAuthorization) -> Void
    typealias FailureHandler = (Error) -> Void

    private let onSuccess: SuccessHandler?
    private let onFailure: FailureHandler?
    private weak var anchorWindow: UIWindow?

    init(anchorWindow: UIWindow? = nil,
         onSuccess: SuccessHandler? = nil,
         onFailure: FailureHandler? = nil) {
        self.anchorWindow = anchorWindow
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        super.init()
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onSuccess?(authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onFailure?(error)
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let anchorWindow {
            return anchorWindow
        }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        return ASPresentationAnchor()
    }
}
