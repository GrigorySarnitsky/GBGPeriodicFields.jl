# Manual CPU-threading benchmark (NOT part of Pkg.test). Run at a chosen thread count:
#
#   julia -t1 --project=. bench/threading.jl
#   julia -t8 --project=. bench/threading.jl
#
# Reports serial-vs-threaded wall time for a few representative in-place operations at
# several grid sizes, using the `with_threading` override so both run in the same process.
# (FFTs thread separately via FFTW, fixed at the load-time `Threads.nthreads()` — to see
# their scaling, run this script at different `-t`.)

using GBGPeriodicFields
const F = GBGPeriodicFields.Fields

# minimum over a few samples, after a warmup/compile call
best(f; samples = 5) = (f(); minimum(@elapsed(f()) for _ in 1:samples))

function scalar_plans(grid)
  shape = F.spectral_field_shape(grid, RealFourierLayout(), Val(0))
  return FieldTransformPlans(ScalarFieldPhysical(zeros(grid.grid_size...), grid),
                             ScalarFieldSpectral(zeros(ComplexF64, shape), grid))
end

println("Julia threads = ", Threads.nthreads(), "   (cutoff = ", threading_cutoff(), ")")
println(rpad("operation", 26), rpad("grid", 9), rpad("serial ms", 12), rpad("threaded ms", 13), "speedup")
println("-"^66)

for N in (64, 128, 192)
  grid = Grid3D((N, N, N), (2π, 2π, 2π))
  a = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y), grid)
  b = ScalarFieldPhysical((x, y, z) -> cos(z), grid)
  dest = ScalarFieldPhysical(zeros(N, N, N), grid)
  u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
  A = TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], grid)
  wdest = VectorFieldPhysical(zeros(N, N, N, 3), grid)
  plans = scalar_plans(grid)
  as = to_spectral(a, plans)
  m = FieldSpectralMultipliers(as)
  ldest = F.similar_field(as, Val(0))

  operations = (
    ("add!(d, a, b)",          () -> add!(dest, a, b)),
    ("mul!(w, A, u)",          () -> mul!(wdest, A, u)),
    ("laplacian!(l, as, m)",   () -> laplacian!(ldest, as, m)),
  )

  for (name, operation) in operations
    serial   = best(() -> with_threading(enabled = false) do; operation() end)
    threaded = best(() -> with_threading(enabled = true) do; operation() end)
    println(rpad(name, 26), rpad("$(N)³", 9),
            rpad(round(serial * 1e3; digits = 3), 12),
            rpad(round(threaded * 1e3; digits = 3), 13),
            round(serial / threaded; digits = 2), "x")
  end
end
