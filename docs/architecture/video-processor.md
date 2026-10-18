# Video Processor Module

**Source:** `LayoutEngine/VideoProcessor/VideoProcessor/`

Handles video composition with overlay slides and chunk-based rendering. Uses `AVFoundation` for composition and export, `CoreImage` for transitions.

## File Map

| File | Role |
|------|------|
| `OverlayCompositing.swift` | The overlay program and the chunk composition builder. `OverlayComposite` — `hold(_:over:)` and `dissolve(from:to:progress:over:)` — is how an image lands on a source frame, shared by the preview compositor and the chunk renderer. `ChunkComposition` turns a chunk's overlay(s) into an `AVVideoComposition` for `DefaultChunkRenderer`. |
| `Slide.swift` | `Slide` — an overlay image with the time it starts — and `Metrics.transitionTime`, the dissolve length. |
| `VideoComposer.swift` | The preview pipeline: `PreviewRecipe` (the recipe the compositor reads, published through a lock), `PreviewVideoCompositor` (the custom `AVVideoCompositing` that must not be replaced by the filter API), and `VideoComposer`, which publishes the recipe, builds the preview `AVVideoComposition` and offers the slide-based `setupExport`. |
| `ExportSession.swift` | `VideoComposer.ExportSession` — a configured `AVAssetExportSession` with async progress, performed by the caller. |
| `Chunk.swift` | `ContentIdentity`, `ChunkType`, `ChunkState`, `Chunk` (with the `hasOverlay` / `isInPlan` / `needsRender` / `isRendered` / `isValid` predicates the stages share), and the pipeline's two seams, `ChunkRendererProtocol` and `StitcherProtocol`. |
| `RegionPlan.swift` | `ChunkRegion`, `generateRegions()` — the timeline swept into clipped, contiguous regions — and `diffRegionsIntoChunks()`, which reuses what the new plan still covers and drops the rest. |
| `ChunkQueue.swift` | `ChunkQueueProgress` and the `ChunkQueue` actor: it owns the plan and drains it through the renderer, one chunk at a time. |
| `ChunkPipelineTrace.swift` | `Trace.log` and the formatting helpers (`traceLabel`, `traceDescription`, `TraceTimer`) that put one `[Area]`-prefixed line per chunk into the `chunk-pipeline` log. `Trace.isEnabled` silences the whole pipeline. |
| `VideoProcessorLog.swift` | The module's `os.Logger`s: `chunk-pipeline` for the trace, `composition` for export-setup failures. |
| `DefaultChunkRenderer.swift` | Concrete `ChunkRendererProtocol` implementation. `VideoSettings` config. Renders chunks via `ChunkComposition` + `AVAssetExportSession`; failures are traced and return `nil`, not thrown. |
| `DefaultStitcher.swift` | Concrete `StitcherProtocol` implementation. Assembles rendered chunks plus source-video ranges into one `AVMutableComposition` and hands back an `ExportSession` for the caller to perform. |

## Core Types

### Slide

```swift
public nonisolated struct Slide: Sendable, Equatable {
    let image: CIImage?
    public let startTime: CMTime
}
```

A `CIImage?` with a `CMTime` start time. Nil image represents "no overlay" (fade-out) slides.

`Slide` and the other types on the plan's path are `nonisolated` because `ChunkQueue` is an `actor`
(ARCHITECTURE.md §5.2 → *Isolation*); the annotation and the extensions' own markers are the rule
that keeps that path free of main-actor hops.

### VideoComposer

```swift
public class VideoComposer {
    var asset: AVAsset
    var slides: [Slide]  // sorted by startTime

    // Slide-based composition (preview + full-video export)
    func setupComposition() async throws -> AVVideoComposition?
    func setupExport(...) async -> ExportSession?
}
```

**Slide-based path:** Creates `AVVideoComposition` whose compositor knows the slide plan (the spans
`generateRegions` keys the export from); dissolves and holds are resolved per frame from it. Used for
both real-time preview and full-video export.

