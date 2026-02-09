import MetalKit
import Foundation

/// Manages asynchronous fetching, Metal texture creation, and LRU caching of map tiles.
/// Tiles are fetched from OpenStreetMap tile servers and converted to Metal textures.
final class MapTileManager {

    // MARK: - Properties

    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader

    /// LRU cache: tile coordinate -> Metal texture
    private var cache: [TileCoordinate: MTLTexture] = [:]
    /// Ordered list for LRU eviction (most recently used at the end)
    private var cacheOrder: [TileCoordinate] = []
    /// Maximum number of cached textures
    private let maxCacheSize: Int = 300

    /// Tiles currently being downloaded (prevents duplicate requests)
    private var pendingRequests: Set<TileCoordinate> = []

    /// URLSession configured with proper User-Agent for OSM tile usage policy
    private let urlSession: URLSession

    /// Serial queue for thread-safe cache access
    private let cacheQueue = DispatchQueue(label: "com.airplanetracker3d.tilecache")

    /// Current visual theme (affects tile URL provider)
    var currentTheme: Theme = .day

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)

        // Configure URLSession with proper User-Agent per OSM tile usage policy
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "AirplaneTracker3D/1.0"]
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024,
                                   diskCapacity: 200 * 1024 * 1024)
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Theme Switching

    /// Switch to a new theme and clear tile cache (tiles need re-download with new style).
    func switchTheme(_ theme: Theme) {
        currentTheme = theme
        clearCache()
    }

    // MARK: - Tile URL

    /// Build the tile URL using the current theme's tile provider.
    func tileURL(for tile: TileCoordinate) -> URL {
        return ThemeManager.tileURL(for: tile, theme: currentTheme)
    }

    // MARK: - Texture Access

    /// Get the Metal texture for a tile if cached, or start an async fetch.
    /// Returns nil if the tile is still loading (caller should render placeholder).
    func texture(for tile: TileCoordinate) -> MTLTexture? {
        var cachedTexture: MTLTexture?
        var shouldFetch = false

        cacheQueue.sync {
            if let tex = cache[tile] {
                // Move to end of cacheOrder (mark as recently used)
                if let idx = cacheOrder.firstIndex(of: tile) {
                    cacheOrder.remove(at: idx)
                    cacheOrder.append(tile)
                }
                cachedTexture = tex
            } else if !pendingRequests.contains(tile) {
                pendingRequests.insert(tile)
                shouldFetch = true
            }
        }

        if shouldFetch {
            fetchTile(tile)
        }

        return cachedTexture
    }

    // MARK: - Async Fetch

    /// Download a tile PNG and convert it to a Metal texture.
    private func fetchTile(_ tile: TileCoordinate) {
        let url = tileURL(for: tile)

        #if DEBUG
        print("[MapTileManager] Fetching tile \(tile.zoom)/\(tile.x)/\(tile.y) from \(url.absoluteString)")
        #endif

        Task {
            do {
                let (data, response) = try await urlSession.data(from: url)

                // Verify we got a valid HTTP response
                if let httpResponse = response as? HTTPURLResponse {
                    #if DEBUG
                    print("[MapTileManager] Tile \(tile.zoom)/\(tile.x)/\(tile.y) HTTP \(httpResponse.statusCode), \(data.count) bytes")
                    #endif
                    if httpResponse.statusCode != 200 {
                        cacheQueue.sync { pendingRequests.remove(tile) }
                        return
                    }
                }

                // Guard against empty data (would cause MTKTextureLoader to fail)
                if data.isEmpty {
                    #if DEBUG
                    print("[MapTileManager] Tile \(tile.zoom)/\(tile.x)/\(tile.y) received empty data, skipping")
                    #endif
                    cacheQueue.sync { pendingRequests.remove(tile) }
                    return
                }

                // Convert PNG data to Metal texture
                let options: [MTKTextureLoader.Option: Any] = [
                    .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                    .textureStorageMode: MTLStorageMode.shared.rawValue,
                    .SRGB: false
                ]

                let texture = try await textureLoader.newTexture(data: data, options: options)
                texture.label = "Tile \(tile.zoom)/\(tile.x)/\(tile.y)"

                #if DEBUG
                print("[MapTileManager] Tile \(tile.zoom)/\(tile.x)/\(tile.y) texture created: \(texture.width)x\(texture.height)")
                #endif

                // Store in cache
                cacheQueue.sync {
                    pendingRequests.remove(tile)
                    cache[tile] = texture
                    cacheOrder.append(tile)

                    // Evict oldest if over limit
                    while cacheOrder.count > maxCacheSize {
                        let evicted = cacheOrder.removeFirst()
                        cache.removeValue(forKey: evicted)
                    }

                    #if DEBUG
                    print("[MapTileManager] Cache size: \(cache.count) tiles")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[MapTileManager] Failed to fetch tile \(tile.zoom)/\(tile.x)/\(tile.y): \(error.localizedDescription)")
                #endif
                cacheQueue.sync { pendingRequests.remove(tile) }
            }
        }
    }

    // MARK: - Zoom Level

    /// Map camera distance to tile zoom level (6-12).
    /// Closer camera = higher zoom number = more detail.
    func zoomLevel(forCameraDistance distance: Float) -> Int {
        // Use log2 interpolation:
        // distance 800+ -> zoom 6
        // distance ~400 -> zoom 7
        // distance ~200 -> zoom 8
        // distance ~100 -> zoom 9
        // distance ~50  -> zoom 10
        // distance ~25  -> zoom 11
        // distance <20  -> zoom 12
        let clampedDistance = max(10.0, min(1000.0, distance))
        let zoom = Int(round(15.0 - log2(clampedDistance)))
        return max(6, min(12, zoom))
    }

    // MARK: - Cache Management

    /// Clear all cached tiles (e.g., on memory warning).
    func clearCache() {
        cacheQueue.sync {
            cache.removeAll()
            cacheOrder.removeAll()
            pendingRequests.removeAll()
        }
    }
}
