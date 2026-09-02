#!/usr/bin/env bash
# The deterministic half of /check-docs, as a program rather than a page of commands to retype.
#
# WHY THIS EXISTS. The battery was documented in check-docs.md and run BY HAND, and PF has measured
# what that costs: on 2026-08-04 the sentence-opener scan was run with `| head -5`, reported five
# hits, and there were THIRTY-ONE; the same day the ScalarFieldSpectral sweep showed ten of twenty.
# A deterministic check that depends on who types it is not deterministic. IT reached the same
# conclusion from the same kind of incident and extracted its battery first; this is PF doing the
# same postmortem, not PF adopting IT's scripts — the checks below are PF's own, from PF's own page.
#
# THE ONE RULE THIS SCRIPT ENFORCES STRUCTURALLY: it never truncates. Every scan reports its full
# count and its complete output. There is no `head` anywhere in this file and adding one would
# reintroduce the exact defect it was written for.
#
#   Usage:  .claude/commands/check-docs/guards.sh [repo-root]
#   Exit:   0  every must-be-empty scan clean
#           1  at least one must-be-empty scan has hits (triage findings never fail the run)
set -uo pipefail
cd "${1:-$(git rev-parse --show-toplevel)}" || exit 2

DOCS_MD=(docs/ARCHITECTURE.md docs/FORMALIZATION.md docs/TESTING.md docs/PERFORMANCE.md
         docs/src/notation.md docs/src/index.md docs/src/tutorial.md docs/src/api.md)
for f in docs/src/api/*.md examples/HIST_CPU.jl examples/gpu/*/*.jl; do [ -e "$f" ] && DOCS_MD+=("$f"); done

fail=0
hard() {  # a scan that MUST come back empty
  local name="$1"; shift
  local out; out="$("$@" 2>/dev/null)"
  local n; n=$(printf '%s' "$out" | grep -c . || true)
  if [ "$n" -gt 0 ]; then
    printf '  FAIL  %-34s %4d hit(s)\n' "$name" "$n"; printf '%s\n' "$out" | sed 's/^/          /'
    fail=1
  else
    printf '  ok    %-34s\n' "$name"
  fi
}
soft() {  # a heuristic: real signal mixed with false positives, read it, never fails the run
  local name="$1"; shift
  local out; out="$("$@" 2>/dev/null)"
  local n; n=$(printf '%s' "$out" | grep -c . || true)
  printf '  %4d  %s\n' "$n" "$name"
  [ "$n" -gt 0 ] && printf '%s\n' "$out" | sed 's/^/          /'
  return 0
}

echo "=== MUST BE EMPTY ==="
hard "indented markdown table"        grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs
hard "neutral register (knob/tweak)"  grep -rniE '\b(knobs?|tweaks?)\b' docs src examples
hard "bare-index partial"             grep -rnE '\\partial_[ijk]' src "${DOCS_MD[@]}"
hard "gratuitous thin space (src)"    grep -rnP '\\\\,(?!\\\\mathrm\{d\})' src
hard "gratuitous thin space (docs)"   grep -rnP '\\,(?!\\mathrm\{d\})' "${DOCS_MD[@]}"
hard "unbraced fraction (src)"        grep -rnP '\\\\[dt]?frac[0-9]' src
hard "unbraced fraction (docs)"       grep -rnP '\\[dt]?frac[0-9]' "${DOCS_MD[@]}"
hard "\\! before \\bigl (src)"          grep -rnP '\\\\!\\\\[bB]ig[lr]' src
hard "\\! before \\bigl (docs)"         grep -rnP '\\!\\[bB]ig[lr]' "${DOCS_MD[@]}"
hard "double negative thin (src)"     grep -rnP '\\\\!\\\\!' src
hard "double negative thin (docs)"    grep -rnP '\\!\\!' "${DOCS_MD[@]}"
hard "\\mathbb on a digit (src)"       grep -rnP '\\\\mathbb\s*\{?\s*[0-9]' src
hard "\\mathbb on a digit (docs)"      grep -rnP '\\mathbb\s*\{?\s*[0-9]' "${DOCS_MD[@]}"
# A `@ref` link immediately followed by a code span renders as two adjacent monospace chips with a
# visible seam. PF documents the rule and had no check for it; there are currently zero violations,
# which is the moment to add the guard rather than after one lands.
hard "@ref abutting a code span"      grep -rnoE '\]\(@ref[^)]*\)`' src docs/ARCHITECTURE.md docs/FORMALIZATION.md docs/TESTING.md docs/PERFORMANCE.md

