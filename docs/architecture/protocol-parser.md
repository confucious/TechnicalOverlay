# Protocol Parser Module

**Source:** `LayoutEngine/ProtocolParser/ProtocolParser/`

Status: **Implemented.** The module, the committed fixtures and the SwiftSoup dependency are in
place; the app-side merge (§8.1) is implemented and tested, and the import flow that drives it from
`ScoringListView` (§8.2) is wired. Two document kinds are read: the ijsLive HTML pages of §2.1–§2.2
and the ISU FS Manager protocol PDFs of §2.3. This document is the authoritative specification for
the module; current test counts live in [`docs/testing.md`](../testing.md).

## 1. Purpose

Import a skater's **executed elements** from a published competition protocol — an ijsLive results
page or an ISU FS Manager PDF — so the user does not have to retype an entire element list into
`ScoringListView`. The output is a value type carrying the raw element abbreviation plus base value /
GOE / bonus in **integer hundredths** — the units `ElementData` uses — with a thin app-side mapper
into `OverlayData.elementScores`.

**In scope:** locate the protocol document, isolate one skater, read that skater's element table,
convert it to values.

**Out of scope (explicitly):**
- Translating an abbreviation (`3Tb1+2T`) into a displayed name (`3 Toeloop + 2 Toeloop`) — that is
  `ElementNameExpander` (§9), specified in
  [`docs/architecture/abbreviation-expansion.md`](abbreviation-expansion.md).
- Program components, deductions, place, start number, segment/total scores beyond the per-element
  panel score (§5.2).
- Downloading/caching whole events, browsing categories, following sibling segments (§7.3).
- Any UI. The module never imports the app; the dependency points app → ProtocolParser (§8).

## 2. Input pages

Competition results are published by **ijsLive** (the pages in scope say
`<!-- Created by ijsLive 2.6.4 -->`). Two page kinds matter, and a third document kind carries the
same content — the ISU FS Manager protocol PDF (§2.3).

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

### 2.3 Protocol PDF — ISU FS Manager `…_JudgesDetailsperSkater.pdf`

The ISU results site publishes the same content as a PDF: one file per segment, titled
`JUDGES DETAILS PER SKATER`, written by PDFsharp. It is the table of §2.2 in another form — one
skater per block:

```
JUDGES DETAILS PER SKATER
WOMEN SHORT PROGRAM                            ← segment line, directly under the title
Rank Name Nation Starting Number …             ← column headers, several rows
1 Mao SHIMADA JPN 8 82.11 49.23 32.88 0.00     ← identity: rank, name, nation, start no., 4 scores
# Executed Elements  Info  Base Value  GOE  J1…J9  [Bonus]  Ref.  Scores of Panel
1 3A                8.00   2.51  3 3 3 3 3 3 4 3 4       10.51
2 3Fq        q      5.30  -0.38  -1 -1 -1 0 -2 0 -2 0 1   4.92
4 3Lz+3T           11.11 x  1.77  3 3 3 3 2 3 4 3 3       12.88
Program Components … / Judges Total Program Component Score (factored) / Deductions: …
```

Notes that matter for parsing:
- **There is no markup.** Every cell is an independently positioned text run and the order the runs
  were *drawn* in is not reading order (all the abbreviations are emitted together, then their
  numbers), so the table has to be rebuilt from geometry (§4.8).
- **Read the numbers positionally, not by header.** The bonus column is headed `Bonus` (not `ref`),
  `Ref.` is the referee's column, and either may be absent from a document — §4.9 defines the row.
- The `x` second-half flag and the info markers (`F`, `q`, `!`, `*`, …) sit in their own cells, and
  the abbreviation already carries its own marker (`3Fq`, `3Lzb`) — neither is a value (§10a).
- The event title appears above the title line when the document has one; a document may carry only
  the segment line.
- A skater's name carries **no club** here (`Mao SHIMADA`), so `namePart` is the whole cell (§6).
- The page draws a logo and two images; they carry no text and are ignored.
- A PDF that cannot be opened is `.unreadablePDF`; an open PDF that is not this protocol (no
  `JUDGES DETAILS PER SKATER` title) is `.unrecognizedPage`.

## 3. Reference pages (fixtures)

