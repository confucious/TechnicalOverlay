# Layout Engine Module

**Source:** `LayoutEngine/LayoutEngine/`

A UIKit-based view library that renders figure skating scoring overlays, designed to be rasterized to `CIImage` for video compositing. No SwiftUI — pure UIKit `UIView` hierarchy.

## File Map

| File | Role |
|------|------|
| `LayoutEngine.swift` | Shared constants: `Color` (named overlay colors), `Metrics` (layout proportions, plus `borderInset(for:)` and `fontSize(for:)` for the row arithmetic), `CornerDirection` enum, `UIView` extensions (`cornerRadius()`, `roundedCornerConfiguration(corners:)`). |
| `OverlayView.swift` | Base class for the overlay's views. Programmatic only: the storyboard initializer is marked unavailable here, and every row inherits that instead of repeating a `fatalError` stub. |
| `LabelBoxView.swift` | `LabelBoxView` + `LabelBoxGeometry` — a background with one label inset inside it, sized in proportions of its own height. Every single-label row is one of these (the lower third's name line, the element name, both halves of the score row and of the total row), so the border arithmetic and the font sizing live in one place. `cornerRadiusSource` picks whether the corner radius follows the box's height or the row's, and `fontScale` sizes the text for less than the label's height — for a row taller than its neighbours that keeps their text size. |
| `VideoOverlay.swift` | Main overlay container `UIView` (1280x720 base). Holds both technical panes — `IsuTechnicalPaneView` and `Isu2026TechnicalPaneView` (top-left, the one `TechnicalViewModel.style` names) — and `IsuLowerThirdView` (bottom-center). `Mode` enum (`none`, `technicalPane`, `lowerThirdPane`). `render(size:)` → `CIImage`. |
| `IsuLowerThirdView.swift` | Skater introduction overlay with two lines: `UpperLineView` (skater name on blue) + `LowerLineView` (left/center/right text on dark gray). |
| `IsuTechnicalPaneView.swift` | The classic technical scoring overlay and its `TechnicalViewModel` + `TechnicalPaneStyle`: four subcomponents (`ElementRowView`, `ElementNameView`, `ElementScoreView`, `ProgramTotalView`) and a `RowOrder` (`boxesFirst` for *Classic*, `totalFirst` for *Classic 2*). The box row is optional (`showsElementBox`). |
| `Isu2026TechnicalPaneView.swift` | The ISU 2026 technical overlay: five flush rows, running total first and the element boxes last. Holds the same `TechnicalViewModel`; the box row is optional on the same terms. |
| `TechnicalPaneComponents/ElementBoxView.swift` | Single colored box with modes: `unscored`, `positive`, `negative`, `neutral`, drawn in one of two palettes (`ElementBoxView.Style`: classic or ISU 2026). |
| `TechnicalPaneComponents/ElementNameView.swift` | Element name label on black background. |
| `TechnicalPaneComponents/ElementRowView.swift` | Dynamic container that creates `ElementBoxView` instances based on `boxModes` array. Classic: touching boxes on a strip that hugs them. 2026: spaced boxes across a white row that fills the pane. |
| `TechnicalPaneComponents/Isu2026RowView.swift` | One text row of the 2026 pane: black label left, value right in a shared score column, optionally in a filled cell (the GOE row's green/red box). |
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
| `Color.isu2026Row` | white | 2026 pane rows below the name row |
| `Color.isu2026ElementRow` | white 0.87 | 2026 element-name row |
| `Color.isu2026Text` | black | 2026 pane labels and values |
| `Color.isu2026NameRow` | (0, 80, 178) | 2026 name row, the leader row's blue |
| `Color.isu2026NameRowText` | white | 2026 name and running total |
| `Color.isu2026NameRowDivider` | white 0.25 | Rule between the name and its total |
| `Color.isu2026Positive` | (47, 166, 0) | 2026 execution cell and box, GOE ≥ 0 |
| `Color.isu2026Negative` | (213, 11, 14) | 2026 execution cell and box, GOE < 0 |
| `Color.isu2026Neutral` | white 0.62 | 2026 box, base value 0 |
| `Color.isu2026Unscored` | white | 2026 box, not yet scored |
| `Color.isu2026BoxOutline` | white 0.4 | 2026 box outline |

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
| `Metrics.isu2026TechPaneHeightPercent` | 0.20 | 2026 pane height as fraction of overlay height |
| `Metrics.isu2026TechPaneAspectRatio` | 2.3 | 2026 pane width/height ratio |
| `Metrics.isu2026NameRowFontSizeIncrease` | 1 | Points the 2026 name row's text exceeds the block's |
| `Metrics.isu2026FontPercent` | `0.75 × (1 - 2 × 0.3 × borderPercent)` | A row's text size as a fraction of its height |
| `Metrics.isu2026NameRowExtraHeight` | `isu2026NameRowFontSizeIncrease / isu2026FontPercent` | Height the name row adds to carry its larger text |
| `Metrics.isu2026NameRowGapPercent` | `isu2026ChipPercent × isu2026BoxGapPercent` | Clear gap under the 2026 name row — the chips' own hairline |
| `Metrics.isu2026NameRowWidthPercent` | 1.15 | 2026 name row width, as a fraction of the pane's |
| `Metrics.isu2026BoxRowPercent` | 0.85 | 2026 box row, relative to one of its text rows |
| `Metrics.isu2026MainRowPercent` | `1/(1 + Gap + 3 + BoxRow)` | One 2026 text row below the name row, as a fraction of the pane less the name row's extra height |
| `Metrics.isu2026BoxInsetPercent` | 0.15 | 2026 box inset from its row's top and bottom |
| `Metrics.isu2026BoxGapPercent` | 0.1 | 2026 gap between boxes, as a fraction of a box (a hairline) |
| `Metrics.isu2026ChipPercent` | `isu2026BoxRowPercent × (1 - 2 × isu2026BoxInsetPercent)` | A 2026 chip's width, as a fraction of a text row |

## View Hierarchy

```
VideoOverlay (1280x720 base frame)
├── IsuTechnicalPaneView          (top-left, 16% height, 2.65 aspect ratio — .boxesFirst)
│   ├── ElementRowView            (top row: colored element boxes)
│   ├── ElementNameView           (element name label, black bg — a LabelBoxView)
│   ├── ElementScoreView          (base value left, GOE right — two LabelBoxViews)
│   └── ProgramTotalView          (skater name blue-left, total pink-right — two LabelBoxViews)
├── IsuTechnicalPaneView          (same frame — .totalFirst, "Classic 2")
│   └── the same four rows, from the running total down to the boxes
├── Isu2026TechnicalPaneView      (same corner, 20% height, 2.3 aspect ratio)
│   ├── Isu2026RowView ×4         (total, element name, base value, GOE — in that order)
│   └── ElementRowView            (bottom row: element boxes, .isu2026 palette)
└── IsuLowerThirdView             (bottom-center, 15% height, 8.5 aspect ratio)
    ├── UpperLineView             (skater name on blue bg — a LabelBoxView)
    │   └── box → label
    └── LowerLineView             (left/center/right text on dark gray bg)
        └── backgroundView → centerLabel, leftLabel, rightLabel
```

Every single-label row is a `LabelBoxView`. Its `LabelBoxGeometry` gives the background's inset from
the row and the label's inset inside the background, both as multiples of
`Metrics.borderInset(for: rowHeight)`; the label's font is `Metrics.fontSize(for: labelHeight)`. The two
rows that split into boxes (`ElementScoreView`, `ProgramTotalView`) place their boxes themselves and
take the corner radius from the row's height rather than the box's. `LowerLineView` keeps its own
layout — its centre label is measured and the other two fill the space beside it.

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
| `TechnicalViewModel` | `IsuTechnicalPaneView` / `Isu2026TechnicalPaneView` | `skaterName`, `elementName`, `baseValue`, `goeValue`, `totalValue`, `boxModes: [ElementBoxView.Mode]`, `showsElementBox: Bool`, `style: TechnicalPaneStyle` |

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

## Pane styles

`TechnicalPaneStyle` (`classic`, `classic2`, `isu2026`) picks which pane draws a `TechnicalViewModel`;
the style is a field of the view model for the same reason `showsElementBox` is — the mode is the cache
key and the chunk's content identity. `VideoOverlay` holds one pane per style and shows the one the
mode names, so a style change re-renders; nothing switches a pane in place.

**Classic 2 is the classic pane reordered, not a third design.** `IsuTechnicalPaneView.RowOrder`
decides where the box row sits — `boxesFirst` (boxes, name, score, total) or `totalFirst` (total, name,
score, boxes) — and nothing else changes: same four components, same palette, same `Metrics`, same pane
frame and aspect, same one-border gaps between rows. One layout serves both, so the two orders cannot
drift apart; the only order-dependent code is the frames and which row takes the outer corners.

`Isu2026TechnicalPaneView` is five rows, top to bottom:

1. **Name row** — skater name (left) and running total (right), in the broadcast leader row's blue with
   white text and a rule between name and total. It is not one more row of the block: its text is **one
   point larger** than the rows below it, and its height is **proportional to that text** — a row's text
   is `Metrics.isu2026FontPercent` of its height, so the row is taller by exactly
   `Metrics.isu2026NameRowExtraHeight`. It overhangs the block by 15% of the pane's width, and only the
   chips' own hairline separates it from it.
2. Element name — light-gray row, black text, left-aligned; the only row with no value.
3. `BASE VALUE:` and the base value (with its bonus, as the classic pane formats it) — white row.
4. `EXECUTION:` and the GOE, in a cell filled green or red by the value's sign — white row, white value.
5. The element boxes — **no row background**; the boxes alone sit over the video, packed from the
   row's left inset as a strip of square chips with a hairline between them (they shrink only if that
   many would not fit the row's width), and an empty slot is white inside a mid-gray outline so it
   reads against a light frame.

Rows 2–5 are flush, because the graphic's are: two neighbouring white rows read as one block with the
green/red cell cutting across it. Their values share one column (`Isu2026RowView.valueColumnPercent`) so
they line up down the pane; the name row's total is right-aligned in its own wider row instead.

The broadcast graphic's leader *row above the pane*, flag and `TECHNICAL SCORE` header are not drawn:
this pane is only the current element's block, with the leader row's styling reused for its first row.

The 2026 pane's height and aspect (`Metrics.isu2026TechPaneHeightPercent`, `…AspectRatio`) are its own:
it carries one more row than the classic pane, and at the classic pane's height its text would be a
third smaller. Both panes hang off the same top-left corner.

Hiding the element boxes leaves the 2026 pane's bottom row out of the layout — the rows above it keep
their place and the unused space below the execution row stays clear, rather than the rows moving up as
they do in the classic pane (where the box row is on top).

## ElementBoxView.Mode

| Case | Visual | Meaning |
|------|--------|---------|
| `.unscored` | Default | Element not yet scored |
| `.positive` | Green | GOE ≥ 0 |
| `.negative` | Red | GOE < 0 |
| `.neutral` | Default | Base value is 0 |

`ElementBoxView.Style` picks the palette the four modes are drawn in. Classic: filled grey means
unscored, dark grey means neutral, and the box's one-point border is black. ISU 2026: an unscored box is
**white inside a mid-gray outline** — the row behind it is transparent, so the outline is what gives the
slot its edge on a light frame — and the filled colors come from the `Color.isu2026*` set rather than
the classic `positive`/`negative`.

## Dependencies

- Uses only Apple frameworks: `UIKit`, `CoreImage` (via `CIImage` from callers)
