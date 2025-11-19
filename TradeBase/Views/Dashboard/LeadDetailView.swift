import SwiftUI
import MapKit
import Contacts
import CoreLocation
import QuickLook
import UniformTypeIdentifiers
import CloudKit
import UIKit

struct LeadDetailView: View {
    @Environment(\.appState) private var state
    let lead: MarketplaceLead
    @State private var region: MKCoordinateRegion?

    // Hydrated photos specifically for the detail view
    @State private var hydratedPhotoURLs: [URL] = []
    @State private var isHydratingPhotos = false

    // Single-image Quick Look state (matches Chat behavior)
    @State private var showQL = false
    @State private var qlItem: NSURL?

    // Phase 2: navigation to chat
    @State private var openConversation: Conversation? = nil
    @State private var isOpeningChat = false
    @State private var openError: String?

    // NEW: flag to control initial focus in ChatView
    @State private var focusComposerOnChatAppear = false

    // NEW: fallback alert when identity is missing
    @State private var showIdentityUnavailableAlert = false

    // NEW: WhatsApp error alert
    @State private var whatsappError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photosSection

                VStack(alignment: .leading, spacing: 8) {
                    Text(lead.title.isEmpty ? "Untitled job" : lead.title)
                        .font(.title2.bold())

                    HStack(spacing: 8) {
                        if let cat = lead.category {
                            badge(cat.displayName, systemImage: "wrench.adjustable")
                        }
                        if lead.isUrgent {
                            badge("Urgent", systemImage: "exclamationmark.triangle.fill", color: .red.opacity(0.2))
                        }
                    }

                    Text(lead.description)
                        .foregroundStyle(.secondary)
                }

                budgetSection
                timingSection
                locationSection

