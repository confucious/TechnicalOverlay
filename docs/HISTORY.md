# TechnicalOverlay — History & Rationale

> **Status**: Living record · **Last updated**: 2026-10-16

Why things are the way they are: dated decisions, the measurements behind them, what each choice
replaced, and what past passes got wrong.

**`docs/ARCHITECTURE.md` and `docs/architecture/*.md` state the current state and the rules. This
file holds the reasoning and the record of change.** The two are a pair: a constraint in a doc that a
reader might otherwise "simplify" away — the two `AVURLAsset`s, the custom preview compositor, integer
hundredths, SwiftSoup — carries a pointer to the section here that explains why it exists.

## How to maintain this file

- New design work adds a row to the [decision ledger](#decision-ledger) and, when the decision needs
  its reasoning on the record, a dated subsection under the topic it belongs to. Both go in the same
  change as the code and the doc edit.
- The ledger is **chronological, oldest first — append**. Topic sections are grouped by era, newest
  era first.
- Record a fix as what was **measured**, with the sample it came from ("clean in 8 of 8 runs against
  3 stalls in 9"). A row claiming a fix off one green run is worse than no row: the next session
  trusts it and stops looking.
- When a later pass supersedes a decision, say so in the newer entry and name what it replaces.
- **Never move a rule in here.** Rules are current state and live in the architecture docs; only the
  reasoning and the record of change live here.

## Decision ledger

| Date | Decision |
|------|----------|
| 2025-10 → 11 | Scores in integer hundredths; cascading timing; `(size, mode)` image cache; UIKit→CIImage overlay rendering. |
| 2025-11 | Chunk-based incremental rendering pipeline built (`generateRegions`/`diffRegionsIntoChunks`/`ChunkQueue`/`DefaultChunkRenderer`/`DefaultStitcher`), wired into the app's "Save Video" export flow. |
| 2026-09-01 | `graphify-out/` deleted and Graphify commit/checkout hooks uninstalled — do not regenerate; not part of the project. |
| 2026-09-01 | **Converted to Tuist.** `Project.swift`/`Config.swift` at repo root generate the project (`tuist generate`); generated `.xcodeproj`/`.xcworkspace` gitignored; the four hand-maintained `.xcodeproj` files removed. Platform is **iOS only (iPhone/iPad)** — LayoutEngine imports UIKit, so no native macOS target. Build/test via `tuist build` / `tuist test`. |
| 2026-09-01 | Documentation consolidated: root `ARCHITECTURE.md` folded into `docs/ARCHITECTURE.md`; detailed module docs stay in `docs/architecture/`. |
| 2026-10-10 | Tuist build/test commands re-verified (Tuist 4.205, Xcode 27.0 release). `tuist test <FrameworkTarget>` executes **zero tests** and exits 0; every `tuist test` run leaves a narrowed `.xcodeproj` that must be fixed with `tuist generate`. Documented the working commands; no manifest changes were needed. Known blockers are source bugs only: `MainView.swift` (app) and `DefaultStitcherTests.swift` (VideoProcessor test bundle) do not compile. |
| 2026-10-10 | Overlay file extension `.tod` → **`.tojson`**, UTI renamed to exported-only `org.cjas.jhsu.overlay-document`. `.tod` was a filename-extension collision (VLC claims `org.videolan.tod` as `public.movie`), so macOS could type our files as a non-conforming type and the file importer greyed them all out; `UTType(exportedAs:)` replaces the dynamic-prone `UTType(filenameExtension:)` lookup, and the contradictory duplicate `UTImportedTypeDeclarations` entry is gone. Mirrors the fix already made on `inline-renderer`; there is no backward-compatibility shim, so existing `.tod` files must be renamed. |
| 2026-10-10 | App runs on **Apple-silicon Macs as a "Designed for iPad" app**. Added `.macWithiPadDesign` to the shared target `destinations`, which makes Tuist emit `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES` (it defaults to **NO**, and without it "My Mac" is not a run destination). Build with `-destination 'platform=macOS,arch=arm64,variant=Designed for iPad'`. Still no native macOS or Mac Catalyst target — `SUPPORTS_MACCATALYST = NO`, LayoutEngine stays UIKit/iOS. |
| 2026-10-12 | Chunk-pipeline tracing added (plain `print`, per-chunk, `[ChunkQueue]`/`[ChunkRenderer]`/`[Stitcher]` prefixes). It immediately exposed a **stitcher bug**: `copyFrom` advanced the composition cursor by the source track's duration instead of the range it had appended, so every chunk after the first was written at a wild offset (a 3s slice of the 212s sample composed 212.5s). Fixed. Same pass: `DefaultStitcherTests` updated to the current contract (perform the export) and to pass `videoDuration` = the plan's end, app test bundles import the renamed module (`TechnicalOverlay`, not `Technical_Overlay`). All four test schemes now build and run. |
| 2026-10-12 | Restored `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` on all targets. The Tuist conversion dropped them — they lived in the *project-level* settings of the old pbxproj — silently changing the concurrency model: `generateSlides()`'s `Task` left the main actor and `VideoOverlay.render` mutated `UILabel` layers off the main thread, which UIKit flags as illegal. The code was always written for default MainActor isolation (see the `nonisolated Codable` on `VersionedOverlayData`). |
| 2026-10-12 | **`waitForCompletion()` fixed** — it returned while a chunk was still rendering (the drain started by `enqueue()` had dequeued it, so it was neither pending nor finished). `validChunks()` then omitted it, and the stitcher refused the plan, returning nil. That nil was the entire symptom of "Save Video does nothing": `MainView` resets to `.idle` and only writes to the console. The queue now keeps its drain task and awaits it. Regression test uses a renderer whose first render is 30× slower (the instant `FakeRenderer` could never see this race). |
| 2026-10-12 | **Save flow: destination first.** "Save Video" asks for the destination *before* rendering — the save panel is given a zero-byte `SaveDestinationPlaceholder` and returns the chosen URL — then the passthrough export writes `.mp4` straight to it. That removes the old temp file plus `MovieDocument`'s `Data(contentsOf:)` copy of the finished video, and avoids requesting a second presentation while the progress sheet is up. The panel's placeholder file is deleted before exporting (`AVAssetExportSession` refuses to overwrite: -11823 "already in use"). `performExport()` now throws and `ExportPhase` gained `.failed(message)`, so a failure shows up in the sheet and cleans up the destination instead of silently resetting to `.idle`. |
| 2026-10-12 | **Migrated the three composition builders off the deprecated Core Image filter API.** `videoComposition(with:applyingCIFiltersWithHandler:)` is deprecated as of iOS/macOS 27.0; the replacement is *not* a rename — it is `async throws`, the applier receives `AVCIImageFilteringParameters`, and it **returns** `AVCIImageFilteringResult(resultImage:ciContext: nil)` instead of calling `finish(with:context:)`, so the old statement-style branches became returning branches. Verified behaviour-preserving: identical composition pixels at five sample times across a dissolve, and a rendered chunk with identical duration / nominalFrameRate / naturalSize and identical decoded centre pixels (only ~8 bytes of bitstream differ). It does **not** change the simulator's CoreMedia `signalled err` notices — those come from the simulator media stack, not from this API choice. |
| 2026-10-12 | **Background render indicator.** `ChunkQueueProgress` gained `isRendering`, reported on enqueue, at drain start, after each chunk and at drain end; `MainView` shows a dot at the end of the video button row — **yellow** while the queue has work queued or in flight, **green** once every renderable chunk is rendered and the queue is idle, grey when no video is loaded. Chunks left stale by a failed render don't count as work, so the dot settles instead of sitting yellow forever. |
| 2026-10-12 | **Slides fade in from (and out to) noOverlay again.** `setupComposition(from:to:transitionStart:)` rendered the bare source frame whenever either side of a transition was nil, so the whole noOverlay ↔ slide chunk contained no overlay and the slide popped in at the next constant chunk; slide→slide dissolves were unaffected, which is why only the first transition looked wrong. A nil side now means "no overlay on that side" and dissolves against `CIImage.clear`, matching what the slide-based preview always did. The preview got the same treatment — it fed nil into the dissolve inputs and force-unwrapped `dissolve.outputImage`, which is nil once a `.none` slide (the app creates them) enters its transition window. |
| 2026-10-14 | **`ProtocolParser` implemented** (`LayoutEngine/ProtocolParser/ProtocolParser/`): page classification, judge-detail link extraction, segment parsing to integer-hundredths element values, normalized skater selection, the `ProtocolFetching` seam and `ProtocolImporter`. App side: `TechnicalOverlay/ProtocolImport.swift` with the index-keyed, timing-preserving `OverlayData.merge(_:)`. Manifest: the app and its test bundle now depend on `ProtocolParser`, which carries the SwiftSoup package. Tests: ProtocolParser 39/39, app unit tests 14/14, the invariant sweep over the 825 committed fixture rows. Two spec corrections fell out of implementing it — the page classifier needs non-link leaderboard signals, and the `inHTML:baseURL:` entry point is `async` — both documented in the module doc §7.2/§12. The import UI followed: an **Import Protocol** button on `ScoringListView`, to the left of **Add Element**, driven by `ProtocolImportModel` (module doc §8.2). |
| 2026-10-14 | **Dependency policy stated explicitly** (`docs/ARCHITECTURE.md` §2.2). The "zero external dependencies" line was a description of the project's *state*, not a rule; it is now written as such, with the actual policy: dependencies are used minimally and only when one gives an obvious, well-fitted benefit over self-written code (less code and fewer failure modes, well-fitted to the job, maintained, verified to build for our targets, with measured costs and no transitive footprint). Decisions are recorded with their measurements. |
| 2026-10-14 | **`ProtocolParser` designed** (no code yet). The module imports a skater's executed elements from the published protocol: a leaderboard page (`CATnnnSEGnnn.html`) is followed through its `<LI class="judgeDetailRef">` anchor to the static segment detail page (`SEGMnnn.html`), which is parsed. A missing anchor is an error (`.detailLinkMissing`), not a fallback — the leaderboard page's inline `detailScoreElm` table has no bonus column. Full spec, column mapping, API and verification (10 segment pages — singles and pairs — 85 skaters / 717 element rows, `bv + goe + bonus == psv` on all of them; the row count was re-measured 2026-10-15, see the module doc §12) in `docs/architecture/protocol-parser.md`; the import **merge is index-keyed and timing-preserving** (§8.1) so a re-import never discards the user's `displayTime` values. **All seven design questions are resolved** (§10, 2026-10-14): the `info` column is never used; no leaderboard-page data is ever imported (a missing judge-detail link is an error, not a fallback); zero-value elements are always imported; `panelScore` is kept for sanity checking only; sibling segments are never navigated; SwiftSoup is adopted for parsing. |
| 2026-10-14 | **First external dependency adopted: SwiftSoup 2.14.2** for `ProtocolParser`'s HTML parsing — decided by the user (§10g) and now wired in (MIT, pure Swift, no transitive dependencies; module doc §4.1). A spike implemented both a hand-rolled scanner and the SwiftSoup version over 16 fixture pages: identical output on 825 element rows, SwiftSoup 3× faster (139 ms vs 430 ms), 58 vs 162 lines — and the hand-rolled variant produced two *silent* wrong-value bugs (entity-decode ordering; `Int("-0") == 0` losing signs below 1.00, which broke 268 rows) that only the `bv + goe + bonus == psv` invariant exposed. Verified to compile for `arm64-apple-ios15.0-simulator` inside this project; costs measured at ~5 s added to a clean Debug build, ~46 s to a clean Release build, and ~4 MB per architecture. |
| 2026-10-15 | **Singles element-abbreviation expansion implemented** (`LayoutEngine/ProtocolParser/ProtocolParser/ElementNameExpander.swift`, spec and rules in [`docs/architecture/abbreviation-expansion.md`](architecture/abbreviation-expansion.md)). `ElementNameTranslating` (identity default) plus `ElementNameExpander`: jumps as `<revolutions> <name>` (`3S` → `3 Salchow`, `Eu` → `Euler`, never `1 Euler`), spins as `<name> <level>` using the short call names (`CCoSp4` → `Change Combo Spin 4`, not "Change Foot Combination Spin") with `V` after the level and space-separated from it (`CCoSpBV` → `…Spin B V`) and the name alone when the protocol called no level (`CoSp`), `StSqN` → `Step Sequence N`, `ChSq1` / `ChSp1` / `pChSq1` → `Choreo Sequence 1` / `Choreo Spin 1` / `Choreo Sequence 1` (`Choreographic` shortened, digit kept, `p` prefix dropped); parts joined by ` + `, `*` → `(Invalid)` per token, unknown tokens verbatim. `ElementNameExpanderTests.swift` adds 17 tests — **ProtocolParser is now 56/56 over 7 suites** — including a sweep that classifies **535/535** singles fixture rows with zero verbatim passthrough and checks all 825 rows of the eleven committed pages for a well-formed name. **Wired into the app the same day**: `ElementData.init(_ element:translator:)` and `OverlayData.merge(_:translator:)` write the display name on both merge paths, the translator injectable and defaulted to `ElementNameExpander()` (spec §7/§10). |
| 2026-10-15 | **Dragging the playhead no longer deadlocks the app.** The preview's CIFilter composition made every seek run `FigVideoCompositionProcessorSetPlaybackTimeRange` → `AVCoreImageFilterCustomVideoCompositor.cancelAllPendingVideoCompositionRequests`, whose `dispatch_group_wait` for outstanding frame requests runs as a barrier on the compositor session's own serial `clientcustomcompositorq`, while MediaToolbox holds the lock `AVPlayerItem.currentTime` takes — and AVKit polls `currentTime` on the main thread every scrub tick, so the whole app wedged (beachball; main thread parked in `__psynch_mutexwait` under `-[AVPlayerController updateAtMinMaxTime]`). **Fix:** the preview builder (`setupComposition()`) now pre-renders each frame through a shared `CIContext` and hands AVFoundation a `CGImage`-backed image (`filteringResult(_:over:)`) instead of a recipe it renders later, on the request being cancelled. Reproduced headlessly (seek-drag loop + `AVPlayerItemVideoOutput` frame puller + `sample` on wedge) with a hand-written composition containing no app code: the lazy applier wedges after **2** seeks, `ci-trivial` (returns `request.sourceImage` untouched) wedges just the same, while pre-rendering lands **400/400** and still composites the overlay (checked pixel-for-pixel). Controls: no composition and a plain `AVMutableVideoComposition` never wedge; seeking one-at-a-time and awaited is also safe (that is why *clicking* the scrubber always worked); a Core Animation overlay tool (`AVVideoCompositionCoreAnimationTool`) is not an alternative — it raises on playback. The chunk-renderer builders keep returning recipes, so exported pixels are unchanged. |
| 2026-10-16 | **The residual playhead freeze: the preview now owns its compositor, and the chunk renderer gets its own asset.** The 2026-10-15 pre-render fix narrowed the cancel-path wedge but did not remove it: a third freeze showed the *same* stack — main thread parked in `AVPlayerItem.currentTime`, `clientcustomcompositorq` parked in `AVCoreImageFilterCustomVideoCompositor.cancelAllPendingVideoCompositionRequests`'s `dispatch_group_wait` — this time with the chunk queue rendering (`mediaprocessor.videocompression` / `remaker.videoprocessor` / `formatwriter.qtmovie` all alive). Two mechanisms were at work, and they are fixed on opposite sides — see [Playhead freeze](#playhead-freeze). |
| 2026-10-16 | **Architecture docs split from their history.** `docs/ARCHITECTURE.md` and `docs/architecture/*.md` now carry only the current state of the app and project — no dates, no rationale narratives, no measured comparisons, no bug stories. Everything dated moved to this file, and the constraint in a doc that a reader might "simplify" away carries a pointer here. The standing rule is in [`AGENTS.md`](../AGENTS.md) → Documentation. |
| 2026-10-17 | **Element box row is optional.** `TechnicalViewModel.showsElementBox` (default `true`) drives `IsuTechnicalPaneView.showsElementBox`: hidden, `ElementRowView`'s frame is zero and the name/score/total rows stack from the top of the pane, so the pane keeps its frame and aspect while its content sits one box row higher — the rows keep their height rather than filling the vacated space, which is what keeps the text size unchanged. The flag is part of the view model and of `OverlayData` (per-document, persisted, in `renderingHash`) because `VideoOverlay.Mode` equality is both the slide cache key and a chunk's content identity — two modes differing only in this flag must compare different, or a toggle would reuse stale chunks. `OverlayData`'s decoding is now hand-written so version 1 `.tojson` files without the key still load, defaulting to boxes shown (a persisted field that stays backward-compatible need not bump the version). UI: the toggle and the render-status dot moved into their own row below Load/Save Video, since the video row was a fixed pair of buttons. |
| 2026-10-17 | **The element box toggle is a device preference**, not document data — it supersedes the storage decision in the previous row, which had put it in `OverlayData`'s Codable model. `OverlayPreferences` owns it in `UserDefaults` under `"showsElementBox"` (absent = boxes shown), read once at launch after `scoring.load()` and written on every toggle, so it survives a relaunch and applies to every document. It is out of `CodingKeys` and `update(from:)` no longer copies it, so importing a `.tojson` can't change what the device shows; the document decode stays tolerant because unknown keys are ignored, which is why no `init(from:)` is needed any more. Still in `renderingHash`, since it changes the rendered slides. |
| 2026-10-17 | **The render indicator moved onto the video** (supersedes the "end of the video button row" placement in the 2026-10-12 row, and the config-row placement in the two rows above). It is now an `.overlay(alignment: .bottomTrailing)` on `VideoPlayer`, inset 72pt from the bottom and 16pt from the trailing edge: AVKit draws its control cluster — the scrubbing control included — in that bottom band, so a fixed inset is what keeps the dot off it (the offset is not derived from the video's size or aspect). It is wrapped in a translucent capsule because the frame underneath is arbitrary video, and it sets `allowsHitTesting(false)` so taps still reach the player controls. Consequence: it is only on screen while a video is loaded, so the `.noVideo` grey state no longer has a surface. The config row it left behind now holds only the **Element boxes** toggle. |
| 2026-10-17 | **A set display time is a seek button.** In `TimeSettingsView`, a row whose time is set renders that time as a plain, tinted `Button` instead of a `Text`; tapping it calls the new `seekTo:` closure, which `MainView` wires to `player.seek(to:)`. Tapping a time only moves the playhead — it does **not** call `timeUpdated()`, so no slides are regenerated and no chunks are re-rendered. Unset rows keep the plain `--` text, since there is nowhere to jump to. The seek uses default tolerance: this is a navigation affordance, not a frame-accurate one. |
| 2026-10-17 | **The timeline is an editor, not a view of the video: it is listed whenever there is scoring data, with or without a video loaded.** Without media it is read-only — `TimeSettingsView` takes a single `Playhead?` (a `getTime`/`seekTo` pair, defined beside the view) instead of two separate closures, so "no media" is one optional rather than two independently optional capabilities: `Start Now` is a hidden button holding its layout space (the rows keep their height when a video arrives), and a set time renders as plain text rather than a seek button that would do nothing. `MainView` builds the view once, with `state.player.map { … }` supplying the playhead, so loading a video no longer swaps the view in that slot. **`Start Now` reads the playhead at tap time** — the first cut sampled `getTime()` while building the body, and since playback changes nothing SwiftUI observes, the sampled value went stale: play 30s, tap, and the stamped time was whatever moment the body last ran. A non-numeric `CMTime` (`isNumeric == false`, i.e. no current item) yields no time at all; that is what the optional return is for, and a tap in that state is a no-op rather than a written `NaN` — which would trap in `formatDisplayTime`'s `Int(floor(_:))`. |
| 2026-10-17 | **Clear Slides resets the document.** A destructive, confirmed button next to the other slides actions: the dialog is the only path, and the button is disabled when the document is already empty. `ViewModel.clearSlides()` updates the existing `OverlayData` **in place** (`update(from: OverlayData())`) rather than replacing the instance, so views already holding it see the reset; it then clears the image cache, saves the emptied state (a relaunch must not bring the data back) and regenerates the slides, which drops the overlays from the preview and marks the queue's rendered chunks stale. `showsElementBox` is untouched — it is device state, not document data. **Layout:** the four slides labels do not fit one row on a phone in portrait — measured through XCTest frames, a plain `HStack` squeezed `Save Slides` and `Edit Slides` to 70pt and wrapped each onto two lines (56.3pt tall against 34.3pt), so the row is now a `ViewThatFits`: one row when the labels fit (landscape, iPad: all four 34.3pt tall on one line) and two rows in portrait, each pair single-line. |

## Playhead freeze

Two passes, 2026-10-15 and 2026-10-16; the second supersedes the first, which superseded nothing but
narrowed the symptom without removing it.

**Symptom.** Dragging the playhead beachballed the app. The main thread was parked in
`__psynch_mutexwait` under `-[AVPlayerController updateAtMinMaxTime]`, waiting on
`AVPlayerItem.currentTime` while the player's compositor session was stuck.

**Mechanism (pass 1).** A seek ran
`FigVideoCompositionProcessorSetPlaybackTimeRange` →
`AVCoreImageFilterCustomVideoCompositor.cancelAllPendingVideoCompositionRequests`, whose
`dispatch_group_wait` for outstanding frame requests runs as a barrier on the compositor session's
own serial `clientcustomcompositorq` — while MediaToolbox holds the lock `AVPlayerItem.currentTime`
takes. AVKit polls `currentTime` on the main thread on every scrub tick, so the whole app wedged.
Fixed by having the preview builder pre-render each frame through a shared `CIContext` and hand
AVFoundation a `CGImage`-backed image (`filteringResult(_:over:)`) instead of a recipe it renders
later, on the request being cancelled.

Reproduced headlessly (seek-drag loop + `AVPlayerItemVideoOutput` frame puller + `sample` on wedge)
with a hand-written composition containing no app code: the lazy applier wedged after **2** seeks,
and `ci-trivial` (returning `request.sourceImage` untouched) wedged just the same, while
pre-rendering landed **400/400** and still composited the overlay (checked pixel-for-pixel).
Controls: no composition, and a plain `AVMutableVideoComposition`, never wedge; seeking one-at-a-time
and awaited is also safe — that is why *clicking* the scrubber always worked. A Core Animation overlay
tool (`AVVideoCompositionCoreAnimationTool`) is not an alternative: it raises on playback.

**Mechanism (pass 2).** Pre-rendering narrowed the wedge but a third freeze showed the *same* stack,
this time with the chunk queue rendering (`mediaprocessor.videocompression` /
`remaker.videoprocessor` / `formatwriter.qtmovie` all alive). Two independent mechanisms were left:

1. **The player's own session.** `setupComposition()` still built the preview with
   `AVVideoComposition(applyingFiltersTo:applier:)`, whose Core Image compositor blocks in the cancel
   path. It now builds an `AVVideoComposition.Configuration` with
   `customVideoCompositorClass = PreviewVideoCompositor.self` — a Core Image `AVVideoCompositing`
   whose `cancelAllPendingVideoCompositionRequests()` deliberately waits for nothing, so a cancelled
   frame is simply never finished and the cancel path always returns instead of waiting on a frame
   request stuck behind it. A custom compositor is handed raw frames, so the compositor bakes in the
   video track's `preferredTransform`, and it runs the same slide/dissolve program the chunk renderer
   runs, which is what keeps preview and export in step.
2. **The shared asset.** `MainView.generateSlides()` gave the chunk renderer the same `AVURLAsset`
   instance the player item used, so the chunk export and the preview contended for one asset's
   decode/compositor state.

**Measured headlessly** (`scripts/probe-scrub-deadlock.swift`: a human-paced drag, ~5 seeks/s, with
2-second chunk exports draining back to back when `export` is passed):

| Variant | Result |
|---|---|
| CIFilter composition, applier lazy (`ci-drag`) | wedges after **2** seeks |
| same, applier returns the source frame untouched (`ci-trivial`) | wedges the same — it is the composition type, not the filters |
| same, applier pre-renders its frames (`ci-eager`, the 2026-10-15 fix) | 400/400 on a plain drag; still stalls under a draining export |
| our own `AVVideoCompositing` on the preview (`shipped`, 2026-10-16) | 400/400 on a plain drag; still stalls under a draining export |
| no composition / plain `AVMutableVideoComposition` | 300/300 with the export running — the composed-frame path is the hazard |
| seeks awaited one at a time (`ci-serial`) | 400/400 — why *clicking* the scrubber always worked |
| Core Animation overlay tool (`std-catool`) | raises on playback — not an option |
| `shipped` + exporter's own `AVURLAsset` (`sep`) | **6/6 clean** (3/4 stalls without it) |
| `shipped` + ~0.6 s idle between chunk exports (`pace`) | clean 2/2 |
| `shipped` + software `CIContext` for the preview (`soft`) | clean 2/2 |

Two records of the shared-vs-separate asset comparison exist: 3 stalls in 9 drags for a shared asset
(the 2026-10-16 ledger row above) and 3/4 without `sep` against 6/6 with it (the probe's own table).

The chunk-renderer builders are never seeked, so they keep using the filter API and their rendered
pixels are unchanged.

## Element abbreviation expansion

The rules themselves are `docs/architecture/abbreviation-expansion.md` §4. This is what producing
them cost and what changed on the way.

**Rules revised twice on 2026-10-15, after the first implementation** (user): `COMBO` and `REP` went
from dropped to **shown** like `SEQ`; `Combination` became **`Combo`** in the spin names
(`CCoSp4` → `Change Combo Spin 4`); the choreographic digits went from not shown to **shown**
(`ChSq1` → `Choreo Sequence 1`); the spins use the short call names (`Change…`, not `Change Foot…`);
and the spin `V` became **separated from the level by a space** (`CCoSp1V` → `Change Combo Spin 1 V`,
`CCoSpBV` → `Change Combo Spin B V`). Supersedes the earlier digitless-choreographic rule and the
attached-`V` rule.

**Verification (2026-10-15).** All **535** singles element cells were extracted from the five
committed singles fixtures (`SEGM001`, `SEGM011`, `SEGM015`, `SEGM021`, `SEGM034`) — 187 distinct
abbreviations, 119 distinct `+`-separated tokens — and the inventory in `abbreviation-expansion.md` §3 was built
from those bytes, not from a rendered view. A throwaway prototype (Python, scratch) of the rule model
was run over every row: with `kp…` dropped, **535/535 rows classify completely, 0 unclassified
tokens**, and every example in `abbreviation-expansion.md` §5 is that prototype's real output. The prototype is what
found the `q`-vs-`StSq`/`ChSq` collision and the bonus-after-marker order (`3Lz<b1`) — both silently
mis-expanded `StSq*`/`ChSq*` and `3Lz<b1` in its first version. Mean expansion length moved 14.9 →
14.5 characters across the revisions (15.4 with `Combination`, 16.2 with `Change Foot…`, 17.3 before
the choreographic digits were shown); worst case 50 throughout.

Each spin code in `abbreviation-expansion.md` §4.3 was checked against the ISU singles abbreviation list, so the
table carries codes that do not occur in these five pages but may occur in another singles protocol.

**Implementation (2026-10-15).** `ElementNameExpander.swift` plus `ElementNameExpanderTests.swift`
beside it — **56/56 tests in 7 suites** (`xcodebuild test -scheme ProtocolParser`), 17 of them the new
suite, including both sweeps: 535/535 singles rows classified with zero verbatim passthrough, and all
825 rows of the eleven detail pages expanding to a well-formed name. Wired into the app the same day:
`ElementData.init(_ element:translator:)` and `OverlayData.merge(_:translator:)` in
`TechnicalOverlay/ProtocolImport.swift` write `displayName(for:)` into `name` on **both** paths — a
refresh at an index and an append — so a re-import cannot revert an already-timed element to a raw
code; the translator is a parameter defaulted to `ElementNameExpander()`. The app's merge suite
followed: its five existing expectations now assert display names, and a sixth merges with the
identity default to pin the seam.

**Not verified.** Pairs and ice-dance rules (the pairs codes are inventoried in
`protocol-parser.md` §9 but no rules were designed for them); the `q`/`V` semantics (taken from ISU
communications, not measured — they only decide what gets ignored, never the values); and the
on-screen fit of the longest expansions, which the module doc computes from `Metrics` rather than
measuring on a rendered overlay.

## Protocol parser

Spec: `docs/architecture/protocol-parser.md`. This section records the design pass, the
implementation's corrections to it, and the counts that moved.

**Verification performed (2026-10-14).** The two reference pages in the requirements, the event index
(`index.asp`) and **ten** segment detail pages (five singles, five pairs) were fetched from the same
event (`2026 Boston Open`, id `36683`) and the raw markup inspected — every structural claim in
`protocol-parser.md` §2, §4 and §5 comes from that markup, not from a rendered export. A throwaway prototype
(Python, scratch) of the parsing model parsed all ten detail pages: **85 skaters, 672 element rows, 0
unparsed rows, 0 violations of `bv + goe + bonus == psv`**.

- **The pairs template is the singles template.** All ten pages have exactly the same table classes
  (`sum`/`elm`/`ded`/`maj`, one each per skater, no others) and the same element-row cell-class
  sequence (`num, elem, info, bv, two, goe, ded, jud×10, ref, psv, spc`); only the element vocabulary
  differs. The design needs no pairs-specific branch.
- Confirmed the strict-parser rejection with Expat against both page kinds.
- Confirmed table nesting on the leaderboard page (`#catSegTable` → `detailScoreElm`), the
  `detailScoreSum`/`detailScoreElm` substring trap, `<B>` markup inside `ded` cells, the
  `&nbsp;`/`&lt;`-only entity set, and the all-ASCII body.
- Version drift observed within one event: `index.asp` reports ijsLive 2.6.3 while every segment page
  reports 2.6.4 — so field presence must be handled per page, not per site version.
- All seven design questions were resolved by the user on 2026-10-14 (`protocol-parser.md` §10 keeps the letters
  and the answers).
- Not verified in that pass: ice dance (no dance segment exists at this competition — the user
  confirmed), a page with a withdrawn skater (no `elm` table; no `Withdrawn`/`WD`/`DNS` marker appears
  in any fixture), other events/eras of ijsLive, and non-U.S. events.

**Implemented 2026-10-14.** `ProtocolModel.swift` (page kind, element/skater/segment),
`ProtocolHTMLParser.swift` (classification, link, segment parse, skater selection),
`ProtocolFetching.swift`, `ProtocolImporter.swift`, `ProtocolParser.swift` (errors); app side
`TechnicalOverlay/ProtocolImport.swift` (`ElementData(_:)` + `OverlayData.merge(_:)`) and
`ProtocolImportModel.swift` + the **Import Protocol** button on `ScoringListView`. Test results:
**ProtocolParser 39/39** (six suites), **TechnicalOverlayTests 22/22** (five merge, eight import flow)
and **two UI tests** for the button; the invariant sweep covers all **825** rows of the committed
fixtures.

Writing it corrected two things in the spec, both now reflected in the module doc: the classifier
needs **non-`judgeDetailRef` leaderboard signals** (a page whose link is not published was reported as
"not a protocol page" instead of `.detailLinkMissing`), and `skater(named:inHTML:baseURL:)` must be
**`async`**, because following a supplied page's link is a fetch.

**Counts re-measured 2026-10-15** (while specifying the abbreviation expansion): the ten detail pages
hold **717** element rows (535 singles + 182 pairs — the sum of the spec's own per-page column), the
invariant holds on all 717, **696** of those rows have an empty bonus cell, and the distinct
abbreviations are **241** (187 singles + 66 pairs). The 672 / 654 / 221 figures the module doc
previously carried were stale. The 825-row figure for the committed eleven-detail-page set was
already correct (717 + `SEGM033`'s 108).

## SwiftSoup adoption

`docs/architecture/protocol-parser.md` §4.1 states the outcome: parsing uses SwiftSoup 2.14.2. This is
the measurement that chose it, and the reason it is not "just write a scanner".

**The scans are ruled out by the input.** `XMLParser` (and any strict parser) is out for a reason
independent of dependencies: the pages are **not well-formed XML** even though they declare an XHTML
doctype. Both page kinds fail Expat on the same construct, plus three more:

```
<H2 class=title>2026 Boston Open</H1>          <!-- mismatched end tag -->
<H2 class=catseg>…</H2><H3>Judges' Details</H2>
&nbsp;                                          <!-- undeclared entity -->
<TABLE class=sum> … border=0 cellSpacing=0     <!-- unquoted attribute values -->
```

Verified: Expat rejects both pages — `not well-formed (invalid token): line 14, column 12`.
Pre-cleaning the page to make it XML (normalize every tag pair, declare `nbsp`) is more code than
either tolerant alternative. That left: **write a scanner, or take a package** — decided on
measurements, per `docs/ARCHITECTURE.md` §2.2.

**Candidate survey (2026-10-14).**

| Package | Fit | Maintenance | Verdict |
|---|---|---|---|
| **SwiftSoup** (`scinfu/SwiftSoup`) | Pure Swift WHATWG HTML5 parser; DOM + CSS selectors (`table.sum`, `li.judgeDetailRef a`); `text()` strips markup and decodes entities; **no package dependencies** (Foundation/Darwin only) | MIT; 5.1k ★; release 2.14.2 **two days old**; `swift-tools-version:6.0`, declares iOS 13+; compiles warning-free on Swift 6.4 | **chosen candidate** |
| Kanna (`tid-kijyun/Kanna`) | libxml2 wrapper (C library + module map) — tolerant HTML, but a system-library build dependency and a smaller API surface for our use | MIT; 2.5k ★; last release 2026-02 | runner-up, rejected on fit |
| Fuzi (`cezheng/Fuzi`) | libxml2 wrapper, XPath/CSS | MIT; 1.1k ★; last release **2020**, last push 2024-07 | effectively abandoned |
| HTMLKit (`vapor-community/HTMLKit`) | HTML *templating/dsl* engine, not a scraper | 3.0.0 **alpha** | wrong tool |

**The spike (16 fixture pages, 825 element rows, release build).** Both approaches were implemented
and run over every fixture — the ten reference detail pages plus the leaderboard pages, the event
index and a 404 body:

| | hand-rolled scanner | SwiftSoup |
|---|---|---|
| Output vs. the other implementation | **identical** on all 16 files / 825 rows (0 diffs) | **identical** |
| `bv + goe + bonus == psv` invariant | 0 violations | 0 violations |
| Reference skater (`Milo Yeon`, 9 elements) | matches `protocol-parser.md` §5.2 table | matches `protocol-parser.md` §5.2 table |
| Implementation size | 162 lines + the trap-specific tests below | **58 lines** |
| Parse time, 16 files, release | 430 ms | **139 ms** (3.1× faster) |
| Parse time, 154 KB page (largest) | 70 ms | 21 ms |
| Traps it must handle itself | 1–8 in the trap checklist | 0 — the parser handles them; only 9–11 remain |
| New code on our side to maintain | scanner + attribute parser + entity table + tag stripper + depth counting | selectors + value conversion |
| Added build time (clean) | 0 | ~5 s Debug; **~46 s Release**, iOS simulator |
| Linked binary size (arm64, iOS sim) | 0 | **+4.15 MB Debug**; +4.2 MB per arch Release (fat release framework: 67 KB → 8.80 MB unstripped, 8.80 MB → 7.96 MB after `strip -S`) |
| Transitive footprint | none | **none** (single target, Foundation only) |
| Builds for our targets | — | **verified**: compiles for `arm64-apple-ios15.0-simulator` (platform 7, SDK 27.0), links into `ProtocolParser.framework`, 7002 SwiftSoup symbols |

**The hand-rolled route is not merely more code, it is more failure modes**, and the spike hit two of
them in the same afternoon — both silently, on real data, with the row still parsing:

1. **Entity decode before tag strip.** Decoding `&lt;` first turns it into `<`, which the tag stripper
   then swallows: `2Lz&lt;&lt;` parsed as `2Lz` (and `2Lo<+1Lo` as `2Lo`) on 6 of the 16 files. The
   element abbreviation column loses its rotation markers. Correct order is strip-then-decode.
2. **Sign lost below 1.00.** `Int("-0") == 0`, so a parser that reads the sign off the whole-number
   component turns `-0.90` into `+90`: 268 rows violated the `bv + goe + bonus == psv` invariant
   (invariant failures are the only reason this was caught at all).

Neither is exotic — they are the shapes of bug a bespoke scanner invites, and each needs its own
permanent regression test. SwiftSoup cannot have them: it is a port of jsoup, a parser with two
decades of real-world tag soup behind it, and its `.text()` gives canonical, entity-decoded,
whitespace-normalized text (it normalizes `&nbsp;` away for us).

**Decision (adopted 2026-10-14): SwiftSoup is the parsing implementation.** It clears the `ARCHITECTURE.md` §2.2 bar on
every count — it removes real work (58 lines against 162 plus ~10 trap tests), it is well-fitted (CSS
selectors over exactly the tables we key on), it is maintained and proven, it has no transitive
footprint, it is 3× faster than the scanner we would write, and it is *verified* to build for this
project's targets. The costs are real and bounded: ~5 s on a clean Debug build, ~46 s on a clean
Release build, and ~4 MB per architecture of linked code (the largest single cost; accepted because
the import path is one-shot user-initiated work with no server-side size pressure, and the app
already links AVFoundation/CoreImage).

**Behaviour it imposes on us** (now stated as rules in `protocol-parser.md` §4.1): it parses to an HTML5
tree, so selectors are written against the parsed tree and section pairing stays "the next
`table.elm` in document order after the matched `table.sum`"; its `.text()` normalizes whitespace and
drops `&nbsp;`; and it is a class-based, non-`Sendable` API, so parsing stays on the calling actor or
inside a `nonisolated` function that returns only `Sendable` value types.

**The manifest edit was reverted after the spike** — nothing was wired in and the spike's
`.package.resolved` was deleted; it was re-added when the implementation landed. Not verified in the
spike: **device (arm64-only, stripped, archived) binary growth** — the numbers above are simulator
artifacts — and the dependency's behaviour on ijsLive versions other than 2.6.x.

**Fallback, if the dependency is ever dropped:** the hand-rolled scanner exists, passes the same 825
rows, and its two bugs are documented above so the next attempt does not repeat them.

## Dependency policy

Specified 2026-10-14, in response to a design pass that had been treating the project's *state* as a
rule. The docs said "zero external dependencies"; that was a description of today, not policy, and it
was written as such. The policy that replaced it — dependencies used minimally, only when one gives an
obvious and well-fitted benefit over self-written code, with measured costs — lives in
`docs/ARCHITECTURE.md` §2.2. SwiftSoup is the first exercise of it, and its measurement is the
[SwiftSoup adoption](#swiftsoup-adoption) section above: that is the shape a candidate has to argue
in.

## Core Image filter API migration

2026-10-12, superseding nothing (the old factory was deprecated, not broken).
`AVVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:)` is deprecated as of
iOS/macOS 27.0 and the replacement is *not* a rename: it is `async throws`, the applier receives
`AVCIImageFilteringParameters`, and it **returns** `AVCIImageFilteringResult(resultImage:ciContext:
nil)` instead of calling `finish(with:context:)`, so statement-style branches become returning
branches. Verified behaviour-preserving: identical composition pixels at five sample times across a
dissolve, and a rendered chunk with identical duration / nominalFrameRate / naturalSize and identical
decoded centre pixels (only ~8 bytes of bitstream differ). It does **not** change the simulator's
CoreMedia `signalled err` notices — those come from the simulator media stack, not from this API
choice. Details and the message shapes are in
[`docs/architecture/video-processor.md`](architecture/video-processor.md) §Composition API.

## Chunk pipeline

History of the incremental-render pipeline's landings and the three bugs tracing exposed
(2026-10-12; rows in the [ledger](#decision-ledger) carry the detail).

- **Chunk-pipeline tracing** (plain `print`, per-chunk, `[ChunkQueue]`/`[ChunkRenderer]`/`[Stitcher]`
  prefixes) was added first, and immediately earned itself: it is how the stitcher cursor bug and the
  `waitForCompletion()` race below were found rather than guessed at.
- **Stitcher cursor bug.** `copyFrom` advanced the composition cursor by the source track's duration
  instead of the range it had appended, so every chunk after the first was written at a wild offset —
  a 3 s slice of the 212 s sample composed 212.5 s. The doc's rule ("advance by the appended range")
  is that fix.
- **`waitForCompletion()` race.** It returned while a chunk was still rendering: the drain started by
  `enqueue()` had dequeued it, so it was neither pending nor finished. `validChunks()` then omitted
  it and the stitcher refused the plan, returning nil — and that nil was the *entire* symptom of
  "Save Video does nothing", since `MainView` reset to `.idle` and only wrote to the console. The
  queue now keeps its drain task and awaits it. The regression test needs a renderer whose first
  render is 30× slower; the instant `FakeRenderer` could never see the race.
- **Save flow rework.** The destination is chosen before any rendering (the save panel gets a
  zero-byte `SaveDestinationPlaceholder` and returns the chosen URL), which removed the old temp file
  plus `MovieDocument`'s `Data(contentsOf:)` copy of the finished video, and avoided requesting a
  second presentation while the progress sheet was up. The placeholder must be deleted before
  exporting: `AVAssetExportSession` refuses to overwrite (-11823 "already in use"). `performExport()`
  throws and `ExportPhase` gained `.failed(message)`, so a failure surfaces in the sheet and cleans up
  the destination instead of silently resetting to `.idle`.
- **Background render indicator.** `ChunkQueueProgress.isRendering` is reported on enqueue, at drain
  start, after each chunk and at drain end; the dot's three states and the "stale chunks don't count
  as work" rule are the fix for a dot that would otherwise sit yellow forever after a failed render.
- **Slides fade in from (and out to) noOverlay.** `setupComposition(from:to:transitionStart:)` used to
  render the bare source frame whenever either side of a transition was nil, so the whole
  noOverlay ↔ slide chunk contained no overlay and the slide popped in at the next constant chunk —
  slide→slide dissolves were unaffected, which is why only the first transition looked wrong. A nil
  side now means "no overlay on that side" and dissolves against `CIImage.clear`. The preview needed
  the same treatment: it fed nil into the dissolve inputs and force-unwrapped `dissolve.outputImage`,
  which is nil once a `.none` slide (the app creates them) enters its transition window.
- **Reconsidered and rejected:** folding the chunk pipeline back into `VideoComposer.setupExport()`.
  The chunk path exists so an edit to one timestamp re-renders one region instead of the whole video;
  the older path is still used for the live preview and for full-video export.

## Project infrastructure

2026-09-01 → 2026-10-12; the rules that came out of these are in `AGENTS.md` → Build & Run and
`docs/ARCHITECTURE.md` §2.1.

- **Converted to Tuist** (2026-09-01): `Project.swift`/`Config.swift` at the repo root generate the
  project; the generated `.xcodeproj`/`.xcworkspace` are gitignored and the four hand-maintained
  `.xcodeproj` files were removed. Platform is iOS only — LayoutEngine imports UIKit, so a native
  macOS target is not possible.
- **`tuist test <FrameworkTarget>` executes zero tests and exits 0** (Tuist 4.205, re-verified
  2026-10-10). The test flow focuses the graph on the tested target and drops the test bundle before
  generation, so the scheme's test action is empty; explicit `Scheme` definitions and
  `--test-targets` / `--no-upload` / `--skip-ui-tests` don't help. Every `tuist test` run also leaves
  a **narrowed** `.xcodeproj` on disk that breaks later `tuist build`/Xcode opens until
  `tuist generate` is re-run — hence the standing rule to regenerate after any test run.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` were
  dropped by the Tuist conversion** (restored 2026-10-12). They had lived in the *project-level*
  settings of the old pbxproj, so their loss silently changed the concurrency model:
  `generateSlides()`'s `Task` left the main actor and `VideoOverlay.render` mutated `UILabel` layers
  off the main thread, which UIKit flags as illegal ("Modifying properties of a view's layer off the
  main thread is not allowed"). The code was always written for default MainActor isolation — see the
  `nonisolated Codable` on `VersionedOverlayData`. This is why the settings are called out as
  non-negotiable in `AGENTS.md`.
- **"Designed for iPad" on Apple-silicon Macs** (2026-10-10): `.macWithiPadDesign` in the shared
  target's `destinations` makes Tuist emit `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES` (it defaults
  to **NO**, and without it "My Mac" is not a run destination at all). Still no native macOS target
  and no Mac Catalyst.
- **Overlay file extension `.tod` → `.tojson`** (2026-10-10): a filename-extension collision — VLC
  claims `org.videolan.tod` as `public.movie` — meant macOS could type our files as a non-conforming
  type and the file importer greyed every one of them out. `UTType(exportedAs:)` replaced the
  dynamic-prone `UTType(filenameExtension:)` lookup and the contradictory duplicate
  `UTImportedTypeDeclarations` entry was removed. Mirrors a fix already made on `inline-renderer`.
  There is no backward-compatibility shim, so existing `.tod` files must be renamed.
- **`graphify-out/` deleted** and the Graphify commit/checkout hooks uninstalled (2026-09-01) — do not
  regenerate; not part of the project.
- **Test-run reporting traps**, all still live and documented in `AGENTS.md`: `-scheme VideoProcessor`
  prints its Swift Testing summary and then hangs in teardown (the tests have passed at that point);
  `-scheme TechnicalOverlay` prints the unit-test summary *before* the XCTest UI tests run.

## Documentation

- 2026-09-01 — documentation consolidated: the root `ARCHITECTURE.md` was folded into
  `docs/ARCHITECTURE.md`, per-module detail stayed in `docs/architecture/`.
- Unknown date — the per-scheme test-count table was removed from `AGENTS.md` and replaced by
  `docs/testing.md`, because the copy in the instruction file had already gone stale unnoticed (63
  tests recorded where the bundle ran 66; "2 UI tests" where the scheme runs 8 XCTest tests). An
  instruction file is re-read every session, so a stale snapshot there is re-taught instead of
  corrected.
- 2026-10-16 — **this split.** The architecture docs had accumulated their own justification: a
  ~12 KB decision-log table, a 90-line dependency survey, verification transcripts, bug post-mortems
  and superseded rules, all of it read into every session that opened the docs (`AGENTS.md` points at
  `docs/ARCHITECTURE.md` as required reading). Dated material moved here; the docs now carry current
  state and rules, and a constraint that a reader might otherwise "simplify" away carries a pointer
  into this file. The standing rule is in [`AGENTS.md`](../AGENTS.md) → Documentation.
