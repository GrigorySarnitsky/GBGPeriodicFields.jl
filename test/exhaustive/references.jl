# Independent reference implementations — the oracle for the exhaustive sweep.
#
# WHY THESE EXIST. The sweep's first oracle compared the package against ITSELF: an aliased call
# against an unaliased one. That catches a defect which depends on aliasing and is blind to every
# defect that does not — a wrong cross product is wrong identically on both sides and reports clean.
# It is the self-referential assertion decision 52 named, rebuilt at 17,000 cases.
#
# So each operation gets a reference computed here, from raw arrays, by the plainest expression of its
# definition. Slow, obviously correct, and sharing no code with the implementation — which is the only
# property that matters. A correctness oracle also SUBSUMES the aliasing one: if an aliased call
# produces the right answer, aliasing did not break it.
#
# Wavenumbers are rebuilt here from the grid rather than taken from `FieldSpectralMultipliers`, or the
# spectral references would inherit the package's own convention instead of checking it.

using GBGPeriodicFields

# --- wavenumbers, derived from the grid alone -------------------------------------------------------
# The derivative wavenumber is zeroed at an even axis's Nyquist frequency (invariant 5); the squared
# wavenumber keeps the true value there. Both are rebuilt from first principles.
function reference_wavenumbers(grid::Grid3D{T}, layout, axis, len) where {T}
  n = grid.grid_size[axis]
  L = grid.domain_size[axis]
  folded = axis == layout.fft_dims[1]
  raw = folded ? T[2π * k / L for k in 0:(n ÷ 2)] :
                 T[2π * (k <= n ÷ 2 ? k : k - n) / L for k in 0:(n - 1)]
  @assert length(raw) == len "reference wavenumber length $(length(raw)) ≠ $len on axis $axis"
  derivative = copy(raw)
  if iseven(n)
    nyquist = folded ? lastindex(derivative) : findfirst(≈(2π * (n ÷ 2) / L), abs.(raw))
    nyquist === nothing || (derivative[nyquist] = zero(T))
  end
  return derivative, raw
end

# --- physical fiberwise algebra ---------------------------------------------------------------------
ref_add(a, b) = a .+ b
ref_subtract(a, b) = a .- b
ref_combine(α, a, β, b) = α .* a .+ β .* b
ref_scale(a, s) = a .* s
ref_divide(a, s) = a ./ s

function ref_cross(a, b)                      # (u×v)_i = ε_ijk u_j v_k, written out
  out = similar(a)
  out[:, :, :, 1] .= a[:, :, :, 2] .* b[:, :, :, 3] .- a[:, :, :, 3] .* b[:, :, :, 2]
  out[:, :, :, 2] .= a[:, :, :, 3] .* b[:, :, :, 1] .- a[:, :, :, 1] .* b[:, :, :, 3]
  out[:, :, :, 3] .= a[:, :, :, 1] .* b[:, :, :, 2] .- a[:, :, :, 2] .* b[:, :, :, 1]
  return out
end

ref_dot(a, b) = sum(a[:, :, :, i] .* b[:, :, :, i] for i in 1:3)
ref_norm(a) = sqrt.(sum(a[:, :, :, i] .^ 2 for i in 1:3))

function ref_transpose(A)
  out = similar(A)
  for i in 1:3, j in 1:3; out[:, :, :, i, j] .= A[:, :, :, j, i]; end
  return out
end

ref_sym(A) = (A .+ ref_transpose(A)) ./ 2
ref_skew(A) = (A .- ref_transpose(A)) ./ 2
ref_trace(A) = sum(A[:, :, :, i, i] for i in 1:3)

function ref_dev(A)
  out = copy(A)
  third = ref_trace(A) ./ 3
  for i in 1:3; out[:, :, :, i, i] .-= third; end
  return out
end