Segment pages are listed by the **event index** (`…/results/2026/36683/index.asp`), which maps each
`<TD class="event">` (e.g. `222_231 Novice Pairs / Short Program`) to its leaderboard page. That is
the only way to discover them — the site blocks directory listing, and the detail page's name is not
derivable from the leaderboard name.

The ten detail pages below are the reference set the model is checked against; §12 has the fixture
inventory and what is not covered.

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

### 3.2 Protocol PDFs

Two ISU FS Manager documents, one per segment, both `…_JudgesDetailsperSkater.pdf`:

| Event | Document | Segment | Skaters | Element rows |
|-------|----------|---------|--------:|-------------:|
| 2026 Grand Prix Canada, `season2627/gpcan2026` | `FSKWSINGLES-----------QUAL000100--` | WOMEN SHORT PROGRAM | 12 | 84 |
| 2026 Cranberry Cup International, `results/2026/37263` | `FSKMSINGLES-ADVNOV----QUAL000100--` | ADVANCED NOVICE BOYS SHORT PROGRAM | 8 | 48 |

Base URLs: `https://results.isu.org/results/season2627/gpcan2026/` and
`https://ijs.usfigureskating.org/leaderboard/results/2026/37263/`. The second document has the
**Bonus** column (§2.3) — 21 of its 48 rows carry a value in it — so the two together cover both row
shapes. The first document has no event title line, the second does; that is why §4.9 reads the
segment line from the title's neighbours rather than from "the lines above the first skater".

## 4. Parsing model

### 4.1 Approach: tolerant HTML parsing with SwiftSoup

`XMLParser` — or any strict parser — is **out**: the pages are **not well-formed XML** despite
declaring an XHTML doctype. Both page kinds fail Expat on the same construct, plus three more:

```
<H2 class=title>2026 Boston Open</H1>          <!-- mismatched end tag -->
<H2 class=catseg>…</H2><H3>Judges' Details</H2>
&nbsp;                                          <!-- undeclared entity -->
<TABLE class=sum> … border=0 cellSpacing=0     <!-- unquoted attribute values -->
```

Verified: Expat rejects both pages — `not well-formed (invalid token): line 14, column 12`.

Parsing therefore goes through **SwiftSoup 2.14.2** — a tolerant WHATWG HTML5 parser, pure Swift, MIT,
no transitive dependencies — pinned exactly in `Project.swift`. The candidate survey, the comparison
against a hand-rolled scanner, the measured build/binary costs and the two silent bugs that scanner
produced are in `docs/HISTORY.md` → *SwiftSoup adoption*; the dependency policy this decision
exercised is `docs/ARCHITECTURE.md` §2.2.

**Behaviour the parser imposes on us** — our code's job, not the parser's:

- It parses to an **HTML5 tree**, not to our markup: implicit `<tbody>` wrappers, malformed tags
  repaired per spec. Write selectors against the parsed tree (`table.sum`,
  `table.sum tbody td.name`), and keep section pairing as "the next `table.elm` in document order
  after the matched `table.sum`" rather than a positional sibling assumption (§4.4).
- Its `.text()` **normalizes whitespace and drops `&nbsp;`**, so the "is this cell empty" test works on
  it directly — but keep a `\u{00A0}` guard for pages that encode padding differently.
- It is a class-based API and **not `Sendable`**: parsing stays on the actor that calls it, or inside a
  `nonisolated` function that keeps the `Document` local and returns only `Sendable` value types
  (§7.2).
- It is an **implementation detail**: no SwiftSoup type (`Document`, `Element`, `Selector`) may appear
  in a public signature (§7), so the dependency stays replaceable.

Traps 1–8 of the §4.7 checklist are the parser's job under this approach; 9–11 remain ours.

### 4.2 Decoding and text extraction

- Body is `iso-8859-1` per `<meta http-equiv="Content-Type">`. Decode `Data` as UTF-8 first, then
  ISO-8859-1 (Windows-1252 where it matters). None of the ten fixtures contain a byte above ASCII,
  but skater names are free text, so do not skip this.
