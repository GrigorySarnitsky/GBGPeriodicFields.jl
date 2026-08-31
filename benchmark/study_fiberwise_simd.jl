# The IT-item-3 STUDY script — not a suite member, and deletable once its question is answered.
#
# Question: does restructuring the fused fiberwise engine's CPU loop pay on the i7-12700K at
# production thread counts, or is that host — like the 9800X3D — already at its memory roof there?
# The 9800X3D answered: wins of 1.16–3.58x at ONE thread, exactly 1.00x at t4/t8 out of cache
# (43–47 GB/s both arms — saturated). The 12700K runs DDR4-2666 (theoretical 42.7 GB/s dual
# channel, ~32–36 practical), and IT measured the engine at 23→30 GB/s from t1→t8 there, i.e.
# ~90% of the practical roof at t8 — so the expectation is CONFIRM SATURATION and close the item
# as measured-and-declined (CLAUDE.md, planned directions, IT item 3). Run:
#
#   julia --startup-file=no -t1 --project=. benchmark/study_fiberwise_simd.jl
#   julia --startup-file=no -t4 --project=. benchmark/study_fiberwise_simd.jl
#   julia --startup-file=no -t8 --project=. benchmark/study_fiberwise_simd.jl
#
# Verdict rule: if hand/simd ≈ 1.0x at t4/t8 out-of-cache (as here), the port is declined for good;
# only a broad t4/t8 win would justify touching the highest-blast-radius engine in the package.
# `bitwise=true` must hold in every row or the variant measures a different formula.
# IT item 3, option 3: the standalone prototype. NO package code is changed; the "PKG" arm IS the
# package call, and the hand arms replicate its exact per-element formulas on the same storage.
#   HAND  = plain @inbounds loop  -> what a restructured engine gets: no closures, no stray bounds
#           checks; the compiler may vectorize behind its own runtime overlap guards (option 1).
#   SIMD  = the same loop under @simd -> the explicit no-overlap promise (option 2's fast lane).
using GBGPeriodicFields, Random, Printf, Statistics
using Base.Threads
const GF = GBGPeriodicFields

# --- hand kernels: linear indexing with component offsets, chunked contiguously over threads ---
function cross_hand!(w, u, v, P)
  @threads :static for c in 1:nthreads()
    lo = 1 + (c - 1) * cld(P, nthreads()); hi = min(P, c * cld(P, nthreads()))
    @inbounds for n in lo:hi
      w[n]         = u[n + P] * v[n + 2P] - u[n + 2P] * v[n + P]
      w[n + P]     = u[n + 2P] * v[n]     - u[n]      * v[n + 2P]
      w[n + 2P]    = u[n]      * v[n + P] - u[n + P]  * v[n]
    end
  end
  return w
end

function cross_simd!(w, u, v, P)
  @threads :static for c in 1:nthreads()
    lo = 1 + (c - 1) * cld(P, nthreads()); hi = min(P, c * cld(P, nthreads()))
    @inbounds @simd for n in lo:hi
      w[n]         = u[n + P] * v[n + 2P] - u[n + 2P] * v[n + P]
      w[n + P]     = u[n + 2P] * v[n]     - u[n]      * v[n + 2P]
      w[n + 2P]    = u[n]      * v[n + P] - u[n + P]  * v[n]
    end
  end
  return w
end

# A_ij u_j with the codegen's left-fold association (a*b + c*d) + e*f
function mul_hand!(w, A, u, P)
  @threads :static for c in 1:nthreads()
    lo = 1 + (c - 1) * cld(P, nthreads()); hi = min(P, c * cld(P, nthreads()))
    @inbounds for n in lo:hi
      u1 = u[n]; u2 = u[n + P]; u3 = u[n + 2P]
      w[n]      = (A[n]      * u1 + A[n + 3P] * u2) + A[n + 6P] * u3
      w[n + P]  = (A[n + P]  * u1 + A[n + 4P] * u2) + A[n + 7P] * u3
      w[n + 2P] = (A[n + 2P] * u1 + A[n + 5P] * u2) + A[n + 8P] * u3
    end
  end
  return w
end

function mul_simd!(w, A, u, P)
  @threads :static for c in 1:nthreads()
    lo = 1 + (c - 1) * cld(P, nthreads()); hi = min(P, c * cld(P, nthreads()))
    @inbounds @simd for n in lo:hi
      u1 = u[n]; u2 = u[n + P]; u3 = u[n + 2P]
      w[n]      = (A[n]      * u1 + A[n + 3P] * u2) + A[n + 6P] * u3
      w[n + P]  = (A[n + P]  * u1 + A[n + 4P] * u2) + A[n + 7P] * u3
      w[n + 2P] = (A[n + 2P] * u1 + A[n + 5P] * u2) + A[n + 8P] * u3
    end
  end
  return w
end

bench(f, n = 7) = (f(); minimum([(t0 = time_ns(); f(); (time_ns() - t0) / 1e9) for _ in 1:n]))

for T in (Float64, Float32), N in (128, 256, 512)
  grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
  Random.seed!(9)
  u = VectorFieldPhysical(rand(T, N, N, N, 3), grid)
  v = VectorFieldPhysical(rand(T, N, N, N, 3), grid)
  A = TensorFieldPhysical{2}(rand(T, N, N, N, 3, 3), grid)
  w = VectorFieldPhysical(zeros(T, N, N, N, 3), grid)
  P = N^3
  ud, vd, Ad, wd = GF.field_data(u), GF.field_data(v), GF.field_data(A), GF.field_data(w)

  # bitwise sanity first: each variant must reproduce the package exactly
  import LinearAlgebra
  GF.cross!(w, u, v); ref = copy(wd)
  cross_hand!(wd, ud, vd, P); h_ok = wd == ref
  cross_simd!(wd, ud, vd, P); s_ok = wd == ref
  GF.mul!(w, A, u); refm = copy(wd)
  mul_hand!(wd, Ad, ud, P); hm_ok = wd == refm
  mul_simd!(wd, Ad, ud, P); sm_ok = wd == refm
  ok = h_ok && s_ok && hm_ok && sm_ok

  tc_pkg  = bench(() -> GF.cross!(w, u, v))
  tc_hand = bench(() -> cross_hand!(wd, ud, vd, P))
  tc_simd = bench(() -> cross_simd!(wd, ud, vd, P))
  tm_pkg  = bench(() -> GF.mul!(w, A, u))
  tm_hand = bench(() -> mul_hand!(wd, Ad, ud, P))
  tm_simd = bench(() -> mul_simd!(wd, Ad, ud, P))
  gb(streams, t) = streams * P * sizeof(T) / t / 1e9
  @printf("%-7s %4d^3 t%-2d bitwise=%s | cross pkg %8.3f hand %8.3f (%.2fx) simd %8.3f (%.2fx) [%5.1f→%5.1f GB/s]\n",
          string(T), N, nthreads(), ok, 1e3tc_pkg, 1e3tc_hand, tc_pkg/tc_hand, 1e3tc_simd, tc_pkg/tc_simd,
          gb(9, tc_pkg), gb(9, tc_simd))
  @printf("%-7s %4d^3 t%-2d            | mul!  pkg %8.3f hand %8.3f (%.2fx) simd %8.3f (%.2fx) [%5.1f→%5.1f GB/s]\n",
          string(T), N, nthreads(), 1e3tm_pkg, 1e3tm_hand, tm_pkg/tm_hand, 1e3tm_simd, tm_pkg/tm_simd,
          gb(15, tm_pkg), gb(15, tm_simd))
end
