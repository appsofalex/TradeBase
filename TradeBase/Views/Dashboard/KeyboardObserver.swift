import UIKit

final class KeyboardObserver {
    private var willShow: NSObjectProtocol?
    private var willHide: NSObjectProtocol?

    func start(onChange: @escaping (Bool) -> Void) {
        stop()
        willShow = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { _ in onChange(true) }
        willHide = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { _ in onChange(false) }
    }

    func stop() {
        if let t = willShow { NotificationCenter.default.removeObserver(t) }
        if let t = willHide { NotificationCenter.default.removeObserver(t) }
        willShow = nil
        willHide = nil
    }

    deinit { stop() }
}
