# Element Abbreviation Expansion (Pairs and Ice Dance)

**Source:** proposed additions to `LayoutEngine/ProtocolParser/ProtocolParser/ElementNameExpander.swift`;
tests in `LayoutEngine/ProtocolParser/ProtocolParserTests/ElementNameExpanderTests.swift`

Status: **specification only — nothing in this document is implemented.** It extends the singles
rules in [`abbreviation-expansion.md`](abbreviation-expansion.md) and replaces that document's §8
deferral. The component, its protocol and its integration point are unchanged (§6), so the work is
tables and branches, not plumbing. §8 records the decisions taken on this specification.

## 1. Purpose

Turn a published pairs or ice-dance abbreviation (`3Tw3`, `3STh`, `5ALi4`, `BoDs2`, `ChPSp1`,
`SqTwW4+SqTwM4`, `MiStW1+MiStM2`, `StaLi4+RoLi4`, `1GW2+kpYNNY`) into the name shown on the overlay
and in the scoring list (`3 Twist Lift 3`, `Throw 3 Salchow`, `5 Axel Lasso Lift 4`,
`Backward Outside Death Spiral 2`, `Choreo Pair Spin 1`, `Sequential Twizzles W 4 / M 4`,
`Midline Steps W 1 / M 2`, `Stationary Lift 4 + Rotational Lift 4`,
`Golden Waltz 1 2`).

**In scope:** the element codes of the pairs and ice-dance protocols — throws, twist lifts, pair
lifts, death spirals, pivot figures, pair spins, dance spins, dance lifts, twizzle sets, dance step
sequences and one-foot turns, the choreographic family, the creative dance element, and the
pattern-dance element codes.

**Out of scope:** the singles rules (they stay as specified — §4.1 only adds branches after them),
values, the `info` column, and any language other than English.

## 2. Input

### 2.1 The string being expanded

Unchanged from `abbreviation-expansion.md` §2.1: `ProtocolElement.abbreviation`, the element cell
exactly as published and entity-decoded. Pairs and dance pages use the same table layout as singles
(`class=elem` / `class=info` / `class=bv` / `class=goe`, `protocol-parser.md` §2.2), so the input
needs no parser change.

### 2.2 What is different from singles

| | Singles | Pairs / dance |
|---|---|---|
| Element combos | jump combinations: several **elements** | every `+`-joined pair is **one element** with two halves — two lifts (`StaLi4+RoLi4`), two partners (`SqTwW4+SqTwM4`, `MiStW1+MiStM2`) |
| Numbers | one (revolutions) | two on some codes — group/revolutions then level (`4Li3`, `3Tw3`, `PSp4`) |
| Level | spins and step sequences only | almost everything, and a dance half may have **no** level (`SqTwM`) |
| Partner | — | `W` / `M` suffix marks whose level it is |
| Key points | `+kp…` | the same token, on pattern-dance elements |
| Markers | `<` `<<` `!` `e` `q` `b…` `*` | those plus `S`, `>`, `ExEI`, and `<`/`<<` meaning "reduce the level" |

### 2.3 Tokenization

**Split on `+` first**, exactly as today (`abbreviation-expansion.md` §2.3), then **recombine the
two halves of a two-partner element before rendering** (§4.6). The split stays the unit of
classification: a lift combination's halves are separate elements and classify separately, and a
twizzle set's or step sequence's halves are one element and are rejoined.

## 3. Reference pages and the measured inventory

**Pairs:** the five pairs pages already committed —
`SEGM026.html`, `SEGM028.html`, `SEGM030.html`, `SEGM031.html`, `SEGM032.html`
(`protocol-parser.md` §3).

**Ice dance:** thirteen pages from the Challenge Cup 2026 protocol set
(`https://ijs.usfigureskating.org/leaderboard/results/2026/37064/`, detail pages `SEGM001`–`SEGM009`
and `SEGM018`–`SEGM021`), to be committed beside the existing pages as
`ProtocolParserTests/Fixtures/ChallengeCup-SEGMnnn.html`. They cover
juvenile, novice, intermediate, junior and senior partnered dance: six pattern-dance pages and seven
rhythm/free-dance pages. Nine further pages in that event (the solo pattern dances and the adult
and senior solo free dance) carry **no element table at all**; they are not part of this set (§7.2).

