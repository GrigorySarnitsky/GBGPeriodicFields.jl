<!-- gbg:managed begin vdev — rewritten by `gbg sync`; do not edit -->
# Documentation and API — `RULE.DOC.*`, `RULE.API.*`

What a docstring and an API page contain, in what order and in what shape. 42 rules, written from the rule values themselves,
so a rule reworded here was reworded in the program that checks it.

### RULE.API.POSITIONAL
A result-affecting argument is positional; a performance hint or a builder cost/accuracy tunable is a keyword; exceptions are recorded.

In an operation, every argument that affects the result is positional, defaults included; an argument that cannot change the result is a keyword. An exception is a ledger deviation with its reason.

Decided by an agent, because this needs meaning.

### RULE.DOC.ADMONITION_TITLE
Every !!! block carries a custom descriptive title (docs.admonition_titles: always, or load-bearing only).

For this package the rule is {{docs.admonition_titles}}: either every `!!!` block carries a custom descriptive title, or a block carrying one load-bearing claim does while a general aside may stay a …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.AI_BANNER
A rationale page and a rendered Literate example carry the provenance banner, verbatim; a script that is never rendered is not a page and carries none.

A banner reworded in one package is a banner a reader learns to skim past in all of them.

Decided by a program.

### RULE.DOC.ALIASING_BULLET
An operation-specific aliasing statement lives in the destination bullet; the package-wide guarantee lives in the module docstring.

The package-wide guarantee lives in the module docstring and is not repeated per operation; an operation states it for itself only when it has an operation-specific reason, or when its contract is …

Decided by an agent, because this needs meaning.

### RULE.DOC.API_GROUPING
One docstring has one home on the built site, and a Base function the package extends is public.

Two homes for one docstring is two things to keep true, and the second teaches a reader nothing.

Decided by a program.

### RULE.DOC.ARGCOV
Every argument in a docstring's signature, positional and keyword, is documented in its body.

A reader passing an argument the docstring never mentions has to read the source to learn what it does.

Decided by a program.

### RULE.DOC.ARGS_FORM
Three or more arguments, or any keyword, use the bulleted form, led by the marker phrase and a colon; fewer are bound in running prose; the two are never mixed.

A reader looking for one argument of many needs a list; a reader of a two-argument call needs a sentence.

Decided by a program.

### RULE.DOC.ARG_BULLET
An argument or field bullet names its argument in a plain code span, never a bold one.

Bold marks emphasis; a name set in bold reads as a heading over the paragraph rather than as the argument.

Decided by a program.

### RULE.DOC.BATTERY
'Check the docs' means the complete battery over every surface, never one check or one file.

When asked to check, review or audit the documentation in any words, run the full matrix — every check across every surface — and report it; do not run one check, sweep one file, and stop.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.BUILD_VERIFY
A doc edit is verified by the full docs build exiting 0, never by a diff, a lint subset or a log grep.

A lint run standalone cannot see a dangling reference, and grepping a log for error text passes a build that died at load. After editing a Literate example, regenerate it and read the output.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: harness:makedocs enforces it inside a package's own test suite

### RULE.DOC.CLASS_SWEEP
A flagged instance is a sample of a class: sweep every surface for the class and fix all in one pass.

Fixing only the pointed-at line and waiting to be handed the next instance is the failure this rule exists to stop. After a class fix, enumerate the surfaces from the finding's own text, not from …

Decided by an agent, because this needs meaning.

### RULE.DOC.COORD_FREE
Maps and pairings are stated intrinsically; matrix/flattening machinery is confined to the formalization doc.

Component notation for a genuine fiber algebra is fine; the rule targets flattening a structured space to a bare vector. Where a basis form is needed to mirror the code, state the basis and the …

Decided by an agent, because this needs meaning.

### RULE.DOC.COVERAGE_BASES
A measure reduction documents every base it supports.

A measure reduction over a grid and the same reduction over a point set are both stated where the operation is documented.

Decided by an agent, because this needs meaning.

### RULE.DOC.CURRENT
No stale claim: a rule cited by id names a rule that exists, and a retired phrasing is not used.

