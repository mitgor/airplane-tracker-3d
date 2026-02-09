import MetalKit
import CoreText
import AppKit

// MARK: - AirportData

/// Codable representation of an airport from the embedded JSON database.
struct AirportData: Codable {
    let icao: String
    let iata: String?
    let name: String
    let lat: Double
    let lon: Double
    let type: String
}

// MARK: - AirportLabelManager

/// Manages a texture atlas of airport IATA code labels and produces instance data
/// for billboard rendering at ground level. Modeled after LabelManager but simpler --
/// airport labels are static (text never changes) and are distance-culled.
final class AirportLabelManager {

    // MARK: - Atlas Constants

    /// Atlas: 2048x1024, slots 128x32 => 16 columns x 32 rows = 512 slots
    private let atlasWidth = 2048
    private let atlasHeight = 1024
    private let slotWidth = 128
    private let slotHeight = 32
    private let columnsPerRow = 16  // 2048 / 128
    private let rowCount = 32       // 1024 / 32
    private var maxSlots: Int { columnsPerRow * rowCount }  // 512

    // MARK: - Properties

    /// Loaded airport data from JSON
    private(set) var airports: [AirportData] = []

    /// Pre-computed world-space XZ positions (Y = 0.5 above ground)
    private(set) var airportPositions: [SIMD3<Float>] = []

    /// Single texture atlas for all airport labels
    private(set) var textureAtlas: MTLTexture?

    /// Triple-buffered label instance buffers
    private var labelBuffers: [MTLBuffer] = []

    /// Per-buffer label count
    private var labelCounts: [Int] = [0, 0, 0]

    /// Maximum visible airport labels per frame
    let maxVisibleLabels = 40

    /// Maximum distance from camera before airport label is hidden
    let maxDistance: Float = 400.0

    /// Distance at which labels start fading
    let fadeDistance: Float = 200.0

    /// Atlas slot UV coordinates per airport (indexed same as airports array)
    private var slotUVs: [(atlasUV: SIMD2<Float>, atlasSize: SIMD2<Float>)] = []

    /// Reusable CGContext for label rasterization (128x32)
    private var cgContext: CGContext?

    /// Metal device
    private let device: MTLDevice

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device

