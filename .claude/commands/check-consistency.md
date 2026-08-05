# /check-consistency — the fresh-eyed multi-hat RENDERED-docs panel

Fire an expert panel of fresh-eyed agents at the **rendered** documentation and collect every
internal-consistency and expert-instinct defect they find. This is the **judgment-level** counterpart to
`/check-docs`: where `/check-docs` runs a *deterministic* battery (greps, build lints, the
argument-coverage sweep) against the **source**, `/check-consistency` reads the **rendered site as a
reader would** and hunts what a grep cannot — a quantity or normalization defined two ways across pages, a
mathematical or convention error, a structure/design smell, an unreachable citation, a cold-read gap.

Each hat is a **fresh agent** that reads ONLY the reader-text manuscript (no `src/`, no `CLAUDE.md`, no
memory — it judges the docs as written, from its own expertise) and banks its findings to a file. **One
exception:** the `latex-typesetter` hat (#7) also reads the authored **source** (`src/`, `docs/`,
`examples/`) and the **`CLAUDE.md` §Style** rulebook — typesetting idiom lives in the source markup, not the
rendered output, and the house style it enforces is defined in `CLAUDE.md`. The
panel is **collect-only**: it never edits `src/` or `docs/`; you act only when the user says fix. It runs
**sequentially**, so a token-out loses at most the current hat; the hat order is **priority** (most
critical first).

## What it catches — and what it does not

Catches: cross-page contradictions, mathematical / normalization / category errors, method disagreements,
design and API smells in the *documented* interface, structure non-uniformity, citation gaps/overclaims,
and self-containedness ("cold read") failures. These need judgment and cross-referencing.

Does **not** reliably catch: mechanical, pattern-matchable idioms — gratuitous `\,`, unbraced
`\tfrac`/`\frac`, a bare italic imaginary unit `i` / differential `d`, bare-index `\partial_i`,
formula-in-backticks. A hat that *reads* the TeX may not *flag* these (a panel once read the `\,` overuse
and waved it through). **Those belong to `/check-docs`'s deterministic scans** (several are build-enforced)
— do not lean on the panel for them. (The `latex-typesetter` hat now comes closest: it reads the authored
**source** against the `CLAUDE.md` §Style rulebook, so it is a real judgment-level backstop — but
`/check-docs` stays the enforcement, and the hat is told to spend its effort on the context calls a grep
cannot make.)

## The panel (12 hats)

Substrate **FULL** = every rendered page incl. the design docs; **SITEONLY** = the four design docs
(Architecture / Formalization / Testing / Performance) withheld, so the two no-design-doc hats judge
self-containedness and structure without the design docs as a crutch.

| # | Hat | Lens | Substrate |
|---|-----|------|-----------|
| 1 | `consistency-matrix` | the spine — matrix every recurring entity (object, symbol, formula, normalization, method, docstring shape) and diff it across all pages | FULL |
| 2 | `software-architect` | the *documented* design as a senior Julia dev — signatures, dispatch, `f`/`f!`, the section/representation decomposition, single-source-of-truth, decision-log soundness | FULL |
| 3 | `spectral-methods-mathematician` | every field operation's mathematics vs pseudospectral theory *and* itself — the transform pair and where `1/N` lives, the `iκ`/`−|k|²` multipliers and the Nyquist split, Parseval, Hermitian symmetry, spline order & smoothness | FULL |
| 4 | `differential-geometer` | the *intrinsic* structure — the fiber-bundle / section model, base vs fiber, the measure taxonomy, and the adjoint/duality claims as maps between the right spaces; the category/type errors a value-check can't see (a fiber `ℝ^N⊗V` flattened to `ℝ^N`, the `N/M` measure-adjoint, an object conflated with its representation) | FULL |
| 5 | `gpu-kernel-practitioner` | the allocation / backend / performance claims — allocation-free in-place, no scalar indexing, plan reuse, kernel fusion, CPU/CUDA/ROCm parity, `Float32`/`Float64` | FULL |
| 6 | `structure-consistency` | infer the implicit docstring template, then flag every outlier against it | SITEONLY |
| 7 | `latex-typesetter` | every formula's TeX idiom, judged against the **`CLAUDE.md` §Style** rulebook and reading the authored **source** (not just the rendered output): upright `\mathrm{i}`/`\mathrm{d}`, component notation, braced fractions, no gratuitous `\,`, no manual `\;`/`\!` spacing, no `\left`/`\right` (bar the `\left\{ … \right.` system), `\mathbb` only on `A`–`Z`/`k` | FULL + source + CLAUDE.md |
| 8 | `api-user` | build/drive the library from the docs alone — arg coverage, return shapes/representations, exported-vs-documented agreement | FULL |
| 9 | `normalization-convention-auditor` | every normalization factor & indexing convention correct *and* identical across pages (the `1/N`, the multiplier signs, `fftfreq`/rFFT-Nyquist, the Parseval/spectrum factors, the `N/M` adjoint) | FULL |
| 10 | `citations-integrity` | consistent author-year, inline↔reference-block matching with verbatim DOIs, no inaccessible source, no overclaim | FULL |
| 11 | `style-editor` | internal uniformity (majority style) **+** the raw built HTML for silent-render failures | FULL + raw HTML |
| 12 | `cold-reader` | a Fourier-literate newcomer's top-to-bottom cold read — undefined symbols/terms, self-containedness | SITEONLY |