**Composition API:** `ChunkComposition` (in `OverlayCompositing.swift`) is the only builder that uses `AVVideoComposition(applyingFiltersTo:applier:)`; its frame handler returns `AVCIImageFilteringResult(resultImage:ciContext: nil)`. (`setupComposition()` — the preview — is the exception; see below.) It replaces `videoComposition(with:applyingCIFiltersWithHandler:)`, deprecated in iOS/macOS 27.0, and the replacement is not a rename — the handler's return is the `AVCIImageFilteringResult` (`docs/HISTORY.md` → *Core Image filter API migration*).

**The preview has its own compositor.** `setupComposition()` — the only builder attached to an `AVPlayerItem` — is the one builder that does **not** use `AVVideoComposition(applyingFiltersTo:applier:)`. It builds a `Configuration` with `customVideoCompositorClass = PreviewVideoCompositor.self`: a Core Image `AVVideoCompositing` whose `cancelAllPendingVideoCompositionRequests()` deliberately waits for nothing, so a cancelled frame is simply never finished and a seek's cancel path can never block on it. AVFoundation's own Core Image compositor *does* block there, while AVKit polls `AVPlayerItem.currentTime` on the main thread on every scrub tick — that combination freezes the app mid-drag, which is the entire reason this compositor exists. It bakes in the track's `preferredTransform` (custom compositors receive raw frames). **Do not simplify it back** to the filter API, and do not share an `AVURLAsset` between the player item and the chunk exporter. Mechanism, repro harness and measurements: `docs/HISTORY.md` → *Playhead freeze*.

**One overlay program.** The preview and the chunk renderer draw a frame through `OverlayComposite`
(`OverlayCompositing.swift`): `hold(_:over:)` and `dissolve(from:to:progress:over:)`. The preview
resolves the frame against the plan's spans and hands the endpoints to `OverlayComposite`;
`ChunkComposition` is handed the endpoints directly. A nil image means **no overlay on that
side** — a nil side of a dissolve is a fully transparent image, so a slide fades in from (and out to)
the plain source frame — and `progress` is clamped to 0…1 there, once.

**Chunk composition:** `ChunkComposition(asset:)` builds the export composition for one chunk —
`overlay(_:)` for a held overlay, `transition(from:to:startingAt:)` for a dissolve. It covers the whole
asset; the export session's `timeRange` selects the chunk, so the applier's `compositionTime` is on the
asset's timeline and `transitionStart` is absolute.

### VideoComposer.ExportSession

```swift
public struct ExportSession {
    let exportSession: AVAssetExportSession
    let outputUrl: URL
    let outputFileType: AVFileType
    let exportState: any AsyncSequence<AVAssetExportSession.State, Never>

    func performExport() async
}
```

Wraps `AVAssetExportSession` with async progress tracking via `exportState` (uses `AVAssetExportSession.states(updateInterval:)`).

### VideoSettings

```swift
public struct VideoSettings: Sendable {
    let presetName: String
    let outputFileType: AVFileType

    public static let `default` = VideoSettings(
        presetName: AVAssetExportPresetHighestQuality,
        outputFileType: .mov
    )
}
```

Configuration for chunk export encoding.


### DefaultChunkRenderer

```swift
public final class DefaultChunkRenderer: ChunkRendererProtocol {
    private let sourceAsset: AVAsset
    private let outputDirectory: URL
    private let settings: VideoSettings

    public init(sourceAsset: AVAsset, outputDirectory: URL, settings: VideoSettings = .default)
    public func render(_ chunk: Chunk) async -> URL?
}
```

Renders individual chunks by exporting time-limited segments of the source video with overlay composited via `AVVideoComposition`. `ChunkQueue` (an actor) calls `render(chunk:)` sequentially, so no additional queue or synchronization is needed.

**Render flow:**
1. Staleness check — returns `nil` if `chunk.stitchingTimeRange` is `nil`.
2. `noOverlay` guard — returns `nil` for `.noOverlay` chunks (defensive; `ChunkQueue` already filters these).
3. Build output URL (`chunk_<uuid>.mov`, in the directory it was given — the app passes a per-queue
directory so the whole set can be deleted in one go).
4. Check export compatibility (`AVAssetExportSession.compatibility(ofExportPreset:with:outputFileType:)`).
5. Create `AVAssetExportSession` with the configured preset.
6. Apply composition via `ChunkComposition.overlay(_:)` or `.transition(from:to:startingAt:)` depending on chunk type.
7. Limit export to `chunk.stitchingTimeRange`.
8. Export to file via `exportSession.export(to:as:)`.

