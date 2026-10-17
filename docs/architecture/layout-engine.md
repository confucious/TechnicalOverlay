# Layout Engine Module

**Source:** `LayoutEngine/LayoutEngine/`

A UIKit-based view library that renders figure skating scoring overlays, designed to be rasterized to `CIImage` for video compositing. No SwiftUI — pure UIKit `UIView` hierarchy.

## File Map

| File | Role |
|------|------|
| `LayoutEngine.swift` | Shared constants: `Color` (named overlay colors), `Metrics` (layout proportions), `CornerDirection` enum, `UIView` extensions (`cornerRadius()`, `roundedCornerConfiguration(corners:)`, `fontSize()`). |
| `VideoOverlay.swift` | Main overlay container `UIView` (1280x720 base). Holds `IsuTechnicalPaneView` (top-left) and `IsuLowerThirdView` (bottom-center). `Mode` enum (`none`, `technicalPane`, `lowerThirdPane`). `render(size:)` → `CIImage`. |
| `IsuLowerThirdView.swift` | Skater introduction overlay with two lines: `UpperLineView` (skater name on blue) + `LowerLineView` (left/center/right text on dark gray). |
| `IsuTechnicalPaneView.swift` | Technical scoring overlay with four subcomponents: `ElementRowView`, `ElementNameView`, `ElementScoreView`, `ProgramTotalView`. The box row is optional (`showsElementBox`). |
| `TechnicalPaneComponents/ElementBoxView.swift` | Single colored box with modes: `unscored`, `positive`, `negative`, `neutral`. |
| `TechnicalPaneComponents/ElementNameView.swift` | Element name label on black background. |
| `TechnicalPaneComponents/ElementRowView.swift` | Dynamic container that creates `ElementBoxView` instances based on `boxModes` array. |
| `TechnicalPaneComponents/ElementScoreView.swift` | Two-part display: base value (left) + GOE (right), GOE background colored green/red based on sign. |
| `TechnicalPaneComponents/ProgramTotalView.swift` | Two-part display: skater name (blue, left) + total score (pink, right). |

## Constants

### Colors (`LayoutEngine.swift`)

| Symbol | RGB | Use |
|--------|-----|-----|
| `Color.nameBox` | (83, 144, 205) | Skater name background |
| `Color.positive` | (79, 153, 47) | Positive GOE background |
| `Color.negative` | (195, 84, 65) | Negative GOE background |
| `Color.technicalBackground` | lightGray | Pane background |
| `Color.totalScore` | (195, 102, 147) | Program total background |
| `Color.bottomLine` | darkGray | Lower third background |

### Metrics

| Symbol | Value | Use |
|--------|-------|-----|
| `Metrics.techPaneHeightPercent` | 0.16 | Technical pane height as fraction of overlay height |
| `Metrics.techPaneAspectRatio` | 2.65 | Technical pane width/height ratio |
| `Metrics.overlayBorderPercent` | 0.05 | Border padding around overlay |
| `Metrics.lowerThirdHeightPercent` | 0.15 | Lower third height as fraction of overlay height |
| `Metrics.lowerThirdAspectRatio` | 8.5 | Lower third width/height ratio |
| `Metrics.boxRowPercent` | 0.6 | Box row height proportion |
| `Metrics.borderPercent` | 0.1 | Border size proportion |
| `Metrics.mainRowPercent` | `1/(3 + boxRowPercent + 5 * borderPercent)` | Main row height proportion |
| `Metrics.cornerRadiusPercent` | 0.1 | Corner radius as fraction of view height |

## View Hierarchy

```
VideoOverlay (1280x720 base frame)
├── IsuTechnicalPaneView          (top-left, 16% height, 2.65 aspect ratio)
│   ├── ElementRowView            (top row: colored element boxes)
│   ├── ElementNameView           (element name label, black bg)
│   ├── ElementScoreView          (base value left, GOE right)
│   └── ProgramTotalView          (skater name blue-left, total pink-right)
└── IsuLowerThirdView             (bottom-center, 15% height, 8.5 aspect ratio)
    ├── UpperLineView             (skater name on blue bg)
    │   └── backgroundView → nameLabel
    └── LowerLineView             (left/center/right text on dark gray bg)
        └── backgroundView → centerLabel, leftLabel, rightLabel
```

## Rendering

`VideoOverlay.render(size:)` → `CIImage`:

1. Sets `bounds` to target size, calls `layoutIfNeeded()`.
2. Creates `UIGraphicsImageRenderer` with `scale=1`, `opaque=false`.
3. Renders the view's `CALayer` into the renderer's context.
4. Wraps the resulting `UIImage` in `CIImage`.

The overlay has `alpha=0.9` and `backgroundColor=.clear`. Both subviews are hidden by default; the active one is shown based on `Mode`.

## Data Binding (ViewModel types)

Both are `Hashable` value types passed into views via `update(from:)`.

| ViewModel | View | Fields |
|-----------|------|--------|
| `LowerThirdViewModel` | `IsuLowerThirdView` | `skaterName`, `leftText`, `centerText`, `rightText` |
| `TechnicalViewModel` | `IsuTechnicalPaneView` | `skaterName`, `elementName`, `baseValue`, `goeValue`, `totalValue`, `boxModes: [ElementBoxView.Mode]`, `showsElementBox: Bool` |

## Element box row

`IsuTechnicalPaneView.showsElementBox` (set from `TechnicalViewModel.showsElementBox`) decides
whether `ElementRowView` is drawn. When it is false the row's frame becomes zero and
`ElementNameView`, `ElementScoreView` and `ProgramTotalView` stack from the top of the pane at their
usual heights, so the pane keeps its frame and aspect and the scored rows sit one box row higher on
screen. The name row takes over the box row's rounded top corners. `IsuTechnicalPaneView` draws no
background of its own, so the space the row vacates is invisible.

The setting lives in the view model, not on the view alone, because `VideoOverlay.Mode` equality is
the slide cache key and a chunk's content identity: two modes differing only in `showsElementBox`
have to compare different.

## ElementBoxView.Mode

| Case | Visual | Meaning |
|------|--------|---------|
| `.unscored` | Default | Element not yet scored |
| `.positive` | Green | GOE ≥ 0 |
| `.negative` | Red | GOE < 0 |
| `.neutral` | Default | Base value is 0 |

## Dependencies

- Uses only Apple frameworks: `UIKit`, `CoreImage` (via `CIImage` from callers)