A citation of something renamed or removed reads exactly like one that resolves, which is why it survives.

Decided by a program.

### RULE.DOC.FIELDS
A type with named fields documents them under "The fields are", one bullet per field: every bullet a real field, and every field a bullet.

A field list that has drifted is worse than none: it names what does not exist and hides what does.

Decided by a program.

### RULE.DOC.GRAMMAR
Every sentence has a subject and a verb; concise means few words, not missing verbs.

Concise means few words, not missing verbs — compact prose that still reads as sentences aloud.

Decided by an agent, because this needs meaning.

### RULE.DOC.HOME_ORDER
A function docstring is ordered: identity, when-to-use, arguments, one formula, citation, links, caveats, then `# References`, then `# Fields` last; internals, jargon and rationale are excluded.

In full: (1) a plain one-sentence identity in the user's terms; (2) when to use it, versus the alternatives; (3) each argument (positional and keyword) and its effect; (4) one formula if a clean one …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.INTERNAL_API
An API page puts its internal section last, holds no empty block of collected docstrings, and is never indexed.

Internals in the middle of the public surface, and an index on a hand-grouped page, both make a reader work around the page.

Decided by a program.

### RULE.DOC.LEADING_IDENTITY
Item (1) is a plain one-sentence identity, physical-meaning first or estimand first (rubric.leading_identity).

For this package the identity leads with {{rubric.leading_identity}}: an operation computed in a derived representation still states what it does to the real object first — with the explicit …

Decided by an agent, because this needs meaning.

### RULE.DOC.LINKS
Cross-referencing is discriminating: a target is linked at most once in one docstring, at its first genuine mention.

A second link to the same target is invisible in the rendered text and tells the reader nothing new.

Decided by a program.

### RULE.DOC.LINK_UNIFORMITY
In one run of names, either every name is linked or none is.

A list where one name links and the next does not reads as though the difference meant something.

Decided by a program.

### RULE.DOC.LITERATE
A Literate example is a rendered page: full-line # comments are prose, their math is LaTeX, control-flow-internal comments use ##.

A full-line comment inside a control-flow block splits the code fence, so reserve full-line `# ` for narrative prose at statement boundaries. An underscored identifier in that prose is backticked, …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.MODULE_MAP
A module docstring lists one linked one-liner per operation family and no formula.

Its order is identity, then the contents list, then an optional trailing remark.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.NO_DEAD_REFS
A docstring or error message cites no section number and no inaccessible source; it reads complete at the REPL.

At the REPL there are no links: a section number cannot be followed, and it is renumbered besides.

Decided by a program.

### RULE.DOC.ONE_HOME
One concept, one home: one docstring per operation on the bare binding; the ! form owns the formula and is listed first; every other variant is a thin wrapper that @ref-links the home and carries no second formula.

Per-scheme or per-representation specifics live in the scheme's or the representation's own docstring, linked. Across an `f`/`f!` pair the in-place `!` form is the home — it owns the formula and the …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.ONE_NOTATION
One notation per concept and one concept per notation; a local use yields to a package-wide glyph.

Before introducing a symbol, check it is not a synonym for one already in use, and check the section for the glyph and confirm it is free. When an edit introduces a symbol, retire the old one.

Decided by an agent, because this needs derivation.

### RULE.DOC.REF_ABUT
A cross-reference never abuts a second code span; the whole call is the link text.

The two render as adjacent monospace chips with a seam, as though the name had been cut in half.

Decided by a program.

### RULE.DOC.REGISTER
A tunable is an option, a setting or a keyword argument, never a `knob` or a `tweak`.

The house register is plain and exact; `knob` is neither, and reads as though the value did not matter.

Decided by a program.

### RULE.DOC.RETURNS
A type docstring leads with its constructor; a '-> Type' arrow or a 'Returns x.' sentence states the result where the identity sentence does not.

A mutator whose signature carries no arrow says what it returns in a sentence before any caveat; a signature carries an arrow only where the return type is fixed by the signature; arrow and sentence …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.SELF_CONTAINED
A rationale doc reads top to bottom without another file: every symbol is bound in plain language at first use.

