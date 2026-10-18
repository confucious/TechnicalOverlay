# Element Abbreviation Expansion

**Source:** `LayoutEngine/ProtocolParser/ProtocolParser/ElementNameExpander.swift`, tests in
`LayoutEngine/ProtocolParser/ProtocolParserTests/ElementNameExpanderTests.swift`

Status: **implemented and wired into the app, for all three vocabularies.** The rules in §4.2–§4.12
are in `ProtocolParser` — `ElementNameExpander.swift` plus the `+Pairs` and `+Dance` extensions — and
the import writes display names into `ElementData.name` (§7). Test counts are in
[`docs/testing.md`](../testing.md). This document is the authoritative specification for the
component, and is the translator `docs/architecture/protocol-parser.md` §9 specifies (an
abbreviation → display-name component with an identity default). **§4 is the specification and §5 the worked examples; earlier
drafts are superseded** (`docs/HISTORY.md` → *Element abbreviation expansion*).

## 1. Purpose

Turn a raw protocol abbreviation — `3Tb1+2T`, `2Lz<<`, `CCoSpBV`, `StSq4b0.5+kpYYYY`, `3Tw3`,
`5ALi4`, `ChPSp1`, `StaLi4+RoLi4`, `1GW2+kpYNNY` — into the name shown on the overlay and in the
scoring list: `3 Toeloop + 2 Toeloop`, `2 Lutz`, `Change Combo Spin B V`, `Step Sequence 4`,
`3 Twist Lift 3`, `5 Axel Lasso Lift 4`, `Choreo Pair Spin 1`, `Stationary Lift 4 + Rotational
Lift 4`, `Golden Waltz 1 2`.

**In scope:** the element codes of the singles, pairs and ice-dance protocols — jumps and their
combinations and sequences, solo and combination spins, step sequences, the choreographic family and
the creative dance element; pairs throws, twist lifts, pair lifts, death spirals, pivot figures and
pair spins; dance spins, dance lifts, twizzle sets, dance step sequences, one-foot turns and the
pattern-dance element codes — plus the markers and call tokens a published protocol carries.

**Out of scope (explicitly):**

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

Pairs and dance pages use the same table layout as singles (`class=elem` / `class=info` /
`class=bv` / `class=goe`, `protocol-parser.md` §2.2), so the input needs no parser change.

### 2.2 Real shapes, quoted from the fixtures (singles)

| Shape | Real examples from the ten fixture pages' singles rows |
|---|---|
| jump, numbered | `3T`, `2Lz`, `1A`, `3A`, `4T` |
| jump + bonus | `3Tb1`, `3Sb1`, `3Lob1`, `3Lz<b1`, `3Fb1` |
| jump + rotation/edge marker | `2A<`, `3Lo<<`, `2Lz!`, `2Lze`, `2F!`, `3Lzq`, `1Lze` |
| jump + invalid flag | `1Lz*`, `1A*`, `1T*`, `2S*` |
| combination / sequence | `3Tb1+2T`, `3F+3Tb1`, `2A+Eu+2F`, `3S+1A+2T+SEQ`, `2Lz+SEQ+1A*+2Lo*` |
| call tokens | `+SEQ`, `+COMBO`, `+REP` (`2Lz+COMBO`, `2Fq+REP`, `3Lo+REP`, `T+COMBO+2T*+REP`, `3S+1A+2T+SEQ`) — all three reach the output, as published (§4.5) |
| dangling jump | `A`, `A*`, `T`, `Lo*`, `Lz*` (the jump through which a repeat fell apart) |
| spin | `CCoSp4`, `FSSp3`, `CCoSp1V`, `CCoSpBV`, `CSp2`, `CoSp`, `FSSp` |
| step sequence | `StSq2+kpYNNN`, `StSqB+kpNNNN`, `StSq4b0.5+kpYYYY` |
| choreographic | `ChSq1`, `ChSp1`, `pChSq1` |

### 2.3 Tokenization

**Split on `+` first.** Every abbreviation is a `+`-joined token list; the tokens are the unit the
rules operate on. Two consequences visible in the fixtures:

- `+kp…` is a **separate token** (`StSq4b0.5` + `kpYYYY`), not a suffix of the `StSq` token — so
  "ignore the `+kp` addition" is a token-drop rule, not a string trim.
- In `2Lz+SEQ+1A*+2Lo*` a call token sits **between** jumps, so it keeps its position in the
  joined output rather than being moved to the end (§4.5).

Then **recombine the two halves of a two-partner element before rendering** (§4.8). The split stays
the unit of classification: a lift combination's halves are two elements and classify separately; a
twizzle set's or step sequence's halves are one element and are rejoined.

### 2.4 Traps that decide the implementation

| # | Trap | Evidence |
|---|---|---|
| 1 | **`q` is both a marker and a letter of `StSq`/`ChSq`.** Stripping marker characters as a blanket character class turns `StSq2` into `StS2` and `ChSq1` into `ChS1`, and those tokens then fail to classify. Markers are a **suffix on a jump token only**. | `StSq2` ×21, `ChSq1` ×16 |
| 2 | **The bonus marker is not positionally fixed.** `b1` follows the jump (`3Tb1`) but also follows a marker (`3Lz<b1`, `3S<b1`), so stripping "marker then bonus" in a fixed order fails on 4 tokens. | `3Lz<b1` ×2, `3S<b1` ×2 |
| 3 | **Spin codes are prefixes of each other and end in `Sp`.** `CSp` ⊂ `CCSp`, `SSp` ⊂ `FSSp`/`CSSp`, `CoSp` ⊂ `CCoSp`/`FCoSp`, `CSp` ⊂ `FCSp`. Classification must match the **longest known code first**, whole-token. | 34 distinct spin tokens |
| 4 | **A jump letter alone is not a jump.** `S` is also the tail of `SSp`/`FSSp`/`CSSp`, `F` of `FSSp`, `T` of `StSq`(no) but `Tw`/`Th` in pairs. Jump matching may only run on a token that did not match the spin/step/choreographic table, and the remainder after the jump code must be **markers only** — otherwise `3STh` (a throw) would expand as a Salchow. | `3STh` in the pairs fixtures |
| 5 | **A jump token can have no rotation number.** `A`, `T`, `A*`, `Lo*`, `Lz*` — the requirement's rule assumes a number exists. | 5 tokens / 11 rows |
| 6 | **`Eu` carries no number.** Only the bare `Eu` appears (4 tokens); the rule below is stated so a hypothetical `1Eu` still renders `Euler`. | `Eu` ×4, no `1Eu` |
| 7 | **`S` is a dance marker and the Salchow code**; `e` is a dance error marker, the singles wrong-edge marker **and the last letter of `SpEe`/`CrEe`/`IBEe`**; `>` only ever marks an extended lift. Markers therefore belong to the branch that owns the token, never to a shared character set (§4.6) — and a dance code must be offered to the dance rules with and without the shared trailing strip, or those three edge elements lose their final letter before anything looks at them. | `SqTw…S` on a dance page; `3S` on any singles page; `SpEe` |
| 8 | **`Sq` means two things**: *sequential* in `SqTw` (a twizzle set) and *sequence* in a pattern-dance code (`FO1Sq4`). Position decides; never unify them. | `SqTwW4+SqTwM4` and `FO1Sq4+kpYYYY` |

