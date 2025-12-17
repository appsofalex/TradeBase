import SwiftUI
import PhotosUI
import Photos
import UIKit
import Observation

struct TradespersonSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    // Photos picker selection
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isPresentingPhotoPicker = false
    @State private var showPhotosDeniedAlert = false

    // Delete account flow
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?

    // Subscription upsell
    @State private var showingPremiumUpsell = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                editProfileSection
                subscriptionSection
                preferencesSection(bindableState: state)
                aboutSection
                deleteAccountSection
            }
            .scrollContentBackground(.hidden)
            .background(TBTheme.gradient.ignoresSafeArea())
            .navigationTitle("Settings")
        }
        // Upsell sheet — tradesperson variant
        .fullScreenCover(isPresented: $showingPremiumUpsell) {
            PremiumUpsellView()
        }
        // Programmatic PhotosPicker presentation (after permission)
        .photosPicker(isPresented: $isPresentingPhotoPicker,
                      selection: $pickedPhoto,
                      matching: .images,
                      photoLibrary: .shared())
        // Handle photo selection
        .onChange(of: pickedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await state.updateAvatar(with: data)
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
        // Delete account confirmation
        .alert("Delete Account?", isPresented: $showDeleteAlert, actions: {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await deleteAccountFlow() }
            }
        }, message: {
            Text("This will permanently remove your profile, posts, and any associated data. This action cannot be undone.")
        })
        // Error alert for delete failures
        .alert("Delete Failed", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        ), actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(deleteErrorMessage ?? "An unknown error occurred.")
        })
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    avatarImage
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                        .shadow(radius: 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.profile.name).font(.headline)

                        // Quick summary: primary trade and a couple of skills (if available)
                        let primary = state.profile.tradeTypes.first?.displayName ?? ""
                        let skillsPreview = state.profile.skills.prefix(2).joined(separator: " • ")
                        let summary = [primary, skillsPreview].filter { !$0.isEmpty }.joined(separator: " • ")
                        if !summary.isEmpty {
                            Text(summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

            // Signed-in provider status (hidden when provider is .none)
            let provider = state.authProvider
            if provider != .none {
                HStack(spacing: 12) {
                    providerIcon(for: provider)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        if provider == .guest {
                            Text("Signed in as a Guest")
                                .font(.subheadline.weight(.semibold))
                        } else {
                            Text("Signed in with \(providerDisplayName(provider))")
                                .font(.subheadline.weight(.semibold))
                        }
                        if let email = state.authEmail, !email.isEmpty, provider != .guest {
                            Text(email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            } else if state.isAuthenticated {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as a Guest")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var editProfileSection: some View {
        Section("Edit Profile") {
            if state.authProvider != .none {
                Button {
                    Task { await handleChangePhotoTapped() }
                } label: {
                    Label("Change profile photo", systemImage: "camera.fill")
                }
            } else {
                HStack {
                    Label("Sign in to change profile photo", systemImage: "camera.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            NavigationLink {
                TradespersonProfileSettingsView()
            } label: {
                Label("Edit profile", systemImage: "square.and.pencil")
            }

            Button(role: .destructive) {
                state.signOut()
                dismiss()
            } label: {
                Label {
                    Text("Sign out")
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .baselineOffset(-2) // nudges the icon lower
                }
                .foregroundStyle(.red)
            }
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription") {
            if state.profile.isPremium {
                Label("You’re on TradeBase Pro", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Free plan", systemImage: "seal")
                Button {
                    showingPremiumUpsell = true
                } label: {
                    Label {
                        Text("Upgrade to TradeBase Pro")
                    } icon: {
                        Image(systemName: "bolt.badge.a")
                            .foregroundStyle(TBTheme.brand)
                    }
                }
            }
        }
    }

    private func preferencesSection(@Bindable bindableState: AppState) -> some View {
        // Intercept ON -> show upsell and keep the toggle OFF
        let notificationsBinding = Binding<Bool>(
            get: { bindableState.notificationsEnabled },
            set: { newValue in
                if newValue {
                    if state.profile.isPremium {
                        bindableState.notificationsEnabled = true
                    } else {
                        showingPremiumUpsell = true
                        bindableState.notificationsEnabled = false
                    }
                } else {
                    bindableState.notificationsEnabled = false
                }
            }
        )
        
        // Intercept Appearance change -> show upsell if not premium
        let appearanceBinding = Binding<AppState.AppearanceMode>(
            get: { bindableState.appearanceMode },
            set: { newValue in
                if state.profile.isPremium {
                    bindableState.appearanceMode = newValue
                } else {
                    showingPremiumUpsell = true
                    // do not set bindableState.appearanceMode
                }
            }
        )

        return Section("Preferences") {
            Toggle(isOn: notificationsBinding) {
                Label("Notifications", systemImage: "bell.badge")
            }
            Picker(selection: appearanceBinding) {
                Text("System").tag(AppState.AppearanceMode.system)
                Text("Light").tag(AppState.AppearanceMode.light)
                Text("Dark").tag(AppState.AppearanceMode.dark)
            } label: {
                Label("Appearance", systemImage: "paintbrush")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            Link(destination: URL(string: "https://www.notion.so/lexthepogger/TradeBase-Privacy-Policy-2bd2e6386ba68068a82bde74c884700d?source=copy_link")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://www.notion.so/lexthepogger/TradeBase-Terms-of-Service-2bd2e6386ba6804e8e34fcf81de480b8?source=copy_link")!) {
                Label("Terms of Service", systemImage: "doc.plaintext")
            }
            
            // New items
            Link(destination: URL(string: "https://www.notion.so/lexthepogger/TradeBase-Support-2bd2e6386ba6800ca8b8d24a3fee0877?source=copy_link")!) {
                Label("Support", systemImage: "questionmark.circle")
            }

            Link(destination: URL(string: "https://apps.apple.com/us/app/habit-hero-daily-quests/id6751962274")!) {
                Label("Rate the app", systemImage: "star")
            }

            ShareLink(item: URL(string: "https://apps.apple.com/us/app/habit-hero-daily-quests/id6751962274")!) {
                Label("Recommend the app", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var deleteAccountSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label {
                    Text("Delete Account")
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
            .disabled(isDeleting)
        } footer: {
            if isDeleting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Deleting your account…")
                }
                .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Avatar image for header

    @ViewBuilder
    private var avatarImage: some View {
        if let url = state.profile.avatarURL {
            if url.isFileURL {
                LocalFileImage(url: url) {
                    placeholderAvatar
                }
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholderAvatar
                    case .success(let image):
                        image.resizable().scaledToFill()
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
                .frame(width: 36, height: 36)
                .foregroundStyle(TBTheme.brand)
        }
    }

    private func providerDisplayName(_ provider: AppState.AuthProvider) -> String {
        switch provider {
        case .apple: return "Apple"
        case .google: return "Google"
        case .x: return "X"
        case .email: return "Email"
        case .guest: return "Guest"
        case .none: return "None"
        }
    }

    @ViewBuilder
    private func providerIcon(for provider: AppState.AuthProvider) -> some View {
        switch provider {
        case .apple:
            Image("appleLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        case .google:
            Image("googleLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        case .x:
            Image("XLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        case .email:
            Image(systemName: "envelope.fill")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
        case .guest:
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
        case .none:
            Image(systemName: "person")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
        }
    }

    // MARK: - Permission handling

    private func handleChangePhotoTapped() async {
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

    // MARK: - Delete helpers

    private func deleteAccountFlow() async {
        await MainActor.run { isDeleting = true }
        do {
            // If you also want to re-show the unauthenticated onboarding pager, pass true.
            try await state.deleteTradespersonAccountAndResetSetup(resetUnauthOnboarding: false)
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { deleteErrorMessage = error.localizedDescription }
        }
        await MainActor.run { isDeleting = false }
    }
}

// MARK: - Local file image loader (copied from CustomerSettingsView)

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
        .task(id: url) {
            image = nil
            await load()
        }
    }

    private func load() async {
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
