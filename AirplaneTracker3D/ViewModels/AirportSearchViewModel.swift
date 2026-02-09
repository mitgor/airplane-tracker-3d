import Foundation
import simd

/// ViewModel powering the airport search panel. Provides:
/// - Text search filtering by airport name, IATA code, or ICAO code
/// - Nearby airport list sorted by distance from the current camera target
/// - Fly-to action that posts a notification for the Metal coordinator to animate
@MainActor
final class AirportSearchViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var searchText: String = ""
    @Published var showNearby: Bool = true

    // MARK: - Camera Position (updated externally)

    /// Current camera target in world space, used for nearby distance computation.
    var cameraTarget: SIMD3<Float> = .zero

    // MARK: - Airport Data

    /// All airports loaded from airports.json
    private let airports: [AirportData]

    /// Pre-lowercased search fields for fast filtering
    private let searchableFields: [(name: String, iata: String, icao: String)]

    // MARK: - Init

    init() {
        // Load airports from bundle (same pattern as AirportLabelManager)
        var loaded: [AirportData] = []
        if let url = Bundle.main.url(forResource: "airports", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                loaded = try JSONDecoder().decode([AirportData].self, from: data)
            } catch {
                #if DEBUG
                print("[AirportSearchViewModel] Failed to decode airports.json: \(error)")
                #endif
            }
        }
        self.airports = loaded

        // Pre-compute lowercased fields for search
        self.searchableFields = loaded.map { airport in
            (
                name: airport.name.lowercased(),
                iata: (airport.iata ?? "").lowercased(),
                icao: airport.icao.lowercased()
            )
        }
    }

    // MARK: - Computed Properties

    /// Airports matching the current search query (by name, IATA, or ICAO).
    /// Returns empty when searchText is empty. Capped at 10 results.
    var filteredAirports: [AirportData] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }

        var results: [AirportData] = []
        for i in 0..<airports.count {
            let fields = searchableFields[i]
            if fields.name.contains(query) ||
               fields.iata.contains(query) ||
               fields.icao.contains(query) {
                results.append(airports[i])
                if results.count >= 10 { break }
            }
        }
        return results
    }

    /// Nearby airports sorted by XZ Euclidean distance from the camera target.
    /// Returns the 10 closest airports.
    var nearbyAirports: [(airport: AirportData, distance: Float)] {
        let coordSystem = MapCoordinateSystem.shared
        let cx = cameraTarget.x
        let cz = cameraTarget.z

        var entries: [(airport: AirportData, distance: Float)] = []
        entries.reserveCapacity(airports.count)

        for airport in airports {
            let wx = coordSystem.lonToX(airport.lon)
            let wz = coordSystem.latToZ(airport.lat)
            let dx = wx - cx
            let dz = wz - cz
            let dist = sqrt(dx * dx + dz * dz)
            entries.append((airport: airport, distance: dist))
        }

        entries.sort { $0.distance < $1.distance }
        return Array(entries.prefix(10))
    }

    // MARK: - Actions

    /// Fly the camera to the given airport by posting a notification.
    /// The MetalView Coordinator observes this notification and starts the FlyToAnimator.
    func flyTo(airport: AirportData) {
        let coordSystem = MapCoordinateSystem.shared
        let x = coordSystem.lonToX(airport.lon)
        let z = coordSystem.latToZ(airport.lat)
        let position: [Float] = [x, 0.5, z]

        NotificationCenter.default.post(
            name: .flyToAirport,
            object: nil,
            userInfo: ["position": position]
        )

        // Clear search after fly-to
        searchText = ""
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let flyToAirport = Notification.Name("flyToAirport")
    static let toggleSearch = Notification.Name("toggleSearch")
    static let cameraTargetUpdated = Notification.Name("cameraTargetUpdated")
}
