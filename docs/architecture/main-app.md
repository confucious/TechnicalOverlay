# Main App Module

**Source:** `TechnicalOverlay/TechnicalOverlay/`

A SwiftUI iOS app that creates video overlays for figure skating competitions. It takes a video of a skating performance and overlays technical scoring information (element names, base values, GOE scores, running totals) and introduction slides, producing a scored video with dissolve transitions.

## Entry Point

**`TechnicalOverlayApp.swift`** — SwiftUI `@main` app that launches `MainView` inside a `WindowGroup`.

## File Map

| File | Role |
|------|------|
| `MainView.swift` | Primary UI. Contains inner `ViewModel` (`@Observable`) managing `AVPlayer`, `VideoComposer`, and `OverlayData`. Buttons: Load Video, Save Video (export), Load Slides, Save Slides, Edit Slides. Embeds `TimeSettingsView`. |
| `OverlayData.swift` | Core data model. `OverlayData`, `IntroductionData`, `ElementData` types. Persistence (UserDefaults + `.tojson` files), slide generation, image caching, `renderingHash`. |
| `OverlayDataDocument.swift` | SwiftUI `FileDocument` for `.tojson` file I/O. Versioned JSON via `VersionedOverlayData` (current version 1). |
| `ScoringListView.swift` | Full-screen data entry via `NavigationStack` destination. Edits skater names, intro slide texts, element scores (name, base, GOE, bonus) in a grid. Add/remove buttons. Saves on `onDisappear`. |
| `TimeSettingsView.swift` | Timeline editor showing all intro slides and elements with timestamps. Each row has a "Start Now" button capturing the current video playback time. Cascading time propagation to subsequent items. |
| `ElementBuilderView.swift` | Placeholder: discipline picker (Singles/Pairs/Ice Dance/Synchronized) and type picker (Jumps/Spins/Steps & Spirals). Not yet wired into the app. |
| `ContentView.swift` | Legacy/prototype view with hardcoded test data (Scotty HSU example). Contains `UIViewRepresentable` wrappers for previewing LayoutEngine views. Not used in production. |

## Data Model

All data uses Apple's `@Observable` macro (Swift Concurrency Observation framework). Defined in `OverlayData.swift`.

| Type | Purpose |
|------|---------|
| `OverlayData` | Top-level model: skater full name, abbreviated name, intro slides, element scores. Methods: `save()`/`load()` (UserDefaults), `update(from:)`, `setIntroTime(index:time:)`, `setElementTime(index:time:)`, `makeSlides(size:)`, `makeSlide(size:mode:startTime:)`, `renderingHash` (deterministic hash of all rendering-affecting fields). |
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
├── VideoPlayer (if video loaded)
├── TimeSettingsView (if scoring data + video loaded)
└── Button row: Load Video | Save Video | Load Slides | Save Slides | Edit Slides   (+ render status dot)
       │              │              │             │            └── ScoringListView (NavigationStack destination)
       │              │              │             └── OverlayDataDocument export (.tojson)
       │              │              └── OverlayDataDocument import (.tojson) → update + save
       │              └── save panel picks the destination → ExportSession.performExport → writes .mp4 there
       └── fileImporter (.movie) → ViewModel.assetUrl → generateSlides() → new VideoComposer → replace player item
```

**Two assets, on purpose.** `generateSlides()` builds the player item from one `AVURLAsset` and
hands the chunk renderer a *second* `AVURLAsset` over the same file. The chunk queue renders while
the video is on screen, and sharing a single asset instance makes the two pipelines contend for its
decode/compositor state: with a video composition on the player item, chunk exports drained back to
back block the player's own `AVPlayerItem.currentTime` for tens of seconds, and AVKit reads
`currentTime` on the main thread on every scrub tick — so the whole app freezes mid-drag. Do not
re-merge them; see the decision log (2026-10-16) and `scripts/probe-scrub-deadlock.swift`.

## File I/O

| Format | Mechanism | Details |
|--------|-----------|---------|
| UserDefaults (JSON) | `OverlayData.save()` / `load()` | Auto-save under key `"state"`. |
| `.tojson` files | `OverlayDataDocument` (SwiftUI `FileDocument`) | Versioned JSON (`VersionedOverlayData.version == 1`). Import via `fileImporter`, export via `fileExporter`. |
| Video files | `MainView` | `.movie` import via `fileImporter`. Export: `fileExporter` with a zero-byte `SaveDestinationPlaceholder` picks the destination first, then the passthrough export writes `.mp4` straight to it (the placeholder file is deleted first — `AVAssetExportSession` won't overwrite). |

## Dependencies

- **LayoutEngine** — `VideoOverlay`, `LowerThirdViewModel`, `TechnicalViewModel`, `ElementBoxView.Mode`
- **VideoProcessor** — `VideoComposer`, `Slide`
