<!-- gbg:managed begin vdev — rewritten by `gbg sync`; do not edit -->
# Citations — `RULE.CIT.*`

Author–year in the prose, the full reference where the reader can reach it, a DOI on every title. 5 rules, written from the rule values themselves,
so a rule reworded here was reworded in the program that checks it.

### RULE.CIT.BLOCK_LIST
References are listed one to a line, never run together with semicolons.

A reader looking for one reference in a semicolon-separated run has to parse the whole paragraph.

Decided by a program.

### RULE.CIT.DOI
Every reference carries a clickable DOI, or an Open Library link for a book, on its title.

A DOI a reader cannot click is a string to retype; one written as a bare label is indistinguishable from prose.

Decided by a program.

### RULE.CIT.FULL_INLINE
A docstring cites author–year in its prose and carries the full reference in a `# References` section, identical to the canonical entry in title and DOI.

A full reference mid-sentence takes the reader's eye out of the sentence, and a hand-copied entry drifts from the one the package keeps.

Decided by a program.
This package may set `references`; unset, it is `docs/ARCHITECTURE.md`.

### RULE.CIT.NO_INACCESSIBLE
Never cite an inaccessible source on any user-facing surface: not a gitignored monograph, an accompanying thesis, an appendix or figure the reader cannot open, nor working notes.

A citation the reader cannot follow is the author telling themselves where they got it; the reader is left with an assertion and nowhere to check it.

Decided by an agent, because this needs meaning.

### RULE.CIT.STYLE
In-text author–year: author-prominent takes a parenthesized year; up to 3 authors are named, 'First et al.' for four or more.

Keep enough surnames to disambiguate two works that would otherwise collide. An eponymous method name takes no year unless the work is actually cited.

Decided by an agent, because this needs meaning.

<!-- gbg:managed end -->