function ref_det(A)                            # the 3×3 cofactor expansion, written out
  a11, a12, a13 = A[:,:,:,1,1], A[:,:,:,1,2], A[:,:,:,1,3]
  a21, a22, a23 = A[:,:,:,2,1], A[:,:,:,2,2], A[:,:,:,2,3]
  a31, a32, a33 = A[:,:,:,3,1], A[:,:,:,3,2], A[:,:,:,3,3]
  return a11 .* (a22 .* a33 .- a23 .* a32) .-
         a12 .* (a21 .* a33 .- a23 .* a31) .+
         a13 .* (a21 .* a32 .- a22 .* a31)
end

function ref_matvec(A, u)                      # (Au)_i = A_ij u_j
  out = similar(u)
  for i in 1:3
    out[:, :, :, i] .= sum(A[:, :, :, i, j] .* u[:, :, :, j] for j in 1:3)
  end
  return out
end

# --- spectral operators, per mode --------------------------------------------------------------------
# Each walks every stored mode explicitly and applies the definition, so nothing is shared with the
# package's fused kernels or its multiplier arrays.
function mode_wavenumbers(grid, layout, shape)
  k1, s1 = reference_wavenumbers(grid, layout, 1, shape[1])
  k2, s2 = reference_wavenumbers(grid, layout, 2, shape[2])
  k3, s3 = reference_wavenumbers(grid, layout, 3, shape[3])
  return (k1, k2, k3), (s1, s2, s3)
end

function ref_gradient(f, grid, layout)
  shape = size(f); (k1, k2, k3), _ = mode_wavenumbers(grid, layout, shape)
  out = similar(f, (shape..., 3))
  for c in CartesianIndices(shape)
    k = (k1[c[1]], k2[c[2]], k3[c[3]])
    for i in 1:3; out[c, i] = im * k[i] * f[c]; end
  end
  return out
end

function ref_divergence(u, grid, layout)
  shape = size(u)[1:3]; (k1, k2, k3), _ = mode_wavenumbers(grid, layout, shape)
  out = similar(u, shape)
  for c in CartesianIndices(shape)
    k = (k1[c[1]], k2[c[2]], k3[c[3]])
    out[c] = sum(im * k[i] * u[c, i] for i in 1:3)
  end
  return out
end

function ref_curl(u, grid, layout)
  shape = size(u)[1:3]; (k1, k2, k3), _ = mode_wavenumbers(grid, layout, shape)
  out = similar(u)
  for c in CartesianIndices(shape)
    k = (k1[c[1]], k2[c[2]], k3[c[3]])
    out[c, 1] = im * (k[2] * u[c, 3] - k[3] * u[c, 2])
    out[c, 2] = im * (k[3] * u[c, 1] - k[1] * u[c, 3])
    out[c, 3] = im * (k[1] * u[c, 2] - k[2] * u[c, 1])
  end
  return out
end

function ref_laplacian(f, grid, layout)
  shape = size(f); _, (s1, s2, s3) = mode_wavenumbers(grid, layout, shape)
  out = similar(f)
  for c in CartesianIndices(shape)
    out[c] = -(s1[c[1]]^2 + s2[c[2]]^2 + s3[c[3]]^2) * f[c]
  end
  return out
end

function ref_inverse_laplacian(f, grid, layout)
  shape = size(f); _, (s1, s2, s3) = mode_wavenumbers(grid, layout, shape)
  out = similar(f)
  for c in CartesianIndices(shape)
    k2 = s1[c[1]]^2 + s2[c[2]]^2 + s3[c[3]]^2
    out[c] = iszero(k2) ? zero(eltype(f)) : -f[c] / k2
  end
  return out
end

function ref_symmetric_gradient(u, grid, layout)
  shape = size(u)[1:3]; (k1, k2, k3), _ = mode_wavenumbers(grid, layout, shape)
  out = similar(u, (shape..., 3, 3))
  for c in CartesianIndices(shape)
    k = (k1[c[1]], k2[c[2]], k3[c[3]])
    for i in 1:3, j in 1:3
      out[c, i, j] = im * (k[j] * u[c, i] + k[i] * u[c, j]) / 2
    end
  end
  return out
end

