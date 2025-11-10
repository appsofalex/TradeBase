import SwiftUI
import CloudKit

struct ConversationRow: View {
    let conversation: Conversation
    let currentUserId: String?
    let publicProfileStore: AppState.PublicProfileStore?
    let container: CKContainer

    @State private var displayName: String = ""
    @State private var avatarURL: URL? = nil

    var body: some View {
        HStack(spacing: 12) {
            avatarView
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName.isEmpty ? fallbackName : displayName)
                        .font(.headline)
                        .foregroundStyle(TBTheme.title)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if conversation.leadId != nil {
                        Image(systemName: "doc.text.magnifyingglass")
                            .imageScale(.small)
                            .foregroundStyle(TBTheme.brand)
                            .accessibilityHidden(true)
                    }

                    Spacer()

                    Text(shortTime(conversation.lastMessageAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text(conversation.lastMessageText.isEmpty ? " " : conversation.lastMessageText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if let me = currentUserId {
                        let unread = max(0, conversation.unreadCount(for: me))
                        if unread > 0 {
                            Text("\(unread)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(TBTheme.brand))
                                .accessibilityLabel("\(unread) unread")
                        }
                    }
                }
            }
        }
        .task {
            await resolveOtherParticipant()
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = avatarURL {
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
            Circle().fill(TBTheme.brand.opacity(0.12))
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(TBTheme.brand)
        }
    }

    private func shortTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df.string(from: date)
    }

    private var fallbackName: String {
        // If we can’t resolve the profile, show “Conversation”
        "Conversation"
    }

    private func otherParticipantId() -> String? {
        guard let me = currentUserId else { return conversation.participantIds.first }
        return conversation.participantIds.first(where: { $0 != me }) ?? conversation.participantIds.first
    }

    private func resolveOtherParticipant() async {
        guard let other = otherParticipantId(), !other.isEmpty else { return }
        if let store = publicProfileStore, let profile = try? await store.fetch(identity: other) {
            await MainActor.run {
                // Coalesce optional name to a nonoptional String
                self.displayName = profile.name ?? ""
                self.avatarURL = profile.avatarURL
            }
        } else {
            await MainActor.run {
                self.displayName = ""
                self.avatarURL = nil
            }
        }
    }
}

// Minimal local-file image helper (matches pattern used elsewhere)
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

