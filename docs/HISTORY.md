# TechnicalOverlay — History & Rationale

> **Status**: Living record · **Last updated**: 2026-11-04

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
| 2026-10-17 | **Region plans are clipped to the video, and the chunk rules moved onto `Chunk`.** `generateRegions` could end the plan past the video: a slide at 119.5 s of a 120 s video produced `0.0–119.5, 119.5–120.5`, and `DefaultStitcher.stitch` requires the plan to end *exactly* at `videoDuration`, so a valid timeline failed with "The rendered chunks don't cover the whole video" — any last slide within the 0.75 s transition of the end was enough. Reproduced with a probe test before the fix, at `preferredTimescale 1000`: at timescale 1 the 119.5 rounds to 119 and the overrun vanishes, which is why the region suite never saw it. Every region is now clipped to `[0, videoDuration]` and an emptied one is dropped, a slide at or beyond the end adds none, and the sweep reads as three `append(type, from:to:)` calls instead of hand-built ranges. Second half, same pass: `Chunk.isStale` became `isInPlan` (it always meant "still in the plan"), and new `hasOverlay` / `needsRender` / `isValid` replace the `type != .noOverlay` (17 sites) and `renderState == .pending` (8) predicates copied through `ChunkQueue`, `DefaultChunkRenderer` and `DefaultStitcher` — `validChunks()` and the stitcher now share one filter, which is what makes the two agree by construction. Tests: +2 in `RegionGenerationTests` (a clipped plan stays contiguous and ends at the duration; a slide past the end is one whole-video noOverlay) and +2 in a new `ChunkValidityTests` — **VideoProcessor 70/70 in 8 suites**, including the real render and stitch exports. |
| 2026-10-17 | **One overlay program, and the chunk composition has its own type.** The dissolve existed twice — `PreviewVideoCompositor.composited` and `VideoComposer.setupComposition(from:to:transitionStart:)` — two copies of the same three lines that had to agree by inspection; the docs asserted they matched and nothing enforced it. `OverlayCompositing.swift` now holds `OverlayComposite` (`hold(_:over:)`, `dissolve(from:to:progress:over:)`), which both callers use: the preview picks the slide by time, `ChunkComposition` is handed the endpoints, and the 0…1 clamp on `progress` lives in one place. The chunk builders left `VideoComposer`, which had been a preview-state holder (`asset` + `slides`) that the export pipeline reached through for a static function — `DefaultChunkRenderer` built `VideoComposer(asset:slides: [])` twice just to get a composition. It now holds one `ChunkComposition(asset:)`, and `VideoComposer` is the preview path only. Deleting the chunk builders took the two `setupExport(overlay:…)` / `setupExport(from:to:…)` overloads with them: nothing called them, so the three-way `setupExport` family collapsed to the one slide-based export (which the app also does not call — the chunk pipeline is the export path; it stays as the documented full-video path). Pixels are unchanged by construction: `OverlayComposite` runs the same filter, the same clear-image convention for a nil side, and the same clamp. Verified: VideoProcessor 70/70 in 8 suites, the real render/stitch exports included; `tuist build TechnicalOverlay` succeeded. |
| 2026-10-17 | **The main screen's view model was split into the jobs it was doing.** `MainView` held a 264-line nested `ViewModel` doing five things at once — security scoping, asset probing, slide generation and player-item swaps, chunk-queue lifecycle, and the export flow — inside a 649-line view file, which is why none of it could be tested without a view. It is now `MainViewModel` (the player, the document, and `assetUrl`'s setter: adopt the new file, drop the old plan, regenerate) with three collaborators: `AssetSession` (the security scope and the size probe, cached per file), `RenderPipeline` (preview composition + the chunk queue, publishing the indicator's `status` and the queue's `progress`), and `ExportCoordinator` (phase, stitching progress, stitch-and-write, cleanup on failure). The queue status enum moved onto the pipeline it describes (`RenderPipeline.Status`), and `MainView` keeps only the SwiftUI presentation of it. Behaviour is unchanged, including the two deliberate oddities the split had to preserve: the export writes to a destination chosen before any work, and the chunk renderer still gets its own `AVURLAsset`. `@State private var state` became `model`, which is what CLEANUP's naming item asked for. Queue teardown is still the old behaviour — swapping videos drops the reference while the old drain finishes (B4 in `CLEANUP.md`, now a one-line change in `RenderPipeline.reset`), and `generateSlides()` still spawns an unguarded `Task` (B3). Verified: TechnicalOverlay 32 unit tests in 6 suites + 8 XCTest UI tests, `** TEST SUCCEEDED **`; `tuist build TechnicalOverlay` succeeded; `tuist generate` for the four new files. |
| 2026-10-17 | **`print` is gone from both modules: the app and the chunk pipeline log through `os.Logger`.** A diagnostic line is now filterable instead of being an unlabelled line in the console. App: `org.cjas.technical-overlay`, with `data` (autosave, the `.tojson` pickers, decode), `media` (security scope, size probe, preview composition, the movie picker) and `export` (stitch progress, failures). Module: `org.cjas.technical-overlay.video-processor`, with `chunk-pipeline` (the per-chunk trace) and `composition` (the three export-setup failures). Failures are `.error`, which persists; routine events and the trace are `.debug`, so they stream while debugging and are not stored — the trace is loud by design and now costs nothing when nobody is watching. `Trace.isEnabled` is the pipeline's single switch. **Isolation note:** the trace's arguments are the module's MainActor-default formatting helpers (`traceDescription`, `Chunk.hasOverlay`, `traceLabel`, …), so marking `Trace.log` `nonisolated` to match a `nonisolated` logger broke every `ChunkQueue` call site — 'main actor-isolated property … can not be referenced on a nonisolated actor instance'. The sink changed; the isolation did not. Verified: VideoProcessor 70/70 in 8 suites, TechnicalOverlay 32 unit tests in 6 suites + 8 XCTest tests (the UI suites included), `tuist build TechnicalOverlay` succeeded. |
| 2026-10-17 | **`VideoProcessor.swift` was split into the six types it held — no behaviour change.** The file was 760 lines carrying `Slide`, `Metrics`, the preview recipe and compositor, `VideoComposer`, `ExportSession`, the chunk types, both pipeline protocols, the region planner and the queue actor; the module doc's own file map described it as "Everything". It is now `Slide.swift` (the slide and `Metrics.transitionTime`), `VideoComposer.swift` (the preview recipe, `PreviewVideoCompositor` and `VideoComposer`, which stay together because the recipe's lock box is file-private to its writer), `ExportSession.swift` (as an extension, so `VideoComposer.ExportSession` keeps its name), `Chunk.swift` (identity, type, state, `Chunk` and the two seams), `RegionPlan.swift` (`generateRegions` / `diffRegionsIntoChunks`) and `ChunkQueue.swift`. Every declaration moved verbatim: same access levels, same docs, same order inside each file. Verified: VideoProcessor 70/70 in 8 suites (real render/stitch exports included) and TechnicalOverlay 38 unit + 8 XCTest, `tuist build TechnicalOverlay` succeeded. |
| 2026-10-17 | **`OverlayData` was split from the four jobs it was doing.** The model carried the document, the `UserDefaults` autosave, the `(size, mode)` image cache, the slide plan, the timing cascade and four `String` conversions, all in one 394-line `@Observable` class — so render state sat on the observation surface (mutating the cache invalidated views for nothing) and persistence could not be reasoned about without the rest. Now: `OverlayData.swift` is the document and its hash, `OverlayTimeline.swift` is `setIntroTime`/`setElementTime` and the shared `shiftTimes`, `SlideFactory.swift` is `slidePlan()` (modes and start times, with a `.none` fade-out after each group) plus the `SlideFactory` that renders and caches them, `OverlayStore.swift` is the `"state"` key with `save()`/`load()` as forwarders, and `ScoreFormatting.swift` is hundredths ↔ text. One behaviour change, on purpose: the factory keeps only the modes the current plan uses, so the cache prunes itself instead of being emptied when the editor closes — `ScoringListView` no longer calls `clearCache()` and an editing session can no longer grow the cache at all. Verified: TechnicalOverlay 38 unit tests in 7 suites + 8 XCTest, `tuist build TechnicalOverlay` succeeded. |
| 2026-10-17 | **`generateSlides()` passes supersede each other.** Five call sites — the first `onAppear`, the file setter, a timestamp edit, the overlay-look toggle and Clear Slides — each spawned its own unstructured `Task`, and they interleave at every `await`. The winner was whichever *finished* last, not whichever was *called* last: a slow pass could install an older document's preview and enqueue its chunk plan on top of a newer pass that had already finished. Each pass now takes a number, and every `await` is followed by a check that the pass is still the latest, so a superseded one discards its player item and its plan instead of publishing them. A counter rather than `Task.cancel()`: the awaits are AVFoundation loads and a seek, which a cancelled task cannot actually abort, so the work would still complete and its result would still have to be discarded. Not covered by a test — forcing the interleave deterministically needs injectable delays at each await; verified by build, the existing suites and the check after every suspension point. |
| 2026-10-17 | **A replaced video's pipeline is shut down, and its chunks are deleted.** `RenderPipeline.reset()` dropped its `ChunkQueue` reference on a video swap, which stopped nothing: the old queue's drain task kept exporting the old asset, and `DefaultChunkRenderer` wrote `chunk_<uuid>.mov` straight into `FileManager.default.temporaryDirectory` — no directory of its own, no cleanup path, so every swap left renders running and files behind until the OS pruned tmp. Now `ChunkQueue.shutdown()` cancels the drain, **awaits it** (nothing can still be writing when the files go) and deletes every file its chunks point at; `DefaultChunkRenderer` writes into a per-queue `chunks/<uuid>/` directory that `reset()` removes after the shutdown, so two pipelines cannot collide. One related leak fixed in the same place: a late progress report from the old queue could flip the indicator back to yellow after a swap, so the pipeline now ignores reports from any queue that is not its current one. Tests: `ChunkQueueShutdownTests` (+2) — shutdown deletes the rendered files, and a shutdown that lands mid-render still leaves nothing behind — **VideoProcessor 72/72 in 9 suites**. |
| 2026-10-17 | **One walk for the preview and the plan.** The preview compositor answered "which overlay owns this frame" by walking *back* from the playhead (last slide with `startTime <= time`, dissolve for `transitionTime`); `generateRegions` answered it by sweeping *forward* with a cursor that jumps to the end of each transition. Those agree only while slides are at least `transitionTime` apart. At 10.0 and 10.3 with 0.75 s dissolves, the preview was already dissolving slide 1 → 2 at 10.31 while the export was still fading slide 1 in — the same frame, two different pictures, and only the export's reached the file. Resolved by making the export's sweep the single definition: `overlaySpans()` produces the contiguous plan (sorted, clipped to the video, noOverlay gaps / transition windows / constant holds), `generateRegions()` is now a map over it that adds `ContentIdentity`, and the preview recipe carries the same spans, resolved per frame by `[OverlaySpan].content(at:transitionTime:)`. Decided, on the user's direction, that **a transition always runs its full `transitionTime`**: crowded slides do not shorten a dissolve that is already running — the next one starts when it ends, later than that slide's own start time. The alternative (compressing dissolves into the gap) was rejected because it would make an overlay's timing depend on how close its neighbour happens to be. Drawing still goes through `OverlayComposite`, so the preview and the chunk renderer run one program on one plan. Tests: `OverlaySpanTests` (+5) — the two paths' time ranges and identities come from the same walk, crowded slides get full-length transitions and stay contiguous, and the 2.6 s frame resolves to the first slide's dissolve at 0.8 rather than the second slide — **VideoProcessor 77/77 in 10 suites**. |
| 2026-10-17 | **All compiler warnings resolved (73 → 0 in a clean build).** The bulk were `main actor-isolated … nonisolated context` diagnostics inside `ChunkQueue`: every target is MainActor by default, so the plan's value types, the pure transforms and the trace/log helpers were MainActor-only and the queue's `actor` could not read them without a hop. Fixed with `nonisolated` on those declarations — and on their extensions, which need their own marker — while `SWIFT_DEFAULT_ACTOR_ISOLATION` stays. Also gone: an unused `guard` binding, a never-failing `renderer != nil` test assertion, and a weak-`self` var capture read from a `Task`. |

