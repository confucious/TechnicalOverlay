# Video Processor Module

**Source:** `LayoutEngine/VideoProcessor/VideoProcessor/`

Handles video composition with overlay slides and chunk-based rendering. Uses `AVFoundation` for composition and export, `CoreImage` for transitions.

## File Map

| File | Role |
|------|------|
| `VideoProcessor.swift` | Everything: `Slide`, `VideoComposer` (including CIImage-based composition/export methods), `ExportSession`, `ContentIdentity`, `ChunkType`, `ChunkState`, `Chunk`, protocols (`ChunkRendererProtocol`, `StitcherProtocol`), `ChunkRegion`, `generateRegions()`, `diffRegionsIntoChunks()`, `ChunkQueue` actor. |
| `DefaultChunkRenderer.swift` | Concrete `ChunkRendererProtocol` implementation. `VideoSettings` config, `ChunkRendererError` enum. Renders chunks via `VideoComposer` CIImage-based composition + `AVAssetExportSession`. |
| `DefaultStitcher.swift` | Concrete `StitcherProtocol` implementation. Assembles rendered chunks plus source-video ranges into one `AVMutableComposition` and hands back an `ExportSession` for the caller to perform. |

## Core Types

### Slide

```swift
public struct Slide: Sendable, Equatable {
    let image: CIImage?
    public let startTime: CMTime
}
```

A `CIImage?` with a `CMTime` start time. Nil image represents "no overlay" (fade-out) slides.

### VideoComposer

```swift
public class VideoComposer {
    var asset: AVAsset
    var slides: [Slide]  // sorted by startTime

    // Slide-based composition (preview + full-video export)
    func setupComposition() async throws -> AVVideoComposition?
    func setupExport(...) async -> ExportSession?

    // CIImage-based composition (chunk rendering)
    func setupComposition(overlay: CIImage?) async throws -> AVVideoComposition
    func setupComposition(from: CIImage?, to: CIImage?, transitionStart: CMTime) async throws -> AVVideoComposition

    // CIImage-based export helpers
    func setupExport(overlay: CIImage?, withPreset: String, toFileType: AVFileType, atURL: URL) async -> ExportSession?
    func setupExport(from: CIImage?, to: CIImage?, transitionStart: CMTime, withPreset: String, toFileType: AVFileType, atURL: URL) async -> ExportSession?
}
```

**Slide-based path:** Creates `AVVideoComposition` with dissolve transitions between slides composited over source video. Used for both real-time preview and full-video export.

**Composition API:** the three chunk-renderer builders use `AVVideoComposition(applyingFiltersTo:applier:)`; the frame handler returns an `AVCIImageFilteringResult(resultImage:ciContext: nil)`. (`setupComposition()` — the preview — is the exception; see below.) It replaces `videoComposition(with:applyingCIFiltersWithHandler:)`, deprecated in iOS/macOS 27.0, and the replacement is not a rename — the handler's return is the `AVCIImageFilteringResult` (`docs/HISTORY.md` → *Core Image filter API migration*).

**The preview has its own compositor.** `setupComposition()` — the only builder attached to an `AVPlayerItem` — is the one builder that does **not** use `AVVideoComposition(applyingFiltersTo:applier:)`. It builds a `Configuration` with `customVideoCompositorClass = PreviewVideoCompositor.self`: a Core Image `AVVideoCompositing` whose `cancelAllPendingVideoCompositionRequests()` deliberately waits for nothing, so a cancelled frame is simply never finished and a seek's cancel path can never block on it. AVFoundation's own Core Image compositor *does* block there, while AVKit polls `AVPlayerItem.currentTime` on the main thread on every scrub tick — that combination freezes the app mid-drag, which is the entire reason this compositor exists. It bakes in the track's `preferredTransform` (custom compositors receive raw frames) and runs the same slide/dissolve program as the chunk renderer, so preview and export stay in step. **Do not simplify it back** to the filter API, and do not share an `AVURLAsset` between the player item and the chunk exporter. Mechanism, repro harness and measurements: `docs/HISTORY.md` → *Playhead freeze*.

**CIImage-based path (chunk rendering):** Direct `CIImage` → `AVVideoComposition` methods that bypass the `Slide[]` abstraction. Used by `DefaultChunkRenderer` to render individual time-limited chunks. Each frame handler composites the overlay image(s) over the source using `CIImage.composited(over:)`.

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