### 2.5 What pairs and ice dance add

| | Singles | Pairs / dance |
|---|---|---|
| Element combos | jump combinations: several **elements** | every `+`-joined pair is **one element** with two halves — two lifts (`StaLi4+RoLi4`), two partners (`SqTwW4+SqTwM4`, `MiStW1+MiStM2`) |
| Numbers | one (revolutions) | two on some codes — group/revolutions then level (`4Li3`, `3Tw3`, `PSp4`) |
| Level | spins and step sequences only | almost everything, and a dance half may have **no** level (`SqTwM`) |
| Partner | — | `W` / `M` suffix marks whose level it is |
| Key points | `+kp…` | the same token, on pattern-dance elements |
| Markers | `<` `<<` `!` `e` `q` `b…` `*` | those plus `S`, `>`, `ExEI`, and `<`/`<<` meaning "reduce the level" |

## 3. Reference pages and the measured inventory

### 3.1 Singles

Source: the committed segment pages under
`LayoutEngine/ProtocolParser/ProtocolParserTests/Fixtures/` — the five singles pages `SEGM001`,
`SEGM011`, `SEGM015`, `SEGM021`, `SEGM034`. These are the pages the parser doc already lists as
parsed and invariant-checked (`protocol-parser.md` §3, §12).

| Measure | Count |
|---|---|
| Element rows (singles) | **535** |
| Distinct abbreviations | **187** |
| Distinct `+`-separated tokens | **119** |
| Tokens that are jumps | 460 |
| Tokens that are spins | 126 |
| Tokens that are step sequences / choreographic | 94 |
| Call tokens, all shown (§4.5): `SEQ` / `COMBO` / `REP` | 38 / 6 / 8 |
| Tokens to be dropped (`kp…`) | 47 |
| Rows carrying at least one marker or bonus (`<`/`<<`/`!`/`e`/`q`/`*`/`b…`) | 157 of 535 |
| Rows whose every token the rules below classify once `kp…` is dropped | **535 / 535** |
| Rows carrying a `COMBO` or `REP` | 13 of 535 |
| Rows carrying any call token (`SEQ` + those) | 51 of 535 |
| Abbreviation length → expansion length | mean 5.7 → 14.5 chars; max 18 → 50 |

Marker census over those 535 rows (`<` 42 rows, `<<` 8, `!` 10, `e` 6, `q` 9, `*` 12, `b1`/`b0.5` 18)
is why §4.6 ignores markers rather than rejecting a row.

### 3.2 Pairs and ice dance

**Pairs:** the five pairs pages already committed — `SEGM026`, `SEGM028`, `SEGM030`, `SEGM031`,
`SEGM032` (`protocol-parser.md` §3).

**Ice dance:** thirteen pages from the Challenge Cup 2026 protocol set
(`https://ijs.usfigureskating.org/leaderboard/results/2026/37064/`, detail pages `SEGM001`–`SEGM009`
and `SEGM018`–`SEGM021`), committed beside the existing pages as
`ProtocolParserTests/Fixtures/ChallengeCup-SEGMnnn.html`. They cover juvenile, novice, intermediate,
junior and senior partnered dance: six pattern-dance pages and seven rhythm/free-dance pages. Nine
further pages in that event (the solo pattern dances and the solo/adult free dances) carry **no
element table at all**; they are not part of this set (§7.2).

| Measure | Pairs | Ice dance |
|---|---:|---:|
| Element rows | **182** | **247** |
| Distinct abbreviations | **66** | **121** |
| Distinct `+`-separated tokens | **63** | **125** (110 once `kp…` is set aside) |
| Distinct tokens per family | throws 6, twist lifts 8, pair lifts 17, death spirals 6, pivot 1, pair spins 5, choreo-pair 2, solo jumps 11, `SEQ` 1 | twizzle sets 12, dance steps 21, dance lifts 13, dance spin 5, choreo 5, creative 1, pattern dance 39 (RPD 30, named 9), `kp…` 15 |
| Rows carrying a pairs/dance-specific token | **127 / 182** | **219 / 247** |
| Rows whose every token the rules below classify | **182 / 182** | **247 / 247** |
| Abbreviation length → expansion length | mean 4.9 → 14.4; max 11 → 31 | mean 10.1 → 20.7; max 15 → 40 |

The last two rows of each table are the numbers the sweeps freeze: a row that falls back to verbatim
is otherwise silent, because the output still looks like a name. The pairs and dance counts are what
the sweeps assert (§9).

## 4. Expansion model

§4.2–§4.4 are the singles vocabulary, §4.10–§4.12 are pairs and ice dance, and §4.5–§4.9 are the
rules all three share.

### 4.1 Pipeline

```
abbreviation
  └─ split on "+"                                        → [token]
       └─ per token: strip "*" (remember it), strip b<digits>[.<digits>] anywhere, strip the
          trailing marker run the token's own branch owns           (§4.6)
            ├─ token is "SEQ" | "COMBO" | "REP" | "ExEI"  → keep the token verbatim   (§4.5)
            ├─ token starts with kp                      → drop the token entirely    (§4.6)
            ├─ StSq<level>                               → §4.4
            ├─ a choreographic code: ChSq, ChSp, ChSt, ChSl, ChLi, ChAJ, ChPSp,
               ChPLi, pChSq, pChSt, or CDE<level>        → §4.4
            ├─ a spin code, incl. PSp / PCoSp / DSp       → §4.3 (longest code first)
            ├─ <n><jump>Th, <n>Tw<level>, <n>Li<level>, 5XLi<level>,
               (Fi|Fo|Bi|Bo)Ds<level>, PiF<level>         → §4.10
            ├─ (Sq|Sy|pST)Tw<W|M><level>, (Mi|Di|Ci|Se)St<W|M><level>,
               OFT<W|M><level>, (Sta|Sl|Si|Cu|Ro)Li<level>,
               SoTw<level>, PSt<level>, SpEe / CrEe / SeEs / IBEe<level>
                                                          → §4.11
            ├─ a pattern-dance element code               → §4.12
            ├─ <number?> <jump code> + markers-only tail  → §4.2
            └─ nothing matched                           → keep the raw token verbatim (§4.9)
  └─ recombine two-partner halves (§4.8), then join the surviving parts with " + "  (§4.8)
```