- Entity decoding is required and small: the pages use only `&nbsp;` and `&lt;`
  (plus the usual `&amp;` `&gt;` `&quot;` `&#nnn;` for safety). `&lt;` matters in element
  abbreviations (`2Lz&lt;&lt;` → `2Lz<<`).
- **Strip markup first, decode entities second.** The reverse order destroys data: `&lt;` becomes a
  literal `<`, which a tag stripper then treats as the start of a tag and swallows — `2Lz&lt;&lt;`
  parses as `2Lz` and `2Lo&lt;+1Lo` as `2Lo`, silently, on 6 of the 16 fixtures.
  Decoding entities is always the *last* text step.
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

### 4.8 Text extraction — PDF (positions out of the content stream)

A protocol PDF has no structure to parse: cells are positioned text runs. Two consequences shape
this path:

- The order runs are **drawn** in is not reading order — the producer emits every abbreviation in the
  block together and then their numbers — so `String` in document order is a column-major scramble.
- The only reliable information about a cell is the text matrix it was drawn with.

`PDFTextLayout` therefore reads the document with `CGPDFDocument` / `CGPDFScanner` and implements the
text-extraction subset of the PDF imaging model:

| Handled | What it carries |
|---|---|
| `q` `Q` `cm` | the graphics-state stack — the rotated `Info` header is drawn inside a rotated `cm`, and its position is meaningless without it |
| `BT` `ET` `Tf` `Td` `TD` `TL` `T*` `Tm` | the text and line matrices, the font and its size, leading |
| `Tj` `TJ` `'` `"` | the drawn strings |
| `/ToUnicode` | each font's CMap: `beginbfchar` and `beginbfrange` (both the `<low> <high> <dst>` and the `<low> <high> [ … ]` forms), UTF-16BE destinations |

Rules:
- A run's origin is its text matrix applied to the current transformation matrix. Runs within
  `0.4 ×` the effective font size of a row's first run share that baseline; that is one row. The
  row's cells are its runs ordered by x, trimmed, empty ones dropped (`PDFTextRow`).
- The producer writes the CMap's entry separators as the **literal characters** `\r\n` (PDFsharp),
  so entries are tokenised by `<…>`/`[`/`]` rather than split on line breaks.
- A font with no `/ToUnicode` falls back to reading its codes as single-byte Latin-1, which is what
  a simple-font page needs; these protocols always ship a CMap.
- CoreGraphics types stay inside `PDFTextLayout`: what leaves it is `[PDFTextRow]`, a value type.
- `PDFTextLayout.isPDF` is the header check (`%PDF-` in the first KB) — content, not URL.

### 4.9 Rows, skater blocks and values — PDF

The document is read as a stream of rows; a skater's block opens at its identity row and its element
rows follow, exactly as in the HTML path (§4.4).

**Identity row** — right-anchored on its four scores, so a name drawn as several runs still reads as
one name, and a printed nation of `AIN1` or `AUT` is accepted:

```
<rank:Int> <name…> <nation: [A-Z0-9]{2,5}> <startingNumber:Int> <total> <tes> <pcs> <deductions>
```

`rows.count < 7`, a non-integer rank, a non-integer start number or a tail that is not four decimals
means the row is not an identity row and is skipped.

**Element row** — `index, abbreviation, info…, base, [x], goe, judges…, [bonus], panel`:

| Cell | Handling |
|---|---|
| `cells[0]` | element index (required, `Int`) |
| `cells[1]` | abbreviation, verbatim — `3Fq`, `3Lz+3T`, `3Lzb` |
| info markers (`F`, `q`, `!`, `*`, …), `x` | **never read** (§10a) |
| the decimal cells, in order | `base`, `goe`, `bonus`, then `panel` last |

So the panel score is the **last** decimal cell and the ones before it are base, GOE and — only when
the document has a bonus column and the row carries one — bonus. Judge marks are integers and are not
decimal cells, which is what makes the rule work at all; a row with fewer than two decimal cells is
not an element row, and more than four is `.malformedElementRow`. `base + goe + bonus == panel` is
then the same invariant as §5.2, and holds for all 132 fixture rows.

**Titles** — the segment line is the row directly under `JUDGES DETAILS PER SKATER`, and the event
title, when the document has one, is the row directly above it. The column headers follow the segment
line, so "the lines before the first skater" is not a usable definition.

