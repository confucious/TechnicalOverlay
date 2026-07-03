# Video Processor Module

**Source:** `LayoutEngine/VideoProcessor/VideoProcessor/`

Handles video composition with overlay slides and chunk-based rendering. Uses `AVFoundation` for composition and export, `CoreImage` for transitions.

## File Map

| File | Role |
|------|------|
| `VideoProcessor.swift` | Everything: `Slide`, `VideoComposer`, `ExportSession`, `ContentIdentity`, `ChunkType`, `ChunkState`, `Chunk`, protocols (`ChunkRendererProtocol`, `StitcherProtocol`), `ChunkRegion`, `generateRegions()`, `diffRegionsIntoChunks()`, `ChunkQueue` actor. |

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

    func setupComposition() async throws -> AVVideoComposition?
    func setupExport(...) async -> ExportSession?
}
```

Creates `AVVideoComposition` with dissolve transitions between slides composited over source video. Used for both real-time preview and export.

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

## VideoComposition Pipeline (preview + export)

`setupComposition()` → `AVVideoComposition?`:

1. Sorts slides by `startTime`.
2. For each pixel request, finds the **last** slide whose `startTime <= compositionTime`.
3. If within `transitionTime` (0.75s) of the slide's start, performs a Core Image `CIFilter.dissolveTransition` from the previous slide to the current one, with `time` parameter interpolating from 0→1.
4. Otherwise, composites the current slide's image over the source frame.
5. If no slide matches (before first slide or all nil), passes through the source unchanged.

```
compositionTime ──┬─ before first slide ──→ source unchanged
                  ├─ between slides ────────→ dissolve or composite
                  └─ past last slide ────────→ source unchanged (or nil slide)
```

## Chunk-based Rendering Pipeline (unused by main app)

A more sophisticated pipeline designed for incremental/reusable rendering. Not currently wired into the main app.

```
[Slide[]] ──generateRegions()──→ [ChunkRegion[]] ──diffRegionsIntoChunks()──→ [Chunk[]]
                                                                              
[Chunk[]] ──ChunkQueue.drain()──→ Rendered URL[] ──StitcherProtocol.stitch()──→ Output video
```

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
3. `waitForCompletion()` polls until all pending chunks are done.

### Key insight

`diffRegionsIntoChunks()` reuses unchanged constant chunks (for overlapping portions), only re-rendering what changed. This enables incremental updates when timing data changes — you don't need to re-render the entire video when only one element's timestamp shifts.

## Protocols

| Protocol | Purpose |
|----------|---------|
| `ChunkRendererProtocol` | `func render(_ chunk: Chunk) async -> URL?` — render a chunk to a file URL. |
| `StitcherProtocol` | `func stitch(chunks: [Chunk], sourceAsset: AVAsset, videoDuration: CMTime, to outputURL: URL) async -> URL?` — assemble rendered chunks + source video into final output. |

## Dependencies

- `AVFoundation` — `AVAsset`, `AVVideoComposition`, `AVAssetExportSession`, `CMTime`
- `CoreImage` — `CIImage`, `CIFilter.dissolveTransition`
