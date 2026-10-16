# Protocol Parser Module

**Source:** `LayoutEngine/ProtocolParser/ProtocolParser/`

Status: **Implemented.** The module, its 39 tests, the committed fixtures and the SwiftSoup
dependency are in place; the app-side merge (§8.1) is implemented and tested, and the import flow
that drives it from `ScoringListView` (§8.2) is wired. This document is the authoritative
specification for the module.

## 1. Purpose

Import a skater's **executed elements** from a published competition protocol page so the user
does not have to retype an entire element list into `ScoringListView`. The output is a value type
carrying the raw element abbreviation plus base value / GOE / bonus in **integer hundredths** —
the units `ElementData` uses — with a thin app-side mapper into `OverlayData.elementScores`.

**In scope:** locate the protocol page, isolate one skater, read that skater's element table,
convert it to values.

**Out of scope (explicitly):**
- Translating an abbreviation (`3Tb1+2T`) into a displayed name (`Triple Toeloop (bonus 1) + Double
  Toeloop`). Deferred — see §9. Until then the abbreviation is used verbatim.
- Program components, deductions, place, start number, segment/total scores beyond the per-element
  panel score (§5.2).
- Downloading/caching whole events, browsing categories, following sibling segments (§7.3).
- Any UI. The module never imports the app; the dependency points app → ProtocolParser (§8).

## 2. Input pages

Competition results are published by **ijsLive** (the pages in scope say
`<!-- Created by ijsLive 2.6.4 -->`). Two page kinds matter.

### 2.1 Leaderboard page — `CATnnnSEGnnn.html` ("the javascript webpage")

The per-(category, segment) results table. It is the page a user is most likely to have open, and
it is the page that *sometimes* carries the link to the static protocol. Anatomy (verbatim, from
the reference page):

```html
<LI class="judgeDetailRef">
<A href=SEGM034.html>Judge detail scores</A>
</LI>
```

Notes that matter for parsing:
- `href` is **unquoted** — a quoted-attribute-only matcher finds nothing here. Attribute parsing
  must accept `"…"`, `'…'` and bare values.
- The value is **relative** to the leaderboard page's directory
  (`…/results/2026/36683/`), so it must be resolved against the page URL.
