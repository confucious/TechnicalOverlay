# Test Health

> **Status**: Living record · **Last verified**: 2026-11-04 — iOS Simulator, `iPhone 17`, Xcode 27.

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
| `LayoutEngine` | 17 tests (1 suite), ~1 s | The classic technical pane's element-box layout — the row is hidden and zero-sized when turned off, the remaining rows move up by its height at unchanged size, the pane frame is untouched; `LabelBoxView`'s inset arithmetic (box and label insets scale with the row's height, a full-bleed box keeps only the label inset, the font follows the label's height rather than the row's); `Classic 2` (the same pane with `RowOrder.totalFirst`: the running total first, the boxes last, the classic sizes and one-border row gaps unchanged, and the rows still moving up when the boxes are hidden), and the ISU 2026 pane: its rows stack running-total to element-boxes inside the pane with the box row shortest, the name row wears the leader-row blue with white text, its own rule, text one point larger than the block's in a row taller in proportion to it, an overhang past the block and the chips' hairline below it, each row carries its part of the element (including `BASE VALUE:`/`EXECUTION:` and the sign-coloured execution cell), the block's values sit in one score column, the boxes lay out from the modes it is handed, stay square and evenly pitched with a hairline between them and no row background behind them, hiding the box row leaves the rows above in place, and `VideoOverlay` draws the pane the mode's style names. |
| `ProtocolParser` | 87 tests (8 suites), ~18 s | Page classification, judge-detail link extraction, segment parsing into hundredths, the `ProtocolFetching` seam (including a `file:` body read from a saved page directory), `ProtocolImporter`'s routing, the element-abbreviation expansion for singles, pairs and ice dance — over the committed fixture pages, with a zero-passthrough sweep per vocabulary (535 / 182 / 247 rows) — and the ISU FS Manager PDF path (`ProtocolPDFParserTests`): header sniffing, both committed documents read into skaters and elements, the Bonus column, the second-half and info columns ignored, the `base + goe + bonus == panel` sweep over 132 rows, name matching, contiguous numbering, and the two rejection paths — plus the abbreviation expansion over those documents (the amount-less bonus marker `3Tb` → `3 Toeloop`, and a zero-passthrough sweep over their 46 abbreviations). |
| `VideoProcessor` | 77 tests (10 suites), ~15 s | Chunk diffing (`DiffAlgorithmTests`, the densest suite), the shared span walk and its per-frame resolution (`OverlaySpanTests`: full-length transitions for crowded slides, and the mid-dissolve frame both paths now agree on), region generation (including the clip to the video's duration and the contiguity of a clipped plan), the `Chunk` predicates the queue, renderer and stitcher share (`ChunkValidityTests`), `ChunkQueue` (reuse, staleness, `waitForCompletion`, progress, and `shutdown()` deleting the files it rendered — `ChunkQueueShutdownTests`, including a shutdown that lands mid-render), the chunk composition (`ChunkComposition`, and the shared overlay program it runs), and the real chunk-render/stitch exports. |
| `TechnicalOverlay` | 52 unit tests (8 suites) + 9 XCTest tests, ~2 min | Unit: the protocol merge (including the injected-translator seam), the import flow (from an address and from a file picked on disk: a saved detail page, a saved leaderboard page following its link to the file beside it, a PDF routed by its bytes whatever the extension, an unreadable file, and the skater-name guard on both paths), `TimingCascadeTests` (moving a timestamp carries the delta to later items, an unscheduled intro run is stamped `+5 s` up to the next timed slide, an unscheduled element is left alone, an out-of-range index is a no-op), `ClearSlidesTests` (clearing empties the model, keeps the instance identity, persists the emptied state and leaves the device preference alone), and `OverlayConfigurationTests` (the element-box `UserDefaults` preference: absent = shown, written value survives a relaunch, a launch seeds the view model from it, a `.tojson` neither carries it nor overrides it, and it changes both `renderingHash` and the technical slide's mode), and `TechnicalPaneStylePreferenceTests` on the same terms for the pane style (absent = classic, an unrecognised stored value = classic, the written style survives a relaunch, a launch seeds the view model from it, a `.tojson` neither carries it nor overrides it, it changes `renderingHash`, and `slidePlan()` draws elements in the stored style). XCTest: `ScoringListImportButtonTests` (3 — the button's row, the dialog's address and file options, the file picker), `TechnicalOverlayUITests` (2 — the Import Protocol button), `TechnicalOverlayUITestsLaunchTests` (4). |

`ProtocolParser` (87/87, 8 suites) and `TechnicalOverlay` (52 unit + 9 XCTest) verified 2026-11-04
after the **Import From File** entry point, the fetcher's `file:` body read and the file option's
move into the import dialog — both ending
`** TEST SUCCEEDED **`; the import dialog was also checked in a rendered screenshot.
`LayoutEngine` (17/17) and `TechnicalOverlay` (47 unit + 8 XCTest) re-verified 2026-11-02 after the
ISU 2026 pane, its style menu and both panes' refinements — both ending `** TEST SUCCEEDED **`;
`ProtocolParser` (86/86, 8 suites) re-verified the same day after the PDF path and its
amount-less bonus marker landed. Before that, `LayoutEngine`
(5/5) and `TechnicalOverlay` (38 unit + 8 XCTest) were re-verified 2026-10-17 — the app
bundle again after the main-screen split and the shared timing cascade, `LayoutEngine` after the
row refactor onto `LabelBoxView`. `VideoProcessor` re-verified 2026-10-17
(77/77, 10 suites, including the real render and stitch exports) after the region clip, the
overlay-program extraction, the queue teardown and the shared span walk; `ProtocolParser` re-verified 2026-10-18 (70/70, 7 suites) after the pairs and ice-dance expansion
landed; `TechnicalOverlay` re-verified the same day (38 unit + 8 XCTest) against it.

## Prerequisites and known flakiness

- `VideoProcessorTests`' integration tests need the **untracked 398 MB**
  `TechnicalOverlay/TechnicalOverlay/Boston Open 2025.mov`, looked up in one place
  (`VideoProcessorTests/TestSupport.swift`). Without it `DefaultStitcherTests`
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
