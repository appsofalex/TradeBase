//
//  TradespersonProfileSettingsView.swift
//  TradeBase
//

import SwiftUI

struct TradespersonProfileSettingsView: View {
    @Environment(AppState.self) private var state

    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var selectedTrade: TradeType? = nil
    @State private var skills: [String] = []

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $name)
                TextField("Bio", text: $bio)
            }
            Section("Primary trade") {
                Picker("Trade", selection: Binding(
                    get: { selectedTrade },
                    set: { selectedTrade = $0 }
                )) {
                    Text("None").tag(TradeType?.none)
                    ForEach(TradeType.allCases) { t in
                        Text(t.displayName).tag(TradeType?.some(t))
                    }
                }
            }
            Section("Skills") {
                if let trade = selectedTrade {
                    let options = SkillsCatalog.skills(for: trade)
                    ForEach(options, id: \.self) { s in
                        Toggle(s, isOn: Binding(
                            get: { skills.contains(s) },
                            set: { isOn in
                                if isOn { skills.append(s) } else { skills.removeAll { $0 == s } }
                            }
                        ))
                    }
                } else {
                    Text("Select a trade to choose skills").foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Save") {
                    state.completeTradespersonSetup(
                        name: name.isEmpty ? state.profile.name : name,
                        primaryTrade: selectedTrade ?? state.profile.tradeTypes.first ?? .generalBuilder,
                        skills: Array(Set(skills)).sorted()
                    )
                }
            }
        }
        .navigationTitle("Edit Profile")
        .onAppear {
            name = state.profile.name
            bio = state.profile.bio
            selectedTrade = state.profile.tradeTypes.first
            skills = state.profile.skills
        }
    }
}

