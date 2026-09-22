<!-- gbg:managed begin v2.0.0-rc.7 — rewritten by `gbg sync`; do not edit -->
# LaTeX idiom — `RULE.TEX.*`

What renders, and how mathematics is written so that it renders the same way everywhere. 18 rules, written from the rule values themselves,
so a rule reworded here was reworded in the program that checks it.

### RULE.TEX.BOLDSYMBOL_BRACED
A bold symbol braces its argument.

Unbraced, it bolds the next character alone and leaves the rest of the name upright.

Covered by a program.

### RULE.TEX.CODE_IN_MATH
A code identifier never sits inside a math span; inside a formula it is written \texttt{…}.

The renderer sets a run of letters in a math span as a product of italic single letters, not as a name. That remedy is for a name taking part in a formula which says more than the name itself: where the formula only names what the code denotes, the name stays a code span and a connective joins the two (`RULE.TEX.ONE_SPAN`).

Covered by a program.

### RULE.TEX.CODE_SPAN_JULIA
A backtick span holds only well-formed Julia, never code-looking math.

A half-open interval, an inequality, a product, a lone `≤` or `·` glyph is LaTeX; the real operators `×`, `⋅` and `≈` backticked are code and stay.

Covered by a reader given nothing.

### RULE.TEX.FRAC_BRACED
Both arguments of a fraction are braced.

An unbraced fraction takes one character as its numerator and silently drops the rest.

Covered by a program.

### RULE.TEX.GREEK_AB
The accumulation scalars are written as Unicode α and β wherever they appear. Two ASCII spellings stay, both named in this rule's `why`: a flag whose name carries the α/β variant, and an external window-shape parameter `beta` inside an English-register block.

A hand-written operation spelling them `alpha`/`beta` is drift; a flag naming the α/β variant and an external window-shape `beta` in an English-register block are the recorded exceptions.

Covered by a reader given other documents.

### RULE.TEX.IMAGINARY
The imaginary unit is upright \mathrm{i}; i, j, k are indices.

Never a bare italic `i`, never `\imath` or `\mathbb{i}`; the differential is likewise upright, `\,\mathrm{d}x`.

Covered by a reader given nothing, because this needs derivation.

### RULE.TEX.INLINE_ONE_LINE
An inline math span opens and closes on one line, never across a list or blockquote marker.

A marker inside an open span lands in the formula, and the prose after it renders as mathematics.

Covered by a program.

### RULE.TEX.LEFTRIGHT
A sized delimiter names what it sizes: \left( pairs with \right), and neither stands alone.

An unpaired sizing command is a LaTeX error, and the whole formula fails to render.

Covered by a program.

### RULE.TEX.MATHBB
A blackboard-bold digit is not a set; the identity is written \mathbb{1} only where it means one.

A blackboard digit renders as an outline numeral, which means nothing to a reader of mathematics.

Covered by a program.

### RULE.TEX.MATHBF
Bold is admitted only for the strings a package lists, plus the identity, which every package is granted.

Bold means one thing in one package and another in the next; unlisted, it is a reader's guess.

Covered by a program.
This package may set `mathbf_allowed`; unset, it is `String[]`.

### RULE.TEX.NO_HSCROLL
No horizontal scroll: hand-wrap long signatures and display formulas with aligned/gathered.

Neither a rendered code block nor display math auto-wraps; inline math reflows and is exempt. Never pack several equations on one line behind `\quad`.

Covered by a reader given rendered.

### RULE.TEX.ONE_SPAN
A code span and a math span are never set against each other where the formula continues into or out of the name: where it says more than the name — a definition, or a symbol and then its definition — the name goes inside it as \texttt{…}, and where it only names what the code denotes, a connective joins the two. A formula finished at the edge the name sits on is not continued by it and is left as it is.

Abutting spans render as two disjoint runs at different sizes, leaving the reader to guess whether the second continues the first, qualifies it, or defines it. Apposition says which: `atol` (``\varepsilon``) keeps the name styled as code — clickable, and the same as every other name on the page — while `\texttt{atol}` is the math renderer's monospace, and a link wrapped round the whole formula makes its every operator a link to the name.

Covered by a program.

### RULE.TEX.PARTIAL
A partial derivative names its index as a symbol, not as a bare letter subscript.

A bare index reads as a variable named i rather than as the direction differentiated in.

Covered by a program.

### RULE.TEX.RENDERED_MARKUP
No markup shows on the built page as literal characters.

Asterisks meant to set emphasis, shown as asterisks, are the mark of prose nobody read after building.

Covered by a program.

### RULE.TEX.RENDERED_MATH
Mathematics is written in a double-backtick span: never between dollar signs, and never inside a code span.

Dollars render as literal text and a code span renders as monospace; neither comes out as mathematics.

Covered by a program.

### RULE.TEX.RENDERED_MATH_SITE
On the built page, every math span has rendered: none still shows its own markup.

A span that renders as its own source is a formula the reader never sees, and the source looks right.

Covered by a program.

### RULE.TEX.SPACING
Spacing inside a formula is the renderer's: no thin space, no medium or thick space, no negative thin space before a sized delimiter, and none of them doubled.

Hand spacing is tuned to one renderer at one font size and is wrong in every other setting.

Covered by a program.

### RULE.TEX.SWALLOWED_ESCAPE
Inside a Julia docstring every LaTeX backslash is doubled; a single-backslash escape is swallowed by the parser.

Julia consumes the escape when it reads the string, so the formula never reaches the documentation build at all.

Covered by a program.

<!-- gbg:managed end -->
