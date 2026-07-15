# /check-consistency — the fresh-eyed multi-hat RENDERED-docs panel

Fire an expert panel of fresh-eyed agents at the **rendered** documentation and collect every
internal-consistency and expert-instinct defect they find. This is the **judgment-level** counterpart to
`/check-docs`: where `/check-docs` runs a *deterministic* battery (greps, build lints, the
argument-coverage sweep) against the **source**, `/check-consistency` reads the **rendered site as a
reader would** and hunts what a grep cannot — a quantity or normalization defined two ways across pages, a
mathematical or convention error, a structure/design smell, an unreachable citation, a cold-read gap.

Each hat is a **fresh agent** that reads ONLY the reader-text manuscript (no `src/`, no `CLAUDE.md`, no
memory — it judges the docs as written, from its own expertise) and banks its findings to a file. The
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
— do not lean on the panel for them.

## The panel (11 hats)

Substrate **FULL** = every rendered page incl. the design docs; **SITEONLY** = the four design docs
(Architecture / Formalization / Testing / Performance) withheld, so the two no-design-doc hats judge
self-containedness and structure without the design docs as a crutch.

| # | Hat | Lens | Substrate |
|---|-----|------|-----------|
| 1 | `consistency-matrix` | the spine — matrix every recurring entity (object, symbol, formula, normalization, method, docstring shape) and diff it across all pages | FULL |
| 2 | `software-architect` | the *documented* design as a senior Julia dev — signatures, dispatch, `f`/`f!`, the section/representation decomposition, single-source-of-truth, decision-log soundness | FULL |
| 3 | `spectral-methods-mathematician` | every field operation's mathematics vs pseudospectral theory *and* itself — the transform pair and where `1/N` lives, the `iκ`/`−|k|²` multipliers and the Nyquist split, Parseval, Hermitian symmetry, spline order & smoothness | FULL |
| 4 | `gpu-kernel-practitioner` | the allocation / backend / performance claims — allocation-free in-place, no scalar indexing, plan reuse, kernel fusion, CPU/CUDA/ROCm parity, `Float32`/`Float64` | FULL |
| 5 | `structure-consistency` | infer the implicit docstring template, then flag every outlier against it | SITEONLY |
| 6 | `latex-typesetter` | every formula's TeX idiom read as source, in the house style (upright `\mathrm{i}`/`\mathrm{d}`, component notation, `\Bigl` preferred, braced fractions, no gratuitous `\,`) | FULL |
| 7 | `api-user` | build/drive the library from the docs alone — arg coverage, return shapes/representations, exported-vs-documented agreement | FULL |
| 8 | `normalization-convention-auditor` | every normalization factor & indexing convention correct *and* identical across pages (the `1/N`, the multiplier signs, `fftfreq`/rFFT-Nyquist, the Parseval/spectrum factors, the `N/M` adjoint) | FULL |
| 9 | `citations-integrity` | consistent author-year, inline↔reference-block matching with verbatim DOIs, no inaccessible source, no overclaim | FULL |
| 10 | `style-editor` | internal uniformity (majority style) **+** the raw built HTML for silent-render failures | FULL + raw HTML |
| 11 | `cold-reader` | a Fourier-literate newcomer's top-to-bottom cold read — undefined symbols/terms, self-containedness | SITEONLY |

The hats live in `.claude/commands/check-consistency/panel.js` (their personas are the source of truth;
this table is the map). Scale the panel to the ask: this full 11-hat run is the "thorough audit" (~2 M
tokens, tens of minutes); for a quick check, run a subset.

## Run it

Let `$SCRATCH` be this session's scratchpad and `$REPO` the repo root (absolute). The large, ephemeral
manuscripts go in `$SCRATCH`; the findings pile is the repo's `.claude/doc-review/`.

1. **Build the docs fresh** — the panel reads the *rendered* output, so it must be current, and the two
   build lints must be clean first (`docs/Project.toml` already dev-links the package, so the
   `Pkg.develop` is a defensive no-op that also fixes a fresh checkout):
   ```bash
   julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd()))' >/dev/null 2>&1
   julia --project=docs docs/make.jl          # both lints + checkdocs + doctests must pass
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
              args: { full:     "$SCRATCH/manuscript-full.md",
                      siteonly: "$SCRATCH/manuscript-siteonly.md",
                      rawhtml:  "$REPO/docs/build",
                      pile:     "$REPO/.claude/doc-review" } })
   ```
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

## Output

- `.claude/doc-review/NN-<key>.md` — one file per hat (the raw banked findings).
- `.claude/doc-review/00-SUMMARY.md` — the consolidated, deduplicated, ranked report with dispositions,
  the verified-clean batteries, and the confirmed false positives.
- An **Artifact** dashboard (filterable by severity/surface) for the user to scan.
- `.claude/doc-review-prev/` — the previous round, kept for diffing.

`.claude/doc-review*` is untracked working notes (never commit it — stage tracked files with `git add -u`,
never `-A`). This command file and its `check-consistency/` scripts ARE tracked.