function ref_helmholtz(u, grid, layout)
  shape = size(u)[1:3]; (k1, k2, k3), _ = mode_wavenumbers(grid, layout, shape)
  out = similar(u)
  for c in CartesianIndices(shape)
    k = (k1[c[1]], k2[c[2]], k3[c[3]])
    kk = sum(abs2, k)
    longitudinal = iszero(kk) ? zero(eltype(u)) : sum(k[j] * u[c, j] for j in 1:3) / kk
    for i in 1:3
      out[c, i] = u[c, i] - k[i] * longitudinal
    end
  end
  return out
end

ref_convolve(f, kernel_data) = f .* kernel_data


# --- the L²/measure reductions ---------------------------------------------------------------------
#
# Written from the DOCUMENTED definitions (the docstrings' own display formulas), not from the
# implementation — which is the point. An oracle copied off the code checks that the code equals
# itself; one written from the stated contract checks that the code means what the documentation
# claims, so a disagreement is a real finding either way round.
#
#   integral   ∫_Ω f dμ = (|Ω|/N) Σ_x f(x)            fiber-preserving, the one EXTENSIVE reduction
#   inner      ⟨f, g⟩   = (1/N) Σ_x f(x)·g(x)          normalized, fiber contracted
#   l2norm     ‖f‖₂     = √⟨f, f⟩
#   lpnorm     ‖f‖_p    = ((1/N) Σ_x |f(x)|^p)^(1/p),  p = Inf → max_x |f(x)|
#   mean       (1/N) Σ_x f(x)                          fiber-preserving
#   var        (1/(N-1)) Σ_n (f_n - f̄)²                scalar only, Bessel-corrected by default
#   cov        R_ij = (1/(N-1)) Σ_n (u_i - ū_i)(u_j - ū_j)

# Base points down the rows, fiber components across the columns. This uses only the DOCUMENTED
# storage contract — fiber-last, component slices contiguous (invariant 3) — and a plain `reshape`, so
# it borrows no code from the implementation. Partial linear indexing (`data[n, i]` on a 4-D array) is
# not a thing in Julia and was the first attempt.
_ref_flat(data, R) = reshape(data, :, 3^R)

_ref_fiber(data, index, R) = _ref_flat(data, R)[index, :]
_ref_base_count(data, R) = size(_ref_flat(data, R), 1)

# |f(x)|, the fiber magnitude — the 2-norm of the components, which is what every normalized reduction
# means by the bars.
_ref_magnitude(data, index, R) = sqrt(sum(abs2, _ref_fiber(data, index, R)))

function ref_mean(data, R)
  N = _ref_base_count(data, R)
  total = sum(_ref_fiber(data, n, R) for n in 1:N)
  return total ./ N
end

ref_integral(data, R, grid) =
  ref_mean(data, R) .* prod(grid.domain_size)          # (|Ω|/N)·Σ = |Ω|·mean

function ref_inner(a, b, R)
  N = _ref_base_count(a, R)
  return sum(sum(_ref_fiber(a, n, R) .* _ref_fiber(b, n, R)) for n in 1:N) / N
end

ref_l2norm(a, R) = sqrt(ref_inner(a, a, R))

function ref_lpnorm(data, p, R)
  N = _ref_base_count(data, R)
  magnitudes = [_ref_magnitude(data, n, R) for n in 1:N]
  isinf(p) && return maximum(magnitudes)
  return (sum(m^p for m in magnitudes) / N)^(1 / p)
end

function ref_var(data)                                  # scalar sections only
  N = length(data)
  average = sum(data) / N
  return sum(abs2, data .- average) / (N - 1)
end

ref_std(data) = sqrt(ref_var(data))

function ref_cov(data)                                  # a vector section's Sym²(V) second moment
  N = div(length(data), 3)
  averages = [sum(data[:, :, :, i]) / N for i in 1:3]
  out = zeros(eltype(data), 3, 3)
  for i in 1:3, j in 1:3
    out[i, j] = sum((data[:, :, :, i] .- averages[i]) .* (data[:, :, :, j] .- averages[j])) / (N - 1)
  end
  return out
end
