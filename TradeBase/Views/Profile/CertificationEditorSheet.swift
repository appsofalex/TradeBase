// CertificationEditorSheet.swift
import SwiftUI

struct CertificationEditorSheet: View {
    let navTitle: String
    let initialTitle: String
    let initialIssuer: String
    let initialYear: Int
    let onSave: (String, String, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var issuer: String
    @State private var year: Int

    private let minYear = 1950
    private let maxYear = Calendar.current.component(.year, from: Date()) + 1

    init(
        navTitle: String,
        initialTitle: String,
        initialIssuer: String,
        initialYear: Int,
        onSave: @escaping (String, String, Int) -> Void
    ) {
        self.navTitle = navTitle
        self.initialTitle = initialTitle
        self.initialIssuer = initialIssuer
        self.initialYear = initialYear
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _issuer = State(initialValue: initialIssuer)
        _year = State(initialValue: initialYear)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    TextField("Issuer (optional)", text: $issuer)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Year") {
                    Picker("Year", selection: $year) {
                        // Count down from most recent so the wheel starts near the present.
                        ForEach(Array(stride(from: maxYear, through: minYear, by: -1)), id: \.self) { y in
                            // Disable grouping so it never shows as "2,025" in any locale.
                            Text(y, format: .number.grouping(.never)).tag(y)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .accessibilityLabel("Year")
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines),
                               issuer.trimmingCharacters(in: .whitespacesAndNewlines),
                               year)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(minYear...maxYear).contains(year))
                }
            }
        }
    }
}