**Validation** — element indices must run 1…N within a block (`.malformedElementRow`), and a block
with no element rows is `.elementTableMissing`. Rows that are neither (the totals line, the
program-components block, the `Deductions:` line, and the page header a page break repeats) are
skipped by shape, so a block may continue across a page boundary.

## 5. Values and units

### 5.1 Integer hundredths

The module emits **`Int` hundredths** (`2.10` → `210`, `-0.26` → `-26`, `1.00` → `100`) — the
project-wide convention (see `docs/ARCHITECTURE.md` §3.1). This is not optional: it is what lets
the parser's output drop straight into `ElementData(baseValue:goeValue:bonusValue:)`.

Conversion rules (module-local `ProtocolNumber`, shared by both parsers; the app's
`String.toHundredthsInt()` is `internal` to the app target and cannot be reached from here):
- Trim, decode entities, then parse an optional sign, digits, optional `.` + 1–2 digits. Scale by
  100 — `0.5` → `50`. Do not silently accept a 3rd decimal.
- **Track the sign separately from the integer part.** `Int("-0") == 0`, so a reader that infers the
  sign from the whole-number component turns `-0.90` into `+90`. The failure is invisible except for
  the §5.2 invariant — the numbers still look like plausible scores. Test it directly:
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
the first comma, so the app can decide what goes into `OverlayData.skaterFullName`. A PDF page's name
carries no club (§2.3), so there `namePart` is the whole cell and the club rung of the ladder is
simply never reached.

The matcher itself lives on `ProtocolSegment` (`skater(named:)`) and is shared by both document
kinds; `ProtocolHTMLParser.skater(named:in:)` stays as the documented HTML entry point and forwards.

Elements with **no value** are always imported (§10c): `CoSp` / `FSSp` rows where the skater
attempted an element the panel did not credit (`0.00` base, all `-` judge marks) produce a record
with zeros, per "each element corresponds to an `ElementData` record". There is **no filter and no
"skip empty elements" option** — the protocol lists the element, so the import keeps it. It renders
neutral grey by the existing color rule (`baseValue == 0` → `.neutral`).

## 7. Public API

Module-level design constraints: no app types (§8), no I/O inside the parser (§7.2), everything
`Sendable`; the model types and the parsing entry points are `nonisolated` so parsing can move off
the main actor without restructuring (every target is MainActor-isolated by default — `Project.swift`
`baseSettings`). **A `nonisolated` type's extensions are still MainActor-isolated** unless each
extension declares it too.
**No type is named `ProtocolParser`** — that would collide with the module name (the project uses
`VideoComposer` in the `VideoProcessor` module, not `VideoProcessor`).
**The HTML parser is an implementation detail**: no `SwiftSoup` type (`Document`, `Element`,
`Elements`, `Selector`) may appear in a public signature, and the app never imports the package — so
the dependency stays replaceable and its behaviour cannot leak into call sites.

### 7.1 Model (hundredths; no UI, no naming policy)

```swift
public nonisolated struct ProtocolElement: Sendable, Equatable, Hashable {
    public let index: Int             // 1-based, contiguous
    public let abbreviation: String   // raw + entity-decoded: "3Tb1+2T", "2Lz<<", "StSq2+kpYYNN"
    public let baseValue: Int         // hundredths
    public let goeValue: Int          // hundredths, may be negative
    public let bonusValue: Int        // hundredths; 0 when the column is empty
    public let panelScore: Int        // hundredths; validation only (§5.2)
}

public nonisolated struct ProtocolSkater: Sendable, Equatable {
    public let name: String           // "Milo Yeon, SC of Boston" (verbatim)
    public let elements: [ProtocolElement]
    public var namePart: String       // "Milo Yeon"
    public var club: String?          // "SC of Boston"
}

public nonisolated struct ProtocolSegment: Sendable, Equatable {
    public let eventName: String      // "2026 Boston Open"
    public let categorySegment: String// "101_109 Champ Intermediate Men / Free Skate"
    public let skaters: [ProtocolSkater]
}
```

All three declare public memberwise inits: the app builds them directly in its own unit tests (the
§8.1 merge test needs a `ProtocolSkater` and must not parse HTML or touch the network).

