# Live 21-band signal

## Selected design

The first working implementation keeps `mpv` for playback and captures only HodlJuice's PipeWire output stream.

```text
mpv --audio-client-name=hodljuice
                │
                ├── PipeWire default output → speakers
                │
                └── pw-record --target hodljuice → mono s16 PCM at 16 kHz
                                                    │
                                                    └── 21-bin Goertzel analyzer
                                                           │
                                                           └── JSON lines → QML SplitParser
```

This avoids capturing unrelated desktop audio and requires no CAVA, NumPy, GStreamer plugin, or custom decoder.

## Verified target behavior

On the target Omarchy 4 system, mpv creates a PipeWire node with:

```text
node.name = hodljuice
media.class = Stream/Output/Audio
```

`pw-record` must receive the node **name or serial**, not the transient global object ID:

```bash
pw-record \
  --target hodljuice \
  --rate 16000 \
  --channels 1 \
  --format s16 \
  --raw -
```

A live muted-output test produced real program audio with RMS around 3,800 and peaks around 18,600. Passing a transient global node ID instead captured only a low noise floor, so the named target is part of the contract.

## Analyzer

`bin/hodljuice spectrum`:

- reads 512 mono signed 16-bit samples per frame
- updates at approximately 31.25 frames per second
- applies a Hann window
- evaluates 21 logarithmically spaced centers from 90 Hz to 7.6 kHz
- converts magnitude to dB and normalizes it to `[0, 1]`
- uses fast attack and slower decay
- emits one compact JSON array per line

The QML process uses `SplitParser`; each valid 21-value frame replaces `signalBands`. QML only interpolates heights between real samples. It does not invent playing data.

## Lifecycle

- Analyzer starts only when playback state becomes `playing`.
- It stops and clears the display on pause, stop, tuning, or error.
- If the PipeWire capture exits while playback continues, QML retries after a bounded delay.
- The analyzer terminates its `pw-record` child on shutdown.
- Loading uses a separate, explicitly state-driven tuning sweep.

## Validation completed

- deterministic sine-wave unit test confirms the dominant band
- silence/decay test confirms values remain bounded and fall
- live PipeWire node isolation test
- live playback test with system sink muted during validation
- panel screenshot confirmed moving real bands, progress, remaining time, and `SIGNAL` state
- cleanup confirmed no analyzer or `pw-record` process remained

## Follow-up tuning

Before public release, test the normalization constants against:

- quiet archival recordings
- loud normalized modern podcasts
- speech over intro music
- alternating speakers
- silence and room tone
- mono and stereo feeds

CPU and long-session memory measurements remain release gates.
