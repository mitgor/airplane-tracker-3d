# Testing Patterns

**Analysis Date:** 2026-02-07

## Test Framework

**Runner:**
- Not detected - No testing framework configured
- No unit/integration test files found in repository
- Application is single HTML file without build process

**Assertion Library:**
- None configured
- Manual testing appears to be the approach

**Run Commands:**
```bash
# No test commands available
# Application is designed to be run directly in browser
```

## Test File Organization

**Location:**
- No test files present
- Single file structure: `airplane-tracker-3d-map.html`
- All code in one file makes unit testing difficult without refactoring

**Naming:**
- Not applicable - no test files

**Structure:**
- Not applicable - no test infrastructure

## Manual Testing Approach

**Current State:**
The application uses manual/exploratory testing rather than automated testing. Key areas tested manually:

**Three.js Rendering:**
- Visual inspection of 3D models in different themes (Day, Night, Retro)
- Performance validation through browser DevTools
- Canvas rendering verified through screenshot comparisons

**Data Integration:**
- dump1090 endpoint connectivity: Manual fetch verification
- Aircraft data parsing: Logged to console for inspection
- Stats collection: Verified through IndexedDB inspection

**User Interactions:**
- Keyboard shortcuts: Manual input testing (`Arrow keys`, `+/-`, `R`, `A`, `L`, `G`, `T`)
- Mouse interactions: Click detection, drag rotation, wheel zoom
- Touch gestures: Two-finger pinch/rotate on mobile devices

**Theme Switching:**
- Visual verification of color changes
- Tile texture reloading in each theme

## Key Testable Areas (Currently Untested)

**Data Processing:**
- `formatAltitude()`, `formatSpeed()`, `formatVertRate()` - Unit conversion functions
- `latLonToXZ()`, `latLonToTile()`, `tileToLatLon()` - Coordinate transformation functions
- `getAltitudeColor()` - Color mapping logic
- Aircraft data filtering and interpolation

**State Management:**
- Cookie-based settings persistence: `setCookie()`, `getCookie()`, `loadSettings()`, `saveSettings()`
- IndexedDB operations: `initStatsDatabase()`, `saveStatsToDb()`, `loadStatsFromDb()`
- Aircraft state tracking: Adding, updating, removing aircraft from `airplanes` Map

**Event Handling:**
- Aircraft selection: `selectPlane()`, `deselectPlane()`
- UI toggle functions: `toggleLabels()`, `toggleGraphs()`, `toggleTrails()`, `toggleStats()`
- Control callbacks: `panMap()`, `mapZoomIn()`, `mapZoomOut()`, `cameraZoomIn()`, `cameraZoomOut()`

**API Integration:**
- Aircraft enrichment: `fetchAircraftInfo()`, `fetchRouteInfo()` - External API calls
- Stats collection: `fetchStats()` - dump1090 stats.json endpoint
- graphs1090 detection: `checkGraphs1090()` - Endpoint availability check

## Suggested Testing Strategy

**Unit Tests:**
The following functions would benefit from unit testing:

```javascript
// Format functions
describe('formatAltitude', () => {
  test('converts feet to meters in metric mode', () => {
    currentUnits = 'metric';
    expect(formatAltitude(3280)).toContain('1000 m');
  });

  test('returns feet in imperial mode', () => {
    currentUnits = 'imperial';
    expect(formatAltitude(10000)).toContain('10000 ft');
  });
});

// Coordinate transformations
describe('latLonToXZ', () => {
  test('converts coordinates within map bounds', () => {
    window.mapBounds = { north: 51, south: 50, east: 8, west: 7 };
    const pos = latLonToXZ(50.5, 7.5);
    expect(pos.x).toBeCloseTo(0, 100);
    expect(pos.z).toBeCloseTo(0, 100);
  });
});

// Color functions
describe('getAltitudeColor', () => {
  test('returns green for low altitude', () => {
    expect(getAltitudeColor(2000)).toBe(0x00ff00);
  });

  test('returns different colors by altitude band', () => {
    expect(getAltitudeColor(10000)).toBe(0xffff00);
    expect(getAltitudeColor(20000)).toBe(0xff8800);
  });
});
```

**Integration Tests:**

```javascript
// Settings persistence
describe('Settings Persistence', () => {
  test('saves and loads user preferences', () => {
    currentTheme = 'night';
    showLabels = false;
    saveSettings();

    // Clear state
    currentTheme = 'day';
    showLabels = true;

    // Reload
    loadSettings();
    expect(currentTheme).toBe('night');
    expect(showLabels).toBe(false);
  });
});

// Aircraft state management
describe('Aircraft Management', () => {
  test('adds aircraft to tracking', () => {
    const data = { hex: 'a00001', lat: 51.5, lon: 0, altitude: 10000 };
    const plane = createAirplane(data);
    airplanes.set(data.hex, plane);

    expect(airplanes.has('a00001')).toBe(true);
  });

  test('updates aircraft position', () => {
    const updatedData = { hex: 'a00001', lat: 51.6, lon: 0.1 };
    const pos = latLonToXZ(updatedData.lat, updatedData.lon);
    // Update position
    expect(pos).toHaveProperty('x');
  });
});

// API mocking
describe('Aircraft Enrichment', () => {
  test('fetches aircraft information', async () => {
    // Mock hexdb.io API
    global.fetch = jest.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({
          Registration: 'G-ABCD',
          Type: 'Boeing 747'
        })
      })
    );

    const info = await fetchAircraftInfo('a00001');
    expect(info.registration).toBe('G-ABCD');
  });

  test('caches aircraft info to avoid repeated requests', async () => {
    const hex = 'a00001';
    await fetchAircraftInfo(hex);
    await fetchAircraftInfo(hex);

    // fetch should only be called once
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });
});
```

