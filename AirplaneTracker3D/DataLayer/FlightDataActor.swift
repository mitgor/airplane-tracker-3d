import Foundation
import QuartzCore
import simd

// MARK: - FlightDataActor

/// Actor-based polling system for ADS-B flight data with provider fallback,
/// time-windowed interpolation buffer, and stale aircraft removal.
actor FlightDataActor {

    // MARK: - Types

    /// Data source mode: local dump1090 receiver or global API providers.
    enum DataMode: Sendable {
        case local
        case global
    }

    /// An API provider with URL builder and failure tracking.
    struct Provider {
        let name: String
        let buildURL: @Sendable (Double, Double, Int) -> URL
        var failCount: Int = 0
    }

    /// A timestamped data entry for the interpolation buffer.
    struct BufferEntry: Sendable {
        let timestamp: CFTimeInterval
        let data: AircraftModel
    }

    // MARK: - Configuration Constants

    /// Delay between real time and interpolation target, ensuring smooth playback
    /// even with jittery API responses. Matches web app INTERPOLATION_DELAY = 2000ms.
    private let interpolationDelay: CFTimeInterval = 2.0

    /// How long to keep data points for local mode buffer (5 seconds).
    private let localBufferWindow: CFTimeInterval = 5.0

    /// How long to keep data points for global mode buffer (15 seconds).
    private let globalBufferWindow: CFTimeInterval = 15.0

    /// Stale aircraft removal threshold for local mode (delay + 2s = 4s).
    private let localStaleThreshold: CFTimeInterval = 4.0

    /// Stale aircraft removal threshold for global mode (delay + interval + 2s = 9s).
    private let globalStaleThreshold: CFTimeInterval = 9.0

    /// Global search radius in nautical miles.
    private let searchRadius: Int = 250

    /// Local dump1090 base URL.
    private let localURL = URL(string: "http://localhost:8080/data/aircraft.json")!

    // MARK: - State

    /// API providers for global mode, tried in order with fallback.
    private var providers: [Provider] = [
        Provider(name: "airplanes.live",
                 buildURL: { lat, lon, radius in
            URL(string: "https://api.airplanes.live/v2/point/\(lat)/\(lon)/\(radius)")!
        }),
        Provider(name: "adsb.lol",
                 buildURL: { lat, lon, radius in
            URL(string: "https://api.adsb.lol/v2/point/\(lat)/\(lon)/\(radius)")!
        })
    ]

    /// Per-aircraft time-windowed ring buffer for interpolation.
    /// Key: hex identifier. Value: sorted array of timestamped data entries.
    private var dataBuffer: [String: [BufferEntry]] = [:]

    /// Tracks when each aircraft was last seen in an API response.
    private var lastSeen: [String: CFTimeInterval] = [:]

    /// Current polling mode.
    private var currentMode: DataMode = .global

    // MARK: - Public API

    /// Start polling for aircraft data. Returns an AsyncStream that yields the latest
    /// aircraft dictionary after each poll cycle.
    ///
    /// - Parameters:
    ///   - mode: Local (dump1090) or global (airplanes.live/adsb.lol) mode.
    ///   - center: Center coordinates for the search area (lat, lon).
    /// - Returns: An AsyncStream yielding the latest aircraft by hex after each fetch.
    func startPolling(mode: DataMode, center: (lat: Double, lon: Double)) -> AsyncStream<[String: AircraftModel]> {
        currentMode = mode
        dataBuffer.removeAll()
        lastSeen.removeAll()

        return AsyncStream { continuation in
            let task = Task { [weak self] in
                let interval: Duration = mode == .local ? .seconds(1) : .seconds(5)
                while !Task.isCancelled {
                    guard let self = self else { break }
                    let aircraft = await self.fetchWithFallback(mode: mode, center: center)
                    await self.updateBuffer(aircraft)
                    let latest = await self.latestAircraft()
                    continuation.yield(latest)
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Switch the data mode. Clears the buffer and resets provider fail counts.
    func switchMode(to mode: DataMode) {
        currentMode = mode
        dataBuffer.removeAll()
        lastSeen.removeAll()
        for i in providers.indices {
            providers[i].failCount = 0
        }
    }

    /// Get a snapshot of the current buffer for interpolation on the caller's thread.
    /// Returns a Sendable copy of the buffer data.
    func getBufferSnapshot() -> [String: [BufferEntry]] {
        return dataBuffer
    }

    // MARK: - Network Fetching

    /// Fetch aircraft with provider fallback.
    private func fetchWithFallback(mode: DataMode, center: (lat: Double, lon: Double)) async -> [AircraftModel] {
        if mode == .local {
            return await fetchLocal()
        }
        // Global: try each provider in sequence
        for i in providers.indices {
            do {
                let url = providers[i].buildURL(center.lat, center.lon, searchRadius)
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ADSBV2Response.self, from: data)
                providers[i].failCount = 0
                return DataNormalizer.normalizeV2(response)
            } catch {
                providers[i].failCount += 1
                continue
            }
        }
        return [] // All providers failed silently
    }

    /// Fetch from local dump1090 receiver.
    private func fetchLocal() async -> [AircraftModel] {
        do {
            let (data, _) = try await URLSession.shared.data(from: localURL)
            let response = try JSONDecoder().decode(Dump1090Response.self, from: data)
            return DataNormalizer.normalizeDump1090(response)
        } catch {
            return [] // Silent failure for network errors
        }
    }

    // MARK: - Buffer Management

    /// Update the interpolation buffer with new aircraft data.
    /// Timestamps each entry, trims old entries, and removes stale aircraft.
    private func updateBuffer(_ aircraft: [AircraftModel]) {
        let now = CACurrentMediaTime()
        let bufferWindow = currentMode == .local ? localBufferWindow : globalBufferWindow
        let staleThreshold = currentMode == .local ? localStaleThreshold : globalStaleThreshold

        // Add new data points
        for ac in aircraft {
            let entry = BufferEntry(timestamp: now, data: ac)
            if dataBuffer[ac.hex] != nil {
                dataBuffer[ac.hex]!.append(entry)
            } else {
                dataBuffer[ac.hex] = [entry]
            }
            lastSeen[ac.hex] = now
        }

        // Trim old entries beyond buffer window and remove stale aircraft
        var toRemove: [String] = []
        for (hex, entries) in dataBuffer {
            // Trim entries older than buffer window
            let trimmed = entries.filter { now - $0.timestamp <= bufferWindow }
            if trimmed.isEmpty {
                toRemove.append(hex)
            } else {
                dataBuffer[hex] = trimmed
            }

            // Remove stale aircraft (not seen recently)
            if let seen = lastSeen[hex], now - seen > staleThreshold {
                toRemove.append(hex)
            }
        }

        for hex in toRemove {
            dataBuffer.removeValue(forKey: hex)
            lastSeen.removeValue(forKey: hex)
        }
    }

    /// Get the most recent data entry for each aircraft.
    private func latestAircraft() -> [String: AircraftModel] {
        var result: [String: AircraftModel] = [:]
        for (hex, entries) in dataBuffer {
            if let last = entries.last {
                result[hex] = last.data
            }
        }
        return result
    }
}

// MARK: - FlightDataManager

/// Main-actor manager that owns the FlightDataActor, consumes its AsyncStream,
/// and provides synchronous interpolated states for the render loop.
///
/// Architecture: The polling actor yields raw data at 1-5 second intervals.
/// This manager stores a buffer snapshot and computes interpolated positions
/// each frame in `interpolatedStates(at:)`, which runs synchronously on main
/// thread (safe for MTKViewDelegate draw(in:) calls).
@MainActor
final class FlightDataManager {

    // MARK: - Properties

    let actor = FlightDataActor()

    /// Latest raw buffer snapshot (updated each poll cycle).
    private var bufferSnapshot: [String: [FlightDataActor.BufferEntry]] = [:]

    /// Active polling task.
    private var pollingTask: Task<Void, Never>?

    /// Altitude scale factor: converts feet to world-space Y units.
    /// At 0.001, 35000 feet = 35 world units (with worldScale=500, reasonable visual scale).
    let altitudeScale: Float = 0.001

    // MARK: - Lifecycle

    /// Start polling for aircraft data.
    func startPolling(mode: FlightDataActor.DataMode, center: (lat: Double, lon: Double)) {
        stopPolling()
        pollingTask = Task {
            let stream = await actor.startPolling(mode: mode, center: center)
            for await _ in stream {
                // After each poll cycle, grab a fresh buffer snapshot
                self.bufferSnapshot = await actor.getBufferSnapshot()
            }
        }
    }

    /// Stop the current polling loop.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Switch data mode (local/global). Restarts polling with the new mode.
    func switchMode(to mode: FlightDataActor.DataMode, center: (lat: Double, lon: Double)) {
        Task {
            await actor.switchMode(to: mode)
        }
        startPolling(mode: mode, center: center)
    }

    // MARK: - Interpolation (called each render frame from draw(in:))

    /// Compute interpolated aircraft states for the current render frame.
    /// This runs on main thread, which is safe since MTKViewDelegate draw(in:) runs on main.
    ///
    /// - Parameter renderTime: Current frame time from CACurrentMediaTime().
    /// - Returns: Array of render-ready interpolated aircraft states.
    func interpolatedStates(at renderTime: CFTimeInterval) -> [InterpolatedAircraftState] {
        let targetTime = renderTime - 2.0 // interpolation delay
        var results: [InterpolatedAircraftState] = []

        for (hex, entries) in bufferSnapshot {
            guard !entries.isEmpty else { continue }

            // Find surrounding data points for interpolation
            var before: FlightDataActor.BufferEntry?
            var after: FlightDataActor.BufferEntry?

            for entry in entries {
                if entry.timestamp <= targetTime {
                    before = entry
                } else {
                    after = entry
                    break
                }
            }

            // Need at least one data point
            guard let b = before ?? after, let a = after ?? before else { continue }

            // Calculate interpolation factor
            var t: Float = 0
            if b.timestamp != a.timestamp {
                t = Float((targetTime - b.timestamp) / (a.timestamp - b.timestamp))
                t = max(0, min(1, t))
            }

            // Interpolate position and flight parameters
            let lat = Double(lerp(Float(b.data.lat), Float(a.data.lat), t))
            let lon = Double(lerp(Float(b.data.lon), Float(a.data.lon), t))
            let alt = lerp(b.data.altitude, a.data.altitude, t)
            let heading = lerpAngle(b.data.track, a.data.track, t)
            let speed = lerp(b.data.groundSpeed, a.data.groundSpeed, t)
            let vrate = lerp(b.data.verticalRate, a.data.verticalRate, t)

            // Convert to world-space coordinates
            let worldPos = MapCoordinateSystem.shared.worldPosition(lat: lat, lon: lon)
            let altWorld = alt * altitudeScale

            // Classify aircraft category (use the more recent data point for metadata)
            let classifySource = a.data
            let category = AircraftCategory.classify(classifySource)

            let state = InterpolatedAircraftState(
                position: SIMD3<Float>(worldPos.x, altWorld, worldPos.z),
                heading: heading * .pi / 180.0,
                groundSpeed: speed,
                verticalRate: vrate,
                altitude: alt,
                category: category,
                hex: hex,
                callsign: classifySource.callsign,
                squawk: classifySource.squawk,
                lat: lat,
                lon: lon
            )
            results.append(state)
        }

        return results
    }

    // MARK: - Math Utilities

    /// Linear interpolation between two values.
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }

    /// Angle interpolation with 360-degree wraparound.
    /// Handles the case where interpolating between 350 and 10 degrees
    /// should go through 0/360, not through 180.
    private func lerpAngle(_ a: Float, _ b: Float, _ t: Float) -> Float {
        var a = a.truncatingRemainder(dividingBy: 360)
        var b = b.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        if b < 0 { b += 360 }
        var diff = b - a
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return a + diff * t
    }
}
