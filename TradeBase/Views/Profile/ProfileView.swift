//
//  ProfileView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import PhotosUI
import Photos
import UIKit
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(\.appState) private var state
    @State private var showingSettings = false

    // Deep links (read-only cards that push edit/detail screens)
    @State private var showingReviews = false
    @State private var showingCerts = false
    @State private var showingPLI = false
    @State private var showingGuarantees = false

    // Photos picker selection
    @State private var pickedPhoto: PhotosPickerItem?

    // Programmatic presentation + permission gating
    @State private var isPresentingPhotoPicker = false
    @State private var showPhotosDeniedAlert = false

    // Treat a local file URL that no longer exists as "no avatar"
    private var hasAvatar: Bool {
        guard let url = state.profile.avatarURL else { return false }
        if url.isFileURL {
            return FileManager.default.fileExists(atPath: url.path)
        } else {
            return true
        }
    }

    private var displayName: String {
        state.profile.name.isEmpty ? "Your Name" : state.profile.name
    }

    // New: primary trade line (tradespeople only)
    private var primaryTradeLine: String {
        state.profile.tradeTypes.first?.displayName ?? ""
    }

    // Subline mirrors public views: prefer headline, then first sentence of bio.
    private var subline: String {
        if !state.profile.headline.isEmpty {
            return state.profile.headline
        }
        if !state.profile.bio.isEmpty {
            if let idx = state.profile.bio.firstIndex(of: ".") {
                return String(state.profile.bio[state.profile.bio.startIndex...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return state.profile.bio
        }
        return ""
    }

    // City (optional display)
    private var city: String {
        state.profile.city ?? ""
    }

    // Certifications summary used in the card subtitle (trades only)
    private var certsSubtitle: String {
        let titles = state.profile.certifications.map { $0.title }
        if titles.isEmpty { return "No certifications provided" }
        if titles.count <= 3 { return titles.prefix(3).joined(separator: " • ") }
        return "\(titles.count) certifications"
    }

    private var pliSubtitle: String {
        state.profile.publicLiabilityFileURL == nil ? "Not provided" : "Provided"
    }

    private var guaranteesSubtitle: String {
        state.profile.guaranteesFileURL == nil ? "Not provided" : "Provided"
    }

    private var reviewsSubtitle: String {
        "When reviews are posted, they'll appear here."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headerTitle
                        avatarBlock
                        identityBlock
                        cardsBlock
                        // Removed premiumBlock from profile; CTA remains in CustomerSettingsView
                        // Removed: certificationsBlock — keep certifications only in the menu
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Show the settings cog for both roles; route to role-appropriate settings
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .principal) { EmptyView() }
            }
            navigationDestinations
        }
        // Programmatic PhotosPicker presentation (after permission)
        .photosPicker(isPresented: $isPresentingPhotoPicker,
                      selection: $pickedPhoto,
                      matching: .images,
                      photoLibrary: .shared())
        // Handle photo selection and mirror avatar to public profile
        .onChange(of: pickedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await state.updateAvatar(with: data)
                        if let identity = state.currentAuthIdentity(),
                           let url = state.profile.avatarURL {
                            try? await state.publicProfileStore?.updateAvatar(from: url, identity: identity)
                        }
                    }
                } catch {
                    print("Failed to load picked image: \(error)")
                }
                await MainActor.run { pickedPhoto = nil }
            }
        }
        // Alert for denied/restricted access
        .alert("Photos Access Needed", isPresented: $showPhotosDeniedAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") { openAppSettings() }
        } message: {
            Text("Please allow photo library access to select a profile photo.")
        }
        // Mirror the private profile to the public profile when this view appears
        .task {
            await mirrorTradesProfileToPublicIfNeeded()
        }
        // Also re-mirror when the user switches into the tradesperson role
        .onChange(of: state.selectedRole) { newRole, _ in
            if newRole == .tradesperson {
                Task { await mirrorTradesProfileToPublicIfNeeded() }
            }
        }
    }

    // MARK: - Subviews (split to reduce type-checker load)

    private var headerTitle: some View {
        Text(state.selectedRole == .tradesperson ? "Trades Profile" : "Customer Profile")
            .tbLargeHeader(horizontal: 0)
    }

    private var avatarBlock: some View {
        AvatarLarge(
            imageURL: state.profile.avatarURL,
            placeholderTint: TBTheme.brand,
            onEdit: { Task { await handleAddOrChangePhotoTapped() } },
            size: 170,
            ringWidth: 5
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile picture")
        .accessibilityHint(hasAvatar ? "Double tap to change" : "Double tap to add")
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var identityBlock: some View {
        VStack(spacing: 4) {
            Text(displayName)
                .font(.title3.bold())
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .center)

            // New: Primary trade/profession line (tradesperson only)
            if state.selectedRole == .tradesperson, !primaryTradeLine.isEmpty {
                Text(primaryTradeLine)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if !subline.isEmpty {
                Text(subline)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center) // Center the bio/headline
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if !city.isEmpty {
                Text(city)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var cardsBlock: some View {
        VStack(spacing: 12) {
            RowCard(
                title: "Reviews",
                subtitle: reviewsSubtitle,
                icon: "star.leadinghalf.filled",
                action: { showingReviews = true }
            )

            // Show these only for tradespeople
            if state.selectedRole == .tradesperson {
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
    }

    private var navigationDestinations: some View {
        Group {
            // Settings destination routes by role
            NavigationLink(isActive: $showingSettings) {
                if state.selectedRole == .tradesperson {
                    TradespersonSettingsView()
                } else {
                    CustomerSettingsView()
                }
            } label: { EmptyView() }
            .hidden()

            NavigationLink(isActive: $showingReviews) {
                if state.selectedRole == .tradesperson {
                    TradespersonReviewsListView()
                } else {
                    CustomerReviewsListView()
                }
            } label: { EmptyView() }
            .hidden()

            // The following destinations are trades-only; guard with role as well
            if state.selectedRole == .tradesperson {
                NavigationLink(isActive: $showingCerts) {
                    CertificationsSettingsView()
                } label: { EmptyView() }
                .hidden()

                NavigationLink(isActive: $showingPLI) {
                    PLIComplianceDetailView(
                        currentURL: state.profile.publicLiabilityFileURL,
                        onUpload: { }, // handled internally
                        onPreview: { _ in },
                        onRemove: { }
                    )
                    .environment(\.appState, state)
                } label: { EmptyView() }
                .hidden()

                NavigationLink(isActive: $showingGuarantees) {
                    GuaranteesComplianceDetailView(
                        currentURL: state.profile.guaranteesFileURL,
                        onUpload: { },
                        onPreview: { _ in },
                        onRemove: { }
                    )
                    .environment(\.appState, state)
                } label: { EmptyView() }
                .hidden()
            }
        }
    }

    // MARK: - Permission handling

    private func handleAddOrChangePhotoTapped() async {
        let status = await requestPhotoLibraryAccessIfNeeded()
        switch status {
        case .authorized, .limited:
            await MainActor.run { isPresentingPhotoPicker = true }
        case .denied, .restricted:
            await MainActor.run { showPhotosDeniedAlert = true }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    private func requestPhotoLibraryAccessIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            return await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    cont.resume(returning: status)
                }
            }
        } else {
            return current
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - Public mirror helper

    private func mirrorTradesProfileToPublicIfNeeded() async {
        guard state.selectedRole == .tradesperson else { return }
        guard let store = state.publicProfileStore else { return }
        guard let identity = state.currentAuthIdentity(), !identity.isEmpty else { return }

        // Upsert minimal fields to public profile
        try? await store.upsert(from: state.profile, identity: identity)

        // If we have a local avatar file, best-effort upload it too
        if let url = state.profile.avatarURL,
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            try? await store.updateAvatar(from: url, identity: identity)
        }
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

// MARK: - PLI / Guarantees detail screens with "add file" pill

// Shared pill button
private struct CapsuleActionButton: View {
    var title: String
    var systemImage: String
    var tint: Color = TBTheme.brand
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// A tiny helper to copy picked files into our sandbox with protection flags.
// Mirrors CertificationsSettingsView.storeDocument(from:) behavior.
private func storeComplianceDocument(from url: URL) throws -> URL {
    let fm = FileManager.default
    let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let ext = url.pathExtension
    let base = url.deletingPathExtension().lastPathComponent
    var dest = docs.appendingPathComponent("\(base).\(ext.isEmpty ? "bin" : ext)")
    var i = 1
    while fm.fileExists(atPath: dest.path) {
        dest = docs.appendingPathComponent("\(base)-\(i).\(ext.isEmpty ? "bin" : ext)")
        i += 1
    }
    let needsStop = url.startAccessingSecurityScopedResource()
    defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
    do {
        try fm.copyItem(at: url, to: dest)
    } catch {
        // Fallback to read/write if direct copy fails (e.g. from iCloud Drive)
        let data = try Data(contentsOf: url)
        try data.write(to: dest, options: [.atomic])
    }
    try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dest.path)
    var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true
    try? dest.setResourceValues(rvs)
    return dest
}

struct PLIComplianceDetailView: View {
    @Environment(\.appState) private var state

    var currentURL: URL?
    var onUpload: () -> Void
    var onPreview: (URL) -> Void
    var onRemove: () -> Void

    @State private var showPicker = false
    @State private var previewURL: URL? = nil
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    SectionCard(title: "Public Liability Insurance", icon: "doc.richtext") {
                        VStack(alignment: .leading, spacing: 12) {
                            statusRow
                            if let url = state.profile.publicLiabilityFileURL {
                                CapsuleActionButton(title: "View file", systemImage: "eye") {
                                    previewURL = url
                                }
                                CapsuleActionButton(title: "Replace file", systemImage: "arrow.triangle.2.circlepath") {
                                    showPicker = true
                                }
                                Button(role: .destructive) {
                                    removePLI()
                                } label: {
                                    Label("Remove file", systemImage: "trash")
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .clipShape(Capsule())
                            } else {
                                CapsuleActionButton(title: "Add document", systemImage: "plus.circle.fill") {
                                    showPicker = true
                                }
                            }
                            Text("Upload a PDF or image of your current PLI certificate.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Public Liability Insurance")
        .sheet(isPresented: $showPicker) {
            DocumentPicker(allowedContentTypes: [.pdf, .image, .item]) { url in
                handlePickedPLI(url: url)
            }
        }
        .sheet(item: Binding(
            get: { previewURL.map(PreviewItem.init(url:)) },
            set: { previewURL = $0?.url }
        )) { item in
            DocumentPreviewWithClose(url: item.url)
        }
        .alert("Couldn’t add file", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: state.profile.publicLiabilityFileURL != nil ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(state.profile.publicLiabilityFileURL != nil ? .green : .red)
            Text(state.profile.publicLiabilityFileURL != nil ? "Provided" : "Not provided")
                .font(.headline)
        }
    }

    private func handlePickedPLI(url: URL) {
        do {
            let stored = try storeComplianceDocument(from: url)
            Task { @MainActor in
                state.profile.publicLiabilityFileURL = stored
                state.saveProfile()
            }
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    private func removePLI() {
        Task { @MainActor in
            // Best-effort local delete if inside our sandbox
            if let url = state.profile.publicLiabilityFileURL,
               url.isFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            state.profile.publicLiabilityFileURL = nil
            state.saveProfile()
        }
    }
}

struct GuaranteesComplianceDetailView: View {
    @Environment(\.appState) private var state

    var currentURL: URL?
    var onUpload: () -> Void
    var onPreview: (URL) -> Void
    var onRemove: () -> Void

    @State private var showPicker = false
    @State private var previewURL: URL? = nil
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    SectionCard(title: "Guarantees", icon: "doc.text") {
                        VStack(alignment: .leading, spacing: 12) {
                            statusRow
                            if let url = state.profile.guaranteesFileURL {
                                CapsuleActionButton(title: "View file", systemImage: "eye") {
                                    previewURL = url
                                }
                                CapsuleActionButton(title: "Replace file", systemImage: "arrow.triangle.2.circlepath") {
                                    showPicker = true
                                }
                                Button(role: .destructive) {
                                    removeGuarantees()
                                } label: {
                                    Label("Remove file", systemImage: "trash")
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .clipShape(Capsule())
                            } else {
                                CapsuleActionButton(title: "Add document", systemImage: "plus.circle.fill") {
                                    showPicker = true
                                }
                            }
                            Text("Upload a PDF or image showing your guarantees or warranty policy.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Guarantees")
        .sheet(isPresented: $showPicker) {
            DocumentPicker(allowedContentTypes: [.pdf, .image, .item]) { url in
                handlePickedGuarantees(url: url)
            }
        }
        .sheet(item: Binding(
            get: { previewURL.map(PreviewItem.init(url:)) },
            set: { previewURL = $0?.url }
        )) { item in
            DocumentPreviewWithClose(url: item.url)
        }
        .alert("Couldn’t add file", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: state.profile.guaranteesFileURL != nil ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(state.profile.guaranteesFileURL != nil ? .green : .red)
            Text(state.profile.guaranteesFileURL != nil ? "Provided" : "Not provided")
                .font(.headline)
        }
    }

    private func handlePickedGuarantees(url: URL) {
        do {
            let stored = try storeComplianceDocument(from: url)
            Task { @MainActor in
                state.profile.guaranteesFileURL = stored
                state.saveProfile()
            }
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    private func removeGuarantees() {
        Task { @MainActor in
            if let url = state.profile.guaranteesFileURL,
               url.isFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            state.profile.guaranteesFileURL = nil
            state.saveProfile()
        }
    }
}
