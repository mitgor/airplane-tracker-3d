import MetalKit
import CoreText
import AppKit

// MARK: - LabelManager

/// Manages a texture atlas of label bitmaps and produces label instance data
/// for billboard rendering. Also produces altitude reference line vertices.
final class LabelManager {

    // MARK: - Atlas Constants

    /// Atlas dimensions: 2048x2048 pixels, subdivided into 256x64 slots
    private let atlasWidth = 2048
    private let atlasHeight = 2048
    private let slotWidth = 256
    private let slotHeight = 64
    private let columnsPerRow = 8   // 2048 / 256
    private let rowCount = 32       // 2048 / 64
    private var maxSlots: Int { columnsPerRow * rowCount }  // 256 slots

    // MARK: - Properties

    /// Single large texture atlas for all label bitmaps
    private(set) var textureAtlas: MTLTexture?

    /// Triple-buffered label instance buffers
    private var labelBuffers: [MTLBuffer] = []

    /// Triple-buffered altitude line vertex buffers
    private var altLineBuffers: [MTLBuffer] = []

    /// Per-buffer label count
    private var labelCounts: [Int] = [0, 0, 0]

    /// Per-buffer altitude line vertex count
    private var altLineVertexCounts: [Int] = [0, 0, 0]

    /// Cache: hex -> (text, slot) for avoiding re-rasterization
    private var labelCache: [String: (text: String, slot: Int)] = [:]

    /// Tracks which atlas slots are in use
    private var slotAllocator: [Bool]

    /// Reusable CGContext for label rasterization (256x64 pixels)
    private var cgContext: CGContext?

    /// Maximum distance from camera before label is hidden
    var maxLabelDistance: Float = 300.0

    /// Distance at which label starts fading
    var fadeLabelDistance: Float = 150.0

    /// Maximum number of labels
    let maxLabels = 256

    /// Stale tracking: consecutive frames a hex is missing
    private var missingFrames: [String: Int] = [:]