| Measure | Pairs | Ice dance |
|---|---:|---:|
| Element rows | **182** | **247** |
| Distinct abbreviations | **66** | **121** |
| Distinct `+`-separated tokens | **63** | **125** (110 once `kp…` is set aside) |
| Distinct tokens per family | throws 6, twist lifts 8, pair lifts 17, death spirals 6, pivot 1, pair spins 5, choreo-pair 2, solo jumps 11, `SEQ` 1 | twizzle sets 12, dance steps 21, dance lifts 13, dance spin 5, choreo 5, creative 1, pattern dance 39 (RPD 30, named 9), `kp…` 15 |
| Rows carrying a pairs/dance-specific token | **127 / 182** | **219 / 247** |
| Rows whose every token the rules below classify | **182 / 182** | **247 / 247** |
| Abbreviation length → expansion length | mean 4.9 → 14.4; max 11 → 31 | mean 10.1 → 20.7; max 15 → 40 |

The last two rows are the numbers a regression test freezes: a pairs or dance row that falls back to
verbatim is otherwise silent, because the output still looks like a name.

## 4. Expansion model

### 4.1 Pipeline

```
abbreviation
  └─ split on "+"                             → [token]                (unchanged)
       └─ per token: strip "*" (remember it), strip b<digits>[.<digits>] anywhere,
          strip trailing singles marker run                              (unchanged)
            ├─ token is "SEQ" | "COMBO" | "REP" | "ExEI"  → keep the token verbatim
            ├─ token starts with kp                      → drop the token entirely
            ├─ StSq<level>                               → singles step-sequence rule (unchanged)
            ├─ a choreographic code (ChSq, ChSp, ChSt, ChSl, ChLi, ChAJ,
               pChSt, ChPSp, ChPLi)                      → §4.2 (pairs) / §4.3 (dance)
            ├─ CDE<level>                                → §4.3
            ├─ a spin code, incl. PSp / PCoSp / DSp      → §4.2 (spins; longest code first)
            ├─ a pairs code                              → §4.2 (throws, twists, lifts, …)
            ├─ a dance code                              → §4.3 (twizzles, steps, lifts, …)
            ├─ a pattern-dance code                      → §4.4
            ├─ <number?> <jump code> + markers-only tail → singles jump rule (unchanged)
            └─ nothing matched                           → keep the raw token verbatim (§4.7)
  └─ recombine two-partner halves (§4.6), then join the parts with " + "    (unchanged)
```

Two ordering requirements, both correctness rather than style:

- **New branches run before the jump rule.** The jump rule accepts a single letter code with an
  optional leading number, so it is the last resort by construction; everything else narrows first,
  as it already does for spins (`abbreviation-expansion.md` §4.1).
- **Every table is matched longest-code-first, whole token.** Reason unchanged from singles trap 3:
  `PSp` ⊂ `PCoSp`, and the `ChS…` codes (`ChSq`, `ChSp`, `ChSl`, `ChSt`) share three letters — the
  singles spin table already had to be sorted for exactly this reason.

### 4.2 Pairs

`<element> <level>`, level last and space-separated, `B` or `1`–`4` — the shape the singles spin
rule already uses. Throws are the one family whose name the published code puts last and the display
puts **first**: `<n><jump>Th` → `Throw <n> <jump>`.

