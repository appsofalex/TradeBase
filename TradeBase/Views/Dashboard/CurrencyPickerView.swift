import SwiftUI

struct CurrencyPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var all: [String] = ["GBP", "EUR", "USD", "AUD", "CAD", "NZD", "JPY", "CHF", "CNY"]
    private var filtered: [String] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    // Explicit initializer to ensure it’s accessible from other files in the same module.
    init(selection: Binding<String>) {
        self._selection = selection
    }

    var body: some View {
        ZStack { TBTheme.gradient.ignoresSafeArea()
            List {
                Section {
                    TextField("Search currency", text: $query)
                        .textInputAutocapitalization(.characters)
                }
                ForEach(filtered, id: \.self) { code in
                    HStack {
                        Text(code)
                        Spacer()
                        if selection.uppercased() == code {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(TBTheme.brand)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = code
                        dismiss()
                    }
                }
                // Simple manual override option
                Section("Other") {
                    Button("Enter code manually…") {
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}