## VideoComposition Pipeline (preview + export)

`setupComposition()` → `AVVideoComposition?`:

1. Sorts slides by `startTime`.
2. Sweeps them into the plan: `overlaySpans(slides:videoDuration:transitionTime:)` — the same walk
   `generateRegions` keys the export from, published in the preview recipe.
3. For each pixel request, resolves `compositionTime` against those spans
   (`[OverlaySpan].content(at:transitionTime:)`) — the span containing the time decides.
4. A `.transition` span dissolves from its `from` to its `to` at `(time - span.start) / transitionTime`
   with `CIFilter.dissolveTransition`; a `.constant` span holds its image; `.noOverlay` passes the
   source through. A nil image on either side is **no overlay** and dissolves as a clear image, so a
   slide fades in from (and out to) the plain source frame.

```
compositionTime ──┬─ inside a .noOverlay span ──→ source unchanged
                  ├─ inside a .transition span ─→ dissolve, progress = elapsed / transitionTime
                  └─ inside a .constant span ───→ image held over source
```

**The preview is the export's plan, resolved per frame.** The compositor does not search the slides
itself: a slide list walked from the playhead answers a different question than the export's forward
sweep, and the two disagree as soon as two slides are closer than `transitionTime` (the preview
dissolved into the second slide while the export was still fading the first one in).
`docs/HISTORY.md` → *One walk for the preview and the plan*.

## Chunk-based Rendering Pipeline

The app's export path, wired into `MainView`'s **Save Video**. `ChunkQueue` (actor) renders pending
chunks through `DefaultChunkRenderer`, and `DefaultStitcher` assembles them into the final file.
`generateRegions` / `diffRegionsIntoChunks` live in `RegionPlan.swift`, and `ChunkQueue` in
`ChunkQueue.swift`.

```
[Slide[]] ──generateRegions()──→ [ChunkRegion[]] ──diffRegionsIntoChunks()──→ [Chunk[]]

[Chunk[]] ──ChunkQueue.drain()──→ [Chunk[] with URLs] ──StitcherProtocol.stitch()──→ Output video

                     ↓ DefaultChunkRenderer.render(chunk)
              AVAssetExportSession + ChunkComposition
              (time-limited segment export)
```

### DefaultChunkRenderer rendering algorithm

Each chunk is rendered as a time-limited `AVAssetExportSession` export with `AVVideoComposition` compositing:

| Chunk Type | Composition Method | Behavior |
|------------|-------------------|----------|
| `.constant(CIImage)` | `ChunkComposition.overlay(_:)` | Single overlay image composited over source for every frame in the chunk's time range |
| `.transition(from, to)` | `ChunkComposition.transition(from:to:startingAt:)` | `CIFilter.dissolveTransition` interpolating from `from` to `to`, then `to` composited over source for remaining frames. A **nil side means "no overlay"** and dissolves as a clear image — that's the noOverlay ↔ slide fade (rendering the bare source frame instead made slides pop in). Both sides nil → source frame only. |
| `.noOverlay` | — | Returns `nil` immediately (filtered by `ChunkQueue` before reaching renderer) |

The CIImage-based composition methods operate directly on `CIImage` objects (unlike the slide-based path which works with `Slide[]` and finds slides by time lookup per frame). This is simpler and more direct for the chunk rendering use case where each chunk has a known, fixed overlay set.

### Region generation

`overlaySpans(slides:videoDuration:transitionTime:)` → `[OverlaySpan]`, and
`generateRegions(slides:videoDuration:transitionTime:)` → `[ChunkRegion]`, which is the same spans
with each one's `ContentIdentity` added (`generateRegions` is a map over `overlaySpans`, so the two
cannot be walked differently).

Sweeps the video timeline from start to end, producing contiguous spans:

