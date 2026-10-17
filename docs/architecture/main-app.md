# Main App Module

**Source:** `TechnicalOverlay/TechnicalOverlay/`

A SwiftUI iOS app that creates video overlays for figure skating competitions. It takes a video of a skating performance and overlays technical scoring information (element names, base values, GOE scores, running totals) and introduction slides, producing a scored video with dissolve transitions.

## Entry Point

**`TechnicalOverlayApp.swift`** — SwiftUI `@main` app that launches `MainView` inside a `WindowGroup`.

## File Map

| File | Role |
|------|------|
| `MainView.swift` | Primary UI. Holds the `MainViewModel` in `@State` and renders it: buttons Load Video, Save Video (export), Load Slides, Save Slides, Edit Slides, Clear Slides (destructive, confirmed); config row with the element box toggle; the background render indicator over the video's bottom-right corner, clear of the scrubbing control; the export progress sheet. Embeds `TimeSettingsView`. Also carries the SwiftUI presentation of `RenderPipeline.Status` (dot colour, label, accessibility text). |
| `MainViewModel.swift` | The main screen's state: `AVPlayer`, `OverlayData`, and the two background jobs. Owns `AssetSession`, `RenderPipeline` and `ExportCoordinator`, keeps them pointed at the same file (`assetUrl`'s setter adopts the new file, drops the old plan and regenerates), and is what the views observe. |
| `AssetSession.swift` | The loaded video's security scope and probed metadata: `adopt(_:)` starts the new scope and releases the previous one; `size(of:)` returns the track's natural size with its preferred transform applied, abs'ed, cached per file. |
| `RenderPipeline.swift` | The preview and the chunk queue: `makePreviewItem(asset:slides:)` builds the `VideoComposer` and returns the `AVPlayerItem`; `enqueue(slides:asset:videoURL:)` plans the slides into the `ChunkQueue` (with the *second* `AVURLAsset` over the same file) and starts rendering; `waitForCompletion()` / `validChunks()` for the export. Publishes `status` (the indicator) and `progress`. |
| `ExportCoordinator.swift` | "Save Video": `phase` (idle → rendering → stitching → done, or `failed(message)`), `stitchingProgress`, and `exportScoredVideo(videoURL:to:)` — wait for the chunks, stitch straight to the chosen destination, monitor and perform the passthrough export, clean up on failure. |
| `OverlayData.swift` | Core data model. `OverlayData`, `IntroductionData`, `ElementData` types. Persistence (UserDefaults + `.tojson` files), slide generation, image caching, `renderingHash`. |
| `OverlayPreferences.swift` | Device-level overlay settings in `UserDefaults` (`showsElementBox`, default `true`). Applied to `OverlayData` at launch; deliberately not part of the `.tojson` document. |
| `OverlayDataDocument.swift` | SwiftUI `FileDocument` for `.tojson` file I/O. Versioned JSON via `VersionedOverlayData` (current version 1). |
| `ScoringListView.swift` | Full-screen data entry via `NavigationStack` destination. Edits skater names, intro slide texts, element scores (name, base, GOE, bonus) in a grid. Add/remove buttons. Saves on `onDisappear`. |
| `TimeSettingsView.swift` | Timeline editor showing all intro slides and elements with timestamps. Always shown when there is scoring data — a loaded video is not required, and without one the timeline is read-only. `Playhead` (defined here) is the playback seam: `getTime()` returns the current time, `seekTo(_:)` moves the video to a time. A set time renders as a button that seeks there; "Start Now" stamps the playhead time read at tap time, and is hidden (with its layout space kept) when there is no playhead. Cascading time propagation to subsequent items. |
| `ElementBuilderView.swift` | Placeholder: discipline picker (Singles/Pairs/Ice Dance/Synchronized) and type picker (Jumps/Spins/Steps & Spirals). Not yet wired into the app. |
| `ContentView.swift` | Legacy/prototype view with hardcoded test data (Scotty HSU example). Contains `UIViewRepresentable` wrappers for previewing LayoutEngine views. Not used in production. |

## Data Model

All data uses Apple's `@Observable` macro (Swift Concurrency Observation framework). Defined in `OverlayData.swift`.