- The link lives inside `<LI class="judgeDetailRef">` and its anchor text is
  `Judge detail scores`. **Four** `.html` links appear on this page (the stylesheet, the page
  itself, the sibling segment's leaderboard `CAT022SEG033.html`, and the detail link), so "first
  `.html` link" or "any link ending in `.html`" resolves to the wrong page. Anchor on
  `judgeDetailRef`.
- The page also embeds an **approximate** per-skater element table inline
  (`<TABLE class=detailScoreElm>`, inside collapsed `<TR class=child>` rows): no bonus column,
  names pre-expanded to `Triple Toeloop (bonus 1) + Double Toeloop`, no raw abbreviations.
  We deliberately **do not** parse it — see §7.4.

### 2.2 Segment detail page — `SEGMnnn.html` ("the static HTML webpage")

The page to parse; one page per segment, all skaters of that segment. Anatomy: for **each skater**,
four sibling tables in document order — `sum`, `elm`, `ded`, `maj` (68 tables = 17 skaters × 4 on
the reference page). No nesting, no `id`s, no `<DIV>`/`<SPAN>` wrappers between them.

```html
<H2 class=catseg>101_109 Champ Intermediate Men / Free Skate</H2>   <!-- category / segment -->
<TABLE class=sum>          <!-- rank, name, segment/elm/comp/ded scores -->
  <THEAD><TR><TH class=name>Name<BR>&nbsp;</TH> …</TR></THEAD>
  <TBODY><TR><TD class=rank>1</TD><TD class=name>Milo Yeon, SC of Boston</TD> …</TR></TBODY>
</TABLE>
<TABLE class=elm>          <!-- the element table (and the program-components rows) -->
  <THEAD><TR><TH class=num>#</TH><TH class=elem>Executed<BR>Elements</TH><TH class=info>I</TH>
             <TH class=bv>Base<BR>Value</TH><TH class=two></TH><TH class=goe>GOE</TH>
             <TH class=ded>&nbsp;</TH><TH class=jud>&nbsp;J1</TH> … <TH class=jud>&nbsp;J9</TH>
             <TH class=jud></TH><TH class=ref>Bonus</TH><TH class=psl>Panel<BR>Scores</TH> …</TR></THEAD>
  <TBODY>
    <TR><TD class=num>1</TD><TD class=elem>2Lz</TD><TD class=info></TD><TD class=bv>2.10</TD>
        <TD class=two></TD><TD class=goe>0.42</TD><TD class=ded>&nbsp;</TD>
        <TD class=jud>&nbsp;2</TD> … ×9 … <TD class=ref></TD><TD class=psv>2.52</TD>
        <TD class=spc></TD></TR>
    <TR><TD class=num>2</TD><TD class=elem>3Tb1+2T</TD> … <TD class=ref>1.00</TD>
        <TD class=psv>6.75</TD><TD class=spc></TD></TR>
    …
  </TBODY>
</TABLE>
```

## 3. Reference pages (fixtures)

Segment pages are listed by the **event index** (`…/results/2026/36683/index.asp`), which maps each
`<TD class="event">` (e.g. `222_231 Novice Pairs / Short Program`) to its leaderboard page. That is
the only way to discover them — the site blocks directory listing, and the detail page's name is not
derivable from the leaderboard name.

All ten detail pages below were fetched 2026-10-14 and parsed by a throwaway prototype of the
algorithm in this document; see §12 for what that verification established.

| Segment | Leaderboard page | Detail page | Skaters | Element rows |
|---------|------------------|-------------|--------:|-------------:|
| 201 Champ Preliminary Girls Grp A | `CAT001SEG001.html` | `SEGM001.html` | 15 | 120 |
| 209_215 Champ Novice Men | `CAT009SEG011.html` | `SEGM011.html` | 12 | 72 |
| 211_219 Champ Senior Men | `CAT011SEG015.html` | `SEGM015.html` | 2 | 14 |
| 217_226 Champ Senior Women | `CAT014SEG021.html` | `SEGM021.html` | 16 | 176 |
| 101_109 Champ Intermediate Men / Free Skate | `CAT022SEG034.html` | `SEGM034.html` | 17 | 153 |
| 222_231 Novice Pairs / Free Skate | `CAT017SEG026.html` | `SEGM026.html` | 3 | 27 |
| 223_230 Junior Pairs / Free Skate | `CAT018SEG028.html` | `SEGM028.html` | 3 | 27 |
| 224_229 Senior Pairs / Free Skate | `CAT019SEG030.html` | `SEGM030.html` | 2 | 20 |
| 227 Juvenile Pairs / Free Skate | `CAT020SEG031.html` | `SEGM031.html` | 9 | 63 |
| 228 Intermediate Pairs / Free Skate | `CAT021SEG032.html` | `SEGM032.html` | 5 | 45 |

Base URLs: `https://ijs.usfigureskating.org/leaderboard/results/2026/36683/`. The detail URL is
**not** derivable from the leaderboard URL by string substitution — always follow the anchor.

## 4. Parsing model

### 4.1 Approach: HTML parser, not a hand-rolled scanner

`XMLParser` is out, for a reason independent of dependencies: the pages are **not well-formed XML**
even though they declare an XHTML doctype. Both page kinds fail a strict parser on the same
construct, plus three more:

```
<H2 class=title>2026 Boston Open</H1>          <!-- mismatched end tag -->
<H2 class=catseg>…</H2><H3>Judges' Details</H2>
&nbsp;                                          <!-- undeclared entity -->
<TABLE class=sum> … border=0 cellSpacing=0     <!-- unquoted attribute values -->
```

Verified: Expat (the same well-formedness rules `XMLParser` enforces) rejects both pages —
`not well-formed (invalid token): line 14, column 12`. Pre-cleaning the page to make it XML
(normalize every tag pair, declare `nbsp`) is more code than either alternative below.

That leaves a tolerant HTML parse: **write a scanner, or take a package.** Per
`docs/ARCHITECTURE.md` §2.2 external dependencies are allowed when one gives an obvious
well-fitted benefit; this section is the measurement that decided it (§12 records the raw run).

#### Candidate survey (2026-10-14)

| Package | Fit | Maintenance | Verdict |
|---|---|---|---|
| **SwiftSoup** (`scinfu/SwiftSoup`) | Pure Swift WHATWG HTML5 parser; DOM + CSS selectors (`table.sum`, `li.judgeDetailRef a`); `text()` strips markup and decodes entities; **no package dependencies** (Foundation/Darwin only) | MIT; 5.1k ★; release 2.14.2 **two days old**; `swift-tools-version:6.0`, declares iOS 13+; compiles warning-free on Swift 6.4 | **chosen candidate** |
| Kanna (`tid-kijyun/Kanna`) | libxml2 wrapper (C library + module map) — tolerant HTML, but a system-library build dependency and a smaller API surface for our use | MIT; 2.5k ★; last release 2026-02 | runner-up, rejected on fit |
| Fuzi (`cezheng/Fuzi`) | libxml2 wrapper, XPath/CSS | MIT; 1.1k ★; last release **2020**, last push 2024-07 | effectively abandoned |
| HTMLKit (`vapor-community/HTMLKit`) | HTML *templating/dsl* engine, not a scraper | 3.0.0 **alpha** | wrong tool |

#### The spike (16 fixture pages, 825 element rows, release build)

Both approaches were implemented and run over every fixture — the ten reference detail pages plus
the leaderboard pages, the event index and a 404 body:

| | hand-rolled scanner | SwiftSoup |
|---|---|---|
| Output vs. the other implementation | **identical** on all 16 files / 825 rows (0 diffs) | **identical** |
| `bv + goe + bonus == psv` invariant | 0 violations | 0 violations |
| Reference skater (`Milo Yeon`, 9 elements) | matches the §5.2 table | matches the §5.2 table |
| Implementation size | 162 lines + the trap-specific tests below | **58 lines** |
| Parse time, 16 files, release | 430 ms | **139 ms** (3.1× faster) |
| Parse time, 154 KB page (largest) | 70 ms | 21 ms |
| Traps it must handle itself | 1–8 in the list below | 0 — the parser handles them; only 9–11 remain |
| New code on our side to maintain | scanner + attribute parser + entity table + tag stripper + depth counting | selectors + value conversion |
| Added build time (clean) | 0 | ~5 s Debug; **~46 s Release**, iOS simulator |
| Linked binary size (arm64, iOS sim) | 0 | **+4.15 MB Debug**; +4.2 MB per arch Release (fat release framework: 67 KB → 8.80 MB unstripped, 8.80 MB → 7.96 MB after `strip -S`) |
| Transitive footprint | none | **none** (single target, Foundation only) |
| Builds for our targets | — | **verified**: compiles for `arm64-apple-ios15.0-simulator` (platform 7, SDK 27.0), links into `ProtocolParser.framework`, 7002 SwiftSoup symbols |

The hand-rolled route is not merely more code, it is more *failure modes*, and the spike hit two of
them in the same afternoon — both silently, on real data, with the row still parsing:

1. **Entity decode before tag strip.** Decoding `&lt;` first turns it into `<`, which the tag
   stripper then swallows: `2Lz&lt;&lt;` parsed as `2Lz` (and `2Lo<+1Lo` as `2Lo`) on 6 of the 16
   files. The element abbreviation column loses its rotation markers. Correct order is
   strip-then-decode (§4.2).
2. **Sign lost below 1.00.** `Int("-0") == 0`, so a parser that reads the sign off the whole-number
   component turns `-0.90` into `+90`: 268 rows violated the `bv + goe + bonus == psv` invariant
   (invariant failures are the only reason this was caught at all). See §5.1.

Neither is exotic — they are the shapes of bug that a bespoke scanner invites, and each needs its
own permanent regression test. SwiftSoup cannot have them: it is a port of jsoup, a parser with two
decades of real-world tag soup behind it, and its `.text()` gives canonical, entity-decoded,
whitespace-normalized text (it even normalizes `&nbsp;` away for us).

**Decision (adopted 2026-10-14, §10g): SwiftSoup is the parsing implementation.** It clears the
§2.2 bar on every count — it removes
real work (58 lines against 162 plus ~10 trap tests), it is well-fitted (CSS selectors over exactly
the tables we key on), it is maintained and proven, it has no transitive footprint, it is 3× faster
than the scanner we would write, and it is *verified* to build for this project's targets. The
costs are real and bounded: ~5 s on a clean Debug build, ~46 s on a clean Release build, and
~4 MB per architecture of linked code (the largest single cost; accepted because the import path is
one-shot user-initiated work with no server-side size pressure, and the app already links
AVFoundation/CoreImage).

**Behaviour it imposes on us** (must be handled in the implementation, not assumed away):

- It parses to an **HTML5 tree**, not our markup: implicit `<tbody>` wrappers, and malformed tags
  repaired per spec. Selectors must be written against the parsed tree (`table.sum`,
  `table.sum tbody td.name`), and section pairing must stay "the next `table.elm` in document
  order after the matched `table.sum`" rather than a positional sibling assumption.
- Its `.text()` **normalizes whitespace and drops `&nbsp;`**, so the "is this cell empty" test
  works on it directly — but a `\u{00A0}` guard is still worth keeping for pages that encode
  padding differently.
- It is a class-based API and not `Sendable`: parsing stays on the actor that calls it, or runs
  inside a `nonisolated` function that keeps the `Document` local and returns only `Sendable` value
  types (§7.2 already specifies that shape).

If the dependency is ever dropped, §4.2–§4.6 remain a correct specification for a hand-rolled
scanner — that implementation exists, passes the same 825 rows, and its two bugs are documented
above so the next attempt does not repeat them. Everything below is expressed in terms of *which*
cells and *which* pairing are correct; with SwiftSoup the implementation reaches them through CSS
selectors over the parsed DOM.

### 4.2 Decoding and text extraction

- Body is `iso-8859-1` per `<meta http-equiv="Content-Type">`. Decode `Data` as UTF-8 first, then
  ISO-8859-1 (Windows-1252 where it matters). None of the ten fixtures contain a byte above ASCII,
  but skater names are free text, so do not skip this.
- Entity decoding is required and small: the pages use only `&nbsp;` and `&lt;`
  (plus the usual `&amp;` `&gt;` `&quot;` `&#nnn;` for safety). `&lt;` matters in element
  abbreviations (`2Lz&lt;&lt;` → `2Lz<<`).
- **Strip markup first, decode entities second.** The reverse order destroys data: `&lt;` becomes a
  literal `<`, which a tag stripper then treats as the start of a tag and swallows — `2Lz&lt;&lt;`
  parses as `2Lz` and `2Lo&lt;+1Lo` as `2Lo`, silently, on 6 of the 16 fixtures (the spike hit
  exactly this; see §4.1). Decoding entities is always the *last* text step.
- **A cell's inner text is not necessarily tag-free.** `<TD class=name>Falls<B>:</B></TD>` occurs
  in the `ded` table. Strip markup from cell text rather than assuming `<TD …>text</TD>`; treat
  `<BR>` as a space.
- `<TD class=jud>&nbsp;&nbsp;</TD>` uses multiple `nbsp`s for padding — trim after decoding, not
  before.

### 4.3 Table scanning

- Attribute **values** must be matched as whole tokens: the leaderboard page has
  `class=detailScoreSum` / `class=detailScoreElm`, and a substring test for `sum`/`elm` matches
  them. Match `class` on exact value equality (the attribute may hold several classes —
  `class="sortable men"` — so compare token-wise, not by string equality of the whole value).
- Closing-tag search must **count depth**: the leaderboard page nests
  `<TABLE class=detailScoreElm>` inside `#catSegTable`'s child row, so "first `</TABLE>` after the
  open tag" ends the outer table early. The detail pages happen to have no nesting.
- Tag and attribute names are case-insensitive (`<TABLE>` vs `<table>`); the files use uppercase
  tags, mixed-case attributes, and both `<H2>`-with-`</H1>`-style errors.

### 4.4 Isolating a skater section

Walk the tables in document order. A skater's section is the pair

```
<TABLE class=sum>   ← skater identity + rank/scores
<TABLE class=elm>   ← that skater's elements (the next elm table after the sum table)
```

Rules:
- The skater's display name is the **`<TD class=name>` inside the `sum` table's `<TBODY>`** — for
  the reference page `Milo Yeon, SC of Boston`. Do **not** take the first `class=name` in the file
  (the `sum` header uses `<TH class=name>Name</TH>`, and 95 of the 114 `class=name` cells in the
  fixture set belong to `ded`/`maj` tables).
- Pair each `sum` table with the **next** `elm` table *after* it (not "the table at the structural
  index"), so a section that is present but unparsable — e.g. a withdrawn skater emitted with no
  element table — produces `.elementTableMissing` for that skater instead of mis-assigning the next
  skater's elements.
- Everything between the matched `sum` table and the following `sum` table belongs to that skater
  and can be ignored (`elm`, `ded`, `maj`).

### 4.5 Element rows

The `elm` table contains **more than element rows**: the program-components block (`Composition`,
`Presentation`, `Skating Skills`), a `Total BV:` row and `Total elm. score:` cells live in the same
table, with different cell classes (`pcl`, `cjud`, `panel`, `fact`, `cn`, `tbvl`, `tbvv`, …).

**An element row is a `<TR>` containing a `<TD class=num>`.** This is the only filter needed and it
is exact (672/672 rows across the fixture set). Element index
should be verified to run 1…N contiguously; a gap is a `.malformedElementRow` (it means a row was
dropped or the table shape changed).

### 4.6 Column mapping

The requirement describes the columns ordinally; in the markup each one carries a stable `class`,
which is what the parser keys on — positional indexing breaks because the judge columns vary in
count (7–9 are present; the header always emits 10 `class=jud` cells) and Jackson Patterson's table
emits an **extra empty `jud` column and an empty `ref` header**, shifting every positional index
after it.

| Ordinal (req.) | Cell class | Meaning | Handling |
|---|---|---|---|
| 1 | `num` | element index | `ProtocolElement.index` |
| 2 | `elem` | raw abbreviation | `ProtocolElement.abbreviation` (entity-decoded) |
| 3 | `info` | under-rotation / fall / edge marker (`F`, `<<`, `<`, `!`, `e`, `q`, `nC`, `nS`, `*`) | **never used** — not parsed, not modelled, no later component may depend on it (§10a); the abbreviation is the sole element identity |
| — | `two` | display flag only: `x` marks a second-half element; empty otherwise | ignored (not a value column) |
| 4 | `bv` | base value | `ProtocolElement.baseValue` |
| 5 | `goe` | GOE | `ProtocolElement.goeValue` |
| — | `ded` | empty (`&nbsp;`), padding | ignored |
| — | `jud` × *n* | individual judges' GOE marks (`-5`…`3`, `-` when no element) | **ignored** — variable count, and the trailing two are padding (`&nbsp;&nbsp;` / `&nbsp;`) |
| second-to-last | `ref` | bonus for difficult elements (`1.00`, `0.50`, empty, `&nbsp;`) | `ProtocolElement.bonusValue`; empty → `0` |
| last | `psv` | panel score = base + GOE + bonus | `ProtocolElement.panelScore`, validation only (§5.2) |
| — | `spc` | spacer | ignored |

### 4.7 Trap checklist

Everything a tolerant parse has to survive, all of it observed in the fixtures. Items **1–8** are
the markup parser's job — SwiftSoup handles them with no code from us (§4.1) — while **9–11** are
our own value/section logic and hold under either approach.

| # | Trap | Where it bites | Handled by |
|---|---|---|---|
| 1 | Unquoted attribute values (`href=SEGM034.html`) | leaderboard page | the parser |
| 2 | Arbitrary tag/attribute case (`<TABLE>` vs `<table>`) | both page kinds | the parser |
| 3 | Mismatched end tags, general tag soup (`<H2 …></H1>`) | both | the parser |
| 4 | Undeclared entities (`&nbsp;`), `&lt;` inside cell text | both | the parser |
| 5 | Inline markup inside a cell (`Falls<B>:</B>`) | `ded` tables | the parser |
| 6 | Class **token** matching, not substring (`sum` ≠ `detailScoreSum`) | leaderboard page | the parser (CSS class selector) |
| 7 | Nested tables — the body needs depth counting, not "first `</TABLE>`" | leaderboard page | the parser (tree) |
| 8 | `<BR>` in header cells; `&nbsp;` padding runs in data cells | both | the parser |
| 9 | Empty / `&nbsp;` bonus cell means `0` | 696 of 717 rows | ours (§5.1) |
| 10 | Hundredths conversion incl. the sign-below-1.00 trap | 268 rows when done wrong | ours (§5.1) |
| 11 | Variable judge count and extra empty cells shifting positions | 7–9 judges; Jackson Patterson's table | ours (class keying, §4.6) |

## 5. Values and units

### 5.1 Integer hundredths

The module emits **`Int` hundredths** (`2.10` → `210`, `-0.26` → `-26`, `1.00` → `100`) — the
project-wide convention (see `docs/ARCHITECTURE.md` §3.1). This is not optional: it is what lets
the parser's output drop straight into `ElementData(baseValue:goeValue:bonusValue:)`.

Conversion rules (module-local `String → Int` helper; the app's `String.toHundredthsInt()` is
`internal` to the app target and cannot be reached from here):
- Trim, decode entities, then parse an optional sign, digits, optional `.` + 1–2 digits. Scale by
  100 — `0.5` → `50`. Do not silently accept a 3rd decimal.
- **Track the sign separately from the integer part.** `Int("-0") == 0`, so a reader that infers the
  sign from the whole-number component turns `-0.90` into `+90`. This is not hypothetical: it broke
  **268 of the 825 rows** in the spike (every GOE below −1.00 magnitude), and it is invisible except
  for the §5.2 invariant — the numbers still look like plausible scores. Test it directly:
  `"-0.90" → -90`, `"-1.19" → -119`, `"0.42" → 42`.
- Empty, `&nbsp;` → `0` for the **bonus** column (696 of 717 rows are empty).
- Empty / `-` / non-numeric for `bv`, `goe` → `.malformedElementRow` (§6). `-` appears only in
  judge cells, which are ignored.
- All 2016 `bv`/`goe`/`psv` values in the fixture set are exactly two decimals, so the conversion is
  lossless today; parse tolerantly anyway (the bonus abbreviation `b0.5` in §9 shows the site is
  willing to print one decimal).

### 5.2 The total column is an invariant, not a field

The last column satisfies `bv + goe + bonus == psv` **exactly, in hundredths, for all 717 element
rows across the ten fixture pages** (0 mismatches, 0 non-numeric). Confirmed examples:

| # | abbrev | base | GOE | bonus | panel | check |
|---|--------|-----:|----:|------:|------:|-------|
| 1 | `2Lz` | 210 | 42 | 0 | 252 | ✓ |
| 2 | `3Tb1+2T` | 550 | 25 | 100 | 675 | ✓ |
| 3 | `3Sb1+1A+2Lo+SEQ` | 710 | −26 | 100 | 784 | ✓ |
| 5 | `3T` | 462 | 84 | 0 | 546 | ✓ |

`panelScore` is **kept for sanity checking only** (§10e): never displayed, never summed into
anything. It exists so the parser can be checked against the page's own arithmetic (§5.2) and so a
disagreement can surface in the UI. The overlay's running total is computed by the app from
base + GOE + bonus (`docs/ARCHITECTURE.md` §3.3); a mismatch is not fatal — it means the page's
columns disagreed, which the import surfaces rather than rejecting the element.

## 6. Section isolation by name

Matching is **normalized exact**, never fuzzy:

1. Normalize both sides: trim, collapse whitespace, case-fold, strip diacritics, drop
   `.`/`'`/`’`/`-`. (The site itself drops apostrophes — `Lianna OGrady, Skokie Valley SC` — so
   `Lianna O'Grady` must still match.)
2. Compare the query against the candidate's **name part** (the text before the first comma:
   `Milo Yeon`).
3. If that matches more than one skater, retry against the **club-qualified** full cell
   (`Milo Yeon, SC of Boston`) — the disambiguation ladder.
4. 0 matches → `.skaterNotFound(name:available:)` carrying every name on the page (the message is
   the UI's picker). >1 → `.skaterAmbiguous(name:matches:)`.
5. Nothing else is accepted: no prefix, substring or typo tolerance. Picking the wrong skater
   silently would produce a wrong protocol.

`ProtocolSkater` keeps the cell text verbatim (`name`) and exposes `namePart` / `club` derived at
the first comma, so the app can decide what goes into `OverlayData.skaterFullName`.

Elements with **no value** are always imported (§10c): `CoSp` / `FSSp` rows where the skater
attempted an element the panel did not credit (`0.00` base, all `-` judge marks) produce a record
with zeros, per "each element corresponds to an `ElementData` record". There is **no filter and no
"skip empty elements" option** — the protocol lists the element, so the import keeps it. It renders
neutral grey by the existing color rule (`baseValue == 0` → `.neutral`).

## 7. Public API

Module-level design constraints: no app types (§8), no I/O inside the parser (§7.2), everything
`Sendable`; parsing entry points are `nonisolated` so they can be moved off the main actor without
restructuring (every target is MainActor-isolated by default — `Project.swift` `baseSettings`).
**No type is named `ProtocolParser`** — that would collide with the module name (the project uses
`VideoComposer` in the `VideoProcessor` module, not `VideoProcessor`).
**The HTML parser is an implementation detail**: no `SwiftSoup` type (`Document`, `Element`,
`Elements`, `Selector`) may appear in a public signature, and the app never imports the package — so
the dependency stays replaceable and its behaviour cannot leak into call sites.

### 7.1 Model (hundredths; no UI, no naming policy)

```swift
public struct ProtocolElement: Sendable, Equatable, Hashable {
    public let index: Int             // 1-based, contiguous
    public let abbreviation: String   // raw + entity-decoded: "3Tb1+2T", "2Lz<<", "StSq2+kpYYNN"
    public let baseValue: Int         // hundredths
    public let goeValue: Int          // hundredths, may be negative
    public let bonusValue: Int        // hundredths; 0 when the column is empty
    public let panelScore: Int        // hundredths; validation only (§5.2)
}

public struct ProtocolSkater: Sendable, Equatable {
    public let name: String           // "Milo Yeon, SC of Boston" (verbatim)
    public let elements: [ProtocolElement]
    public var namePart: String       // "Milo Yeon"
    public var club: String?          // "SC of Boston"
}

public struct ProtocolSegment: Sendable, Equatable {
    public let eventName: String      // "2026 Boston Open"
    public let categorySegment: String// "101_109 Champ Intermediate Men / Free Skate"
    public let skaters: [ProtocolSkater]
}
```

All three declare public memberwise inits: the app builds them directly in its own unit tests (the
§8.1 merge test needs a `ProtocolSkater` and must not parse HTML or touch the network).

### 7.2 Pure parsing surface

```swift
public enum ProtocolPageKind: Sendable, Equatable {
    case leaderboard      // CATnnnSEGnnn.html — carries the judge-detail link
    case segmentDetail    // SEGMnnn.html — carries the element tables
}

public enum ProtocolHTMLParser {           // nonisolated, sync, no network, no state
    /// nil when the page is neither kind (login page, 404 body, unrelated site).
    public static func pageKind(of html: String) -> ProtocolPageKind?

    /// The `<A>` inside `<LI class="judgeDetailRef">`, resolved against `base`.
    /// Throws .detailLinkMissing when the page has no such element.
    public static func judgeDetailLink(in html: String, relativeTo base: URL?) throws -> URL

    public static func parseSegment(html: String) throws -> ProtocolSegment

    public static func skater(named: String, in segment: ProtocolSegment) throws -> ProtocolSkater
}
```

`pageKind` precedence — the leaderboard page contains `detailScoreSum`/`detailScoreElm` but neither
`class=sum` nor `class=elm`, so the signals are disjoint; still, check `judgeDetailRef` **first** so
a future leaderboard page that grows a `class=elm` table is still treated as a leaderboard page:

| Signal | Verdict |
|---|---|
| `<LI class="judgeDetailRef">` **or** `<TABLE id=catSegTable>` **or** `<DIV class=segLinks>` present | `.leaderboard` |
| `<TABLE class=sum>` **and** `<TABLE class=elm>` present | `.segmentDetail` |
| neither | `nil` → `.unrecognizedPage` |

The link is not the only leaderboard signal, and it must not be: it is absent precisely when judge
details are unpublished, and that page still has to be recognisable so the import can report
`.detailLinkMissing` (§10b) rather than "this is not a protocol page". The results table and the
segment-links list are present either way.

### 7.3 Fetching seam and orchestrator

```swift
public nonisolated protocol ProtocolFetching: Sendable {
    func fetch(_ url: URL) async throws -> String      // decoded text
}
public struct URLSessionProtocolFetcher: ProtocolFetching {   // GET, no cache (pages send no-cache)
    public init()
}

public struct ProtocolImporter: Sendable {
    public init(fetcher: ProtocolFetching = URLSessionProtocolFetcher())

    /// URL of either page kind — classified, and followed if it is a leaderboard page.
    public func skater(named: String, at url: URL) async throws -> ProtocolSkater

    /// Page content supplied directly (paste / file / test), optionally with its URL for
    /// resolving the relative detail link. `async` because supplied leaderboard content still
    /// has to fetch the detail page it links to; supplied detail content needs no network.
    public func skater(named: String, inHTML html: String, baseURL: URL? = nil) async throws -> ProtocolSkater
}
```

`ProtocolFetching` is declared `nonisolated`: every target is MainActor-isolated by default
(`Project.swift` `baseSettings`), so a plain protocol declaration would be MainActor-only and no
actor — nor any off-main fetcher — could conform to it. The same applies to anything else in this
module that is implemented off the main actor.

Control flow:

```
url ──fetch──▶ html ──pageKind──┬─ .leaderboard ─▶ judgeDetailLink(relativeTo: url)
                                │                    └─ fetch ─▶ html' ──pageKind── must be
                                │                                    .segmentDetail else
                                │                                    .unrecognizedPage
                                └─ .segmentDetail ─┐
                                                   ▼
                    parseSegment(html) ─▶ ProtocolSegment ─▶ skater(named:) ─▶ ProtocolSkater
                                                   ▼
                                  app: OverlayData.merge(_:) ─▶ [ElementData]
```

**The link is mandatory for a leaderboard page** (§10b). The leaderboard page is used for **nothing
except locating the link** — no leaderboard-page data is imported, ever. If `judgeDetailRef` is
absent the import ends in `.detailLinkMissing`; that is the specified behaviour ("if the javascript
webpage does not have the link yet, then report that as an error condition"), and it is the correct
signal: the organizer has not published judge details for that segment yet, so the user waits and
retries. The embedded `detailScoreElm` table (§2.1) is **not** a fallback at any point: it has no
bonus column and no raw abbreviations, so importing from it would silently produce different values
than the static page.

**Sibling segments are never followed.** The leaderboard page links to its own segment and to other
segments of the same category (`CAT022SEG033.html` next to `CAT022SEG034.html`); only the
`judgeDetailRef` anchor is followed, so one importer call = one segment.

A relative link with no `baseURL` (`inHTML:` with `baseURL: nil`) throws
`.relativeLinkWithoutBaseURL` rather than guessing.

### 7.4 Errors

```swift
public enum ProtocolParserError: Error, LocalizedError, Equatable {
    case unrecognizedPage                                  // not a results page we understand
    case detailLinkMissing                                 // leaderboard page has no judge-detail link
    case detailLinkAmbiguous(count: Int)                   // more than one judge-detail link
    case relativeLinkWithoutBaseURL                        // relative href, no base to resolve against
    case fetchFailed(statusCode: Int)
    case undecodableBody                                   // neither UTF-8 nor ISO-8859-1
    case skaterNotFound(name: String, available: [String])
    case skaterAmbiguous(name: String, matches: [String])
    case elementTableMissing(skater: String)
    case malformedElementRow(skater: String, index: String, reason: String)
}
```

Failure policy: **fail fast on structure, default only on genuinely optional columns.** Required in
each element row: `num`, `elem`, `bv`, `goe` (missing/unparseable → `.malformedElementRow`).
Optional: bonus (`ref` absent/empty → `0`), `info`, `two`, `ded`, `spc`, `jud`, `psv`. A page whose
`sum`/`elm` counts disagree, or a matched skater with no following `elm` table, is
`.elementTableMissing`. Behaviour is per-element, not all-or-nothing: one bad row fails the import
with the row's index and reason, so the user can see which element to enter by hand.

## 8. Integration with the app

**Dependency direction:** app → ProtocolParser. `ElementData` is an `internal @Observable class` in
the app target (`OverlayData.swift:276`), so the module cannot produce it; the mapping and the merge
live in the app:

```swift
extension ElementData {
    convenience init(_ element: ProtocolElement) {          // displayTime stays nil — the app sets timing
        self.init(name: element.abbreviation,               // verbatim until the translator lands (§9)
                  baseValue: element.baseValue,
                  goeValue: element.goeValue,
                  bonusValue: element.bonusValue)
    }
}
```

### 8.1 Merge policy — iCndex-keyed, and it never discards timing

Import is **not** a wholesale replacement of `elementScores`: it rewrites values **in place, keyed by
element index**, so a user who has already placed elements on the timeline does not lose that work to
a re-import.

| Existing `elementScores` | Imported protocol | Result |
|---|---|---|
| entry at that index (timed or untimed) | element at the same index | **values replaced at that index** — `name`, `baseValue`, `goeValue`, `bonusValue` come from the protocol; **`displayTime` is preserved exactly** (an existing timestamp is maintained; `nil` stays `nil`) |
| — (the protocol has **more** elements) | surplus elements | **appended** as new `ElementData` with `displayTime == nil` — they land untimed for the user to place in `TimeSettingsView` |
| surplus entries beyond the protocol's element count | — (the protocol has **fewer** elements) | **left completely untouched** — values and `displayTime` exactly as they were; the UI can hint that the protocol listed fewer elements than the current data |

"Index" means the **position in the parsed element list** (0-based), i.e. protocol index *n* →
`elementScores[n-1]`. §4.5 validates that the protocol's index column runs 1…N contiguously, so
position and index agree. The element *identity* at a position may legitimately change on re-import
(a different jump is now element 3) — that position keeps its time on purpose, because the timestamp
marks a place on the timeline, not a particular element.

```swift
extension OverlayData {
    /// Merges an imported protocol into `elementScores`, keyed by element index (§8.1).
    /// Values are refreshed; timing is never destroyed.
    func merge(_ skater: ProtocolSkater) {
        for (index, element) in skater.elements.enumerated() {
            if index < elementScores.count {
                // Replace at the same index, keeping the existing displayTime.
                let existing = elementScores[index]
                existing.name = element.abbreviation
                existing.baseValue = element.baseValue
                existing.goeValue = element.goeValue
                existing.bonusValue = element.bonusValue
                // existing.displayTime deliberately not touched
            } else {
                // Protocol has more elements than the current data: append, untimed.
                elementScores.append(ElementData(
                    name: element.abbreviation,
                    baseValue: element.baseValue,
                    goeValue: element.goeValue,
                    bonusValue: element.bonusValue,
                    displayTime: nil))
            }
        }
        // Anything past skater.elements.count is left as-is.
    }
}
```

Consequences worth knowing:

- Mutating the existing `ElementData` instance in place (rather than rebuilding the array) preserves
  object identity and `displayTime` by construction — there is no code path that can drop a
  timestamp. `OverlayData.renderingHash` covers the refreshed fields, so the chunk pipeline sees the
  change.
- A bad or empty parse (a page whose element table yields no rows) therefore cannot destroy imported
  timing: the worst case is refreshed values or appended elements.
- Newly appended elements are `nil`-timed and are **not** auto-cascaded into place; existing spacing
  is left stale-relative until the user sets a timestamp, at which point `setElementTime`'s cascading
  propagates the delta to everything after it.
- `OverlayData.skaterFullName` is **not** written by the parser: `ProtocolSkater.namePart`/`club`
  are offered and the UI decides (the protocol cell carries the club, the overlay lower-third shows
  a name).
- Importing is a data change, so the existing `imageCache` invalidation paths apply
  (`OverlayData` clears the cache on data change; `ScoringListView.onDisappear` saves + clears).
- **Manifest (done):** the app target depends on `.target(name: "ProtocolParser")`, the module
  target carries `.package(product: "SwiftSoup")` with the package pinned in `Project.swift`'s
  `packages:` list, the app test target depends on `ProtocolParser` (its merge test builds
  `ProtocolSkater` values directly), and `Package.resolved` is committed.

### 8.2 The import flow in the app

`ScoringListView` carries an **Import Protocol** button — the first control in the element button
row, to the left of **Add Element**. It:

1. asks for the protocol page address (`TextField` in an alert; **either page kind is accepted**, and
   a leaderboard page is followed to its judge-detail page when that has been published);
2. takes the skater to find from `OverlayData.skaterFullName`, and refuses with an explanation if it
   is empty;
3. shows a `ProgressView` while the import runs, with the button disabled;
4. on success calls `OverlayData.merge(_:)` (§8.1) and clears any message;
5. on failure shows the thrown error's `errorDescription` in an alert — `ProtocolParserError`'s
   descriptions are written to be shown to the user (`.detailLinkMissing` reads "The judge detail
   scores have not been published for this segment yet.").

`ProtocolImportModel` holds that state (`urlString`, `isImporting`, `errorMessage`) and does the
validation, which keeps the flow unit-testable with a fake `ProtocolFetching` and no UI: eight tests
cover both guards, the successful merge (including that an existing `displayTime` survives),
`.detailLinkMissing`, the not-found message and the in-progress flag. The UI itself is covered by two
UI tests — that the button exists **to the left of Add Element** (compared by frame), and that tapping
it presents the address prompt.

## 9. Abbreviation → display name (deferred)

`ElementData.name` receives the raw abbreviation until the app calls the translator (§8.1). The
translator is a single component with an **identity default**, so its absence is not a failure mode.
**The singles rules are implemented in this module's `ElementNameExpander.swift` and specified in
[`docs/architecture/abbreviation-expansion.md`](abbreviation-expansion.md)** — that document owns the
jump / spin / step-sequence / choreographic vocabulary and the marker handling; this section keeps
only the seam and the token inventory.

```swift
public protocol ElementNameTranslating: Sendable {
    func displayName(for abbreviation: String) -> String    // default: the abbreviation, unchanged
}
```

The token grammar the table must cover, taken from the **241 distinct abbreviations** in the ten
fixtures (187 singles + 66 pairs, largely disjoint vocabularies):

| Shape | Examples | Note |
|---|---|---|
| jump / combo | `3Tb1+2T`, `2A+1A+2T+SEQ`, `2F+Eu+3S<` | `+`-joined tokens; `Eu` = Euler |
| bonus marker | `3Tb1`, `3F+3Tb1`, `StSq4b0.5+kpYYYN`, `3Tw3b1` | `b1` / `b0.5` — also in the bonus column |
| rotation / edge | `2Lz<<`, `2Lo<`, `2Lz!`, `2Lze`, `2Lo+2Tq` | also (partly) in the `info` column, which is **never read** (§10a) |
| repeat / sequence / invalid | `3Lo+REP`, `2Lz+COMBO`, `1Lz*+COMBO`, `T+COMBO+2T*+REP` | site shorthand, incl. dangling `Lo*` / `T` |
| spins | `CCoSp4`, `FSSp3`, `CCoSp1V`, `CoSp` | `V` = version/level variant |
| step sequences | `StSq2+kpYYNN`, `StSqB+kpYNNN`, `StSq4b0.5+kpYYYY` | `+kp…` key points |
| pairs: throws / twists | `3STh`, `1LoTh`, `2LzTh`, `3SThb1`, `3Tw3`, `2Tw4` | `Th` throw, `Tw` twist; bonus marker composes (`3Tw3b1`) |
| pairs: lifts / death spirals | `1Li3`, `5ALi4`, `4LiB`, `BoDs2`, `FiDs3` | `Li` lift + level, `B` = base value; `Ds` death spiral |
| pairs: choreographic / pattern | `ChPLi1`, `ChPSp1`, `PSp3`, `PiF1` | choreographic lifts/spins, pattern elements |

Recommended shape: tokenize on `+`, map each token through the table, keep unknown tokens verbatim,
and reassemble — so an unrecognized token degrades to the abbreviation instead of failing the
import.

## 10. Decisions (all resolved 2026-10-14)

Letters are kept stable because other sections and `docs/ARCHITECTURE.md` reference them.
**Nothing in this document is still open.**

| # | Question | Decision |
|---|---|---|
| a | The `info` column (third column: `F`, `<<`, `!`, `e`, `q`, `nC`, `nS`, `*`) — keep it on the model for a future translator? | **The information in that column is never used.** It is not parsed, not carried on `ProtocolElement`, and no later component may depend on it. The abbreviation is the sole element identity (§9). |
| b | The leaderboard page embeds an approximate element table — use it as a fallback when the judge-detail link is absent? | **Never. No leaderboard-page data is used for anything except locating the link.** With the link absent the import ends in `.detailLinkMissing`: the user waits for the organizer to publish judge details and retries. |
| c | Zero-value rows (`0.00` base, all-`-` judge marks — uncredited `CoSp`/`FSSp`) | **Always real elements, always imported.** No filtering and no "skip empty elements" option: the protocol lists the element, so the import produces the record (it renders neutral grey by the existing rule). |
| d | Merge policy: replace `elementScores`, append, or match by index? | **Index-keyed and timing-preserving** — §8.1: replace values at the same index keeping `displayTime`, append surplus protocol elements untimed, leave surplus existing entries untouched. |
| e | Keep the total column (`psv`)? | **Kept for sanity checking only** — never displayed, never summed into anything. It exists to verify `bv + goe + bonus == panelScore` (§5.2) and to let a disagreement surface in the UI. |
| f | One URL = one segment; may the module follow sibling-segment links? | **No navigation to sibling segments, ever.** Only the `judgeDetailRef` anchor is followed; the app passes the per-segment page. |
| g | Adopt the SwiftSoup dependency (§4.1)? | **Adopted** — SwiftSoup `2.14.2` is the parsing implementation (§4.1, §13). Identical output to the hand-rolled scanner on 825 rows, 3.1× faster, 58 vs 162 lines, verified to build for this project's iOS targets; costs ≈ 5 s Debug / ≈ 46 s Release clean-build time and ≈ 4 MB per architecture. |

## 11. Testing

Fixtures are HTML files committed under
`LayoutEngine/ProtocolParser/ProtocolParserTests/Fixtures/` — the twelve pages of §3’s table plus
`SEGM033.html` (the sibling segment, which the link test needs), i.e. **eleven detail pages and two
leaderboard pages, ~900 KB**, and two synthetic pages (a leaderboard page with the judge-detail
block removed; a detail page with one Base Value cell removed). Text, so no untracked-large-file
caveat like the 398 MB sample video. The sweep asserts over the committed set: **825 element rows**.
**Tests never hit the network** — `ProtocolFetching` is the seam; use a fake that returns fixture
text (the pattern `VideoProcessorTests` uses with `FakeRenderer`).

| # | Test | Expectation |
|---|---|---|
| 1 | `pageKind` on both page kinds + on a 404 body / unrelated HTML | `.leaderboard`, `.segmentDetail`, `nil` |
| 2 | `judgeDetailLink` on `CAT022SEG034.html` / `CAT022SEG033.html` | resolves to `…/SEGM034.html` / `…/SEGM033.html` (proves sibling links are not picked) |
| 3 | `judgeDetailLink` on a synthetic fixture with the `judgeDetailRef` block removed | throws `.detailLinkMissing` |
| 4 | `parseSegment` on `SEGM034.html` | 17 skaters, names in rank order, categorySegment = `101_109 Champ Intermediate Men / Free Skate` |
| 5 | Milo Yeon's elements (frozen table) | 9 elements, abbrevs + `bv`/`goe`/`bonus`/`panel` exactly as §5.2, index 1…9 |
| 6 | **Invariant sweep** over every fixture: `bv + goe + bonus == psv` | 825/825 rows |
| 7 | Pairs fixture (`SEGM030.html`, `SEGM031.html`) parses to the same schema | `3Tw3`, `5ALi4`, `FiDs3`, `ChPSp1` land in `abbreviation`; 10 `jud` cells ignored |
| 7b | Entity decoding | `2Lz&lt;&lt;` → `2Lz<<`; `&nbsp;` bonus → `0` |
| 8 | Optional-column defaults | empty **and** `&nbsp;` bonus → `0`; Jackson Patterson's table (extra empty `jud`/`ref` cells) parses to the same schema |
| 9 | Zero-value elements retained | `CoSp` → `baseValue == 0, goeValue == 0` |
| 10 | Matcher: `Milo Yeon` vs `Milo Yeon, SC of Boston` vs `milo yeon` vs `Lianna O'Grady` (site text `Lianna OGrady`); miss → `.skaterNotFound` with 17 available names; ambiguity → `.skaterAmbiguous` | unit-tested on a hand-built `ProtocolSegment`, no HTML needed |
| 11 | Malformed row: synthetic fixture with the `bv` cell removed | throws `.malformedElementRow` naming the row index |
| 12 | Unquoted-attribute handling | `href=SEGM034.html` parsed (regression guard for §2.1) |
| 13 | Value conversion edge cases | `"-0.90"` → `-90`, `"-1.19"` → `-119`, `"0.42"` → `42`, `"0.5"` → `50`, empty/`&nbsp;`/`-` → the §5.1 rule per column |
| 14 | Merge policy (§8.1) — **app-side**, in `TechnicalOverlayTests`, no HTML needed | given timed `elementScores`: same-index values refresh while `displayTime` survives; a longer protocol appends entries with `displayTime == nil`; a shorter protocol leaves the surplus entries byte-for-byte untouched |

Indices are 1-based in test expectation tables so they read like the protocol.

**What the SwiftSoup dependency changes here.** Tests 1, 3, 7b and 12 (tag soup, entities, unquoted
attributes, case) stop being our tests — they are the library's, exercised by its own suite. The
tests that stay ours are the ones the library cannot know about: classification and link selection
(1–3), the extraction contract (4–5, 7–9), the matcher (10), and the error paths (11). The
highest-value test remains **6**, the invariant sweep: across every fixture it asserts the source's
own arithmetic against the values we extracted, and it is what caught the sign bug (§5.1) that
would otherwise have shipped plausible-looking wrong scores. Keep it regardless of approach.

## 12. Verification performed (2026-10-14)

- Fetched the two reference pages in the requirements, the event index (`index.asp`), and **ten**
  segment detail pages (five singles, five pairs) from the same event (`2026 Boston Open`, id
  `36683`), and inspected the raw markup — every structural claim in §2, §4 and §5 is taken from
  that markup, not from a rendered export.
- A throwaway prototype of §4.3–§4.6 (Python, scratch dir) parsed all ten detail pages: **85
  skaters, 672 element rows, 0 unparsed rows, 0 violations of `bv + goe + bonus == psv`**.
- **The pairs template is the singles template.** All ten pages have exactly the same table classes
  (`sum`/`elm`/`ded`/`maj`, one each per skater, no others) and the same element-row cell-class
  sequence (`num, elem, info, bv, two, goe, ded, jud×10, ref, psv, spc`); only the element
  vocabulary differs (66 pairs abbreviations, mostly disjoint from the 166 singles ones). The
  design needs no pairs-specific branch.
- Confirmed the strict-parser rejection in §4.1 against both page kinds, with Expat.
- Confirmed table nesting on the leaderboard page (`#catSegTable` → `detailScoreElm`), the
  `detailScoreSum`/`detailScoreElm` substring trap, `<B>` markup inside `ded` cells, the
  `&nbsp;`/`&lt;`-only entity set, and the all-ASCII body.
- Version drift observed within one event: `index.asp` reports ijsLive 2.6.3 while every segment
  page reports 2.6.4 — so field presence must be handled per page, not per site version.
- **Dependency spike (§4.1).** A hand-rolled Swift scanner and a SwiftSoup implementation were both
  written and run over all 16 fixture files (825 element rows, release build): **identical output**,
  0 invariant violations, `Milo Yeon`'s 9 elements matching §5.2 in both. SwiftSoup parsed in
  **139 ms** against the scanner's 430 ms (16 files); 21 ms vs 70 ms on the 154 KB page. Code size
  58 lines vs 162. Two silent bugs surfaced in the hand-rolled variant only (entity-decode ordering,
  sign-below-1.00) — both fixed, both documented above, and both caught only because of the §5.2
  invariant.
- **SwiftSoup verified for this project's targets**: added to `Project.swift`, `tuist generate`
  resolved it, and `xcodebuild -scheme ProtocolParser -destination 'platform=iOS Simulator,name=iPhone 17'`
  built it for `arm64-apple-ios15.0-simulator` (Mach-O platform 7, SDK 27.0) with 7002 SwiftSoup
  symbols linked into `ProtocolParser.framework`. Measured costs: clean Debug build ≈ 5 s added,
  clean Release build ≈ 46 s added, framework binary +4.15 MB (Debug arm64) / +8.33 MB unstripped
  and +7.53 MB after `strip -S` for the two-architecture release framework (≈ +4 MB per
  architecture). **The manifest edit was reverted** — nothing is wired in; the spike's `.package.resolved`
  was deleted.
- Not verified in the spike: **device (arm64-only, stripped, archived) binary growth** — the numbers
  above are simulator artifacts; and the dependency's behaviour on ijsLive versions other than 2.6.x.
- All seven design questions were resolved by the user on 2026-10-14 and are recorded in §10; the
  SwiftSoup dependency in §4.1/§13 is adopted and **wired in**.
- **Implemented 2026-10-14.** `ProtocolModel.swift` (page kind, element/skater/segment),
  `ProtocolHTMLParser.swift` (classification, link, segment parse, skater selection),
  `ProtocolFetching.swift`, `ProtocolImporter.swift`, `ProtocolParser.swift` (errors); app side
  `TechnicalOverlay/ProtocolImport.swift` (`ElementData(_:)` + `OverlayData.merge(_:)`) and
  `ProtocolImportModel.swift` + the **Import Protocol** button on `ScoringListView` (§8.2). Test
  results: **ProtocolParser 39/39** (six suites), **TechnicalOverlayTests 22/22** (five of them the
  merge, eight the import flow) and **two UI tests** for the button; the invariant sweep covers all
  **825** rows of the committed fixtures. Writing it corrected two things in this spec: the
  classifier needs non-`judgeDetailRef` leaderboard signals (a page whose link is not published was
  being reported as "not a protocol page" instead of `.detailLinkMissing`), and
  `skater(named:inHTML:baseURL:)` must be `async` because following a supplied page's link is a
  fetch. Both are reflected above.
- **Counts re-measured 2026-10-15** (while specifying the abbreviation expansion,
  `docs/architecture/abbreviation-expansion.md`): the ten detail pages hold **717** element rows
  (535 singles + 182 pairs — the sum of §3's own per-page column), the invariant holds on all 717,
  **696** of those rows have an empty bonus cell, and the distinct abbreviations are **241**
  (187 singles + 66 pairs). The 672 / 654 / 221 figures this document previously carried were stale.
  The 825-row figure for the committed eleven-detail-page set was already correct
  (717 + `SEGM033`'s 108).
- Not verified: **ice dance** (no dance segment exists at this competition — the user confirmed),
  a page with a withdrawn skater (no `elm` table; no `Withdrawn`/`WD`/`DNS` marker appears in any
  fixture), other events/eras of ijsLive, and non-U.S. events. The design is structure-based and
  class-keyed, so it should carry over; §11's invariant sweep is the cheapest way to extend
  coverage when a fixture becomes available.

## 13. Dependencies

- **SwiftSoup** (SPM, `https://github.com/scinfu/SwiftSoup.git`, pinned exact `2.14.2`, MIT) — the
  tolerant HTML5 parser. Chosen and justified in §4.1; integration is a `packages:` entry in
  `Project.swift` plus `.package(product: "SwiftSoup")` on the `ProtocolParser` target
  (`docs/ARCHITECTURE.md` §2.2 covers the policy this decision exercised).
- `Foundation` — `URL`, `URLSession`, `Data`, `String`, `LocalizedError`.
- No other package, and no import of the app, `LayoutEngine` or `VideoProcessor`.
