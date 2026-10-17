# Test Health

> **Status**: Living record · **Last verified**: 2026-10-17 — iOS Simulator, `iPhone 17`, Xcode 27.

Per-scheme test counts, what each bundle covers, and when it was last verified. **Counts belong
here, not in `AGENTS.md`**: that file is instructions, and a number written into it goes stale
without anyone noticing — the snapshot it used to carry was already wrong when it was removed: 63
tests where the bundle ran 66, "2 UI tests" where the app scheme runs 8 XCTest tests.
Update this file in the same change that adds, removes or renames tests, and update the date above.

## Running them

One scheme at a time, through `xcodebuild`:

```bash
xcodebuild test -scheme <Scheme> -workspace TechnicalOverlay.xcworkspace \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The framework test bundles have no app host, so `-scheme <Framework>` works directly. The traps
documented in [`AGENTS.md`](../AGENTS.md) all apply when reading the output:

- `tuist test <FrameworkTarget>` executes **zero** tests, and any `tuist test` run narrows the
  generated project until the next `tuist generate`.
- `-scheme VideoProcessor` intermittently hangs in teardown *after* printing its summary.
- `-scheme TechnicalOverlay` prints its Swift Testing summary *before* the XCTest UI tests run.

## Current state

| Scheme | Tests | Covers |
|--------|-------|--------|
| `LayoutEngine` | 3 tests (1 suite), ~0 s | The technical pane's element-box layout: the row is hidden and zero-sized when turned off, the remaining rows move up by its height at unchanged size, and the pane frame is untouched. |
| `ProtocolParser` | 56 tests (7 suites), ~8 s | Page classification, judge-detail link extraction, segment parsing into hundredths, the `ProtocolFetching` seam, `ProtocolImporter`, and the singles element-abbreviation expansion — over the committed fixture pages. |
| `VideoProcessor` | 70 tests (8 suites), ~15 s | Chunk diffing (`DiffAlgorithmTests`, the densest suite), region generation (including the clip to the video's duration and the contiguity of a clipped plan), the `Chunk` predicates the queue, renderer and stitcher share (`ChunkValidityTests`), `ChunkQueue` (reuse, staleness, `waitForCompletion`, progress), the chunk composition (`ChunkComposition`, and the shared overlay program it runs), and the real chunk-render/stitch exports. |
| `TechnicalOverlay` | 32 unit tests (6 suites) + 8 XCTest tests, ~1.5 min | Unit: the protocol merge (including the injected-translator seam), the import flow, `ClearSlidesTests` (clearing empties the model, keeps the instance identity, persists the emptied state and leaves the device preference alone), and `OverlayConfigurationTests` (the element-box `UserDefaults` preference: absent = shown, written value survives a relaunch, a launch seeds the view model from it, a `.tojson` neither carries it nor overrides it, and it changes both `renderingHash` and the technical slide's mode). XCTest: `ScoringListImportButtonTests` (2), `TechnicalOverlayUITests` (2 — the Import Protocol button), `TechnicalOverlayUITestsLaunchTests` (4). |

`LayoutEngine` (3/3) and `TechnicalOverlay` (32 unit + 8 XCTest) re-verified 2026-10-17 with the
element-box toggle, its `UserDefaults` preference and Clear Slides, both ending
`** TEST SUCCEEDED **`. `VideoProcessor` re-verified 2026-10-17 (70/70, 8 suites, including the real
render and stitch exports) after the region clip and the overlay-program extraction; `ProtocolParser`
last re-verified 2026-10-15 (56/56 after the abbreviation expansion) and is untouched by either.

## Prerequisites and known flakiness

- `VideoProcessorTests`' integration tests need the **untracked 398 MB**
  `TechnicalOverlay/TechnicalOverlay/Boston Open 2025.mov`. Without it `DefaultStitcherTests`
  early-return and pass trivially. They render real chunks and perform real exports, so they are far
  slower than the pure-logic suites; the stitcher refuses a plan whose last chunk does not end
  exactly at `videoDuration` (defensive — `generateRegions` clips every region to it, so a plan built
  from slides always ends there), so the tests pass the plan's own end as the duration.
- Those same real-export tests **crash intermittently when the machine is loaded** — a probe sweep
  or an app build running alongside is enough to kill the simulator's media stack mid-export, and
  the run then reports "Restarting after unexpected exit, crash, or test timeout" per test. They
  pass when the suite has the machine to itself. Before blaming a code change, re-run the bundle
  alone against a stash of that change.
- For a bounded run, cap the wall clock and kill the process rather than trusting it to exit (see
  the teardown hang above). A capped or killed run has no result — record the previous verified
  numbers, not the partial ones.
