# HodlJuice for Omarchy

A theme-native Bitcoin podcast receiver for the Omarchy shell.

HodlJuice tunes into a random episode from [hodljuice.app](https://hodljuice.app), autoplays it through `mpv`, and renders a real 21-band voice signal captured from only the HodlJuice PipeWire stream.

> **Status:** early beta (`0.1.0-dev`). The core Tune → Listen → Retune experience is working and tested on Omarchy 4.

## Features

- Random Bitcoin podcast discovery with automatic playback
- Any Time, Last 7 Days, and Last 30 Days filters
- Retune keeps the active filter and automatically skips unavailable results
- Real per-stream 21-band spectrum—no fake animation during playback
- Podcast name and compact live signal in the Omarchy bar
- Play/pause, ±30-second seeking, progress, duration, and resume position
- Local Saved Episodes library with keyboard and pointer navigation
- Theme-native colors, type, spacing, borders, and light/dark behavior
- Local-only state with no account, analytics, advertising, or telemetry

## Controls

| Key | Action |
|---|---|
| `Space` | Play or pause |
| `H` / `L` | Seek backward or forward 30 seconds |
| `R` | Retune and autoplay using the active filter |
| `T` | Open or close the filter tuner |
| `S` | Save or unsave the current episode |
| `B` | Open Saved Episodes |
| `J` / `K` or arrows | Move selection |
| `Enter` | Activate the selected item |
| `Esc` | Go back or close the panel |

Pointer controls are available for every primary action. On the bar, left click opens the receiver, middle click Retunes, and right click toggles playback.

## Install

Once this repository is published, install it with its Git URL:

```bash
omarchy plugin add https://github.com/OWNER/REPOSITORY.git --enable
```

The widget defaults to the center section. Move it at any time with:

```bash
omarchy bar move nmorton.hodljuice --section center
```

Remove it with:

```bash
omarchy plugin remove nmorton.hodljuice
```

## Requirements

- Omarchy 4.0+
- Python 3.11+
- `mpv`
- PipeWire tools providing `pw-record`
- Network access to `https://hodljuice.app` and episode audio hosts

Check the runtime environment from the installed plugin directory:

```bash
./bin/hodljuice doctor
```

## Saved episodes and local data

Saving creates a local bookmark; it does not download the audio. Saved metadata is duplicate-safe by audio URL, and selecting a saved episode resumes and autoplays it. If a saved URL becomes unavailable, HodlJuice reports the failure instead of silently replacing the explicit selection.

State is stored under:

```text
$XDG_STATE_HOME/hodljuice/
```

This is normally `~/.local/state/hodljuice/` and contains saved episodes, bounded discovery history, resume positions, and current playback metadata. Private runtime files live under `$XDG_RUNTIME_DIR/hodljuice/` with user-only permissions.

## Development

Run the complete local validation suite:

```bash
./tests/run.sh
./bin/hodljuice doctor
```

Test an endpoint directly:

```bash
./bin/hodljuice discover --band all --range any --json
./bin/hodljuice discover --band all --range 7 --json
./bin/hodljuice discover --band all --range 30 --json
```

Install the current checkout for live Omarchy testing without copying `.git` or generated files:

```bash
plugin="$HOME/.config/omarchy/plugins/nmorton.hodljuice"
rm -rf "$plugin"
mkdir -p "$plugin"
tar --exclude=.git --exclude='__pycache__' --exclude='*.pyc' \
  -cf - . | tar -xf - -C "$plugin"

omarchy-shell shell rescanPlugins
omarchy plugin enable nmorton.hodljuice --section center
omarchy-shell shell summon nmorton.hodljuice '{}'
```

After changing a mounted bar widget or panel structure, restart the shell:

```bash
omarchy restart shell
```

### CLI

The QML plugin invokes its bundled CLI directly. During development, use `./bin/hodljuice`:

```bash
./bin/hodljuice status
./bin/hodljuice current
./bin/hodljuice toggle
./bin/hodljuice seek -30
./bin/hodljuice saved
./bin/hodljuice history
./bin/hodljuice stop
```

## Architecture and project status

The QML layer is intentionally thin. Discovery, persistence, `mpv` IPC, and spectrum analysis live in the separately testable Python CLI.

- [`docs/development-status.md`](docs/development-status.md) — implemented and remaining work
- [`docs/implementation-plan.md`](docs/implementation-plan.md) — product and architecture plan
- [`docs/spectrum.md`](docs/spectrum.md) — real-signal design and validation

Known pre-release work includes a recent-history panel, explicit MPRIS validation, analyzer performance measurements, and eventually deciding whether to reintroduce category, people, and calendar-year filters.

## Privacy

HodlJuice has no accounts, analytics, advertising, or telemetry. It contacts `hodljuice.app` for discovery and the episode audio hosts returned by that service for playback. Remote artwork is not loaded by the current UI.

## License

[MIT](LICENSE)
