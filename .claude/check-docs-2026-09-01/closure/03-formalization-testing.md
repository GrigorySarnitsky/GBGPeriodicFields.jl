RANGE: ac1226e4..HEAD

## Finding 1
- verdict: HONORED
- evidence: `git diff ac1226e4..HEAD -- docs/FORMALIZATION.md` shows the exact hunk:
  ```
  -changes the values, and — because ``\texttt{Grid3D}`` stores the domain size, spacing and origin at the
  +changes the values, and — because `Grid3D` stores the domain size, spacing and origin at the
  ```
  This is precisely the fix the finding requested: replace the math-mode `\texttt{Grid3D}` with a
  plain backtick code span. Confirmed no residual bare `\texttt{Grid3D}` (or any other bare, non-formula
  `\texttt{...}` instance) remains: `grep -n 'texttt{' docs/FORMALIZATION.md docs/TESTING.md` now shows
  every remaining `\texttt{...}` instance sitting inside a real formula with math operators (`=`, `·`,
  `α`, `β`, e.g. `docs/FORMALIZATION.md:159,170,178,316,338,405,473,481,492,532,541`), matching exactly
  the "correct usages" class the finding itself contrasted against (its own examples at
  `docs/TESTING.md:586,600,604,627,647`). No other instance of this misuse exists in either surface.
- class_surfaces: The finding names one class — a bare code identifier wrapped in a math-mode
  `\texttt{}` span with no surrounding formula content, contrasted explicitly against the
  "correct" in-formula usages at `docs/TESTING.md:586`, `600`, `604`, `627`, `647` (which the finding
  says should NOT be touched, being load-bearing). The finding's scope is the two files this lane
  covers (`docs/FORMALIZATION.md`, `docs/TESTING.md`); Finding 2 covers the sibling instance in
  `docs/TESTING.md`. A post-fix grep of both files for `texttt{` (see evidence) confirms zero
  remaining bare, non-formula instances — the class was fully swept across both surfaces the finding
  could reach, and the correctly-in-formula lines were left untouched as the finding itself required.

## Finding 2
- verdict: HONORED
- evidence: `git diff ac1226e4..HEAD -- docs/TESTING.md` shows the exact hunk:
  ```
  -points), the extensive/intensive relation between ``\texttt{integral}`` and ``\texttt{mean}`` — the one is the other times the base measure — (incl. an anisotropic box), the
  +points), the extensive/intensive relation between `integral` and `mean` — the one is the other times the base measure — (incl. an anisotropic box), the
  ```
  This is exactly the fix requested: both bare identifiers converted from math-mode `\texttt{}` spans
  to plain backtick code spans. Post-fix grep (see Finding 1's evidence) confirms no other bare,
  non-formula `\texttt{integral}`/`\texttt{mean}` instance remains in either file; the only surviving
  `\texttt{integral}`/`\texttt{mean}` occurrences are inside real formulas (`docs/FORMALIZATION.md:473,
  481,532,541`; `docs/TESTING.md:647`'s `\texttt{integral} = |\Omega|\cdot\texttt{mean}`), which are
  the legitimate in-formula class the finding explicitly did not ask to change.
- class_surfaces: Same class as Finding 1 (bare-identifier-in-math-mode misuse), this instance in
  `docs/TESTING.md:585` (`integral`/`mean`). The finding names the contrast set at `docs/FORMALIZATION.md:473`
  (the real display formula for the same relation) and the correct in-formula usages at
  `docs/TESTING.md:586,600,604,627,647` — none of which the finding asks to be touched. Grep confirms
  those are untouched and still correctly in math mode, and no other bare instance of `integral`/`mean`
  in math mode remains anywhere in the two files this lane covers.
