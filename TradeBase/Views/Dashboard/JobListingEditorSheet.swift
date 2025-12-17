//
//  JobListingEditorSheet.swift
//  TradeBase
//

import SwiftUI
import MapKit
import PhotosUI

struct JobListingEditorSheet: View {
    let listing: JobListing
    let showPublish: Bool
    let onSave: (JobListing) -> Void
    let onPublish: (JobListing) -> Void

    // New: allow caller to set the nav title (default keeps “Post Job”)
    let viewTitle: String

    @Environment(\.dismiss) private var dismiss

    // Working copies (hydrated on appear)
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var category: TradeType? = nil

    @State private var line1: String = ""
    @State private var city: String = ""
    @State private var postcode: String = ""

    @State private var budgetType: JobBudgetType = .quote
    @State private var budgetMin: Decimal? = nil
    @State private var budgetMax: Decimal? = nil
    @State private var currency: String = "GBP"

    @State private var startDate: Date? = nil
    @State private var isUrgent: Bool = false

    // NEW: phone (editor-only for now; not wired to store or leads)
    @State private var phone: String = ""

    // Photos working copy
    @State private var photos: [URL] = []
    @State private var showingPhotoPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isAddingPhotos = false
    @State private var photoAddError: String? = nil

    // MARK: - Map/geocoding state (mirrors JobPostingWizard)
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var locatedCoordinate: CLLocationCoordinate2D? = nil

    // iOS 17+ camera that drives the SwiftUI Map
    @State private var camera: MapCameraPosition = .automatic

    @State private var geocodeTask: Task<Void, Never>? = nil
    @State private var isGeocoding: Bool = false
    @State private var geocodeError: String? = nil
    @State private var geocodeRequestID: UUID? = nil

    // Keyboard visibility
    @State private var isKeyboardVisible: Bool = false
    private let keyboardObserver = KeyboardObserver()

    // Ensure we only hydrate once to avoid wiping user edits if parent view re-renders
    @State private var didHydrateOnce = false

    // NEW: controls the popover presentation of the date picker
    @State private var isShowingDatePicker = false

    // Objectionable content filtering state
    private let contentFilter = ObjectionableContentFilter()
    @State private var flaggedTerms: [String] = []
    @State private var showObjectionableAlert = false
    @State private var objectionableMessage: String? = nil

    // Validation roughly aligned to wizard
    private var canSave: Bool {
        let hasBasics = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasLocation = !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                          !postcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasBudget: Bool = {
            switch budgetType {
            case .quote: return true
            case .fixed, .hourly: return budgetMin != nil
            case .range: return budgetMin != nil && budgetMax != nil
            }
        }()
        // New: require a valid international phone number before posting/saving
        let hasValidPhone = isPhoneValidE164(phone)
        return hasBasics && hasLocation && hasBudget && hasValidPhone
    }