    /// Theme-aware text and background colors for label rasterization
    var textColor: NSColor = .white
    var bgColor: NSColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0.6)

    /// Theme-aware altitude line color
    var altLineColor: SIMD4<Float> = SIMD4<Float>(0.5, 0.5, 0.5, 0.3)

    // MARK: - Init

    init(device: MTLDevice) {
        slotAllocator = [Bool](repeating: false, count: columnsPerRow * rowCount)

        // Create 2048x2048 RGBA8 texture atlas
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead]
        texDesc.storageMode = .managed
        textureAtlas = device.makeTexture(descriptor: texDesc)
        textureAtlas?.label = "Label Atlas"

        // Clear the atlas to transparent
        if let atlas = textureAtlas {
            let bytesPerRow = atlasWidth * 4
            let totalBytes = bytesPerRow * atlasHeight
            let zeros = [UInt8](repeating: 0, count: totalBytes)
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                   size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1))
            atlas.replace(region: region, mipmapLevel: 0, withBytes: zeros, bytesPerRow: bytesPerRow)
        }

        // Allocate triple-buffered instance buffers
        let labelStride = MemoryLayout<LabelInstanceData>.stride
        let altLineStride = MemoryLayout<AltLineVertex>.stride

        for i in 0..<Renderer.maxFramesInFlight {
            guard let lb = device.makeBuffer(length: labelStride * maxLabels,
                                              options: .storageModeShared) else {
                fatalError("Failed to create label instance buffer")
            }
            lb.label = "Label Instance Buffer \(i)"
            labelBuffers.append(lb)

            // 2 vertices per aircraft (top + ground)
            guard let ab = device.makeBuffer(length: altLineStride * maxLabels * 2,
                                              options: .storageModeShared) else {
                fatalError("Failed to create alt line buffer")
            }
            ab.label = "AltLine Buffer \(i)"
            altLineBuffers.append(ab)
        }

        // Create reusable CGContext (256x64 RGBA)
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
    }

    // MARK: - Label Rasterization

    /// Rasterize a text label into the texture atlas at the given slot.
    private func rasterizeLabel(text: String, slot: Int) {
        guard let ctx = cgContext, let atlas = textureAtlas else { return }

        // Clear to transparent
        ctx.clear(CGRect(x: 0, y: 0, width: slotWidth, height: slotHeight))

        // Semi-transparent background rounded rect (theme-aware color)
        let bgRect = CGRect(x: 2, y: 2, width: slotWidth - 4, height: slotHeight - 4)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setFillColor(bgColor.cgColor)
        ctx.addPath(bgPath)
        ctx.fillPath()

        // Split text into lines
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Draw each line with CoreText (theme-aware text color)
        let font = NSFont.boldSystemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        // Flip context for text drawing (CoreText uses bottom-left origin)
        ctx.saveGState()
        ctx.textMatrix = .identity

        let lineHeight: CGFloat = 18
        let startY: CGFloat = CGFloat(slotHeight) - 14 // Start near top

        for (index, line) in lines.enumerated() {
            let attrStr = NSAttributedString(string: line, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(attrStr)
            let y = startY - CGFloat(index) * lineHeight
            ctx.textPosition = CGPoint(x: 8, y: y)
            CTLineDraw(ctLine, ctx)
        }

        ctx.restoreGState()

        // Upload pixel data to atlas
        guard let data = ctx.data else { return }

        let col = slot % columnsPerRow
        let row = slot / columnsPerRow
        let region = MTLRegion(
            origin: MTLOrigin(x: col * slotWidth, y: row * slotHeight, z: 0),
            size: MTLSize(width: slotWidth, height: slotHeight, depth: 1)
        )
        atlas.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: slotWidth * 4)
    }

    /// Allocate the next free atlas slot. Returns nil if atlas is full.
    private func allocateSlot() -> Int? {
        for i in 0..<maxSlots {
            if !slotAllocator[i] {
                slotAllocator[i] = true
                return i
            }
        }
        return nil
    }

    /// Free an atlas slot for reuse.
    private func freeSlot(_ slot: Int) {
        guard slot >= 0 && slot < maxSlots else { return }
        slotAllocator[slot] = false
    }

    // MARK: - Cache Invalidation

    /// Clear all cached labels so they are re-rasterized next frame with current theme colors.
    func invalidateCache() {
        for (_, cached) in labelCache {
            freeSlot(cached.slot)
        }
        labelCache.removeAll()
        missingFrames.removeAll()
    }

    // MARK: - Per-Frame Update

    /// Update label instances and altitude line vertices for the current frame.
    func update(states: [InterpolatedAircraftState], bufferIndex: Int, cameraPosition: SIMD3<Float>) {
        let labelPtr = labelBuffers[bufferIndex].contents()
            .bindMemory(to: LabelInstanceData.self, capacity: maxLabels)
        let altLinePtr = altLineBuffers[bufferIndex].contents()
            .bindMemory(to: AltLineVertex.self, capacity: maxLabels * 2)

        var labelIdx = 0
        var altLineIdx = 0
        var activeHexes = Set<String>()

        for state in states {
            guard labelIdx < maxLabels else { break }

            let dx = state.position.x - cameraPosition.x
            let dy = state.position.y - cameraPosition.y
            let dz = state.position.z - cameraPosition.z
            let distance = sqrt(dx * dx + dy * dy + dz * dz)

            // Skip if too far
            guard distance <= maxLabelDistance else { continue }

            // Compute opacity (LOD fade)
            let opacity: Float
            if distance < fadeLabelDistance {
                opacity = 1.0
            } else {
                opacity = 1.0 - (distance - fadeLabelDistance) / (maxLabelDistance - fadeLabelDistance)
            }

            activeHexes.insert(state.hex)

            // Build label text
            let callsignText = state.callsign.isEmpty ? state.hex : state.callsign
            let altFeet = Int(state.altitude)
            let labelText = "\(callsignText)\n\(altFeet)ft"

            // Check cache and rasterize if needed
            if let cached = labelCache[state.hex] {
                if cached.text != labelText {
                    // Text changed, re-rasterize in same slot
                    rasterizeLabel(text: labelText, slot: cached.slot)
                    labelCache[state.hex] = (text: labelText, slot: cached.slot)
                }
            } else {
                // New label: allocate slot and rasterize
                if let slot = allocateSlot() {
                    rasterizeLabel(text: labelText, slot: slot)
                    labelCache[state.hex] = (text: labelText, slot: slot)
                } else {
                    continue // Atlas full, skip this label
                }
            }

            guard let cached = labelCache[state.hex] else { continue }
            let slot = cached.slot
            let col = slot % columnsPerRow
            let row = slot / columnsPerRow

            // Atlas UV coordinates (normalized 0-1)
            let atlasUV = SIMD2<Float>(
                Float(col * slotWidth) / Float(atlasWidth),
                Float(row * slotHeight) / Float(atlasHeight)
            )
            let atlasSize = SIMD2<Float>(
                Float(slotWidth) / Float(atlasWidth),
                Float(slotHeight) / Float(atlasHeight)
            )

            // Write label instance
            labelPtr[labelIdx] = LabelInstanceData(
                position: state.position + SIMD3<Float>(0, 4.0, 0),
                size: 8.0,
                atlasUV: atlasUV,
                atlasSize: atlasSize,
                opacity: opacity,
                _pad0: 0,
                _pad1: 0,
                _pad2: 0
            )
            labelIdx += 1

            // Write altitude line vertices (top = aircraft, bottom = ground)
            altLinePtr[altLineIdx] = AltLineVertex(
                position: state.position,
                worldY: state.position.y,
                color: altLineColor
            )
            altLineIdx += 1

            altLinePtr[altLineIdx] = AltLineVertex(
                position: SIMD3<Float>(state.position.x, 0, state.position.z),
                worldY: 0,
                color: altLineColor
            )
            altLineIdx += 1
        }

        labelCounts[bufferIndex] = labelIdx
        altLineVertexCounts[bufferIndex] = altLineIdx

        // Clean up stale labels: free slots for aircraft no longer visible
        var toRemove: [String] = []
        for (hex, _) in labelCache {
            if !activeHexes.contains(hex) {
                missingFrames[hex] = (missingFrames[hex] ?? 0) + 1
                if (missingFrames[hex] ?? 0) > 180 { // ~3 seconds at 60fps
                    toRemove.append(hex)
                }
            } else {
                missingFrames[hex] = 0
            }
        }
        for hex in toRemove {
            if let cached = labelCache[hex] {
                freeSlot(cached.slot)
            }
            labelCache.removeValue(forKey: hex)
            missingFrames.removeValue(forKey: hex)
        }
    }

    // MARK: - Buffer Accessors

    func labelBuffer(at index: Int) -> MTLBuffer {
        return labelBuffers[index]
    }

    func altLineBuffer(at index: Int) -> MTLBuffer {
        return altLineBuffers[index]
    }

    func labelVertexCount(at index: Int) -> Int {
        return labelCounts[index]
    }

    func altLineVertexCount(at index: Int) -> Int {
        return altLineVertexCounts[index]
    }
}