The hats live in `.claude/commands/check-consistency/panel.js` (their personas are the source of truth;
this table is the map). Two mathematicians sit adjacent by design — `spectral-methods-mathematician` (applied
Fourier/numerics) then `differential-geometer` (intrinsic geometry / measure theory / functional analysis) —
the applied one catching the concrete sign/normalization bugs, the pure one the structural/category errors.
Scale the panel to the ask: the full 12-hat run is the "thorough audit" (tens of minutes; cost per the modes
below); for a quick check, run a subset.

## Cost modes (mirrors `/check-docs` — policy 2026-07-23)

**Economy is the DEFAULT.** Ten of the twelve hats run on the cheap scan model (Sonnet); the two
mathematician hats — `spectral-methods-mathematician` and `differential-geometer` — are **anchors** that
always run at the session's full-strength model. The asymmetry is deliberate: a cheap hat's *false
positive* is caught downstream (the discipline already verifies every Tier-1/2 finding against `src/` and
the built HTML in the main thread, at full strength), but a *false negative* — a subtle category error or
structurally-false-but-plausible sentence read past — has no downstream verifier, and those two hats exist
precisely for that class. The other ten lenses are enumerative or rule-anchored (matrix-diffing, template
outliers, arg coverage, citations, style, the written §Style typesetting rulebook, the cold read), the
kind of narrow evidence-cited scan the cheap lanes have proven strong at (the 659-formula Phase-B sweep
and the five coverage-axes lanes both ran on them), and the panel's cross-hat redundancy means the
anchors' domains overlap most of what a cheap hat could miss. Net: roughly a 3–4× panel-cost cut for a
little extra false-positive noise, absorbed by the verification step. **Never economized:** the
main-thread verification, the consolidation/ranking, and any later fix pass — the same rule as
`/check-docs`. **Full strength** (every hat at the session model) runs only on explicit request: pass
`strength: "full"` in the Workflow args.

## Run it

Let `$SCRATCH` be this session's scratchpad and `$REPO` the repo root (absolute). The large, ephemeral
manuscripts go in `$SCRATCH`; the findings pile is the repo's `.claude/doc-review/`.

1. **Build the docs fresh** — the panel reads the *rendered* output, so it must be current, and the two
   build lints must be clean first (`docs/Project.toml` already dev-links the package, so the
   `Pkg.develop` is a defensive no-op that also fixes a fresh checkout):
   ```bash
   julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd()))' >/dev/null 2>&1
   julia --project=docs docs/make.jl; echo $?  # all four lints + checkdocs + doctests; REQUIRE exit 0
   # (never grep the output for errors — a lint failure prints `ERROR:`, not `┌ Error`)
   git checkout -- docs/Project.toml           # revert the transient dev entry (Project.toml ALONE)
   ```
2. **Consolidate** the built HTML into the two reader-text manuscripts (needs `beautifulsoup4`):
   ```bash
   python3 .claude/commands/check-consistency/consolidate.py docs/build \
       "$SCRATCH/manuscript-full.md" "$SCRATCH/manuscript-siteonly.md"
   ```
   Confirm the reported page count matches the site and no page is empty.
3. **Archive** any prior findings so a re-run starts clean (keep the last round for diffing):
   ```bash
   if [ -n "$(ls -A .claude/doc-review 2>/dev/null)" ]; then
     rm -rf .claude/doc-review-prev && mv .claude/doc-review .claude/doc-review-prev
   fi
   mkdir -p .claude/doc-review
   ```
