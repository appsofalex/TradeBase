import Foundation
import MapKit
import Combine

@MainActor
final class PlaceSearchViewModel: NSObject, ObservableObject {
    @Published var query: String = ""
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching: Bool = false

    private let completer = MKLocalSearchCompleter()
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        // Debounce user input a bit to reduce requests
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.completer.queryFragment = text
            }
            .store(in: &cancellables)

        completer.delegate = self
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> MKMapItem? {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request(completion: completion)
        // World directory by default (don’t constrain to region)
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems.first
    }
}

extension PlaceSearchViewModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.suggestions = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }
}
