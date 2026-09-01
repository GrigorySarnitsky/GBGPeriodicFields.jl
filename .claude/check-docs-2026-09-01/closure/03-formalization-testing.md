RANGE: ac1226e4..HEAD

## Finding 1
- verdict: HONORED
- evidence: `git diff ac1226e4..HEAD -- docs/FORMALIZATION.md` shows the exact quoted line changed:
  ```
  -changes the values, and — because ``\texttt{Grid3D}`` stores the domain size, spacing and origin at the
  +changes the values, and — because `Grid3D` stores the domain size, spacing and origin at the
  ```
  The bare-identifier `\texttt{}` math span is replaced with a plain backtick code span, exactly the
  fix requested.
- class_surfaces: The finding is a narrow style nit about one specific misuse of `\texttt{}` (wrapping
  a bare code identifier in math delimiters when it names no formula) at `docs/FORMALIZATION.md:748`.
  It does not itself name or imply other surfaces beyond the file it's in — Finding 2 (same rule) is
  the only sibling this finding's own text points to, and it is graded separately below. A
  post-fix sweep of both `docs/FORMALIZATION.md` and `docs/TESTING.md` (`grep -n 'texttt{'`) shows every
  remaining `\texttt{...}` occurrence sits inside an actual equation with an operator (`=`, `+`, α/β,
  etc.) — e.g. `docs/FORMALIZATION.md:481` (`\texttt{mean}(f) = ...`), `:492`, `:532`, `:541`,
  `docs/TESTING.md:586,600,604,627,647` — none is a bare-identifier misuse of the kind flagged here. A
  Python scan of every double-backtick math span in both files confirms no remaining span contains a
  `\texttt{...}` with no accompanying operator. The class (as scoped by this finding, within this
  lane's two surfaces) is swept clean.

## Finding 2
- verdict: HONORED
- evidence: `git diff ac1226e4..HEAD -- docs/TESTING.md` shows the exact quoted line changed:
  ```
  -points), the extensive/intensive relation between ``\texttt{integral}`` and ``\texttt{mean}`` — the one is the other times the base measure — (incl. an anisotropic box), the
  +points), the extensive/intensive relation between `integral` and `mean` — the one is the other times the base measure — (incl. an anisotropic box), the
  ```
  Both bare-identifier `\texttt{}` spans replaced with plain backtick code spans, exactly the fix
  requested.
- class_surfaces: The finding itself explicitly names the surfaces that must NOT be touched — its
  "why" section contrasts this violation with "the correct usages at the same file's lines 586, 600,
  604, 627, 647, where `\texttt{...}` sits inside an actual equation and the wrapping is load-bearing."
  Checked all five: `docs/TESTING.md:586` (`\texttt{inner}(u,u) = ...`), `:600` (`C(0) =
  \texttt{inner}(f,f)`), `:604` (`\texttt{inner} = 0`), `:627` (`b = \texttt{dest}`), `:647`
  (`\texttt{integral} = |\Omega|\cdot\texttt{mean}`) — all five remain unchanged in the diff and all
  five are genuinely in-formula (an operator present in the span), so the fix correctly left them
  alone rather than over-applying the rule. No other bare-identifier `\texttt{}` instance exists
  anywhere in either of this lane's two files (see Finding 1's sweep). The class, exactly as the
  finding itself delimits it, is fully and correctly swept.
