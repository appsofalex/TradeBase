//  MapSnapshot.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import MapKit
import CoreLocation
import Contacts

struct MapSnapshot: View {
    var address: Address

    @State private var snapshot: Image? = nil

    var body: some View {
        Button(action: { Task { await openInAppleMaps() } }) {
            ZStack {
                if let img = snapshot {
                    img
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(width: 90, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .task { await makeSnapshot() }
    }

    @MainActor
    private func makeSnapshot() async {
        guard let coordinate = address.coordinate else { return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = CGSize(width: 180, height: 128)

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let result = try await snapshotter.start()
            snapshot = Image(uiImage: result.image)
        } catch {
            print("Snapshot error: \(error)")
        }
    }

    @MainActor
    private func openInAppleMaps() async {
        do {
            let coord: CLLocationCoordinate2D
            if let existing = address.coordinate {
                coord = existing
            } else {
                // Geocode the postal address to get a coordinate
                coord = try await geocodeCoordinate(from: address.cnPostalAddress)
            }

            // Build placemark with both coordinate and postal address
            let placemark = MKPlacemark(coordinate: coord, postalAddress: address.cnPostalAddress)
            let item = MKMapItem(placemark: placemark)
            item.name = address.line1

            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        } catch {
            // As a fallback, try opening a search in Maps using the address string
            let query = "\(address.line1), \(address.city) \(address.postcode)"
            if let url = URL(string: "http://maps.apple.com/?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                await UIApplication.shared.open(url)
            } else {
                print("Failed to open Maps: \(error)")
            }
        }
    }

    private func geocodeCoordinate(from postal: CNPostalAddress) async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.geocodePostalAddress(postal) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let location = placemarks?.first?.location {
                    continuation.resume(returning: location.coordinate)
                } else {
                    continuation.resume(throwing: NSError(domain: "Geocoding", code: 1, userInfo: [NSLocalizedDescriptionKey: "No coordinates found for address"]))
                }
            }
        }
    }
}