Classifier ordering is a correctness requirement, not a style choice — see traps 1, 3, 4, 7 and 8
(§2.4). Three rules follow from it:

- **New branches run before the jump rule.** The jump rule accepts a single letter code with an
  optional leading number, so it stays the last resort; everything else narrows first.
- **Every table is matched longest-code-first, whole token.** `CSp` ⊂ `CCSp`, `PSp` ⊂ `PCoSp`,
  `ChSq`/`ChSp`/`ChSl`/`ChSt` share three letters — a first-match walk over an unordered table
  mis-expands all of them.
- **Markers are stripped only inside the branch that owns the token** (§4.6), never as a blanket
  character class.

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
- The same rule covers **pairs solo jumps** (`2F<` → `2 Flip`, `3Tb1+2A+SEQ` → `3 Toeloop + 2 Axel
  + SEQ`). A throw is not a jump; it is §4.10.

### 4.3 Spins

`<spin name> <level>`, with `V` (reduced value) after the level **separated by a space**. The
level is one of `B`, `1`, `2`, `3`, `4`.

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
| `CoSp`   | Combo Spin                     | ✅ `CoSp`                                                                 |
| `CCoSp`  | Change Combo Spin              | ✅ `CCoSpB`…`CCoSp4`, `CCoSp1V`, `CCoSp2V`, `CCoSp3V`, `CCoSpBV`, `CCoSp` |
| `FCoSp`  | Flying Combo Spin              | —                                                                        |
| `FCCoSp` | Flying Change Combo Spin       | ✅ `FCCoSp3`, `FCCoSp4`                                                   |
| `PSp`    | Pair Spin                      | ✅ `PSp1`–`PSp4`, `PSpB` (pairs)                                          |
| `PCoSp`  | Pair Combo Spin                | — (pairs)                                                                |
| `DSp`    | Dance Spin                     | ✅ `DSp1`–`DSp4`, `DSpB` (dance)                                          |

