# Element Abbreviation Expansion (Singles)

**Source:** `LayoutEngine/ProtocolParser/ProtocolParser/` (planned — nothing is in the tree yet)

Status: **Design complete — every rule settled; no code written.** This document
specifies the deferred translator of `docs/architecture/protocol-parser.md` §9 (an abbreviation →
display-name component with an identity default). It covers **singles only**: the jump, spin,
step-sequence and choreographic vocabulary of the singles protocol. Pairs and ice-dance codes are
deliberately out of scope (§8) and currently pass through unchanged. **Every rule is settled**: §4 is
the specification and §5 the worked examples.

## 1. Purpose

Turn a raw protocol abbreviation (`3Tb1+2T`, `2Lz<<`, `CCoSpBV`, `StSq4b0.5+kpYYYY`) into the name
shown on the overlay and in the scoring list (`3 Toeloop + 2 Toeloop`, `2 Lutz`,
`Change Combination Spin BV`, `Step Sequence 4`).

**In scope:** singles element codes — jumps, jump combinations/sequences, solo and combination
spins, step sequences, choreographic sequence/spin; the markers and call tokens that appear on a
published protocol.

**Out of scope (explicitly):**

- **Pairs and ice dance** codes (`3Tw3`, `5ALi4`, `BoDs2`, `ChPSp1`, `PiF1`, …). Unrecognized tokens
  pass through verbatim, so pairs rows behave exactly as they do today (§8).
- **Values.** The expansion never touches `baseValue` / `goeValue` / `bonusValue`; the bonus marker
  `b1` is dropped from the *name* only, because the value already arrives in the `ref` column
  (`protocol-parser.md` §5.2).
- **Reading the `info` column.** Under-rotation/fall/edge markers are already excluded from the
  abbreviation's source data — that column is never parsed (`protocol-parser.md` §10a).
- Any language other than English.

## 2. Input

### 2.1 The string being expanded

`ProtocolElement.abbreviation` — the element cell exactly as published, entity-decoded by the parser
(`protocol-parser.md` §4.2). Decoding matters here: `<` and `<<` reach the expander as literal
characters, never as `&lt;`:

```html
<TD class=elem>2Lz&lt;&lt;</TD>   →  2Lz<<
<TD class=elem>3Tb1+2T</TD>      →  3Tb1+2T
```

### 2.2 Real shapes, quoted from the fixtures

| Shape | Real examples from the ten fixture pages' singles rows |
|---|---|
| jump, numbered | `3T`, `2Lz`, `1A`, `3A`, `4T` |
| jump + bonus | `3Tb1`, `3Sb1`, `3Lob1`, `3Lz<b1`, `3Fb1` |
| jump + rotation/edge marker | `2A<`, `3Lo<<`, `2Lz!`, `2Lze`, `2F!`, `3Lzq`, `1Lze` |
| jump + invalid flag | `1Lz*`, `1A*`, `1T*`, `2S*` |
| combination / sequence | `3Tb1+2T`, `3F+3Tb1`, `2A+Eu+2F`, `3S+1A+2T+SEQ`, `2Lz+SEQ+1A*+2Lo*` |
| call tokens | `+SEQ`, `+COMBO`, `+REP` (`2Lz+COMBO`, `2Fq+REP`, `3Lo+REP`, `T+COMBO+2T*+REP`, `3S+1A+2T+SEQ`) — only `SEQ` reaches the output (§4.5) |
| dangling jump | `A`, `A*`, `T`, `Lo*`, `Lz*` (the jump through which a repeat fell apart) |
| spin | `CCoSp4`, `FSSp3`, `CCoSp1V`, `CCoSpBV`, `CSp2`, `CoSp`, `FSSp` |
| step sequence | `StSq2+kpYNNN`, `StSqB+kpNNNN`, `StSq4b0.5+kpYYYY` |
| choreographic | `ChSq1`, `ChSp1`, `pChSq1` |

### 2.3 Tokenization

