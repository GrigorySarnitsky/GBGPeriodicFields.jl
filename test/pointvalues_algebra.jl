# Behaviour tests for the PointValues algebra (Points module): the full M2 + M3 surface,
# mirroring the fields' physical algebra, checked against an independent array / per-point
# reference across Float64 and Float32. The data types are tested in interpolation.jl and the
# method-set is locked in method_parity.jl; here we check the numbers.

using Test
using GBGPeriodicFields

# Per-point references in plain Base (no LinearAlgebra / StaticArrays dependency).
crossref(u, v) = [u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1]]
matvec(A, u) = [sum(A[i, j] * u[j] for j in 1:3) for i in 1:3]
vecmat(u, A) = [sum(u[j] * A[j, i] for j in 1:3) for i in 1:3]
matmat(A, B) = [sum(A[i, k] * B[k, j] for k in 1:3) for i in 1:3, j in 1:3]

@testset "PointValues algebra" begin
  for T in (Float64, Float32)
    M = 6
    sv = ScalarPointValues(rand(T, M) .+ T(1)); sv2 = ScalarPointValues(rand(T, M))
    vv = VectorPointValues(rand(T, M, 3));      vv2 = VectorPointValues(rand(T, M, 3))
    tv = TensorPointValues(rand(T, M, 3, 3));   tv2 = TensorPointValues(rand(T, M, 3, 3))
    a = FiberVector{T}(rand(T, 3)...); Af = FiberTensor2{T}(rand(T, 9)...)
    ds, ds2 = point_values(sv), point_values(sv2)
    dv, dv2 = point_values(vv), point_values(vv2)
    dt, dt2 = point_values(tv), point_values(tv2)
    ra = reshape(collect(a), 1, 3); rA = reshape(collect(Af), 1, 3, 3)

    @testset "vector space + scaling ($T)" begin
      @test point_values(vv + vv2) ≈ dv .+ dv2
      @test point_values(vv - vv2) ≈ dv .- dv2
      @test point_values(vv + vv2 + vv) ≈ dv .+ dv2 .+ dv
      @test point_values(-tv) ≈ .-(dt)
      @test (+sv) === sv
      @test point_values(T(2) * vv) ≈ T(2) .* dv
      @test point_values(vv / T(2)) ≈ dv ./ T(2)
      @test point_values(sv + T(3)) ≈ ds .+ T(3)
      @test point_values(T(3) - sv) ≈ T(3) .- ds
      out = VectorPointValues(zeros(T, M, 3))
      add!(out, vv, vv2);     @test point_values(out) ≈ dv .+ dv2
      subtract!(out, vv, vv2); @test point_values(out) ≈ dv .- dv2
      multiply!(out, T(2), vv); @test point_values(out) ≈ T(2) .* dv
      divide!(out, vv, T(2));   @test point_values(out) ≈ dv ./ T(2)
    end

    @testset "± fiber, scalar-field products & division ($T)" begin
      @test point_values(vv + a) ≈ dv .+ ra
      @test point_values(a - vv) ≈ ra .- dv
      @test point_values(tv + Af) ≈ dt .+ rA
      @test point_values(Af - tv) ≈ rA .- dt
      @test point_values(sv * a) ≈ ds .* ra
      @test point_values(a * sv) ≈ ds .* ra
      @test point_values(sv * Af) ≈ ds .* rA
      @test point_values(sv * vv) ≈ ds .* dv
      @test point_values(vv * sv) ≈ ds .* dv
      @test point_values(sv * tv) ≈ ds .* dt
      @test point_values(sv * sv2) ≈ ds .* ds2
      @test point_values(vv / sv) ≈ dv ./ ds
      @test point_values(a / sv) ≈ ra ./ ds
      @test point_values(T(2) / sv) ≈ T(2) ./ ds
    end

    @testset "dot / cross / mul! ($T)" begin
      @test point_values(dot(vv, vv2)) ≈ [sum(dv[m, i] * dv2[m, i] for i in 1:3) for m in 1:M]
      @test point_values(vv ⋅ vv2) ≈ point_values(dot(vv, vv2))
      @test point_values(dot(vv, a)) ≈ [sum(dv[m, i] * a[i] for i in 1:3) for m in 1:M]
      @test point_values(dot(tv, tv2)) ≈ [sum(dt[m, :, :] .* dt2[m, :, :]) for m in 1:M]
      for m in 1:M
        @test point_values(cross(vv, vv2))[m, :] ≈ crossref(dv[m, :], dv2[m, :])
        @test point_values(vv × a)[m, :]         ≈ crossref(dv[m, :], a)
        @test point_values(tv * vv)[m, :]        ≈ matvec(dt[m, :, :], dv[m, :])
        @test point_values(vv * tv)[m, :]        ≈ vecmat(dv[m, :], dt[m, :, :])
        @test point_values(tv * tv2)[m, :, :]    ≈ matmat(dt[m, :, :], dt2[m, :, :])
      end
      # five-argument mul! accumulate (β ≠ 0)
      dest = VectorPointValues(rand(T, M, 3)); prev = copy(point_values(dest))
      mul!(dest, tv, vv, T(2), T(3))
      for m in 1:M
        @test point_values(dest)[m, :] ≈ T(2) .* matvec(dt[m, :, :], dv[m, :]) .+ T(3) .* prev[m, :]
      end
      # overwrite (β = 0) must ignore the destination's prior contents (NaN included)
      ow = VectorPointValues(fill(T(NaN), M, 3))
      mul!(ow, tv, vv, T(1), T(0))
      @test all(isfinite, point_values(ow))
      for m in 1:M
        @test point_values(ow)[m, :] ≈ matvec(dt[m, :, :], dv[m, :])
      end
    end

    @testset "transpose / norm / sym / skew / dev / trace / det ($T)" begin
      for m in 1:M, i in 1:3, j in 1:3
        @test point_values(transpose(tv))[m, i, j] ≈ dt[m, j, i]
      end
      @test point_values(norm(vv)) ≈ [sqrt(sum(dv[m, i]^2 for i in 1:3)) for m in 1:M]
      @test point_values(norm(tv)) ≈ [sqrt(sum(dt[m, :, :] .^ 2)) for m in 1:M]
      @test point_values(tr(tv)) ≈ [dt[m, 1, 1] + dt[m, 2, 2] + dt[m, 3, 3] for m in 1:M]
      @test point_values(det(tv)) ≈ [dt[m, 1, 1] * (dt[m, 2, 2] * dt[m, 3, 3] - dt[m, 2, 3] * dt[m, 3, 2]) -
                                     dt[m, 1, 2] * (dt[m, 2, 1] * dt[m, 3, 3] - dt[m, 2, 3] * dt[m, 3, 1]) +
                                     dt[m, 1, 3] * (dt[m, 2, 1] * dt[m, 3, 2] - dt[m, 2, 2] * dt[m, 3, 1]) for m in 1:M]
      for m in 1:M
        Am = dt[m, :, :]; Amt = permutedims(Am)
        tr3 = (Am[1, 1] + Am[2, 2] + Am[3, 3]) / 3
        dref = copy(Am); dref[1, 1] -= tr3; dref[2, 2] -= tr3; dref[3, 3] -= tr3
        @test point_values(sym(tv))[m, :, :]  ≈ (Am .+ Amt) ./ 2
        @test point_values(skew(tv))[m, :, :] ≈ (Am .- Amt) ./ 2
        @test point_values(dev(tv))[m, :, :]  ≈ dref
      end
    end
  end
