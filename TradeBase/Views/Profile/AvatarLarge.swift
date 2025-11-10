import SwiftUI
import UIKit

struct AvatarLarge: View {
    var imageURL: URL?
    var placeholderTint: Color
    var onEdit: () async -> Void
    var size: CGFloat = 170
    var ringWidth: CGFloat = 5

    @State private var localImage: UIImage? = nil
    @State private var isLoadingLocal = false

    var body: some View {
        Button {
            Task { await onEdit() }
        } label: {
            ZStack {
                // Outer subtle ring
                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: ringWidth)

                // Inner accent ring
                Circle()
                    .inset(by: ringWidth + 2)
                    .strokeBorder(placeholderTint.opacity(0.35), lineWidth: 2)

                // Image content
                avatarContent
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(radius: 1)
                    .padding(ringWidth + 4) // keep inside rings
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profile picture")
        .accessibilityHint("Double tap to add or change")
        .task(id: imageURL) {
            await loadLocalIfNeeded()
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let url = imageURL {
            if url.isFileURL {
                if let img = localImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else if isLoadingLocal {
                    ZStack {
                        Circle().fill(placeholderTint.opacity(0.10))
                        ProgressView().tint(placeholderTint)
                    }
                } else {
                    placeholderView
                }
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Circle().fill(placeholderTint.opacity(0.10))
                            ProgressView().tint(placeholderTint)
                        }
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Circle().fill(placeholderTint.opacity(0.12))
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundStyle(placeholderTint)
        }
    }

    private func loadLocalIfNeeded() async {
        localImage = nil
        guard let url = imageURL, url.isFileURL else { return }
        isLoadingLocal = true
        defer { isLoadingLocal = false }
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var loaded: UIImage? = nil
                if let data = try? Data(contentsOf: url),
                   let ui = UIImage(data: data) {
                    loaded = ui
                }
                DispatchQueue.main.async {
                    self.localImage = loaded
                    cont.resume()
                }
            }
        }
    }
}

#Preview {
    ZStack {
        TBTheme.gradient.ignoresSafeArea()
        VStack(spacing: 24) {
            AvatarLarge(imageURL: nil, placeholderTint: TBTheme.brand, onEdit: { })
            AvatarLarge(imageURL: URL(string: "https://example.com/avatar.jpg"),
                        placeholderTint: TBTheme.brand,
                        onEdit: { })
                .frame(width: 140, height: 140)
        }
        .tint(.white)
    }
}
