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

### Y6. `AGENTS.md` is stale — the corrections to apply (user-only)

`AGENTS.md` is a protected instruction file, so this half cannot be applied from a session; the
`docs/ARCHITECTURE.md` half (two pointers at an untracked `TODO.md`) is fixed. Ten places are stale,
and each is something a future session would be taught wrongly (line numbers are the current file's):

1. **`:99-101`, tracing** — says the chunk pipeline `print`s and that the output "does not reach
   Console.app". It logs through `os.Logger` (`VideoProcessorLog.swift`: subsystem
   `org.cjas.technical-overlay.video-processor`, category `chunk-pipeline`, `.debug`, non-persistent;
   `Trace.isEnabled` silences it), so Console.app does see it under that subsystem.
2. **`:105-107`, the indicator** — "green once everything is rendered and the queue is idle" →
   `RenderPipeline.Status.rendered` (`.idle` was renamed because next to `noVideo` it read as
   "nothing loaded").
3. **`:122-130`, app source listing** — delete the `ElementBuilderView.swift` and `ContentView.swift`
   rows; both files are gone. The target's 19 files are `TechnicalOverlayApp`, `MainView`,
   `MainViewModel`, `AssetSession`, `RenderPipeline`, `ExportCoordinator`, `OverlayData`,
   `OverlayTimeline`, `OverlayStore`, `SlideFactory`, `ScoreFormatting`, `OverlayDataDocument`,
   `ScoringListView`, `TimeSettingsView`, `Log`, `PreviewData` (plus `Assets.xcassets`,
   `Info.plist`, and the untracked test movie).
4. **`:132-136`, LayoutEngine tree** — add `OverlayView.swift` (the base view that carries the
   unavailable `init(coder:)`) and `LabelBoxView.swift` (the boxed-label rig the lower third, the name
   box and the score rows share).
5. **`:142`, VideoProcessor tree** — `VideoProcessor.swift` is deleted; the module is `Slide`,
   `VideoComposer`, `ExportSession`, `Chunk`, `RegionPlan`, `ChunkQueue`, `OverlayCompositing`,
   `ChunkPipelineTrace`, `VideoProcessorLog`, plus the renderer and stitcher.
6. **`:146`, test bundle** — "7 test files" → 10, and the per-file list below it omits
   `ChunkValidityTests`, `OverlaySpanTests`, `ChunkQueueShutdownTests` and `TestSupport.swift`.
7. **`:239-240`, control flow** — `scoring.makeSlides(size:)` → `scoring.slidePlan()` then
   `SlideFactory.slides(from:size:)`; "(imageCache keyed by `(size, mode)` in `OverlayData`)" → the
   cache is `SlideFactory`'s.
8. **Gotchas `:277-278`** — the `ContentView.swift` (legacy prototype) and `ElementBuilderView.swift`
   (placeholder) lines describe files that no longer exist; delete both.
9. **Gotchas `:281`** — the security-scope pairing rule cites `MainView.ViewModel.assetUrl`; it is
   `AssetSession.adopt(_:)` (replacement) and `AssetSession.deinit` (teardown).
10. **Gotchas `:282-283`** — "`OverlayData` clears its `imageCache` on data changes" and
    "`ScoringListView` … clears cache on `onDisappear`": the cache is `SlideFactory`'s, it keeps only
    the modes the current plan uses, and nothing calls `clearCache()` any more (`ScoringListView`
    still saves on `onDisappear`).

---

## What is left

One item, and it is yours: **Y6** — `AGENTS.md` is stale in ten places, each written out under
*Readability* above with the replacement text. It is a protected instruction file, so those edits have
to come from you; everything else from the audit has landed.
