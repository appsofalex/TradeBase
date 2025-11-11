// TradespersonProfileSettingsView.swift
import SwiftUI

struct TradespersonProfileSettingsView: View {
    @Environment(\.appState) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var primaryTrade: TradeType = .electrician
    @State private var selectedSkills: Set<String> = []
    @State private var newSkill: String = ""
    @State private var city: String = "" // New: working copy of city

    private var catalogSkills: [String] {
        SkillsCatalog.skills(for: primaryTrade)
    }
    private var customSkills: [String] {
        selectedSkills.filter { !catalogSkills.contains($0) }.sorted()
    }

    var body: some View {
        Form {
            Section {
                TextField("Name or business name", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Name").foregroundStyle(TBTheme.offWhite)
            }
            
            Section {
                TextField("Your city (e.g. London)", text: $city)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("City").foregroundStyle(TBTheme.offWhite)
            }

            Section {
                TextField("Tell customers about you (max 80 characters)", text: $bio)
                    .onChange(of: bio) { _, newValue in
                        if newValue.count > 80 {
                            bio = String(newValue.prefix(80))
                        }
                    }
            } header: {
                Text("Bio").foregroundStyle(TBTheme.offWhite)
            }

            Section {
                Picker("Primary trade", selection: $primaryTrade) {
                    ForEach(TradeType.allCases) { trade in
                        Text(trade.displayName).tag(trade)
                    }
                }
            } header: {
                Text("Industry").foregroundStyle(TBTheme.offWhite)
            }

            Section {
                if catalogSkills.isEmpty {
                    Text("No predefined skills yet. Add your own below.")
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                } else {
                    ForEach(catalogSkills, id: \.self) { skill in
                        Toggle(skill, isOn: Binding(
                            get: { selectedSkills.contains(skill) },
                            set: { isOn in
                                if isOn { selectedSkills.insert(skill) } else { selectedSkills.remove(skill) }
                            }
                        ))
                    }
                }
            } header: {
                Text("Recommended skills").foregroundStyle(TBTheme.offWhite)
            }

            Section {
                if customSkills.isEmpty {
                    Text("Add any services you offer that aren’t listed above.")
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                } else {
                    ForEach(customSkills, id: \.self) { skill in
                        Toggle(skill, isOn: Binding(
                            get: { selectedSkills.contains(skill) },
                            set: { isOn in
                                if isOn { selectedSkills.insert(skill) } else { selectedSkills.remove(skill) }
                            }
                        ))
                        .swipeActions {
                            Button(role: .destructive) {
                                selectedSkills.remove(skill)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                HStack {
                    TextField("Add custom skill", text: $newSkill)
                        .textInputAutocapitalization(.words)
                    Button {
                        addCustomSkill()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(TBTheme.brand)
                    }
                    .disabled(newSkill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Custom skills").foregroundStyle(TBTheme.offWhite)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await saveAndDismiss() }
                }
                .disabled(!canSave)
            }
        }
        .scrollContentBackground(.hidden)
        .background(TBTheme.gradient.ignoresSafeArea())
        .onAppear {
            name = state.profile.name
            bio = state.profile.bio
            primaryTrade = state.profile.tradeTypes.first ?? .electrician
            selectedSkills = Set(state.profile.skills)
            city = state.profile.city ?? "" // hydrate city
        }
        .onChange(of: primaryTrade) { _ in
            // No-op
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasName
    }

    private func addCustomSkill() {
        let trimmed = newSkill.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedSkills.insert(trimmed)
        newSkill = ""
    }

    private func saveAndDismiss() async {
        // Update the in-memory profile
        state.profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        state.profile.tradeTypes = [primaryTrade]
        state.profile.skills = Array(selectedSkills).sorted()
        state.profile.city = city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : city

        // Username removed
        state.profile.username = nil

        // 1) Save locally
        state.saveProfile()

        // 2) Upsert to CloudKit so changes persist across sign-out/sign-in
        if let id = state.currentAuthIdentity() {
            try? await state.cloudProfileStore.saveProfile(state.profile, identity: id)
        }

        dismiss()
    }
}
