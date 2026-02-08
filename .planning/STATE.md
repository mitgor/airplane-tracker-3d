# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-08)

**Core value:** Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.
**Current focus:** v2.0 Native macOS App — defining requirements

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-02-08 — Milestone v2.0 started

## Accumulated Context

### Decisions

- [Phase 1]: Used ADSBx v2 format normalization — one parser for airplanes.live and adsb.lol
- [Phase 2]: Pre-filtered airports to medium/large only (~5K) for performance
- [Phase 3]: Used CPU-side vertex displacement (32x32 segments) for terrain
- [Phase 4]: Used wireframe outlines for airspace to avoid transparency sorting artifacts
- [v2.0]: Metal over SceneKit — maximum performance and control
- [v2.0]: SwiftUI for UI — modern, declarative
- [v2.0]: Core features first — prove native rendering, add terrain/airports later

### Notes

- Web app at ~5,616 lines — serves as feature reference for native port
- Terrain uses AWS S3 Terrarium tiles (free, no auth) — reuse in native version
- Airspace is US-only (FAA ADDS) — deferred to future native milestone
- Native app targets macOS 13+ for Metal 3 support

## Session Continuity

Last session: 2026-02-08
Stopped at: Milestone v2.0 initialization
Resume file: None
