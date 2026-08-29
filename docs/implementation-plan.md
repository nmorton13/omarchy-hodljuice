# HodlJuice for Omarchy — Implementation Plan

## 1. Product statement

HodlJuice is a theme-native Bitcoin broadcast receiver for Omarchy. It turns the existing HodlJuice random podcast discovery experience into a small, beautiful, keyboard-first part of the desktop.

It is not a generic podcast library and should not look like a conventional player. Its core loop is deliberately short:

1. **Tune** a band and time range.
2. **Receive** a random matching Bitcoin episode.
3. **Listen** while its real voice signal becomes visible.
4. **Retune** when the listener wants another discovery.

The visual signature is a real, voice-responsive **21-band signal**. Color, typography, spacing, borders, radii, and control states come from the active Omarchy theme.

## 2. Product principles

### Theme-native, identity through form

HodlJuice must not ship a fixed green, amber, or orange palette. It consumes Omarchy's semantic `Color`, `Style`, `Border`, and shared-control APIs. The current theme owns the palette; HodlJuice owns the receiver shape, 21-band signal, motion, language, and interactions.

A theme change must update the open panel and bar widget immediately without restarting HodlJuice.

### Opinionated before configurable

The default experience should already be excellent. Initial settings are limited to choices with clear user value:

- bar display: icon, compact signal, or signal plus title
- visualizer mode: spectrum, waveform, or pulse (spectrum is default)
- motion reduction
- default band and range
- voice profile: natural or clear

There will be no arbitrary color picker, layout builder, or ten-band user EQ in the first release.

### Keyboard-first, pointer-complete

Every action works by keyboard, while obvious mouse controls remain available.

- `Space`: play/pause
- `R`: retune
- `T`: enter/leave tuner
- `H` / `L`: seek backward/forward 30 seconds
- `S`: save/unsave
- `V`: cycle visualizer
- `J` / `K` or arrows: navigate
- `Enter`: activate
- `Escape`: unwind one level, then close
- `?`: help
- `Tab` / `Shift+Tab`: switch neighboring Omarchy panels

### Motion communicates state

Animation must represent a real state:

- decoded PCM drives the live spectrum
- loading produces a bounded tuning sweep
- pause decays to a baseline
- retuning collapses the old signal before resolving the next
- errors briefly break the line using the theme's urgent role

There must be no fake random spectrum while audio is playing.

### Local, inspectable, and composable

The QML remains a thin view. Network access, state, playback, and spectrum analysis live in a separately testable local command/service. No account is required. No analytics or tracking are added.

## 3. User experience

## 3.1 Bar widget states

| State | Presentation | Primary action |
|---|---|---|
| Idle | HodlJuice glyph and quiet baseline | Open panel |
| Tuning | short themed sweep and `TUNING` | Wait/cancel |
| Buffering | restrained moving center pulse | Wait/cancel |
| Playing | compact live voice signal, optional title | Open panel |
| Paused | signal decays to a flat line | Resume |
| Error | broken baseline and urgent accent | Open details/retry |

Pointer actions:

- left click: open/close panel
- right click: play/pause
- middle click: retune with current filters
- scroll: playback volume

Animations stop when hidden except for the low-cost compact signal required by the bar.

## 3.2 Receiver panel

The first panel view contains only what is needed now:

1. receiver header and state (`SIGNAL`, `TUNING`, `PAUSED`, or error)
2. prominent 21-band live signal
3. podcast name, episode title, person/date metadata
4. progress and remaining time
5. seek, play/pause, save, and retune controls
6. current tuning summary (`ALL BITCOIN · 30D`)
7. compact shortcut strip

Artwork is optional and secondary. When enabled, it is cropped or dithered into a theme-compatible treatment rather than dominating the receiver.

## 3.3 Tuner view

Pressing `T` replaces the episode controls with the tuner rather than opening a generic settings form.

### Band

- All Bitcoin
- Human Rights
- Climate / Energy
- Film / Video
- Money
- People

Selecting People opens a second level containing the people exposed by HodlJuice.

### Range

- Any time
- Last 7 days
- Last 30 days
- Year
- Specific date

A selection is previewed but does not interrupt playback until the listener activates **Retune**.

## 3.4 Saved and recent episodes

This is a secondary view, not the home screen.

- saved episodes are local and persistent
- recent discoveries are kept in a bounded history
- selecting an entry starts playback
- deleting or clearing history requires an explicit action
- v1 does not synchronize with browser local storage