**Split on `+` first.** Every abbreviation is a `+`-joined token list; the tokens are the unit the
rules operate on. Two consequences visible in the fixtures:

- `+kp…` is a **separate token** (`StSq4b0.5` + `kpYYYY`), not a suffix of the `StSq` token — so
  "ignore the `+kp` addition" is a token-drop rule, not a string trim.
- In `2Lz+SEQ+1A*+2Lo*` a call token sits **between** jumps, so `SEQ` keeps its position in the
  joined output rather than being moved to the end (§4.5).

### 2.4 Traps that decide the implementation

| # | Trap | Evidence |
|---|---|---|
| 1 | **`q` is both a marker and a letter of `StSq`/`ChSq`.** Stripping marker characters as a blanket character class turns `StSq2` into `StS2` and `ChSq1` into `ChS1`, and those tokens then fail to classify (the throwaway prototype did exactly this before it was corrected). Markers are a **suffix on a jump token only**. | `StSq2` ×21, `ChSq1` ×16 |
| 2 | **The bonus marker is not positionally fixed.** `b1` follows the jump (`3Tb1`) but also follows a marker (`3Lz<b1`, `3S<b1`), so stripping "marker then bonus" in a fixed order fails on 4 tokens. | `3Lz<b1` ×2, `3S<b1` ×2 |
| 3 | **Spin codes are prefixes of each other and end in `Sp`.** `CSp` ⊂ `CCSp`, `SSp` ⊂ `FSSp`/`CSSp`, `CoSp` ⊂ `CCoSp`/`FCoSp`, `CSp` ⊂ `FCSp`. Classification must match the **longest known code first**, whole-token. | 34 distinct spin tokens |
| 4 | **A jump letter alone is not a jump.** `S` is also the tail of `SSp`/`FSSp`/`CSSp`, `F` of `FSSp`, `T` of `StSq`(no) but `Tw`/`Th` in pairs. Jump matching may only run on a token that did not match the spin/step/choreographic table, and the remainder after the jump code must be **markers only** — otherwise `3STh` (a throw) would expand as a Salchow. | `3STh` in the pairs fixtures |
| 5 | **A jump token can have no rotation number.** `A`, `T`, `A*`, `Lo*`, `Lz*` — the requirement's rule assumes a number exists. | 5 tokens / 11 rows |
| 6 | **`Eu` carries no number.** Only the bare `Eu` appears (4 tokens); the rule below is stated so a hypothetical `1Eu` still renders `Euler`. | `Eu` ×4, no `1Eu` |

## 3. Reference fixtures and the measured inventory

Source: the committed segment pages under
`LayoutEngine/ProtocolParser/ProtocolParserTests/Fixtures/`, singles pages only —
`SEGM001`, `SEGM011`, `SEGM015`, `SEGM021`, `SEGM034`. These are the pages the parser doc already
lists as parsed and invariant-checked (`protocol-parser.md` §3, §12).

| Measure | Count |
|---|---|
| Element rows (singles) | **535** |
| Distinct abbreviations | **187** |
| Distinct `+`-separated tokens | **119** |
| Tokens that are jumps | 460 |
| Tokens that are spins | 126 |
| Tokens that are step sequences / choreographic | 94 |
| `SEQ` tokens (kept in the expansion) | 38 |
| `COMBO` / `REP` tokens (dropped, §4.5) | 6 + 8 |
| Tokens to be dropped (`kp…`) | 47 |
| Rows carrying at least one marker or bonus (`<`/`<<`/`!`/`e`/`q`/`*`/`b…`) | 157 of 535 |
| Rows whose every token the rules below classify once `kp…` is dropped | **535 / 535** |
| Rows whose expansion changes when `COMBO`/`REP` are dropped rather than shown | 13 of 535 |
| Abbreviation length → expansion length | mean 5.7 → 15.4 chars; max 18 → 50 |

Marker census over those 535 rows (`<` 42 rows, `<<` 8, `!` 10, `e` 6, `q` 9, `*` 12, `b1`/`b0.5` 18)
is why §4.6 ignores markers rather than rejecting a row.