(— = a valid ISU code that does not occur in these fixture pages; it must still be in the table, since
someone's protocol may use it. The list is the ISU abbreviation set.) 34 distinct singles spin tokens
appear, and they justify every entry on the ✅ singles rows.

Behaviour:

- `CCoSp4` → `Change Combo Spin 4`; `CSp2` → `Camel Spin 2`; `FSSpB` → `Flying Sit Spin B`;
  `DSp2` → `Dance Spin 2`; `PSpB` → `Pair Spin B`.
- **`V` follows the level, space-separated**, including the `B` level: `CCoSp1V` →
  `Change Combo Spin 1 V`, `CCoSpBV` → `Change Combo Spin B V`.
- **No level** → the name alone, nothing appended: `CoSp` → `Combo Spin`, `CCSp` → `Change Camel
  Spin`. These are the uncredited rows the parser already imports with zero values
  (`protocol-parser.md` §6) — the site prints the code with no level for them.
- `V` where no level is present: not observed; the grammar allows `(B-4)V`, so the same rule covers
  it — `CoSpV` would read `Combo Spin V`. Pairs and dance codes carry no `V`: their level alphabet
  is `B`,`1`–`4`.

### 4.4 Step sequences and choreographic elements

| Code          | Expansion                | Notes                                                                        |
| ------------- | ------------------------ | ---------------------------------------------------------------------------- |
| `StSq<level>` | `Step Sequence <level>`  | level `B`, `1`–`4`. `StSqB` → `Step Sequence B`, `StSq4` → `Step Sequence 4` |
| `ChSq1`       | `Choreo Sequence 1`      | the trailing `1` is shown                                                    |
| `ChSp1`       | `Choreo Spin 1`          | the trailing `1` is shown; this code is singles *and* dance                   |
| `pChSq1`      | `Choreo Sequence 1`      | the `p` prefix is not shown; the `1` is                                       |
| `ChSt1`       | `Choreo Char Step Sequence 1` | dance: the choreographic character step sequence                        |
| `pChSt1`      | `Choreo Step Sequence 1` | dance: the juvenile/adult free-dance form of the same idea                    |
| `ChSl1`       | `Choreo Slide 1`         | dance: choreographic sliding movement                                         |
| `ChLi1`       | `Choreo Lift 1`          | dance                                                                        |
| `ChAJ1`       | `Choreo Assisted Jumps 1` | dance                                                                       |
| `ChPSp1`      | `Choreo Pair Spin 1`     | pairs                                                                        |
| `ChPLi1`      | `Choreo Pair Lift 1`     | pairs                                                                        |
| `CDE<level>`  | `Creative Dance Element <level>` | level `B`, `1`–`4`; senior rhythm dance only                          |

- `StSq…b0.5` carries a bonus marker: `StSq4b0.5` → `Step Sequence 4`.
- The `+kp…` token is dropped (§4.6), so `StSq2+kpYNNN` → `Step Sequence 2` with **no dangling
  separator**. 47 of the 535 rows carry a `kp…` token.
- **The word `Choreographic` is shortened to `Choreo`, every choreographic code keeps its trailing
  digit, and a `p` prefix is dropped.** `ChSt1` and `pChSt1` are different elements, so their names
  differ in more than the prefix.

### 4.5 Call tokens and the extra-element token

| Token | Rule | Example |
|---|---|---|
| `SEQ` | kept in place, uppercase as published, separated by the same ` + ` | `3S+1A+2T+SEQ` → `3 Salchow + 1 Axel + 2 Toeloop + SEQ` |
| `COMBO` | kept in place | `2Lz+COMBO` → `2 Lutz + COMBO` |
| `REP` | kept in place | `3Lo+REP` → `3 Loop + REP` |
| `ExEI` | kept in place (dance: an extra element) | `RoLi4+ExEI` → `Rotational Lift 4 + ExEI` |

`SEQ`, `COMBO` and `REP` are calls the technical panel made rather than elements — a combination that
did not complete, a jump that was repeated — and they are shown as published. They are common: **52
tokens over 51 of the 535 singles rows** (`SEQ` 38, `COMBO` 6, `REP` 8, one row carrying both `COMBO`
and `REP`). A call token keeps its position, even mid-abbreviation:

| Input | Output |
|---|---|
| `2Lz+COMBO` | `2 Lutz + COMBO` |
| `T+COMBO+2T*+REP` | `Toeloop + COMBO + 2 Toeloop (Invalid) + REP` |
| `2Lz+SEQ+1A*+2Lo*` | `2 Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)` |

### 4.6 Ignored tokens and markers

| Ignored | Meaning on the protocol | Rule |
|---|---|---|
| `b1`, `b0.5` | bonus for a difficult element | stripped from the name anywhere in the token; the value is already in `bonusValue` |
| `<` | under-rotated jump; on a pattern-dance code, one level less | stripped (trailing marker run) |
| `<<` | downgraded jump or twist; on a pattern-dance code, two levels less | stripped |
| `!` | unclear edge | stripped |
| `e` | wrong edge on a jump; on a choreographic element, the element did not fulfil its requirements | stripped |
| `q` | quarter-short of rotation | stripped |
| `S` | dance: reduce one level (separation or loss of contact on `PSt`, `SyTw`, `SqTw`, `OFT`) | stripped **inside the dance rules only** |
| `>` | dance: an extended lift | stripped inside the dance rules only |
| `kpNNNN`, `kpYNNN`, … | step-sequence key points | the whole token is **dropped** |

**Markers belong to the branch that owns the token. Do not hoist them into one character set.** `S`
is the Salchow code and the dance separation marker (trap 7); `e` is the singles wrong-edge marker
and the dance error marker; `q` is a marker and a letter of `StSq`/`ChSq` (trap 1); `>` never appears
outside a dance lift. A blanket strip either destroys codes or stops elements classifying, silently.

### 4.7 The invalid flag `*`

`*` marks an element the panel did not credit (a repeat beyond the allowance). It is rendered as
`(Invalid)` **on the token it belongs to**, in every vocabulary:

| Input | Output |
|---|---|
| `1Lz*+COMBO` | `1 Lutz (Invalid) + COMBO` |
| `2Lz+SEQ+1A*+2Lo*` | `2 Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)` |
| `3Sb1+COMBO+1T*` | `3 Salchow + COMBO + 1 Toeloop (Invalid)` |
| `A*` | `Axel (Invalid)` |

### 4.8 Joining, and recombining two-partner halves

Surviving parts are joined with **` + `** (one space on each side) — the requirement's separator,
applied after markers are stripped and the `kp…` tokens are dropped, so no separator is left
dangling and no empty part is emitted: `StSq4b0.5+kpYYYY` → `Step Sequence 4`, never
`Step Sequence 4 + `.

Two adjacent tokens are **halves of one element** when they carry the same code and the two partner
letters — `SqTwW4` + `SqTwM4`, `MiStW1` + `MiStMB`, `pSTwW4` + `pSTwM4`, in either order. They are
rendered as a single part:

```
<name>s <W|M> <level> / <W|M> <level>        e.g. Sequential Twizzles W 4 / M 4
```

- The name is plural; each level stays with its partner letter; a missing level is left off rather
  than filled in (`Sequential Twizzles W 2 / M`).
- The rule covers the twizzle sets and the step sequences / one-foot turns. A lift combination has
  two different codes and is never recombined: `StaLi4+RoLi4` → `Stationary Lift 4 + Rotational
  Lift 4`.
- A half that appears alone keeps the singular form (`SqTwW4` → `Sequential Twizzle W 4`).

Without the recombination a two-partner element reads as two elements — which is what a bare ` + `
join produces, since every dance combination is published as one row. Recombining is also what keeps
the dance vocabulary under the singles worst case of 50 characters (§5).

### 4.9 Unknown tokens

A token that matches nothing (a call the site invents, a future code) is kept **verbatim**, so the
expansion degrades to today's behaviour rather than failing the import. This is also why an
unrecognized prefix (`pChSq1`) is a documented table entry rather than a guess — and why the
pairs/dance rules must never *mis*-expand: §3.2's 182/182 and 247/247 are the guard, and trap 4 is
what protects a throw from being read as a jump.

### 4.10 Pairs: throws, twist lifts, lifts, death spirals, pivot figures

`<element> <level>`, level last and space-separated, `B` or `1`–`4`. Throws are the one family whose
name the published code puts last and the display puts **first**.

| Family | Code | Name | Fixtures |
|---|---|---|---|
| Throw jump | `<n><jump>Th` | `Throw <n> <jump>` | `1LoTh`, `2STh`, `2LoTh`, `2FTh`, `2LzTh`, `3STh` |
| Twist lift | `<n>Tw<level>` | `<n> Twist Lift <level>` | `1Tw1`, `1Tw2`, `1TwB`, `2Tw1`–`2Tw4`, `3Tw3` |
| Pair lift | `1Li`–`4Li` | `<n> Lift <level>` | `1Li3`, `1Li4`, `1LiB`, `2Li2`–`2Li4`, `2LiB`, `3Li1`–`3Li4`, `3LiB`, `4Li2`–`4Li4`, `4LiB` |
| Pair lift | `5TLi` `5SLi` `5BLi` `5ALi` `5RLi` | `5 Toe Lasso Lift`, `5 Step-in Lasso Lift`, `5 Backward Lasso Lift`, `5 Axel Lasso Lift`, `5 Reverse Lasso Lift` (+ level) | `5ALi4` |
| Death spiral | `FiDs` `FoDs` `BiDs` `BoDs` | `Forward Inside Death Spiral`, `Forward Outside …`, `Backward Inside …`, `Backward Outside …` (+ level) | `FiDs1`, `FiDs2`, `FiDs3`, `FiDsB`, `BoDs2`, `BoDs3` |
| Pivot figure | `PiF<level>` | `Pivot Figure <level>` | `PiF1` |

- `3Tw3` → `3 Twist Lift 3`; `3Tw3b1` → `3 Twist Lift 3` (the bonus is stripped); `1Li4` → `1 Lift 4`;
  `4LiB` → `4 Lift B`; `BoDs3` → `Backward Outside Death Spiral 3`.
- **The five group-5 lifts have no `Group` word to drop**: their letter is the variety and is part of
  the name (`5ALi4` → `5 Axel Lasso Lift 4`).
- A pair spin is a spin (§4.3), the choreographic pair codes are §4.4, and pairs solo jumps and solo
  spins are §4.2 and §4.3.

### 4.11 Ice dance: lifts, twizzle sets, step sequences, one-foot turns

The Name column is **one half's** name; two halves of the same element recombine into the plural form
(§4.8).

| Family | Code | Name | Fixtures |
|---|---|---|---|
| Dance lift | `StaLi` | `Stationary Lift <level>` | `StaLi2`, `StaLi4` |
| Dance lift | `SlLi` (`SiLi`) | `Straight Line Lift <level>` | `SlLi1`–`SlLi4` |
| Dance lift | `CuLi` | `Curve Lift <level>` | `CuLi1`, `CuLi3`, `CuLi4` |
| Dance lift | `RoLi` | `Rotational Lift <level>` | `RoLi2`, `RoLi3`, `RoLi4` |
| Twizzle set | `SqTw<W\|M><level>` | `Sequential Twizzle <W\|M> <level>` | `SqTwW2+SqTwM`, `SqTwW4+SqTwM4`, … |
| Twizzle set | `SyTw<W\|M><level>` | `Synchronized Twizzle <W\|M> <level>` | `SyTwW4+SyTwM3`, … |
| Twizzle set | `pSTw<W\|M><level>` | `Synchronized Twizzle <W\|M> <level>` | `pSTwW4+pSTwM4`, … |
| Solo twizzles | `SoTw<level>` | `Solo Twizzles <level>` | — solo dance, no page in this set (§7.2) |
| Step sequence | `MiSt` `DiSt` `CiSt` `SeSt` | `Midline Step`, `Diagonal Step`, `Circular Step`, `Serpentine Step` `<W\|M> <level>` | `MiStW1+MiStM1`, `CiStW2+CiStM2`, `DiStW1+DiStM1`, `SeStW1+SeStM1` |
| One-foot turn | `OFT<W\|M><level>` | `One Foot Turn <W\|M> <level>` | `OFTW2+OFTM1` |
| Pattern dance type step sequence | `PSt<level>` | `Pattern Dance Type Step Sequence Style D <level>` | — senior rhythm dance, no page in this set (§7.2) |
| Edge element (solo dance) | `SpEe` `CrEe` `SeEs` `IBEe` | `Spiral Edge Element`, `Crouch Edge Element`, `Spread Eagle Edge Element`, `Ina Bauer Type Edge Element` (+ level) | — solo dance, no page in this set (§7.2) |

Behaviour:

- **`W` / `M` is a suffix of the code, shown after the name and before the level**, and each level
  stays with its letter: `SqTwW4` → `Sequential Twizzle W 4`, `MiStMB` → `Midline Step M B`.
- **A half with no level renders as the name alone** (`SqTwM` → `Sequential Twizzle M`), exactly as
  an unlevelled spin does today (§4.3). Two fixture rows carry a partner half with no level; they
  keep the letter and drop only the number (`SqTwW2+SqTwM` → `Sequential Twizzles W 2 / M`).
- **`p` is dropped from the name**, as §4.4 already does for `pChSq1`: `pSTwW4+pSTwM4` →
  `Synchronized Twizzles W 4 / M 4`, `pChSt1` → `Choreo Step Sequence 1`.
- **A lift combination is not recombined** (§4.8): `StaLi4+RoLi4` → `Stationary Lift 4 + Rotational
  Lift 4`.
- **The three edge-element codes end in `e`**, which is also a marker (trap 7): `SpEe`, `CrEe` and
  `IBEe` therefore classify on the token *before* the shared marker strip, and on the stripped token
  when the `e` really is a marker.
- The dance spin is a spin (§4.3); the creative dance element and the dance choreographic codes are
  §4.4; the pattern-dance element codes are §4.12.

### 4.12 Pattern-dance elements

Three published shapes, all carrying key points:

| Grammar | Shape | Fixtures | Expansion |
|---|---|---|---|
| standalone pattern dance | `<dance><sequence>Sq<level>` | `FO1Sq4+kpYYYY`, `TA2Sq2+kpYNYN` | `Fourteenstep Seq 1 4`, `Tango Seq 2 2` |
| RD pattern element | `<slot><dance><level>` | `1GW2+kpYNNY`, `1WW1+kpNNNY`, `2WWB+kpNNNN` | `Golden Waltz 1 2`, `Pattern Dance 1 1`, `Pattern Dance 2 B` |
| generic pattern dance | `RPD<sequences><sequence>Sq<level>` | `RPD41Sq4+kpYYYY`, `RPD22Sq1+kpNYNN` | `Pattern Dance Seq 1 4`, `Pattern Dance Seq 2 1` |

- The `kp…` token is dropped as today, so `FO1Sq4+kpYYYY` ends at `Fourteenstep Seq 1 4` with no
  dangling separator.
- **`RPD` carries no dance identity.** It is the site's code for a required pattern dance whose
  dance has no ISU abbreviation, and its digit is the number of **sequences** in that dance, not a
  dance number (`IJS Parameters`, partner ice dance PD rows: every two-sequence dance is
  "[use RPD2]", three-sequence "[use RPD3]", four-sequence "[use RPD4]"). The leading digit is
  therefore dropped from the name rather than shown.
- **`1WW` / `2WW` are slot codes, and are not named.** `WW` is the Westminster Waltz code, but the
  ISU 2026-27 list labels `1WW` "PD Element Rhumba 1st Sequence (Juniors)" and `2WW` "PD Element
  Quickstep 1st Sequence (Juniors)" — the labels left over from 2025-26's `1RH`/`1QS` — so which
  dance sits behind the code is a season fact this component cannot see. `1GW` is named because that
  code's label and its dance code agree.
- **The first number does not mean the same thing in the two grammars**, which is why the two are
  rendered differently. In `<dance><sequence>Sq<level>` it is the dance's own sequence and is shown
  as `Seq <n>`. In `<slot><dance><level>` it is the element's slot in the segment (1st or 2nd
  pattern element), and the level is the final digit — `1WWB`, `1WW1` and `1WW2` are the same element
  at three levels (base values 2.50 / 3.50 / 4.00 in the junior rhythm dance), so a rule that read
  the leading digit as a sequence would invent a sequence that is not published.

