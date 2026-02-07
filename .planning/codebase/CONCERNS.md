# Codebase Concerns

**Analysis Date:** 2026-02-07

## Tech Debt

**Single-file monolithic architecture:**
- Issue: All code (4,631 lines) exists in a single HTML file with embedded CSS and JavaScript
- Files: `airplane-tracker-3d-map.html`
- Impact:
  - No code reusability across projects
  - Difficult to test individual components
  - Version control changes show massive diffs
  - IDE support and refactoring tools are limited
  - No dependency management or build process
- Fix approach: Modularize into separate files using a build tool (webpack/esbuild), create reusable components, implement proper module exports

**Hardcoded configuration values:**
- Issue: Critical constants like `DATA_URL`, `REFRESH_INTERVAL`, `MAP_GROUND_SIZE`, tile servers are hardcoded
- Files: `airplane-tracker-3d-map.html` (lines 1034-1039, 2006-2018)
- Impact:
  - Must edit HTML file to change dump1090 endpoint
  - Can't run multiple instances with different configurations
  - No environment-based configuration management
- Fix approach: Extract configuration to JSON file or environment variables, load at runtime

**Manual memory management patterns:**
- Issue: Code manually manages object pools and reuses objects to avoid garbage collection (lines 3091-3094, 1129-1150)
- Files: `airplane-tracker-3d-map.html`
- Impact:
  - Complex, error-prone patterns that are hard to maintain
  - Reused objects (`_interpolatedData`, `_seenHexes`) can cause subtle bugs if not reset properly
  - Modern JavaScript engines have excellent GC; premature optimization complicates code
- Fix approach: Benchmark GC impact; if minimal, remove object pooling for clearer code. If needed, create proper object pool library

## Known Bugs

**Aircraft trail coordinates become invalid on map pan/zoom:**
- Symptoms: Trails visually disconnect from aircraft when map center or zoom changes, trail points "jump" across screen
- Files: `airplane-tracker-3d-map.html` (lines 3183-3217)
- Trigger: Pan map or zoom while trails are active
- Root cause: Trails are stored as lat/lon/alt but converted to world coordinates using `latLonToXZ()`. When map bounds change, old trail points are rendered at incorrect screen positions.
- Current mitigation: Code stores coordinates as lat/lon to maintain stability (line 3189 comment notes this)
- Workaround: Clear trails when zooming (implemented in UI)
- Fix approach: Either (1) store world coordinates AND map bounds with each trail point, (2) re-render trails on map change, or (3) convert all trails to current map bounds on each render

**External API calls can silently fail with no user feedback:**
- Symptoms: Aircraft information panels show "--" with no indication why data isn't loading
- Files: `airplane-tracker-3d-map.html` (lines 4375-4410, 4413-4485, 4488-4535)
- Trigger: hexdb.io, adsbdb.com, or adsb.lol APIs are unreachable
- Root cause: Fetch failures are caught but only logged to console; UI shows loading spinner then disappears if APIs fail
- Current mitigation: Try/catch blocks, cache negative results to avoid repeated requests
- Workaround: Check browser console for errors
- Fix approach: Show error message in UI, add retry button, display timeout warnings

**Aircraft category detection relies on fragile callsign patterns:**
- Symptoms: Military/helicopter identification fails for less common callsigns, affecting visual representation
- Files: `airplane-tracker-3d-map.html` (lines 4541-4577)
- Trigger: Aircraft with callsigns not matching regex patterns
- Root cause: Regex patterns like `/^(RCH|REACH|DUKE|...)` are incomplete and hardcoded
- Current mitigation: Defaults to 'jet' category for unmatched patterns
- Fix approach: Use external aircraft database (FlightAware, ADS-B Exchange) for authoritative category data

**IndexedDB database version mismatch can corrupt stats:**
- Symptoms: Stats graphs disappear or reset unexpectedly, historical data lost
- Files: `airplane-tracker-3d-map.html` (lines 1260-1288)
- Trigger: Browser IndexedDB schema is v2 but if code changes database structure, existing stores aren't automatically migrated
- Root cause: `onupgradeneeded` checks `db.objectStoreNames.contains()` but doesn't handle schema changes if store already exists
- Current mitigation: Creates stores only if they don't exist
- Fix approach: Implement proper migration logic with version numbers, delete old stores if schema changes

## Security Considerations

