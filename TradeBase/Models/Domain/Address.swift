//
//  Address.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation
import CoreLocation
import Contacts

struct Address: Hashable, Codable {
    var line1: String
    var city: String
    var postcode: String
    var coordinate: CLLocationCoordinate2D? = nil

    // New: persisted multi-line formatted address for display/use across the app.
    // Typically up to 3–4 lines like:
    // [ "221B Baker Street", "Marylebone", "London", "NW1 6XE" ]
    var formattedLines: [String] = []

    enum CodingKeys: String, CodingKey {
        case line1
        case city
        case postcode
        case latitude
        case longitude
        case formattedLines
    }

    // Legacy keys from an older Address.swift
    private enum LegacyKeys: String, CodingKey {
        case lat
        case lon
    }

    init(line1: String, city: String, postcode: String, coordinate: CLLocationCoordinate2D? = nil, formattedLines: [String] = []) {
        self.line1 = line1
        self.city = city
        self.postcode = postcode
        self.coordinate = coordinate
        self.formattedLines = formattedLines
    }

    init(from decoder: Decoder) throws {
        // Decode required fields first
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line1 = try container.decode(String.self, forKey: .line1)
        city = try container.decode(String.self, forKey: .city)
        postcode = try container.decode(String.self, forKey: .postcode)

        // Try primary latitude/longitude keys
        if let lat = try container.decodeIfPresent(Double.self, forKey: .latitude),
           let lon = try container.decodeIfPresent(Double.self, forKey: .longitude) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                  let lat = try legacy.decodeIfPresent(Double.self, forKey: .lat),
                  let lon = try legacy.decodeIfPresent(Double.self, forKey: .lon) {
            // Fallback: legacy lat/lon keys if present
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            coordinate = nil
        }

        // New (backward compatible): formattedLines, default to [] if absent
        formattedLines = (try? container.decode([String].self, forKey: .formattedLines)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(line1, forKey: .line1)
        try container.encode(city, forKey: .city)
        try container.encode(postcode, forKey: .postcode)
        if let coord = coordinate {
            try container.encode(coord.latitude, forKey: .latitude)
            try container.encode(coord.longitude, forKey: .longitude)
        }
        try container.encode(formattedLines, forKey: .formattedLines)
    }

    // Convenience: Contacts postal address for MapKit/Maps
    var cnPostalAddress: CNPostalAddress {
        let pa = CNMutablePostalAddress()
        pa.street = line1
        pa.city = city
        pa.postalCode = postcode
        pa.isoCountryCode = "GB" // Adjust if you add non-UK mock data
        return pa.copy() as! CNPostalAddress
    }

    // MARK: - Equatable
    static func == (lhs: Address, rhs: Address) -> Bool {
        guard lhs.line1 == rhs.line1,
              lhs.city == rhs.city,
              lhs.postcode == rhs.postcode,
              lhs.formattedLines == rhs.formattedLines
        else { return false }

        switch (lhs.coordinate, rhs.coordinate) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return l.latitude == r.latitude && l.longitude == r.longitude
        default:
            return false
        }
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(line1)
        hasher.combine(city)
        hasher.combine(postcode)
        formattedLines.forEach { hasher.combine($0) }
        if let coord = coordinate {
            hasher.combine(coord.latitude)
            hasher.combine(coord.longitude)
        } else {
            hasher.combine(0xFF as UInt8)
        }
    }
}
