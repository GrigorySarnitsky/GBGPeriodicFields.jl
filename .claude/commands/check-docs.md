---
description: Run the COMPLETE documentation-quality battery — every check across every doc surface, fix all findings, rebuild.
---

Run the **entire** documentation-quality battery. This is the full matrix of (every check) × (every
surface), run to completion in one invocation — not a single check, not a single file. Do not stop after
one check or one file, and do not ask which check to run. Cover every cell, fix every genuine finding in
one pass, rebuild, and report the matrix.

## Cost modes — cheap lanes by default; the fix is never economized

The scan/review lanes run on a **cheaper agent model by default** (the economy mode is the standard
one — Sonnet-class lanes; lane cost is the ONLY thing it reduces). Run the lanes at full strength
only when the user explicitly asks for it (in any words — "strong lanes", "full-price scan",
"expensive lanes"). In EVERY mode the **fix phase is never reduced**: the main thread — at its own
(strongest) model, full effort — verifies every finding and closes every one in the same run, as
*fixed* or as *dismissed with a written reason*, including the expensive judgment calls (cold-reader
glosses, argument-coverage triage against the at-home rule, the class sweeps the findings demand).
Deferring findings to a later session is NOT an outcome of any mode. All modes produce the identical
end state — zero open findings, clean build — and differ only in what the lanes cost. (Policy:
full-fix-in-any-mode set 2026-07-23, after the 2026-07-22 economy run deferred its judgment tail as
a standing remainder — the failure mode this paragraph forbids; cheap-lanes-by-default set
2026-07-23.)

## Surfaces (ALL of them)

1. `docs/ARCHITECTURE.md` — every section §1–§13 and §References.
2. `docs/FORMALIZATION.md`, `docs/TESTING.md`, `docs/PERFORMANCE.md`.
3. Every docstring in `src/*.jl` — FiberSections, Fields, FieldAlgebra, DifferentialOperators,
   Convolution, Points, Interpolation, Reductions, and the umbrella `GBGPeriodicFields.jl` (Public **and**
   Internal docstrings; `#` comments are exempt — not rendered).
4. Every page in `docs/src/` — `index.md`, `tutorial.md`, and all `docs/src/api/*.md` (hand-written prose;
   skip `@autodocs` / `@example` / `@repl` / `@contents` / `@index` blocks).
5. The Literate example `examples/HIST_CPU.jl` (and the GPU sibling) — **a rendered doc page**: every
   full-line `# ` comment becomes prose, so its math is LaTeX under the same rules, single-backslash (the
   LaTeX lives in comments, not docstrings). The build lints already scan the generated
   `docs/src/examples/hist_cpu.md`; edit the *source* `.jl`.

