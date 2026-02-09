import MetalKit
import CoreText
import AppKit

// MARK: - AirspaceLabelManager

/// Manages a texture atlas of airspace name labels and produces instance data
/// for billboard rendering at the centroid of each airspace volume.
/// Modeled on AirportLabelManager but dynamic -- labels update as airspace
/// features change when the camera moves to a new area.
final class AirspaceLabelManager {

    // MARK: - Atlas Constants

    /// Atlas: 1024x512, slots 128x32 => 8 columns x 16 rows = 128 slots
    private let atlasWidth = 1024
    private let atlasHeight = 512
    private let slotWidth = 128
    private let slotHeight = 32
    private let columnsPerRow = 8   // 1024 / 128
    private let rowCount = 16       // 512 / 32
    private var maxSlots: Int { columnsPerRow * rowCount }  // 128

    // MARK: - Properties

    /// Single texture atlas for all airspace labels
    private(set) var textureAtlas: MTLTexture?

    /// Triple-buffered label instance buffers
    private var labelBuffers: [MTLBuffer] = []

    /// Per-buffer label count
    private var labelCounts: [Int] = [0, 0, 0]

    /// Maximum visible airspace labels per frame
    let maxVisibleLabels = 60

    /// Maximum distance from camera before airspace label is hidden
    let maxDistance: Float = 500.0

    /// Distance at which labels start fading
    let fadeDistance: Float = 300.0

    /// Cache: feature name -> (slot index, atlasUV, atlasSize)
    private var labelCache: [String: (slot: Int, atlasUV: SIMD2<Float>, atlasSize: SIMD2<Float>)] = [:]

    /// Next available slot for rasterization
    private var nextSlot = 0

    /// Reusable CGContext for label rasterization (128x32)
    private var cgContext: CGContext?

    /// Metal device
    private let device: MTLDevice

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device