### 7.2 Pure parsing surface

```swift
public nonisolated enum ProtocolPageKind: Sendable, Equatable {
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

public enum ProtocolPDFParser {            // nonisolated, sync, no network, no state
    /// The document's own header (`%PDF-`), not the address it was fetched from.
    public static func isPDF(_ data: Data) -> Bool

    /// Throws .unreadablePDF for bytes CGPDFDocument cannot open, .unrecognizedPage for an open PDF
    /// that is not a judges-details protocol.
    public static func parseSegment(data: Data) throws -> ProtocolSegment
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
    func fetchData(_ url: URL) async throws -> Data      // bytes: the body may be HTML or a PDF
}
extension ProtocolFetching {
    public func fetchText(_ url: URL) async throws -> String   // UTF-8, then ISO-8859-1
}
public struct URLSessionProtocolFetcher: ProtocolFetching {   // GET, no cache (pages send no-cache)
    public init()
}

public struct ProtocolImporter: Sendable {
    public init(fetcher: ProtocolFetching = URLSessionProtocolFetcher())

    /// URL of either page kind or a protocol PDF — classified by its bytes, and followed if it is a
    /// leaderboard page.
    public func skater(named: String, at url: URL) async throws -> ProtocolSkater

    /// Content supplied directly (paste / file / test), optionally with its URL for resolving the
    /// relative detail link. `async` because supplied leaderboard content still has to fetch the
    /// detail page it links to; supplied detail content and a PDF need no network.
    public func skater(named: String, in data: Data, baseURL: URL? = nil) async throws -> ProtocolSkater
    public func skater(named: String, inHTML html: String, baseURL: URL? = nil) async throws -> ProtocolSkater
}
```

The seam hands over **bytes**, not text: whether the document is an HTML page or a PDF is a fact
about its content, and the importer is the only component that should have to know it. `fetchText`
keeps the HTML path reading as before.

`ProtocolFetching` is declared `nonisolated`: every target is MainActor-isolated by default
(`Project.swift` `baseSettings`), so a plain protocol declaration would be MainActor-only and no
actor — nor any off-main fetcher — could conform to it. The same applies to anything else in this
module that is implemented off the main actor.

Control flow:

```
url ──fetchData──▶ bytes ──┬─ isPDF ─▶ parseSegment(data:) ──────────────┐
                           │                                             │
                           └─ text ─▶ pageKind ─┬─ .leaderboard ─▶ judgeDetailLink(relativeTo: url)
                                                │                    └─ fetchData ─┬─ isPDF ─▶ parseSegment(data:)
                                                │                                  └─ text ─▶ must be
                                                │                                              .segmentDetail
                                                │                                              else .unrecognizedPage
                                                └─ .segmentDetail ─┐
                                                                   ▼
                    parseSegment ─▶ ProtocolSegment ─▶ skater(named:) ─▶ ProtocolSkater
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
    case unreadablePDF                                     // corrupt, truncated or password-protected
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
    convenience init(_ element: ProtocolElement,           // displayTime stays nil — the app sets timing
                     translator: ElementNameTranslating = ElementNameExpander()) {
        self.init(name: translator.displayName(for: element.abbreviation),   // "3Tb1+2T" → "3 Toeloop + 2 Toeloop"
                  baseValue: element.baseValue,
                  goeValue: element.goeValue,
                  bonusValue: element.bonusValue)
    }
}
```

### 8.1 Merge policy — index-keyed, and it never discards timing

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

1. asks for the protocol address (`TextField` in an alert; **either HTML page kind or a protocol PDF
   is accepted** — the importer decides from the downloaded bytes, and a leaderboard page is followed
   to its judge-detail page when that has been published);
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

## 9. Abbreviation → display name

`ElementData.name` receives the abbreviation's **display name**, because the app's import calls the
translator (§8). The translator is a single component with an **identity default**, so its absence is
not a failure mode.
**The rules are implemented in this module — `ElementNameExpander.swift` plus its `+Pairs` and
`+Dance` extensions — and specified in
[`docs/architecture/abbreviation-expansion.md`](abbreviation-expansion.md)** — that document owns the
jump / spin / step-sequence / choreographic / throw / lift / twizzle / pattern-dance vocabulary and
the marker handling; this section keeps only the seam and the token inventory.

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

