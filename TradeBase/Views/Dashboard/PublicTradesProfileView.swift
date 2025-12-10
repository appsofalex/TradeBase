import SwiftUI
import UIKit

struct PublicTradesProfileView: View {
    let identity: String

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var profile: PublicUserProfile? = nil

    // Navigation toggles
    @State private var showingReviews = false
    @State private var showingCerts = false
    @State private var showingPLI = false
    @State private var showingGuarantees = false

    // Keep existing local reviews behavior for now (no public reviews yet)
    @State private var reviews: [Review] = []
    
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
        return "Tradesperson"
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
                    Text("Trades Profile").tbLargeHeader(horizontal: 0)

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

                    if let main = profile?.mainSkills, !main.isEmpty {
                        VStack(alignment: .center, spacing: 8) {
                            Text("Main Skills")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.95))
                                .frame(maxWidth: .infinity, alignment: .center)
                            SkillsChips(skills: main, tint: TBTheme.brand, alignment: .center)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let sub = profile?.subSkills, !sub.isEmpty {
                        VStack(alignment: .center, spacing: 8) {
                            Text("Other Skills")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.95))
                                .frame(maxWidth: .infinity, alignment: .center)
                            SkillsChips(skills: sub, tint: TBTheme.brandMuted, alignment: .center)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 12) {
                        RowCard(
                            title: "Reviews",
                            subtitle: reviewsSubtitle,
                            icon: "star.leadinghalf.filled",
                            action: { showingReviews = true }
                        )
                        RowCard(
                            title: "Certifications",
                            subtitle: certsSubtitle,
                            icon: "doc.badge.plus",
                            action: { showingCerts = true }
                        )
                        RowCard(
                            title: "Public Liability Insurance",
                            subtitle: pliSubtitle,
                            icon: "doc.richtext",
                            action: { showingPLI = true }
                        )
                        RowCard(
                            title: "Guarantees",
                            subtitle: guaranteesSubtitle,
                            icon: "doc.text",
                            action: { showingGuarantees = true }
                        )
                    }
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
            CustomerReviewsListView(reviews: reviewsOrState)
        }
        .navigationDestination(isPresented: $showingCerts) {
            PublicCertificationsListView(titles: profile?.certificationsSummary ?? [])
        }
        .navigationDestination(isPresented: $showingPLI) {
            PublicComplianceStatusView(
                title: "Public Liability Insurance",
                provided: profile?.hasPublicLiability ?? false
            )
        }
        .navigationDestination(isPresented: $showingGuarantees) {
            PublicComplianceStatusView(
                title: "Guarantees",
                provided: profile?.hasGuarantees ?? false
            )
        }
        .task {
            let didUpload = await mirrorIfMine()
            await loadProfile()
            if didUpload {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await loadProfile()
            }
            // Convert legacy [String] reviews to [Review] for display
            await MainActor.run {
                self.reviews = state.profile.reviews.enumerated().map { idx, text in
                    Review(author: "Customer", rating: 5, text: text, date: Date().addingTimeInterval(-Double(idx) * 86400))
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

    // MARK: - Helpers

    private var reviewsOrState: [Review] {
        if !reviews.isEmpty { return reviews }
        // Fallback map from legacy strings if local state empty
        return state.profile.reviews.enumerated().map { idx, text in
            Review(author: "Customer", rating: 5, text: text, date: Date().addingTimeInterval(-Double(idx) * 86400))
        }
    }

    private var reviewsSubtitle: String {
        let list = reviewsOrState
        if list.isEmpty {
            return "When reviews are posted, they'll appear here."
        } else {
            let total = list.reduce(0) { $0 + $1.rating }
            let avg = Double(total) / Double(list.count)
            let formatted = String(format: "%.1f", avg)
            return "\(formatted) average from \(list.count) review\(list.count == 1 ? "" : "s")"
        }
    }

    private var certsSubtitle: String {
        let count = profile?.certificationsSummary.count ?? 0
        if count == 0 {
            return "No certifications provided"
        } else if count <= 3 {
            let titles = profile?.certificationsSummary.prefix(3).joined(separator: " • ") ?? ""
            return titles
        } else {
            return "\(count) certification\(count == 1 ? "" : "s")"
        }
    }

    private var pliSubtitle: String {
        (profile?.hasPublicLiability ?? false) ? "Provided" : "Not provided"
    }

    private var guaranteesSubtitle: String {
        (profile?.hasGuarantees ?? false) ? "Provided" : "Not provided"
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

    // Returns true if we uploaded an avatar this run (used to trigger a follow-up fetch).
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

// Shared alignment mode for chips across this file
private enum AlignmentMode { case leading, center }

// Helpers (unchanged except for alignment support)
private struct SkillsChips: View {
    var skills: [String]
    var tint: Color
    var alignment: AlignmentMode = .leading

    var body: some View {
        FlexibleChips(items: skills, alignment: alignment) { text in
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Capsule().fill(tint.opacity(0.18))
                )
                .overlay(
                    Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
                .foregroundStyle(.white.opacity(0.95))
        }
    }
}

private struct FlexibleChips<Content: View>: View {
    let items: [String]
    let alignment: AlignmentMode
    let content: (String) -> Content

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        VStack {
            GeometryReader { geo in
                self.generateContent(in: geo)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        // For centered layout we’ll compute the line breaks first, then center each line.
        if alignment == .center {
            let lines = buildLines(maxWidth: g.size.width)
            return AnyView(
                VStack(alignment: .center, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 8) {
                            ForEach(line, id: \.self) { item in
                                content(item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .background(viewHeightReader($totalHeight))
            )
        }

        // Leading (original) layout
        return AnyView(
            ZStack(alignment: .topLeading) {
                ForEach(items, id: \.self) { item in
                    content(item)
                        .alignmentGuide(.leading) { d in
                            if (abs(width - d.width) > g.size.width) {
                                width = 0
                                height -= d.height
                            }
                            let result = width
                            if item == items.last! {
                                width = 0
                            } else {
                                width -= d.width
                            }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if item == items.last! {
                                height = 0
                            }
                            return result
                        }
                }
            }
            .background(viewHeightReader($totalHeight))
        )
    }

    // Break items into lines that fit the given width, measuring roughly using an intrinsic size host.
    private func buildLines(maxWidth: CGFloat) -> [[String]] {
        var lines: [[String]] = [[]]
        var currentWidth: CGFloat = 0
        let spacing: CGFloat = 8

        for item in items {
            // Measure the chip quickly by hosting it off-screen
            let size = HostingSizeCalculator.size(for: content(item))
            let chipWidth = size.width

            if currentWidth == 0 || currentWidth + chipWidth + spacing <= maxWidth {
                lines[lines.count - 1].append(item)
                currentWidth = (currentWidth == 0 ? chipWidth : currentWidth + spacing + chipWidth)
            } else {
                lines.append([item])
                currentWidth = chipWidth
            }
        }
        return lines
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo -> Color in
            DispatchQueue.main.async {
                binding.wrappedValue = geo.size.height
            }
            return Color.clear
        }
    }
}

// Utility to measure a SwiftUI view’s intrinsic size
private enum HostingSizeCalculator {
    static func size<V: View>(for view: V) -> CGSize {
        let controller = UIHostingController(rootView: view)
        let size = controller.sizeThatFits(in: UIView.layoutFittingCompressedSize)
        return size
    }
}

private struct PublicCertificationsListView: View {
    var titles: [String]

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            if titles.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("None provided")
                            .font(.title3.bold())
                        Text("This tradesperson hasn’t added any certifications.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                List {
                    Section {
                        ForEach(titles, id: \.self) { title in
                            Text(title)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Certifications")
    }
}

private struct PublicComplianceStatusView: View {
    var title: String
    var provided: Bool

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: provided ? "checkmark.seal.fill" : "xmark.seal")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(provided ? .green : .red)
                Text(provided ? "Provided" : "Not provided")
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.95))
                Text(provided
                     ? "This tradesperson has indicated they have \(title.lowercased())."
                     : "This tradesperson hasn’t provided \(title.lowercased()) yet.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(title)
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
