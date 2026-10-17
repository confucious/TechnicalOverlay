# CLEANUP.md — structural review backlog

A ranked list of proposed work from an audit of the whole tree for **modularity, isolation, code
repetition and readability**. Every item names the file and line it lives at and what to create,
move or delete — no "consider refactoring".

**How to use this file:** delete an item when it lands; this list should shrink, never accumulate.
IDs are never reused, so a gap in the numbering is finished work (B1, R3 and Y4 are done). It is a
backlog, not a design doc: rationale for anything that ships goes in `docs/HISTORY.md` per
`AGENTS.md` → Documentation, and `docs/ARCHITECTURE.md` stays current-state only.

**Tags**

- **[generate]** — the fix moves code into new files, so it needs `tuist generate` afterwards
  (sources are globbed from `Project.swift`; a new file is not in the workspace until then).
- **verified** — the behaviour was reproduced with a throwaway probe test, reverted afterwards.
- **read** — the claim comes from reading the code, not from running it.

Accepted as designed, not to be re-litigated: two `AVURLAsset`s over one file, the hand-written
`PreviewVideoCompositor`, and `Metrics.transitionTime = 0.75` — `docs/HISTORY.md` → *Playhead
freeze*. The `ProtocolParser` module is the model the rest of the tree should follow: pure parsing
behind a `ProtocolFetching` IO seam, an injectable `ElementNameTranslating`, value types only.

---

## Blocking

### B2. Preview and export disagree when two slides are closer than `transitionTime` (read)

The preview walks back from the playhead — last slide with `startTime <= time`, dissolve if
`diff <= transitionTime` (`VideoProcessor.swift:125-142`). `generateRegions` instead advances
`cursor` to `slideStart + transitionTime` before considering the next slide (`581-588`). For slides
at 10.0 and 10.3 the preview dissolves at 10.3 while the export is still holding slide 1.

**Fix:** derive the region plan from the same slide-walk the compositor uses, so "which slide owns
this frame" has one definition. At minimum, assert the invariant in a test both paths share.

### B3. `generateSlides()` is an unguarded unstructured `Task` per call (read)

`MainView.swift:135-194`, called from `onAppear` (`584-586`), `assetUrl.didSet` (`73`),
`timeUpdated` (`549-551`), `clearSlides()` (`216`) and `setShowsElementBox` (`205`). Each call
spawns a task that interleaves at every `await`; the last writer of `self.videoComposer` and
`self.chunkQueue` is whichever finishes last, not whichever was called last, and a superseded run
can still `enqueue(slides:)` after a newer one.

**Fix:** keep the handle (`renderTask?.cancel()`) or a generation counter checked after each
`await`, keyed by `assetUrl`.

### B4. Swapping videos leaks the old pipeline and its chunk files (read)

`assetUrl.willSet` nils `chunkQueue` (`MainView.swift:55-64`) but the old queue's `drainTask` keeps
exporting the old asset and nothing deletes its output. `DefaultChunkRenderer` writes
`chunk_<uuid>.mov` straight into `FileManager.default.temporaryDirectory` (`MainView.swift:173`),
with no directory of its own and no cleanup path.

**Fix:** `ChunkQueue.shutdown()` — cancel the drain, delete its outputs — called from `willSet`;
give the renderer a `chunks/<uuid>/` subdirectory so cleanup is one `removeItem`.

---

## Modularity / isolation

### M1. `VideoProcessor.swift` is one 908-line file holding ten public types [generate]

`Slide`, `Metrics`, `PreviewRecipe`, `PreviewVideoCompositor`, `VideoComposer`, `ExportSession`,
`ContentIdentity`, `ChunkType`, `ChunkState`, `Chunk`, both protocols, `ChunkRegion`,
`generateRegions`, `diffRegionsIntoChunks`, `ChunkQueueProgress`, `ChunkQueue` — the module doc's
own file map calls it "Everything" (`docs/architecture/video-processor.md:11`).

**Fix:** split along the seams that already exist: `Slide`+`Metrics`, `VideoComposer` (preview),
`Chunk`/`ChunkType`/`ChunkState`/`ContentIdentity`/`ChunkRegion`, `RegionPlan`
(`generateRegions`, `diffRegionsIntoChunks`), `ChunkQueue`, `ExportSession`. Pure moves.

### M2. `VideoComposer` is a preview-state holder *and* a stateless composition factory [generate]

`DefaultChunkRenderer` builds `VideoComposer(asset:slides: [])` twice (`DefaultChunkRenderer.swift:121-131`)
purely to reach `setupComposition(overlay:)` / `setupComposition(from:to:transitionStart:)`. The
chunk path never uses `slides` — the export pipeline depends on the preview object for a static
function.

**Fix:** a `ChunkComposition` struct (asset in, `AVVideoComposition` out) owning the two CIImage
builders; `DefaultChunkRenderer` depends on it, and `VideoComposer` keeps only the preview recipe.

### M3. `MainView.ViewModel` carries five responsibilities in a 649-line view file [generate]

Security scoping (`MainView.swift:55-75`), asset probing (`109-133`), slide generation and
player-item swap (`135-194`), chunk-queue lifecycle, export orchestration and progress phases
(`224-301`).

