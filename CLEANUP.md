# CLEANUP.md — structural review backlog

A ranked list of proposed work from an audit of the whole tree for **modularity, isolation, code
repetition and readability**. Every item names the file and line it lives at and what to create,
move or delete — no "consider refactoring".

**How to use this file:** delete an item when it lands; this list should shrink, never accumulate.
IDs are never reused, so a gap in the numbering is finished work (B1–B4, M1–M5, R1–R6 and Y1–Y6 are
all done). It is a backlog, not a design doc: rationale for anything that ships goes in `docs/HISTORY.md`
per `AGENTS.md` → Documentation, and `docs/ARCHITECTURE.md` stays current-state only.

**Tags**

- **[generate]** — the fix moves code into new files, so it needs `tuist generate` afterwards
  (sources are globbed from `Project.swift`; a new file is not in the workspace until then).
- **verified** — the behaviour was reproduced with a throwaway probe test, reverted afterwards.
- **read** — the claim comes from reading the code, not from running it.

Accepted as designed, not to be re-litigated: two `AVURLAsset`s over one file, the hand-written
`PreviewVideoCompositor`, and `Metrics.transitionTime = 0.75` — `docs/HISTORY.md` → *Playhead
freeze*. The `ProtocolParser` module is the model the rest of the tree should follow: pure parsing
behind a `ProtocolFetching` IO seam, an injectable `ElementNameTranslating`, value types only.

---

## What is left

Nothing. Every item from the audit has landed; this file can be retired (deleted) whenever you like —
the reasoning for what shipped is in `docs/HISTORY.md`, one ledger row per change.