## 4. Expansion model

### 4.1 Pipeline

```
abbreviation
  └─ split on "+"                             → [token]
       └─ per token: strip "*" (remember it), strip b<digits>[.<digits>] anywhere, strip trailing
          marker run
            ├─ token is "SEQ"                           → keep the token verbatim
            ├─ token is "COMBO" | "REP"                 → drop the token entirely
            ├─ token starts with kp                    → drop the token entirely
            ├─ token matches StSq / ChSq / ChSp / pChSq → §4.4
            ├─ token matches a spin code (longest first) → §4.3
            ├─ token matches <number?> <jump code> + markers-only tail → §4.2
            └─ nothing matched                          → keep the raw token verbatim (§4.9)
  └─ join the surviving parts with " + "
```

Classifier ordering is a correctness requirement, not a style choice — see traps 1, 3 and 4 (§2.4).

### 4.2 Jumps

`<revolutions> <jump name>`, with the number always shown and `Euler` the exception.

| Code | Name | Code | Name |
|---|---|---|---|
| `S` | Salchow | `A` | Axel |
| `T` | Toeloop | `F` | Flip |
| `Lo` | Loop | `Eu` | Euler |
| `Lz` | Lutz | | |

- `3S` → `3 Salchow`; `2Lz` → `2 Lutz`; `1A` → `1 Axel`; `4T` → `4 Toeloop`.
- **`Eu` never takes a number**: `Eu` → `Euler`, never `1 Euler`. It never takes a *different*
  number either — the token is a rotation-free marker between two jumps.
- Longest code first: `Lo`/`Lz` before `S`/`T`/`A`/`F` (so `Lo` is not read as `L`+…, and `2Lz` is
  not `2L`+`z`). The tail after the code must be markers only (trap 4).
- A token with **no** rotation number expands to the bare name: `A` → `Axel`, `Lo*` →
  `Loop (Invalid)`.

### 4.3 Spins

`<spin name> <level>` with `V` (reduced value) appended after the level. The level is one of
`B`, `1`, `2`, `3`, `4`.

| Code     | Name                           | In the fixtures                                                          |
| -------- | ------------------------------ | ------------------------------------------------------------------------ |
| `USp`    | Upright Spin                   | —                                                                        |
| `LSp`    | Layback Spin                   | —                                                                        |
| `CSp`    | Camel Spin                     | ✅ `CSp2`                                                                 |
| `SSp`    | Sit Spin                       | ✅ `SSp1`, `SSp2`, `SSpB`                                                 |
| `FUSp`   | Flying Upright Spin            | —                                                                        |
| `FLSp`   | Flying Layback Spin            | —                                                                        |
| `FCSp`   | Flying Camel Spin              | ✅ `FCSp2`, `FCSp3`, `FCSp4`                                              |
| `FSSp`   | Flying Sit Spin                | ✅ `FSSpB`, `FSSp1`…`FSSp4`, `FSSp`                                       |
| `CUSp`   | Change Upright Spin            | —                                                                        |
| `CLSp`   | Change Layback Spin            | —                                                                        |
| `CCSp`   | Change Camel Spin              | ✅ `CCSpB`, `CCSp2`…`CCSp4`, `CCSp`                                       |
| `CSSp`   | Change Sit Spin                | ✅ `CSSpB`, `CSSp2`, `CSSp4`, `CSSp`                                      |
| `FCUSp`  | Flying Change Upright Spin     | —                                                                        |
| `FCLSp`  | Flying Change Layback Spin     | —                                                                        |
| `FCCSp`  | Flying Change Camel Spin       | —                                                                        |
| `FCSSp`  | Flying Change Sit Spin         | —                                                                        |
| `CoSp`   | Combination Spin               | ✅ `CoSp`                                                                 |
| `CCoSp`  | Change Combination Spin        | ✅ `CCoSpB`…`CCoSp4`, `CCoSp1V`, `CCoSp2V`, `CCoSp3V`, `CCoSpBV`, `CCoSp` |
| `FCoSp`  | Flying Combination Spin        | —                                                                        |
| `FCCoSp` | Flying Change Combination Spin | ✅ `FCCoSp3`, `FCCoSp4`                                                   |

