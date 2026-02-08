import Foundation

/// Aircraft category classification for rendering mesh selection.
/// Each category maps to a distinct procedural 3D mesh.
enum AircraftCategory: CaseIterable, Sendable {
    case jet        // narrowbody (default)
    case widebody   // wide-body long-haul
    case helicopter // rotary wing
    case small      // GA prop plane
    case military   // military aircraft
    case regional   // regional jet/turboprop

    /// Classify an aircraft using a 4-priority chain:
    /// 1. dbFlags (military flag)
    /// 2. ADS-B emitter category (A0-D7)
    /// 3. ICAO type code lookup
    /// 4. Callsign + flight parameter heuristics
    static func classify(_ aircraft: AircraftModel) -> AircraftCategory {
        // Priority 1: dbFlags for military identification
        if aircraft.dbFlags & 1 != 0 { return .military }

        // Priority 2: ADS-B category field (A0-D7)
        switch aircraft.category {
        case "A1":          return .small       // Light (<15,500 lbs)
        case "A2":          return .small       // Small (15,500-75,000 lbs)
        case "A3":          return .regional    // Large (75,000-300,000 lbs)
        case "A4":          return .jet         // High vortex large (e.g. B757)
        case "A5":          return .widebody    // Heavy (>300,000 lbs)
        case "A6":          return .widebody    // High performance (>5g, >400kts)
        case "A7":          return .helicopter  // Rotorcraft
        case "B1", "B2":    return .small       // Glider / lighter than air
        default:            break
        }

        // Priority 3: ICAO type code (t field)
        let type = aircraft.typeCode.uppercased()
        if !type.isEmpty {
            // Helicopter type codes
            let heliTypes = ["R22", "R44", "R66", "B06", "B47", "EC35", "EC45", "AS50",
                             "S76", "B412", "A109", "B429", "H60", "UH1"]
            if heliTypes.contains(where: { type.hasPrefix($0) }) { return .helicopter }

            // Wide-body type codes
            let wideTypes = ["B74", "B77", "B78", "A33", "A34", "A35", "A38", "B76", "MD11"]
            if wideTypes.contains(where: { type.hasPrefix($0) }) { return .widebody }

            // Military type codes
            let milTypes = ["F16", "F15", "F18", "F22", "F35", "C17", "C130", "C5", "KC",
                            "B1", "B2", "B52", "E3", "E6", "P8", "V22"]
            if milTypes.contains(where: { type.hasPrefix($0) }) { return .military }
        }

        // Priority 4: Callsign + flight parameter heuristics
        let callsign = aircraft.callsign.uppercased()
        let alt = aircraft.altitude
        let speed = aircraft.groundSpeed

        // Helicopter patterns (low and slow with heli-associated callsigns)
        if alt < 3000 && speed < 150 {
            let heliCallsigns = ["LIFE", "MED", "HELI", "COAST", "RESCUE"]
            if heliCallsigns.contains(where: { callsign.hasPrefix($0) }) { return .helicopter }
            // N-number followed by digit at low altitude/speed could be helicopter
            if callsign.hasPrefix("N") && callsign.count > 1 && callsign.dropFirst().first?.isNumber == true {
                return .helicopter
            }
        }

        // Military callsign patterns
        let milCallsigns = ["RCH", "REACH", "DUKE", "EVAC", "SPAR", "EXEC",
                            "FORCE", "NAVY", "ARMY", "TOPCAT", "HAWK"]
        if milCallsigns.contains(where: { callsign.hasPrefix($0) }) { return .military }

        // Small aircraft (low/slow with GA callsign)
        if alt < 10000 && speed < 200 {
            if callsign.hasPrefix("N") || callsign.isEmpty { return .small }
        }

        // Regional (medium altitude, medium speed)
        if alt < 30000 && speed < 400 { return .regional }

        // Wide-body indicators (long-haul carrier callsigns)
        let wideCallsigns = ["UAE", "QTR", "SIA", "CPA", "BAW", "DLH", "AFR", "KLM", "ANA", "JAL"]
        if wideCallsigns.contains(where: { callsign.hasPrefix($0) }) { return .widebody }

        return .jet // Default: narrowbody jet
    }
}
