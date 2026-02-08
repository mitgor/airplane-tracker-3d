import Foundation
import simd

// MARK: - Altitude Value (handles both Int and "ground" string from ADS-B APIs)

/// Represents altitude from ADS-B APIs, which can be an integer (feet) or the string "ground".
enum AltitudeValue: Codable, Sendable {
    case feet(Int)
    case ground

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .feet(intVal)
        } else if let strVal = try? container.decode(String.self), strVal == "ground" {
            self = .ground
        } else {
            self = .feet(0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .feet(let f):
            try container.encode(f)
        case .ground:
            try container.encode("ground")
        }
    }

    /// Convert to feet as Float. Ground returns 0.
    var asFeet: Float {
        switch self {
        case .feet(let f): return Float(f)
        case .ground: return 0
        }
    }
}

// MARK: - ADS-B V2 API Response (airplanes.live, adsb.lol)

/// Top-level response from airplanes.live and adsb.lol V2 APIs.
struct ADSBV2Response: Codable, Sendable {
    let ac: [ADSBV2Aircraft]?
    let msg: String?
    let now: Double?
    let total: Int?
    let ctime: Double?
    let ptime: Double?
}

/// Individual aircraft from V2 API response. All fields optional per API spec.
struct ADSBV2Aircraft: Codable, Sendable {
    let hex: String?
    let flight: String?
    let r: String?              // registration
    let t: String?              // ICAO type code (e.g., "B738", "A320")
    let desc: String?           // long type name
    let lat: Double?
    let lon: Double?
    let alt_baro: AltitudeValue?    // barometric altitude (number or "ground")
    let alt_geom: Int?              // geometric altitude (always number)
    let gs: Double?             // ground speed (knots)
    let track: Double?          // true track 0-359 degrees
    let baro_rate: Int?         // barometric vertical rate (ft/min)
    let geom_rate: Int?         // geometric vertical rate (ft/min)
    let squawk: String?
    let category: String?       // ADS-B emitter category A0-D7
    let emergency: String?
    let nav_heading: Double?
    let true_heading: Double?
    let mag_heading: Double?
    let ias: Int?               // indicated airspeed
    let tas: Int?               // true airspeed
    let mach: Double?
    let seen: Double?           // seconds since last message
    let seen_pos: Double?       // seconds since last position
    let messages: Int?
    let rssi: Double?
    let dbFlags: Int?           // 1=military, 2=interesting, 4=PIA, 8=LADD
}

// MARK: - dump1090 Local Response

/// Top-level response from dump1090 local receiver.
struct Dump1090Response: Codable, Sendable {
    let now: Double?
    let messages: Int?
    let aircraft: [Dump1090Aircraft]?
}

/// Individual aircraft from dump1090 response. All fields optional.
struct Dump1090Aircraft: Codable, Sendable {
    let hex: String?
    let flight: String?
    let lat: Double?
    let lon: Double?
    let altitude: AltitudeValue?    // number or "ground"
    let speed: Double?              // ground speed (knots)
    let track: Double?
    let vert_rate: Int?             // vertical rate (ft/min)
    let squawk: String?
    let seen: Double?
    let messages: Int?
    let rssi: Double?
}

// MARK: - Normalized Aircraft Model

/// Normalized aircraft data from any source. Used as the common internal format.
struct AircraftModel: Sendable {
    let hex: String
    var callsign: String
    var lat: Double
    var lon: Double
    var altitude: Float             // feet, 0 for ground
    var track: Float                // degrees 0-359
    var groundSpeed: Float          // knots
    var verticalRate: Float         // ft/min
    var squawk: String
    var category: String            // ADS-B category A0-D7 (empty if unavailable)
    var registration: String        // from r field (empty if unavailable)
    var typeCode: String            // ICAO type code from t field (empty if unavailable)
    var dbFlags: Int                // military/interesting flags (0 if unavailable)
}

// MARK: - Interpolated Aircraft State (render-ready)

/// Render-ready aircraft state with world-space position. Produced by interpolation each frame.
struct InterpolatedAircraftState: Sendable {
    /// World-space position: X (east/west), Y (altitude), Z (north/south)
    var position: SIMD3<Float>
    /// Heading in radians (0 = north, clockwise)
    var heading: Float
    /// Ground speed in knots
    var groundSpeed: Float
    /// Vertical rate in ft/min
    var verticalRate: Float
    /// Altitude in feet (for color mapping)
    var altitude: Float
    /// Aircraft category classification
    var category: AircraftCategory
    /// ICAO hex identifier
    var hex: String
    /// Flight callsign
    var callsign: String
}
