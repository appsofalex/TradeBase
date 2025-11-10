//
//  ProfileHeader.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct ProfileHeader: View {
    @Environment(AppState.self) private var state

    enum Mode {
        case tradesperson
        case customer
    }

    let profile: UserProfile
    var mode: Mode = .tradesperson

    // Consider bio "present" only if it has visible characters.
    private var hasBio: Bool {
        !profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                avatarInteractiveView
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading) {
                    HStack {
                        Text(profile.name)
                            .font(.title2.bold())
                            .foregroundStyle(TBTheme.title)
                        if profile.isPremium {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                        }
                    }

                    // For customers: show city under the name.
                    // For tradespeople: keep the skills/trades summary.
                    if mode == .customer {
                        if let city = profile.city, !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(city)
                                .font(.subheadline)
                                .foregroundStyle(TBTheme.subtext)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        SummaryLine(tokens: summaryTokens(from: profile))
                    }
                }
                Spacer()
            }

            // Show bio only for tradespeople and only when it exists.
            if mode == .tradesperson, hasBio {
                Text(profile.bio)
                    .foregroundStyle(TBTheme.title)
            }
        }
        // Make the card a little shorter when there’s no bio.
        .padding(.horizontal, 16)
        .padding(.vertical, hasBio ? 16 : 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(radius: 1)
    }

    // MARK: - Avatar (display-only here; editing happens in Settings)
    @ViewBuilder
    private var avatarInteractiveView: some View {
        // No PhotosPicker here — just show the image.
        avatarImageView
    }

    @ViewBuilder
    private var avatarImageView: some View {
        if let url = profile.avatarURL {
            if url.isFileURL {
                LocalFileImage(url: url) {
                    placeholderAvatar
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                .shadow(radius: 1)
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Circle().fill(TBTheme.brand.opacity(0.15))
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                            .shadow(radius: 1)
                    case .failure:
                        placeholderAvatar
                    @unknown default:
                        placeholderAvatar
                    }
                }
            }
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle().fill(TBTheme.brand.opacity(0.15))
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(TBTheme.brand)
        }
    }

    private func summaryTokens(from profile: UserProfile) -> [String] {
        var tokens: [String] = []
        if let primary = profile.tradeTypes.first {
            tokens.append(primary.displayName)
        }
        if !profile.skills.isEmpty {
            tokens.append(contentsOf: profile.skills)
        }
        return tokens
    }
}

// MARK: - Inline summary with "+N more" sheet

private struct SummaryLine: View {
    let tokens: [String]
    var maxInline: Int = 3

    @State private var showAll = false

    var body: some View {
        if tokens.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                Text(inlineText)
                    .font(.subheadline)
                    .foregroundStyle(TBTheme.subtext)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if extraCount > 0 {
                    Text(" • ")
                        .font(.subheadline)
                        .foregroundStyle(TBTheme.subtext)

                    Button(action: { showAll = true }) {
                        Text("+\(extraCount) more")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TBTheme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showAll) {
                AllLabelsSheet(tokens: tokens)
            }
        }
    }

    private var inlineText: String {
        let visible = Array(tokens.prefix(maxInline))
        return visible.joined(separator: " • ")
    }

    private var extraCount: Int {
        max(0, tokens.count - maxInline)
    }
}

private struct AllLabelsSheet: View {
    let tokens: [String]
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(tokens, id: \.self) { token in
                        Chip(text: token)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Your skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Local file image loader

private struct LocalFileImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        SwiftUI.Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        // Always present, so it runs when the URL changes even if we already have an image
        .task(id: url) {
            image = nil
            await load()
        }
    }

    private func load() async {
        // Load off the main thread
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var loaded: UIImage? = nil
                if let data = try? Data(contentsOf: url),
                   let ui = UIImage(data: data) {
                    loaded = ui
                }
                DispatchQueue.main.async {
                    self.image = loaded
                    cont.resume()
                }
            }
        }
    }
}