## 5. Worked examples

Every row is a real fixture string and the expander's actual output; each is pinned by a test (§9).

| Abbreviation       | Expansion                                            |
| ------------------ | ---------------------------------------------------- |
| `3S`               | `3 Salchow`                                          |
| `3Tb1+2T`          | `3 Toeloop + 2 Toeloop`                              |
| `2F+Eu+3S<`        | `2 Flip + Euler + 3 Salchow`                         |
| `3Lz<b1`           | `3 Lutz`                                             |
| `3Lz!+2T`          | `3 Lutz + 2 Toeloop`                                 |
| `2Lo+2Tq`          | `2 Loop + 2 Toeloop`                                 |
| `1Lz*+COMBO`       | `1 Lutz (Invalid) + COMBO`                           |
| `T+COMBO+2T*+REP`  | `Toeloop + COMBO + 2 Toeloop (Invalid) + REP`        |
| `2Lz+COMBO`        | `2 Lutz + COMBO`                                     |
| `3Lo+REP`          | `3 Loop + REP`                                       |
| `2Lz+SEQ+1A*+2Lo*` | `2 Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)` |
| `3S+1A+2T+SEQ`     | `3 Salchow + 1 Axel + 2 Toeloop + SEQ`               |
| `4T`               | `4 Toeloop`                                          |
| `3A`               | `3 Axel`                                             |
| `StSqB+kpNNNN`     | `Step Sequence B`                                    |
| `StSq4b0.5+kpYYYY` | `Step Sequence 4`                                    |
| `ChSq1`            | `Choreo Sequence 1`                                  |
| `ChSp1`            | `Choreo Spin 1`                                      |
| `pChSq1`           | `Choreo Sequence 1`                                  |
| `CoSp`             | `Combo Spin`                                         |
| `CCoSpBV`          | `Change Combo Spin B V`                              |
| `CCoSp1V`          | `Change Combo Spin 1 V`                              |
| `FCCoSp4`          | `Flying Change Combo Spin 4`                         |
| `CSp2`             | `Camel Spin 2`                                       |

