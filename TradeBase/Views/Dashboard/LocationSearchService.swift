// LocationSearchService.swift
import Foundation
import MapKit
import Combine

@MainActor
final class LocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    @Published var suggestions: [MKLocalSearchCompletion] = []

    var regionBias: MKCoordinateRegion? {
        didSet { completer.region = regionBias ?? MKCoordinateRegion() }
    }

    private let completer: MKLocalSearchCompleter

    override init() {
        let c = MKLocalSearchCompleter()
        c.resultTypes = [.address] // cities, postcodes, addresses
        self.completer = c
        super.init()
        completer.delegate = self
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }

    // MARK: - Resolve a suggestion

    struct LocationResult: Identifiable, Hashable {
        var id = UUID()
        var title: String
        var subtitle: String
        var coordinate: CLLocationCoordinate2D?
        var locality: String?          // city/town
        var adminArea: String?         // region/state
        var postalCode: String?
        var countryCode: String?
        var thoroughfare: String?      // street
        var subThoroughfare: String?   // street number

        // Custom Equatable to avoid relying on CLLocationCoordinate2D Hashable availability
        static func == (lhs: LocationResult, rhs: LocationResult) -> Bool {
            lhs.title == rhs.title &&
            lhs.subtitle == rhs.subtitle &&
            lhs.locality == rhs.locality &&
            lhs.adminArea == rhs.adminArea &&
            lhs.postalCode == rhs.postalCode &&
            lhs.countryCode == rhs.countryCode &&
            lhs.thoroughfare == rhs.thoroughfare &&
            lhs.subThoroughfare == rhs.subThoroughfare &&
            lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
            lhs.coordinate?.longitude == rhs.coordinate?.longitude
        }

        // Custom Hashable combining stable fields and lat/long when present
        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            hasher.combine(subtitle)
            hasher.combine(locality)
            hasher.combine(adminArea)
            hasher.combine(postalCode)
            hasher.combine(countryCode)
            hasher.combine(thoroughfare)
            hasher.combine(subThoroughfare)
            if let c = coordinate {
                hasher.combine(c.latitude)
                hasher.combine(c.longitude)
            } else {
                // Differentiate nil coordinate from 0/0
                hasher.combine(false)
            }
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> LocationResult {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        // Choose the first item; you could also present multiple if needed.
        guard let item = response.mapItems.first else {
            return LocationResult(
                title: completion.title,
                subtitle: completion.subtitle,
                coordinate: nil,
                locality: nil,
                adminArea: nil,
                postalCode: nil,
                countryCode: nil,
                thoroughfare: nil,
                subThoroughfare: nil
            )
        }
        let pm = item.placemark
        return LocationResult(
            title: completion.title,
            subtitle: completion.subtitle,
            coordinate: pm.location?.coordinate,
            locality: pm.locality,
            adminArea: pm.administrativeArea,
            postalCode: pm.postalCode,
            countryCode: pm.countryCode,
            thoroughfare: pm.thoroughfare,
            subThoroughfare: pm.subThoroughfare
        )
    }
}

