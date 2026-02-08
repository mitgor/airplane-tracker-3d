import Foundation

/// Represents a slippy map tile coordinate (x, y, zoom).
/// Uses the standard OSM/Google tile numbering scheme.
struct TileCoordinate: Hashable {
    let x: Int
    let y: Int
    let zoom: Int

    /// Compute the tile coordinate containing a given lat/lon at a zoom level.
    /// Uses standard slippy map math: https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
    static func tileFor(lat: Double, lon: Double, zoom: Int) -> TileCoordinate {
        let n = pow(2.0, Double(zoom))
        let latRad = lat * .pi / 180.0

        var x = Int(floor((lon + 180.0) / 360.0 * n))
        var y = Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))

        // Clamp to valid range
        let maxTile = Int(n) - 1
        x = x % Int(n)
        if x < 0 { x += Int(n) }
        y = max(0, min(y, maxTile))

        return TileCoordinate(x: x, y: y, zoom: zoom)
    }

    /// Get the geographic bounding box of this tile.
    /// Returns (minLat, maxLat, minLon, maxLon).
    static func tileBounds(tile: TileCoordinate) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let n = pow(2.0, Double(tile.zoom))

        let minLon = Double(tile.x) / n * 360.0 - 180.0
        let maxLon = Double(tile.x + 1) / n * 360.0 - 180.0

        // Note: tile y=0 is the top (north). Higher y = further south.
        // maxLat is the north edge (lower y value), minLat is the south edge (higher y value).
        let maxLat = atan(sinh(.pi * (1.0 - 2.0 * Double(tile.y) / n))) * 180.0 / .pi
        let minLat = atan(sinh(.pi * (1.0 - 2.0 * Double(tile.y + 1) / n))) * 180.0 / .pi

        return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    /// Compute visible tiles around a center point at a given zoom level.
    /// Returns a grid of tiles extending `radius` tiles in each direction from the center tile.
    static func visibleTiles(centerLat: Double, centerLon: Double, zoom: Int, radius: Int) -> [TileCoordinate] {
        let center = tileFor(lat: centerLat, lon: centerLon, zoom: zoom)
        let n = Int(pow(2.0, Double(zoom)))
        let maxTile = n - 1

        var tiles: [TileCoordinate] = []
        tiles.reserveCapacity((2 * radius + 1) * (2 * radius + 1))

        for dy in -radius...radius {
            let ty = center.y + dy
            // Skip tiles outside valid Y range
            guard ty >= 0 && ty <= maxTile else { continue }

            for dx in -radius...radius {
                // Wrap X around the globe
                var tx = center.x + dx
                tx = ((tx % n) + n) % n
                tiles.append(TileCoordinate(x: tx, y: ty, zoom: zoom))
            }
        }

        return tiles
    }
}