### 5.1 Pairs

| Abbreviation | Expansion |
|---|---|
| `3Tw3` | `3 Twist Lift 3` |
| `3Tw3b1` | `3 Twist Lift 3` |
| `3STh` | `Throw 3 Salchow` |
| `2LoTh` | `Throw 2 Loop` |
| `1Li4` | `1 Lift 4` |
| `4LiB` | `4 Lift B` |
| `5ALi4` | `5 Axel Lasso Lift 4` |
| `BoDs3` | `Backward Outside Death Spiral 3` |
| `FiDsB` | `Forward Inside Death Spiral B` |
| `PiF1` | `Pivot Figure 1` |
| `PSpB` | `Pair Spin B` |
| `ChPSp1` | `Choreo Pair Spin 1` |
| `ChPLi1` | `Choreo Pair Lift 1` |
| `3Tb1+2A+SEQ` | `3 Toeloop + 2 Axel + SEQ` |

### 5.2 Ice dance

| Abbreviation | Expansion |
|---|---|
| `DSp2` | `Dance Spin 2` |
| `StaLi4+RoLi4` | `Stationary Lift 4 + Rotational Lift 4` |
| `SlLi3+RoLi3` | `Straight Line Lift 3 + Rotational Lift 3` |
| `CuLi4` | `Curve Lift 4` |
| `SqTwW4+SqTwM4` | `Sequential Twizzles W 4 / M 4` |
| `SqTwW2+SqTwM` | `Sequential Twizzles W 2 / M` |
| `SyTwW3+SyTwM4` | `Synchronized Twizzles W 3 / M 4` |
| `pSTwW4+pSTwM1` | `Synchronized Twizzles W 4 / M 1` |
| `MiStW1+MiStM2` | `Midline Steps W 1 / M 2` |
| `MiStW1+MiStMB` | `Midline Steps W 1 / M B` |
| `CiStW2+CiStM2` | `Circular Steps W 2 / M 2` |
| `OFTW2+OFTM3` | `One Foot Turns W 2 / M 3` |
| `ChAJ1` | `Choreo Assisted Jumps 1` |
| `ChSt1` | `Choreo Char Step Sequence 1` |
| `pChSt1` | `Choreo Step Sequence 1` |
| `ChSl1` | `Choreo Slide 1` |
| `CDE4` | `Creative Dance Element 4` |
| `FO1Sq4+kpYYYY` | `Fourteenstep Seq 1 4` |
| `TA2Sq1+kpNYNN` | `Tango Seq 2 1` |
| `1GW2+kpYNNY` | `Golden Waltz 1 2` |
| `1WW1+kpNNNY` | `Pattern Dance 1 1` |
| `2WWB+kpNNNN` | `Pattern Dance 2 B` |
| `RPD41Sq4+kpYYYY` | `Pattern Dance Seq 1 4` |

Length: singles mean 5.7 → 14.5 characters, max 18 → 50. Pairs mean 4.9 → 14.4, max 11 → 31
(`Backward Outside Death Spiral 3`). Ice dance mean 10.1 → 20.7, max 15 → 40 (`Straight Line Lift 3
+ Rotational Lift 3`). Recombining the partner halves is what keeps the dance vocabulary under the
singles worst case.

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

Both types are in the module (`ElementNameExpander.swift`). The identity default lives in a protocol
extension, so a conformer that implements nothing is valid — the identity test in §9 pins that.

**The pairs and ice-dance rules change neither the protocol nor the type** — they are tables and
branches — so `ElementData.init(_:translator:)` and `OverlayData.merge(_:translator:)` pick them up
unchanged. The tables live in two source files beside it — `ElementNameExpander+Pairs.swift` and
`ElementNameExpander+Dance.swift` (§8 Q8).

**No failure mode.** An unclassifiable token is not an error — it is returned verbatim (§4.9), so
this component cannot fail an import and needs no error type.

## 7. Integration with the app

Chain: `ProtocolElement.abbreviation` → `ElementNameExpander` → `ElementData.name`, and it is
**wired in** — the mapping point is `ElementData.init(_ element:translator:)` in
`TechnicalOverlay/ProtocolImport.swift`, which `OverlayData.merge(_:translator:)` calls on both of its
paths: a refresh at an index must land the same text as an append, or re-importing would silently
revert elements the user has already timed back to raw codes. Both take the translator as a parameter
defaulted to `ElementNameExpander()`, so the app gets the expansion and a caller (or a test) can hand
in the identity default — the seam §6 specifies.

### 7.1 What the app sees

- **The raw abbreviation is not retained.** `ElementData` has only `name` (`OverlayData.swift:276`);
  after import the code is gone, so a rule change here means re-importing to see it. Keeping the code
  on the model is **out of scope** — it would touch the persisted model and its
  `version` (`docs/ARCHITECTURE.md` §4), so it is not a silent addition.
