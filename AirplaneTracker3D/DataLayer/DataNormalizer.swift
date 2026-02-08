import Foundation

/// Static normalizers for converting API responses to the common AircraftModel format.
enum DataNormalizer {

    /// Normalize a V2 API response (airplanes.live, adsb.lol) to [AircraftModel].
    /// Requires hex, lat, lon to be non-nil. Trims whitespace from callsign.
    static func normalizeV2(_ response: ADSBV2Response) -> [AircraftModel] {
        guard let acList = response.ac else { return [] }
        return acList.compactMap { ac -> AircraftModel? in
            guard let hex = ac.hex,
                  let lat = ac.lat,
                  let lon = ac.lon else { return nil }

            return AircraftModel(
                hex: hex,
                callsign: (ac.flight ?? "").trimmingCharacters(in: .whitespaces),
                lat: lat,
                lon: lon,
                altitude: ac.alt_baro?.asFeet ?? Float(ac.alt_geom ?? 0),
                track: Float(ac.track ?? 0),
                groundSpeed: Float(ac.gs ?? 0),
                verticalRate: Float(ac.baro_rate ?? ac.geom_rate ?? 0),
                squawk: ac.squawk ?? "",
                category: ac.category ?? "",
                registration: ac.r ?? "",
                typeCode: ac.t ?? "",
                dbFlags: ac.dbFlags ?? 0
            )
        }
    }

    /// Normalize a dump1090 local response to [AircraftModel].
    /// Maps older field names: speed -> groundSpeed, vert_rate -> verticalRate, altitude -> alt_baro.
    /// Sets category/registration/typeCode/dbFlags to empty/zero since dump1090 lacks these fields.
    static func normalizeDump1090(_ response: Dump1090Response) -> [AircraftModel] {
        guard let acList = response.aircraft else { return [] }
        return acList.compactMap { ac -> AircraftModel? in
            guard let hex = ac.hex,
                  let lat = ac.lat,
                  let lon = ac.lon else { return nil }

            return AircraftModel(
                hex: hex,
                callsign: (ac.flight ?? "").trimmingCharacters(in: .whitespaces),
                lat: lat,
                lon: lon,
                altitude: ac.altitude?.asFeet ?? 0,
                track: Float(ac.track ?? 0),
                groundSpeed: Float(ac.speed ?? 0),
                verticalRate: Float(ac.vert_rate ?? 0),
                squawk: ac.squawk ?? "",
                category: "",
                registration: "",
                typeCode: "",
                dbFlags: 0
            )
        }
    }
}