("—" = a valid ISU code that does not occur in these five pages; it must still be in the table, since
a singles protocol may use it. The list is the ISU singles abbreviation set.) 34 distinct spin
tokens appear, and they justify every entry on the ✅ rows.

Behaviour:

- `CCoSp4` → `Change Combination Spin 4`; `CSp2` → `Camel Spin 2`; `FSSpB` → `Flying Sit Spin B`.
- **`V` follows the level as printed**, including the `B` level: `CCoSp1V` → `…Spin 1V`,
  `CCoSpBV` → `…Spin BV`.
- **No level** → the name alone, nothing appended: `CoSp` → `Combination Spin`, `CCSp` →
  `Change Camel Spin`. These are the uncredited rows the parser already imports with zero values
  (`protocol-parser.md` §6) — the site prints the code with no level for them.
- `V` where no level is present: not observed; the grammar allows `(B-4)V`, so the same rule covers it.

### 4.4 Step sequences and choreographic elements

| Code          | Expansion                | Notes                                                                        |
| ------------- | ------------------------ | ---------------------------------------------------------------------------- |
| `StSq<level>` | `Step Sequence <level>`  | level `B`, `1`–`4`. `StSqB` → `Step Sequence B`, `StSq4` → `Step Sequence 4` |
| `ChSq1`       | `Choreographic Sequence` | the trailing `1` is not shown                                                |
| `ChSp1`       | `Choreographic Spin`     | the trailing `1` is not shown                                                |
| `pChSq1`      | `Choreographic Sequence` | neither the `p` prefix nor the trailing `1` is shown                         |

- `StSq…b0.5` carries a bonus marker: `StSq4b0.5` → `Step Sequence 4`.
- The `+kp…` token is dropped (§4.6), so `StSq2+kpYNNN` → `Step Sequence 2` with **no dangling
  separator**. 47 of the 535 rows carry a `kp…` token.

### 4.5 Call tokens: only `SEQ` is shown

| Token | Rule | Example |
|---|---|---|
| `SEQ` | kept in place, uppercase as published, separated by the same ` + ` | `3S+1A+2T+SEQ` → `3 Salchow + 1 Axel + 2 Toeloop + SEQ` |
| `COMBO` | **dropped entirely** | `2Lz+COMBO` → `2 Lutz` |
| `REP` | **dropped entirely** | `3Lo+REP` → `3 Loop` |

`COMBO`/`REP` are calls the technical panel made about a jump that fell apart or was repeated, not
elements; the user wants only the sequence marker shown. Dropping them leaves no dangling separator
and no empty token, so a bare `2Lz+COMBO` collapses to `2 Lutz`, and
`T+COMBO+2T*+REP` → `Toeloop + 2 Toeloop (Invalid)`. This changes the expansion of **13 of the 535**
singles rows (§3), and interactively: `SEQ` stays where it sits, even mid-abbreviation
(`2Lz+SEQ+1A*+2Lo*` → `2 Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)`).

### 4.6 Ignored tokens and markers

| Ignored | Meaning on the protocol | Rule |
|---|---|---|
| `b1`, `b0.5` | bonus for a difficult element | stripped from the name anywhere in the token; the value is already in `bonusValue` |
| `<` | under-rotated | stripped (trailing marker run) |
| `<<` | downgraded | stripped |
| `!` | unclear edge | stripped |
| `e` | wrong edge | stripped |
| `q` | quarter-short of rotation | stripped |
| `kpNNNN`, `kpYNNN`, … | step-sequence key points | the whole token is **dropped** |
| `COMBO`, `REP` | call tokens for a broken/repeated combination (§4.5) | the whole token is **dropped** |

### 4.7 The invalid flag `*`