                if let identity = lead.posterIdentity {
                    customerSection(posterIdentity: identity)
                } else {
                    customerSection(posterIdentity: nil)
                }
            }
            .padding(16)
        }
        .background(TBTheme.gradient.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    state.toggleSave(lead: lead)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Image(systemName: state.isLeadSaved(lead.id) ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(state.isLeadSaved(lead.id) ? "Unsave lead" : "Save lead")
            }
        }
        .onAppear {
            if let coord = lead.location.coordinate {
                region = MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
            }
            Task { await hydratePhotosIfNeeded() }
        }
        .navigationTitle("Lead")
        .navigationBarTitleDisplayMode(.inline)
        .background(chatNavigationLink) // extracted to keep body simpler
        .alert("Couldn’t open chat", isPresented: Binding(
            get: { openError != nil },
            set: { if !$0 { openError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(openError ?? "Please try again.")
        }
        .alert("Customer identity unavailable", isPresented: $showIdentityUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("We can’t start a chat for this job because the customer’s identity isn’t attached to the listing.")
        }
        .sheet(isPresented: $showQL) {
            if let item = qlItem {
                QLPreviewControllerWrapper(item: item, isPresented: $showQL)
                    .ignoresSafeArea()
            }
        }
        .alert("Can’t open WhatsApp", isPresented: Binding(
            get: { whatsappError != nil },
            set: { if !$0 { whatsappError != nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(whatsappError ?? "Please check the phone number or install WhatsApp.")
        }
    }

    // Extracted to reduce type-checker complexity
    private var chatNavigationLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { openConversation != nil },
                set: { if !$0 { openConversation = nil } }
            )
        ) {
            if let convo = openConversation {
                ChatView(conversation: convo, focusOnAppear: focusComposerOnChatAppear)
                    .environment(\.appState, state)
            } else {
                EmptyView()
            }
        } label: { EmptyView() }
        .hidden()
    }

    // MARK: - Photo hydration

    private func hydratePhotosIfNeeded() async {
        if isHydratingPhotos { return }
        await MainActor.run { isHydratingPhotos = true }

        // 1) Prefer URLs already on the lead that decode.
        let usable = lead.photoURLs.filter { UIImage(contentsOfFile: $0.path) != nil }
        if !usable.isEmpty {
            await MainActor.run {
                self.hydratedPhotoURLs = usable
                self.isHydratingPhotos = false
            }
            return
        }

        // 2) Fallback: fetch the CloudKit record directly and read CKAsset.fileURL (same as ChatView).
        do {
            let db = state.cloudKitContainer.publicCloudDatabase
            let recID = CKRecord.ID(recordName: lead.id.uuidString)
            if let rec = try? await db.record(for: recID),
               let assets = rec["photoAssets"] as? [CKAsset] {
                var urls: [URL] = []
                for a in assets {
                    if let u = a.fileURL, UIImage(contentsOfFile: u.path) != nil {
                        urls.append(u)
                    }
                }
                await MainActor.run {
                    self.hydratedPhotoURLs = urls
                    self.isHydratingPhotos = false
                }
                return
            }
        } catch {
            // ignore; we’ll leave hydratedPhotoURLs empty and UI will simply show nothing
        }

        await MainActor.run { isHydratingPhotos = false }
    }

    @ViewBuilder
    private var photosSection: some View {
        let urls = hydratedPhotoURLs
        if !urls.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(urls.enumerated()), id: \.element) { idx, url in
                        if let img = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 260, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let preview = normalizedPreviewURL(for: url) {
                                        qlItem = preview as NSURL
                                        showQL = true
                                    }
                                }
                                .accessibilityLabel("Photo \(idx + 1) of \(urls.count). Double tap to view.")
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        } else if isHydratingPhotos {
            ProgressView().frame(height: 12).padding(.top, 4)
        }
    }

    private func badge(_ text: String, systemImage: String, color: Color = Color.white.opacity(0.12)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color))
    }

    @ViewBuilder
    private var budgetSection: some View {
        SectionCard(title: "Budget", icon: "sterlingsign.circle") {
            Text(budgetSummary())
                .foregroundStyle(TBTheme.subtext)
        }
    }

    @ViewBuilder
    private var timingSection: some View {
        SectionCard(title: "Timing", icon: "calendar") {
            if let start = lead.startDate {
                Text("Start: \(start.formatted(date: .abbreviated, time: .omitted))")
            } else {
                Text("Start date: Not specified")
            }
            Text("Posted: \(lead.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        SectionCard(title: "Location", icon: "location") {
            VStack(alignment: .leading, spacing: 12) {
                let addressLines: [String] = {
                    let lines = lead.location.formattedLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    if !lines.isEmpty { return lines }
                    let parts = [lead.location.line1, lead.location.city, lead.location.postcode]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    return parts
                }()
                if !addressLines.isEmpty {
                    Text(addressLines.joined(separator: ", "))
                        .accessibilityLabel("Address: \(addressLines.joined(separator: ", "))")
                } else {
                    Text("Address not specified")
                        .foregroundStyle(.secondary)
                }

                if let reg = region {
                    Map(position: .constant(.region(reg)))
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .simultaneousGesture(
                            TapGesture().onEnded { openInAppleMaps() }
                        )
                        .accessibilityLabel("Open in Apple Maps")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens Apple Maps for directions")
                }

                Button {
                    openInAppleMaps()
                } label: {
                    HStack(spacing: 8) {
                        Text("Open in")
                        Image("applemapsiconsvg")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(height: 18)
                            .offset(y: 1)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TBTheme.brand)
                .controlSize(.large)
                .clipShape(Capsule())
                .accessibilityLabel("Open in Apple Maps")
                .accessibilityHint("Opens Apple Maps for directions")
                .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private func customerSection(posterIdentity: String?) -> some View {
        SectionCard(title: "Customer", icon: "person") {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    PublicCustomerProfileView(identity: posterIdentity ?? "")
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(TBTheme.brand)
                        VStack(alignment: .leading) {
                            Text("View customer profile")
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("View customer profile")

                Button {
                    Task {
                        await messageCustomer(posterIdentity: posterIdentity)
                    }
                } label: {
                    Label("Message customer", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TBTheme.brand)
                .controlSize(.large)
                .clipShape(Capsule())
                .disabled(isOpeningChat)

                if let phone = lead.contactPhone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    orSeparator

                    Button {
                        openWhatsApp(with: phone)
                    } label: {
                        HStack(spacing: 8) {
                            Image("whatsappwhiteicon")
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Message in WhatsApp")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.145, green: 0.827, blue: 0.400))
                    .controlSize(.large)
                    .clipShape(Capsule())
                    .accessibilityLabel("Message in WhatsApp")
                    .accessibilityHint("Opens WhatsApp to chat with the customer")
                }
            }
        }
    }

    private var orSeparator: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            Text("or")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TBTheme.subtext)
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .accessibilityLabel("or")
    }

    private func messageCustomer(posterIdentity: String?) async {
        if let me = state.currentAuthIdentity(),
           let other = posterIdentity, !other.isEmpty,
           other != me {
            await openChat(with: other)
            return
        }
        if let appID = lead.posterAppID {
            do {
                if let other = try await state.cloudProfileStore.identity(forAppID: appID),
                   let me = state.currentAuthIdentity(),
                   !other.isEmpty,
                   other != me {
                    await openChat(with: other)
                    return
                }
            } catch { }
        }
        await MainActor.run { showIdentityUnavailableAlert = true }
    }

    private func openChat(with otherUserId: String) async {
        await MainActor.run {
            isOpeningChat = true
            openError = nil
        }

        var shouldFocus = false
        if let me = state.currentAuthIdentity() {
            if let existing = try? await state.messagingService.fetchConversations(for: me) {
                let already = existing.contains(where: { conv in
                    Set(conv.participantIds) == Set([me, otherUserId]) && conv.leadId == lead.id.uuidString
                })
                shouldFocus = !already
            } else {
                shouldFocus = true
            }
        }

        do {
            let convo = try await state.openOrCreateConversation(with: otherUserId, leadId: lead.id.uuidString)
            await MainActor.run {
                self.focusComposerOnChatAppear = shouldFocus
                self.openConversation = convo
                self.isOpeningChat = false
            }
        } catch {
            await MainActor.run {
                self.openError = error.localizedDescription
                self.isOpeningChat = false
            }
        }
    }

    // MARK: - WhatsApp

    private func openWhatsApp(with rawPhone: String) {
        let normalized = normalizePhoneForWhatsApp(rawPhone)
        guard !normalized.isEmpty else {
            whatsappError = "This job doesn’t include a valid phone number."
            return
        }
        if let schemeURL = URL(string: "whatsapp://send?phone=\(normalized)"),
           UIApplication.shared.canOpenURL(schemeURL) {
            UIApplication.shared.open(schemeURL, options: [:], completionHandler: nil)
            return
        }
        if let httpsURL = URL(string: "https://wa.me/\(normalized)") {
            UIApplication.shared.open(httpsURL, options: [:], completionHandler: nil)
        } else {
            whatsappError = "Couldn’t form a WhatsApp link for this number."
        }
    }

    private func normalizePhoneForWhatsApp(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for (i, ch) in trimmed.enumerated() {
            if ch.isNumber { result.append(ch) }
            else if ch == "+", i == 0 { result.append(ch) }
        }
        if result.hasPrefix("+") {
            return result.replacingOccurrences(of: "+", with: "")
        }
        return result
    }

    private func budgetSummary() -> String {
        let sym = CurrencyCatalog.symbol(for: lead.currency)
        switch lead.budgetType {
        case .quote:
            return "Quote requested"
        case .fixed:
            if let min = lead.budgetMin { return "\(sym)\(min as NSNumber)" }
            return "\(sym)—"
        case .hourly:
            if let min = lead.budgetMin { return "\(sym)\(min as NSNumber)/hr" }
            return "\(sym)—/hr"
        case .range:
            let minS = lead.budgetMin.map { "\($0 as NSNumber)" } ?? "—"
            let maxS = lead.budgetMax.map { "\($0 as NSNumber)" } ?? "—"
            return "\(sym)\(minS) – \(sym)\(maxS)"
        }
    }

    private func openInAppleMaps() {
        if let coord = lead.location.coordinate {
            let placemark = MKPlacemark(coordinate: coord, addressDictionary: nil)
            let item = MKMapItem(placemark: placemark)
            item.name = lead.title.isEmpty ? "Job Location" : lead.title
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        } else {
            let postal: CNPostalAddress = lead.location.cnPostalAddress
            Task {
                let geocoder = CLGeocoder()
                do {
                    if let result = try await geocoder.geocodePostalAddress(postal).first,
                       let coord = result.location?.coordinate {
                        let placemark = MKPlacemark(coordinate: coord, postalAddress: postal)
                        let item = MKMapItem(placemark: placemark)
                        item.name = lead.title.isEmpty ? "Job Location" : lead.title
                        item.openInMaps(launchOptions: [
                            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                        ])
                    }
                } catch {
                    // ignore
                }
            }
        }
    }

    // MARK: - Quick Look normalization (single image) – matches Chat

    private func normalizedPreviewURL(for original: URL) -> URL? {
        let ext = original.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "gif", "tiff"].contains(ext) {
            return original
        }
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("QLPreview", isDirectory: true)
        if !fm.fileExists(atPath: tmpDir.path) {
            try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        }
        let newExt = "jpg"
        var dest = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(newExt)

        do {
            if let data = try? Data(contentsOf: original),
               let img = UIImage(data: data),
               let jpg = img.jpegData(compressionQuality: 0.95) {
                try jpg.write(to: dest, options: [.atomic])
            } else {
                try FileManager.default.copyItem(at: original, to: dest)
            }
            var rvs = URLResourceValues()
            rvs.isExcludedFromBackup = true
            try? dest.setResourceValues(rvs)
            return dest
        } catch {
            return original
        }
    }
}

// MARK: - Native Quick Look wrapper with Close button (same as ChatView’s local wrapper)

private struct QLPreviewControllerWrapper: UIViewControllerRepresentable {
    let item: NSURL
    @Binding var isPresented: Bool

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