## 3.5 Reduced motion and accessibility

- use Omarchy font and sizing roles
- preserve keyboard focus visibly using shared control states
- support light and dark themes
- provide non-color state cues
- respect a plugin `reduceMotion` setting; later detect a shell-wide preference if one becomes available
- do not require Nerd Font-only labels for essential actions
- expose meaningful tooltips and accessible names where Quickshell supports them

## 4. Technical architecture

```text
BarWidget.qml ─┐
Panel.qml      ├── JSON commands/events ── hodljuice service
Visualizer.qml┘                              ├── HodlJuice HTTP adapter
                                             ├── filter/history/save state
                                             ├── mpv lifecycle + JSON IPC
                                             ├── PipeWire audio tap
                                             ├── 21-band analyzer
                                             └── MPRIS metadata/control
```

## 4.1 Plugin layer

The repository itself is an Omarchy `bar-widget` plugin with a nested panel.

- `manifest.json`: schema v1 plugin declaration
- `BarWidget.qml`: lifecycle forwarding and compact signal
- `Panel.qml`: keyboard panel and receiver/tuner views
- `components/SignalVisualizer.qml`: theme-aware 21-band rendering
- `components/ReceiverButton.qml`: shared themed control
- `Model.js`: pure formatting and view-state helpers

The plugin imports `qs.Commons` and `qs.Ui` and uses:

- `Color` semantic surface and text roles
- `Style` font, spacing, radius, and bar roles
- `BorderSurface` / `Border.surfaceSpec` for theme-resolved borders
- shared focus/hover/selected control conventions

No palette color is hard-coded. Opacity and color mixing may be applied to semantic theme colors.

## 4.2 Local service and CLI

`bin/hodljuice` is both a user-facing CLI and the control surface used by QML.

Planned commands:

```text
hodljuice discover [filters] [--json]
hodljuice play [episode-or-url]
hodljuice retune [filters]
hodljuice status --json
hodljuice events
hodljuice toggle
hodljuice pause
hodljuice seek +/-SECONDS
hodljuice volume [VALUE|up|down]
hodljuice save [current]
hodljuice saved --json
hodljuice history --json
hodljuice stop
hodljuice doctor
```

State locations follow XDG conventions:

```text
$XDG_STATE_HOME/hodljuice/state.json
$XDG_STATE_HOME/hodljuice/saved.json
$XDG_STATE_HOME/hodljuice/history.json
$XDG_RUNTIME_DIR/hodljuice/control.sock
$XDG_RUNTIME_DIR/hodljuice/events.sock
$XDG_RUNTIME_DIR/hodljuice/mpv.sock
```

Runtime directories must be owned by the current user and mode `0700`. State writes use a temporary file plus atomic rename.

## 4.3 HodlJuice HTTP adapter

The current website renders episode metadata into a hidden `.episode-info-mappapi` element. The first adapter can parse these fixed `data-*` attributes using Python's standard library:

- GUID
- podcast name and artist
- episode title
- audio URL
- podcast URL
- artwork URL
- episode date

Current routes map to tuning choices:

- `/` with the `year` query (`year=` for all time)
- `/custom_date_filter?date=YYYY-MM-DD`
- `/humanitarian`
- `/climate_energy`
- `/video`
- `/money`
- `/person/<slug>`

The current site does not expose a stable way to combine category/person routes with date ranges. The compatibility adapter must reject unsupported combinations rather than silently returning the wrong episode. Combined tuning is part of the proposed JSON API contract.

HTML parsing is an initial compatibility layer, not the long-term contract. The preferred server addition is a versioned JSON endpoint such as:

```text
GET /api/v1/random?band=money&range=30d
```

The adapter boundary must allow switching from HTML to JSON without changing playback or UI code.

Security rules:

- only HTTPS requests to configured HodlJuice origins
- validate returned audio URLs as HTTP(S)
- bounded connection and response timeouts
- bounded response size
- never execute returned strings
- retain last-good metadata on transient failures

## 4.4 Playback

The initial playback engine is `mpv` in idle mode controlled through its JSON IPC socket.

Reasons:

- mature streaming and codec handling
- already available on the target Omarchy system
- reliable seeking and playback-speed controls
- metadata can be exposed through MPRIS
- direct control over a long-lived queue and current stream

The service owns the mpv process and socket. QML never talks directly to mpv.

Required mpv behavior:

