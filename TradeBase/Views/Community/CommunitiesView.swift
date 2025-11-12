//
//  CommunitiesView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct CommunitiesView: View {
    @Environment(AppState.self) private var state

    @State private var showingComposer = false
    @State private var editingPost: CommunityPost? = nil

    // Account gating presentation
    @State private var showAccountGateAlert = false
    @State private var showAuthEntrySheet = false
    @State private var pendingAction: PendingAction? = nil
    @State private var pendingPost: CommunityPost? = nil

    // iCloud write gate
    @State private var showICloudGateAlert = false

    // Error state for posting/mutations
    @State private var errorMessage: String? = nil

    // Loading/Error state for feed
    @State private var isLoadingPosts = false
    @State private var loadErrorMessage: String? = nil

    // ADMIN passcode sheet
    @State private var showAdminPasscodeSheet = false
    @State private var postPendingAdminDelete: CommunityPost? = nil

    private enum PendingAction {
        case create
        case edit
        case delete
    }

    private var defaultCity: String {
        let cityCounts = Dictionary(grouping: state.posts, by: { $0.city }).mapValues { $0.count }
        return cityCounts.max(by: { $0.value < $1.value })?.key ?? "London"
    }

    private var hasFullAccount: Bool {
        state.isAuthenticated && state.authProvider != nil
    }

    private func canEdit(_ post: CommunityPost) -> Bool {
        guard hasFullAccount, let identity = state.currentAuthIdentity() else { return false }
        return post.authorId == identity
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Community")
                        .tbLargeHeader()

                    content
                        .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if hasFullAccount {
                            Task {
                                let canWrite = await state.isCloudKitAvailableForPosting()
                                await MainActor.run {
                                    if canWrite {
                                        showingComposer = true
                                    } else {
                                        showICloudGateAlert = true
                                    }
                                }
                            }
                        } else {
                            pendingAction = .create
                            showAccountGateAlert = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Post")
                }
            }
        }
        .task {
            if state.posts.isEmpty {
                await reloadCommunity()
            }
        }
        .fullScreenCover(isPresented: $showingComposer) {
            CommunityComposerView(
                mode: .create,
                initialText: "",
                initialTag: "",
                initialCity: defaultCity,
                charLimit: 500
            ) { newPost in
                Task {
                    do {
                        let saved = try await state.publishCommunityPost(
                            text: newPost.text,
                            city: newPost.city,
                            tag: newPost.tag
                        )
                        await MainActor.run {
                            state.posts.insert(saved, at: 0)
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $editingPost) { post in
            CommunityComposerView(
                mode: .edit(existing: post),
                initialText: post.text,
                initialTag: post.tag,
                initialCity: post.city,
                charLimit: 500
            ) { updated in
                updatePost(updated)
            }
        }
        .alert("Account Required", isPresented: $showAccountGateAlert, actions: {
            Button("Cancel", role: .cancel) {
                pendingAction = nil
                pendingPost = nil
            }
            Button("Create Account") {
                showAuthEntrySheet = true
            }
        }, message: {
            Text("Posting requires a TradeBase account. Editing or deleting is only available for posts you authored.")
        })
        .alert("iCloud Required to Post", isPresented: $showICloudGateAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text("Sign in to iCloud on this device to publish posts. Reading is available to everyone.")
        })
        .alert("Action Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        ), actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(errorMessage ?? "An unknown error occurred.")
        })
        .sheet(isPresented: $showAuthEntrySheet, onDismiss: {
            if hasFullAccount {
                routePendingActionIfPossible()
            }
            pendingAction = nil
            pendingPost = nil
        }) {
            AuthEntryView(presentation: .gatedModal)
        }
        .sheet(isPresented: $showAdminPasscodeSheet, onDismiss: {
            postPendingAdminDelete = nil
        }) {
            if let target = postPendingAdminDelete {
                AdminPasscodeSheet(
                    title: "Delete post?",
                    message: "Enter the 4-digit passcode to delete this post immediately.",
                    onCancel: { showAdminPasscodeSheet = false },
                    onValidated: {
                        showAdminPasscodeSheet = false
                        adminDeletePost(target)
                    }
                )
            } else {
                AdminPasscodeSheet(
                    title: "Delete post?",
                    message: "Enter the 4-digit passcode to delete this post immediately.",
                    onCancel: { showAdminPasscodeSheet = false },
                    onValidated: { showAdminPasscodeSheet = false }
                )
            }
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if isLoadingPosts {
            ScrollView {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Loading community…")
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
            .refreshable { await reloadCommunity() }
        } else if let message = loadErrorMessage {
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                    Text("Couldn’t load posts").font(.headline).foregroundStyle(TBTheme.offWhite)
                    Text(message).font(.footnote).foregroundStyle(TBTheme.offWhiteSecondary).multilineTextAlignment(.center)
                    Button {
                        Task { await reloadCommunity() }
                    } label: {
                        Text("Try Again")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(TBTheme.brand))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 280)
            }
            .refreshable { await reloadCommunity() }
        } else {
            let posts = state.posts

            if posts.isEmpty {
                ScrollView {
                    VStack {
                        EmptyStateView(title: "No posts",
                                       subtitle: "Be the first to ask or offer.",
                                       icon: "bubble.left.and.exclamationmark.bubble.right")
                            .padding(.top, 60)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
                .scrollContentBackground(.hidden)
                .refreshable { await reloadCommunity() }
            } else {
                List {
                    ForEach(posts) { post in
                        let editable = canEdit(post)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(post.author).font(.headline).foregroundStyle(TBTheme.title)
                                Spacer()
                                let trimmedTag = post.tag.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmedTag.isEmpty {
                                    Text("#\(trimmedTag)").foregroundStyle(TBTheme.subtext)
                                }
                            }
                            Text(post.text).foregroundStyle(TBTheme.title)
                            HStack(spacing: 4) {
                                Text(post.city)
                                Text("•")
                                RelativeTimeText(date: post.date)
                            }
                            .font(.footnote)
                            .foregroundStyle(TBTheme.subtext)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            postPendingAdminDelete = post
                            showAdminPasscodeSheet = true
                        }
                        .if(editable) { view in
                            view.contextMenu {
                                Button {
                                    editingPost = post
                                } label: {
                                    Label("Edit", systemImage: "square.and.pencil")
                                }
                                Button(role: .destructive) {
                                    deletePost(post)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .if(editable) { view in
                            view.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    editingPost = post
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: "square.and.pencil")
                                            .foregroundStyle(.white)
                                        Text("Edit")
                                            .font(.caption)
                                            .foregroundStyle(TBTheme.offWhite)
                                    }
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    deletePost(post)
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.white)
                                        Text("Delete")
                                            .font(.caption)
                                            .foregroundStyle(TBTheme.offWhite)
                                    }
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await reloadCommunity() }
            }
        }
    }

    // MARK: - Data loading

    private func reloadCommunity() async {
        await MainActor.run {
            isLoadingPosts = true
            loadErrorMessage = nil
        }
        let err = await state.refreshCommunity(city: nil as String?)
        await MainActor.run {
            isLoadingPosts = false
            loadErrorMessage = err?.localizedDescription
        }
    }

    // MARK: - Routing after auth

    private func routePendingActionIfPossible() {
        guard hasFullAccount, let action = pendingAction else { return }
        switch action {
        case .create:
            Task {
                let canWrite = await state.isCloudKitAvailableForPosting()
                await MainActor.run {
                    if canWrite { showingComposer = true } else { showICloudGateAlert = true }
                }
            }
        case .edit:
            if let post = pendingPost, canEdit(post) {
                editingPost = post
            }
        case .delete:
            if let post = pendingPost, canEdit(post) {
                deletePost(post)
            }
        }
    }

    // MARK: - Mutations (server-backed)

    private func updatePost(_ updated: CommunityPost) {
        guard canEdit(updated) else { return }
        Task {
            do {
                let saved = try await state.updateCommunityPost(updated)
                await MainActor.run {
                    if let idx = state.posts.firstIndex(where: { $0.ckRecordName == saved.ckRecordName }) {
                        state.posts[idx] = saved
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deletePost(_ post: CommunityPost) {
        guard canEdit(post) else { return }
        Task {
            do {
                try await state.deleteCommunityPost(post)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func adminDeletePost(_ post: CommunityPost) {
        Task {
            do {
                try await state.adminDeleteCommunityPost(post)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Conditional modifier helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Relative time helper

private struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        if Date().timeIntervalSince(date) < 60 {
            TimelineView(.periodic(from: date, by: 1)) { context in
                Text(relativeElapsedString(since: date, now: context.date))
            }
        } else {
            TimelineView(.periodic(from: date, by: 60)) { context in
                Text(relativeElapsedString(since: date, now: context.date))
            }
        }
    }
}

private func relativeElapsedString(since date: Date, now: Date = Date()) -> String {
    let interval = max(0, now.timeIntervalSince(date))
    if interval < 60 {
        // Seconds
        let secs = Int(interval)
        return "\(secs)s"
    } else if interval < 3600 {
        // Minutes
        let minutes = Int(interval / 60)
        return "\(minutes)m"
    } else if interval < 86_400 {
        // Hours
        let hours = Int(interval / 3600)
        return "\(hours)h"
    } else {
        // Days (days only from here on)
        let days = Int(interval / 86_400)
        return "\(days)d"
    }
}

// MARK: - Admin passcode sheet

private struct AdminPasscodeSheet: View {
    let title: String
    let message: String
    var onCancel: () -> Void
    var onValidated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    @State private var showError: Bool = false
    @FocusState private var isPINFocused: Bool

    private let requiredPIN = "2529"

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(TBTheme.offWhite)
                    Text(message)
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { idx in
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
                                    .frame(width: 52, height: 56)
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TBTheme.offWhite.opacity(0.25)))
                                Text(character(at: idx))
                                    .font(.title.bold())
                                    .foregroundStyle(TBTheme.title)
                            }
                        }
                    }
                    .overlay(
                        TextField("", text: Binding(
                            get: { pin },
                            set: { newVal in
                                let digits = newVal.filter { $0.isNumber }
                                pin = String(digits.prefix(4))
                                showError = false
                            })
                        )
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isPINFocused)
                        .foregroundColor(.clear)
                        .accentColor(.clear)
                        .opacity(0.01)
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                    )

                    if showError {
                        Text("Incorrect passcode.")
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 12) {
                        PillButton(title: "Cancel", style: .light) {
                            onCancel()
                            dismiss()
                        }
                        PillButton(title: "Delete", style: .brand) {
                            validateAndDelete()
                        }
                        .disabled(pin.count < 4)
                        .opacity(pin.count < 4 ? 0.6 : 1)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPINFocused = true
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isPINFocused = true }
    }

    private func character(at index: Int) -> String {
        guard index < pin.count else { return "•" }
        let chars = Array(pin)
        return String(chars[index])
    }

    private func validateAndDelete() {
        if pin == requiredPIN {
            onValidated()
            dismiss()
        } else {
            showError = true
            pin = ""
            isPINFocused = true
        }
    }
}
