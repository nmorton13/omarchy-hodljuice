# HodlJuice for Omarchy

A theme-native Bitcoin broadcast receiver for the Omarchy shell.

HodlJuice keeps the original product's simple idea—tune a filter and receive a random Bitcoin podcast episode—while making spoken audio visible through a real 21-band signal. It is an Omarchy plugin first, with a reusable CLI/service intended to support a future TUI.

> **Status:** working vertical slice. Discovery, playback, status, real per-stream PipeWire spectrum, and the first Band/Range tuner are running inside Omarchy.

## Design promises

- Active Omarchy themes own every color, surface, border, font, radius, and spacing choice.
- The 21-band playing visualization will be derived from actual HodlJuice audio, never random animation.
- Tune → Listen → Retune remains the primary interaction.
- Keyboard and pointer paths are both first class.
- No account, analytics, advertising, or tracking.

The full implementation plan is in [`docs/implementation-plan.md`](docs/implementation-plan.md).

## Current vertical slice

- Valid Omarchy 4 bar-widget manifest
- Theme-derived receiver panel and real 21-band renderer
- Real random episode discovery from `hodljuice.app`
- Main, category, recent/year, person, and date URL contracts in the CLI
- Hidden episode metadata parsed into a stable JSON contract
- Long-lived `mpv` playback controlled through a private IPC socket
- Play/pause, ±30-second seeking, progress, duration, and remaining time
- Per-process PipeWire capture of only the named HodlJuice mpv stream
- 21 logarithmic bands with real voice response, attack, and decay
- Keyboard-first Band/Range tuner plus a live two-column People tuner
- Local save/unsave with a keyboard/pointer Saved Episodes library
- Bounded discovery history and per-episode resume positions
- Live dark/light theme validation
- Unit, fixture, manifest, and native Omarchy validation

The playing signal is generated from actual decoded HodlJuice audio. The only synthetic movement is the bounded **TUNING** sweep while a discovery request is active. See [`docs/spectrum.md`](docs/spectrum.md).

## Install

```bash
omarchy plugin add <git-url> --enable
```

HodlJuice is self-contained inside the plugin directory; the shell invokes its bundled CLI directly. Run `./bin/hodljuice doctor` from the installed checkout if playback or the visualizer is unavailable.

To remove it:

```bash
omarchy plugin remove nmorton.hodljuice
```

## Development

```bash
./tests/run.sh
./bin/hodljuice doctor
./bin/hodljuice discover --band all --range 30 --json
```

Test the checkout in Omarchy by copying it into the plugin directory (Omarchy plugin installs do not support repository symlinks):

```bash
rm -rf ~/.config/omarchy/plugins/nmorton.hodljuice
cp -a . ~/.config/omarchy/plugins/nmorton.hodljuice
omarchy-shell shell rescanPlugins
omarchy plugin enable nmorton.hodljuice --section center
```

Open it over shell IPC:

```bash
omarchy-shell shell summon nmorton.hodljuice '{}'
```

After changing panel geometry, restart the shell if hot reload does not replace the mounted widget:

```bash
omarchy restart shell
```

## CLI

```bash
hodljuice discover --band all --range any --json
hodljuice discover --band money --range 30 --json
hodljuice people --json
hodljuice discover --band people --person Lyn_Alden --json
hodljuice play --url HTTPS_URL --title "Episode" --artist "Podcast"
hodljuice toggle
hodljuice seek -30
hodljuice status
hodljuice saved
hodljuice history
hodljuice resume --url HTTPS_URL
hodljuice stop
```

During development, use `./bin/hodljuice` instead of `hodljuice`.

## Requirements

Current:

- Omarchy 4.0+
- Python 3.11+
- `mpv`
- network access to `https://hodljuice.app`

Development tests also use Node.js and `jq`, both present on standard Omarchy installations.

## Privacy and local data

HodlJuice has no accounts, analytics, advertising, or telemetry. It contacts `https://hodljuice.app` for discovery and the episode audio hosts returned by that service for playback. It does not load remote artwork in the current UI. Saved episodes, history, resume positions, and current playback metadata stay under `$XDG_STATE_HOME/hodljuice` (normally `~/.local/state/hodljuice`). Runtime control files stay under `$XDG_RUNTIME_DIR/hodljuice` with user-only permissions.

## License

MIT
