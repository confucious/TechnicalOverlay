# TechnicalOverlay Architecture

A SwiftUI iOS/macOS app that creates video overlays for figure skating competitions. It takes a video of a skating performance and overlays technical scoring information (element names, base values, GOE scores, running totals) and introduction slides, producing a scored video with dissolve transitions.

## Project Structure

```
TechnicalOverlay/                          # Workspace root (Tuist-managed)
├── mise.toml                              # Tool versioning (tuist 4.61.2)
├── Tuist.swift                            # Tuist project config
├── TechnicalOverlay/                      # Main app target
│   ├── TechnicalOverlay.xcodeproj/
│   └── TechnicalOverlay/
│       ├── TechnicalOverlayApp.swift      # @main entry point
│       ├── MainView.swift                 # Primary UI + VideoComposer orchestration
│       ├── OverlayData.swift              # Core data model
│       ├── OverlayDataDocument.swift      # .tod file I/O (versioned JSON)
│       ├── ScoringListView.swift          # Full-screen data entry view
│       ├── TimeSettingsView.swift         # Timeline editor with "Start Now"
│       ├── ElementBuilderView.swift       # Placeholder: element builder
│       └── ContentView.swift              # Legacy/prototype view
├── LayoutEngine/                          # Shared library bundle
│   ├── LayoutEngine/                      # LayoutEngine framework (UIKit views)
│   │   ├── LayoutEngine.swift             # Constants: Color, Metrics, UIView extensions
│   │   ├── VideoOverlay.swift             # Main overlay container (1280x720)
│   │   ├── IsuLowerThirdView.swift        # Skater intro overlay
│   │   ├── IsuTechnicalPaneView.swift     # Technical scoring overlay
│   │   └── TechnicalPaneComponents/       # Pane subviews (5 files)
│   ├── VideoProcessor/                    # VideoProcessor framework (AVFoundation)
│   │   └── VideoProcessor/
│   │       ├── VideoProcessor.swift       # Slide, VideoComposer, Chunk pipeline
│   │       └── DefaultChunkRenderer.swift # ChunkRendererProtocol implementation
│   └── ProtocolParser/                    # Placeholder (empty stub)
│       └── ProtocolParser/
│           └── ProtocolParser.swift       # Empty import stub
└── docs/architecture/                     # Detailed module docs (this file links here)
    ├── main-app.md
    ├── layout-engine.md
    ├── video-processor.md
    └── protocol-parser.md
```

## Module Docs

Detailed documentation for each module lives in `docs/architecture/`:

| Module | Doc | Source |
|--------|-----|--------|
| **Main App** | [main-app.md](docs/architecture/main-app.md) | `TechnicalOverlay/TechnicalOverlay/` |
| **Layout Engine** | [layout-engine.md](docs/architecture/layout-engine.md) | `LayoutEngine/LayoutEngine/` |
| **Video Processor** | [video-processor.md](docs/architecture/video-processor.md) | `LayoutEngine/VideoProcessor/` |
| **Protocol Parser** | [protocol-parser.md](docs/architecture/protocol-parser.md) | `LayoutEngine/ProtocolParser/` |

## Data Flow

```
User loads video (MainView → fileImporter)
    │
    ▼
ViewModel.assetUrl = fileUrl
    │  (startAccessingSecurityScopedResource, generateSlides())
    ▼
OverlayData.makeSlides(size:)
    │  (for each intro + element: VideoOverlay.Mode → VideoOverlay.render() → CIImage → Slide)
    │  (imageCache keyed by (size, mode))
    ▼
VideoComposer(asset: AVAsset, slides: [Slide])
    │  (setupComposition() → AVVideoComposition)
    ▼
AVPlayerItem.videoComposition = composition
    │  (replaceCurrentItem, seek to previous position)
    ▼
AVPlayer plays video with overlays composited in real-time
    │
    ├── User edits timing (TimeSettingsView → setIntroTime/setElementTime)
    │       (cascading time propagation to subsequent items)
    │       → generateSlides() → new VideoComposer → replace player item
    │
    ├── User edits scoring data (ScoringListView → OverlayData mutation)
    │       → onDisappear: save() + clearCache()
    │       → generateSlides() → new VideoComposer
    │
    └── User exports (MainView → setupExport → ExportSession.performExport())
            → AVAssetExportSession writes .mov to temp URL
            → fileExporter dialog to save
```

## Key Design Decisions

1. **SwiftUI + UIKit hybrid:** App UI is SwiftUI; overlay rendering is UIKit → CIImage. UIKit views are easier to render to `CIImage` via `layer.render(in:)` for precise pixel-level layout.

2. **Scores in hundredths:** All score values stored as `Int` (hundredths of a point) internally, with string conversion for UI. Avoids floating-point precision issues in comparisons and hashing.

3. **Cascading timing:** When a user timestamps one item, all subsequent items shift by the same delta, preserving relative spacing.

4. **Image caching:** `OverlayData` caches rendered `CIImage` objects keyed by `(size, mode)`. Cache is cleared on data changes.

5. **Two rendering paths:** The main `VideoComposer` path is used for both preview and export (simple, single pipeline). The `ChunkQueue` + `DefaultChunkRenderer` path is a separate pipeline designed for incremental rendering — `DefaultChunkRenderer` is implemented but not yet wired into the main app export flow.

6. **No external dependencies:** The project uses only Apple frameworks (SwiftUI, AVFoundation, CoreImage, UIKit, CoreMedia, Observation). No SPM packages, CocoaPods, or Carthage.

7. **Tuist project generation:** Managed via Tuist 4.61.2, but generates standard Xcode `.xcodeproj` files.

## Dependencies Between Modules

```
TechnicalOverlay (app)
├── LayoutEngine (UIKit overlay views)
├── VideoProcessor (AVFoundation composition)
│   └── (implicitly depends on CoreImage from LayoutEngine's CIImage types)
└── ProtocolParser (placeholder, not linked)
```

`VideoProcessor` is part of the LayoutEngine Xcode workspace but is a separate framework target. It doesn't import LayoutEngine — it works with `CIImage` types directly.