| 2026-10-18 | **The abbreviation spec now covers pairs and ice dance, and the two expansion documents are one.** The rules for the 66 pairs and 121 ice-dance abbreviations were designed the way the singles were — census the fixtures first, prototype the classifier, freeze the numbers — over 182 pairs rows (the five committed pairs pages) and 247 dance rows (thirteen Challenge Cup 2026 pages): `Throw 3 Salchow`, `1 Lift 4`, `3 Twist Lift 3`, death spirals, pivot figures, pair and dance spins, dance lifts, twizzle sets, dance step sequences, `CDE`, and the three published pattern-dance shapes. Two findings decide how those codes are read: `RPD<n>` is a dance with *n sequences*, not a dance number (IJS Parameters), and `1WW`/`2WW` are slot codes whose ISU labels still read "Rhumba/Quickstep 1st Sequence" — so they render `Pattern Dance <n>` instead of claiming the Westminster Waltz. The eight naming decisions are §8 of the document. `abbreviation-expansion-pairs-dance.md` is deleted and `abbreviation-expansion.md` is no longer titled "(Singles)"; the singles sections kept their numbers, so every `§` citation in the Swift comments and the other docs still resolves. Status: singles implemented, pairs and ice dance specified only. Verified: a prototype of the new rules classifies 429/429 pairs and dance rows with zero passthrough and still 535/535 singles rows (all 24 singles examples byte-identical), and every count in the document and all 68 worked examples are that run's output; the shipped `ElementNameExpander` was run over the same 429 rows first, to show that it mangles nothing today. |
| 2026-10-21 | **A timeline row is one line and 44 pt, and its stamp control is a stopwatch glyph.** The row stacked the time over a bordered "Start Now" button in a `VStack`, so each row measured **82.8 pt of pitch for 20.3 pt of text**: 3.6 of 9 rows were visible in the 303.3 pt list a loaded video leaves, and with no video loaded the button was hidden but still reserved its 34.3 pt, so a single-line row was 82.7 pt of mostly nothing. The control is now a `Label("Start now", systemImage: "stopwatch").labelStyle(.iconOnly)` on the same line as the time, the row is `Metrics.rowHeight = 44` (the minimum tap target), and the `Grid` became a `VStack` of `HStack` rows — the label flexes, the time and the glyph keep their width at the trailing edge. A stopwatch rather than a play glyph because the control stamps the playhead's *current* time and starts no playback; `play.fill` sits in AVKit's transport controls two rows away. Icon-only keeps the verb in the accessibility label (plus a hint), since a glyph alone is what a VoiceOver user would otherwise hear as the control's name. Two corrections came from measuring the running app rather than the code: the `Grid`'s 8 pt vertical spacing on each side of every divider had inflated the pitch to 63 pt, and the flexible trailing column squeezed the label column enough to wrap `8: Ch Combination Spin 4`, which had fitted on one line before — hence the `Grid` → `VStack` change. Verified: `tuist build TechnicalOverlay` succeeded; row pitch measured from the dividers in the running app is 44, 44, 45, 44, 44, 45, 44, 44 pt (was 82.8), and all ten rows now fit the list that showed 7.4; `#Preview("With a playhead")` rendered on the iPhone 18 Pro simulator shows the glyph right-aligned, centred, and one straight column. No test covers the view. |