`*` marks an element the panel did not credit (a repeat beyond the allowance). It is rendered as
`(Invalid)` **on the token it belongs to**:

| Input | Output |
|---|---|
| `1Lz*+COMBO` | `1 Lutz (Invalid)` |
| `2Lz+SEQ+1A*+2Lo*` | `2 Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)` |
| `3Sb1+COMBO+1T*` | `3 Salchow + 1 Toeloop (Invalid)` |
| `A*` | `Axel (Invalid)` |

### 4.8 Joining

Surviving parts are joined with **` + `** (one space on each side) — the requirement's separator,
applied after markers are stripped and the `kp…`, `COMBO` and `REP` tokens are dropped, so no
separator is left dangling and no empty part is emitted: `StSq4b0.5+kpYYYY` → `Step Sequence 4`,
`2Lz+COMBO` → `2 Lutz`, and never `Step Sequence 4 + ` or `2 Lutz + `.

### 4.9 Unknown tokens

A token that matches nothing (pairs/ice-dance codes, a call the site invents, a future code) is kept
**verbatim**, so the expansion degrades to today's behaviour rather than failing the import. This is
also what makes the pairs rows safe (§8), and why an unrecognized prefix (`pChSq1`) is a documented
table entry rather than a guess.

## 5. Worked examples

Produced by the throwaway prototype of §4 over the real fixture strings (§10):

| Abbreviation       | Expansion                                            |
| ------------------ | ---------------------------------------------------- |
| `3S`               | `3 Salchow`                                          |
| `3Tb1+2T`          | `3 Toeloop + 2 Toeloop`                              |
| `2F+Eu+3S<`        | `2 Flip + Euler + 3 Salchow`                         |
| `3Lz<b1`           | `3 Lutz`                                             |
| `3Lz!+2T`          | `3 Lutz + 2 Toeloop`                                 |
| `2Lo+2Tq`          | `2 Loop + 2 Toeloop`                                 |
| `1Lz*+COMBO`       | `1 Lutz (Invalid)`                                   |
| `T+COMBO+2T*+REP`  | `Toeloop + 2 Toeloop (Invalid)`                      |
| `2Lz+COMBO`        | `2 Lutz`                                             |
| `3Lo+REP`          | `3 Loop`                                             |
| `2Lz+SEQ+1A*+2Lo*` | `2 Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)` |
| `3S+1A+2T+SEQ`     | `3 Salchow + 1 Axel + 2 Toeloop + SEQ`               |
| `4T`               | `4 Toeloop`                                          |
| `3A`               | `3 Axel`                                             |
| `StSqB+kpNNNN`     | `Step Sequence B`                                    |
| `StSq4b0.5+kpYYYY` | `Step Sequence 4`                                    |
| `ChSq1`            | `Choreographic Sequence`                             |
| `ChSp1`            | `Choreographic Spin`                                 |
| `pChSq1`           | `Choreographic Sequence`                             |
| `CoSp`             | `Combination Spin`                                   |
| `CCoSpBV`          | `Change Combination Spin BV`                         |
| `CCoSp1V`          | `Change Combination Spin 1V`                         |
| `FCCoSp4`          | `Flying Change Combination Spin 4`                   |
| `CSp2`             | `Camel Spin 2`                                       |

## 6. Public API

The seam is the one already specified in `protocol-parser.md` §9 — a small protocol with an identity
default, so its absence is not a failure mode:

```swift
public protocol ElementNameTranslating: Sendable {
    func displayName(for abbreviation: String) -> String    // default: the abbreviation, unchanged
}
```