| Family | Code | Name | Fixtures |
|---|---|---|---|
| Throw jump | `<n><jump>Th` | `Throw <n> <jump>` | `1LoTh`, `2STh`, `2LoTh`, `2FTh`, `2LzTh`, `3STh` |
| Twist lift | `<n>Tw<level>` | `<n> Twist Lift <level>` | `1Tw1`, `1Tw2`, `1TwB`, `2Tw1`–`2Tw4`, `3Tw3` |
| Pair lift | `1Li`–`4Li` | `<n> Lift <level>` | `1Li3`, `1Li4`, `1LiB`, `2Li2`–`2Li4`, `2LiB`, `3Li1`–`3Li4`, `3LiB`, `4Li2`–`4Li4`, `4LiB` |
| Pair lift | `5TLi` `5SLi` `5BLi` `5ALi` `5RLi` | `5 Toe Lasso Lift`, `5 Step-in Lasso Lift`, `5 Backward Lasso Lift`, `5 Axel Lasso Lift`, `5 Reverse Lasso Lift` (+ level) | `5ALi4` |
| Death spiral | `FiDs` `FoDs` `BiDs` `BoDs` | `Forward Inside Death Spiral`, `Forward Outside …`, `Backward Inside …`, `Backward Outside …` (+ level) | `FiDs1`, `FiDs2`, `FiDs3`, `FiDsB`, `BoDs2`, `BoDs3` |
| Pivot figure | `PiF<level>` | `Pivot Figure <level>` | `PiF1` |
| Pair spin | `PSp<level>` | `Pair Spin <level>` | `PSp1`–`PSp4`, `PSpB` |
| Pair combo spin | `PCoSp<level>` | `Pair Combo Spin <level>` | — (ISU code, not in these pages) |
| Choreo pair spin | `ChPSp<n>` | `Choreo Pair Spin <n>` | `ChPSp1` |
| Choreo pair lift | `ChPLi<n>` | `Choreo Pair Lift <n>` | `ChPLi1` |
| Choreo sequence | `ChSq<n>` | `Choreo Sequence <n>` | `ChSq1` (singles rule already) |

The five group-5 lifts have no `Group` word to drop: their letter is the variety and is part of the
name (`5ALi4` → `5 Axel Lasso Lift 4`).

Pairs solo jumps, solo spins, step sequences and their markers keep the singles rules unchanged
(`3Tb1+2A+SEQ` → `3 Toeloop + 2 Axel + SEQ`, `2F<` → `2 Flip`).

### 4.3 Ice dance

The Name column is **one half's** name; two halves of the same element recombine into the plural form
(§4.6).

| Family | Code | Name | Fixtures |
|---|---|---|---|
| Dance spin | `DSp<level>` | `Dance Spin <level>` | `DSp1`–`DSp4`, `DSpB` |
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
| Choreo — assisted jumps | `ChAJ<n>` | `Choreo Assisted Jumps <n>` | `ChAJ1` |
| Choreo — character step sequence | `ChSt<n>` | `Choreo Char Step Sequence <n>` | `ChSt1` |
| Choreo — slide | `ChSl<n>` | `Choreo Slide <n>` | `ChSl1` |
| Choreo — lift | `ChLi<n>` | `Choreo Lift <n>` | `ChLi1` |
| Choreo — spinning movement | `ChSp<n>` | `Choreo Spin <n>` | `ChSp1` (singles rule already) |
| Choreo — step sequence (juvenile/adult FD) | `pChSt<n>` | `Choreo Step Sequence <n>` | `pChSt1` |
| Creative dance element | `CDE<level>` | `Creative Dance Element <level>` | `CDE4` |
| Edge element (solo dance) | `SpEe` `CrEe` `SeEs` `IBEe` | `Spiral Edge Element`, `Crouch Edge Element`, `Spread Eagle Edge Element`, `Ina Bauer Type Edge Element` (+ level) | — solo dance, no page in this set (§7.2) |

Behaviour:

- **A twizzle set or step sequence is one element with two halves, and renders as one name**
  (§4.6): `SqTwW4+SqTwM4` → `Sequential Twizzles W 4 / M 4`, `MiStW1+MiStM2` → `Midline Steps
  W 1 / M 2`. The name is plural and each level sits with its partner letter.
