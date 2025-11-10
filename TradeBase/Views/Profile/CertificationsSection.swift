//
//  CertificationsSection.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct CertificationsSection: View {
    let certs: [Certification]
    @State private var previewURL: URL?

    var body: some View {
        SectionCard(title: "Certifications", icon: "doc.plaintext") {
            if certs.isEmpty {
                Text("No certifications added yet.")
                    .foregroundStyle(TBTheme.subtext)
            } else {
                ForEach(certs) { c in
                    Button {
                        if let url = c.fileURL { previewURL = url }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title)
                                    .foregroundStyle(TBTheme.title)
                                if c.fileURL != nil {
                                    Text("Tap to view")
                                        .font(.footnote)
                                        .foregroundStyle(TBTheme.subtext)
                                }
                            }
                            Spacer()
                            Text("\(c.issuer) \(c.year)")
                                .foregroundStyle(TBTheme.subtext)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
        }
        .sheet(item: Binding(
            get: { previewURL.map(CertificationsPreviewItem.init(url:)) },
            set: { previewURL = $0?.url }
        )) { item in
            DocumentPreviewWithClose(url: item.url)
        }
    }
}

private struct CertificationsPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}
