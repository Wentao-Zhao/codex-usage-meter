# Compressed history recovery

## Scope

Restore `.jsonl.zst` history without changing token accounting. A plain and compressed rollout share one session identity; prefer the plain copy when both exist. Keep the v4 index compatible and retain old totals until a replacement finishes successfully.

## Resource budget

- Bundle the official v1.5.7 decoder only; no external executable or network is used at runtime.
- One decoder at a time, maximum 8 MiB Zstandard window, 64 KiB I/O buffers and bounded JSONL line storage.
- Each archive slice consumes at most 1 MiB decoded data or approximately 8 ms of work (checked between bounded reads), followed by a 200 ms yield on background QoS.
- Back off further on low power and pause archive decoding during serious/critical thermal pressure.
- Publish progress at most once per second, checkpoint completed sessions at most once per five seconds, and persist on completion/stop.
- Unchanged completed archives use metadata only. Failed or interrupted replacements cannot overwrite valid session statistics.

## Work

- [x] Reproduce omitted compressed history with a regression test.
- [x] Vendor decoder with provenance/license and a bounded streaming bridge.
- [x] Add incremental JSONL batches preserving partial lines, model context and fork-history resets.
- [x] Add canonical discovery, compressed metadata caching, atomic replacement and archive slices to the indexer.
- [x] Schedule throttled slices and show progress in the existing update label.
- [x] Cover migration, duplicate copies, reload, malformed/truncated input, changed archives, memory/window limits, bounded reads and no-repeat scans.
- [x] Verify regression suites, a scratch real-history sample and native UI; build/sign/restart the local app. Full recovery runs only in the app to avoid two simultaneous archive scans. Do not generate DMG or push unless requested.

## Verification notes

- 260 logic checks, 270 native layout checks, 26 reminder-service checks and the existing 7 executable discovery checks passed during development.
- The real-history scratch sample used 1.01 s user + 0.25 s system CPU over 32.93 s wall time, with 24,690,688 bytes maximum RSS. It used background QoS and a 200 ms pause between slices, without changing production cache or logs.
- The 8 ms limit is cooperative, checked between bounded reads. It is not a realtime guarantee: filesystem, checkpoint and scheduling delays can overrun it; the sample's longest observed call was about 74 ms.
- Headers of all 400 local compressed rollouts required at most a 2 MiB window, below the bundled decoder's 8 MiB limit.
- A valid 16 MiB-window RLE fixture is rejected without decoding large output. Skippable frames yield after a bounded compressed-input read even when they emit no decoded data.
- The original production index was backed up under ignored `.build/usage-index-before-zstd.json`. The local app was rebuilt, signature verified, dependencies checked (no Homebrew runtime dependency), and restarted for progressive recovery.