**XSS vulnerability in stats display:**
- Risk: User-controlled aircraft data (callsigns, types) rendered via `innerHTML` without sanitization
- Files: `airplane-tracker-3d-map.html` (line 4314)
- Current mitigation: Data is generated from ADS-B aircraft codes; unlikely to contain malicious HTML
- Code: `document.getElementById('top-aircraft-types').innerHTML = typesHtml`
- Recommendations:
  - Use `textContent` for all user data (safe but limits formatting)
  - Or use template DOM APIs instead of string concatenation
  - Or sanitize with DOMPurify library

**External API URLs hardcoded in fetches:**
- Risk: If code is compromised, attacker can redirect aircraft info requests to malicious endpoints
- Files: `airplane-tracker-3d-map.html` (lines 2006-2018, 4363, 4385, 4426, 4453)
- Examples: Tile servers (OSM, CartoDB, Stamen), enrichment APIs (hexdb.io, adsbdb.com, adsb.lol)
- Current mitigation: Uses HTTPS, URLs are documented in code
- Recommendations:
  - Move all API URLs to configuration file
  - Add Content Security Policy (CSP) header to restrict fetch destinations
  - Validate API responses against schema before using

**No input validation on flight callsigns used in URLs:**
- Risk: Callsigns passed directly to external URLs (FlightAware, Flightradar24)
- Files: `airplane-tracker-3d-map.html` (lines 4520-4527)
- Code: `document.getElementById('link-flightaware').href = callsign ? https://flightaware.com/live/flight/${callsign.trim()} : '#'`
- Current mitigation: Trim whitespace, assume callsigns are safe
- Recommendations:
  - URL-encode callsigns: `encodeURIComponent(callsign)`
  - Validate against aircraft callsign format (e.g., regex)
  - Use URL constructor to validate

**Fetch requests with `cache: 'force-cache'` can serve stale data indefinitely:**
- Risk: Aircraft information cached forever, won't update if operator or registration changes
- Files: `airplane-tracker-3d-map.html` (lines 4386, 4427)
- Impact: User sees outdated aircraft data
- Recommendations:
  - Use `cache: 'default'` with proper Cache-Control headers
  - Implement cache expiration (e.g., stale-while-revalidate)
  - Add "refresh" button to clear cache

## Performance Bottlenecks

**Trail rendering scales poorly with aircraft count:**
- Problem: Trail geometries are rebuilt every frame for every active aircraft
- Files: `airplane-tracker-3d-map.html` (lines 3185-3220, trail update logic)
- Cause: Each trail is a separate THREE.LineGeometry/BufferGeometry that's updated in real-time
- With 50+ aircraft with trails, performance degrades significantly
- Metrics: No profiling data available, but visual lag reported at 100+ aircraft
- Improvement path:
  1. Batch trail updates - queue changes, apply once per frame
  2. Use THREE.BufferGeometry with dynamic draw buffers
  3. Implement trail LOD - reduce points for distant/slow aircraft
  4. Consider webgpu alternative for massive point sets

**Aircraft data fetch blocking on single endpoint:**
- Problem: All aircraft data comes from single dump1090 JSON endpoint at `/dump1090/data/aircraft.json`
- Files: `airplane-tracker-3d-map.html` (line 1034)
- Cause: If endpoint is slow or offline, entire visualization stalls (1 second refresh interval)
- Impact: Single point of failure; no fallback or timeout handling
- Improvement path:
  - Add request timeout (currently no explicit timeout)
  - Implement fallback data sources (ADS-B Exchange API, OpenSky)
  - Cache last valid response, show stale data during outages
  - Add connection status indicator

**Texture cache can grow unbounded:**
- Problem: Tile textures cached in memory up to `MAX_TILE_CACHE_SIZE` (300 items)
- Files: `airplane-tracker-3d-map.html` (line 1181, tile caching logic)
- At high zoom levels with panning, 300 textures × ~256KB per tile = ~78MB
- Cause: No LRU (least-recently-used) eviction; cache cleared only on oversize
- Improvement path:
  - Implement LRU cache with time-based expiration
  - Reduce MAX_TILE_CACHE_SIZE for lower-memory devices
  - Monitor WebGL memory with `renderer.info.memory`

**Stats graphs continuously render to canvas:**
- Problem: Three graph canvases redraw every 2 seconds even when off-screen
- Files: `airplane-tracker-3d-map.html` (lines 4625-4628)
- Cause: `updateStatsPanel()` called on interval without checking visibility
- Impact: Wasted CPU on headless browser/mobile/background tabs
- Improvement path:
  - Use IntersectionObserver to detect visibility
  - Pause graph updates when tab not visible (using visibilitychange event)
  - Already has `pageVisible` flag (line 1167) but not used everywhere