**Fix:** extract `MainViewModel` into its own file (tests already construct it —
`ClearSlidesTests.swift:29` — so this is a rename there), then split into `AssetSession`,
`RenderPipeline`, `ExportCoordinator`.

### M4. `OverlayData` is a god object [generate]

394 lines carrying the model, `Codable` keys, `UserDefaults` persistence (`53-77`), the image cache
(`155-163`), slide generation (`165-240`), the timing cascade (`85-128`), plus `IntroductionData`,
`ElementData` and four `String` extensions.

**Fix:** model / `OverlayTimeline` (cascade) / `SlideFactory` (cache + `makeSlides`) /
`OverlayStore` (the `"state"` key) / `ScoreFormatting`. `imageCache` on an `@Observable` model means
render-state mutation invalidates views for nothing — it belongs in the factory.

### M5. `deinit { assetUrl = nil }` relies on observers firing during deinit

`MainView.swift:105-107` releases the security scope by assigning through `willSet`/`didSet`, which
also nils `player` and `chunkQueue` mid-teardown.

**Fix:** an explicit `close()`; leave `deinit` empty or asserting.

---

## Repetition

### R1. Three near-identical `setupExport` overloads

`VideoProcessor.swift:194`, `310`, `348` — ~90 lines of the same compatibility check → session
creation → `try/catch { print("export failed") }`.

**Fix:** one private `exportSession(composition:)` plus three-line wrappers.

### R2. The dissolve program exists twice

`PreviewVideoCompositor.composited` (`VideoProcessor.swift:125-142`) and
`setupComposition(from:to:transitionStart:)` (`273-304`). The docs assert they match
(`video-processor.md:53`); nothing enforces it, so they can drift silently.

**Fix:** one `nonisolated func overlay(from:to:at:transitionTime:over:)`, used by both.

### R4. The timing cascade is written twice

`setIntroTime` (`OverlayData.swift:85-110`) vs `setElementTime` (`112-128`) differ only in what
happens to an unset sibling.

**Fix:** one generic shift over `[TimeInterval?]` with a write-back closure; two recursive walks
become loops.

### R5. LayoutEngine repeats the same rig five times

`IsuLowerThirdView.UpperLineView` (`100-128`) and `LowerLineView` (`130-203`), `ElementNameView`
(`37-48`), `ElementScoreView` (`60-91`), `ProgramTotalView` (`59-80`): background view + label,
`inset = bounds.height * Metrics.borderPercent`, frame insets, font, `cornerConfiguration`. Ten
copies of `required init?(coder:) { fatalError }` as well.

**Fix:** a `LabelBoxView` (background + label, alignment, corner mask, weight) and a
`Metrics.inset(for:)` helper, so each row declares composition instead of arithmetic.

### R6. Test scaffolding duplicated across bundles' files

`makeTestAsset()` is verbatim identical in `DefaultChunkRendererTests.swift:19` and
`DefaultStitcherTests.swift:19`.

**Fix:** a shared `TestSupport.swift` in the `VideoProcessorTests` bundle.

---

## Readability

### Y1. Names that mislead

- `@State private var state = ViewModel()` (`MainView.swift:308`) makes every call site `state.x`.
- `QueueStatus` (`30-37`) uses `idle` for "everything rendered" next to a separate `noVideo`.

**Fix:** `model`, and a label per case that says what it means.

### Y2. Dead code the compiler still builds — delete, do not polish

- `ContentView.swift` (193 lines, hardcoded Scotty HSU data, no production path).
- `ElementBuilderView.swift` (37 lines, never wired in).
- `WriterInputs` (`DefaultStitcher.swift:212-218`) — unused.
- `ChunkRendererError` (`DefaultChunkRenderer.swift:27-45`) — never thrown; the renderer returns
  `nil` and traces.
- `ElementScoreView.GoeStyle` (`11-14`) — unused.
- `IsuLowerThirdView.secondaryText` (`44-53`) — the getter returns `("", "", "")`.
- `IsuLowerThirdView`'s seeded `"Scotty HSU"` label text (`113`).

### Y3. `print` is the logging channel

24 `print`s in the app target alone (`"saved"`, `"loaded"`, `"Invalidating cachedSize"`), none
prefixed, none filterable; `Trace.log` is the only structured one.

**Fix:** `os.Logger` subsystems for both, with one switch to silence the chunk pipeline.

### Y5. `makeSlides` duplicates its own fade-out block, and the copy lies

`OverlayData.swift:179-182` and `208-217` are the same block with the same comment, but the second
one fades out the *element* slides, not the intro slide.

**Fix:** one `appendFadeOut(after:)` helper.

### Y6. Doc drift: `ARCHITECTURE.md` §7 cites a `TODO.md` that is not in the repo

`docs/ARCHITECTURE.md:291` and `:300` point at `TODO.md` for the feature backlog; no such file is
tracked. Either add it or retarget those lines at this file.

---

## If you only do three things

1. **M2 + R2** — pull the CIImage composition builders and the dissolve function out of
   `VideoComposer`. One extraction removes the preview↔export coupling, the triple `setupExport`
   and the drift risk together.
2. **M3** — extract `MainViewModel`. It is the file that makes every other item here hard to test.
3. **B2** — one slide-walk shared by the preview and the plan, which is the natural follow-on to M2.

Everything left is a refactor with no user-visible behaviour; B2 is the only remaining one that can
produce a wrong export.
