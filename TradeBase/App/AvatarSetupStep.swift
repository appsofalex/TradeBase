import SwiftUI
import PhotosUI
import Photos
import UIKit

struct AvatarSetupStep: View {
    @Environment(\.appState) private var state

    // Controls whether the parent flow can enable “Finish”
    @Binding var hasAvatar: Bool

    // Local PhotosPicker state
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isPresentingPhotoPicker = false
    @State private var showPhotosDeniedAlert = false

    var body: some View {
        VStack(spacing: 16) {
            AvatarLarge(
                imageURL: state.profile.avatarURL,
                placeholderTint: TBTheme.brand,
                onEdit: { await handleAddOrChangePhotoTapped() },
                size: 170,
                ringWidth: 5
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Profile picture")
            .accessibilityHint(hasAvatar ? "Double tap to change" : "Double tap to add")

            // New helper subtitle below the avatar (used by both setup flows)
            Text("Tap the circle above to select a photo")
                .font(.footnote)
                .foregroundStyle(TBTheme.offWhiteSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .photosPicker(isPresented: $isPresentingPhotoPicker,
                      selection: $pickedPhoto,
                      matching: .images,
                      photoLibrary: .shared())
        .onChange(of: pickedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await state.updateAvatar(with: data)
                        // Mirror to public profile if tradesperson and we have identity
                        if state.selectedRole == .tradesperson,
                           let identity = state.currentAuthIdentity(),
                           let url = state.profile.avatarURL {
                            try? await state.publicProfileStore?.updateAvatar(from: url, identity: identity)
                        }
                    }
                } catch {
                    // Best-effort; keep UI responsive
                }
                await MainActor.run {
                    pickedPhoto = nil
                    hasAvatar = currentHasAvatar()
                }
            }
        }
        .alert("Photos Access Needed", isPresented: $showPhotosDeniedAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") { openAppSettings() }
        } message: {
            Text("Please allow photo library access to select a profile photo.")
        }
        .task {
            // Seed binding on appear
            await MainActor.run {
                hasAvatar = currentHasAvatar()
            }
        }
        .onChange(of: state.profile.avatarURL) { _, _ in
            hasAvatar = currentHasAvatar()
        }
    }

    // MARK: - Helpers

    private func currentHasAvatar() -> Bool {
        guard let url = state.profile.avatarURL else { return false }
        if url.isFileURL {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return true
    }

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
}
