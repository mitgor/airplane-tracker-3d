import MetalKit
import simd

// MARK: - AircraftInstanceManager

/// Manages per-instance GPU buffers for aircraft rendering.
/// Triple-buffered to match Renderer's triple buffering scheme.
/// Populates instance data each frame from InterpolatedAircraftState array.
class AircraftInstanceManager {

    // MARK: - Types

    struct CategoryRange {
        var offset: Int
        var count: Int
    }

    // MARK: - Properties

    private let device: MTLDevice
    let meshLibrary: AircraftMeshLibrary

    /// Triple-buffered instance buffers
    private var instanceBuffers: [MTLBuffer] = []   // AircraftInstanceData
    private var glowBuffers: [MTLBuffer] = []       // GlowInstanceData
    private var spinBuffers: [MTLBuffer] = []       // AircraftInstanceData for spinning parts

    /// Per-frame state: how many aircraft per category and where they start in the buffer
    private(set) var categoryRanges: [AircraftCategory: CategoryRange] = [:]
    private(set) var totalAircraftCount: Int = 0
    private(set) var helicopterCount: Int = 0
    private(set) var propCount: Int = 0

    /// Spinning parts start offset in the spin buffer (helicopters first, then props)
    private(set) var helicopterSpinOffset: Int = 0
    private(set) var propSpinOffset: Int = 0

    /// Animation state (persistent across frames for continuity)
    private var lightPhases: [String: Float] = [:]
    private var rotorAngles: [String: Float] = [:]

    let maxInstances = 1024

    // MARK: - Init

    init(device: MTLDevice, meshLibrary: AircraftMeshLibrary) {
        self.device = device
        self.meshLibrary = meshLibrary

        let instanceStride = MemoryLayout<AircraftInstanceData>.stride
        let glowStride = MemoryLayout<GlowInstanceData>.stride

        for i in 0..<Renderer.maxFramesInFlight {
            guard let ib = device.makeBuffer(length: instanceStride * maxInstances,
                                              options: .storageModeShared) else {
                fatalError("Failed to create aircraft instance buffer")
            }
            ib.label = "Aircraft Instance Buffer \(i)"
            instanceBuffers.append(ib)

            guard let gb = device.makeBuffer(length: glowStride * maxInstances,
                                              options: .storageModeShared) else {
                fatalError("Failed to create glow instance buffer")
            }
            gb.label = "Glow Instance Buffer \(i)"
            glowBuffers.append(gb)

            guard let sb = device.makeBuffer(length: instanceStride * maxInstances,
                                              options: .storageModeShared) else {
                fatalError("Failed to create spin instance buffer")
            }
            sb.label = "Spin Instance Buffer \(i)"
            spinBuffers.append(sb)
        }
    }

    // MARK: - Per-Frame Update

