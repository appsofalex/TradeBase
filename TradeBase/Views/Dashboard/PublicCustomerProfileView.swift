// PublicCustomerProfileView.swift
import SwiftUI
import UIKit

struct PublicCustomerProfileView: View {
    let identity: String

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var profile: PublicUserProfile? = nil

    // Keep existing local reviews behavior for now
    @State private var reviews: [Review] = []
    @State private var showingReviews = false
    
    // Blocking
    @State private var showBlockConfirmation = false

    private var fetchIdentity: String {
        if let current = state.currentAuthIdentity(), current == identity {
            return current
        }
        return identity
    }

    private var displayName: String {
        if let name = profile?.name, !name.isEmpty {
            return name
        }
        return "Customer"
    }

    private var subline: String {
        if let h = profile?.headline,
           !h.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return h
        }
        if let b = profile?.bio,
           !b.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            if let idx = b.firstIndex(of: ".") {
                return String(b[b.startIndex...idx]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
            return b
        }
        return ""
    }

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Customer Profile").tbLargeHeader(horizontal: 0)

                    AvatarLarge(
                        imageURL: profile?.avatarURL,
                        placeholderTint: TBTheme.brand,
                        onEdit: { /* read-only */ },
                        size: 170,
                        ringWidth: 5
                    )
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, alignment: .center)

                    VStack(spacing: 4) {
                        Text(displayName)
                            .font(.title3.bold())
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .center)

                        if !subline.isEmpty {
                            Text(subline)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        if let city = profile?.city, !city.isEmpty {
                            Text(city)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                    RowCard(
                        title: "Reviews",
                        subtitle: reviewsSubtitle,
                        icon: "star.leadinghalf.filled",
                        action: { showingReviews = true }
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }

            if isLoading {
                ProgressView().tint(TBTheme.brand)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Only show block option if not viewing own profile
                if state.currentAuthIdentity() != identity {
                    Menu {
                        Button(role: .destructive) {
                            blockUser()
                        } label: {
                            Label("Block user", systemImage: "hand.raised.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17))
                            .foregroundStyle(TBTheme.brand)
                    }
                }
            }
        }
        .overlay {
            if showBlockConfirmation {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Image(systemName: "hand.raised.slash.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.red)
                        
                        VStack(spacing: 12) {
                            Text("User Blocked")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            
                            Text("You’ve blocked this user. Their jobs and content will no longer be visible to you.")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, 8)
                    }
                    .padding(32)
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .navigationDestination(isPresented: $showingReviews) {
            CustomerReviewsListView(reviews: reviews)
        }
        .task {
            let didUpload = await mirrorIfMine()
            await loadProfile()
            if didUpload {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await loadProfile()
            }
            await MainActor.run {
                self.reviews = state.profile.reviews.enumerated().map { idx, text in
                    Review(author: "Tradesperson", rating: 5, text: text, date: Date().addingTimeInterval(-Double(idx) * 86400))
                }
            }
        }
    }
    
    private func blockUser() {
        state.blockUser(identity: identity)
        withAnimation {
            showBlockConfirmation = true
        }
    }

    private var reviewsSubtitle: String {
        if reviews.isEmpty {
            return "When tradespeople leave them reviews, they'll appear here."
        } else {
            let total = reviews.reduce(0) { $0 + $1.rating }
            let avg = Double(total) / Double(reviews.count)
            let formatted = String(format: "%.1f", avg)
            return "\(formatted) average from \(reviews.count) review\(reviews.count == 1 ? "" : "s")"
        }
    }

    private func loadProfile() async {
        guard let store = state.publicProfileStore else { return }
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let fetched = try await store.fetch(identity: fetchIdentity)
            await MainActor.run { self.profile = fetched }
        } catch {
            await MainActor.run { self.profile = nil }
        }
    }

    private func mirrorIfMine() async -> Bool {
        guard let store = state.publicProfileStore else { return false }
        guard let current = state.currentAuthIdentity(), current == identity else {
            return false
        }

        let writeIdentity = current
        try? await store.upsert(from: state.profile, identity: writeIdentity)

        var uploadedAvatar = false
        if let url = state.profile.avatarURL,
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            try? await store.updateAvatar(from: url, identity: writeIdentity)
            uploadedAvatar = true
        }
        return uploadedAvatar
    }
}

private extension Text {
    func tbLargeHeader(horizontal: CGFloat = 18) -> some View {
        self
            .font(.system(size: 36, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.horizontal, horizontal)
    }
}
