// CommunityComposerView.swift
import SwiftUI

struct CommunityComposerView: View {
    enum Mode: Equatable {
        case create
        case edit(existing: CommunityPost)
    }

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let initialText: String
    let initialTag: String
    let initialCity: String
    let charLimit: Int
    var onSubmit: (CommunityPost) -> Void

    @State private var text: String
    @State private var tag: String
    @State private var city: String

    init(mode: Mode,
         initialText: String,
         initialTag: String,
         initialCity: String,
         charLimit: Int = 500,
         onSubmit: @escaping (CommunityPost) -> Void) {
        self.mode = mode
        self.initialText = initialText
        self.initialTag = initialTag
        self.initialCity = initialCity
        self.charLimit = charLimit
        self.onSubmit = onSubmit
        _text = State(initialValue: initialText)
        _tag = State(initialValue: initialTag)
        _city = State(initialValue: initialCity)
    }

    private var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !sanitizedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        text.count <= charLimit
    }

    private var sanitizedTag: String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private var title: String {
        switch mode {
        case .create: return "New Post"
        case .edit: return "Edit Post"
        }
    }

    private var actionTitle: String {
        switch mode {
        case .create: return "Post"
        case .edit: return "Save"
        }
    }

    private var authorHandle: String {
        // Create a simple handle from the profile name if it doesn't already look like one.
        let name = state.profile.name
        let compact = name.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return name.hasPrefix("@") ? name : "@\(compact)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Author row
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(TBTheme.brand.opacity(0.15)).frame(width: 44, height: 44)
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(TBTheme.brand)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                // Make name and handle lighter for legibility on dark background
                                Text(state.profile.name)
                                    .font(.headline)
                                    .foregroundStyle(TBTheme.offWhite)
                                Text(authorHandle)
                                    .font(.subheadline)
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)

                        // Text editor
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $text)
                                    .frame(minHeight: 160)
                                    .scrollContentBackground(.hidden)
                                    .foregroundStyle(TBTheme.title)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground).opacity(0.6)))

                                if text.isEmpty {
                                    Text("What’s happening?")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 14)
                                        .padding(.leading, 14)
                                }
                            }

                            HStack {
                                Spacer()
                                Text("\(text.count)/\(charLimit)")
                                    .font(.footnote)
                                    .foregroundStyle(text.count > charLimit ? .red : .secondary)
                            }
                        }
                        .padding(.horizontal)

                        // Tag and City
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Text("#").foregroundStyle(.secondary)
                                TextField("Tag (e.g. tools, hiring, supply)", text: $tag)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground).opacity(0.6)))

                            TextField("City", text: $city)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground).opacity(0.6)))
                        }
                        .padding(.horizontal)

                        Spacer(minLength: 12)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(actionTitle) {
                        submit()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func submit() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTag = sanitizedTag

        switch mode {
        case .create:
            let new = CommunityPost(
                authorId: state.currentAuthIdentity() ?? state.profile.id.uuidString,
                author: authorHandle,
                text: trimmedText,
                date: Date(),
                city: city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "London" : city,
                tag: finalTag
            )
            onSubmit(new)
            dismiss()

        case .edit(let existing):
            var updated = existing
            updated.text = trimmedText
            updated.city = city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? existing.city : city
            updated.tag = finalTag
            onSubmit(updated)
            dismiss()
        }
    }
}