Implemented shape (`ElementNameExpander`): tokenize on `+`, map each token through the table, keep
unknown tokens verbatim, and reassemble — so an unrecognized token degrades to the abbreviation
instead of failing the import. **Pairs and ice-dance codes are not expanded yet**; they pass through
verbatim by this rule.

## 10. Decisions (all resolved)

Letters are stable — other sections and `docs/ARCHITECTURE.md` reference them. **Nothing in this
document is still open.** Each decision is a rule, and the section in parentheses owns it.

| # | Decision |
|---|---|
| a | The `info` column is **never used** — not parsed, not carried on `ProtocolElement`, no later component may depend on it. The abbreviation is the sole element identity (§4.6, §9). |
| b | **No leaderboard-page data is used for anything except locating the judge-detail link.** With the link absent the import ends in `.detailLinkMissing`: the user waits for the organizer to publish judge details and retries (§7.3). |
| c | Zero-value rows (`0.00` base, all-`-` judge marks — uncredited `CoSp`/`FSSp`) are **always real elements, always imported**. No filtering and no "skip empty elements" option; they render neutral grey by the existing rule (§6). |
| d | Import **replaces values in place, keyed by element index, and never discards timing** — `displayTime` survives a re-import, surplus protocol elements are appended untimed, surplus existing entries are left untouched (§8.1). |
| e | The total column (`psv`) is **kept for sanity checking only** — never displayed, never summed into anything. It exists to verify `bv + goe + bonus == panelScore` and to let a disagreement surface in the UI (§5.2). |
| f | **No navigation to sibling segments, ever.** Only the `judgeDetailRef` anchor is followed; the app passes the per-segment page (§7.3). |
| g | **SwiftSoup `2.14.2` is the parsing implementation** (§4.1, §13). |
| h | **The document decides the parser, not the address.** The importer sniffs `%PDF-` in the fetched bytes, so a pasted protocol address works whether it serves an HTML page or a PDF, and the URL never has to be inspected (§4.8, §7.3). |
| i | **The PDF path reads positions out of the content stream with CoreGraphics, not PDFKit.** PDFKit's `page.string` returns these tables column-major (abbreviations first, then the numbers) and its per-character bounds are wrong on this producer's files, so neither the text order nor a bounds-based rebuild can recover the table. `CGPDFScanner` + `/ToUnicode` gives every cell's true origin (§4.8); the measurements are in `docs/HISTORY.md` → *Protocol PDF*. |
| j | **A PDF's numeric columns are read by position, never by header.** Bonus is headed `Bonus` (not `ref`), `Ref.` is the referee's column, and a document may omit either — base, GOE, bonus and the panel score are recognised as the decimal cells in x order, with `base + goe + bonus == panel` as the check (§4.9, §5.2). |

## 11. Testing

Fixtures are HTML files committed under
`LayoutEngine/ProtocolParser/ProtocolParserTests/Fixtures/` — **eleven detail pages and two
leaderboard pages, ~900 KB** (the ten of §3's table plus `SEGM033.html`, the sibling segment the link
test needs), and two synthetic pages (a leaderboard page with the judge-detail
block removed; a detail page with one Base Value cell removed). Text, so no untracked-large-file
caveat like the 398 MB sample video. The sweep asserts over the committed set: **825 element rows**.
Beside them sit the **two protocol PDFs of §3.2** (535 KB together), read as bytes — no resource
bundle, since `Fixture` resolves them from this source file's own directory.
**Tests never hit the network** — `ProtocolFetching` is the seam; use a fake that returns fixture
content (the pattern `VideoProcessorTests` uses with `FakeRenderer`).

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
| 15 | `ProtocolPDFParser.isPDF` on both PDFs, on an HTML page, on empty data | `true`, `true`, `false`, `false` |
| 16 | `parseSegment(data:)` on the women's short program PDF | 12 skaters in rank order, 7 elements each, `categorySegment == "WOMEN SHORT PROGRAM"`, no event title |
| 17 | The advanced novice men's short program PDF | 8 skaters, event `2026 CRANBERRY CUP INTERNATIONAL`, category `ADVANCED NOVICE BOYS SHORT PROGRAM` |
| 18 | Mao Shimada's elements (frozen table) | 7 rows — `3A` 800 + 251 = 1051 … — exactly as §4.9, with `bonusValue == 0` on every one |
| 19 | Bonus column | `3Lzb` → base 590, GOE −118, bonus 100, panel 572; a row with no bonus cell → `bonusValue == 0` |
| 20 | **PDF invariant sweep** over both documents | `bv + goe + bonus == psv` on **132/132** rows, indices contiguous 1…N in every block |
| 21 | Second-half flag and info markers | `3Lz+3T` row with `x` → base 1111/GOE 177; `q` in the Info cell leaves the abbreviation `3Fq` |
| 22 | Importer routing | a PDF body at a `.html` address takes the PDF path (one fetch); an HTML body still takes the HTML path |
| 23 | Rejections | HTML bytes / empty data → `.unreadablePDF`; a CoreGraphics-made PDF of unrelated text → `.unrecognizedPage` |