Later uses may be bare; universally standard mathematics may stand unglossed. A decision-log entry browsed on its own meets the same bar.

Decided by an agent, because this needs reading order.

### RULE.DOC.SENTENCE_OPENER
A sentence opens with a capitalised ordinary word, never a lowercase identifier or a formula; bullets, comments, headings and fenced code are exempt.

At a full stop a reader cannot tell a new sentence beginning with a lowercase name from the old one running on.

Decided by a program.

### RULE.DOC.SHAPE
A paragraph of prose stays inside the house cap, an admonition count stays inside its own, and prose that was here before the cap may shrink but never grow.

Prose grows by accretion: each addition is small, nobody rewrites, and the paragraph nobody can read was never written in one sitting.

Decided by a program.

### RULE.DOC.SIBLING_LINK
The first mention of a sibling package links to that package's site; later mentions are bare.

A reader meeting the name for the first time must be able to reach it, and a fourth link teaches nothing.

Decided by a program.
This package may set `sibling_sites`; unset, it is `["GBGPeriodicFields" => "https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/", "GBGIsotropicTurbulence" => "https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl/", "GBGStreamingStatistics" => "https://grigorysarnitsky.github.io/GBGStreamingStatistics.jl/", "GBGCloudPhysics" => "https://grigorysarnitsky.github.io/GBGCloudPhysics.jl/", "GBGCodingTools" => "https://grigorysarnitsky.github.io/GBGCodingTools.jl/"]`.

### RULE.DOC.SIGNATURE_FIDELITY
The signature a docstring displays and the methods the module defines agree, argument for argument.

A displayed signature is what a reader calls; one the method table has moved past is a call that fails.

Decided by a program.

### RULE.DOC.SIGNATURE_MIRROR
A docstring's signature block fits the house column and repeats only as much of the method as a reader needs.

A signature wider than the column wraps in the rendered page and in every terminal that shows it.

Decided by a program.

### RULE.DOC.STEER
Every ! form with an allocating sibling carries the verbatim in-place steer sentence, naming its own destination argument.

The sentence is the template below — a template, not a link: `destination` is replaced by the argument the signature actually has and `f` by the allocating sibling's own name, so the `@ref` resolves …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.TABLE_TOP_LEVEL
A Markdown table is top-level, never indented inside a list item.

Markdown reads an indented block as code, so an indented table renders as the pipes and dashes themselves.

Decided by a program.

### RULE.DOC.TERMS_DEFINED
A term of art is defined in a clause or @ref-linked on first use; the acceptance test is the cold read.

A docstring can bind every symbol and still be unreadable to someone who has not read the module, because its terms of art are nouns, not symbols; parse it with the module's context withheld, and a …

Decided by an agent, because this needs meaning.

### RULE.DOC.TWO_TIER
A module docstring is a map (linked one-liners, no formulas); a function docstring is a home.

The map states what the module is, its scope and place in the architecture, and its invariants — then a linked one-liner per operation family, and no formulas; every formula lives in the operation's …

Decided by an agent, because this needs reading order.

### RULE.DOC.VARIANT_PAIR
Across an f/f! or getter/setter pair the defining math appears once; the wrapper carries no display formula (the review unit is the variant set).

Typed twice, the math drifts — one member writing a partial one way and its twin another — and a within-string check cannot see it; a lane that groups each operation's generics and diffs them can.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.DOC.VERIFIED
Every formula, normalization, adjoint relation and cross-scheme equivalence is verified by expansion against the code, never asserted.

A plausible 'X is just Y' is a false claim until the expansion matches. Run this as a positive verification — enumerate every formula, constant, relation and quantifier and verify each — not as a …

Decided by an agent, because this needs meaning.

### RULE.DOC.XLINK
A name another module owns is linked at its first mention in a docstring, qualified so the link resolves.

A reader meeting a name from elsewhere has nowhere to go: the docstring in front of him does not define it.

Decided by a program.

<!-- gbg:managed end -->
