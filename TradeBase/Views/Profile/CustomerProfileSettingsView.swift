// CustomerProfileSettingsView.swift
import SwiftUI

struct CustomerProfileSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var city: String = ""
    @State private var bio: String = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Name").foregroundStyle(TBTheme.offWhite)
            }

            Section {
                // Apple-integrated suggestions as you type.
                LocationAutocompleteField(text: $city, placeholder: "City (e.g. London)") { result in
                    if let locality = result.locality {
                        city = locality
                    } else {
                        city = result.title
                    }
                }
            } header: {
                Text("City").foregroundStyle(TBTheme.offWhite)
            }

            Section {
                TextEditor(text: $bio)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1))
                    )
            } header: {
                Text("Bio").foregroundStyle(TBTheme.offWhite)
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
            city = state.profile.city ?? ""
            bio = state.profile.bio
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasName
    }

    private func saveAndDismiss() async {
        let trimmedName = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        state.profile.name = trimmedName
        state.profile.city = trimmedCity.isEmpty ? nil : trimmedCity
        state.profile.bio = trimmedBio

        // Ensure no legacy tradesperson-only fields get modified from this screen.
        // (We intentionally do not touch tradeTypes or skills.)
        state.profile.username = nil

        state.saveProfile()
        dismiss()
    }
}