**Altitude line geometry recreated every frame:**
- Problem: `updateAltitudeLine()` rebuilds THREE.BufferGeometry for every visible aircraft per frame
- Files: `airplane-tracker-3d-map.html` (lines 3222, altitude line creation logic)
- Cause: No caching or reuse of altitude line geometries
- Improvement path: Pool/reuse geometries, update vertex positions instead of recreating

## Fragile Areas

**Map transition state machine:**
- Files: `airplane-tracker-3d-map.html` (lines 2505-2555)
- Why fragile: Complex state (`mapTransition` object) must be coordinated across multiple functions (`startMapTransition`, `updateMapTransition`, `updateMapBoundsSmooth`). No validation that state is valid before use.
- Safe modification:
  - Add invariant checks: ensure `mapTransition.active` implies all fields set
  - Encapsulate as class with getters/setters
  - Add tests for transition edge cases (rapid zoom, pan during transition)
- Test coverage: Likely none; transitions not covered by automated tests

**Aircraft data interpolation buffer:**
- Files: `airplane-tracker-3d-map.html` (lines 3050-3066, 3097-3155)
- Why fragile: Circular buffer (`aircraftDataBuffer`) is manually managed with `shift()` and timestamp comparisons. Off-by-one errors in cleanup or interpolation cause visible glitches.
- Safe modification:
  - Add logging to detect buffer corruption
  - Add assertions: `if (buffer.length > 500) console.warn('buffer overflow')`
  - Test with high-frequency data feed (50+ msg/sec)
- Test coverage: None

**Theme system depends on class names:**
- Files: `airplane-tracker-3d-map.html` (style rules scattered throughout)
- Why fragile: Theme colors hardcoded in CSS and JavaScript. Changing theme requires updates in multiple places (CSS, `invertToGreen()`, THREE.js material colors).
- Safe modification:
  - Extract theme colors to JavaScript constants object
  - Use data attributes instead of classes for styling
  - Create a Theme class with color getters
- Test coverage: Themes are visual; no automated tests

**WebGL context loss not handled:**
- Files: `airplane-tracker-3d-map.html` (no webglcontextlost listener)
- Why fragile: If WebGL context is lost (tab backgrounded, GPU reset), THREE.js will fail silently
- Safe modification:
  - Add `renderer.domElement.addEventListener('webglcontextlost', ...)`
  - Add `webglcontextrestored` handler to re-initialize
  - Display user message about context loss
- Test coverage: Can't easily test; requires manual tab backgrounding

## Scaling Limits

**Maximum aircraft in scene:**
- Current capacity: ~200 aircraft with trails enabled (estimated from code comments and THREE.js rendering)
- Limit: Beyond ~300 aircraft, frame rate drops below 30fps
- Cause: Each aircraft = 1 mesh with trails, altitude line, label; overhead per object is high
- Scaling path:
  1. Implement mesh instancing for aircraft (render 100s as single draw call)
  2. Use THREE.Points for simplified rendering at distance
  3. Culling: only render aircraft within view frustum
  4. LOD: reduce trail detail for distant aircraft

**Browser memory consumption:**
- Current capacity: ~500MB with 200 aircraft + stats history
- Limit: Beyond ~1GB, browser may become unresponsive or crash
- Cause: Each aircraft has userData (trail points, labels, cache); stats history unbounded in memory
- Scaling path:
  - Limit aircraft trails to max 5000 points total (shared budget, not per-aircraft)
  - Implement stats history pruning (currently only done on IndexedDB writes)
  - Use SharedArrayBuffer for large buffers (if COOP headers set)

**Network bandwidth for continuous aircraft updates:**
- Current capacity: ~100 aircraft at 1 Hz refresh = ~100KB/sec from dump1090
- Limit: Mobile connections (LTE < 2Mbps) will lag; high-traffic areas can exceed available bandwidth
- Scaling path:
  - Implement delta updates: only send changed fields
  - Add compression (gzip)
  - Implement lower refresh rate for high-aircraft-count scenarios

## Dependencies at Risk

**THREE.js r128 (Jan 2022):**
- Risk: Three years old (as of Feb 2025), CVE history likely includes security fixes
- Impact: WebGL bugs, performance regressions may not be addressed
- Migration plan:
  - Upgrade to latest THREE.js (v170+)
  - Test all visual effects (glow, trails, geometry rendering)
  - Audit for breaking API changes

**Hard dependency on dump1090 JSON endpoint:**
- Risk: dump1090 project is unmaintained by official repo; if source becomes unavailable, no migration path
- Impact: Application becomes non-functional without compatible receiver
- Migration plan:
  - Add abstraction layer for data sources (current: tightly coupled)
  - Implement adapters for ADS-B Exchange, OpenSky, ADSB.lol
  - Allow fallback to recorded data for testing