- **A half without its partner half keeps the singular form** — `<name> <W|M> <level>`, as in
  `SqTwW4` → `Sequential Twizzle W 4` — and **a half with no level renders as the name alone**
  (`SqTwM` → `Sequential Twizzle M`), exactly as an unlevelled spin does today
  (`abbreviation-expansion.md` §4.3). Two fixture rows carry a partner half with no level; they keep
  the letter and drop only the number (`SqTwW2+SqTwM` → `Sequential Twizzles W 2 / M`).
- **`p` is dropped from the name**, as the singles rule already does for `pChSq1`: `pSTwW4+pSTwM4` →
  `Synchronized Twizzles W 4 / M 4`, `pChSt1` → `Choreo Step Sequence 1`.
- **A lift combination is not recombined.** Its two halves are two different lifts, so each keeps its
  own name and they stay ` + `-joined: `StaLi4+RoLi4` → `Stationary Lift 4 + Rotational Lift 4`.
- **No `V` in pairs or dance.** `V` is a singles spin suffix; the level alphabet here is `B`,`1`–`4`.

### 4.4 Pattern-dance elements

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
  dance sits behind the code is a season fact this component cannot see. `1GW` is named because
  that code's label and its dance code agree.
- **The first number does not mean the same thing in the two grammars**, which is why the two are
  rendered differently. In `<dance><sequence>Sq<level>` it is the dance's own sequence and is shown
  as `Seq <n>`. In `<slot><dance><level>` it is the element's slot in the segment (1st or 2nd pattern
  element), and the level is the final digit — `1WWB`, `1WW1` and `1WW2` are the same element at three
  levels — base values 2.50 / 3.50 / 4.00 in the junior rhythm dance, so a rule that read the
  leading digit as a sequence would invent a sequence that is not published.

### 4.5 Markers

| Marker | Where | Meaning | Rule |
|---|---|---|---|
| `b1`, `b0.5` | anywhere, incl. `3Tw3b1`, `3SThb1` | bonus | stripped (already) |
| `<` `<<` | trailing on a jump or throw; on a pattern-dance code | under-rotated / downgraded; reduce PD level 1/2 | stripped (already, and inside §4.4) |
| `!` `e` `q` | trailing on a jump | edge / quarter-short | stripped (already) |
| `e` | trailing on a **choreographic** element | element did not fulfil its requirements | stripped (already; same strip) |
| `S` | trailing on `PSt`, `SyTw`, `SqTw`, `OFT` | reduce one level (separation / loss of contact) | stripped **inside the dance rules only** |
| `>` | trailing on a lift | extended lift | stripped inside the dance rules only |
| `*` | any token | not credited | `(Invalid)` appended to that token (already) |
| `ExEI` | its own `+`-separated token | extra element | kept verbatim, like `COMBO` |

**Markers stay per-branch. Do not hoist them into one character set.** `S` is the Salchow code and
the dance separation marker; `e` is the singles wrong-edge marker and the dance choreo-error marker;
`q` is a marker and a letter of `StSq`/`ChSq` (`abbreviation-expansion.md` §2.4 trap 1). A blanket
strip either destroys codes or stops elements classifying, silently. On landing, the reasoning goes
to `docs/HISTORY.md` → *Element abbreviation expansion (pairs and dance)*.

### 4.6 Recombining two-partner halves, then joining

Two adjacent tokens are **halves of one element** when they carry the same code and the two partner
letters — `SqTwW4` + `SqTwM4`, `MiStW1` + `MiStMB`, `pSTwW4` + `pSTwM4`, in either order. They are
rendered as a single part:

```
<name>s <W|M> <level> / <W|M> <level>        e.g. Sequential Twizzles W 4 / M 4
```

- The name is plural; each level stays with its partner letter; a missing level is left off rather
  than filled in (`Sequential Twizzles W 2 / M`).
- The rule covers the twizzle sets and the step sequences / one-foot turns. A lift combination has
  two different codes and is never recombined.
- Everything else is joined with ` + `, and dropped tokens (`kp…`) leave neither a separator nor an
  empty part, unchanged from `abbreviation-expansion.md` §4.8.