**E2E Tests:**

```javascript
// Browser-based E2E using something like Playwright
describe('Application Workflow', () => {
  test('loads aircraft data and displays them', async () => {
    // Load page
    // Verify dump1090 data fetch
    // Check aircraft render in 3D view
    // Verify aircraft count updates
  });

  test('theme switching updates visuals', async () => {
    // Select Night theme
    // Verify colors change
    // Verify tile textures reload
  });

  test('aircraft selection shows details panel', async () => {
    // Click aircraft in 3D view
    // Verify selected-plane panel appears
    // Verify data populated
  });
});
```

## Mock/Stub Patterns

**External APIs:**
Most external API calls should be mocked in tests:

```javascript
// Mock dump1090 aircraft data
const mockAircraftData = {
  now: 1707334800,
  aircraft: [
    {
      hex: 'a00001',
      flight: 'BA123  ',
      lat: 51.5074,
      lon: -0.1278,
      altitude: 35000,
      track: 270,
      gs: 450,
      baro_rate: 1000,
      squawk: '1234'
    }
  ]
};

global.fetch = jest.fn((url) => {
  if (url.includes('aircraft.json')) {
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve(mockAircraftData)
    });
  }
});

// Mock stats.json
const mockStats = {
  last1min: {
    local: {
      accepted: [500, 500],
      signal: -30
    },
    start: 1707334800,
    end: 1707334860
  }
};
```

**THREE.js Mocking:**
For unit tests, mock THREE.js components:

```javascript
jest.mock('three', () => ({
  Scene: jest.fn(),
  PerspectiveCamera: jest.fn(),
  WebGLRenderer: jest.fn(),
  Group: jest.fn(),
  Mesh: jest.fn(),
  // ... etc
}));
```

**IndexedDB Mocking:**

```javascript
const indexedDBMock = {
  open: jest.fn((dbName, version) => ({
    onsuccess: null,
    onerror: null,
    onupgradeneeded: null
  }))
};

global.indexedDB = indexedDBMock;
```

## Fixtures and Factories

**Test Data Fixtures:**

Aircraft data fixtures in `tests/fixtures/`:
```javascript
// fixtures/aircraft.json
[
  {
    hex: 'a00001',
    flight: 'BA123  ',
    lat: 51.5074,
    lon: -0.1278,
    altitude: 35000,
    track: 270,
    gs: 450,
    baro_rate: 1000,
    squawk: '1234'
  },
  {
    hex: 'a00002',
    flight: 'LH456  ',
    lat: 52.0,
    lon: 13.0,
    altitude: 30000,
    track: 90,
    gs: 480
  }
]
```

**Factory Functions:**

```javascript
// Create test aircraft object
function createTestAircraft(overrides = {}) {
  return {
    hex: 'a00001',
    flight: 'BA123  ',
    lat: 51.5074,
    lon: -0.1278,
    altitude: 35000,
    track: 270,
    gs: 450,
    baro_rate: 1000,
    squawk: '1234',
    ...overrides
  };
}

// Create test THREE.Group
function createTestPlaneGroup() {
  const group = new THREE.Group();
  group.userData = createTestAircraft();
  return group;
}
```

**Test Helpers:**

```javascript
// Initialize test environment
function setupTestEnvironment() {
  // Clear state
  airplanes.clear();
  labels = [];
  selectedPlane = null;

  // Mock current theme/units
  currentTheme = 'day';
  currentUnits = 'imperial';

  // Mock map bounds
  window.mapBounds = {
    north: 51.5,
    south: 50.5,
    east: 0.5,
    west: -0.5
  };
}

function teardownTestEnvironment() {
  // Cleanup
  airplanes.clear();
  if (statsDb) statsDb.close();
}
```

## Coverage

**Requirements:**
- None enforced currently
- No CI/CD pipeline configured

**Target Coverage:**
- Core functions: 80%+
- Data transformations: 100%
- API integrations: Mocked, 70%+
- UI event handlers: Manual/E2E testing

**View Coverage:**
```bash
# After implementing testing framework:
npm test -- --coverage

# Would generate coverage report showing:
# - Statements covered
# - Branches covered (important for conditional logic)
# - Functions covered
# - Lines covered
```

## Areas Without Tests

**Three.js Rendering:**
- Difficult to unit test without full rendering context
- Should use E2E/visual regression testing
- Visual testing (screenshot comparison) recommended

**DOM Manipulation:**
- Brittle to test against static HTML
- Should test through E2E browser automation

**Real-time Data Updates:**
- Interpolation logic: `interpolateAircraft()` (line 3900+)
- Trail updates: `updateTrail()` functions
- Label repositioning: Depends on camera position changes

**Performance-Critical Code:**
- Object pooling logic (harder to test independently)
- Garbage collection behavior
- Render loop optimization

---

*Testing analysis: 2026-02-07*

**Note:** No testing framework is currently configured. To implement automated testing, consider:
1. **Jest** or **Vitest** for unit/integration tests
2. **Playwright** or **Puppeteer** for E2E browser automation
3. **Visual Regression Testing** (Percy, Chromatic) for rendering verification
4. **Refactoring** code into smaller, testable modules (current single-file structure limits testability)
