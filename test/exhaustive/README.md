# The exhaustive survey

The full Cartesian product of PF's operations, arguments and configurations, run occasionally rather
than on every change. `Pkg.test()` is the gate: fast, run always, it pins what is known. This is the
survey: slow, run before a release or after a large change, it looks for what nobody thought to test.
A finding here becomes a gate test once it is fixed.

## Running it

From the root of the repository, on an otherwise idle machine:

```
julia -t4 --project=test          test/exhaustive/runtests.jl     # CPU, plus HDF5 persistence
julia -t4 --project=test/gpu/cuda test/exhaustive/runtests.jl     # CPU and CUDA
julia -t4 --project=test/gpu/rocm test/exhaustive/runtests.jl     # CPU and ROCm
```

- **`-t4` is required.** The thread-invariance checks fire only when more than one thread exists; with
  Julia's default of one, that axis is dead and half the configurations repeat the other half.
- **The environment decides what is reached.** `test/` carries HDF5, so only it reaches the
  persistence operations. A GPU environment adds its device to the universal-checks lane alone; every
  other lane builds host fixtures and runs on the CPU in every environment.
- **It takes about 1.5 hours** on an idle machine. Anything else running inflates it.
- **A device run cannot take the whole product in one process.** Measured on CUDA (2026-10-13): about
  7 minutes and 3.5 GB of host memory per configuration, the memory not returned until the process
  ends, so the 96 configurations need about 16 hours and more memory than a 123 GB host has. On ROCm
  (RX 7900 XTX, 2026-10-18) it is about 16 minutes and up to 18 GB per configuration — a process of
  twelve reached 111 GB — so six per process is the ceiling there, one process at a time. Run it in
  processes selected with `SURVEY_CONFIGURATIONS`, a regular expression on the configuration names
  (`Float32/cubic/fold1/serial/seed815`); unset, every configuration runs. The report states how many
  configurations it ran. The device leg of a threaded configuration is skipped and reported: the
  threading flag only moves the host cutoff, so that leg would repeat the serial one.

## Reading the output

It is a report, not a silenced gate: it prints everything that does not work. Where a failure matches a
recorded decision or contract, the citation is printed beside it, as an explanation, never as a pass.

- **`NO CITATION`** — a new finding; nothing in the package's record explains it.
- **A cited failure** — a known gap; still printed and counted.
- **`NOT REACHED`** — a combination the lane could not build: a hole in the lane, and work to do.
- **`NOT APPLICABLE`** — a combination the package's model does not admit, such as two sections of
  different tensor order sharing storage.
- **`NOT RUN`** — a conditional lane that could not run here, such as a device lane without a device.

Exit code: `0` clean; `1` only quality findings (a cited aliasing case, a type-stability finding, a
method no assertion reaches); `2` a correctness finding, an uncited one, or a problem in the harness
itself, such as a check that did not fire on its own defect.

Two known causes keep the exit code at `2` today, so read the report rather than the status:

- **The `radial_spectrum` value cells on `Float32` anisotropic grids.** A mode whose `|k|/Δk` lands on a
  half-integer falls into one shell or the other depending on rounding, so energy moves between
  adjacent shells while the total agrees exactly. This is a property of the reference's shell-by-shell
  comparison, not of the package.
- **The context-mismatch cells refused by dispatch.** Every mismatched argument is refused, but some
  with a `MethodError` before the call reaches the package's own compatibility checks, and the lane
  counts those as findings. One axis, `length`, has no builder and is reported `NOT REACHED`.

## The lanes

In the order `runtests.jl` runs them:

| lane | file | what it sweeps | oracle |
|---|---|---|---|
| self-check | `selfcheck.jl` | every check below | an operation built to violate it: a check that does not fire is a failure |
| surface coverage | `runtests.jl` | every public operation | is it named by any hand-written lane? |
| universal checks | `invocations.jl`, `checks.jl` | every operation × every buildable call × every configuration × backend | preservation, structural (finite in, finite out), metadata, determinism, type stability |
| properties | `properties.jl` | representation agreement, thread invariance, allocation, ordering, domain rejection | the property itself |
| sequences | `sequences.jl` | plan reuse, repeated application, round-trip cycling, n-step allocation | the property itself, across calls |
| reference cross-validation | `runtests.jl`, `references.jl` | the spectral operators | the independent references, checked before anything uses them |
| relations | `properties.jl`, `ledger.jl` | the declared adjoint, identity and round-trip relations | the relation |
| values | `values.jl`, `references.jl` | every public value-returning operation | an independent reference written from the documented definition |
| storage aliasing | `aliasing.jl` | every in-place operation × every way its arguments can share storage | the same call on fresh, disjoint copies |
| context mismatch | `pools.jl` | every entry point × every quantity its checks compare | a mismatched argument must be refused |
| applicability ledger | `ledger.jl` | every operation × every check type | each cell asserted, or inapplicable by a derived rule |
| per-method ledger | `method_ledger.jl`, `method_reasons.jl` | every (operation, method) pair | an assertion reached the method, or a recorded reason says why none can |

