import Foundation

// MARK: - Enrichment Result Types

/// Aircraft info from hexdb.io (registration, type, owner).
struct AircraftEnrichment: Sendable {
    let registration: String
    let manufacturer: String
    let type: String
    let icaoTypeCode: String
    let owner: String
}

/// Route info from adsbdb.com (airline, origin, destination).
struct RouteEnrichment: Sendable {
    let airline: String
    let originName: String
    let originCode: String
    let destinationName: String
    let destinationCode: String
}

// MARK: - EnrichmentService

/// Actor-based service for fetching aircraft enrichment data from external APIs.
/// Caches results (including negative lookups) to avoid repeated requests.
actor EnrichmentService {

    // MARK: - API Response Types

    /// hexdb.io response
    private struct HexDBResponse: Codable {
        let registration: String?
        let manufacturer: String?
        let icaoTypeCode: String?
        let type: String?
        let registeredOwners: String?

        private enum CodingKeys: String, CodingKey {
            case registration = "Registration"
            case manufacturer = "Manufacturer"
            case icaoTypeCode = "ICAOTypeCode"
            case type = "Type"
            case registeredOwners = "RegisteredOwners"
        }
    }

    /// adsbdb.com response structure
    private struct ADSBDBResponse: Codable {
        let response: ADSBDBInner?

        struct ADSBDBInner: Codable {
            let flightroute: FlightRoute?
        }

        struct FlightRoute: Codable {
            let airline: Airline?
            let origin: Airport?
            let destination: Airport?
        }

        struct Airline: Codable {
            let name: String?
        }

        struct Airport: Codable {
            let name: String?
            let iata_code: String?
            let icao_code: String?
        }
    }

    // MARK: - Caches

    /// Cache for aircraft info (nil value = negative cache / lookup failed)
    private var aircraftCache: [String: AircraftEnrichment?] = [:]

    /// Cache for route info (nil value = negative cache / lookup failed)
    private var routeCache: [String: RouteEnrichment?] = [:]

    /// Shared URLSession with short timeout
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    // MARK: - Aircraft Info (hexdb.io)

    /// Fetch aircraft registration, type, and owner info from hexdb.io.
    func fetchAircraftInfo(hex: String) async -> AircraftEnrichment? {
        // Check cache (including negative results)
        if let cached = aircraftCache[hex] {
            return cached
        }

        do {
            let urlString = "https://hexdb.io/api/v1/aircraft/\(hex)"
            guard let url = URL(string: urlString) else {
                aircraftCache[hex] = nil
                return nil
            }

            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(HexDBResponse.self, from: data)

            let enrichment = AircraftEnrichment(
                registration: response.registration ?? "",
                manufacturer: response.manufacturer ?? "",
                type: response.type ?? "",
                icaoTypeCode: response.icaoTypeCode ?? "",
                owner: response.registeredOwners ?? ""
            )
            aircraftCache[hex] = enrichment
            return enrichment
        } catch {
            aircraftCache[hex] = nil
            return nil
        }
    }

    // MARK: - Route Info (adsbdb.com)

    /// Fetch route origin/destination info from adsbdb.com.
    func fetchRouteInfo(callsign: String) async -> RouteEnrichment? {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return nil }

        // Check cache
        if let cached = routeCache[clean] {
            return cached
        }

        do {
            let urlString = "https://api.adsbdb.com/v0/callsign/\(clean)"
            guard let url = URL(string: urlString) else {
                routeCache[clean] = nil
                return nil
            }

            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(ADSBDBResponse.self, from: data)

            guard let route = response.response?.flightroute else {
                routeCache[clean] = nil
                return nil
            }

            let enrichment = RouteEnrichment(
                airline: route.airline?.name ?? "",
                originName: route.origin?.name ?? "",
                originCode: route.origin?.iata_code ?? route.origin?.icao_code ?? "",
                destinationName: route.destination?.name ?? "",
                destinationCode: route.destination?.iata_code ?? route.destination?.icao_code ?? ""
            )
            routeCache[clean] = enrichment
            return enrichment
        } catch {
            routeCache[clean] = nil
            return nil
        }
    }
}