echo
echo "=== TRIAGE (heuristics — read every line; a count is not a verdict) ==="
# The documented form of this scan filters `#` comment lines — CLAUDE.md exempts code comments from
# the math rules, since they are not rendered. Dropping that filter on extraction produced three
# false positives on the first run; the filter is part of the check, not decoration.
soft "formula in backticks"           bash -c "grep -rnE '\`[^\`]*[≤≥≠∈∉∇Δ⟨⟩‖√][^\`]*\`' src ${DOCS_MD[*]} | grep -vE ':[0-9]+:[[:space:]]*#'"
soft "stray TeX \$…\$"                 grep -rnE '\$[^$]*[\\_^{}][^$]*\$' "${DOCS_MD[@]}"
soft "\\left/\\right (src)"             grep -rnP '\\\\(left|right)(?![a-zA-Z])' src
soft "\\left/\\right (docs)"            grep -rnP '\\(left|right)(?![a-zA-Z])' "${DOCS_MD[@]}"
soft "manual \;/\\: spacing (src)"     grep -rnP '\\\\[;:]' src
soft "crammed citation block"          grep -rnzoE 'Reference[s]?:[^"]*;' src
soft "dead §-ref in a docstring"       bash -c "grep -rnE '§[0-9]|docs/(src|ARCHITECTURE|FORMALIZATION|TESTING|PERFORMANCE)|ARCHITECTURE\.md|inspiration/' src/*.jl | grep -vE ':[0-9]+:[[:space:]]*#'"
# NARROWED TWICE, so it is a script now. This was `grep -E '\. (`[a-z]|``)'`, which needs the period,
# the space and the opener on ONE line. Prose here is hard-wrapped and full of paragraph breaks, so the
# two commonest shapes were structurally invisible: an opener starting a line whose PREVIOUS line ended
# the sentence, and an opener starting a paragraph. On 2026-09-02 the grep reported 0 while nine were
# live, one of them in a docstring on the rendered API site, found by the user reading the page.
#
# That is the second narrowing of this same scan — a 2026-09-01 fix (kept in the file's history) had
# it scanning `src/` while its spec said `src/` and the doc pages, and it reported the class clean over
# surfaces it had never opened. Twice now the failure was coverage, not severity, and both times the
# "ok" was believed. A sentence start is therefore COMPUTED rather than pattern-matched, and the rule's
# own exemptions (bullets and their wrapped continuations, `#` comments, headings, fenced code,
# abbreviations, the ``\checkmark`` marker) live in the script beside their reasons.
soft "sentence opens with code/math"   python3 .claude/commands/check-docs/sentence_openers.py

soft "wide docstring signature (>88)"  awk '/^"""/{d=!d;s=d;next} s&&/^[^ ]/{s=0} s&&/^    [A-Za-z_].*\(/&&length>88{print FILENAME":"FNR}' src/GBGPeriodicFields.jl src/Fields.jl src/FieldAlgebra.jl src/FiberSections.jl src/DifferentialOperators.jl src/Convolution.jl src/Points.jl src/Interpolation.jl src/Reductions.jl

echo
if [ "$fail" -eq 0 ]; then echo "GUARDS: every must-be-empty scan clean."; else echo "GUARDS: FAILED — see the FAIL lines above."; fi
exit $fail
