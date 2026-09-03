# Lane 03-performance — docs/PERFORMANCE.md

Surface: `docs/PERFORMANCE.md` (2516 lines), all sections, with emphasis on findings (ak), (al), (am)
per the assignment (written in the last 24h, least reviewed). Cross-checked prose quantitative claims
against `benchmark/RESULTS.md` (the regenerated table) wherever a claim purported to describe the
committed archive, and cross-checked cited commit hashes against `git log`.

## Method and what was verified

**1. (ak) — numeric cross-check against `benchmark/RESULTS.md`, full verification.**
Every number in finding (ak)'s two result tables was checked against the current `interpolate!
CatmullRom` / `interpolate! CatmullRom ordered` rows (`benchmark/RESULTS.md` lines 509–540):

- `256^3` `Float64`, 9800X3D (`Enteropia`) unordered t1/t8: table 105.578 ms / 15.229 ms vs prose
  "105.58 ms" / "15.23 ms" — match.
- Ordered t1/t8: table 41.479 ms / 7.416 ms vs prose "41.48 ms" / "7.42 ms" — match.
- RTX 5070 Ti unordered/ordered: table 1.485 ms / 485.405 µs vs prose "1.49 ms" / "0.49 ms",
  ratio 3.06× — match (1.485/0.485 = 3.06).
- 12700K t8 (flagged "still stale"): table unordered 35.651 ms, ordered 45.658 ms, ratio 0.78× vs
  prose "35.65 ms | 45.66 ms | 0.78×" — match.
- RX 7900 XTX (flagged "still stale"): table unordered 1.540 ms, ordered 1.812 ms, ratio 0.85× vs
  prose "1.54 ms | 1.81 ms | 0.85×" — match.

All five rows check out exactly. No discrepancy found between (ak)'s prose and the committed table.

**2. (al) — CUDA 64³ numbers against `benchmark/RESULTS.md`'s GPU 5070TI column, full verification.**
The "new" (post-decision-76) values in (al)'s two 64³ tables were checked against the current `fft`
class rows for the GPU 5070TI column (`benchmark/RESULTS.md` lines 12–104):

- `to_spectral` vector `Float32` 64³: table 30.041 µs vs prose "29.7 us" — match within jitter.
- `to_spectral` vector `Float64` 64³: table 125.131 µs vs prose "126.1 us" — match.
- `to_physical!` vector `Float32`/`Float64` 64³: table 40.310 / 137.522 µs vs prose "40.1 us" /
  "137.6 us" — match.
- `to_physical` (allocating) vector `Float32`/`Float64` 64³: table 45.160 / 145.492 µs vs prose
  "45.0 us" / "145.7 us" — match.
- `to_physical!` scratch vector `Float32`/`Float64` 64³: table 42.261 / 142.071 µs vs prose
  "42.2 us" / "142.0 us" — match.

All eight "new" figures reproduce the committed archive to within normal run-to-run jitter (<1%). No
discrepancy found.

**3. Commit-hash claims in (al), full verification against `git log --oneline`.**
- "`93d9d8da` predates `d5f6814a`" — confirmed (`93d9d8da` at git-log position 160, `d5f6814a` at
  145; lower position = more recent, so `d5f6814a` is newer).
- "`ef70e913`, the last commit before decision 76 and after the probe repair [`d5f6814a`]" —
  confirmed: `ef70e913` sits immediately before `11930624` ("feat: the transform plans carry no
  tensor order (decision 76)") in the log, and after `d5f6814a` (position 95 vs 145).
All cited commit-hash orderings are correct.

**4. A candidate cross-finding numeric tension, investigated and RETRACTED (not a real defect).**
Finding (aj) states "the transfer class median is 0.92–0.95 on all four CPU lanes, the decision-78
wrap walk, with `interpolate! CatmullRom` at 0.35–0.49×", where finding (ad)'s dedicated A/B records
"CPU gather 1.3–2.1×" (i.e. ratio 0.48–0.77 in the same after/before convention) for the same scheme.
These two ranges only barely overlap. Investigated further: (aj) is scoped to `Aiporetne`
(i7-12700K), while (ad)'s table is measured "on an RTX 5070 Ti and a Ryzen 9800X3D" — i.e.
`Enteropia`. They are different hosts, so the two figures are not describing the same measurement and
the apparent tension dissolves; this document elsewhere insists platform optima diverge and CPU
results are never compared cross-host, so this is not a same-platform contradiction. No finding filed.

**5. Formatting sweep of (ak)/(al)/(am), lines 1685–2100: clean.**
- No formula wrapped in single backticks (checked for a backtick span containing digits plus
  `×+/=-`) — none found.
- No `\left`/`\right`, no manual `\;`/`\:` spacing around relations, no `\mathbb{}` on anything but
  `A`–`Z`/`k` — none found in this range.
- Code identifiers inside apparent bare mentions (spot-checked `point_traversal_order`, `visit_order`,
  `displace!`, `wrap!`, `PointSet`) are each inside a backtick span; the one apparent hit from an
  automated grep (`visit_order = point_traversal_order(grid, points)`) turned out to be a single multi-word
  backtick span, a false positive of the search pattern, not a bare identifier.
- Tables are all top-level (not indented inside a list item); no literal `|` inside a math span in
  this range.
- Bare Unicode `×` (rather than `` ``\times`` ``) does appear repeatedly in the prose of (ak)/(al)/(am)
  (e.g. "7.7× at t1 rising to 59× at t8", "scheme × grid × element type"). This is not confined to
  the newest findings — the identical convention (`×` as plain prose punctuation for a speedup
  factor, reserving `` ``\times`` `` for values inside a rendered formula/table cell) is used
  throughout the whole file from finding (a) onward (e.g. "1.6–1.7×" at line 208, "0.75×" at line
  262). Given it is a document-wide, load-bearing, pre-existing stylistic convention rather than
  something introduced in the least-reviewed sections, and not scoped to (ak)/(al)/(am), it is
  recorded here as an observation rather than filed as a finding against this lane's assigned
  surface — flagging it would mean flagging hundreds of instances across the whole document under a
  different lane's remit.

**6. Self-containedness spot-check of (ak)/(al)/(am).** Terms of art used (`gcsample`, canary,
`point_traversal_order`, visit order, `_wrap_step`, the decision-76/78/79 shorthand, `weighted_inner`) are
all introduced earlier in the document (§4(s), §4(ad), the decision cross-references) before their
use in these three findings, consistent with reading the document top-to-bottom. No unbound term
found in this range.

## Result

**No findings survive verification.** Every quantitative claim in (ak) and every 64³ CUDA number in
(al) that could be checked against the committed `benchmark/RESULTS.md` table matches it (within
normal measurement jitter, generally <1%). Cited commit hashes and their relative ordering are
correct against `git log`. No formatting, notation, or self-containedness defect was found in the
(ak)/(al)/(am) range. The document's extensive internal self-correction machinery (it corrects its
own earlier findings in place — e.g. (al) falsifying part of (aj)'s mechanism, (ak) fixing a harness
bug that had corrupted a table row, (am) correcting (ad) to add a scatter-specific corner) appears to
be functioning as intended: the three newest findings are consistent with each other, with the
archive, and with the git history they cite.

This lane did not exhaustively re-verify every numeric ratio in the ~2500-line file (sections (a)
through (ai) were read in full but not each cross-checked against RESULTS.md line-by-line — that
would require reconstructing pre-decision-76/78 archives that are no longer committed). The checks
above targeted the assignment's stated priority (ak/al/am) and the specific instruction to check
quantitative claims against the regenerated table.