| 2026-10-18 | **Pairs and ice-dance expansion implemented** (`ElementNameExpander+Pairs.swift`, `ElementNameExpander+Dance.swift`). The tables from the spec's §4.10–§4.12 — throws, twist lifts, pair lifts (groups 1–5), death spirals, pivot figures, the pairs and dance spins folded into the spin table, dance lifts, twizzle sets, step sequences, one-foot turns, the solo-dance and senior codes, and the three pattern-dance shapes — plus the partner-half recombination in `displayName(for:)`. Two implementation points the spec did not anticipate: the dance branch must be offered the token **with and without** the shared trailing-marker strip, because `SpEe`/`CrEe`/`IBEe` end in `e` and the singles rule eats it before anything looks at them; and the recombined name is built in `displayName` rather than per token, since it needs the neighbouring token. Thirteen Challenge Cup 2026 dance pages committed as fixtures (`ChallengeCup-SEGMnnn.html`). Tests: `ElementNameExpanderTests` 17 → 31, **ProtocolParser 70/70 in 7 suites**, with a zero-passthrough sweep per vocabulary (535 / 182 / 247 rows, and the distinct-abbreviation counts 187 / 66 / 121 asserted). App builds and its suite passes unchanged (38 unit + 8 XCTest), since singles names did not move. |
| 2026-11-01 | **A second technical pane: `Isu2026TechnicalPaneView`, chosen by a style menu.** The broadcast 2026 graphic reads top-down — skater and running total, element name, base value with bonus, GOE in a green/red cell, then the element boxes — which is the classic pane's order with the total first and the boxes last, and it carries no black inset boxes, no rounded corners and none of the blue/pink/grey fills. Rather than parameterize the classic pane's five components, the style became a field of `TechnicalViewModel` (`TechnicalPaneStyle`: `classic` | `isu2026`) and `VideoOverlay` holds both panes, showing the one the style names: the mode is the slide cache key and a chunk's content identity, so a style change has to produce a different mode anyway, and one enum in the view model makes that automatic. `ElementBoxView.Style` and `ElementRowView(style:)` carry the only shared code whose rendering differs (palette; spacing and background), instead of duplicating the box row. Device preference on the element-box toggle's terms (`OverlayPreferences.technicalPaneStyle`, key `"technicalPaneStyle"`, absent or unrecognised = classic), seeded at launch and written by the new **Style** menu in `MainView`'s config row. Colours and proportions were measured off the user's reference frame (a photo of a broadcast screen): white rows, an element-name row ~13% darker, GOE/judge green `#2FA600` and red `#D50B0E`, boxes ~0.7 of their row's height with a gap of 0.6 of a box, panel aspect ~2.3. The leader row, flag and `TECHNICAL SCORE` header are deliberately not drawn; **the leader row's styling was then reused for the pane's own first row** on the user's instruction — blue behind white text, the running total in its own band behind a rule, overhanging the block by 15% of the pane's width, with only the chips' own hairline between it and the block. Its text was then set to **one point larger** than the block's with the row's height **proportional to that text** — a row's text is `Metrics.isu2026FontPercent` of its height, so the row is taller by exactly the height one more point needs, and the band ended up a fraction taller than the rows below rather than 1.4× them. The same pass renamed the fourth row's label to `EXECUTION:` (the graphic's word), dropped the box row's background, so the boxes alone sit over the video with a mid-gray outline making an empty slot read on a light frame, and packed the boxes from the row's left inset with a hairline between them instead of sharing the row's width evenly. Tests: `LayoutEngine` 5 → 14 (row order, the name row's leader styling and separation, the block's value-column alignment, execution-cell sign, box-row hiding and layout — including that the chips are packed with a hairline between them — and the overlay picking its pane by style), app unit suite 38 → 46 (`TechnicalPaneStylePreferenceTests`: default, persistence, an unknown stored value, launch seeding, not in the document, `renderingHash`, and `slidePlan()` drawing elements in the stored style). |

| 2026-11-02 | **`Classic 2`: the classic pane's rows reordered, not a third design.** `IsuTechnicalPaneView` gained `RowOrder` — `boxesFirst` (the original: boxes, name, score, total) and `totalFirst` (total, name, score, boxes) — so the two orders share one layout, the same four components, palette, `Metrics`, pane frame and one-border row gaps; only the frames and which row takes the outer corners depend on the order. `VideoOverlay` holds one pane per style and shows the one the mode names, and the style is the view model's, like the other two. The style case is `classic2`, titled *Classic 2* in the menu; its stored value is `"classic2"`, and an unrecognised value still reads as classic. Tests: `LayoutEngine` 14 → 17 (the order, row sizes identical to the classic pane's, the box row hidden at the bottom), app unit suite 46 → 47 (the stored value and the slide's style). |
| 2026-11-02 | **Protocol PDF import.** `ProtocolParser` reads an ISU FS Manager `…_JudgesDetailsperSkater.pdf` as well as an ijsLive HTML page: the importer sniffs `%PDF-` in the bytes it fetched, so a pasted address works for either kind and nothing inspects the URL (module doc §2.3, §4.8, §7.3). New: `PDFTextLayout` (CoreGraphics `CGPDFScanner`) rebuilds each table row from the position of every text run; `ProtocolPDFParser` reads skater identity rows and element rows out of those rows into the existing model, with the same hundredths conversion and the same `base + goe + bonus == panel` check; `ProtocolSkater`'s matcher moved to `ProtocolSegment` and is shared. `ProtocolFetching` became byte-oriented (`fetchData`, plus `fetchText` for the HTML path) because a body is only known to be HTML or a PDF after it arrives. Two fixtures committed — the 2026 Grand Prix Canada women's short program and the 2026 Cranberry Cup advanced novice men's, which carries the Bonus column: 20 skaters, 132 element rows, 0 invariant violations, 0 index gaps. ProtocolParser 70 → 84 tests in 8 suites. |
| 2026-11-02 | **The PDF's amount-less bonus marker is stripped from the name.** The FS Manager PDF prints `3Tb`, `2Ab`, `3Lzb` — the marker without its amount, the value living only in the Bonus column — where the HTML pages print `3Tb1` and `b0.5`. The expansion only knew the amount form, so those abbreviations were returned verbatim and reached `ElementData.name` as "3Tb" instead of "3 Toeloop": 5 of the PDFs' 46 abbreviations. A trailing lowercase `b` is a marker too now. The uppercase level `B` (`CCoSpBV`, `1LiB`, `StSqB`) is untouched, and no abbreviation in the 374 distinct the HTML fixtures hold has a lowercase `b` at all, so the rule cannot collide with a code. Tests: +2 — the marker itself, guarded by the level cases, and a zero-passthrough sweep over the PDFs' 132 rows; ProtocolParser 84 → 86 in 8 suites. |
| 2026-11-04 | **A protocol can be imported from a file, not only an address.** `ScoringListView` gained **Import From File** beside **Import Protocol**, opening the system picker filtered to `.html` and `.pdf`; the picked file is read once inside the picker's access scope and handed to the same importer, which still decides HTML-vs-PDF from the bytes, so an extension never has to be trusted. `URLSessionProtocolFetcher` now reads a `file:` URL from disk, which is what lets a *leaderboard* page saved to disk follow its relative judge-detail link to the sibling file saved beside it — without that branch the link would resolve to a file URL nothing could read. The import and the hand-entry buttons became two rows: four labels do not fit one row on a phone in portrait, and a squeezed `HStack` wraps labels onto two lines rather than overflowing (the failure measured in the *Clear Slides* row above) — verified in a rendered screenshot, with a UI-test height assertion so a wrap fails the suite. Tests: ProtocolParser +1 (a saved page directory served through the production fetcher), app +5 unit (saved detail page, saved leaderboard page beside its detail page, PDF bytes at a `.html` filename, an unreadable file, the name guard on the file path) and +1 UI (the picker presents instead of the address prompt) — **87/87 in 8 suites** and **52 unit + 9 XCTest**. |

**2026-11-01 — why a second pane instead of a style flag on the existing one.** The two graphics
differ in more than colour: their rows are in a different order, five instead of four, flush instead
of bordered and rounded, with the box row at the bottom instead of the top. A style flag threaded
through `IsuTechnicalPaneView`'s layout would have made every row's frame conditional on it, and the
classic pane is the one that has to stay pixel-identical — it is what every existing `.tojson` and
every already-exported video was made with. So the 2026 look is a new view with its own layout, and
the only thing shared is the part where the *data* is the same: the box row (`ElementRowView`'s
geometry plus `ElementBoxView`'s palette) and the `LabelBoxView` rig every row is drawn from.

**Why the style lives in the view model.** A `VideoOverlay.Mode` is the slide cache key and a chunk's
content identity, and slide and chunk reuse is what makes a timing edit cheap. Two slides that look
different must not hash equal, so anything that changes pixels has to be a field of the mode —
`showsElementBox` set that precedent, and the style follows it. The alternative, keeping the style on
the view or in a global, would let the renderer cache the old look.

**The boxes are a strip of chips, not a grid of slots.** They are as tall as the row allows (~0.7 of
it, as in the graphic) and packed from the left with a hairline between them, so the row reads as one
strip that grows as the program goes on. An earlier pass shared the row's width evenly among them, which
spread eight boxes across the pane with gaps wider than the boxes themselves — no longer the graphic's
look. They now only shrink, and their gaps only widen, when that many boxes would not fit the row's
width. The strip therefore does not span the pane: the space to its right stays clear, which is what a
transparent row makes free.

**The classic pane's order is a choice, not a property of the design.** Its two variants differ only in
where the box row sits, so they are one class with a `RowOrder` rather than two views: every row's
styling is identical, and a duplicated layout is what would let the pair drift apart on the next
tweak — the same argument that kept the ISU 2026 pane a view of its own, applied in the other
direction. The outer-corner assignment moves with the order (the top row takes the top corners, the
bottom row the bottom ones), and that is the only conditional code in `layoutSubviews`.

**The rows are flush, so the white block is one surface.** In the graphic the base-value row and the
execution row are both white and touch, so they read as one block broken only by the green/red cell.
Drawing the classic pane's borders between them would turn that block into two striped rows.

**The name row is dressed as the leader row and deliberately breaks the block.** In the graphic the
skater's row is the *scoreboard's* row — blue, white text, the score behind its own rule, taller than
the technical block and wider than it. Reusing that styling for the pane's first row is what makes the
pane read as part of the same broadcast, and the overhang is what marks it as a headline rather than the
first of five equal rows. Its height follows its text rather than being a chosen multiple: the text is
one point larger than the block's and the row is taller by the height that point needs
(`Metrics.isu2026NameRowExtraHeight`), so the band is a fraction taller rather than a banner. The gap
under the band is the chips' hairline, so the pane's only large space is the one around the whole block.
An earlier pass made the band 1.4× the block's rows for a proportionally larger font; two intermediate
passes set the font equal to the block's and then scaled it in a taller row, both of which that
proportional rule subsumes — `LabelBoxView.fontScale`, which existed only for the middle one, is
gone. Consequence: the running total does **not** share the value column
the base value and execution mark use, because the row is wider; the block's two values still line up
with each other.

**The box row has no background, so the boxes must carry their own definition.** With the row
transparent, an empty slot's white fill disappears against bright ice, which is why the outline is a
mid-gray rather than the near-white the filled row allowed. The filled slots (green/red) are unchanged.

**Verified.** `LayoutEngine` 14/14 and the app suite (46 unit + 8 XCTest); both panes rasterized at
1280×720 and compared against the reference frame by eye — order, colours, the leader-styled name row
with its rule, larger type, overhang and gap, the block's value column, and the red cell for a negative
GOE. The empty slots were rendered over both a mid-grey and a near-white ground to check the outline
holds up on a bright frame.

## Compiler warnings (2026-10-17)

A clean `build-for-testing` of `TechnicalOverlay-Workspace` emitted **73 unique warnings** (140 log
lines). 63 of them were in `ChunkQueue.swift`, all one cause: the queue is an `actor`, every target
defaults to MainActor isolation (`Project.swift` `baseSettings`), so the plan's value types, the pure
transforms and the trace helpers were MainActor-only and the actor had to hop — or could not — for
every predicate and trace line.

- **Fixed by marking declaration intent, not by relaxing the build settings:** `nonisolated` on
  `Chunk`, `ChunkState`, `ChunkType`, `ContentIdentity`, `ChunkRegion`, `OverlaySpan`,
  `OverlayContent`, `Slide`, `Metrics`, `overlaySpans`/`generateRegions`/`diffRegionsIntoChunks`,
  the `Trace`/`TraceTimer`/`Log` helpers and their extensions, the `ProtocolParser` model types, and
  `CornerDirection`. `SWIFT_DEFAULT_ACTOR_ISOLATION` is untouched — dropping it is what broke
  `VideoOverlay.render` before (see *Project infrastructure*).
- **`nonisolated` on a type does not reach its extensions.** `extension Chunk`, `extension
  CMTimeRange`, `extension Array where Element == ChunkRegion` each needed their own `nonisolated`;
  without it they stay MainActor-isolated and the warnings come back. Verified with a
  `swiftc -typecheck -swift-version 5 -default-isolation MainActor` probe before editing the module.
- **Three unrelated warnings, each a real leftover:** `RenderPipeline`'s progress callback read a
  weak-`self` **var** capture from inside a `Task` (it now binds a strong `let` first, outside the
  task); `ExportCoordinator` bound `queue` in a `guard` and never used it; and
  `DefaultChunkRendererTests` asserted `renderer != nil` on a non-optional type — a check that could
  never fail. The test double `ProgressRecorder` became `nonisolated` so the queue's `@Sendable`
  callback can call it.
- **Measured after:** the same clean build reports **0** compiler warnings and 0 errors; the only
  remaining `warning:` lines are the `appintentsmetadataprocessor` tool notices ("Metadata extraction
  skipped, no AppIntents.framework dependency found"), which are not source warnings.
- **Deliberately left:** `ChunkRendererProtocol` and `StitcherProtocol` are still MainActor-isolated,
  so `DefaultChunkRenderer.render` hops to the main actor. Making them `nonisolated` changes which
  executor renders and stitches run on — a behavioural decision, not a warning fix.

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

**Pairs and ice dance specified, documents merged (2026-10-18).** Designed the same way as singles:
census the fixtures, prototype the classifier over every row, then freeze the counts as tests. The
census is 182 pairs rows / 66 abbreviations (the five committed pairs pages) and 247 dance rows / 121
abbreviations (thirteen pages of the Challenge Cup 2026 protocol set). The prototype classifies
**429/429** rows with zero verbatim passthrough, and the extended rule set still classifies 535/535
singles rows and reproduces all 24 singles examples, including the `V` spin suffix — the new branches
are additive, which is what test 29 in the document's §9 guards.

Two code-reading findings came out of it. `RPD<n>`'s digit is the number of **sequences** in the
required pattern dance, not a dance number (every two-sequence row in `IJS Parameters` is annotated
`[use RPD2]`, three-sequence `RPD3`, four-sequence `RPD4`), so no dance name is inferable and the
digit is dropped from the display. And `1WW`/`2WW` — the junior rhythm dance's two pattern elements —
are *slot* codes: the ISU 2026-27 list labels them "PD Element Rhumba 1st Sequence" and "PD Element
Quickstep 1st Sequence", which are 2025-26's `1RH`/`1QS` labels carried over, so rendering them as
the Westminster Waltz would be a false claim. Base values settle the string's shape: `1WWB`, `1WW1`
and `1WW2` are one element at three levels (2.50 / 3.50 / 4.00), so the leading digit is the slot and
the trailing one the level.

Names come from the ISU abbreviation list for 2026-27, and the published pages win where the list
disagrees with them (`SlLi` against its `SiLi`, `ChSl` against its `ChSI`). The decisions that are
not derivable — `Throw 3 Salchow` word order, `1 Lift 4`, `3 Twist Lift 3`, `Choreo Char Step
Sequence` against `Choreo Step Sequence`, and recombining a two-partner element into one name
(`Sequential Twizzles W 4 / M 4`) instead of joining two — were taken by the user before
implementation and are recorded in the document's §8; their effect is that the longest names are 50
characters for singles, 40 for dance and 31 for pairs, all under the overlay's shrink-to-fit regime.

The two documents were merged into one rather than kept side by side. The singles document's section
numbers were **kept exactly** (§4.2–§4.9 singles, §4.10–§4.12 pairs and dance), because the Swift
comments and three other documents cite them by number — a renumbering would have silently re-pointed
dozens of citations at the wrong rule.

**Implementation (2026-10-18).** `ElementNameExpander+Pairs.swift` and `ElementNameExpander+Dance.swift`
hold the tables; `displayName(for:)` recombines partner halves before joining, because that needs the
neighbouring token and a per-token function cannot see it. The classifier order is the spec's: sequence
and choreographic, spins (now including `PSp`/`PCoSp`/`DSp`), pairs, dance, pattern dance, and the jump
rule last, which is what keeps `3STh` a throw and `3Tw3` a twist lift rather than a Salchow and a
Toeloop. `ElementNameExpanderTests` went from 17 tests to 31 and **ProtocolParser from 56/56 to 70/70
in 7 suites**; each vocabulary has its own sweep (535 / 182 / 247 rows, zero passthrough) and its
distinct-abbreviation count asserted, so a future code that falls out of the classifier fails a test
instead of importing silently as its own abbreviation. The app's suite did not change: singles names
did not move, which is the evidence that the new branches are additive. No compiler warnings, and the
two new files needed `tuist generate` because sources are globbed (`AGENTS.md`).

**Left unverified.** The dance-only markers `S`, `>` and `ExEI`, and a reduced level on a
pattern-dance code, appear in no page of this event; `PSt`, `SoTw` and the four solo-dance edge
elements have no page at all, so their shapes and names are the ISU list's; and the on-screen fit of
the 40- and 50-character names is still computed from `Metrics`, not measured.

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

**Not verified.** Pairs and ice-dance rules — *superseded 2026-10-18, above: those rules and their
sweeps now exist*; the `q`/`V` semantics (taken from ISU communications, not measured — they only
decide what gets ignored, never the values); and the on-screen fit of the longest expansions, which
the module doc computes from `Metrics` rather than measuring on a rendered overlay.

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

## Protocol PDF

**Why not PDFKit (2026-11-02).** The obvious reader — `PDFKit` — cannot extract these tables. On the
Grand Prix Canada document `PDFPage.string` returns the element block column-major: all seven
abbreviations (`1 3A 2 3Fq 3 FCSp4 4 3Lz+3T …`), then their base values, then their GOE marks, then the
per-judge columns, then the panel scores — the runs are drawn per cell, not per line, so document
order is not reading order. Rebuilding rows from PDFKit's geometry does not rescue it either: its
per-character bounds are wrong on this producer's files. One glyph of `Name` measures 193 pt against a
6.7 pt font, and characters belonging to two visually distinct lines share a baseline to within 3 pt,
so there is no y-tolerance that separates rows.

`CGPDFScanner` (CoreGraphics) provides the one reliable fact: the text matrix each run was drawn
with, and from it the run's true origin. `PDFTextLayout` implements the text-extraction subset of the
imaging model — the graphics-state stack, the text matrices, the four show operators, and each font's
`/ToUnicode` CMap — then groups runs by baseline. Two details are properties of this producer: the
CMap's entries are separated by the **literal characters** `\r\n` (PDFsharp writes them escaped, so
splitting on line breaks finds exactly one entry), and the header labels `Info` and `Ref.` are drawn
inside a rotated `cm`, so a reader that ignores the CTM places them at y ≈ 5 of a 2536-tall page.

**What the round trip measured.** Both documents parsed completely: 12 skaters / 84 element rows and 8
skaters / 48 rows, `base + goe + bonus == panel` on **132 of 132** rows, element indices contiguous
1…N in every block. The row grammar is the one that held for both shapes: the identity row is
right-anchored on its four scores, and an element row's panel score is its last decimal cell, with
base, GOE and — when the document has a bonus column and the row carries one — bonus before it. 21 of
the 48 advanced-novice rows carry a bonus; a row without one prints no cell at all.

**A second difference the PDF forced.** The bonus marker is printed with its amount on the HTML pages
(`3Tb1`, `b0.5`) and without it on the PDF (`3Tb`, `2Ab`), the amount living only in the Bonus column.
The expansion had been written against the HTML form and returned the PDF's tokens verbatim, so the
imported name was `3Tb` for 5 of the 46 abbreviations. A trailing lowercase `b` is now a marker; the
level `B` is uppercase, and none of the 374 HTML abbreviations ends in a lowercase `b`.

**A spec correction the implementation forced.** The first cut read the event and segment titles from
"the lines above the first skater", which is wrong: the *column headers* sit between the segment line
and the first skater, so the last line before that skater is `Number | Score | Deductions`. The titles
are the title line's neighbours — the segment directly under `JUDGES DETAILS PER SKATER`, the event
directly above it when the document has one (module doc §4.9).

**Isolation.** `CGPDFOperatorTable` callbacks are C function pointers: they cannot capture context, and
one cannot be formed from a reference to a `MainActor`-isolated function. Each operator is therefore
registered with a `nonisolated` file-scope function that forwards to a single dispatcher, and the
page's collector arrives through the callback's opaque `info` pointer.

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
