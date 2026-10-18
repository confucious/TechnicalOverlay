# CLEANUP.md — structural review backlog

A ranked list of proposed work from an audit of the whole tree for **modularity, isolation, code
repetition and readability**. Every item names the file and line it lives at and what to create,
move or delete — no "consider refactoring".

**How to use this file:** delete an item when it lands; this list should shrink, never accumulate.
IDs are never reused, so a gap in the numbering is finished work (B1, B3, M1, M2, M3, M4, M5, R1, R2,
R3, R4, R5, R6, Y2, Y3, Y4 and Y5 are done). It is a backlog, not a design doc: rationale for anything that ships goes in `docs/HISTORY.md`
per `AGENTS.md` → Documentation, and `docs/ARCHITECTURE.md` stays current-state only.

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

### B4. Swapping videos leaks the old pipeline and its chunk files (read)

`MainViewModel.load()` (`MainViewModel.swift:70`) replaces the file, and `RenderPipeline.reset()`
(`RenderPipeline.swift:44`) drops the queue — but the old queue's `drainTask` keeps exporting the old
asset and nothing deletes its output. `DefaultChunkRenderer` writes `chunk_<uuid>.mov` straight into
`FileManager.default.temporaryDirectory` (`RenderPipeline.swift:73`), with no directory of its own and
no cleanup path.

**Fix:** `ChunkQueue.shutdown()` — cancel the drain, delete its outputs — called from `willSet`;
give the renderer a `chunks/<uuid>/` subdirectory so cleanup is one `removeItem`.

---

## Modularity / isolation

---

## Readability

### Y1. Names that mislead

- `RenderPipeline.Status` (`RenderPipeline.swift:20-28`) uses `idle` for "everything rendered" next to a
  separate `noVideo`, so the two states read as opposites of nothing.

**Fix:** a case label that says what it means (`rendered` rather than `idle`).

### Y6. Doc drift

- `docs/ARCHITECTURE.md:291` and `:300` point at a `TODO.md` for the feature backlog; no such file is
  tracked. Either add it or retarget those lines at this file.
- `AGENTS.md` names `MainView.ViewModel.assetUrl` (the pairing rule for security scopes, `:281`), and
  its source listing at `:124` omits `MainViewModel`/`AssetSession`/`RenderPipeline`/
  `ExportCoordinator`. Its Gotchas still describe `ContentView.swift` as a legacy prototype and
  `ElementBuilderView.swift` as a placeholder; both files are deleted. Its "Tracing the chunk
  pipeline" section still describes plain `print` output that "does not reach Console.app" — the
  pipeline now logs to `os.Logger` (`chunk-pipeline` category, `debug` level, `Trace.isEnabled`).
  Its module tree still lists `VideoProcessor.swift` (split into `Slide`/`VideoComposer`/
  `ExportSession`/`Chunk`/`RegionPlan`/`ChunkQueue`) and says the VideoProcessor test bundle has
  7 files (it has 8, with `TestSupport.swift`). Its Gotchas say `OverlayData` clears its
  `imageCache` and that `ScoringListView` clears the cache on `onDisappear` — the cache is now
  `SlideFactory`'s and prunes itself to the current plan. That file is a protected instruction
  file, so the corrections have to come from the user.

---

## If you only do three things

1. **B2** — one slide-walk shared by the preview and the plan. `OverlayComposite` unified how a frame
   is *drawn*; this unifies *which* slide owns it, which is the remaining way the preview and the
   export can disagree.
2. **B4** — give the queue a `shutdown()` and its chunks a directory of their own. `RenderPipeline`
   is now the one place that owns the queue, so it is a small change.
3. **Y1** — the one naming item left (`RenderPipeline.Status.idle` for "everything rendered"). Y6 is
   the doc drift, which only you can fix in `AGENTS.md`.

B2 is the only remaining item that can produce a wrong export; B4 is a lifecycle leak; Y1 and Y6 are
naming and doc clean-up.