end


@testset "coverage-axes closure: α = 0, aliasing, guard wiring ($TP)" for TP in (Float64, Float32)
  u = VectorPointValues(rand(TP, 6, 3))
  v = VectorPointValues(rand(TP, 6, 3))
  A = TensorPointValues(rand(TP, 6, 3, 3))

  # α = 0, β ≠ 0 for the point-value mul! — the one α/β op on this base, branch never asserted
  dest = VectorPointValues(rand(TP, 6, 3))
  before = copy(point_values(dest))
  mul!(dest, A, u, TP(0), TP(2))
  @test point_values(dest) == 2 .* before

  # aliased in-place calls: the module claims decision-39 alias-safety but had no guard for it
  ref_add = point_values(u) .+ point_values(v)
  ua = VectorPointValues(copy(point_values(u))); add!(ua, ua, v)
  @test point_values(ua) == ref_add
  vb = VectorPointValues(copy(point_values(v))); add!(vb, u, vb)
  @test point_values(vb) == ref_add
  ref_cross = cross(u, v)
  vx = VectorPointValues(copy(point_values(v))); cross!(vx, u, vx)      # dest ≡ b
  @test point_values(vx) == point_values(ref_cross)
  for (op!, op) in ((transpose!, transpose), (sym!, sym), (skew!, skew), (dev!, dev))
    ref_u = op(A)
    aliased = TensorPointValues(copy(point_values(A)))
    op!(aliased, aliased)
    @test point_values(aliased) == point_values(ref_u)
  end

  # the npoints-mismatch guards fire through the public algebra (only the internal check had a test)
  short = VectorPointValues(rand(TP, 5, 3))
  @test_throws DimensionMismatch add!(VectorPointValues(zeros(TP, 6, 3)), u, short)
  @test_throws DimensionMismatch dot!(ScalarPointValues(zeros(TP, 6)), u, short)

  # M = 0 algebra runs clean (probe-verified, decision 43)
  @test isempty(point_values(add!(ScalarPointValues(zeros(TP, 0)),
                                  ScalarPointValues(zeros(TP, 0)), ScalarPointValues(zeros(TP, 0)))))
end