- audio only
- idle process survives between episodes
- stable user-agent and bounded network behavior
- reconnect support for transient stream failures
- volume and position polling/events
- media title, artist, album, and artwork metadata
- replay/normalization profile suitable for spoken audio

## 4.5 Real 21-band voice signal

This is a release-defining feature and receives an explicit technical spike before UI polish.

### Required properties

- derived from the HodlJuice playback stream, not whole-system audio
- 21 log-spaced bands weighted toward spoken frequencies
- 20–30 updates per second
- fast attack, slower decay, low noise floor
- normalized across quiet and loud podcast feeds
- low CPU use while playing and zero analyzer work while stopped
- event payload remains small

### Candidate capture designs

1. **PipeWire stream tap around mpv** — preferred first spike. Identify the owned mpv node and capture only that node into a small analyzer process.
2. **GStreamer playback pipeline with `spectrum` tee** — fallback if reliable per-process PipeWire capture proves brittle. It provides decoded samples and spectrum messages in one pipeline but expands playback ownership.
3. **Custom decoder/playback engine** — rejected for v1 unless the first two fail; codec and streaming scope is too large.

CAVA may be used as a reference, but it is not currently installed and must not become an unexplained hidden dependency. If used, installation requirements and raw-output configuration must be explicit.

### Band processing

- use logarithmic band boundaries, with useful voice detail concentrated approximately between 80 Hz and 8 kHz
- convert power to dB
- apply a rolling adaptive floor and ceiling
- normalize to `[0, 1]`
- apply per-band exponential smoothing
- emit exactly 21 numeric values
- QML interpolates between samples; it does not invent samples

## 4.6 MPRIS

Playback should appear as a first-class desktop media source so Omarchy media keys and media surfaces work without special bindings.

Expose:

- play/pause/stop
- next = Retune
- seek and position
- title, podcast, date, artwork
- playback status and volume

A collision policy is needed when another player is active; HodlJuice should not seize global focus until it starts playback.

## 4.7 Future TUI

The TUI is a later frontend over the same service and protocol. No core feature may exist only inside QML if it is useful to another client.

The TUI should preserve the receiver metaphor and real spectrum while adapting to full, compact, and split-terminal layouts. It is not required for the first plugin release.

## 5. Data contracts

## 5.1 Episode

```json
{
  "guid": "string",
  "podcast": "Bitcoin Park",
  "artist": "Bitcoin Park",
  "title": "Workshop: UTXO.live with Founder and Developer, Steve",
  "audioUrl": "https://example/episode.mp3",
  "podcastUrl": "https://bitcoinpark.com",
  "artworkUrl": "https://hodljuice.app/podcast-artwork/...",
  "publishedAt": "2023-04-14",
  "sourceUrl": "https://hodljuice.app/?next=True"
}
```

## 5.2 State snapshot

```json
{
  "schemaVersion": 1,
  "sequence": 42,
  "playback": "playing",
  "position": 1122.4,
  "duration": 3250.0,
  "volume": 70,
  "episode": {},
  "tuning": { "band": "all", "range": "30d", "person": null },
  "signal": { "bands": [0.0], "peak": 0.8 },
  "error": null
}
```

Snapshots and events are versioned from the beginning. Consumers ignore unknown fields.

## 6. Delivery phases

## Phase 0 — repository and contracts

**Goal:** establish a valid, testable Omarchy plugin project.

- initialize repository structure
- record product and implementation plan
- add manifest, bar widget, panel shell, visualizer component, and pure model
- add Python CLI package skeleton
- add fixtures and validation scripts
- validate against Omarchy's native plugin validator

**Exit:** plugin validates and the panel opens with theme-derived surfaces in a development install.

## Phase 1 — smallest impressive vertical slice

**Goal:** Tune → receive a real random episode → play it.

- fetch and parse a random episode from the real HodlJuice site
- present episode metadata in the receiver panel
- start/control mpv through owned JSON IPC
- implement play/pause, ±30 seconds, volume, position, Retune
- show accurate loading, playing, paused, and error states
- persist current episode and tuning

**Exit:** a user can discover and listen without opening a browser.

## Phase 2 — real signal spike

**Goal:** prove the defining interaction before expanding features.

- identify and tap only the owned mpv PipeWire stream
- calculate and publish 21 real bands
- tune attack, decay, voice weighting, and normalization on varied podcasts
- build compact and panel visualizers
- measure CPU and memory
- document fallback behavior when analysis is unavailable

