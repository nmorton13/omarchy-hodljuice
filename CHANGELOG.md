# Changelog

## 0.2.0 — Unreleased

### Added

- Episode search by topic, guest, podcast, or phrase through HodlJuice's MCP `search_episodes` tool.
- A search view with a text field, keyboard and pointer result selection, and direct playback. Press `/` to open search or return to its query field.
- A specific-year picker in the tuner, listing publication years from the current year back to 2011. The selected year applies to both random discovery and search and is retained in the widget settings.
- Search respects the active Any Time, Last 7 Days, Last 30 Days, or publication-year filter and shows up to 25 playable matches. The current episode keeps playing until a result is selected.
- Coverage for MCP transport, session reuse and recovery, metadata validation, search errors, panel state transitions, and version consistency.

### Changed

- Random discovery tries the MCP `random_episode` tool first and falls back to HTML with the same filter when MCP is unavailable or returns unusable metadata.
- Discovery and search reuse a private MCP session between CLI invocations, with one reinitialization attempt for expired sessions.
- Structured episode metadata no longer depends on website layout on the MCP path. This is a compatibility improvement, not a claim of faster discovery; initial session setup adds requests.
- Updated the README screenshot, search instructions, installation guidance, and privacy documentation.

### Compatibility

- Existing saved episodes, discovery history, and resume positions retain their formats; no data migration is required.
- Search requires MCP and reports failures without silently switching to random discovery.
- Category, people, and specific-date routes still use HTML. Collection browsing and combined category/time filters are not yet exposed in the UI.
- No AI model, account, or additional Python dependency is required. Search text is sent to HodlJuice only when submitted and is not persisted locally.

## 0.1.0

Initial receiver implementation: random podcast discovery, time filters, `mpv` playback and seeking, a per-stream 21-band PipeWire signal, local saved episodes, resume positions, and theme-native bar and panel controls.