| Type | Purpose |
|------|---------|
| `OverlayData` | Top-level model: skater full name, abbreviated name, intro slides, element scores. `showsElementBox` is the live overlay-look value, seeded from `OverlayPreferences` rather than the document. Methods: `save()`/`load()` (UserDefaults), `update(from:)`, `setIntroTime(index:time:)`, `setElementTime(index:time:)`, `makeSlides(size:)`, `makeSlide(size:mode:startTime:)`, `renderingHash` (deterministic hash of all rendering-affecting fields). |
| `IntroductionData` | One intro slide: `left`/`center`/`right` text strings + optional `displayTime`. `displayValue` joins non-empty texts with `" | "`. `makeMode(skaterName:)` → `VideoOverlay.Mode.lowerThirdPane`. |
| `ElementData` | One scoring element: `name`, `baseValue`, `goeValue`, `bonusValue` (all stored as `Int` in hundredths), optional `displayTime`. Computed properties `baseValueString`, `goeValueString`, `bonusValueString` handle string↔hundredths conversion for UI text fields. `formatValue(_:)` converts hundredths to "X.XX" string. `makeMode(skaterName:runningTotal:boxModes:)` → `VideoOverlay.Mode.technicalPane`. |

### Score representation

Scores are stored as `Int` in hundredths (e.g., 3.40 → 340, -1.19 → -119). This avoids floating-point precision issues in comparisons and hashing.

`String` extensions handle conversion:
- `numberCharacters()` — extracts digits, decimal point, minus sign
- `onlyDigits()` — extracts only 0-9
- `toHundredthsInt()` — parses a decimal string into hundredths integer

### Time representation

All display times are `TimeInterval` (seconds as `Double`). When a user timestamps one item, all subsequent items shift by the same delta (cascading propagation in `setIntroTime`/`setElementTime`), preserving relative spacing.

## UI Flow

```
MainView (root)
├── VideoPlayer (if video loaded)   (+ render status dot, bottom-right, 72pt above the bottom edge)
├── TimeSettingsView (if scoring data; read-only without a video)
├── Config row: Element boxes toggle
└── Button row: Load Video | Save Video | Load Slides | Save Slides | Edit Slides | Clear Slides
    (the slides buttons drop to two lines when four labels don't fit one)
       │              │              │             │            └── ScoringListView (NavigationStack destination)
       │              │              │             └── OverlayDataDocument export (.tojson)
       │              │              └── OverlayDataDocument import (.tojson) → update + save
       │              └── save panel picks the destination → ExportSession.performExport → writes .mp4 there
       └── fileImporter (.movie) → MainViewModel.assetUrl → generateSlides() → new VideoComposer → replace player item
```

**Two `AVURLAsset`s over the same file, deliberately** — one for the player item, a second for the
chunk renderer. The chunk queue renders while the video is on screen, and a single shared instance
makes the two pipelines contend for its decode/compositor state, which freezes the whole app
mid-drag. **Do not re-merge them** — `docs/HISTORY.md` → *Playhead freeze*.

## File I/O

| Format | Mechanism | Details |
|--------|-----------|---------|
| UserDefaults (JSON) | `OverlayData.save()` / `load()` | Auto-save under key `"state"`. |
| UserDefaults (Bool) | `OverlayPreferences.showsElementBox` | Key `"showsElementBox"`; absent means boxes shown. Read once at launch, written on every toggle. |
| `.tojson` files | `OverlayDataDocument` (SwiftUI `FileDocument`) | Versioned JSON (`VersionedOverlayData.version == 1`). Import via `fileImporter`, export via `fileExporter`. |
| Video files | `MainView` | `.movie` import via `fileImporter`. Export: `fileExporter` with a zero-byte `SaveDestinationPlaceholder` picks the destination first, then the passthrough export writes `.mp4` straight to it (the placeholder file is deleted first — `AVAssetExportSession` won't overwrite). |

## Dependencies

- **LayoutEngine** — `VideoOverlay`, `LowerThirdViewModel`, `TechnicalViewModel`, `ElementBoxView.Mode`
- **VideoProcessor** — `VideoComposer`, `Slide`