Without the recombination a two-partner element reads as two elements — which is what a bare
` + ` join produces, since every dance combination in the fixtures is published as one row.

### 4.7 Unknown tokens

Unchanged: a token that matches nothing is kept verbatim, so an unmodelled code degrades to today's
behaviour rather than failing an import. §3's measured 182/182 and 247/247 are the guard: when a new
code appears in a fixture, the sweep fails instead of silently passing it through.

## 5. Worked examples

Produced by a prototype of §4 run over the real fixture strings; every row below is a published
abbreviation from §3's pages.

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

Length: pairs mean 4.9 → 14.4 characters, max 11 → 31 (`Backward Outside Death Spiral 3`); dance
mean 10.1 → 20.7, max 15 → 40 (`Straight Line Lift 3 + Rotational Lift 3`). Recombining the partner
halves is what keeps the dance vocabulary under the singles worst case of 50.

## 6. Public API

Unchanged. No new type, no new protocol requirement, no signature change:

```swift
public nonisolated protocol ElementNameTranslating: Sendable {
    func displayName(for abbreviation: String) -> String    // default: the abbreviation, unchanged
}

public struct ElementNameExpander: ElementNameTranslating {
    public init()
    public func displayName(for abbreviation: String) -> String
}
```

`ElementData.init(_:translator:)` and `OverlayData.merge(_:translator:)` keep calling it unchanged,
so the app gets pairs and dance names the moment the tables land. `ProtocolParser` still needs no
new file target and no new package. The tables go in two new source files —
`ElementNameExpander+Pairs.swift` and `ElementNameExpander+Dance.swift` (§8 Q8) — so the change needs
`tuist generate` (`AGENTS.md` → Build & Run).

## 7. Integration consequences

### 7.1 What the app sees

- **Longer names.** Up to 40 characters for a dance element and 31 for a pairs element, both under
  the singles worst case of 50. The overlay's element-name row shrinks to fit rather than truncating
  (`abbreviation-expansion.md` §7), so the risk is legibility, not clipping; the scoring list gets a
  40-character text field.
- **`renderingHash` covers `name`**, so a re-import that changes an element's name invalidates that
  element's cached slides and chunks as any other data change does (`docs/ARCHITECTURE.md` §3.4).
- **The raw abbreviation is still not retained** — `ElementData` has only `name`. A rule change here
  means re-importing to see it (`abbreviation-expansion.md` §7).
- **` + ` keeps one meaning.** A two-partner element is recombined into a single name (§4.6), so
  ` + ` only ever separates elements: a jump combination, two halves of a lift combination.

### 7.2 Adjacent gaps this specification does not close

- **Team names.** A dance page's name cell is `Lara Luft / Ilias Fourati` with no club, so
  `ProtocolSkater.namePart` returns the whole string and `club` is `nil` — the same shape as a pairs
  entry (`ProtocolModel.swift`). Selecting a team by name therefore works the way pairs already does;
  nothing here changes it.
- **Pages with no element table.** Nine of the event's twenty-two detail pages — the solo pattern
  dances and the solo free dances — have program components only, so the parser's
  `elementTableMissing` path applies. That is an importer question, not an expansion one.
- **Markers not measured.** None of the thirteen dance pages carries `S`, `>`, `*`, `ExEI` or a
  reduced level on a pattern-dance code (§4.5 lists them from the ISU list). The first pass should
  implement them, but they cannot be pinned by a fixture sweep until a page that uses them is
  captured; until then each is one synthetic test.

## 8. Decisions

Settled. Every row is now a rule in §4, not an option; the numbers are kept so a later pass can tell
which rule is which.

