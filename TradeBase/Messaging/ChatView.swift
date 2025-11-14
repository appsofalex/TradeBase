import SwiftUI
import CloudKit
import CoreLocation
import PhotosUI
import AVFoundation
import AVKit
import QuickLook
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(\.appState) private var state
    let conversation: Conversation

    // New: control whether the composer should focus on appear (to raise keyboard)
    var focusOnAppear: Bool = false
    @FocusState private var isComposerFocused: Bool

    @State private var messages: [Message] = []
    @State private var newText: String = ""
    @State private var isLoading = true
    @State private var error: String?

    // Resolved display name for the other participant (nil until loaded)
    @State private var resolvedTitle: String?

    // Job navigation state
    @State private var jobLead: MarketplaceLead?
    @State private var isShowingJob = false
    @State private var isLoadingJob = false
    @State private var jobLoadError: String?
    @State private var jobPollTask: Task<Void, Never>? = nil

    // Media picker
    @State private var pickerItem: PhotosPickerItem?
    @State private var isProcessingMedia = false
    @State private var mediaError: String?

    // Profile navigation state
    @State private var isShowingProfile = false

    // Messages listener task to cancel on disappear
    @State private var messagesListenerTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                messagesList
                inputBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Principal title: tappable name with subtle chevron
            ToolbarItem(placement: .principal) {
                Button {
                    if otherParticipantId() != nil {
                        isShowingProfile = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(titleText)
                            .font(.headline)
                            .foregroundStyle(TBTheme.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TBTheme.offWhiteSecondary)
                            .opacity(titleText.isEmpty ? 0 : 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(titleText.isEmpty || otherParticipantId() == nil)
                .accessibilityLabel(titleText.isEmpty ? "Conversation" : "View profile for \(titleText)")
                .accessibilityAddTraits(.isButton)
            }

            if conversation.leadId != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await openJob() }
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("View job")
                }
            }
        }
        .task {
            await resolveTitleIfNeeded()
            await loadInitial()
        }
        .onAppear {
            startListening()
            // If asked to, focus the composer to raise the keyboard.
            if focusOnAppear {
                // Delay slightly to ensure the TextField is in the hierarchy.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isComposerFocused = true
                }
            }
        }
        .onDisappear {
            messagesListenerTask?.cancel()
            messagesListenerTask = nil
            stopJobPolling()
        }
        .background(
            Group {
                // Job navigation
                NavigationLink(isActive: $isShowingJob) {
                    if let lead = jobLead {
                        LeadDetailView(lead: lead)
                            .onAppear { startJobPolling() }
                            .onDisappear { stopJobPolling() }
                    } else {
                        ProgressView().task { await openJob() }
                    }
                } label: { EmptyView() }
                .hidden()

                // Profile navigation
                NavigationLink(isActive: $isShowingProfile) {
                    if let other = otherParticipantId() {
                        if state.selectedRole == .customer {
                            PublicTradesProfileView(identity: other)
                                .environment(\.appState, state)
                        } else {
                            PublicCustomerProfileView(identity: other)
                                .environment(\.appState, state)
                        }
                    } else {
                        EmptyView()
                    }
                } label: { EmptyView() }
                .hidden()
            }
        )
        .alert("Couldn’t load job", isPresented: Binding(
            get: { jobLoadError != nil },
            set: { if !$0 { jobLoadError = nil } }
        )) { Button("OK", role: .cancel) { } } message: { Text(jobLoadError ?? "Please try again.") }
        .alert("Couldn’t send media", isPresented: Binding(
            get: { mediaError != nil },
            set: { if !$0 { mediaError = nil } }
        )) { Button("OK", role: .cancel) { } } message: { Text(mediaError ?? "Please try again.") }
    }

    private var titleText: String {
        resolvedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @ViewBuilder
    private var messagesList: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView().controlSize(.large)
                Spacer()
            }
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
                Spacer()
            }
            .padding()
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(messages, id: \.id) { msg in
                        MessageBubble(message: msg, isMe: msg.senderId == state.currentAuthIdentity())
                            .listRowBackground(Color.clear)
                            .id(msg.id)
                    }
                }
                .scrollContentBackground(.hidden)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(TBTheme.brand)
            }
            .disabled(isProcessingMedia)
            .onChange(of: pickerItem) { _, newItem in
                guard let item = newItem else { return }
                Task { await handlePickedItem(item) }
            }

            TextField("Message", text: $newText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($isComposerFocused) // New: focus binding

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(TBTheme.brand))
            }
            .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func loadInitial() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        do {
            let msgs = try await state.messagingService.fetchMessages(conversationId: conversation.id, before: nil, limit: 200)
            let stable = msgs.sorted {
                if $0.sentAt != $1.sentAt { return $0.sentAt < $1.sentAt }
                return $0.id < $1.id
            }
            await MainActor.run {
                self.messages = stable
                self.isLoading = false
            }
            if let me = state.currentAuthIdentity() {
                try? await state.messagingService.markConversationRead(conversationId: conversation.id, userId: me)
                await state.refreshUnreadCount()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func startListening() {
        // Cancel any previous listener to avoid duplicates
        messagesListenerTask?.cancel()
        messagesListenerTask = Task {
            for await msgs in state.messagingService.observeMessages(conversationId: conversation.id) {
                let stable = msgs.sorted {
                    if $0.sentAt != $1.sentAt { return $0.sentAt < $1.sentAt }
                    return $0.id < $1.id
                }
                await MainActor.run { self.messages = stable }
            }
        }
    }

    private func send() async {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let me = state.currentAuthIdentity() else { return }
        do {
            _ = try await state.messagingService.sendMessage(conversationId: conversation.id, text: text, senderId: me)
            await MainActor.run { newText = "" }
        } catch {
            // ignore for v1
        }
    }

    // MARK: - Media handling

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        await MainActor.run { isProcessingMedia = true; mediaError = nil }
        defer { Task { @MainActor in isProcessingMedia = false } }

        guard let me = state.currentAuthIdentity() else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uti = item.supportedContentTypes.first {
                if uti.conforms(to: .image) {
                    let (fileURL, meta) = try await downscaleImageToJPEG(data: data, maxDimension: 2048, quality: 0.8)
                    _ = try await state.messagingService.sendMediaMessage(conversationId: conversation.id, senderId: me, fileURL: fileURL, kind: .photo, meta: meta)
                    // No intermediate cleanup needed for images; we keep only the single cached JPEG.
                } else if uti.conforms(to: .movie) || uti.conforms(to: .video) {
                    if let fileURL = try await item.loadTransferable(type: URL.self) {
                        let processed = try await exportVideoTo720p(inputURL: fileURL)
                        // Generate thumbnail directly next to the output to avoid duplicate copies.
                        let thumbPath = processed.outputURL.deletingPathExtension().appendingPathExtension("thumb.jpg")
                        if !FileManager.default.fileExists(atPath: thumbPath.path) {
                            let thumb = try await generateVideoThumbnailJPG(inputURL: processed.outputURL)
                            // Move or replace into sibling thumb.jpg
                            try? FileManager.default.removeItem(at: thumbPath)
                            try? FileManager.default.moveItem(at: thumb, to: thumbPath)
                        }
                        let w = processed.naturalSize.map { Double($0.width) }
                        let h = processed.naturalSize.map { Double($0.height) }
                        let meta = MediaMeta(width: w, height: h, duration: processed.duration)
                        _ = try await state.messagingService.sendMediaMessage(conversationId: conversation.id, senderId: me, fileURL: processed.outputURL, kind: .video, meta: meta)
                        // No extra cleanup required: exported output + sibling thumb.jpg are the canonical files.
                    } else {
                        let tmp = try await writeTemp(data: data, preferredExt: "mov")
                        let processed = try await exportVideoTo720p(inputURL: tmp)
                        // Remove the temporary input after a successful export
                        try? FileManager.default.removeItem(at: tmp)
                        // Generate thumbnail directly next to the output to avoid duplicate copies.
                        let thumbPath = processed.outputURL.deletingPathExtension().appendingPathExtension("thumb.jpg")
                        if !FileManager.default.fileExists(atPath: thumbPath.path) {
                            let thumb = try await generateVideoThumbnailJPG(inputURL: processed.outputURL)
                            try? FileManager.default.removeItem(at: thumbPath)
                            try? FileManager.default.moveItem(at: thumb, to: thumbPath)
                        }
                        let w = processed.naturalSize.map { Double($0.width) }
                        let h = processed.naturalSize.map { Double($0.height) }
                        let meta = MediaMeta(width: w, height: h, duration: processed.duration)
                        _ = try await state.messagingService.sendMediaMessage(conversationId: conversation.id, senderId: me, fileURL: processed.outputURL, kind: .video, meta: meta)
                    }
                } else {
                    throw NSError(domain: "ChatView", code: -20, userInfo: [NSLocalizedDescriptionKey: "Unsupported media type"])
                }
            } else {
                if let url = try await item.loadTransferable(type: URL.self) {
                    let extUTI = item.supportedContentTypes.first
                    if extUTI?.conforms(to: .image) == true {
                        let data = try Data(contentsOf: url)
                        let (fileURL, meta) = try await downscaleImageToJPEG(data: data, maxDimension: 2048, quality: 0.8)
                        _ = try await state.messagingService.sendMediaMessage(conversationId: conversation.id, senderId: me, fileURL: fileURL, kind: .photo, meta: meta)
                    } else {
                        let processed = try await exportVideoTo720p(inputURL: url)
                        let thumbPath = processed.outputURL.deletingPathExtension().appendingPathExtension("thumb.jpg")
                        if !FileManager.default.fileExists(atPath: thumbPath.path) {
                            let thumb = try await generateVideoThumbnailJPG(inputURL: processed.outputURL)
                            try? FileManager.default.removeItem(at: thumbPath)
                            try? FileManager.default.moveItem(at: thumb, to: thumbPath)
                        }
                        let w = processed.naturalSize.map { Double($0.width) }
                        let h = processed.naturalSize.map { Double($0.height) }
                        let meta = MediaMeta(width: w, height: h, duration: processed.duration)
                        _ = try await state.messagingService.sendMediaMessage(conversationId: conversation.id, senderId: me, fileURL: processed.outputURL, kind: .video, meta: meta)
                    }
                } else {
                    throw NSError(domain: "ChatView", code: -21, userInfo: [NSLocalizedDescriptionKey: "Couldn’t read the selected item"])
                }
            }
        } catch {
            await MainActor.run { mediaError = (error as NSError).localizedDescription }
        }
    }

    // MARK: - Image helpers

    private func downscaleImageToJPEG(data: Data, maxDimension: CGFloat, quality: CGFloat) async throws -> (URL, MediaMeta) {
        guard let image = UIImage(data: data) else {
            throw NSError(domain: "ChatView", code: -30, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }
        let size = image.size
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpg = scaled.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "ChatView", code: -31, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])
        }
        let url = try writeToMessagingCache(data: jpg, preferredName: "img-\(UUID().uuidString)", ext: "jpg")
        let meta = MediaMeta(width: Double(targetSize.width), height: Double(targetSize.height), duration: nil)
        return (url, meta)
    }

    // MARK: - Video helpers

    private struct VideoExportResult {
        let outputURL: URL
        let duration: Double
        let naturalSize: CGSize?
    }

    private func exportVideoTo720p(inputURL: URL) async throws -> VideoExportResult {
        let asset = AVURLAsset(url: inputURL)
        let duration = CMTimeGetSeconds(asset.duration)

        let preset = AVAssetExportPreset1280x720
        guard AVAssetExportSession.exportPresets(compatibleWith: asset).contains(preset),
              let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            let dest = try copyToMessagingCache(src: inputURL, preferredName: "vid-\(UUID().uuidString)")
            let track = try await asset.loadTracks(withMediaType: .video).first
            let natural = try await track?.load(.naturalSize)
            return VideoExportResult(outputURL: dest, duration: duration, naturalSize: natural)
        }

        let outputURL = messagingCacheDir().appendingPathComponent("vid-\(UUID().uuidString).mp4")
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()
        if session.status == .completed {
            let track = try await asset.loadTracks(withMediaType: .video).first
            let natural = try await track?.load(.naturalSize)
            try protectFile(outputURL)
            return VideoExportResult(outputURL: outputURL, duration: duration, naturalSize: natural)
        } else if let err = session.error {
            throw err
        } else {
            throw NSError(domain: "ChatView", code: -40, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
    }

    private func generateVideoThumbnailJPG(inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        let cg = try generator.copyCGImage(at: time, actualTime: nil)
        let ui = UIImage(cgImage: cg)
        guard let data = ui.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ChatView", code: -41, userInfo: [NSLocalizedDescriptionKey: "Thumbnail encoding failed"])
        }
        let url = try writeToMessagingCache(data: data, preferredName: "thumb-\(UUID().uuidString)", ext: "jpg")
        return url
    }

    // MARK: - Caching helpers

    private func messagingCacheDir() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        var cache = appDir.appendingPathComponent("MessagingAssets", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) { try? fm.createDirectory(at: appDir, withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: cache.path) { try? fm.createDirectory(at: cache, withIntermediateDirectories: true) }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: cache.path)
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true
        try? cache.setResourceValues(rvs)
        return cache
    }

    private func writeToMessagingCache(data: Data, preferredName: String, ext: String) throws -> URL {
        let dir = messagingCacheDir()
        var url = dir.appendingPathComponent(preferredName).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(preferredName)-\(UUID().uuidString)").appendingPathExtension(ext)
        }
        try data.write(to: url, options: [.atomic])
        try protectFile(url)
        return url
    }

    private func copyToMessagingCache(src: URL, preferredName: String) throws -> URL {
        let dir = messagingCacheDir()
        let ext = src.pathExtension.isEmpty ? "bin" : src.pathExtension
        var url = dir.appendingPathComponent(preferredName).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(preferredName)-\(UUID().uuidString)").appendingPathExtension(ext)
        }
        do { try FileManager.default.copyItem(at: src, to: url) }
        catch { let data = try Data(contentsOf: src); try data.write(to: url, options: [.atomic]) }
        try protectFile(url)
        return url
    }

    private func protectFile(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(rvs)
    }

    private func writeTemp(data: Data, preferredExt: String) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(preferredExt)
        try data.write(to: url, options: [.atomic])
        return url
    }

    // MARK: - Title resolution

    private func otherParticipantId() -> String? {
        guard let me = state.currentAuthIdentity() else { return nil }
        return conversation.participantIds.first(where: { $0 != me })
    }

    private func resolveTitleIfNeeded() async {
        guard resolvedTitle == nil else { return }
        guard let other = otherParticipantId(), !other.isEmpty else { return }
        if let store = state.publicProfileStore, let profile = try? await store.fetch(identity: other) {
            await MainActor.run { self.resolvedTitle = profile.name }
        }
    }

    // MARK: - Job loading / navigation

    private func openJob() async {
        guard let leadId = conversation.leadId, !leadId.isEmpty else { return }
        await MainActor.run { isLoadingJob = true; jobLoadError = nil }
        do {
            let lead = try await fetchLead(leadId: leadId)
            await MainActor.run {
                self.jobLead = lead
                self.isShowingJob = true
                self.isLoadingJob = false
            }
        } catch {
            await MainActor.run { self.jobLoadError = error.localizedDescription; self.isLoadingJob = false }
        }
    }

    private func startJobPolling() {
        stopJobPolling()
        guard let leadId = conversation.leadId, !leadId.isEmpty else { return }
        jobPollTask = Task {
            let db = state.cloudKitContainer.publicCloudDatabase
            while !Task.isCancelled {
                do {
                    let latest = try await fetchLead(leadId: leadId, using: db)
                    await MainActor.run { self.jobLead = latest }
                } catch { }
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
    }

    private func stopJobPolling() {
        jobPollTask?.cancel()
        jobPollTask = nil
    }

    private func fetchLead(leadId: String, using db: CKDatabase? = nil) async throws -> MarketplaceLead {
        let database = db ?? state.cloudKitContainer.publicCloudDatabase
        if let rec = try? await database.record(for: CKRecord.ID(recordName: leadId)),
           let lead = try? mapLeadRecord(rec) {
            return lead
        }
        if UUID(uuidString: leadId) != nil {
            let pred = NSPredicate(format: "id == %@", leadId)
            let q = CKQuery(recordType: "JobLead", predicate: pred)
            let (matched, _) = try await database.records(matching: q, desiredKeys: nil)
            for (_, res) in matched {
                if let rec = try? res.get(), let lead = try? mapLeadRecord(rec) {
                    return lead
                }
            }
        }
        throw NSError(domain: "ChatView", code: -404, userInfo: [NSLocalizedDescriptionKey: "Job not found"])
    }

    private func mapLeadRecord(_ record: CKRecord) throws -> MarketplaceLead {
        let id: UUID = {
            if let s = record["id"] as? String, let u = UUID(uuidString: s) { return u }
            if let u = UUID(uuidString: record.recordID.recordName) { return u }
            return UUID()
        }()

        let title = (record["title"] as? String) ?? ""
        let desc = (record["description"] as? String) ?? ""
        let catString = (record["category"] as? String) ?? ""
        let category = TradeType(rawValue: catString)

        let createdAt = (record["createdAt"] as? Date) ?? record.creationDate ?? Date()
        let updatedAt = (record["updatedAt"] as? Date) ?? record.modificationDate ?? createdAt

        let posterIdentity = record["ownerUserId"] as? String
        let posterAppID: UUID? = (record["posterAppID"] as? String).flatMap(UUID.init(uuidString:))

        let city = (record["city"] as? String) ?? ""
        let postcode = (record["postcode"] as? String) ?? ""
        let coord: CLLocationCoordinate2D? = (record["location"] as? CLLocation)?.coordinate
        let addr = Address(line1: "", city: city, postcode: postcode, coordinate: coord)

        let budgetTypeRaw = (record["budgetType"] as? String) ?? JobBudgetType.fixed.rawValue
        let budgetType = JobBudgetType(rawValue: budgetTypeRaw) ?? .fixed
        let currency = (record["currency"] as? String) ?? "GBP"
        let budgetMin = decimal(from: record["budgetMin"])
        let budgetMax = decimal(from: record["budgetMax"])

        let startDate = (record["startDate"] as? Date)
        let isUrgent = (record["isUrgent"] as? NSNumber)?.boolValue ?? false

        var photoURLs: [URL] = []
        if let assets = record["photoAssets"] as? [CKAsset] {
            for (_, asset) in assets.enumerated() {
                if let url = asset.fileURL { photoURLs.append(url) }
            }
        }

        // New: contactPhone
        let phoneRaw = (record["contactPhone"] as? String) ?? ""
        let contactPhone = phoneRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phoneRaw

        return MarketplaceLead(
            id: id,
            title: title,
            category: category,
            description: desc,
            location: addr,
            budgetType: budgetType,
            budgetMin: budgetMin,
            budgetMax: budgetMax,
            currency: currency,
            startDate: startDate,
            isUrgent: isUrgent,
            photoURLs: photoURLs,
            createdAt: createdAt,
            updatedAt: updatedAt,
            posterIdentity: posterIdentity,
            posterAppID: posterAppID,
            contactPhone: contactPhone
        )
    }

    private func decimal(from any: Any?) -> Decimal? {
        switch any {
        case let n as NSNumber: return Decimal(string: n.stringValue)
        case let s as String: return Decimal(string: s)
        default: return nil
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMe: Bool

    @State private var showQL = false
    @State private var qlItem: NSURL?

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if let media = message.mediaType {
                    if media == "photo" {
                        photoBubble()
                    } else if media == "video" {
                        videoBubble()
                    }
                } else {
                    textBubble()
                }
                Text(shortTime(message.sentAt))
                    .font(.caption2)
                    .foregroundStyle(TBTheme.offWhiteSecondary)
                    .padding(.leading, 6)
            }
            if !isMe { Spacer(minLength: 40) }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .sheet(isPresented: $showQL) {
            if let item = qlItem {
                QLPreviewControllerWrapper(item: item, isPresented: $showQL)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func textBubble() -> some View {
        Text(message.text)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isMe ? TBTheme.brand : Color.white.opacity(0.15))
            )
    }

    @ViewBuilder
    private func photoBubble() -> some View {
        let url = message.mediaLocalURL ?? message.mediaThumbnailURL
        if let url, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 220, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture {
                    if let preview = normalizedPreviewURL(for: url, kind: .photo) {
                        qlItem = preview as NSURL
                        showQL = true
                    }
                }
        } else {
            placeholderBubble(system: "photo")
        }
    }

    @ViewBuilder
    private func videoBubble() -> some View {
        let thumb = message.mediaThumbnailURL ?? message.mediaLocalURL
        ZStack {
            if let url = thumb, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12))
                    .frame(width: 220, height: 180)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = message.mediaLocalURL,
               let preview = normalizedPreviewURL(for: url, kind: .video) {
                qlItem = preview as NSURL
                showQL = true
            }
        }
    }

    @ViewBuilder
    private func placeholderBubble(system: String) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.12))
            .frame(width: 220, height: 160)
            .overlay {
                Image(systemName: system).font(.system(size: 32)).foregroundStyle(.white.opacity(0.9))
            }
    }

    private func shortTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df.string(from: date)
    }

    // MARK: - Quick Look normalization

    private enum PreviewKind { case photo, video }

    private func normalizedPreviewURL(for original: URL, kind: PreviewKind) -> URL? {
        // If it already has a reasonable extension, just use it.
        let ext = original.pathExtension.lowercased()
        if kind == .photo, ["jpg", "jpeg", "png", "heic", "gif", "tiff"].contains(ext) {
            return original
        }
        if kind == .video, ["mp4", "mov", "m4v"].contains(ext) {
            return original
        }

        // Copy to a temp QL folder with a proper extension
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("QLPreview", isDirectory: true)
        if !fm.fileExists(atPath: tmpDir.path) {
            try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        }
        let newExt = (kind == .photo) ? "jpg" : "mp4"
        var dest = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(newExt)

        do {
            // If we need to convert image bytes to jpg, do it; otherwise copy raw bytes.
            if kind == .photo, let data = try? Data(contentsOf: original), let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.95) {
                try jpg.write(to: dest, options: [.atomic])
            } else {
                // For video (or unknown but requested as video), just copy the file
                try fm.copyItem(at: original, to: dest)
            }
            var rvs = URLResourceValues()
            rvs.isExcludedFromBackup = true
            try? dest.setResourceValues(rvs)
            return dest
        } catch {
            return original // fallback; QL may still show generic data view, but we attempted normalization
        }
    }

    // MARK: - Native Quick Look wrapper with Close button

    private struct QLPreviewControllerWrapper: UIViewControllerRepresentable {
        let item: NSURL
        @Binding var isPresented: Bool

        // Use a UINavigationController so a top bar exists for the Close button.
        func makeUIViewController(context: Context) -> UINavigationController {
            let preview = QLPreviewController()
            preview.dataSource = context.coordinator

            let close = UIBarButtonItem(systemItem: .close)
            close.target = context.coordinator
            close.action = #selector(Coordinator.closeTapped)
            preview.navigationItem.rightBarButtonItem = close
            preview.navigationItem.leftItemsSupplementBackButton = false

            let nav = UINavigationController(rootViewController: preview)
            nav.modalPresentationStyle = .fullScreen
            nav.navigationBar.prefersLargeTitles = false
            nav.navigationBar.tintColor = .white
            nav.navigationBar.isTranslucent = true
            return nav
        }

        func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

        func makeCoordinator() -> Coordinator { Coordinator(item: item, isPresented: $isPresented) }

        final class Coordinator: NSObject, QLPreviewControllerDataSource {
            let item: NSURL
            @Binding var isPresented: Bool

            init(item: NSURL, isPresented: Binding<Bool>) {
                self.item = item
                self._isPresented = isPresented
            }

            func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
            func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { item }

            @objc func closeTapped() {
                isPresented = false
            }
        }
    }
}

