//
//  Certification.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

struct Certification: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var issuer: String
    var year: Int
    // Optional file associated with this certification (PDF, image, etc.)
    var fileURL: URL? = nil

    // Persist as a relative filename (in Documents) to avoid sandbox path issues.
    enum CodingKeys: String, CodingKey {
        case id, title, issuer, year, filePath
    }

    init(id: UUID = UUID(), title: String, issuer: String, year: Int, fileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.issuer = issuer
        self.year = year
        self.fileURL = fileURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        issuer = try c.decode(String.self, forKey: .issuer)
        year = try c.decode(Int.self, forKey: .year)

        if let filePath = try c.decodeIfPresent(String.self, forKey: .filePath), !filePath.isEmpty {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            fileURL = docs.appendingPathComponent(filePath)
        } else {
            fileURL = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(issuer, forKey: .issuer)
        try c.encode(year, forKey: .year)

        if let url = fileURL {
            // Store just the filename to keep it portable inside the sandbox.
            try c.encode(url.lastPathComponent, forKey: .filePath)
        } else {
            try c.encodeNil(forKey: .filePath)
        }
    }
}
