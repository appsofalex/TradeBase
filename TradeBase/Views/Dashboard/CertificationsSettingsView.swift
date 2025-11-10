//
//  CertificationsSettingsView.swift
//  TradeBase
//

import SwiftUI

struct CertificationsSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List {
            if state.profile.certifications.isEmpty {
                Text("No certifications yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.profile.certifications) { cert in
                    VStack(alignment: .leading) {
                        Text(cert.title).font(.headline)
                        Text("\(cert.issuer) • \(cert.year)").foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in
                    let items = idx.map { state.profile.certifications[$0] }
                    Task {
                        for c in items {
                            await state.deleteCertification(c)
                        }
                    }
                }
            }
        }
        .background(TBTheme.gradient.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("Certifications")
    }
}