    init(listing: JobListing,
         showPublish: Bool,
         onSave: @escaping (JobListing) -> Void,
         onPublish: @escaping (JobListing) -> Void,
         viewTitle: String = "Job Post") {
        self.listing = listing
        self.showPublish = showPublish
        self.onSave = onSave
        self.onPublish = onPublish
        self.viewTitle = viewTitle
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Basics
                        sectionHeader("Basics")
                        VStack(spacing: 12) {
                            TextField("Give your job a title", text: $title)
                                .textFieldStyle(TBTextFieldStyle())
                                .onChange(of: title) { _, _ in revalidateObjectionable() }

                            TextField("Describe the work", text: $description, axis: .vertical)
                                .textFieldStyle(TBTextFieldStyle())
                                .lineLimit(3...6)
                                .onChange(of: description) { _, _ in revalidateObjectionable() }

                            if !flaggedTerms.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    Text("Your post contains objectionable terms: \(flaggedTerms.joined(separator: ", ")). Please remove them before publishing.")
                                        .font(.footnote)
                                        .foregroundStyle(.yellow)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.12))
                                )
                            }

                            // Category dropdown (native Menu + Picker)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Category")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                                    .padding(.top, 12) // unified top spacing

                                Menu {
                                    if category != nil {
                                        Button(role: .destructive) {
                                            category = nil
                                        } label: {
                                            Label("Clear selection", systemImage: "xmark.circle")
                                        }
                                        Divider()
                                    }

                                    Picker("Category", selection: Binding(get: {
                                        category ?? TradeType.allCases.first
                                    }, set: { newValue in
                                        category = newValue
                                    })) {
                                        ForEach(TradeType.allCases) { type in
                                            Text(type.displayName).tag(Optional(type))
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(category?.displayName ?? "Select a category")
                                            .foregroundStyle(category == nil ? TBTheme.offWhiteSecondary : TBTheme.offWhite)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .foregroundStyle(TBTheme.offWhiteSecondary)
                                    }
                                    .padding()
                                    .background(Color.black.opacity(0.2))
                                    .cornerRadius(12)
                                }
                                .menuStyle(.automatic)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Photos
                        sectionHeader("Photos")
                        VStack(spacing: 12) {
                            HStack {
                                addPhotosButton
                                Spacer()
                            }

                            if isAddingPhotos {
                                HStack(spacing: 8) {
                                    ProgressView().tint(TBTheme.brand)
                                    Text("Adding photos…")
                                        .foregroundStyle(TBTheme.offWhiteSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if let photoAddError {
                                Text(photoAddError)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !photos.isEmpty {
                                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(photos, id: \.self) { url in
                                        ZStack(alignment: .topTrailing) {
                                            thumbnailView(for: url)
                                                .frame(height: 90)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(TBTheme.offWhite.opacity(0.15), lineWidth: 1)
                                                )

                                            Button {
                                                removePhoto(url)
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(6)
                                        }
                                    }
                                }
                            } else {
                                Text("Add photos to help tradespeople understand the job.")
                                    .font(.footnote)
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Location
                        sectionHeader("Location")
                        VStack(spacing: 12) {
                            TextField("Address", text: $line1)
                                .textFieldStyle(TBTextFieldStyle())
                                .onChange(of: line1) { _ in scheduleGeocode() }

                            TextField("City", text: $city)
                                .textFieldStyle(TBTextFieldStyle())
                                .onChange(of: city) { _ in scheduleGeocode() }

                            TextField("Postcode", text: $postcode)
                                .textFieldStyle(TBTextFieldStyle())
                                .textInputAutocapitalization(.characters)
                                .onChange(of: postcode) { _ in scheduleGeocode() }

                            // Map preview
                            VStack(spacing: 8) {
                                ZStack {
                                    Map(position: $camera, interactionModes: [.zoom, .pan]) {
                                        if let coord = locatedCoordinate {
                                            Annotation("",
                                                       coordinate: coord) {
                                                ZStack {
                                                    Circle().fill(TBTheme.brand).frame(width: 14, height: 14)
                                                    Circle().stroke(Color.white, lineWidth: 2).frame(width: 18, height: 18)
                                                }
                                            }
                                        }
                                    }
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(TBTheme.offWhite.opacity(0.25), lineWidth: 1)
                                    )
                                    .overlay(alignment: .bottomTrailing) {
                                        Button(action: recenterMap) {
                                            Image(systemName: "location.fill")
                                                .symbolRenderingMode(.hierarchical)
                                                .foregroundStyle(.white)
                                                .padding(10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(.ultraThinMaterial)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .padding(10)
                                        .accessibilityLabel("Recenter on pin")
                                    }

                                    if isGeocoding {
                                        ProgressView().tint(TBTheme.offWhite)
                                    }
                                }

                                if let geocodeError {
                                    Text(geocodeError)
                                        .font(.footnote)
                                        .foregroundStyle(TBTheme.offWhiteSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 20)

                        // Budget
                        sectionHeader("Costs")
                        VStack(spacing: 12) {
                            Picker("Budget type", selection: $budgetType) {
                                ForEach(JobBudgetType.uiOrder) { t in
                                    Text(t.displayName).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)

                            // Currency dropdown (matches wizard)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Currency")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                                    .padding(.top, 12) // extra breathing room from the segmented control

                                Menu {
                                    Picker("Currency", selection: $currency) {
                                        ForEach(CurrencyCatalog.all) { opt in
                                            Text("\(opt.code) – \(opt.localizedName)")
                                                .tag(opt.code)
                                        }
                                    }
                                } label: {
                                    HStack {
                                        let sym = CurrencyCatalog.symbol(for: currency)
                                        Text("\(currency)  \(sym)")
                                            .foregroundStyle(TBTheme.offWhite)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .foregroundStyle(TBTheme.offWhiteSecondary)
                                    }
                                    .padding()
                                    .background(Color.black.opacity(0.2))
                                    .cornerRadius(12)
                                }
                            }

                            switch budgetType {
                            case .quote:
                                Text("Tradespeople will provide a quote.")
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                            case .fixed, .hourly:
                                CurrencyAmountField(title: "Amount",
                                                    value: Binding(get: { budgetMin ?? 0 }, set: { budgetMin = $0 }),
                                                    currencyCode: currency)

                            case .range:
                                CurrencyAmountField(title: "Min",
                                                    value: Binding(get: { budgetMin ?? 0 }, set: { budgetMin = $0 }),
                                                    currencyCode: currency)
                                CurrencyAmountField(title: "Max",
                                                    value: Binding(get: { budgetMax ?? 0 }, set: { budgetMax = $0 }),
                                                    currencyCode: currency)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Timing
                        sectionHeader("Timing")
                        VStack(spacing: 12) {
                            Toggle("Urgent", isOn: $isUrgent)
                                .tint(TBTheme.brand)

                            // Compact row that opens a popover DatePicker which auto-dismisses on select
                            Button {
                                isShowingDatePicker = true
                            } label: {
                                HStack {
                                    Text("Preferred start date")
                                    Spacer()
                                    Text(formattedDate(startDate))
                                        .foregroundStyle(TBTheme.brand)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.white.opacity(0.12)))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $isShowingDatePicker) {
                                VStack(alignment: .leading, spacing: 12) {
                                    DatePicker(
                                        "Preferred start date",
                                        selection: Binding(get: { startDate ?? Date() }, set: { startDate = $0 }),
                                        displayedComponents: [.date]
                                    )
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                    .tint(TBTheme.brand)
                                    .onChange(of: startDate) { _, _ in
                                        Task { @MainActor in
                                            try? await Task.sleep(nanoseconds: 120_000_000)
                                            isShowingDatePicker = false
                                        }
                                    }

                                    Button("Done") { isShowingDatePicker = false }
                                        .font(.headline)
                                        .foregroundStyle(TBTheme.brand)
                                }
                                .padding()
                                .frame(width: 320)
                                .presentationBackground(.ultraThinMaterial)
                            }

                            // NEW: Phone number (editor-only)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Phone")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                                    .padding(.top, 12) // unified spacing from the row above

                                // No placeholder; prefilled with +44 on hydrate
                                TextField("", text: $phone)
                                    .textFieldStyle(TBTextFieldStyle())
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                                    .foregroundStyle(TBTheme.offWhite)
                                    .onChange(of: phone) { _, newValue in
                                        // Keep the leading +44 preset if user clears everything
                                        if newValue.isEmpty {
                                            phone = "+44"
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Post it! button — match CustomerHomeView CTA (full-width Capsule)
                        if showPublish {
                            VStack {
                                Button(action: postItTapped) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "paperplane.fill")
                                        Text("Post it!")
                                            .fontWeight(.bold)
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(TBTheme.brand))
                                }
                                .buttonStyle(.plain)
                                .disabled(!canSave)
                                .opacity(canSave ? 1 : 0.6)
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer().frame(height: 16)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(viewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if showPublish {
                        Menu {
                            Button("Save as Draft") {
                                let updated = buildUpdatedListing(statusOverride: .draft)
                                onSave(updated)
                                dismiss()
                            }
                            Button("Publish") {
                                // Validate objectionable content before publishing
                                if let warning = objectionableWarningIfNeeded() {
                                    objectionableMessage = warning
                                    showObjectionableAlert = true
                                    return
                                }
                                let updated = buildUpdatedListing(statusOverride: .active)
                                onPublish(updated)
                                dismiss()
                            }
                        } label: {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundStyle(canSave ? TBTheme.brand : TBTheme.offWhiteSecondary)
                        }
                        .disabled(!canSave)
                    } else {
                        Button("Save") {
                            let updated = buildUpdatedListing()
                            onSave(updated)
                            dismiss()
                        }
                        .disabled(!canSave)
                    }
                }
            }
        }
        .onAppear {
            if !didHydrateOnce {
                hydrateFromListing()
                didHydrateOnce = true
                scheduleGeocode()
                camera = .region(region)
                // Initial validation for objectionable content
                revalidateObjectionable()
            }
            keyboardObserver.start { visible in
                withAnimation(.easeInOut(duration: 0.25)) {
                    isKeyboardVisible = visible
                }
            }
        }
        .onDisappear {
            cancelGeocoding()
            keyboardObserver.stop()
        }
        .onChange(of: photoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await importPickedPhotos(newItems) }
        }
        .alert("Please remove objectionable content", isPresented: $showObjectionableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(objectionableMessage ?? "Your post contains objectionable words.")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(TBTheme.offWhiteSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }

    private func hydrateFromListing() {
        title = listing.title
        description = listing.description
        category = listing.category
        line1 = listing.location.line1
        city = listing.location.city
        postcode = listing.location.postcode
        budgetType = listing.budgetType
        budgetMin = listing.budgetMin
        budgetMax = listing.budgetMax
        currency = listing.currency
        startDate = listing.startDate
        isUrgent = listing.isUrgent
        photos = listing.photos
        // If there is an existing phone, keep it; otherwise seed "+44"
        let existing = listing.contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        phone = existing.isEmpty ? "+44" : existing
    }

    private func buildUpdatedListing(statusOverride: JobListingStatus? = nil) -> JobListing {
        var updated = listing
        updated.title = title
        updated.description = description
        updated.category = category
        updated.location = Address(line1: line1, city: city, postcode: postcode)
        updated.budgetType = budgetType
        updated.budgetMin = budgetMin
        updated.budgetMax = budgetMax
        updated.currency = currency
        updated.startDate = startDate
        updated.isUrgent = isUrgent
        updated.photos = photos
        // NEW: persist phone back to the model so CloudKit upsert can mirror it
        updated.contactPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if let statusOverride { updated.status = statusOverride }
        return updated
    }

    // MARK: - Objectionable content validation

    private func revalidateObjectionable() {
        flaggedTerms = contentFilter.flaggedTerms(in: [title, description])
    }

    private func objectionableWarningIfNeeded() -> String? {
        revalidateObjectionable()
        guard !flaggedTerms.isEmpty else { return nil }
        let list = flaggedTerms.joined(separator: ", ")
        return "Your post contains objectionable terms: \(list). Please remove them before publishing."
    }

    // MARK: - Photos

    private var addPhotosButton: some View {
        PhotosPicker(
            selection: $photoPickerItems,
            maxSelectionCount: 12,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(TBTheme.brand.opacity(0.2))
                        .frame(width: 30, height: 30)
                    Image(systemName: "plus")
                        .foregroundStyle(TBTheme.brand)
                        .font(.system(size: 14, weight: .bold))
                }
                Text("Add Photos")
                    .font(.headline)
                    .foregroundStyle(TBTheme.brand)
                if isAddingPhotos {
                    ProgressView().tint(TBTheme.brand)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TBTheme.offWhite.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAddingPhotos)
        .accessibilityLabel("Add photos")
    }

    private func thumbnailView(for url: URL) -> some View {
        Group {
            if let img = PhotoService.shared.thumbnail(for: url, targetSize: CGSize(width: 200, height: 200)) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func removePhoto(_ url: URL) { photos.removeAll { $0 == url }; PhotoService.shared.delete(url) }

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        photoAddError = nil
        isAddingPhotos = true
        defer { isAddingPhotos = false }
        var newURLs: [URL] = []
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    if let url = await PhotoService.shared.save(data) {
                        newURLs.append(url)
                    }
                }
            } catch { photoAddError = "Some photos couldn’t be added." }
        }
        if !newURLs.isEmpty {
            let combined = photos + newURLs
            var seen: Set<String> = []
            photos = combined.filter { url in
                let key = url.path
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
        }
        await MainActor.run { photoPickerItems = [] }
    }

    private func postItTapped() {
        guard canSave else { return }
        // Validate objectionable content before publishing
        if let warning = objectionableWarningIfNeeded() {
            objectionableMessage = warning
            showObjectionableAlert = true
            return
        }
        let updated = buildUpdatedListing(statusOverride: .active)
        onPublish(updated)
        dismiss()
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let d = date else { return "Select" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: d)
    }

    private func recenterMap() {
        let targetCoord = locatedCoordinate ?? region.center
        let targetRegion = MKCoordinateRegion(
            center: targetCoord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        region = targetRegion
        withAnimation(.easeInOut(duration: 0.25)) { camera = .region(targetRegion) }
    }
}

private struct CurrencyAmountField: View {
    let title: String
    @Binding var value: Decimal
    var currencyCode: String

    @State private var text: String = ""
    private let numberFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 0
        nf.usesGroupingSeparator = false
        return nf
    }()

    private var symbol: String { CurrencyCatalog.symbol(for: currencyCode) }

    var body: some View {
        HStack(spacing: 8) {
            Text(symbol)
                .font(.headline)
                .foregroundStyle(TBTheme.offWhite)
            TextField(title, text: Binding(
                get: { text },
                set: { newText in
                    let cleaned = newText
                        .replacingOccurrences(of: symbol, with: "")
                        .replacingOccurrences(of: " ", with: "")
                    text = cleaned
                    if let dec = Decimal(string: cleaned) { value = dec }
                }
            ))
            .keyboardType(.decimalPad)
            .foregroundStyle(TBTheme.offWhite)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TBTheme.offWhite.opacity(0.25), lineWidth: 1)
        )
        .onAppear { syncTextFromValue() }
        .onChange(of: value) { _, _ in syncTextFromValueIfNeeded() }
        .onChange(of: currencyCode) { _, _ in syncTextFromValueIfNeeded() }
    }

    private func syncTextFromValue() {
        if let s = numberFormatter.string(from: value as NSDecimalNumber) {
            text = s
        } else {
            text = (value as NSNumber).stringValue
        }
    }

    private func syncTextFromValueIfNeeded() {
        if let current = Decimal(string: text) {
            if current != value { syncTextFromValue() }
        } else {
            syncTextFromValue()
        }
    }
}

private extension JobListingEditorSheet {
    func scheduleGeocode() {
        cancelGeocoding()
        let query = buildPostalAddressString()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            geocodeError = nil
            locatedCoordinate = nil
            return
        }
        let token = UUID()
        geocodeRequestID = token
        geocodeTask = Task { @MainActor in
            guard !Task.isCancelled, geocodeRequestID == token else { return }
            isGeocoding = true
            geocodeError = nil
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { }
            guard !Task.isCancelled, geocodeRequestID == token else { return }
            await geocodeCurrentAddress(for: token)
            guard !Task.isCancelled, geocodeRequestID == token else { return }
            isGeocoding = false
        }
    }

    func cancelGeocoding() {
        geocodeTask?.cancel()
        geocodeTask = nil
        geocodeRequestID = nil
        isGeocoding = false
    }

    func buildPostalAddressString() -> String {
        let parts = [line1, city, postcode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }

    @MainActor
    func geocodeCurrentAddress(for token: UUID) async {
        guard !Task.isCancelled, geocodeRequestID == token else { return }
        let query = buildPostalAddressString()
        guard !query.isEmpty else { return }
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(query, in: nil)
            guard !Task.isCancelled, geocodeRequestID == token else { return }
            guard let first = placemarks.first, let loc = first.location else {
                geocodeError = "We couldn’t find this address yet."
                locatedCoordinate = nil
                return
            }
            let coord = loc.coordinate
            locatedCoordinate = coord
            withAnimation(.easeInOut) {
                region = MKCoordinateRegion(center: coord,
                                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                camera = .region(region)
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, geocodeRequestID == token else { return }
            geocodeError = "Address lookup failed. Please refine it."
            locatedCoordinate = nil
        }
    }

    // MARK: - Phone validation (E.164 style)
    // Accepts "+<digits>" where total digits count is 8...15.
    func isPhoneValidE164(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "+" else { return false }
        // Keep only + and digits for validation
        var cleaned = "+"
        for (i, ch) in trimmed.enumerated() {
            if ch.isNumber { cleaned.append(ch) }
            else if ch == "+", i == 0 { continue } // already appended
            // ignore spaces, dashes, parentheses, etc.
        }
        // Must be "+" followed by digits only
        guard cleaned.count > 1 else { return false }
        // Digit count (excluding '+')
        let digits = cleaned.dropFirst()
        let count = digits.count
        guard (8...15).contains(count) else { return false }
        // All digits check (already filtered)
        return digits.allSatisfy { $0.isNumber }
    }
}
