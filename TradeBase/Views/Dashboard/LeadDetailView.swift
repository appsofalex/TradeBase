import SwiftUI
import MapKit
import Contacts
import CoreLocation
import QuickLook
import UniformTypeIdentifiers

struct LeadDetailView: View {
    @Environment(\.appState) private var state
    let lead: MarketplaceLead
    @State private var region: MKCoordinateRegion?

    // Quick Look gallery state
    @State private var showGallery = false
    @State private var galleryIndex: Int = 0

    // Phase 2: navigation to chat
    @State private var openConversation: Conversation? = nil
    @State private var isOpeningChat = false
    @State private var openError: String?

    // NEW: fallback alert when identity is missing
    @State private var showIdentityUnavailableAlert = false

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
                    // Always render the Customer section, force show the Message button with fallback
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
        }
        .fullScreenCover(isPresented: $showGallery) {
            ImageQuickLookPreview(urls: previewableImageURLs(from: lead.photoURLs), startIndex: galleryIndex)
                .ignoresSafeArea()
        }
        .navigationTitle("Lead")
        .navigationBarTitleDisplayMode(.inline)
        // Push ChatView instead of presenting it as a sheet
        .background(
            NavigationLink(
                isActive: Binding(
                    get: { openConversation != nil },
                    set: { if !$0 { openConversation = nil } }
                )
            ) {
                if let convo = openConversation {
                    ChatView(conversation: convo)
                        .environment(\.appState, state)
                } else {
                    EmptyView()
                }
            } label: { EmptyView() }
            .hidden()
        )
        .alert("Couldn’t open chat", isPresented: Binding(
            get: { openError != nil },
            set: { if !$0 { openError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(openError ?? "Please try again.")
        }
        // NEW: identity unavailable alert
        .alert("Customer identity unavailable", isPresented: $showIdentityUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("We can’t start a chat for this job because the customer’s identity isn’t attached to the listing.")
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        if lead.photoURLs.isEmpty {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .frame(height: 160)
                .overlay {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(lead.photoURLs.enumerated()), id: \.element) { idx, url in
                        if let img = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 260, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    galleryIndex = idx
                                    showGallery = true
                                }
                                .accessibilityLabel("Photo \(idx + 1) of \(lead.photoURLs.count). Double tap to view.")
                        } else {
                            ZStack {
                                Color.white.opacity(0.06)
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 260, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                galleryIndex = idx
                                showGallery = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
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
            Text(lead.createdAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        SectionCard(title: "Location", icon: "map") {
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

                // Full-width, prominent mint button to match "Message customer"
                Button {
                    openInAppleMaps()
                } label: {
                    Label("Open in Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TBTheme.brand)
                .controlSize(.large)
                .clipShape(Capsule())
                .accessibilityHint("Opens Apple Maps for directions")
                .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private func customerSection(posterIdentity: String?) -> some View {
        SectionCard(title: "Customer", icon: "person.crop.circle") {
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

                // Always show the "Message customer" pill with fallback behavior.
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
            }
        }
    }

    private func messageCustomer(posterIdentity: String?) async {
        // If identity is available and not me, open chat.
        if let me = state.currentAuthIdentity(),
           let other = posterIdentity, !other.isEmpty,
           other != me {
            await openChat(with: other)
            return
        }

        // Fallback: try to resolve from posterAppID
        if let appID = lead.posterAppID {
            do {
                if let other = try await state.cloudProfileStore.identity(forAppID: appID),
                   let me = state.currentAuthIdentity(),
                   !other.isEmpty,
                   other != me {
                    await openChat(with: other)
                    return
                }
            } catch {
                // Ignore resolution error; we’ll show the alert below if we can’t resolve
            }
        }

        // Still no identity — show alert
        await MainActor.run { showIdentityUnavailableAlert = true }
    }

    private func openChat(with otherUserId: String) async {
        await MainActor.run {
            isOpeningChat = true
            openError = nil
        }
        do {
            let convo = try await state.openOrCreateConversation(with: otherUserId, leadId: lead.id.uuidString)
            await MainActor.run {
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

    private func previewableImageURLs(from urls: [URL]) -> [URL] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("QLPreviewImages", isDirectory: true)
        if !fm.fileExists(atPath: tmp.path) {
            try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        }

        return urls.compactMap { url in
            guard fm.fileExists(atPath: url.path) else { return nil }
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty { return url }

            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let inferred = inferImageType(from: data) else {
                return url
            }

            let newExt = preferredExtension(for: inferred) ?? "jpg"
            let base = url.deletingPathExtension().lastPathComponent
            var newURL = tmp.appendingPathComponent(base).appendingPathExtension(newExt)

            if fm.fileExists(atPath: newURL.path) == false {
                do {
                    try data.write(to: newURL, options: [.atomic])
                    var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true
                    try? newURL.setResourceValues(rvs)
                } catch {
                    return url
                }
            }
            return newURL
        }
    }

    private func inferImageType(from data: Data) -> UTType? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if data.count >= 12 {
            let box = data.prefix(12)
            if box[4...7] == Data([0x66, 0x74, 0x79, 0x70]) {
                let brand = box[8...11]
                let brands: [Data] = [
                    Data("heic".utf8), Data("heif".utf8),
                    Data("hevc".utf8), Data("mif1".utf8), Data("msf1".utf8)
                ]
                if brands.contains(brand) { return .heic }
            }
        }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return .gif }
        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return .tiff
        }
        return nil
    }

    private func preferredExtension(for type: UTType) -> String? {
        if type.conforms(to: .jpeg) { return "jpg" }
        if type.conforms(to: .png) { return "png" }
        if type.conforms(to: .heic) { return "heic" }
        if type.conforms(to: .gif) { return "gif" }
        if type.conforms(to: .tiff) { return "tiff" }
        return type.preferredFilenameExtension
    }
}

// MARK: - Native Quick Look image preview

private struct ImageQuickLookPreview: UIViewControllerRepresentable {
    let urls: [URL]
    let startIndex: Int

    func makeCoordinator() -> Coordinator { Coordinator(urls: urls) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.currentPreviewItemIndex = max(0, min(startIndex, urls.count - 1))
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let items: [NSURL]
        init(urls: [URL]) {
            self.items = urls.map { $0 as NSURL }
        }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { items.count }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            items[index]
        }
    }
}
