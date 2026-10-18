# CLEANUP.md — structural review backlog

A ranked list of proposed work from an audit of the whole tree for **modularity, isolation, code
repetition and readability**. Every item names the file and line it lives at and what to create,
move or delete — no "consider refactoring".

**How to use this file:** delete an item when it lands; this list should shrink, never accumulate.
IDs are never reused, so a gap in the numbering is finished work (B1, B2, B3, B4, M1, M2, M3, M4, M5,
R1, R2, R3, R4, R5, R6, Y1, Y2, Y3, Y4 and Y5 are done). It is a backlog, not a design doc: rationale for anything that ships goes in `docs/HISTORY.md`
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

## Readability

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

## What is left

One item, and it is yours: **Y6** — `AGENTS.md` is stale in six places (recorded under *Readability*
above). It is a protected instruction file, so those corrections have to come from you; everything
else from the audit has landed.
