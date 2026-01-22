# 3D Airplane Tracker with Map

An interactive 3D airplane tracking visualization that displays real-time aircraft positions using ADS-B data. Aircraft are rendered in 3D space with an interactive map background, flight trails, and detailed information panels.

![WebGL](https://img.shields.io/badge/WebGL-Enabled-green)
![THREE.js](https://img.shields.io/badge/THREE.js-r128-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Screenshot

![3D Flight Tracker - Retro 80s Theme](screenshot.png)

*Retro 80s theme showing aircraft over Germany with ADS-B statistics panel*

## Features

- **3D Aircraft Visualization** - Renders aircraft models in 3D space with altitude-based positioning
- **Flight Trails** - Configurable historical flight paths (30-300+ seconds)
- **Interactive Controls** - Rotate, zoom, pan, and auto-rotate camera modes
- **Aircraft Selection** - Click aircraft to view detailed info (altitude, speed, heading, squawk, position)
- **Three Theme Modes**
  - Day - Light blue sky with realistic colors
  - Night - Dark background with cyan highlights
  - Retro 80s - Green wireframe CRT aesthetic
- **ADS-B Statistics Panel** - Real-time graphs showing message rate, aircraft count, and signal level
- **Configurable Units** - Toggle between metric and imperial
- **Settings Persistence** - Preferences saved to browser cookies

## Requirements

- Modern web browser with WebGL support (Chrome, Firefox, Edge, Safari)
- Running [dump1090](https://github.com/flightaware/dump1090) instance serving JSON data
- Web server to serve the HTML file

## Installation

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/mitgor/airplane-tracker-3d.git
   cd airplane-tracker-3d
   ```

2. Copy the HTML file to your web server:
   ```bash
   cp airplane-tracker-3d-map.html /var/www/html/
   ```

3. Open in your browser:
   ```
   http://your-server/airplane-tracker-3d-map.html
   ```

### With dump1090

The application expects dump1090 data at these endpoints:
- `/dump1090/data/aircraft.json` - Aircraft position data
- `/dump1090/data/stats.json` - ADS-B statistics

If dump1090 is running on a different host/port, configure your web server to proxy these endpoints.

#### Nginx Example
```nginx
location /dump1090/ {
    proxy_pass http://localhost:8080/;
}
```

#### Apache Example
```apache
ProxyPass /dump1090/ http://localhost:8080/
ProxyPassReverse /dump1090/ http://localhost:8080/
```

## Usage

### Controls

| Control | Action |
|---------|--------|
| Left/Right Arrows | Rotate camera |
| +/- Buttons | Zoom in/out |
| Arrow Buttons | Pan map |
| Auto-rotate | Toggle automatic rotation |
| Reset | Return to default view |

### Settings Panel

| Setting | Options |
|---------|---------|
| Theme | Day, Night, Retro 80s |
| Units | Metric, Imperial |
| Trail Duration | 30, 60, 120, 300+ seconds |
| Labels | Show/Hide aircraft callsigns |
| Altitude Scale | 1x - 200x |
| Graph Period | 1h, 2h, 8h, 24h, 48h |

### Altitude Color Coding

| Altitude | Day/Night Color |
|----------|-----------------|
| < 5,000 ft | Green |
| 5,000 - 15,000 ft | Yellow/Cyan |
| 15,000 - 30,000 ft | Orange |
| > 30,000 ft | Red |

## Configuration

Key constants can be modified in the HTML file:

```javascript
const DATA_URL = '/dump1090/data/aircraft.json';  // Aircraft data endpoint
const REFRESH_INTERVAL = 1000;                     // Data refresh rate (ms)
const MIN_ZOOM = 6;                                // Minimum map zoom level
const MAX_ZOOM = 12;                               // Maximum map zoom level
```

## Technology Stack

- **3D Engine**: THREE.js (r128)
- **Frontend**: HTML5, CSS3, Vanilla JavaScript (ES6+)
- **Storage**: IndexedDB (stats history), Cookies (settings)
- **Maps**: OpenStreetMap, CartoDB, Stamen Toner

## Browser Support

- Chrome 80+
- Firefox 75+
- Safari 13+
- Edge 80+

WebGL and IndexedDB support required.

## License

MIT License - See LICENSE file for details.

## Acknowledgments

- [THREE.js](https://threejs.org/) for 3D rendering
- [dump1090](https://github.com/flightaware/dump1090) for ADS-B decoding
- [OpenStreetMap](https://www.openstreetmap.org/) for map tiles