The configurations, crossed in full: element type × four grids (cubic, anisotropic with mixed parity,
the same with a shifted origin, odd on every axis) × the three Fourier layouts × serial or threaded ×
two seeds. They are defined in `configurations()` in `aliasing.jl`. Argument combinations per method
are sampled at a cap of 400, and the number dropped is printed.

## The rules for changing it

Each rule came from a measured failure of an earlier version.

- **Derive every axis from the code; never maintain a list.** The operations come from the method
  table, the context axes from the equality tests in the `_check_*` predicates, the check types from
  `classify_checks.jl`. A cell that claims a derivation must name its mechanism, a function call;
  where a list is unavoidable (the kernel and scheme pools), it is audited against `subtypes`.
- **A contract is declared, and a probe asserts against it.** Never ask the package whether a check
  applies: a defect can make itself look inapplicable and skip the one cell that would expose it.
- **Applicability is a rule read from the operation**: its name, its methods, its lowered IR. Each
  exemption is itself checked; an operation with an in-place form may not be exempt from allocation,
  one reaching an atomic may not be exempt from determinism.
- **Prune by inapplicability, never by sampling.** Where an axis must be sampled, it says so in the
  output.
- **A reference is written from the operation's docstring, over raw arrays, sharing no code with the
  package**, and spectral references rebuild their wavenumbers from the grid.
- **A ledger reason closes exactly one method, keyed by its signature**, and cites the file and line
  where that method's behaviour is asserted. A reason that cannot cite one is not admissible.
- **Every check is tested against a case built to break it**: in `selfcheck.jl`, and for the per-method
  ledger in `selfcheck_method_ledger` in `method_ledger.jl`. A check that cannot fail is
  indistinguishable from one that passes.
- **A predicate or comparison two lanes share is defined once**, in `shared.jl`.

## When PF gains a feature

A new public operation is picked up by the invocation engine automatically, from the method table, and
gets the universal checks. The rest needs a hand:

1. **A value oracle.** Write a `ref_…` function in `references.jl` from the operation's docstring, and
   add a comparison row to the tuple in `run_value_lane` in `values.jl`. A new differential operator
   also joins the cross-validation list in `run_reference_lane` in `runtests.jl`.
2. **A method that returns no value**, such as a printer or a refusal, gets an entry in
   `LEDGER_REASONS` in `method_reasons.jl` instead, keyed by its signature and citing its assertion.
3. **A new kind of argument**, one the pool cannot supply, gets an entry in `canonical_pool` in
   `invocations.jl`. A new kernel class or transfer scheme must be added to its pool; the `subtypes`
   audit reports the omission. A **required keyword** gets an entry in `REQUIRED_KEYWORDS` in the same
   file, because the engine fills only positional slots; one left out is reported by name as an
   `UndefKeywordError` among the lane's own failures, and an entry naming a keyword no method declares
   is reported as stale.
4. **A relation to another operation** (an adjoint, an identity, a round trip) is declared in
   `RELATIONS` in `ledger.jl` and evaluated in `run_relations_lane` in `properties.jl`.
5. **An entry point that validates a context argument** gets a row in the mismatch entries in `pools.jl`,
   with its fiber contract declared, `:one` or `:many`.
6. **An in-place operation** gets a row in `operations_for` in `runtests.jl`, so the aliasing lane
   sweeps it.
7. **New tests in `test/`**: run `julia --project=test test/exhaustive/classify_checks.jl`. An assertion
   it cannot classify is a check type the survey does not cover.

Then run the survey. The per-method ledger should read zero uncovered, and anything it reports
`NOT REACHED` is the next item on this list.

## What it does not catch

- **A defect confined to a GPU kernel**, its CPU twin correct. Only the universal checks cross a
  device, and they assert no value there; device values are checked by `test/gpu/suite.jl`.
- **What a relation cannot see.** The adjoint and idempotence relations hold for any real symbol, so
  they catch an inconsistency between two operations, not a wrong wavenumber; the value lane covers
  that.
- **Calls nobody meant.** The engine builds every call `applicable` allows, which can include a call
  that means something else, such as a field read as `norm`'s exponent.
- **A contract nobody validates.** The domain-rejection cells come from the validation code, so an
  argument that is never validated contributes none.
- **A check type nobody has written**, since the axis is derived from the existing assertions.
- **The completeness invariants** (a banned method stays absent, no type piracy, the naming
  discipline), which belong in the gate so they fail the moment a violation lands.
- **Grid axes of length 1 or 2**, benchmarks, and concurrency between operations.
