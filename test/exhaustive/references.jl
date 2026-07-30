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
