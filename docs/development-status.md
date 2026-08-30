# Development status

## Implemented

- [x] Empty standalone project directory selected
- [x] Product and implementation plan
- [x] Omarchy bar-widget manifest
- [x] Bar widget and nested keyboard panel lifecycle
- [x] Theme-derived receiver surface
- [x] Reusable 21-band QML renderer
- [x] Honest tuning-only generated animation
- [x] HodlJuice HTML metadata adapter
- [x] Filter URL builder
- [x] `mpv` JSON IPC bootstrap and basic controls
- [x] Retune-to-autoplay with bounded recovery for unavailable episodes
- [x] Event-driven playback status watch (replaces per-second polling), progress, duration, and remaining time
- [x] Per-process PipeWire capture using the named `hodljuice` mpv node
- [x] Real 21-band voice-responsive analyzer and QML stream
- [x] Keyboard-first range tuner with Any Time, Last 7 Days, and Last 30 Days filters
- [x] Local save/unsave button and keyboard/pointer Saved Episodes library
- [x] Bounded, duplicate-safe discovery history
- [x] Per-episode resume position persistence and playback start offset
- [x] Live panel validation under Omarchy 4
- [x] Live dark and light theme validation with restoration
- [x] Unit and contract fixtures

## Next

1. Add a panel view for recent discovery history.
2. Decide when category, people, and calendar-year filters are ready to return to the UI.
3. Complete MPRIS behavior and media-key validation.
4. Tune spectrum normalization across varied podcast feeds and measure CPU/memory (status polling is now a persistent event-driven watch; the live analyzer is the main steady-state cost).
5. Decide whether theme-dithered artwork improves the receiver or adds noise.

## Explicitly incomplete

- MPRIS metadata/control is not explicitly owned by HodlJuice; mpv metadata already appears in Omarchy's media surface.
- Discovery history persists in the core, but its browsing view is not yet implemented in the panel.
- Category and date-range combinations require the proposed JSON API.
- Artwork treatment has not been decided.
- The website adapter still parses HTML pending a versioned JSON endpoint.
