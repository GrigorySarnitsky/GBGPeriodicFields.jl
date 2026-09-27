Status: open, 2026-09-27. Filed by the GBGPeriodicFields session during the rc.23 → rc.30 upgrade.
PF carries a stopgap switch of `RULE.DOC.SIGNATURE_FIDELITY` for `src/Fields.jl` alone, whose reason
cites this file; it comes out, and this file is deleted, when the checker reads a signature block past
a blank line.

# `RULE.DOC.SIGNATURE_FIDELITY` reads only a docstring's first signature when signatures are separated by a blank line

## What happens

At rc.30 the docs build reports three findings in PF that are not defects:

    RULE.DOC.SIGNATURE_FIDELITY  src/Fields.jl:122  [Grid3D]  Grid3D: the defined keyword `origin` appears in no displayed signature
    RULE.DOC.SIGNATURE_FIDELITY  src/Fields.jl:408  [ScalarFieldPhysical]  ScalarFieldPhysical: the defined keyword `array_type` appears in no displayed signature
    RULE.DOC.SIGNATURE_FIDELITY  src/Fields.jl:550  [VectorFieldPhysical]  VectorFieldPhysical: the defined keyword `array_type` appears in no displayed signature

Each docstring does display the keyword. `Grid3D`'s shows two signatures, separated by a blank line,
and the second is the one with the keyword:

    """
        Grid3D(
          grid_size::NTuple{3, Int},
          domain_size::NTuple{3, T},
          grid_spacing::NTuple{3, T},
          origin::NTuple{3, T},
        ) where {T<:AbstractFloat}

        Grid3D(
          grid_size::NTuple{3, Int},
          domain_size::NTuple{3, T};
          origin::NTuple{3, T} = (zero(T), zero(T), zero(T)),
        ) where {T<:AbstractFloat}

    …

The two field constructors show four signatures each in the same way, `array_type` in the third.

## Why

`displayed_signatures` in `src/Rules/modules.jl` takes a docstring's signature block as

    header = collect(Iterators.takewhile(l -> startswith(l, "    "), split(d.text, '\n')))

A blank line does not start with four spaces, so the block ends at the first blank line and every
signature after it is never parsed.

## It errs in both directions

- **False positives**, as above: a keyword shown only in a later signature reads as shown nowhere.
- **False negatives**, which nothing reports: a positional name or a keyword shown in a later
  signature is never compared with the methods, so a stale name there passes. In PF this covers every
  docstring that separates its signatures with blank lines.

## Reproduction

At PF's head with rc.30 pinned, before the stopgap switch: `julia --project=docs docs/make.jl` reports
the three findings above. `gbg check` alone does not show them, since it does not run this rule
("NOT RUN HERE"). Joining the signatures of one of these docstrings without the blank line makes its
finding disappear.

## What would fix it

Read the signature block as every leading line that is either indented four spaces or blank, up to
the first non-blank line that is not indented — so a blank line between two indented signatures does
not end the block. The same `takewhile` may be used by other rules that read a docstring's signature
block (`RULE.DOC.ARGCOV` reads signatures too); they would share the defect.

## What PF did meanwhile

Nothing in the three docstrings was changed: they are correct, and a blank line between multi-line
signatures is how PF lays them out for reading. The rule is switched off for `src/Fields.jl` only, the
one file where it reported this, so every other file stays checked.