        // Create texture atlas
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead]
        texDesc.storageMode = .managed
        textureAtlas = device.makeTexture(descriptor: texDesc)
        textureAtlas?.label = "Airspace Label Atlas"

        // Clear atlas to transparent
        if let atlas = textureAtlas {
            let bytesPerRow = atlasWidth * 4
            let totalBytes = bytesPerRow * atlasHeight
            let zeros = [UInt8](repeating: 0, count: totalBytes)
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                   size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1))
            atlas.replace(region: region, mipmapLevel: 0, withBytes: zeros, bytesPerRow: bytesPerRow)
        }

        // Create reusable CGContext (128x32 RGBA)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        cgContext = CGContext(
            data: nil,
            width: slotWidth,
            height: slotHeight,
            bitsPerComponent: 8,
            bytesPerRow: slotWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        )

        // Allocate triple-buffered instance buffers
        let labelStride = MemoryLayout<LabelInstanceData>.stride
        for i in 0..<Renderer.maxFramesInFlight {
            guard let lb = device.makeBuffer(length: labelStride * maxVisibleLabels,
                                              options: .storageModeShared) else {
                fatalError("Failed to create airspace label instance buffer")
            }
            lb.label = "Airspace Label Instance Buffer \(i)"
            labelBuffers.append(lb)
        }
    }

    // MARK: - Label Rasterization

    /// Rasterize a single label into the given atlas slot.
    private func rasterizeLabel(text: String, slot: Int, config: ThemeConfig) {
        guard let ctx = cgContext, let atlas = textureAtlas else { return }

        ctx.clear(CGRect(x: 0, y: 0, width: slotWidth, height: slotHeight))

        // Semi-transparent background
        let bgRect = CGRect(x: 1, y: 1, width: slotWidth - 2, height: slotHeight - 2)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)

        // Use a dark background tinted to theme (same as airport labels)
        let bgColor = config.airportLabelColor
        ctx.setFillColor(CGColor(red: CGFloat(bgColor.x * 0.15),
                                  green: CGFloat(bgColor.y * 0.15),
                                  blue: CGFloat(bgColor.z * 0.15),
                                  alpha: 0.7))
        ctx.addPath(bgPath)
        ctx.fillPath()

        // Draw text (slightly smaller font to fit longer airspace names)
        let font = NSFont.boldSystemFont(ofSize: 12)
        let textColor = NSColor(red: CGFloat(config.airportLabelColor.x),
                                 green: CGFloat(config.airportLabelColor.y),
                                 blue: CGFloat(config.airportLabelColor.z),
                                 alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        ctx.saveGState()
        ctx.textMatrix = .identity

        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let ctLine = CTLineCreateWithAttributedString(attrStr)

        // Center text horizontally
        let lineWidth = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        let xOffset = max(4, (CGFloat(slotWidth) - CGFloat(lineWidth)) / 2)

        ctx.textPosition = CGPoint(x: xOffset, y: 10)
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()

        // Upload to atlas
        guard let data = ctx.data else { return }
        let col = slot % columnsPerRow
        let row = slot / columnsPerRow
        let uploadRegion = MTLRegion(
            origin: MTLOrigin(x: col * slotWidth, y: row * slotHeight, z: 0),
            size: MTLSize(width: slotWidth, height: slotHeight, depth: 1)
        )
        atlas.replace(region: uploadRegion, mipmapLevel: 0,
                       withBytes: data, bytesPerRow: slotWidth * 4)
    }

    // MARK: - Theme Update

    /// Re-rasterize labels with new theme colors by clearing cache.
    /// Labels will be lazily re-rasterized on next update().
    func updateTheme(_ config: ThemeConfig) {
        // Clear atlas to transparent
        if let atlas = textureAtlas {
            let bytesPerRow = atlasWidth * 4
            let totalBytes = bytesPerRow * atlasHeight
            let zeros = [UInt8](repeating: 0, count: totalBytes)
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                   size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1))
            atlas.replace(region: region, mipmapLevel: 0, withBytes: zeros, bytesPerRow: bytesPerRow)
        }
        labelCache.removeAll()
        nextSlot = 0
    }

    // MARK: - Per-Frame Update

    /// Update airspace label instances for the current frame, filtered by class visibility,
    /// distance-culled, and deduplicated by name.
    func update(features: [AirspaceFeature],
                showClassB: Bool, showClassC: Bool, showClassD: Bool,
                bufferIndex: Int, cameraPosition: SIMD3<Float>,
                themeConfig: ThemeConfig) {

        let labelPtr = labelBuffers[bufferIndex].contents()
            .bindMemory(to: LabelInstanceData.self, capacity: maxVisibleLabels)

        let altitudeScale: Float = 0.001

        // Filter features by class visibility
        let visibleFeatures = features.filter { feature in
            switch feature.airspaceClass {
            case "B": return showClassB
            case "C": return showClassC
            case "D": return showClassD
            default: return false
            }
        }

        // Deduplicate by name: pick the first feature per unique name
        var seenNames = Set<String>()
        var uniqueFeatures: [AirspaceFeature] = []
        for feature in visibleFeatures {
            if !seenNames.contains(feature.name) {
                seenNames.insert(feature.name)
                uniqueFeatures.append(feature)
            }
        }

        // Compute centroid and distance for each unique feature
        struct VisibleLabel {
            let name: String
            let position: SIMD3<Float>
            let distance: Float
        }

        var visible: [VisibleLabel] = []
        visible.reserveCapacity(uniqueFeatures.count)

        for feature in uniqueFeatures {
            // Compute centroid from first 3 fill vertices (first triangle)
            guard feature.fillVertices.count >= 3 else { continue }

            let v0 = feature.fillVertices[0].position
            let v1 = feature.fillVertices[1].position
            let v2 = feature.fillVertices[2].position

            let centroidX = (v0.x + v1.x + v2.x) / 3.0
            let centroidZ = (v0.z + v1.z + v2.z) / 3.0

            // Y position: midpoint between floor and ceiling altitude
            let midY = (feature.floorFeet + feature.ceilingFeet) / 2.0 * altitudeScale

            let position = SIMD3<Float>(centroidX, midY, centroidZ)

            let dx = position.x - cameraPosition.x
            let dy = position.y - cameraPosition.y
            let dz = position.z - cameraPosition.z
            let dist = sqrt(dx * dx + dy * dy + dz * dz)

            if dist <= maxDistance {
                visible.append(VisibleLabel(name: feature.name, position: position, distance: dist))
            }
        }

        // Sort by distance (nearest first), cap at maxVisibleLabels
        visible.sort { $0.distance < $1.distance }
        let visibleCount = min(visible.count, maxVisibleLabels)

        let atlasWF = Float(atlasWidth)
        let atlasHF = Float(atlasHeight)
        let slotWF = Float(slotWidth)
        let slotHF = Float(slotHeight)

        var labelIdx = 0
        for v in visible.prefix(visibleCount) {
            // Truncate name if too long
            let labelText: String
            if v.name.count > 12 {
                labelText = String(v.name.prefix(12))
            } else {
                labelText = v.name
            }

            // Check cache or rasterize into next slot
            let cached: (slot: Int, atlasUV: SIMD2<Float>, atlasSize: SIMD2<Float>)
            if let existing = labelCache[labelText] {
                cached = existing
            } else {
                guard nextSlot < maxSlots else { continue }  // Atlas full
                let slot = nextSlot
                nextSlot += 1

                rasterizeLabel(text: labelText, slot: slot, config: themeConfig)

                let col = slot % columnsPerRow
                let row = slot / columnsPerRow
                let atlasUV = SIMD2<Float>(Float(col) * slotWF / atlasWF,
                                            Float(row) * slotHF / atlasHF)
                let atlasSize = SIMD2<Float>(slotWF / atlasWF, slotHF / atlasHF)
                let entry = (slot: slot, atlasUV: atlasUV, atlasSize: atlasSize)
                labelCache[labelText] = entry
                cached = entry
            }

            // Distance-based opacity: full at < fadeDistance, fades to 0 at maxDistance
            let opacity: Float
            if v.distance < fadeDistance {
                opacity = 1.0
            } else {
                opacity = 1.0 - (v.distance - fadeDistance) / (maxDistance - fadeDistance)
            }

            labelPtr[labelIdx] = LabelInstanceData(
                position: v.position,
                size: 6.0,
                atlasUV: cached.atlasUV,
                atlasSize: cached.atlasSize,
                opacity: opacity,
                _pad0: 0,
                _pad1: 0,
                _pad2: 0
            )
            labelIdx += 1
        }

        labelCounts[bufferIndex] = labelIdx
    }

    // MARK: - Buffer Accessors

    func labelBuffer(at index: Int) -> MTLBuffer {
        return labelBuffers[index]
    }

    func labelCount(at index: Int) -> Int {
        return labelCounts[index]
    }
}
