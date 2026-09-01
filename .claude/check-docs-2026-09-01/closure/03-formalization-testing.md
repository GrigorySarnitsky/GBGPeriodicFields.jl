RANGE: ac1226e4..HEAD

## Finding 1
- verdict: HONORED
- evidence: `git diff ac1226e4..HEAD -- docs/FORMALIZATION.md` shows at the finding's cited line:
  ```
  -changes the values, and — because ``\texttt{Grid3D}`` stores the domain size, spacing and origin at the
  +changes the values, and — because `Grid3D` stores the domain size, spacing and origin at the
  ```
  This is exactly the fix requested: the bare identifier wrapped in a math span (`` ``\texttt{Grid3D}`` ``)
  was replaced with a plain backtick code span (`` `Grid3D` ``), no math delimiters. Confirmed no
  regression: `grep -n '\\texttt{' docs/FORMALIZATION.md` shows only in-formula uses remain (lines 159,
  170, 178, 316, 338, 405, 473, 481, 492, 532, 541 — all inside actual equations with `=`, α/β, etc.,
  matching the finding's own description of the *correct* usage pattern).
- class_surfaces: The finding is a narrow style nit about ONE specific misuse pattern (a bare code
  identifier with no surrounding math operators, wrapped in a math span via `\texttt{}` for no
  formula-internal reason) at one cited location, `docs/FORMALIZATION.md:748`. The finding's own "why"
  section implicitly names the class (any `\texttt{X}` with no math content in its span) but does not
  name other specific sites — it only contrasts with *correct* in-formula usages elsewhere in the
  corpus (not sites needing the same fix). I swept `docs/FORMALIZATION.md` and `docs/TESTING.md` for
  every remaining `\texttt{...}` occurrence post-fix and found zero bare/no-formula instances left in
  either file — every surviving occurrence sits inside a real equation (`=`, α/β accumulate forms,
  etc.), consistent with the rule's own carve-out. The class is empty after the fix, not merely the
  quoted line.

## Finding 2
- verdict: HONORED
- evidence: `git diff ac1226e4..HEAD -- docs/TESTING.md` at line 585 (finding's cited location):
  ```
  -points), the extensive/intensive relation between ``\texttt{integral}`` and ``\texttt{mean}`` — the one is the other times the base measure — (incl. an anisotropic box), the
  +points), the extensive/intensive relation between `integral` and `mean` — the one is the other times the base measure — (incl. an anisotropic box), the
  ```
  Exactly the requested fix: both bare identifiers replaced with plain backtick spans, math
  delimiters removed. The finding explicitly contrasted this site against "correct usages at the same
  file's lines 586, 600, 604, 627, 647" (all in-formula) — those were NOT touched by the diff, which is
  correct, since the finding itself says those are fine as-is.
- class_surfaces: Same class as Finding 1 (bare `\texttt{}` with no formula content), one cited site
  `docs/TESTING.md:585`. Verified via the same post-fix grep of `docs/TESTING.md` (line 586, 600, 604,
  627, 647 all still `\texttt{}`-wrapped but all in-formula, exactly the finding's own "correct usage"
  list, left untouched as they should be). No other bare-wrapped instance remains in either of this
  lane's two surfaces. The class is swept, not just the one line.