        // Load airports from bundle
        loadAirports()

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
        textureAtlas?.label = "Airport Label Atlas"

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
                fatalError("Failed to create airport label instance buffer")
            }
            lb.label = "Airport Label Instance Buffer \(i)"
            labelBuffers.append(lb)
        }

        // Rasterize all airport labels with default (day) theme
        let defaultConfig = ThemeManager.configs[.day]!
        rasterizeAllLabels(config: defaultConfig)
    }

    // MARK: - Airport Loading

    private func loadAirports() {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "json") else {
            #if DEBUG
            print("[AirportLabelManager] airports.json not found in bundle")
            #endif
            return
        }
        do {
            let data = try Data(contentsOf: url)
            airports = try JSONDecoder().decode([AirportData].self, from: data)
        } catch {
            #if DEBUG
            print("[AirportLabelManager] Failed to decode airports.json: \(error)")
            #endif
            return
        }

        // Pre-compute world positions
        let coordSystem = MapCoordinateSystem.shared
        airportPositions = airports.map { airport in
            let x = coordSystem.lonToX(airport.lon)
            let z = coordSystem.latToZ(airport.lat)
            return SIMD3<Float>(x, 0.5, z)  // slightly above ground
        }
    }

    // MARK: - Label Rasterization

    /// Rasterize all airport labels into the atlas with the given theme colors.
    private func rasterizeAllLabels(config: ThemeConfig) {
        guard let atlas = textureAtlas else { return }

        // Clear atlas
        let bytesPerRow = atlasWidth * 4
        let totalBytes = bytesPerRow * atlasHeight
        let zeros = [UInt8](repeating: 0, count: totalBytes)
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1))
        atlas.replace(region: region, mipmapLevel: 0, withBytes: zeros, bytesPerRow: bytesPerRow)

        slotUVs.removeAll()

        let atlasWF = Float(atlasWidth)
        let atlasHF = Float(atlasHeight)
        let slotWF = Float(slotWidth)
        let slotHF = Float(slotHeight)

        for (i, airport) in airports.enumerated() {
            guard i < maxSlots else { break }

            let label = airport.iata ?? airport.icao
            rasterizeLabel(text: label, slot: i, config: config)

            let col = i % columnsPerRow
            let row = i / columnsPerRow
            let atlasUV = SIMD2<Float>(Float(col) * slotWF / atlasWF,
                                        Float(row) * slotHF / atlasHF)
            let atlasSize = SIMD2<Float>(slotWF / atlasWF, slotHF / atlasHF)
            slotUVs.append((atlasUV: atlasUV, atlasSize: atlasSize))
        }
    }

    /// Rasterize a single label into the given atlas slot.
    private func rasterizeLabel(text: String, slot: Int, config: ThemeConfig) {
        guard let ctx = cgContext, let atlas = textureAtlas else { return }

        ctx.clear(CGRect(x: 0, y: 0, width: slotWidth, height: slotHeight))

        // Semi-transparent background
        let bgRect = CGRect(x: 1, y: 1, width: slotWidth - 2, height: slotHeight - 2)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)

        // Use a dark background tinted to theme
        let bgColor = config.airportLabelColor
        ctx.setFillColor(CGColor(red: CGFloat(bgColor.x * 0.15),
                                  green: CGFloat(bgColor.y * 0.15),
                                  blue: CGFloat(bgColor.z * 0.15),
                                  alpha: 0.7))
        ctx.addPath(bgPath)
        ctx.fillPath()

        // Draw text
        let font = NSFont.boldSystemFont(ofSize: 14)
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

    /// Re-rasterize all airport labels with new theme colors.
    func updateTheme(_ config: ThemeConfig) {
        rasterizeAllLabels(config: config)
    }

    // MARK: - Per-Frame Update

    /// Update airport label instances for the current frame, distance-culled and sorted.
    func update(bufferIndex: Int, cameraPosition: SIMD3<Float>, themeConfig: ThemeConfig) {
        let labelPtr = labelBuffers[bufferIndex].contents()
            .bindMemory(to: LabelInstanceData.self, capacity: maxVisibleLabels)

        // Compute distances and collect visible airports
        struct VisibleAirport {
            let index: Int
            let distance: Float
        }

        var visible: [VisibleAirport] = []
        visible.reserveCapacity(airports.count)

        for i in 0..<min(airports.count, maxSlots) {
            let pos = airportPositions[i]
            let dx = pos.x - cameraPosition.x
            let dy = pos.y - cameraPosition.y
            let dz = pos.z - cameraPosition.z
            let dist = sqrt(dx * dx + dy * dy + dz * dz)

            if dist <= maxDistance {
                visible.append(VisibleAirport(index: i, distance: dist))
            }
        }

        // Sort by distance (nearest first), cap at max visible
        visible.sort { $0.distance < $1.distance }
        let visibleCount = min(visible.count, maxVisibleLabels)

        var labelIdx = 0
        for v in visible.prefix(visibleCount) {
            guard v.index < slotUVs.count else { continue }

            // Distance-based opacity: full at < fadeDistance, fades to 0 at maxDistance
            let opacity: Float
            if v.distance < fadeDistance {
                opacity = 1.0
            } else {
                opacity = 1.0 - (v.distance - fadeDistance) / (maxDistance - fadeDistance)
            }

            let slot = slotUVs[v.index]

            labelPtr[labelIdx] = LabelInstanceData(
                position: airportPositions[v.index],
                size: 6.0,
                atlasUV: slot.atlasUV,
                atlasSize: slot.atlasSize,
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
