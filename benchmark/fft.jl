# FFT transform benchmarks: allocating to_spectral / to_physical (the user-facing forms; they copy,
# so they are reusable across evals — invariant 11). Scalar and vector orders. On the CPU every row
# has a `measure` twin planned with `FFTW.MEASURE` — the timed plan search the FieldTransformPlans
# docstring recommends for long CPU runs — so RESULTS.md carries the default-planner (`ESTIMATE`)
# experience and the tuned production path side by side, and their delta per host/size/type
# (PERFORMANCE.md finding (h), the Zen 5 Float32 mis-planning) is a standing measurement instead of
# a one-off finding. GPU rows have no twin: the device FFT libraries take no planner flag.

function add_fft!(group, AT, ::Type{T}, grid, tag) where {T}
  for (label, mk) in (("scalar", scalar_phys), ("vector", vector_phys))
    phys = mk(AT, T, grid)
    plans = plans_for(phys, AT, T, grid)
    spec = to_spectral(phys, plans)
    group["to_spectral $label | $tag"] = @benchmarkable (s = to_spectral($phys, $plans); bench_sync(field_data(s)))
    group["to_physical $label | $tag"] = @benchmarkable (p = to_physical($spec, $plans); bench_sync(field_data(p)))
    # The preserving scratch arity (decision 64): the same inverse transform, allocation-free, plus
    # one explicit copy of the coefficients. Its delta against the in-place row below IS the price of
    # preservation; its delta against the allocating row above is the allocation and the copy the
    # allocating form performs internally.
    scratch = similar_field(spec, Val(field_tensor_order(spec)))
    out_phys = similar_field(phys, Val(field_tensor_order(phys)))
    group["to_physical! $label scratch | $tag"] =
      @benchmarkable (to_physical!($out_phys, $spec, $plans, $scratch); bench_sync(field_data($out_phys)))
    # And the destructive 3-arg baseline it is priced against. Its "source" is the scratch field, NOT
    # `spec` — this row must not consume the coefficients the other rows in this group reuse.
    group["to_physical! $label | $tag"] =
      @benchmarkable (to_physical!($out_phys, $scratch, $plans); bench_sync(field_data($out_phys)))
    if AT === Array
      mplans = measure_plans_for(phys, T, grid)
      group["to_spectral $label measure | $tag"] = @benchmarkable (s = to_spectral($phys, $mplans); bench_sync(field_data(s)))
      group["to_physical $label measure | $tag"] = @benchmarkable (p = to_physical($spec, $mplans); bench_sync(field_data(p)))
    end
  end
end

# CPU twin of plans_for, planned with FFTW.MEASURE. MEASURE overwrites the arrays it plans on, so
# the plans are built on dedicated scratch fields and then applied to the benchmark fields (a plan
# binds to shape/type/alignment, not to the arrays it was planned on — the package's own
# FieldTransformPlans reuse works the same way).
function measure_plans_for(phys, ::Type{T}, grid) where {T}
  R = field_tensor_order(phys)
  scratch_phys = R == 0 ? scalar_phys(Array, T, grid) : vector_phys(Array, T, grid)
  scratch_spec = R == 0 ? scalar_spec(Array, T, grid) : vector_spec(Array, T, grid)
  return FieldTransformPlans(scratch_phys, scratch_spec; fft_flags = FFTW.MEASURE)
end