Indices are 1-based in test expectation tables so they read like the protocol.

Tests 1, 3, 7b and 12 (tag soup, entities, unquoted attributes, case) exercise SwiftSoup as much as
us. What stays ours is classification and link selection (1–3), the extraction contract (4–5, 7–9),
the matcher (10) and the error paths (11). **Test 6 is the highest-value one and must be kept
regardless of parser:** it asserts the page's own arithmetic against the values we extracted, and it
is what caught the sign bug (§5.1) that would otherwise have shipped plausible-looking wrong
scores. Tests 15–23 are the PDF suite (`ProtocolPDFParserTests`), and **test 20** plays that same
role there: 132 rows of the document's own arithmetic against what the extractor read.

## 12. Fixture inventory and known gaps

**Provenance:** the live event *2026 Boston Open*, id `36683` — its leaderboard pages, the event index
and the ten segment detail pages of §3 (five singles, five pairs) — with every structural claim taken
from the raw markup, plus the two ISU FS Manager PDFs of §3.2. **Not covered:** ice dance, a
withdrawn-skater page (no `elm` table; no `Withdrawn`/`WD`/`DNS` marker appears in any fixture), a
PDF segment whose elements split across a page break, a scanned/image-only PDF, and other events or
eras of ijsLive or of the FS Manager report.
`docs/HISTORY.md` → *Protocol parser* and → *Protocol PDF* have the verification runs, the counts
that moved and the spec corrections the implementations forced.

Fixtures live in `LayoutEngine/ProtocolParser/ProtocolParserTests/Fixtures/` — eleven detail pages,
two leaderboard pages, two synthetic pages, ~900 KB of text, and two PDFs (535 KB):

| Measure | Count |
|---|---|
| Element rows across the eleven detail pages (the §11 sweep's scope) | **825** |
| Element rows across the ten reference pages of §3 | **717** (535 singles + 182 pairs) |
| Rows with an empty bonus cell | **696** |
| Distinct abbreviations | **241** (187 singles + 66 pairs) |
| `bv + goe + bonus == psv` violations | **0** |
| Element rows across the two PDFs | **132** (84 + 48) |
| PDF rows with a bonus cell | **21** |
| PDF skaters | **20** (12 + 8) |

## 13. Dependencies

- **SwiftSoup** (SPM, `https://github.com/scinfu/SwiftSoup.git`, pinned exact `2.14.2`, MIT) — the
  tolerant HTML5 parser (§4.1). Integration is a `packages:` entry in `Project.swift` plus
  `.package(product: "SwiftSoup")` on the `ProtocolParser` target. Candidate survey and measurements:
  `docs/HISTORY.md` → *SwiftSoup adoption*; policy: `docs/ARCHITECTURE.md` §2.2.
- **CoreGraphics** (`CGPDFDocument`, `CGPDFScanner`, `CGPDFContentStream`) — reading a protocol PDF
  (§4.8). An Apple framework, already linked; no package.
- `Foundation` — `URL`, `URLSession`, `Data`, `String`, `LocalizedError`.
- No other package, and no import of the app, `LayoutEngine` or `VideoProcessor`.
