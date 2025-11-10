import Foundation
import CoreLocation
import Contacts

@MainActor
final class CurrentLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
    }

    enum LocationError: Error {
        case denied, restricted, failed
    }

    func requestOneShotLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try await waitForAuth()
        }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        default: break
        }

        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    private func waitForAuth() async throws {
    try await withCheckedThrowingContinuation { cont in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            cont.resume(returning: ()) // Return Void instead of calling bare resume()
        }
    }
}

    func reverseGeocode(_ location: CLLocation) async -> (line1: String?, city: String?, postcode: String?) {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let pm = placemarks.first {
                let line1 = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
                return (line1.isEmpty ? nil : line1, pm.locality, pm.postalCode)
            }
        } catch { }
        return (nil, nil, nil)
    }

    // MARK: - Delegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else {
            continuation?.resume(throwing: LocationError.failed)
            continuation = nil
            return
        }
        continuation?.resume(returning: loc)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
