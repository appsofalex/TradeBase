import SwiftUI
import CloudKit

struct MessageHubView: View {
    @Environment(\.appState) private var state
    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedConversation: Conversation?

    // Navigation to Archived sub-menu
    @State private var showArchivedList = false

    // Delete confirm
    @State private var pendingDelete: Conversation?

    // Listener task that we can cancel when leaving this view
    @State private var listenerTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                content
                    .navigationTitle("Messages")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showArchivedList = true
                            } label: {
                                Label("Archived", systemImage: "archivebox")
                            }
                            .tint(TBTheme.brand)
                            .accessibilityLabel("Archived messages")
                        }
                    }
            }
            .background(
                Group {
                    // Push ChatView
                    NavigationLink(
                        isActive: Binding(
                            get: { selectedConversation != nil },
                            set: { if !$0 { selectedConversation = nil } }
                        )
                    ) {
                        if let convo = selectedConversation {
                            ChatView(conversation: convo)
                                .environment(\.appState, state)
                        } else {
                            EmptyView()
                        }
                    } label: { EmptyView() }
                    .hidden()

                    // Push ArchivedMessagesView
                    NavigationLink(isActive: $showArchivedList) {
                        ArchivedMessagesView()
                            .environment(\.appState, state)
                    } label: { EmptyView() }
                    .hidden()
                }
            )
        }
        .task { await loadConversations() }
        .onAppear { startListening() }
        .onDisappear {
            // Ensure no background polling continues when this view is gone
            listenerTask?.cancel()
            listenerTask = nil
        }
        .alert("Delete conversation?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let convo = pendingDelete {
                    Task { await deleteConversation(convo) }
                }
            }
        } message: {
            Text("This removes the conversation for you only. Others will still see it.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(TBTheme.brand)
        } else if let error {
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(TBTheme.offWhiteSecondary)
                Text("Couldn’t load messages")
                    .font(.headline)
                    .foregroundStyle(TBTheme.offWhite)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(TBTheme.offWhiteSecondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await loadConversations() }
                }
                .buttonStyle(.borderedProminent)
                .tint(TBTheme.brand)
            }
            .padding()
        } else {
            let filtered = activeConversations()
            if filtered.isEmpty {
                ScrollView {
                    EmptyStateView(
                        title: "No conversations",
                        subtitle: "Start a chat from a lead or a job.",
                        icon: "bubble.left.and.bubble.right"
                    )
                    .padding(.top, 60)
                }
            } else {
                List {
                    ForEach(filtered, id: \.id) { convo in
                        Button {
                            selectedConversation = convo
                        } label: {
                            ConversationRow(
                                conversation: convo,
                                currentUserId: state.currentAuthIdentity(),
                                publicProfileStore: state.publicProfileStore,
                                container: state.cloudKitContainer
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Delete (soft delete for current user)
                            Button(role: .destructive) {
                                pendingDelete = convo
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)

                            // Archive
                            if let me = state.currentAuthIdentity() {
                                let archived = convo.isArchived(for: me)
                                if archived == false {
                                    Button {
                                        Task { await toggleArchive(convo, archived: true) }
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                    .tint(TBTheme.brand)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await loadConversations() }
            }
        }
    }

    private func activeConversations() -> [Conversation] {
        guard let me = state.currentAuthIdentity() else { return [] }
        let base = conversations.filter { !$0.isDeleted(for: me) }
        return base.filter { !$0.isArchived(for: me) }.sorted(by: { $0.lastMessageAt > $1.lastMessageAt })
    }

    private func startListening() {
        guard let me = state.currentAuthIdentity() else { return }
        // Cancel any previous listener to avoid duplicates
        listenerTask?.cancel()
        listenerTask = Task {
            for await convos in state.messagingService.observeConversations(for: me) {
                await MainActor.run {
                    self.conversations = convos.sorted(by: { $0.lastMessageAt > $1.lastMessageAt })
                }
            }
        }
    }

    private func loadConversations() async {
        guard let me = state.currentAuthIdentity() else {
            await MainActor.run {
                self.isLoading = false
                self.conversations = []
            }
            return
        }
        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }
        do {
            let convos = try await state.messagingService.fetchConversations(for: me)
            await MainActor.run {
                self.conversations = convos.sorted(by: { $0.lastMessageAt > $1.lastMessageAt })
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func toggleArchive(_ convo: Conversation, archived: Bool) async {
        guard let me = state.currentAuthIdentity() else { return }
        do {
            try await state.messagingService.setArchived(conversationId: convo.id, userId: me, archived: archived)
            await loadConversations()
            await state.refreshUnreadCount()
        } catch {
            // ignore for v1
        }
    }

    private func deleteConversation(_ convo: Conversation) async {
        guard let me = state.currentAuthIdentity() else { return }
        do {
            try await state.messagingService.softDelete(conversationId: convo.id, userId: me)
            await loadConversations()
            await state.refreshUnreadCount()
        } catch {
            // ignore for v1
        }
    }
}