| # | Decision | Outcome |
|---|---|---|
| Q1 | Pairs twist lift, which has two bare numbers | `3 Twist Lift 3` — the code's own word between the numbers |
| Q2 | Where `W` / `M` sits in a dance name | **Folded into Q5**; a lone half reads `<name> <W\|M> <level>` |
| Q3 | Whether a pattern-dance code shows the dance name | Yes when the code names a dance (`Fourteenstep Seq 1 4`, `Golden Waltz 1 2`); `Pattern Dance <n> <level>` and `Pattern Dance Seq <n> <level>` for `RPD` and the `1WW`/`2WW` slot codes |
| Q4 | `pSTw` against `SyTw` | Identical names — `p` dropped, as `pChSq1`'s already is |
| Q5 | A two-partner element must not read as two elements | Recombined into one name: `Sequential Twizzles W 4 / M 4` (§4.6). Supersedes Q2 |
| Q6 | `ChSt` against `pChSt` | `Choreo Char Step Sequence 1` / `Choreo Step Sequence 1` |
| Q7 | ISU codes with no page in this set | Named now from the ISU list: `PSt`, `SoTw`, `SpEe`, `CrEe`, `SeEs`, `IBEe` (§4.3), each pinned by a synthetic test |
| Q8 | Where the tables live | Split into `ElementNameExpander+Pairs.swift` and `ElementNameExpander+Dance.swift` `[generate]` |

## 9. Testing

Pure string tests plus the two fixture sweeps; no fixture is needed for a single row.

| # | Test | Expectation |
|---|---|---|
| 1 | Pairs throws and twists | `3STh` → `Throw 3 Salchow` (the word first, the jump second), `2LoTh` → `Throw 2 Loop`, `1TwB` → `1 Twist Lift B`, `3Tw3b1` → `3 Twist Lift 3` |
| 2 | Pairs lifts | `1Li4` → `1 Lift 4`, `4LiB` → `4 Lift B`, `2LiB`, `5ALi4` → `5 Axel Lasso Lift 4`; and `4Li3` is not a level-3 reading of `4` |
| 3 | Death spirals, pivot, pair spins | `BoDs3`, `FiDsB`, `PiF1`, `PSpB`, `PCoSp3` |
| 4 | Pairs solo vocabulary unchanged | `3Tb1+2A+SEQ`, `2F<`, `ChSq1` render exactly as the singles rules already do |
| 5 | Dance lifts and spin | `StaLi4+RoLi4` → `Stationary Lift 4 + Rotational Lift 4` (not recombined), `SlLi3+RoLi3`, `CuLi4`, `RoLi2`, `DSpB`; `SiLi4` aliases `SlLi4` |
| 6 | Twizzle halves recombine | `SqTwW4+SqTwM4` → `Sequential Twizzles W 4 / M 4`; `SyTwW3+SyTwM4`; `pSTwW4+pSTwM1` → `Synchronized Twizzles …`; a lone `SqTwW4` keeps the singular form; `SqTwM` (no level) → name alone |
| 7 | Dance steps and turns recombine | `MiStW1+MiStM2` → `Midline Steps W 1 / M 2`, `MiStW1+MiStMB` → `… W 1 / M B`, `CiStW2+CiStM2`, `DiStW1+DiStM1`, `SeStW1+SeStM1`, `OFTW2+OFTM3` → `One Foot Turns W 2 / M 3` |
| 8 | Choreographic family | `ChAJ1`, `ChSt1` → `Choreo Char Step Sequence 1`, `ChSl1`, `ChLi1`, `ChSp1`, `pChSt1` → `Choreo Step Sequence 1`, `ChPSp1`, `ChPLi1` — all distinct names, none colliding with `ChSq1` |
| 9 | Creative dance element | `CDE4` → `Creative Dance Element 4` |
| 9a | ISU codes with no fixture row | `PSt4` → `Pattern Dance Type Step Sequence Style D 4`, `SoTw3`, `SpEe2`, `CrEe1`, `SeEs2`, `IBEe1` — one synthetic test each, names taken from the ISU list (§8 Q7) |
| 10 | Both pattern-dance grammars | `FO1Sq4+kpYYYY` → `Fourteenstep Seq 1 4`; `TA2Sq1+kpNYNN`; `1GW2+kpYNNY` → `Golden Waltz 1 2` |
| 11 | Pattern codes that must not be named | `1WW1+kpNNNY` and `2WWB+kpNNNN` → `Pattern Dance …`; `RPD41Sq4`/`RPD22Sq1` → `Pattern Dance Seq …` (the digit is a sequence count, not a dance) |
| 12 | Dance-only markers | `SqTwW4S` (separation), `StaLi4>` (extended), `ExEI` kept as its own part, `*` → `(Invalid)` |
| 13 | Marker collisions | `S` alone is still Salchow, `StSq2`/`ChSq1` still classify, `e` still strips on a jump and on a choreographic code |
| 14 | Sweep, pairs | 182/182 rows, 66/66 abbreviations, zero verbatim passthrough |
| 15 | Sweep, ice dance | 247/247 rows, 121/121 abbreviations, zero verbatim passthrough |
| 16 | Well-formedness sweep | no empty part, no doubled separator, no `kp…` in the output, over all 429 rows |
| 17 | Singles regression | the existing 535/535 singles sweep and all 17 singles tests stay green — the spin and choreographic tables are shared, so this is the test that catches a table addition that reclassifies a singles token. The prototype already classifies all 535 with zero passthrough and reproduces all 24 examples in `abbreviation-expansion.md` §5 byte for byte |
| 18 | Recombination is narrow | two halves with *different* codes are not recombined (`SlLi3+RoLi3`), a lone half is not pluralised, and the letters must be one `W` and one `M` — `SqTwW4+SqTwW4` is not a pair |
| 19 | Identity default | unchanged |