### ChunkRendererError

```swift
enum ChunkRendererError: Error, LocalizedError {
    case cannotCreateExportSession
    case exportFailed
    case compositionFailed
    case assetCompatibilityFailed
}
```

Errors produced during chunk rendering. Note: `DefaultChunkRenderer` currently prints errors and returns `nil` rather than propagating these errors to callers.

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
3. Build output URL (`chunk_<uuid>.mov`).
4. Check export compatibility (`AVAssetExportSession.compatibility(ofExportPreset:with:outputFileType:)`).
5. Create `AVAssetExportSession` with the configured preset.
6. Apply composition via `VideoComposer.setupComposition(overlay:)` or `setupComposition(from:to:transitionStart:)` depending on chunk type.
7. Limit export to `chunk.stitchingTimeRange`.
8. Export to file via `exportSession.export(to:as:)`.

## VideoComposition Pipeline (preview + export)

`setupComposition()` → `AVVideoComposition?`:

1. Sorts slides by `startTime`.
2. For each pixel request, finds the **last** slide whose `startTime <= compositionTime`.
3. If within `transitionTime` (0.75s) of the slide's start, performs a Core Image `CIFilter.dissolveTransition` from the previous slide to the current one, with `time` parameter interpolating from 0→1. A nil image on either side is treated as **no overlay** and dissolves as a clear image, so a slide fades in from (and out to) the plain source frame.
4. Otherwise, composites the current slide's image over the source frame.
5. If no slide matches (before first slide or all nil), passes through the source unchanged.

```
compositionTime ──┬─ before first slide ──→ source unchanged
                  ├─ between slides ────────→ dissolve or composite
                  └─ past last slide ────────→ source unchanged (or nil slide)
```

## Chunk-based Rendering Pipeline

The app's export path, wired into `MainView`'s **Save Video**. `ChunkQueue` (actor) renders pending
chunks through `DefaultChunkRenderer`, and `DefaultStitcher` assembles them into the final file.
`generateRegions` / `diffRegionsIntoChunks` / `ChunkQueue` live in `VideoProcessor.swift`.

```
[Slide[]] ──generateRegions()──→ [ChunkRegion[]] ──diffRegionsIntoChunks()──→ [Chunk[]]

[Chunk[]] ──ChunkQueue.drain()──→ [Chunk[] with URLs] ──StitcherProtocol.stitch()──→ Output video

                     ↓ DefaultChunkRenderer.render(chunk)
              AVAssetExportSession + VideoComposer CIImage composition
              (time-limited segment export)
```

### DefaultChunkRenderer rendering algorithm

Each chunk is rendered as a time-limited `AVAssetExportSession` export with `AVVideoComposition` compositing:

| Chunk Type | Composition Method | Behavior |
|------------|-------------------|----------|
| `.constant(CIImage)` | `setupComposition(overlay:)` | Single overlay image composited over source for every frame in the chunk's time range |
| `.transition(from, to)` | `setupComposition(from:to:transitionStart:)` | `CIFilter.dissolveTransition` interpolating from `from` to `to`, then `to` composited over source for remaining frames. A **nil side means "no overlay"** and dissolves as a clear image — that's the noOverlay ↔ slide fade (rendering the bare source frame instead made slides pop in). Both sides nil → source frame only. |
| `.noOverlay` | — | Returns `nil` immediately (filtered by `ChunkQueue` before reaching renderer) |

The CIImage-based composition methods operate directly on `CIImage` objects (unlike the slide-based path which works with `Slide[]` and finds slides by time lookup per frame). This is simpler and more direct for the chunk rendering use case where each chunk has a known, fixed overlay set.

### Region generation

`generateRegions(slides:videoDuration:transitionTime:)` → `[ChunkRegion]`:

Sweeps the video timeline from start to end, producing contiguous regions:

1. **Gap regions** (before each slide's transition): `.noOverlay` — the source video plays without overlays.
2. **Transition regions** (0.75s starting at each slide time): `.transition(from, to)` — dissolve from previous slide to current.
3. **Constant regions** (end of one transition to start of next): `.constant(CIImage)` or `.noOverlay` — the slide image is held static over the source.

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
| `Chunk` | Time-range-based unit of work with `renderState` (`pending` → `rendering` → `rendered(URL)`) and `stitchingTimeRange` for pipeline assembly. |
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