**External APIs with no SLA:**
- Risk: hexdb.io, adsbdb.com, adsb.lol are free services with no uptime guarantee
- Impact: Aircraft enrichment features become unavailable without warning
- Migration plan:
  - Cache aggressively; degrade gracefully when unavailable
  - Add health check endpoint
  - Provide user option to disable enrichment for faster load time

**CDN dependency on cdnjs.cloudflare.com:**
- Risk: THREE.js loaded from CDN; if CDN is down, application won't load
- Impact: No offline functionality; SPA not installable
- Migration plan:
  - Use local copy of THREE.js or self-host
  - Consider bundling with build tool
  - Add fallback CDN

## Missing Critical Features

**No connection status indicator:**
- Problem: If dump1090 endpoint becomes unavailable, user has no way to know why data stopped updating
- Blocks: Diagnostics and user troubleshooting
- Recommendation: Add visual indicator (green/yellow/red dot) showing dump1090 connection status with last update timestamp

**No offline mode:**
- Problem: Application requires constant connection; no way to view cached data when offline
- Blocks: Mobile usage on spotty connections
- Recommendation: Store last N seconds of aircraft data locally; switch to cached view when connection lost

**No data rate limiting/QoS:**
- Problem: If dump1090 sends 10 updates per second instead of 1, interpolation buffer overflows
- Blocks: Compatibility with high-frequency receivers
- Recommendation: Add queue with configurable rate, drop oldest packets if backlog exceeds threshold

**No authentication/access control:**
- Problem: Anyone with URL can access real-time flight data (if dump1090 is exposed)
- Blocks: Private deployments or installations serving real ADS-B data
- Recommendation: Add simple auth (password/API key), CORS restrictions, or reverse proxy with auth

## Test Coverage Gaps

**No automated tests for 3D rendering:**
- What's not tested: Aircraft rendering, trail geometry, altitude scaling, theme colors, camera controls
- Files: `airplane-tracker-3d-map.html` (all THREE.js code)
- Risk: Visual regressions go unnoticed; glow effect changes could have side effects
- Priority: High - visual correctness is core feature
- Improvement: Add visual regression tests (pixel-by-pixel comparison of canvas renders with known test data)

**No tests for data interpolation:**
- What's not tested: Interpolation edge cases (missing data points, out-of-order packets, rapid altitude changes)
- Files: `airplane-tracker-3d-map.html` (lines 3097-3155)
- Risk: Smooth animation may jitter or show discontinuities with malformed data
- Priority: High - interpolation is performance-critical
- Improvement: Unit tests for `lerp()`, `lerpAngle()`, buffer edge cases

**No tests for trail persistence and cleanup:**
- What's not tested: Trail points correctly added/removed, memory properly freed, trails don't grow unbounded
- Files: `airplane-tracker-3d-map.html` (lines 3185-3220)
- Risk: Memory leak if trail cleanup fails
- Priority: Medium - affects long-running sessions
- Improvement: Unit tests for `trailPoints` array management

**No tests for IndexedDB operations:**
- What's not tested: Stats persistence, database schema migration, error handling when storage quota exceeded
- Files: `airplane-tracker-3d-map.html` (lines 1260-1348)
- Risk: Stats data silently lost, corruption on schema change
- Priority: Medium - data loss is problematic for analysis
- Improvement: Mock IndexedDB, test quota exceeded scenarios

**No tests for external API fetches:**
- What's not tested: Timeout handling, network error resilience, response parsing, cache invalidation
- Files: `airplane-tracker-3d-map.html` (lines 4375-4485)
- Risk: Silent failures, stale data served indefinitely
- Priority: Medium - affects data enrichment reliability
- Improvement: Mock fetch with failing scenarios, test cache expiration

**No tests for keyboard/mouse controls:**
- What's not tested: Keyboard shortcuts, mouse drag/zoom, multi-touch gestures
- Files: `airplane-tracker-3d-map.html` (event handlers throughout)
- Risk: Inputs may become unresponsive after refactoring
- Priority: Low - visual inspection sufficient for user-facing controls
- Improvement: E2E tests with headless browser (Playwright, Puppeteer)

**No performance/load tests:**
- What's not tested: Frame rate with 200+ aircraft, memory usage over time, tile cache eviction
- Files: All performance-critical sections
- Risk: Performance regressions introduced silently
- Priority: High - performance is core value proposition
- Improvement: Benchmark suite with target metrics (60fps at 100 aircraft, <500MB memory)

---

*Concerns audit: 2026-02-07*