- **Names get much longer.** Singles mean 5.7 → 14.5 characters, worst 50; pairs up to 31; ice dance
  up to 40. The overlay's element-name row is laid out from `Metrics`: at a 1280×720 overlay the pane
  is 16% of the height with a 2.65 aspect (≈ 305 × 115 px), the name row is the full pane width and
  ≈ 28 px tall, and the label font is 0.75 × row height (≈ 21 pt) with `adjustsFontSizeToFitWidth` +
  `numberOfLines = 1` (`ElementNameView.swift:25-26`). So a long expansion **shrinks rather than
  truncates** — it stays complete, it gets smaller. Those figures are computed from `Metrics`, not
  measured on screen — worth checking on screen before making the overlay's form terser than the
  list's.
- **The scoring list is the other consumer** — the same `name` string is edited by hand in
  `ScoringListView`, so an expansion of 50 characters is also a 50-character text field value.
- **`renderingHash` covers `name`**, so expanding a name invalidates the cached slides/chunks for
  that element as any other data change does (`docs/ARCHITECTURE.md` §3.4).
- **` + ` keeps one meaning.** A two-partner element is recombined into a single name (§4.8), so the
  separator only ever separates elements: a jump combination, or the halves of a lift combination.
- **Manifest:** none — the component lives in a target the app already links (no new target, no new
  package); the pairs and ice-dance tables are two source files in that target.

### 7.2 Adjacent gaps this specification does not close

- **Team names.** A dance page's name cell is `Lara Luft / Ilias Fourati` with no club, so
  `ProtocolSkater.namePart` returns the whole string and `club` is `nil` — the same shape as a pairs
  entry (`ProtocolModel.swift`). Selecting a team by name therefore works the way pairs already does.
- **Pages with no element table.** Nine of the Challenge Cup dance pages — the solo pattern dances
  and the solo free dances — have program components only, so the parser's `elementTableMissing` path
  applies. That is an importer question, not an expansion one.
- **Markers not measured.** None of the thirteen dance pages carries `S`, `>` or `ExEI`, or a reduced
  level on a pattern-dance code (§4.6 lists them from the ISU list). They cannot be pinned by a
  fixture sweep until a page that uses them is captured; until then each is one synthetic test.
- **Solo-dance and senior codes** (`SoTw`, `PSt`, `SpEe`, `CrEe`, `SeEs`, `IBEe`) have no page in this
  set, so their code shapes and names are the ISU list's, not a measurement (§4.11).

## 8. Decisions taken

The singles rules are settled and shipped. The pairs and ice-dance rules were decided before
implementation: each row is now a rule in §4, not an option.

| # | Decision | Outcome |
|---|---|---|
| Q1 | Pairs twist lift, which has two bare numbers | `3 Twist Lift 3` — the code's own word between the numbers |
| Q2 | Where `W` / `M` sits in a dance name | **Folded into Q5**; a lone half reads `<name> <W\|M> <level>` |
| Q3 | Whether a pattern-dance code shows the dance name | Yes when the code names a dance (`Fourteenstep Seq 1 4`, `Golden Waltz 1 2`); `Pattern Dance <n> <level>` and `Pattern Dance Seq <n> <level>` for `RPD` and the `1WW`/`2WW` slot codes |
| Q4 | `pSTw` against `SyTw` | Identical names — `p` dropped, as `pChSq1`'s already is |
| Q5 | A two-partner element must not read as two elements | Recombined into one name: `Sequential Twizzles W 4 / M 4` (§4.8). Supersedes Q2 |
| Q6 | `ChSt` against `pChSt` | `Choreo Char Step Sequence 1` / `Choreo Step Sequence 1` |
| Q7 | ISU codes with no page in this set | Named now from the ISU list (§4.11), each pinned by a synthetic test |
| Q8 | Where the tables live | Split into `ElementNameExpander+Pairs.swift` and `ElementNameExpander+Dance.swift` `[generate]` |

## 9. Testing

Pure string tests — no fixtures needed for a table; the sweeps use the committed pages.