Placement: **`ProtocolParser`**, alongside the importer. The module already owns the abbreviation
vocabulary (`ProtocolElement.abbreviation`) and the fixtures that test it; the app owns display
policy. The expander is a pure, `nonisolated`, `Sendable` value transform with no I/O, no state and
no dependency on the HTML parser, so it tests on strings alone — the same shape as
`ProtocolHTMLParser` and for the same reason (every target is MainActor-isolated by default;
`ProtocolParser.swift`'s model types must stay reachable off the main actor).

```swift
public struct ElementNameExpander: ElementNameTranslating {
    public init()
    public func displayName(for abbreviation: String) -> String
}
```

**No failure mode.** An unclassifiable token is not an error — it is returned verbatim (§4.9), so
this component cannot fail an import and needs no error type.

## 7. Integration with the app

Chain: `ProtocolElement.abbreviation` → `ElementNameExpander` → `ElementData.name`
(the mapping point is the existing `ElementData.init(_ element: ProtocolElement)`, i.e. the import).

Consequences to be aware of:

- **The raw abbreviation is not retained.** `ElementData` has only `name` (`OverlayData.swift:276`);
  after import the code is gone, so a rule change here means re-importing to see it. Keeping the code
  on the model is **out of scope** — it would touch the persisted model and its
  `version` (`docs/ARCHITECTURE.md` §4), so it is not a silent addition.
- **Names get much longer.** Mean 5.7 → 15.4 characters, worst case 18 → 50
  (`2Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)`). The overlay's element-name row is laid out
  from `Metrics`: at a 1280×720 overlay the pane is 16% of the height with a 2.65 aspect
  (≈ 305 × 115 px), the name row is the full pane width and ≈ 28 px tall, and the label font is
  0.75 × row height (≈ 21 pt) with `adjustsFontSizeToFitWidth` + `numberOfLines = 1`
  (`ElementNameView.swift:25-26`). So a long expansion **shrinks rather than truncates** — it stays
  complete, it gets smaller. Those figures are computed from `Metrics`, not measured on screen —
  worth checking on screen before making the overlay's form terser than the list's.
- **The scoring list is the other consumer** — the same `name` string is edited by hand in
  `ScoringListView`, so an expansion of 50 characters is also a 50-character text field value.
- **`renderingHash` covers `name`**, so expanding a name invalidates the cached slides/chunks for
  that element as any other data change does (`docs/ARCHITECTURE.md` §3.4).
- **Manifest:** none — the component lives in a target the app already links (no new file target, no
  new package).

## 8. Deferred: pairs and ice dance

The same component will eventually cover pairs (`3Tw3`, `3STh`, `5ALi4`, `BoDs2`, `ChPSp1`, `PiF1`)
and ice dance. Until then the rules must not *mis*-expand them, which is why §2.4 trap 4 requires a
markers-only tail after a jump code and §4.9 keeps unknown tokens verbatim: `3STh` → `3STh`,
`5ALi4` → `5ALi4`, `1Li3` → `1Li3`. The pairs vocabulary measured in the same fixture set is 66
distinct abbreviations (`protocol-parser.md` §9), disjoint from the 187 singles ones apart from
shared jumps.

## 9. Testing

Pure string tests — no fixtures needed for the table itself; the sweep uses the committed pages.

| # | Test | Expectation                                                                                                                                                            |
|---|---|---|
| 1 | Jumps and numbers | `3S` → `3 Salchow`, `2Lz` → `2 Lutz`, `1A` → `1 Axel`, `4T` → `4 Toeloop`                                                                                              |
| 2 | Euler | `Eu` → `Euler`; `2A+Eu+2F` → `2 Axel + Euler + 2 Flip`; never `1 Euler`                                                                                                |
| 3 | Separator | every `+` becomes ` + `; no dangling separator when `kp…` is dropped                                                                                                   |
| 4 | Bonus ignored, both positions | `3Tb1+2T` → `3 Toeloop + 2 Toeloop`; `3Lz<b1` → `3 Lutz`                                                                                                               |
| 5 | Markers ignored | `2A<`, `3Lo<<`, `2Lz!`, `2Lze`, `3Lzq`, `1Lze` all strip to the plain name                                                                                             |
| 6 | Invalid flag | `1Lz*+COMBO` → `1 Lutz (Invalid)`; two `*` in one row both flagged                                                                                                     |
| 7 | Call tokens | `SEQ` kept in place; `COMBO` and `REP` dropped with no dangling separator or empty token (`2Lz+COMBO` → `2 Lutz`, `T+COMBO+2T*+REP` → `Toeloop + 2 Toeloop (Invalid)`) |
| 8 | Step sequences | `StSqB+kpNNNN` → `Step Sequence B`; `StSq4b0.5+kpYYYY` → `Step Sequence 4`                                                                                             |
| 9 | Choreographic | `ChSq1` → `Choreographic Sequence`; `ChSp1` → `Choreographic Spin` (no digit); `pChSq1` → `Choreographic Sequence` (no prefix, no digit)                               |
| 10 | Spins | `CCoSp4`, `CCoSp1V`, `CCoSpBV`, `FCCoSp4`, `CSp2`, `SSpB`                                                                                                              |
| 11 | Longest-match spin codes | `CCSp3` is not `CSp`…; `FSSp3` is not `SSp`…; `SSp2` is not a Salchow                                                                                                  |
| 12 | Pairs codes untouched (regression) | `3STh`, `3Tw3`, `5ALi4`, `BoDs2`, `ChPSp1` returned verbatim                                                                                                           |
| 13 | Trap regressions (§2.4) | `StSq2`/`ChSq1` survive the `q` marker rule; `3Lz<b1` strips                                                                                                           |
| 14 | **Sweep over the five singles fixtures** | 535/535 rows expand with zero verbatim-passthrough tokens once `kp…` is dropped (the number §3 freezes); any row that regresses to passthrough fails the test          |
| 15 | Identity default | a type conforming without implementing anything returns the abbreviation unchanged (`protocol-parser.md` §9)                                                           |

## 10. Verification performed (2026-10-15)

- Extracted all **535** singles element cells from the five committed singles fixtures
  (`SEGM001`, `SEGM011`, `SEGM015`, `SEGM021`, `SEGM034`) — 187 distinct abbreviations, 119 distinct
  `+`-separated tokens — and built the token census in §3 from those bytes, not from a rendered view.
- Wrote a throwaway prototype of §4 (Python, scratch) and ran it over every row: with `kp…` dropped,
  **535 / 535 rows classify completely, 0 unclassified tokens**; every example in §5 is that
  prototype's real output.
- The prototype is what found the `q`-vs-`StSq`/`ChSq` collision (§2.4 trap 1) and the
  bonus-after-marker order (`3Lz<b1`, trap 2) — both silently mis-expanded `StSq*`/`ChSq*` and
  `3Lz<b1` in its first version.
- **Rules settled and re-measured 2026-10-15** after the naming pass: `COMBO` and `REP` are dropped
  with only `SEQ` shown (§4.5) — **13 of the 535 rows** change against keeping them (6 with `COMBO`,
  8 with `REP`, one row carrying both); the `ChSq1`, `ChSp1` and `pChSq1` digits are not shown (§4.4);
  and the spins use the short names of §4.3 (`Change…` rather than `Change Foot…`). Prototype re-run
  over every row with all of it applied: still **535 / 535** rows classify with 0 passthrough tokens,
  and the mean expansion is **15.4** characters (16.2 with `Change Foot…`, 17.3 with the call tokens
  shown) — worst case 50 either way.
- Checked each spin code in §4.3 against the ISU singles abbreviation list; the ✅ column is which
  codes actually occur in the fixtures, and the "—" rows are codes from that list that do not.
- Not verified: **pairs and ice dance** (the pairs codes are enumerated in
  `protocol-parser.md` §9 but no rules were designed for them); **`q`/`V` semantics** (taken from
  ISU communications, not measured — they only decide what gets ignored, never the values);
  **the on-screen fit** of the longest expansions — the numbers in §7 are computed from
  `Metrics`, not measured on a rendered overlay.

## 11. Dependencies

- **None** beyond the Swift standard library. The expander is string tables and a classifier; no new
  package, no new module, no manifest change (`docs/ARCHITECTURE.md` §2.2 policy not exercised).