**Exit:** bars visibly and truthfully respond to voices, pauses, and intros.

## Phase 3 — tuner and theme depth

**Goal:** make the product distinctively HodlJuice and fully Omarchy-native.

- implement Band and Range tuner views
- load People choices from a maintained or server-provided source
- add signal-lock/retune transition
- audit all semantic colors, border gradients, light themes, font scales, and radii
- add reduced-motion mode
- test multiple stock and community themes

**Exit:** theme changes are immediate and every filter is usable by keyboard and pointer.

## Phase 4 — saved, history, and resilience

- saved episode view
- bounded recent-discovery history
- resume position per episode
- offline/last-good metadata behavior
- stream retry and unreachable-audio retune policy
- atomic persistence and corrupt-state recovery
- privacy and threat-model review

## Phase 5 — MPRIS and release quality

- complete MPRIS service
- media key validation
- first-run dependency checks and `doctor`
- documentation, screenshots, and demo capture across themes
- packaging through `omarchy plugin add <git-url> --enable`
- list in the community plugin directory

## Phase 6 — optional TUI

- select Go/Bubble Tea or a minimal protocol client after the service stabilizes
- responsive receiver layouts
- same controls, filters, state, and real spectrum
- package independently while keeping the Omarchy plugin dependency-light

## 7. Test strategy

### Unit tests

- URL/filter construction
- HTML and future JSON episode parsing
- URL validation and response limits
- state migrations and atomic persistence
- duration/time formatting
- band normalization, smoothing, attack, and decay
- keyboard focus/state reducer

### Contract tests

- recorded HodlJuice HTML fixtures
- mpv IPC request/response fixtures
- state snapshot schema
- 21-band event length and numeric bounds

### Plugin validation

- `jq empty manifest.json`
- manifest entry points and IDs
- JavaScript syntax/tests
- Python unit tests
- shell script syntax
- `omarchy plugin validate .` when available
- `qmllint` when available

### Manual matrix

- dark, light, high-contrast, low-contrast, square, and rounded themes
- top and bottom bar positions
- compact and wide bar layouts
- keyboard-only and pointer-only operation
- no network, slow network, malformed response, unavailable stream
- another active MPRIS player
- suspend/resume and shell restart
- reduced motion

## 8. Performance budgets

Initial targets, measured on the target Omarchy machine:

- idle service CPU: effectively 0%
- playing without analyzer: under 1% average CPU beyond mpv
- analyzer overhead: under 2% average CPU
- bar redraw: at most 30 fps while playing, no animation timer while stopped
- panel open response: under 100 ms when service is warm
- Retune metadata response: network-bound with a visible state within 50 ms
- bounded memory growth across 100 consecutive Retunes

## 9. Security and privacy

- third-party plugin code runs unsandboxed inside `omarchy-shell`; keep QML thin and auditable
- external commands use fixed argument arrays, never shell interpolation
- runtime sockets and directories are private to the user
- validate URLs and content sizes before use
- no credentials are required for v1
- no analytics, advertising, tracking, or remote telemetry
- document every external host contacted
- avoid loading remote artwork until requested or explicitly enabled
- provide a concise threat model before release

## 10. Decisions and open questions

### Decided

- standalone repository in `cliHodljuice`
- Omarchy plugin first, future TUI second
- thin QML plus separately testable service
- active theme owns all color and surface styling
- 21 real bands; no fake playing visualization
- random discovery remains the primary product loop
- mpv is the initial playback engine

### Validate during spikes

- reliable per-process PipeWire capture method for mpv
- whether mpv's existing MPRIS behavior is sufficient or a dedicated service is needed
- whether HodlJuice can add a stable JSON API before the compatibility parser ships
- whether artwork belongs in the default receiver view
- best voice-band boundaries and update rate
- behavior when the website returns an episode with unreachable audio

## 11. Definition of first public release

The first public release is ready when:

- installation works through `omarchy plugin add`
- the plugin uses only active Omarchy theme semantics
- changing themes updates it live
- Band, Range, Retune, playback, seek, volume, save, and history work
- the 21-band visualization is generated from HodlJuice audio only
- MPRIS and media keys work
- keyboard and pointer paths are complete
- failures are bounded and recoverable
- tests, privacy notes, dependency documentation, and uninstall instructions are complete
- the result feels like a small integrated broadcast instrument, not a generic podcast player