| # | Test | Expectation |
|---|---|---|
| 1 | Jumps and numbers | `3S` → `3 Salchow`, `2Lz` → `2 Lutz`, `1A` → `1 Axel`, `4T` → `4 Toeloop` |
| 2 | Euler | `Eu` → `Euler`; `2A+Eu+2F` → `2 Axel + Euler + 2 Flip`; never `1 Euler` |
| 3 | Separator | every `+` becomes ` + `; no dangling separator when `kp…` is dropped |
| 4 | Bonus ignored, both positions | `3Tb1+2T` → `3 Toeloop + 2 Toeloop`; `3Lz<b1` → `3 Lutz` |
| 5 | Markers ignored | `2A<`, `3Lo<<`, `2Lz!`, `2Lze`, `3Lzq`, `1Lze` all strip to the plain name |
| 6 | Invalid flag | `1Lz*+COMBO` → `1 Lutz (Invalid) + COMBO`; two `*` in one row both flagged |
| 7 | Call tokens | `SEQ`, `COMBO` and `REP` all kept in place exactly as published (`2Lz+COMBO` → `2 Lutz + COMBO`, `T+COMBO+2T*+REP` → `Toeloop + COMBO + 2 Toeloop (Invalid) + REP`) |
| 8 | Step sequences | `StSqB+kpNNNN` → `Step Sequence B`; `StSq4b0.5+kpYYYY` → `Step Sequence 4` |
| 9 | Choreographic (singles) | `ChSq1` → `Choreo Sequence 1`; `ChSp1` → `Choreo Spin 1`; `pChSq1` → `Choreo Sequence 1` (prefix dropped, digit kept) |
| 10 | Spins | `CCoSp4` → `Change Combo Spin 4`; `CCoSp1V` → `Change Combo Spin 1 V` (a space before the `V`); `CCoSpBV` → `Change Combo Spin B V`; `FCCoSp4`, `CSp2`, `SSpB` |
| 11 | Longest-match spin codes | `CCSp3` is not `CSp`…; `FSSp3` is not `SSp`…; `SSp2` is not a Salchow |
| 12 | Trap regressions (§2.4) | `StSq2`/`ChSq1` survive the `q` marker rule; `3Lz<b1` strips; `3STh` is a throw, not a Salchow |
| 13 | **Sweep over the five singles fixtures** | 535/535 rows expand with zero verbatim-passthrough tokens once `kp…` is dropped (§3.1); any row that regresses to passthrough fails the test |
| 14 | Identity default | a type conforming without implementing anything returns the abbreviation unchanged (`protocol-parser.md` §9) |
| 15 | Pairs throws and twists | `3STh` → `Throw 3 Salchow`, `2LoTh` → `Throw 2 Loop`, `1TwB` → `1 Twist Lift B`, `3Tw3b1` → `3 Twist Lift 3` |
| 16 | Pairs lifts, spirals, pivot, spins | `1Li4` → `1 Lift 4`, `4LiB` → `4 Lift B`, `5ALi4` → `5 Axel Lasso Lift 4`, `BoDs3`, `FiDsB`, `PiF1`, `PSpB`, `PCoSp3` |
| 17 | Dance lifts and spin | `StaLi4+RoLi4` → `Stationary Lift 4 + Rotational Lift 4` (not recombined), `SlLi3+RoLi3`, `CuLi4`, `RoLi2`, `DSpB`; `SiLi4` aliases `SlLi4` |
| 18 | Twizzle and step halves recombine | `SqTwW4+SqTwM4` → `Sequential Twizzles W 4 / M 4`; `SyTwW3+SyTwM4`; `pSTwW4+pSTwM1`; `MiStW1+MiStM2` → `Midline Steps W 1 / M 2`; `MiStW1+MiStMB`; `OFTW2+OFTM3`; a lone `SqTwW4` keeps the singular form; `SqTwM` (no level) → name alone |
| 19 | Recombination is narrow | halves with *different* codes are not recombined (`SlLi3+RoLi3`); a lone half is not pluralised; the letters must be one `W` and one `M` (`SqTwW4+SqTwW4` is not a pair) |
| 20 | Choreographic (dance and pairs) | `ChSt1` → `Choreo Char Step Sequence 1`, `pChSt1` → `Choreo Step Sequence 1`, `ChSl1`, `ChLi1`, `ChAJ1`, `ChPSp1`, `ChPLi1`, `CDE4` → `Creative Dance Element 4` — all distinct, none colliding with `ChSq1` |
| 21 | Both pattern-dance grammars | `FO1Sq4+kpYYYY` → `Fourteenstep Seq 1 4`; `TA2Sq1+kpNYNN`; `1GW2+kpYNNY` → `Golden Waltz 1 2` |
| 22 | Pattern codes that must not be named | `1WW1+kpNNNY`, `2WWB+kpNNNN` → `Pattern Dance …`; `RPD41Sq4`, `RPD22Sq1` → `Pattern Dance Seq …` |
| 23 | Dance-only markers | `SqTwW4S` (separation), `StaLi4>` (extended), `ExEI` kept as its own part, `*` → `(Invalid)` |
| 24 | Marker collisions | `S` alone is still Salchow; `StSq2`/`ChSq1` still classify; `e` strips on a jump and on a choreographic code |
| 25 | ISU codes with no fixture row | `PSt4` → `Pattern Dance Type Step Sequence Style D 4`, `SoTw3`, `SpEe2`, `CrEe1`, `SeEs2`, `IBEe1` — one synthetic test each |
| 26 | Sweep, pairs | 182/182 rows, 66/66 abbreviations, zero verbatim passthrough (§3.2) |
| 27 | Sweep, ice dance | 247/247 rows, 121/121 abbreviations, zero verbatim passthrough (§3.2) |
| 28 | Well-formedness sweep | no empty part, no doubled separator, no `kp…` in the output, over all 429 pairs and dance rows |
| 29 | Singles regression | the 535/535 singles sweep and every singles test above stay green — the spin and choreographic tables are shared, so this is what catches a table addition that reclassifies a singles token |

**Implemented as `ElementNameExpanderTests.swift`** — one `@Suite("Element name expansion")`, the rows
above as 31 tests, all passing: **ProtocolParser is 70/70 in 7 suites**. Three of them are sweeps
(tests 13, 26 and 27): 535/535 singles rows, 182/182 pairs rows and 247/247 dance rows, each with
zero verbatim passthrough and the exact distinct-abbreviation count §3 froze; test 12's neighbour
checks all 825 static plus 247 dance rows for a well-formed name.

## 10. Verification and known gaps

- **Singles are implemented and measured over every row, not over hand-picked examples:** 535/535
  rows classify completely with `kp…` dropped, 0 unclassified tokens, and §3.1's inventory is the
  census that fell out of it. The tests sweep the same set, plus all **825** rows of the eleven
  detail pages for a well-formed name (no empty part, no dangling separator, no `kp…` leaking
  through). Each spin code in §4.3 was checked against the ISU singles abbreviation list: the ✅
  column is what occurs in these pages, the "—" rows are codes from that list that do not.
- **Pairs and ice dance are implemented and measured the same way.** The sweeps classify all **429**
  rows of the five pairs and thirteen dance pages — 182/182 and 247/247, 0 unclassified tokens, with
  the distinct-abbreviation counts §3.2 froze — and every row of §5.1–§5.2 is a test. The rules were
  built as a prototype first and run over the same rows before any Swift was written; the same
  prototype classified 535/535 singles rows and reproduced all 24 singles examples, which is why the
  new branches are provably additive rather than a rewrite. For the record, the pre-pairs expander
  was also run over those 429 rows: it changed 58 pairs and 153 dance rows, and every one of those
  changes was shared vocabulary (solo jumps, `+SEQ`, `ChSq1`, `ChSp1`) or the separator around a
  dropped `kp…` token — so nothing was mangled before this change either.
- **Not verified:** the `q` and `V` semantics (taken from ISU communications, not measured — they only
  decide what gets ignored, never a value); the dance-only markers `S`, `>` and `ExEI`, which no
  fixture page uses (§7.2); `PSt`, `SoTw` and the four solo-dance edge elements (§8 Q7); and the
  **on-screen fit** of the longest expansions — §7.1's figures are computed from `Metrics`, not
  measured on a rendered overlay, so check on screen before making the overlay's form terser than the
  scoring list's.
- **Sources.** The names come from the ISU judging-system abbreviation list for 2026-27; the published
  pages decide the spellings the list gets wrong (`SlLi` against its `SiLi`, `ChSl` against its
  `ChSI`), and those spellings are kept as aliases.
- Rules that changed while this was being written, with the measurements each revision produced, are in
  `docs/HISTORY.md` → *Element abbreviation expansion*. §4 is normative; nothing else in this document
  is.

## 11. Dependencies

- **None** beyond the Swift standard library. The expander is string tables and a classifier; no new
  package, no new module, no dependency change (`docs/ARCHITECTURE.md` §2.2 policy not exercised). The
  pairs and ice-dance tables add two source files to a target the app already links, which needs
  `tuist generate` and nothing else.
