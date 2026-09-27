Status: open, 2026-09-27. Filed by the GBGPeriodicFields session on the owner's ruling of that day
(question 5 of the CLAUDE.md cut): PF keeps its own rule for `\mathbb` and asks whether
`RULE.TEX.MATHBB` should change. No switch is needed meanwhile, since PF writes `\mathbf{1}`, which the
rule already admits.

# `RULE.TEX.MATHBB` recommends `\mathbb{1}` for the identity, which PF recorded as not rendering on KaTeX

## What the rule says

> A blackboard-bold digit is not a set; the identity is written \mathbb{1} only where it means one.

## What PF records

PF's `CLAUDE.md` (a finding of 2026-07-17, carried fleet-wide at the time) says KaTeX's blackboard font
covers only the capitals `A`–`Z` and `k`, so `\mathbb{1}`, like any blackboard digit, falls back to a
plain glyph with the font silently dropped. On that reading the rule's recommended spelling of the
identity does not render as blackboard bold on a Documenter site, which uses KaTeX, and the reader sees
an ordinary `1`. PF writes the identity and the indicator `\mathbf{1}` instead.

This session did not re-verify the rendering today. Please check it against KaTeX's published support
table, or by building a page containing `\mathbb{1}`, before acting on it.

## What would settle it

If KaTeX indeed has no blackboard digits: the rule would recommend `\mathbf{1}` (or `\boldsymbol{1}`)
for the identity, in line with its own concern that a blackboard digit "means nothing to a reader". If
KaTeX renders it: PF's recorded finding is stale, and PF drops its rule for yours.