    /// Update instance buffers with interpolated aircraft states for the current frame.
    /// When tintColor is non-nil, all aircraft and glow colors are overridden (retro mode).
    func update(states: [InterpolatedAircraftState], bufferIndex: Int,
                deltaTime: Float, time: Float, selectedHex: String? = nil,
                tintColor: SIMD4<Float>? = nil) {
        let count = min(states.count, maxInstances)
        totalAircraftCount = count

        // Sort by category for instanced batching
        let sorted = states.prefix(count).sorted { $0.category.sortOrder < $1.category.sortOrder }

        // Compute category ranges
        categoryRanges.removeAll()
        var currentCategory: AircraftCategory?
        var rangeStart = 0

        for (i, state) in sorted.enumerated() {
            if state.category != currentCategory {
                if let prev = currentCategory {
                    categoryRanges[prev] = CategoryRange(offset: rangeStart, count: i - rangeStart)
                }
                currentCategory = state.category
                rangeStart = i
            }
        }
        if let last = currentCategory {
            categoryRanges[last] = CategoryRange(offset: rangeStart, count: count - rangeStart)
        }

        // Populate instance buffers
        let instancePtr = instanceBuffers[bufferIndex].contents()
            .bindMemory(to: AircraftInstanceData.self, capacity: maxInstances)
        let glowPtr = glowBuffers[bufferIndex].contents()
            .bindMemory(to: GlowInstanceData.self, capacity: maxInstances)
        let spinPtr = spinBuffers[bufferIndex].contents()
            .bindMemory(to: AircraftInstanceData.self, capacity: maxInstances)

        helicopterCount = 0
        propCount = 0
        var spinIndex = 0

        for (i, state) in sorted.enumerated() {
            // Advance per-aircraft light phase
            let phase = (lightPhases[state.hex] ?? Float.random(in: 0..<(2.0 * .pi))) + deltaTime * 5.0
            lightPhases[state.hex] = phase

            // Advance rotor angle
            let rotorSpeed: Float
            switch state.category {
            case .helicopter: rotorSpeed = 0.7 * 2.0 * .pi
            case .small: rotorSpeed = 0.6 * 2.0 * .pi
            default: rotorSpeed = 0
            }
            let rotorAngle = (rotorAngles[state.hex] ?? 0) + deltaTime * rotorSpeed
            rotorAngles[state.hex] = rotorAngle

            // Build model matrix: translate to position, rotate by heading around Y
            let translation = translationMatrix(state.position)
            let rotation = rotationY(state.heading)
            let modelMatrix = translation * rotation

            // Altitude color (or tint override for retro mode)
            let color: SIMD4<Float>
            if let tint = tintColor {
                color = tint
            } else {
                color = altitudeColor(state.altitude)
            }

            // Glow intensity
            let glowIntensity: Float = 0.3 + 0.15 * sin(phase * 0.5)

            // Selection flag: bit 0 = selected (gold highlight in AircraftShaders.metal)
            let flags: UInt32 = (state.hex == selectedHex) ? 1 : 0

            // Populate aircraft instance
            instancePtr[i] = AircraftInstanceData(
                modelMatrix: modelMatrix,
                color: color,
                lightPhase: phase,
                glowIntensity: glowIntensity,
                rotorAngle: rotorAngle,
                flags: flags
            )

            // Populate glow instance
            glowPtr[i] = GlowInstanceData(
                position: state.position + SIMD3<Float>(0, 1.0, 0),
                _pad0: 0,
                color: color,
                size: 7.0 + 1.5 * sin(phase * 0.3),
                opacity: glowIntensity,
                _pad1: 0,
                _pad2: 0
            )

            // Spinning parts
            if state.category == .helicopter {
                // Main + tail rotor: same position as helicopter, rotated around Y by rotorAngle
                let rotorRotation = rotationY(rotorAngle)
                let spinMatrix = translation * rotorRotation
                spinPtr[spinIndex] = AircraftInstanceData(
                    modelMatrix: spinMatrix,
                    color: SIMD4<Float>(0.3, 0.3, 0.3, 1.0), // dark gray rotor
                    lightPhase: phase,
                    glowIntensity: 0,
                    rotorAngle: rotorAngle,
                    flags: 0
                )
                spinIndex += 1
                helicopterCount += 1
            } else if state.category == .small {
                // Propeller: at nose, rotating around Z axis
                let propRotation = rotationZ(rotorAngle)
                let noseOffset = translationMatrix(SIMD3<Float>(0, 0, 0)) // propeller mesh has built-in nose offset
                let spinMatrix = translation * rotation * noseOffset * propRotation
                spinPtr[spinIndex] = AircraftInstanceData(
                    modelMatrix: spinMatrix,
                    color: SIMD4<Float>(0.2, 0.2, 0.2, 1.0), // dark propeller
                    lightPhase: phase,
                    glowIntensity: 0,
                    rotorAngle: rotorAngle,
                    flags: 0
                )
                spinIndex += 1
                propCount += 1
            }
        }

        // Spinning parts layout: helicopters first, then props
        helicopterSpinOffset = 0
        propSpinOffset = helicopterCount
    }

    // MARK: - Buffer Accessors

    func instanceBuffer(at index: Int) -> MTLBuffer {
        return instanceBuffers[index]
    }

    func glowBuffer(at index: Int) -> MTLBuffer {
        return glowBuffers[index]
    }

    func spinBuffer(at index: Int) -> MTLBuffer {
        return spinBuffers[index]
    }

    // MARK: - Altitude Color Gradient

    /// Green (low) -> Yellow -> Orange -> Pink (high) altitude gradient.
    func altitudeColor(_ altitude: Float) -> SIMD4<Float> {
        if altitude < 5000 {
            // Green
            return SIMD4<Float>(0.2, 0.8, 0.2, 1.0)
        } else if altitude < 15000 {
            // Green -> Yellow
            let t = (altitude - 5000) / 10000
            return SIMD4<Float>(0.2 + 0.8 * t, 0.8, 0.2 * (1 - t), 1.0)
        } else if altitude < 30000 {
            // Yellow -> Orange
            let t = (altitude - 15000) / 15000
            return SIMD4<Float>(1.0, 0.8 - 0.3 * t, 0.0, 1.0)
        } else {
            // Orange -> Pink
            let t = min((altitude - 30000) / 15000, 1.0)
            return SIMD4<Float>(1.0, 0.5 - 0.1 * t, 0.3 * t, 1.0)
        }
    }

    // MARK: - Matrix Helpers

    private func translationMatrix(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1.0)
        return m
    }

    private func rotationY(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        var m = matrix_identity_float4x4
        m.columns.0.x = c
        m.columns.0.z = -s
        m.columns.2.x = s
        m.columns.2.z = c
        return m
    }

    private func rotationZ(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        var m = matrix_identity_float4x4
        m.columns.0.x = c
        m.columns.0.y = s
        m.columns.1.x = -s
        m.columns.1.y = c
        return m
    }
}

// MARK: - AircraftCategory Sort Order

extension AircraftCategory {
    /// Stable sort order for instanced batching (group same categories together).
    var sortOrder: Int {
        switch self {
        case .jet: return 0
        case .widebody: return 1
        case .helicopter: return 2
        case .small: return 3
        case .military: return 4
        case .regional: return 5
        }
    }
}