Counts for 14–17 are the §3 numbers; they are the ones to re-measure (not re-quote) if the tables
change. The suite grows `ElementNameExpanderTests` or adds a sibling suite per vocabulary; the
`ProtocolParser` total in [`docs/testing.md`](../testing.md) is updated in the same change.

## 10. Verification performed and not performed

- **Performed (no repo change):** a prototype of §4 over all 429 rows of the five pairs and thirteen
  dance pages — **0 unclassified tokens**, 182/182 and 247/247 rows expanded, and every count in §3
  and every row of §5 is that run's output. The shipped `ElementNameExpander` was compiled
  standalone and run over the same 429 rows to establish the baseline: it changes 58 pairs and 153
  dance rows, and **every** one of those changes is the shared vocabulary (solo jumps, `+SEQ`,
  `ChSq1`, `ChSp1`) or the separator around a dropped `kp…` token — **no pairs or dance code is
  altered today**, so these tests pin existing behaviour rather than fix a defect.
- **Performed (no repo change), the other direction:** the same prototype, extended as §4 requires,
  still classifies all **535/535** singles rows with zero passthrough and reproduces all **24**
  examples in `abbreviation-expansion.md` §5 exactly, including the `V` spin suffix
  (`CCoSpBV` → `Change Combo Spin B V`). The new branches are additive to the singles vocabulary.
- **Not performed:** no Swift change; `S`, `>`, `ExEI` and PD level reduction are specified from the
  ISU abbreviation list and have no fixture row (§7.2); the same goes for `PSt`, `SoTw` and the four
  solo-dance edge elements (§8 Q7) — their code shapes and names are the ISU list's, so the first
  page that publishes one may correct both. The on-screen fit of the longest names is computed from
  `Metrics`, not measured on a rendered overlay.
- The ISU names in §4.2–§4.4 come from the ISU judging-system abbreviation list for 2026-27, and the
  unpublished-code spellings (`SlLi` against the list's `SiLi`, `ChSl` against `ChSI`) from the
  published pages — the pages win, with the list's spelling kept as an alias.

## 11. Dependencies

**None** beyond the Swift standard library. Tables and branches in an existing type, in a module the
app already links; no package, no module, no manifest change (`docs/ARCHITECTURE.md` §2.2 policy not
exercised). One optional new source file if §8 Q8 splits the expander, which needs `tuist generate`.