6. **The BUILT HTML** — `docs/build/api/*/index.html`, after `julia --project=docs docs/make.jl`. This
   is a surface in its own right, not a rendering of surface 4: the API pages are mostly `@autodocs`
   and `@docs` blocks whose CONTENTS ARE DERIVED, and surface 4 explicitly skips those blocks. What
   each block actually collected is visible only here. Two defects lived in this gap and neither was
   findable by reading any `.md`: `map`, `map!` and `transpose` filed under FieldAlgebra's "Internal
   API" (Documenter cannot tell that a Base function the package extends without re-exporting is
   public, so `Public = false` sweeps it in — the block already excluded `+ - * /` for that reason and
   missed the rest), and three Internal API blurbs describing contents their sections do not hold
   (FieldAlgebra's named code generators that moved to `FiberSections` a consolidation ago).

## Checks (ALL of them, on every surface)

Run each as a POSITIVE procedure — enumerate, then verify each item. A defect that is absent-by-omission
(an unbound symbol; a false-but-plausible formula) does not announce itself on a read-through, so passive
reading is not a check.

1. **Correct** — enumerate every formula, normalization constant (the `1/N`, `1/N²`, `2π/L`, Parseval
   factors), adjoint/conservation relation, complexity claim, and quantifier (*exact / all / never /
   bit-for-bit*); verify EACH against the implementation in `src/` (read it, quote the decisive line) or by
   derivation. Flag false / imprecise / overclaim. For a nontrivial statement the sharpest method is to
   write it formally on scratch (types from the code) and expand it. The verified statements live in
   `docs/FORMALIZATION.md`: check each nontrivial prose claim **against its entry** (the chain is *prose ↔
   formalization ↔ test* — the prose agrees with the typed statement, the statement is verified against the
   code, the linked test enforces it), and flag any nontrivial statement with **no entry**, or an entry with
   **no test link**, as a coverage gap.
2. **Self-contained** — enumerate every symbol, sub/superscript, operator name, and bold/blackboard letter;
   cite the clause that binds each; flag any unbound. (Universally standard math — `∇`, `Δ`, `∫`, `ℝ`, `π`,
   the imaginary unit `i`, plain summation indices — needs no binding.) **And, separately, from each
   docstring's *signature*:** enumerate every argument (positional *and* keyword) and cite where the body
   documents it — an argument mentioned only *inside a formula* reads as bound-by-use and is `UNDOCUMENTED`.
   **And the same bar binds *terms of art*, not only symbols:** a noun naming a package concept (an
   *assignment*, a *section*, a *cutoff*, "the destination's length") must be explained in a clause on the
   page or `@ref`-linked, not left correct only to a reader who already knows the package — the **cold read**
   (parse the docstring with the module's source withheld) is the test (`threading_cutoff`'s "element count
   … assignment" passed the symbol sweep and still baffled a fresh reader). Run this in the cold-reader lane.
3. **Notation — one symbol per concept, one concept per symbol, and coordinate-free** — flag a concept
   wearing two symbols; a glyph with two meanings in one section; and basis-dependent *section-level*
   machinery (a dense map matrix `W_{pn}`, an all-ones vector `𝟙`, flattening a section space `ℝ^N⊗V` to
   `ℝ^N`) that buries the base⊗fiber structure. Prefer intrinsic operators and honest sums/integrals; fiber
   component notation (`A_{ij}u_j`, the genuine 3×3 fiber matrix) is fine; if a matrix form mirrors the
   code, name the basis and the space. (`docs/FORMALIZATION.md` is exempt — it is the home for those
   coordinate/matrix expansions — but still subject to *Correct*.)
4. **Formatted (bidirectional)** — math is LaTeX, never backticks (incl. ASCII-math like `S = J*` that
   carries no glyph); every code identifier / type / module name is backticked, never bare; check BOTH
   directions. Markdown tables top-level, never indented in a list. Also the *silent* failures (source looks
   right, page renders broken): a code name never *inside* a ``…`` span, a formula never split across a
   ``…``/`` `code` `` boundary, inline math on one source line (build-enforced), and no >88-col signature or
   wide unbroken display block (horizontal scroll). **Notation idiom** (the `notation.md` house set): the
   imaginary unit and the differential are upright (``\mathrm{i}``, ``\mathrm{d}x``) — never a bare italic
   ``i``/``d`` — so a multiplier is ``\mathrm{i}k``, not `ik`, and an integral carries ``\,\mathrm{d}\mu``;
   every fraction argument is braced (``\tfrac{1}{2}``, not `\tfrac12`; build-enforced); adjacent factors
   juxtapose with **no** gratuitous thin space ``\,`` between them (the thin space is reserved for the
   differential); and a multi-letter run inside a math span is an upright token (``\mathrm{lo}``,
   ``\operatorname{Re}``), never a bare letter-product. The gratuitous-``\,`` and unbraced-fraction scans
   below must come back empty.
5. **Current** — every claim matches the code's present state; no stale *future / deferred / none-exist*;
   and **complete** — a docstring or summary that names only a *subset* of what the code now provides is
   stale even if literally true (e.g. a module docstring naming one of two scheme families, or a capability
   list missing a builder). Check each module/operation/summary still names everything added since it was
   written, against the current `export`s / method set.
6. **Cited** — context-standard author–year; ≤3 authors named, `First et al.` for 4+; inline references
   verbatim-consistent with the `ARCHITECTURE.md` §References entry.
7. **Consistent across variant pairs** (the `src/` docstrings — *relational*, not per-surface) — group each
   operation's generics (allocating `f` / in-place `f!`, getter / `set_…!`, physical / spectral) and confirm
   the defining math (formula, spectral kernel) lives in **one home**, every other variant a thin
   `@ref`-linking wrapper with no second copy of the formula and no notation that differs across the pair
   (the `\partial_i` vs `\partial_{x_i}` drift). Checks 1–6 each run inside one string and cannot see this;
   run it in the family lane. See `CLAUDE.md` §Style, "the review unit is the operation family and the cold read".

`CLAUDE.md` (the doc-edit checklist and the standing notation/structure rules) holds the authoritative
definitions; this command runs all of them.

### API page placement and completeness (surface 6 — the built HTML only)

Run after the build, by PARSING `docs/build/api/*/index.html`. Four questions, none answerable from
the source:

1. **Nothing public sits under "Internal API".** Any `Base.*` entry there is the `Public = false`
   sweep catching a Base extension the package owns; the fix is the block's `Filter`, and it is a
   CLASS — check every module, not the one that was reported.
2. **Nothing appears twice.** An object rendered in both a public section and an Internal API section
   is the same defect one step earlier.
3. **Nothing public is missing.** Diff the derived public surface (`test/public_surface.jl`'s
   `package_operations()`) against every non-Internal section. Expect only the unexported Base
   extensions (`size`, `eltype`, `axes`, `copy`, `copyto!`, `getindex`, `setindex!`, `ndims`, `in`),
   whose omission is deliberate — `checkdocs = :exports` does not require them. Anything else is a
   public operation with no home, which is how `transpose` came to be documented as an internal.
4. **Each Internal API blurb matches what its block collected.** The prose is hand-written and the
   list is derived, so they drift apart silently whenever code moves between modules or a `Filter`
   changes. Read the blurb against the rendered entries and check every clause names something
   present. Three of nine were wrong.

## Mechanism

- Fan out subagents across the surfaces in parallel, **on the cheaper (economy) lane model by
  default** (see Cost modes above) — each runs checks 1–6 on its surface via the
  positive procedures above, reading `src/` as ground truth, and returns genuine findings with evidence and
  a proposed fix.
- Two **cross-cutting lanes** (their grouping is not per-surface, so the surface agents cannot run them):
  a **family lane** that enumerates each operation's `f`/`f!` (and getter/`set_…!`) generics and diffs their
  docstrings for one-home + notation (check 7); and a **cold-reader lane** — an agent handed each exported
  docstring's text *alone, without the module's source*, reporting every term of art it cannot parse (check
  2's audience half). Neither is expressible as a grep. **Substrate rule for the cold-reader lane:** feed it
  the reader's *actual* `?name` view — include the **module docstring** (`?Module`), and **every** method
  docstring of a generic (Julia renders all of them), never one collapsed docstring. A substrate that skips
  the module docstring or shows one method of a multi-method generic makes the lane over-flag things
  documented centrally or on a sibling method, so **verify every cold-reader finding against source before
  fixing** (one sweep raised four such false positives — a module-documented argument, a multi-method verb
  pair, an operator pair, a core supertype — every one deflated on a code-check).
- Run the deterministic grep/awk guards below, plus a bare-module-name scan and a glyph-vs-backtick scan
  (Unicode math *outside* a backtick span). The block has two tiers: **must-be-empty** scans (tables,
  formula-in-backticks, stray `$…$`, neutral register, bare-index ∂, the gratuitous-``\,``, the unbraced
  fraction, the spacing/command idioms (``\!`` before ``\bigl``/``\Bigl``, ``\!\!``, ``\mathbb`` on a digit),
  wide signatures) and **triage** heuristics (``\left``/``\right`` and manual ``\;``/``\:`` spacing,
  code-in-math letter-products, split formulas, dead docstring refs, crammed citations, sentence-opening
  lowercase identifiers) whose hits mix real signal with
  false positives. Two non-grep backstops follow: a **DOI cross-check** (every docstring DOI is in
  `ARCHITECTURE.md` §References, verbatim) and the deterministic **argument-coverage** sweep (from each
  signature, positional + keyword; §Style — check 2). Inline-math-on-one-line and canonical notation are
  **build-enforced** — `docs/make.jl`'s `lint_inline_math()` errors on a span split by a list leader and
  `lint_notation_variants()` on a bare-index `\partial_[ijk]` **and an unbraced fraction ``\frac1``** — so
  the rebuild below IS those guards.

The doc surfaces are `src/*.jl` (docstrings), the four rationale docs, and the hand-written `docs/src`
pages — the same set the build lints scan. The gitignored `docs/src/{architecture,formalization,testing,
performance}.md` are regenerated *copies* of the rationale sources, so exclude them (edit the source, not
the copy). Set the doc list once:

```bash
DOCS_MD="docs/ARCHITECTURE.md docs/FORMALIZATION.md docs/TESTING.md docs/PERFORMANCE.md \
         docs/src/notation.md docs/src/index.md docs/src/tutorial.md docs/src/api.md docs/src/api/*.md \
         examples/HIST_CPU.jl examples/gpu/*/*.jl"   # the Literate examples are single-backslash md-style surfaces

# ---- must come back EMPTY ----
grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs                         # tables top-level only, never indented in a list
grep -rniE '\b(knobs?|tweaks?)\b' docs src examples               # neutral register
grep -rnE '\\partial_[ijk]' src $DOCS_MD                          # bare-index ∂ → \partial_{x_i}; build-enforced
grep -rnP '\\\\,(?!\\\\mathrm\{d\})' src/*.jl; grep -rnP '\\,(?!\\mathrm\{d\})' $DOCS_MD  # gratuitous thin space → keep only the differential \,\mathrm{d}, else a plain space (never delete: \varepsilon\,r → \varepsilon r, not \varepsilonr)
grep -rnP '\\\\[dt]?frac[0-9]' src/*.jl; grep -rnP '\\[dt]?frac[0-9]' $DOCS_MD  # unbraced fraction numerator → \frac{1}{N} (build-enforced by lint_notation_variants)
grep -rnP '\\\\!\\\\[bB]ig[lr]' src/*.jl; grep -rnP '\\!\\[bB]ig[lr]' $DOCS_MD  # \! before a fixed-size delimiter (\max\!\bigl) → drop it; there is already no gap there, so it only jams the delimiter into the name
grep -rnP '\\\\!\\\\!' src/*.jl; grep -rnP '\\!\\!' $DOCS_MD  # \!\! double negative thin (2\!\!\sum overshoots into an overlap) → juxtapose
grep -rnP '\\\\mathbb\s*\{?\s*[0-9]' src/*.jl; grep -rnP '\\mathbb\s*\{?\s*[0-9]' $DOCS_MD  # \mathbb on a digit (\mathbb{1} falls back to a plain glyph — KaTeX's bb font has no digit) → \mathbf{1}

# ---- TRIAGE (heuristics: real signal mixed with false positives — read each, then fix the genuine class) ----
grep -rnE '`[^`]*[≤≥≠∈∉∇Δ⟨⟩‖√][^`]*`' src $DOCS_MD | grep -vE ':[0-9]+:[[:space:]]*#'  # formula-in-backticks → ``LaTeX`` (FP: the real Julia operators ×/⋅/≈; a documented anti-pattern example)
grep -rnE '\$[^$]*[\\_^{}][^$]*\$' $DOCS_MD                        # stray TeX $…$ → use ``…`` / ```math``` (scope to sources, NOT docs/build)
grep -rnP '\\\\(left|right)(?![a-zA-Z])' src/*.jl; grep -rnP '\\(left|right)(?![a-zA-Z])' $DOCS_MD  # \left/\right auto-sized delimiter → size by hand with \bigl/\Bigl (FP: the \left\{ … \right. system idiom + notation.md's delimiter row; \leftarrow/\rightarrow arrows are excluded)
grep -rnP '\\\\[;:]' src/*.jl; grep -rnP '\\[;:]' $DOCS_MD  # manual \;/\: spacing around a relation/binary op (\;=\;) → write the operator bare and let TeX space it (FP: a \; separating args after a comma, \max(0,\; 1))
awk '/^"""/{d=!d;s=d;next} s&&/^[^ ]/{s=0} s&&/^    [A-Za-z_].*\(/&&length>88{print FILENAME":"FNR}' src/*.jl  # wide docstring signatures (>88 col) — FNR (per-file), NOT NR; hand-wrap the ones a reader would scroll
grep -rnoP '``[^`]*``' src/*.jl $DOCS_MD | grep -P '(?<![\\A-Za-z])(?<!\{)[a-z]{2,}' | grep -vP '\\(mathrm|texttt|text|operatorname|hat|[dt]?frac|sqrt|langle|rangle|partial|nabla|Delta|Omega|kappa|varepsilon|sum|prod|int|star|equiv|cdot|times|otimes|lVert|rVert|le|ge|to|mapsto|quad|left|right|Bigl|Bigr|begin|end|sin|cos|exp|log|max|min|Re|Im|det|tr)'  # code-in-math: a bare multi-letter run inside a math span (a letter-product, e.g. `ik`→\mathrm{i}k, `conj`→\overline{}) → \mathrm{…}; SUBSCRIPT index runs (A_{ij}) and #-comment lines are fine
grep -rnP '[^`\s]```[^`]|[^`]```[^`\s]' src/*.jl $DOCS_MD | grep -vP '^\S+:\d+:\s*```'  # split-formula: a ``math`` span abutting a `code` span (3 inline backticks); a documented ```math``` fence-name is a false positive
grep -rnE '§[0-9]|docs/(src|ARCHITECTURE|FORMALIZATION|TESTING|PERFORMANCE)|ARCHITECTURE\.md|inspiration/' src/*.jl | grep -vE ':[0-9]+:[[:space:]]*#'  # dead ref on a user-facing docstring: a §-number / design-doc path (must read complete at the REPL); drop #-comment hits
grep -rnzoE 'Reference[s]?:[^"]*;' src/*.jl                        # crammed citation block (two citations joined by ';') → one per bullet line
grep -rnE '\. (`[a-z]|``)' src/*.jl $DOCS_MD | grep -vE ':[0-9]+:[[:space:]]*#'  # prose SENTENCE opens with a lowercase code identifier OR a math formula → REWORD to lead with a capitalized word (NEVER capitalize the lowercase binding); exempt: bullets / list items (incl. §13 entries, arg-docs), `#` code comments, a CAPITALIZED type/module opener; FPs: e.g./i.e. abbreviations, end-of-line ``\checkmark`` markers
```

Two deterministic backstops that are not one-line greps:

```bash
# DOI cross-check — every DOI cited in a src docstring must appear (verbatim) in ARCHITECTURE.md's
# per-section reference blocks, and vice-versa (CLAUDE.md: the inline copy is verbatim-consistent).
python3 - <<'PY'
import re, glob
src = set()
for f in glob.glob('src/*.jl'):
    for m in re.findall(r'doi\.org/[^\s\)\]]+', open(f).read()):
        src.add(m.rstrip('.,);'))
arch = open('docs/ARCHITECTURE.md').read()
for d in sorted(src):
    if d not in arch: print('DOI in a docstring but not in ARCHITECTURE §References:', d)
PY

# Argument coverage — from each docstring SIGNATURE, every positional + keyword parameter must be
# mentioned as a backticked `arg` in the body (an arg named only inside a formula reads as bound-by-use).
# Triage: a thin wrapper that @ref-links its home may name a math variable in a ``f`` span not `f`; the
# α/β accumulation is documented under its Greek name; internal `_helpers` are looser.
julia --startup-file=no -e '
for file in filter(f->endswith(f,".jl"), readdir("src"; join=true))
  s = read(file, String)
  for m in eachmatch(r"\"\"\"\n(.*?)\n\"\"\""s, s)
    body = m.captures[1]; sig = strip(first(split(body, "\n")))
    (occursin("(", sig) && occursin(")", sig)) || continue
    o = findfirst("(", sig).start; c = findlast(")", sig).start
    inside = sig[nextind(sig, o):prevind(sig, c)]   # prevind, NOT c-1: α/β/σ are multibyte, and a
                                                    # StringIndexError aborts the sweep at the FIRST
                                                    # file, leaving the other seven unscanned while
                                                    # the run still looks like it completed
    for raw in split(inside, ",")
      p = strip(split(split(raw, "::")[1], "=")[1]); p = strip(split(p, ";")[end])
      occursin(r"^[A-Za-z][A-Za-z0-9_!]*$", p) || continue
      occursin(Regex("`\\Q"*p*"\\E`"), body) || println(file, ": ", sig, "  UNDOCUMENTED `", p, "`")
    end
  end
end'
```

```bash
# ---- SURFACE 6: the built API pages. Run AFTER `julia --project=docs docs/make.jl`. ----
# Buckets every rendered docstring under its heading and reports the three mechanical questions;
# question 4 (blurb vs contents) is a read, not a grep — do it from this script's own output.
python3 - <<'PYEOF'
import re, html, glob, os
pub_all, report = set(), []
for page in sorted(glob.glob('docs/build/api/*/index.html')):
    mod = os.path.basename(os.path.dirname(page)); s = open(page).read()
    heads = [(m.start(), m.group(1)) for m in re.finditer(r'<h[12] id="([^"]+)"', s)]
    pub, internal = [], []
    for m in re.finditer(r'<summary id="([^"]+)"><a class="docstring-binding"', s):
        sec = "(none)"
        for hpos, hid in heads:
            if hpos < m.start(): sec = hid
        name = html.unescape(m.group(1)).split('-')[0]
        (internal if "Internal" in sec else pub).append(name)
    pub_all |= {n.split('.')[-1] for n in pub}
    leaked = sorted({n for n in internal if n.startswith("Base.")})     # question 1
    both   = sorted(set(internal) & set(pub))                          # question 2
    if leaked or both:
        report.append(f"{mod}: PUBLIC-IN-INTERNAL={leaked} IN-BOTH={both}")
    print(f"{mod:22s} public={len(set(pub)):3d} internal={len(set(internal)):3d}")
    print(f"    internal entries: {sorted({n.split('.')[-1] for n in internal})}")
print()
print("\n".join(report) if report else "questions 1-2: clean")
PYEOF
# question 3 — every public operation must have a home in some public section
julia --project=test -e 'using GBGPeriodicFields; include("test/public_surface.jl");
  println(join(sort(String.(collect(package_operations()))), "\n"))' | sort > /tmp/pubops.txt
# compare against the `public=` names printed above; expect ONLY the unexported Base extensions
```

- Triage (drop false positives — universally standard math; the real Julia operators `×`/`⋅`/`≈`; pervasive
  shorthand `L²`/`N³`/`O(N²)`; `#`-comment hits; kwarg names correctly backticked; a subscript index run
  `A_{ij}`; a thin-wrapper math variable in a ``…`` span), then fix EVERY genuine finding in one pass — and
  **fix the class, not the line** (an `ik` letter-product or a stray unbraced fraction is a sample of a
  sweepable class).
- Rebuild: `julia --project=docs docs/make.jl` (both lints + `checkdocs = :exports` + doctests + render) —
  must be clean. The gratuitous-``\,``, upright-differential, and braced-fraction conventions are the
  `notation.md` house set (the fraction one is build-enforced by `lint_notation_variants`).
- Commit + push on `master` (no `[skip ci]`; the docs site must redeploy).

## Report

Report the full matrix: which surfaces × checks were run, the findings (class and count) with fixes, and
what was verified clean — including the `FORMALIZATION.md` coverage (every nontrivial operation has a typed
entry, each test-linked), the **family lane**'s one-home/notation audit of each `f`/`f!` pair, and the
**cold-reader lane**'s pass over the exported docstrings, and **surface 6**'s placement audit of the
built API pages (nothing public under Internal API, nothing rendered twice, nothing public missing, and
every Internal API blurb matching what its block collected). Done only when every cell is covered, every
finding is closed (fixed, or dismissed with its reason), and the build is clean — in ANY cost mode.