1. **Gap spans** (before each slide's transition): `.noOverlay` — the source video plays without overlays.
2. **Transition spans** (`transitionTime` starting at each slide time, or where the previous transition
   ended when the slides are closer than that): `.transition(from, to)` — dissolve from previous slide to current.
3. **Constant spans** (end of one transition to start of next): `.constant(CIImage)` or `.noOverlay` — the slide image is held static over the source.

**A transition always runs its full `transitionTime`.** Slides closer together than that do not
shorten it and do not overlap: the sweep advances a cursor to the end of the transition it just
emitted, and the next slide's dissolve starts there — later than that slide's own `startTime`, never
truncated. The preview resolves frames against the same spans, so both paths show the same frame for
the same time.

Every region is **clipped to `[0, videoDuration]`**, and a region left empty by the clip is dropped.
A transition that starts within `transitionTime` of the end (the last slide's, typically) would
otherwise run past the video, and `DefaultStitcher.stitch` requires the plan to end exactly at
`videoDuration` — an overrun would abort a valid export. A slide at or beyond `videoDuration` adds no
region, and a plan with no regions at all is one whole-video `.noOverlay`.

### Chunk diffing

`diffRegionsIntoChunks(newRegions:existingChunks:)` → `[Chunk]`:

Compares new regions against existing chunks, reusing unchanged content:

- **`.noOverlay`** chunks are never reused — always created new.
- **`.transition`** chunks require exact timeRange match to be reused.
- **`.constant`** chunks can be reused for overlapping portions (partial overlap splits into new-reuse-new).
- Unreused existing chunks are marked stale (`stitchingTimeRange = nil`).

### Chunk types

| Type | Description |
|------|-------------|
| `ChunkRegion` | Time-identified region with `ContentIdentity`, `CMTimeRange`, `ChunkType`. |
| `ChunkType` | `.noOverlay` / `.constant(CIImage)` / `.transition(from: CIImage?, to: CIImage?)` |
| `ContentIdentity` | Stable hash for content reuse detection, independent of time range. |
| `Chunk` | Time-range-based unit of work with `renderState` (`pending` → `rendering` → `rendered(URL)`) and `stitchingTimeRange` for pipeline assembly. Its predicates — `hasOverlay`, `isInPlan`, `needsRender`, `isRendered`, `isValid` — are the single definition of "which chunks need rendering" and "which chunks can be stitched"; the queue, the renderer and the stitcher filter on them rather than restating the rules. |
| `ChunkState` | `.pending` / `.rendering` / `.rendered(URL)` |

### ChunkQueue (actor)

```swift
public actor ChunkQueue {
    var chunks: [Chunk] = []
    private let renderer: ChunkRendererProtocol
    private let transitionTime: CMTime
    private var isDraining = false

    func enqueue(slides: [Slide], videoDuration: CMTime)
    func markStale(where: (Chunk) -> Bool)
    func startRendering() async
    func waitForCompletion() async
    func validChunks() -> [Chunk]
}
```

Manages the rendering pipeline:
1. `enqueue()` generates regions from slides, diffs against existing chunks, triggers drain.
2. `drain()` loops: dequeue next pending chunk → mark rendering → call renderer → mark rendered or stale.
3. `waitForCompletion()` awaits the drain task — including the one `enqueue()` started — so it never
   returns while a chunk is in the `.rendering` state.
4. `shutdown()` cancels the drain, **awaits it** (nothing is still exporting when the files go), then
   deletes every file the queue's chunks point at and empties the plan. The queue owns those files:
   the renderer writes them, but only the queue knows which ones it asked for.

### Why the diff exists

`diffRegionsIntoChunks()` reuses unchanged constant chunks (for overlapping portions) so a timing edit
re-renders the regions that changed rather than the whole video — the reason the chunk path exists
alongside `VideoComposer.setupExport()`.

## Protocols

| Protocol | Purpose |
|----------|---------|
| `ChunkRendererProtocol` | `func render(_ chunk: Chunk) async -> URL?` — render a chunk to a file URL. |
| `StitcherProtocol` | `func stitch(chunks: [Chunk], sourceAsset: AVAsset, videoDuration: CMTime, to outputURL: URL) async -> URL?` — assemble rendered chunks + source video into final output. |

## Dependencies

- `AVFoundation` — `AVAsset`, `AVVideoComposition`, `AVAssetExportSession`, `CMTime`
- `CoreImage` — `CIImage`, `CIFilter.dissolveTransition`