4. **Run the panel** — a background `Workflow` on the companion script, sequential, collect-only. Pass
   **absolute** paths (each hat `Read`s them):
   ```
   Workflow({ scriptPath: ".claude/commands/check-consistency/panel.js",
              args: { full:        "$SCRATCH/manuscript-full.md",
                      siteonly:    "$SCRATCH/manuscript-siteonly.md",
                      rawhtml:     "$REPO/docs/build",
                      pile:        "$REPO/.claude/doc-review",
                      adjudicated: "$REPO/.claude/doc-review-adjudicated.md",
                      strength:    "economy" } })   # the default; "full" only on explicit request
   ```
   **The hats are otherwise BLIND to prior rounds, and that is the design** — fresh eyes are the whole
   instrument, and it is why round 2 caught a mathematically false sentence that round 1's *fix pass*
   had introduced. The one exception is `adjudicated`, injected into every hat's preamble: findings
   settled as **not** defects (manuscript-extraction artifacts, user-closed design decisions). Nothing
   merely *fixed* belongs in that file — re-flagging a bad fix is exactly what the panel is for.
   Measured cost of omitting it: 4 of round 2's 87 findings were re-litigation of settled material,
   including one hat's **top-ranked** finding.
   Each hat banks `.claude/doc-review/NN-<key>.md` and returns a structured findings object; you are
   notified when the workflow completes.
5. **Consolidate the findings** into `.claude/doc-review/00-SUMMARY.md` **and an Artifact dashboard**:
   read every `NN-*.md`, **dedup** (cluster cross-hat — a defect found by many hats is a strong signal),
   **rank** by severity × corroboration, and record which batteries came back **clean** and which are
   confirmed **false positives**.

## Discipline (the hard-won rules — follow them)

- **Collect-only.** The panel proposes; the user disposes. Do not touch `src/` or `docs/` during a panel
  run, and do not "quietly fix while I'm here."
- **Verify before you trust — a rendered-text read is not ground truth.** Before reporting any Tier-1/2
  finding, confirm it against the **current `src/`** and the **built HTML** (quote the decisive line).
  Rendered-text reads have produced *false* blockers: a decision log that renders `<ol>` misread as
  unnumbered; a grep-escaping slip that "found" zero of something that was plentiful. Re-check the crux, do
  not relay it raw.
- **Judgment, not mechanics.** See "what it does not catch" — route mechanical idioms to `/check-docs`.
- **Don't launder a flagged smell.** Never close a finding by declaring it "by design" / "for symmetry" /
  "it's convenient". Fix it, or escalate it to the user with the trade-off — the user decides. (The genuine
  by-design absences — no time, no particles, no physics; the deliberate method-set gaps — are stated in
  the docs; a hat is told not to flag those as gaps.)
- **Record dispositions and false positives** in `00-SUMMARY.md` (a short block at the top): what was
  fixed, escalated, left-with-a-first-principle-reason, and confirmed-not-a-defect. A later run reads this
  so it does not re-flag settled items; a still-open finding stays visible.
- **A flagged instance is a sample of a class** — when you do fix (later, on the user's word), fix the
  class across every surface, not just the quoted line.
- **The per-hat files are the work list; `00-SUMMARY.md` is a reading aid.** The consolidated summary is
  written **for the user** — deduplicated, ranked, scannable — and consolidation is *lossy by design*,
  which is exactly what makes it readable. So a fix pass **must be driven from the banked `NN-*.md`
  files**, enumerating every finding in every hat and closing it by number; the summary is never the
  input. Two failures on the 2026-07-24 run prove the point, and both survived that run's fix pass
  untouched because it worked from the summary: `structure-consistency` filed 20 findings and the
  summary folded 19 of them into a single parenthetical inside an unrelated cluster (only its blocker
  was closed; the other 19 surfaced later the same day, and only because the banked file was opened
  directly); and `cold-reader`'s "operation family" finding,
  filed **major / high confidence / contradiction**, was relayed as "soft — no single page is wrong",
  which was false, since "the third of three" and "each of eight submodules owns one" cannot both hold.
  **A severity in the summary never overrides the hat's own** — re-read the hat before downgrading
  anything. Report closure **per hat and per finding number** ("06: 20/20 closed"), so the count is
  auditable against the banked files rather than against the summary's clusters.
- **Bounded output per hat.** Each hat is capped at its ~25 most significant findings with tight quotes
  (the preamble enforces it): the banked file and the returned object mirror each other, so an unbounded
  dump doubles on output and overran the 64k output-token cap (it killed two hats on the 2026-07-23 run).
  A hat that would exceed the cap is being insufficiently selective, not thorough — 15 sharp findings beat
  50 padded ones. A killed hat is simply re-run standalone (same persona, the cap in its prompt) to fill
  its `NN-<key>.md` gap; the other hats' banked files are untouched.

## Output

- `.claude/doc-review/NN-<key>.md` — one file per hat (the raw banked findings).
- `.claude/doc-review/00-SUMMARY.md` — the consolidated, deduplicated, ranked report with dispositions,
  the verified-clean batteries, and the confirmed false positives.
- An **Artifact** dashboard (filterable by severity/surface) for the user to scan.
- `.claude/doc-review-prev/` — the previous round, kept for diffing.

`.claude/doc-review*` is untracked working notes (never commit it — stage tracked files with `git add -u`,
never `-A`). This command file and its `check-consistency/` scripts ARE tracked.
