<!-- gbg:managed begin v2.0.0-rc.5 — rewritten by `gbg sync`; do not edit -->
# Glossary

The terms the rules use. A rule may use any of these without defining it; a term not here is defined
where it is used, or it is not a term of art.

- **consumer** — a package that pins this one and receives its wiring.
- **rule** — one statement with one check and the examples that show the check matches it. Its id is
  `RULE.<FAMILY>.<NAME>`, stable for the life of the rule.
- **check** — what decides that a rule was broken: a program, or an agent where no program can.
- **clause** — one requirement of a statement. A rule with three clauses owes three breaking examples
  and three complying ones.
- **switch** — a package turning a rule off, wholly or for named files, with its reason. It replaces
  the exemption ledger: there is no expiry and no ceremony, only a reason a reader can weigh.
- **file set** — which of a package's files a rule runs over: docstrings, code, pages, rationale,
  Literate examples, tests.
- **finding** — one violation at one location, with the rule that found it.
- **location** — where a finding is: the file, the node (a binding, or a heading path), the quote as
  it read then, and the line as a hint only.
- **generated file** — a file written by a Julia function of this package. Editing one by hand is
  drift, which the wiring check reports and `gbg sync` repairs.
- **pin** — the one version of this package a consumer uses, named in its sub-environments.
- **intention** — whether a change or a finding is in documentation or in code. Documentation is safe
  to fix without asking; code is not.
<!-- gbg:managed end -->
