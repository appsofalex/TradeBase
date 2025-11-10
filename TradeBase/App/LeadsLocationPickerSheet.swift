// LeadsLocationPickerSheet.swift
import SwiftUI
import MapKit
import CoreLocation

struct LeadsLocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState

    // Initial state from caller
    var initialDisplayName: String
    var initialCoordinate: CLLocationCoordinate2D?

    // Callback on Done
    var onDone: (Result) -> Void

    struct Result {
        var displayName: String
        var coordinate: CLLocationCoordinate2D?
        var city: String?
        var postcode: String?
    }

    // Single free-form address field
    @State private var address: String = ""

    // We’ll keep a display name to return (defaults to the address text)
    @State private var pickedName: String

    // Map state
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278), // London default
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var locatedCoordinate: CLLocationCoordinate2D? = nil

    // Geocoding state (debounced; mirrors wizard/editor approach)
    @State private var geocodeTask: Task<Void, Never>? = nil
    @State private var isGeocoding: Bool = false
    @State private var geocodeError: String? = nil
    @State private var geocodeRequestID: UUID? = nil

    // Current location button state
    @State private var isLocating: Bool = false
    @State private var locateError: String? = nil

    // MARK: - Init

    init(
        initialDisplayName: String,
        initialCoordinate: CLLocationCoordinate2D?,
        onDone: @escaping (Result) -> Void
    ) {
        self.initialDisplayName = initialDisplayName
        self.initialCoordinate = initialCoordinate
        self.onDone = onDone
        _pickedName = State(initialValue: initialDisplayName)
        _address = State(initialValue: initialDisplayName)
        // region/locatedCoordinate will be set onAppear if initialCoordinate exists
    }

    var body: some View {
        @Bindable var bindableAppState = appState

        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        // Address field
                        TextField("Enter a city or postcode", text: $address)
                            .textFieldStyle(TBTextFieldStyle())
                            .onChange(of: address) { _ in
                                pickedName = address
                                scheduleGeocode()
                            }

                        // Use current location button
                        Button(action: useCurrentLocation) {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill")
                                Text(isLocating ? "Locating…" : "Use Current Location")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundStyle(TBTheme.brand)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.20))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(TBTheme.offWhite.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .disabled(isLocating)
                        .overlay(alignment: .trailing) {
                            if isLocating {
                                ProgressView().tint(TBTheme.brand)
                                    .padding(.trailing, 14)
                            }
                        }
                        .accessibilityLabel("Use current location")

                        if let locateError {
                            Text(locateError)
                                .font(.footnote)
                                .foregroundStyle(TBTheme.offWhiteSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Map preview
                        VStack(spacing: 8) {
                            ZStack {
                                Map(position: .constant(.region(region)), interactionModes: [.zoom, .pan]) {
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
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(TBTheme.offWhite.opacity(0.25), lineWidth: 1)
                                )

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

                        // Radius slider (0–100 km), bound to MarketFilter.radiusKm
                        VStack(spacing: 8) {
                            HStack {
                                Text("Radius")
                                    .font(.headline)
                                    .foregroundStyle(TBTheme.offWhite)
                                Spacer()
                                Text("\(Int(bindableAppState.marketFilter.radiusKm)) km")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                            }

                            // Styled slider container for a cleaner look
                            ZStack {
                                // Track background
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.20))
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(TBTheme.offWhite.opacity(0.25), lineWidth: 1)

                                // Native slider on top, tinted to brand
                                Slider(
                                    value: $bindableAppState.marketFilter.radiusKm,
                                    in: 0...100,
                                    step: 1
                                )
                                .tint(TBTheme.brand)
                                .padding(.horizontal, 10)
                            }
                            .frame(height: 44)
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Change Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelGeocoding()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        cancelGeocoding()
                        let trimmed = pickedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameToUse = trimmed.isEmpty ? address.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
                        onDone(Result(
                            displayName: nameToUse,
                            coordinate: locatedCoordinate,
                            city: nil,
                            postcode: nil
                        ))
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Seed map/annotation if we have an initial coordinate
            if let coord = initialCoordinate {
                locatedCoordinate = coord
                region = MKCoordinateRegion(center: coord,
                                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
            } else {
                // Keep London as default view
                region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
                                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
            }
            // Kick an initial geocode for the current address if it isn't empty
            let trimmed = initialDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                scheduleGeocode()
            }
        }
        .onDisappear {
            cancelGeocoding()
        }
    }

    // MARK: - Current location action

    private func useCurrentLocation() {
        locateError = nil
        isLocating = true
        cancelGeocoding() // stop any in-flight geocode while we locate

        Task { @MainActor in
            let locationService = CurrentLocationService()
            do {
                let loc = try await locationService.requestOneShotLocation()
                let rev = await locationService.reverseGeocode(loc)

                // Friendly display for the address field and pill
                let display: String = {
                    if let city = rev.city, !city.isEmpty { return city }
                    if let pc = rev.postcode, !pc.isEmpty { return pc }
                    let l1 = rev.line1 ?? ""
                    return l1.isEmpty ? "Current location" : l1
                }()

                // Center map + drop annotation
                let coord = loc.coordinate
                locatedCoordinate = coord
                withAnimation(.easeInOut) {
                    region = MKCoordinateRegion(center: coord,
                                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                }

                // Update the text field and picked name
                address = display
                pickedName = display

                // Immediately update AppState so the pill updates
                appState.leadsSearchLocation = AppState.LeadsSearchLocation(
                    displayName: display,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    city: rev.city,
                    postcode: rev.postcode
                )
            } catch {
                // Permission denied or other error
                locateError = "We couldn’t access your location. You can allow it in Settings."
            }
            isLocating = false
        }
    }
}

// MARK: - Geocoding helpers (debounced)

private extension LeadsLocationPickerSheet {
    func scheduleGeocode() {
        cancelGeocoding()

        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            geocodeError = nil
            // Do not clear locatedCoordinate automatically here; user may be editing.
            return
        }

        let token = UUID()
        geocodeRequestID = token

        geocodeTask = Task { @MainActor in
            guard !Task.isCancelled, geocodeRequestID == token else { return }
            isGeocoding = true
            geocodeError = nil

            // Debounce ~400ms
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { }

            guard !Task.isCancelled, geocodeRequestID == token else { return }
            await geocodeAddress(query: query, token: token)

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

    @MainActor
    func geocodeAddress(query: String, token: UUID) async {
        guard !Task.isCancelled, geocodeRequestID == token else { return }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(query, in: nil)

            guard !Task.isCancelled, geocodeRequestID == token else { return }

            guard let first = placemarks.first, let loc = first.location else {
                geocodeError = "We couldn’t find this place yet."
                return
            }
            let coord = loc.coordinate
            locatedCoordinate = coord
            withAnimation(.easeInOut) {
                region = MKCoordinateRegion(center: coord,
                                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
            }
            geocodeError = nil

            // Also push into AppState so the pill previews this typed place as well.
            let display = address.trimmingCharacters(in: .whitespacesAndNewlines)
            appState.leadsSearchLocation = AppState.LeadsSearchLocation(
                displayName: display.isEmpty ? "Selected place" : display,
                latitude: coord.latitude,
                longitude: coord.longitude,
                city: nil,
                postcode: nil
            )
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled, geocodeRequestID == token else { return }
            geocodeError = "Address lookup failed. Please refine it."
        }
    }
}

