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
  # `k < (n + 1) ÷ 2`, not `k <= n ÷ 2`. On an even non-folded axis the two disagree at exactly the
  # Nyquist slot — the first gives −n/2 (what `fftfreq` and the package produce), the second +n/2. Every
  # current consumer masks it (the squared family is even, cos is even, sinc² is even, and the derivative
  # family is zeroed there by invariant 5), so it is invisible today and would silently hand the wrong
  # oracle to the first operation that is odd in k and does not zero the Nyquist.
  raw = folded ? T[2π * k / L for k in 0:(n ÷ 2)] :
                 T[2π * (k < (n + 1) ÷ 2 ? k : k - n) / L for k in 0:(n - 1)]
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

# The JACOBIAN mode of `gradient`, whose index convention was checked only through `sym`. The one
# exercise of `gradient(vector)` in the suite was `symmetric_gradient = sym(gradient(u))` — and
# `sym(M) = sym(Mᵀ)`, so a transposed fiber-index pair was erased before the comparison ever saw it.
# The convention here is the package's own, stated in its `symmetric_gradient` formula
# `Ŝ_ij = (i/2)(k_j û_i + k_i û_j)`: the DERIVATIVE index is second, so (∇u)_ij = i k_j û_i.
function ref_gradient_jacobian(u, grid, layout)
  shape = size(u)[1:3]; (k1, k2, k3), _ = mode_wavenumbers(grid, layout, shape)
  out = similar(u, (shape..., 3, 3))          # (base..., i, j) — a second-order fiber, not a vector
  for c in CartesianIndices(shape)
    k = (k1[c[1]], k2[c[2]], k3[c[3]])
    for i in 1:3, j in 1:3
      out[c, i, j] = im * k[j] * u[c, i]
    end
  end
  return out
end

# The tensor-tensor product, (AB)_ij = A_ik B_kj. The suite's only exercise of it was
# `det(AB) = det(A)det(B)` — and the determinant is multiplicative AND transpose-invariant, so that
# identity holds equally for `BA`, `AᵀB`, `ABᵀ` and the rest of the family. It cannot tell a correct
# product from a transposed or reversed one; this can.
function ref_matmul(A, B)
  shape = size(A)[1:3]
  out = similar(A)
  for c in CartesianIndices(shape), i in 1:3, j in 1:3
    total = zero(eltype(A))
    for k in 1:3
      total += A[c, i, k] * B[c, k, j]
    end
    out[c, i, j] = total
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


# --- the transforms, from the DFT definition --------------------------------------------------------
#
# Written as the literal sum, not by calling any FFT: the package's transform is what is under test, and
# an oracle that calls `fft` would only be checking one library against another. The phase is
# index-based, exp(-2πi Σ_d n_d m_d / N_d), because the transform is a plain DFT over the storage
# indices — the grid's origin enters position-dependent operations (the transfer verbs, the translation
# kernel), never the FFT itself.
# FIBER-AWARE, and it was not. The three-index read `data[n1+1, n2+1, n3+1]` does not ERROR on a vector
# field's 4-D array — Julia's trailing-dimension linearization makes it silently return component 1 — so
# this oracle was not merely unexercised above R = 0, it was unequipped, and would have "agreed" with the
# package while reading a third of the field. Every spectral vector and tensor operation in the suite
# takes its transformed input on trust from here. The transform is a batched 3-D DFT over the base with
# the fiber carried along, so the fiber is looped, never mixed.
function ref_dft_forward(data, grid, layout)
  N = grid.grid_size
  folded = layout.fft_dims[1]
  stored = ntuple(d -> d == folded ? (N[d] ÷ 2 + 1) : N[d], 3)
  fiber = size(data)[4:end]
  out = zeros(Complex{eltype(data)}, stored..., fiber...)
  for component in CartesianIndices(fiber)
    for m1 in 0:stored[1]-1, m2 in 0:stored[2]-1, m3 in 0:stored[3]-1
      total = zero(Complex{eltype(data)})
      for n1 in 0:N[1]-1, n2 in 0:N[2]-1, n3 in 0:N[3]-1
        phase = -2π * (n1 * m1 / N[1] + n2 * m2 / N[2] + n3 * m3 / N[3])
        total += data[n1 + 1, n2 + 1, n3 + 1, component] * cis(phase)
      end
      out[m1 + 1, m2 + 1, m3 + 1, component] = total
    end
  end
  return out
end

# The inverse, reconstructed from the STORED half-spectrum by Hermitian completion: the unstored
# partner of mode k is conj(f̂(-k)), which is what makes the result real. Normalized by N (AbstractFFTs'
# convention, invariant 4).
# Fiber-aware for the same reason as `ref_dft_forward`: the fiber is carried, never mixed.
function ref_dft_inverse(spectral, grid, layout)
  N = grid.grid_size
  folded = layout.fft_dims[1]
  T = real(eltype(spectral))
  fiber = size(spectral)[4:end]
  out = zeros(T, N..., fiber...)
  stored = size(spectral)[1:3]
  wrap(m, n) = mod(m, n)
  for component in CartesianIndices(fiber)
    for n1 in 0:N[1]-1, n2 in 0:N[2]-1, n3 in 0:N[3]-1
      total = zero(Complex{T})
      for m1 in 0:N[1]-1, m2 in 0:N[2]-1, m3 in 0:N[3]-1
        m = (m1, m2, m3)
        # Reach the stored coefficient for this mode, conjugating when only the partner is kept.
        if m[folded] <= N[folded] ÷ 2
          index = ntuple(d -> m[d] + 1, 3)
          all(d -> index[d] <= stored[d], 1:3) || continue
          coefficient = spectral[index..., component]
        else
          partner = ntuple(d -> wrap(-m[d], N[d]), 3)
          index = ntuple(d -> partner[d] + 1, 3)
          all(d -> index[d] <= stored[d], 1:3) || continue
          coefficient = conj(spectral[index..., component])
        end
        phase = 2π * (n1 * m1 / N[1] + n2 * m2 / N[2] + n3 * m3 / N[3])
        total += coefficient * cis(phase)
      end
      out[n1 + 1, n2 + 1, n3 + 1, component] = real(total) / prod(N)
    end
  end
  return out
end

# --- the spectral kernel symbols, from their documented formulas -------------------------------------
#
# Each builder's docstring states its multiplier; these evaluate that statement per mode, from
# wavenumbers rebuilt here.
function _ref_mode_wavenumbers(grid, layout, shape)
  k1 = reference_wavenumbers(grid, layout, 1, shape[1])
  k2 = reference_wavenumbers(grid, layout, 2, shape[2])
  k3 = reference_wavenumbers(grid, layout, 3, shape[3])
  return (derivative = (k1[1], k2[1], k3[1]), true_k = (k1[2], k2[2], k3[2]))
end

function ref_squared_wavenumber(grid, layout, shape)
  w = _ref_mode_wavenumbers(grid, layout, shape).true_k
  return [w[1][i]^2 + w[2][j]^2 + w[3][l]^2 for i in 1:shape[1], j in 1:shape[2], l in 1:shape[3]]
end

function ref_spectral_band(grid, layout, shape, k_lo, k_hi)
  k2 = ref_squared_wavenumber(grid, layout, shape)
  return [(k_lo^2 <= v <= k_hi^2) ? one(eltype(k2)) : zero(eltype(k2)) for v in k2]
end

ref_spectral_cutoff(grid, layout, shape, k) = ref_spectral_band(grid, layout, shape, zero(k), k)

ref_exponential_symbol(grid, layout, shape, c) = exp.(c .* ref_squared_wavenumber(grid, layout, shape))

# Ŵ = ∏_a sinc²(k_a Δx_a / 2), the linear/CIC assignment window. `sinc` here is the UNNORMALIZED
# sin(x)/x, which is what the formula means; Julia's `sinc` is sin(πx)/(πx), so the argument is divided
# by π to undo that.
function ref_assignment_window(grid, layout, shape)
  w = _ref_mode_wavenumbers(grid, layout, shape).true_k
  Δ = grid.grid_spacing
  factor(k, d) = sinc(k * Δ[d] / (2π))^2
  return [factor(w[1][i], 1) * factor(w[2][j], 2) * factor(w[3][l], 3)
          for i in 1:shape[1], j in 1:shape[2], l in 1:shape[3]]
end

# ĝ = e^{-i k·h}, the shift theorem's phase, with decision 28's Nyquist split: the even (cos) part
# comes from the TRUE |k| and the odd (sin) part from the Nyquist-zeroed derivative k, so an even
# axis's Nyquist multiplier is the real cos(πh/Δ) rather than a phase.
function ref_translation_kernel(grid, layout, shape, h)
  modes = _ref_mode_wavenumbers(grid, layout, shape)
  even, odd = modes.true_k, modes.derivative
  # PER AXIS, then multiplied. The kernel is separable — ∏_a e^{-i k_a h_a} — so the Nyquist split is
  # applied to each axis's own factor. Splitting the SUMMED argument instead gives a different function
  # entirely (it was the first attempt, and it disagreed).
  out = zeros(Complex{eltype(grid.domain_size)}, shape...)
  factor(axis, index) = complex(cos(even[axis][index] * h[axis]), -sin(odd[axis][index] * h[axis]))
  for i in 1:shape[1], j in 1:shape[2], l in 1:shape[3]
    out[i, j, l] = factor(1, i) * factor(2, j) * factor(3, l)
  end
  return out
end


# --- the spectral reductions ------------------------------------------------------------------------
#
# Parseval with the rfft half-spectrum weighting: the folded axis stores only its non-negative
# frequencies, so each mode stands for itself AND its unstored conjugate partner and counts twice,
# EXCEPT that axis's self-conjugate zero plane and — when the axis is even — its Nyquist plane, which
# count once. Written from that statement rather than from the implementation's fused form.
function _ref_parseval_weight(index, grid, layout, shape)
  folded = layout.fft_dims[1]
  m = index[folded] - 1
  n = grid.grid_size[folded]
  self_conjugate = m == 0 || (iseven(n) && m == n ÷ 2)
  return self_conjugate ? 1 : 2
end

function ref_spectral_inner(a, b, grid, layout, R)
  shape = size(a)[1:3]
  N = prod(grid.grid_size)
  total = 0.0
  components = 3^R
  flat_a, flat_b = reshape(a, :, components), reshape(b, :, components)
  for index in CartesianIndices(shape)
    weight = _ref_parseval_weight(Tuple(index), grid, layout, shape)
    linear = LinearIndices(shape)[index]
    for c in 1:components
      total += weight * real(flat_a[linear, c] * conj(flat_b[linear, c]))
    end
  end
  return total / N^2
end

# ⟨f, w·g⟩ — the multiplier-weighted spectral inner, the reduction-dual of `convolve`. Same weighting,
# with the real per-mode multiplier folded in.
function ref_weighted_inner(a, b, weight_field, grid, layout, R)
  shape = size(a)[1:3]
  N = prod(grid.grid_size)
  components = 3^R
  flat_a, flat_b = reshape(a, :, components), reshape(b, :, components)
  total = 0.0
  for index in CartesianIndices(shape)
    parseval = _ref_parseval_weight(Tuple(index), grid, layout, shape)
    linear = LinearIndices(shape)[index]
    w = real(weight_field[index])
    for c in 1:components
      total += parseval * w * real(flat_a[linear, c] * conj(flat_b[linear, c]))
    end
  end
  return total / N^2
end

# The shell-resolved inner: the same Parseval sum, binned by |k| into unit-width shells. Its defining
# property is that the shells sum to `inner`, which the value lane asserts separately.
function ref_radial_spectrum(a, grid, layout, R)
  shape = size(a)[1:3]
  N = prod(grid.grid_size)
  components = 3^R
  flat = reshape(a, :, components)
  k2 = ref_squared_wavenumber(grid, layout, shape)
  Δk = 2π / maximum(grid.domain_size)
  shells = zeros(Float64, 0)
  for index in CartesianIndices(shape)
    linear = LinearIndices(shape)[index]
    shell = round(Int, sqrt(k2[index]) / Δk) + 1
    shell > length(shells) && append!(shells, zeros(shell - length(shells)))
    weight = _ref_parseval_weight(Tuple(index), grid, layout, shape)
    for c in 1:components
      shells[shell] += weight * abs2(flat[linear, c])
    end
  end
  return shells ./ N^2
end

# The TWO-FIELD co-spectrum (decision 22): the same shell binning, contracting `Re(f̂ conj(ĝ))` instead
# of `|f̂|²`. It is a distinct branch — it may be negative, and dropping the conjugate would break the
# documented f↔g symmetry — and the single-field form is the g = f case, so this reference must be
# written from the definition rather than delegated to the one above.
function ref_radial_spectrum(a, b, grid, layout, R)
  shape = size(a)[1:3]
  N = prod(grid.grid_size)
  components = 3^R
  flat_a, flat_b = reshape(a, :, components), reshape(b, :, components)
  k2 = ref_squared_wavenumber(grid, layout, shape)
  Δk = 2π / maximum(grid.domain_size)
  shells = zeros(Float64, 0)
  for index in CartesianIndices(shape)
    linear = LinearIndices(shape)[index]
    shell = round(Int, sqrt(k2[index]) / Δk) + 1
    shell > length(shells) && append!(shells, zeros(shell - length(shells)))
    weight = _ref_parseval_weight(Tuple(index), grid, layout, shape)
    for c in 1:components
      shells[shell] += weight * real(flat_a[linear, c] * conj(flat_b[linear, c]))
    end
  end
  return shells ./ N^2
end

# The exact spectral evaluation of a band-limited field at an arbitrary point — the definition
# `DirectDFT` implements and `NUFFT` approximates to a tolerance. Written as the literal sum over stored
# modes with the rfft multiplicity applied, and the position measured from the grid ORIGIN.
#
# This exists because `NUFFT` had no independent value oracle anywhere in the survey: it was built as a
# scheme argument and its bad-tolerance rejection was checked, but the spread/FFT/deconvolve pipeline
# itself was compared to nothing, so a wrong exponent in the deconvolution window or a transposed axis
# in the gridding produced a finite, deterministic, correctly-shaped, wrong answer that every universal
# check passed.
# The folded axis's Nyquist plane, zeroed. `NUFFT` is exact against `DirectDFT` only on the RESOLVED
# SUB-NYQUIST band — it projects the rfft Nyquist out so the spread and gather stay exact adjoints —
# while `DirectDFT` evaluates the stored spectrum as it is. One reference serves both, with this applied
# for the NUFFT comparison: measured on an 8³ grid, `DirectDFT` agrees with the unprojected reference to
# 6.7e-16 and `NUFFT` differs from it by 0.104, which is the projection, not an error.
function ref_project_out_nyquist(spectral, grid, layout)
  out = copy(spectral)
  for axis in 1:3
    n = grid.grid_size[axis]
    iseven(n) || continue
    # EVERY even axis, not only the folded one — measured: projecting the folded axis alone leaves NUFFT
    # disagreeing by 0.219, projecting all of them brings it to 3.3e-12. On the folded axis the Nyquist
    # is the last stored slot; elsewhere the stored order runs 0, 1, …, so it sits at `n ÷ 2 + 1`.
    index = axis == layout.fft_dims[1] ? size(out, axis) : (n ÷ 2 + 1)
    plane = ntuple(d -> d == axis ? (index:index) : Base.axes(out, d), ndims(out))
    out[plane...] .= 0
  end
  return out
end

function ref_spectral_interpolate(spectral, grid, layout, coordinates, R)
  shape = size(spectral)[1:3]
  components = 3^R
  flat = reshape(spectral, :, components)
  # The TRUE wavenumbers, not the derivative family. Evaluating a field is not differentiating it, so the
  # Nyquist slot carries its real value here (invariant 5's split, taken on the other side).
  _, (k1, k2, k3) = mode_wavenumbers(grid, layout, shape)
  N = prod(grid.grid_size)
  M = size(coordinates, 1)
  out = zeros(real(eltype(spectral)), M, components)
  for p in 1:M, c in 1:components
    total = 0.0
    for index in CartesianIndices(shape)
      linear = LinearIndices(shape)[index]
      k = (k1[index[1]], k2[index[2]], k3[index[3]])
      phase = sum(k[d] * (coordinates[p, d] - grid.origin[d]) for d in 1:3)
      # The rfft stores half the spectrum; a mode with an unstored conjugate partner counts twice, which
      # is the same multiplicity the Parseval weight applies.
      weight = _ref_parseval_weight(Tuple(index), grid, layout, shape)
      total += weight * real(flat[linear, c] * cis(phase))
    end
    out[p, c] = total / N
  end
  return components == 1 ? vec(out) : out
end

# --- the grid↔point transfer ------------------------------------------------------------------------
#
# The Catmull-Rom weights, written out. These are the standard two-point Hermite cubics — the
# `LalescuSpline(1, 1)` the package takes as its default — and are stated here as polynomials in the
# cell-local coordinate rather than obtained from the package's weight builder.
_ref_catmull_rom(t) = (-0.5t^3 + t^2 - 0.5t,
                        1.5t^3 - 2.5t^2 + 1,
                       -1.5t^3 + 2t^2 + 0.5t,
                        0.5t^3 - 0.5t^2)

# Gather: f(x_p) = Σ_stencil w_i w_j w_k f[n + offset], with periodic wrap. Positions are measured from
# the grid's ORIGIN, which is the axis a fixture at origin 0 cannot see.
function ref_interpolate_catmull_rom(data, grid, points, R)
  N, Δ, o = grid.grid_size, grid.grid_spacing, grid.origin
  M = size(points, 1)
  components = 3^R
  flat = reshape(data, :, components)
  linear = LinearIndices(N)
  out = zeros(eltype(data), M, components)
  for p in 1:M
    base = ntuple(3) do d
      position = (points[p, d] - o[d]) / Δ[d]
      floor(Int, position)
    end
    local_t = ntuple(d -> (points[p, d] - o[d]) / Δ[d] - base[d], 3)
    weights = ntuple(d -> _ref_catmull_rom(local_t[d]), 3)
    for i in 1:4, j in 1:4, k in 1:4
      n1 = mod(base[1] + i - 2, N[1]) + 1
      n2 = mod(base[2] + j - 2, N[2]) + 1
      n3 = mod(base[3] + k - 2, N[3]) + 1
      w = weights[1][i] * weights[2][j] * weights[3][k]
      index = linear[n1, n2, n3]
      for c in 1:components
        out[p, c] += w * flat[index, c]
      end
    end
  end
  return R == 0 ? out[:, 1] : reshape(out, M, ntuple(_ -> 3, R)...)
end

# Scatter: the transpose of the gather, accumulating each point's value into the same stencil.
function ref_anterpolate_catmull_rom(values, grid, points, R)
  N, Δ, o = grid.grid_size, grid.grid_spacing, grid.origin
  M = size(points, 1)
  components = 3^R
  flat_values = reshape(values, M, components)
  out = zeros(eltype(values), prod(N), components)
  linear = LinearIndices(N)
  for p in 1:M
    base = ntuple(d -> floor(Int, (points[p, d] - o[d]) / Δ[d]), 3)
    local_t = ntuple(d -> (points[p, d] - o[d]) / Δ[d] - base[d], 3)
    weights = ntuple(d -> _ref_catmull_rom(local_t[d]), 3)
    for i in 1:4, j in 1:4, k in 1:4
      n1 = mod(base[1] + i - 2, N[1]) + 1
      n2 = mod(base[2] + j - 2, N[2]) + 1
      n3 = mod(base[3] + k - 2, N[3]) + 1
      w = weights[1][i] * weights[2][j] * weights[3][k]
      index = linear[n1, n2, n3]
      for c in 1:components
        out[index, c] += w * flat_values[p, c]
      end
    end
  end
  return reshape(out, N..., ntuple(_ -> 3, R)...)
end


# The Wiener–Khinchin dual, shell by shell.
#
# `radial_spectrum` was compared only through `sum(...)` until an adversarial pass, and the sum is
# invariant to how modes are binned — so the binning, the operation's entire purpose, was checked by
# nothing. That was fixed for the spectrum and never carried to its dual: `radial_correlation` was
# checked only at `C(0)`, which Parseval forces, leaving every non-zero separation with no reference.
#
# Written from the documented definition: C(r) = 𝓕⁻¹(|f̂|²)/N, averaged over the shell of
# minimum-image separations |r|. The inverse transform is the reference's own, not the package's.
function ref_radial_correlation(spectral, grid, layout)
  N = grid.grid_size
  power = abs2.(spectral)
  # |f̂|² is real and Hermitian, so its inverse transform is real: reuse the reference inverse DFT,
  # which performs the Hermitian completion from the stored half-spectrum.
  correlation = ref_dft_inverse(complex.(power), grid, layout) ./ prod(N)
  Δ = grid.grid_spacing
  # The minimum-image separation of each offset, and the shell it falls in.
  separation(n, d) = min(n, N[d] - n) * Δ[d]
  Δr = minimum(Δ)
  sums, counts = Float64[], Int[]
  for n1 in 0:N[1]-1, n2 in 0:N[2]-1, n3 in 0:N[3]-1
    r = sqrt(separation(n1, 1)^2 + separation(n2, 2)^2 + separation(n3, 3)^2)
    shell = round(Int, r / Δr) + 1
    while shell > length(sums)
      Base.push!(sums, 0.0); Base.push!(counts, 0)
    end
    sums[shell] += correlation[n1 + 1, n2 + 1, n3 + 1]
    counts[shell] += 1
  end
  return [c == 0 ? 0.0 : s / c for (s, c) in zip(sums, counts)]
end


# --- base-space motion and the reality check (decisions 71, 73) -------------------------------------
# Written from the docstrings, over raw arrays. `wrap!` is the canonical representative in the
# half-open box `[o, o+L)`; `displace!` is `x_p + Σ_j c_j v_j(p)`, taken literally in the universal
# cover, and composed with the wrap when a grid is supplied.
ref_wrap(coordinates, grid) =
  [mod(coordinates[p, d] - grid.origin[d], grid.domain_size[d]) + grid.origin[d]
   for p in axes(coordinates, 1), d in 1:3]


function ref_displace(coordinates, terms...)
  moved = copy(coordinates)
  for (coefficient, values) in terms
    for p in axes(moved, 1), d in 1:3
      moved[p, d] += coefficient * values[p, d]
    end
  end
  return moved
end


ref_displace_wrapped(coordinates, grid, terms...) = ref_wrap(ref_displace(coordinates, terms...), grid)


# The largest ``|f̂(k) - conj(f̂(-k))|`` over the folded axis's self-conjugate planes — its zero plane,
# and its Nyquist plane when that axis has even length — and every fiber component. Which array axis is
# folded is read from the layout, so a permuted fold is checked rather than assumed; the mirror of index
# `i` on a full axis of length `n` is `mod(-(i-1), n) + 1`. A mode that is its own mirror contributes
# twice its imaginary part, which falls out of the same expression rather than being special-cased.
function ref_reality_residual(data, grid, layout)
  folded = layout.fft_dims[1]
  others = Tuple(d for d in 1:3 if d != folded)
  a, b = others
  na, nb = size(data, a), size(data, b)
  planes = iseven(grid.grid_size[folded]) ? (1, size(data, folded)) : (1,)
  fiber_shape = ntuple(i -> size(data, 3 + i), max(0, ndims(data) - 3))
  worst = zero(real(eltype(data)))
  index, mirror = Vector{Int}(undef, 3), Vector{Int}(undef, 3)
  for plane in planes, component in CartesianIndices(fiber_shape), i in 1:na, j in 1:nb
    index[folded] = plane;  index[a] = i;  index[b] = j
    mirror[folded] = plane; mirror[a] = mod(-(i - 1), na) + 1; mirror[b] = mod(-(j - 1), nb) + 1
    here    = data[index[1], index[2], index[3], Tuple(component)...]
    partner = data[mirror[1], mirror[2], mirror[3], Tuple(component)...]
    worst = max(worst, abs(here - conj(partner)))
  end
  return worst
end


# `û = i a × ŵ / |a|²`, the divergence-free preimage of a curl, with the k = 0 mode zero. Written from
# the docstring over raw arrays: the wavenumbers are rebuilt from the grid by `mode_wavenumbers`, and
# the cross product is expanded by hand rather than taken from the package's own `curl`.
function ref_inverse_curl(data, grid, layout)
  result = zeros(eltype(data), size(data))
  (k1, k2, k3), _ = mode_wavenumbers(grid, layout, size(data)[1:3])
  for i in axes(data, 1), j in axes(data, 2), l in axes(data, 3)
    a1, a2, a3 = k1[i], k2[j], k3[l]
    squared = a1 * a1 + a2 * a2 + a3 * a3
    reciprocal = iszero(squared) ? zero(squared) : inv(squared)
    w1, w2, w3 = data[i, j, l, 1], data[i, j, l, 2], data[i, j, l, 3]
    result[i, j, l, 1] = im * (a2 * w3 - a3 * w2) * reciprocal
    result[i, j, l, 2] = im * (a3 * w1 - a1 * w3) * reciprocal
    result[i, j, l, 3] = im * (a1 * w2 - a2 * w1) * reciprocal
  end
  return result
end


# --- constants against a section --------------------------------------------------------------
# A constant added in PHYSICAL representation lands on every base point; in SPECTRAL representation
# invariant 4 says it lands on the zero (DC) Fourier mode alone, scaled by the number of grid points.
# Written from the invariant rather than from the package, which is the point of a reference.
ref_add_constant_physical(data, c, R) = data .+ _fiber_broadcast(c, size(data), R)
ref_subtract_constant_physical(data, c, R) = data .- _fiber_broadcast(c, size(data), R)
ref_constant_minus_physical(data, c, R) = _fiber_broadcast(c, size(data), R) .- data


function _fiber_broadcast(c, shape, R)
  R == 0 && return fill(c, shape)
  # The fiber axes are the TRAILING R, whatever the base is: a field has three base axes and a
  # point-value section has one, and hard-coding three broke on the point sections.
  base = length(shape) - R
  out = Array{typeof(first(c))}(undef, shape)
  for index in CartesianIndices(shape)
    fibre = Tuple(index)[(base + 1):end]
    out[index] = R == 1 ? c[fibre[1]] : c[fibre[1], fibre[2]]
  end
  return out
end


function ref_add_constant_spectral(data, c, grid, R)
  out = copy(data)
  scale = prod(grid.grid_size)
  if R == 0
    out[1, 1, 1] += scale * c
  else
    for fibre in CartesianIndices(ntuple(_ -> 3, R))
      out[1, 1, 1, Tuple(fibre)...] += scale * (R == 1 ? c[fibre[1]] : c[fibre[1], fibre[2]])
    end
  end
  return out
end


function ref_subtract_constant_spectral(data, c, grid, R)
  out = copy(data)
  scale = prod(grid.grid_size)
  if R == 0
    out[1, 1, 1] -= scale * c
  else
    for fibre in CartesianIndices(ntuple(_ -> 3, R))
      out[1, 1, 1, Tuple(fibre)...] -= scale * (R == 1 ? c[fibre[1]] : c[fibre[1], fibre[2]])
    end
  end
  return out
end


# `c - f` is not `-(f - c)` in spectral representation: negating the field negates every mode, while
# the constant still lands on the DC mode alone. Written out rather than derived from the sibling.
function ref_constant_minus_spectral(data, c, grid, R)
  out = -data
  scale = prod(grid.grid_size)
  if R == 0
    out[1, 1, 1] += scale * c
  else
    for fibre in CartesianIndices(ntuple(_ -> 3, R))
      out[1, 1, 1, Tuple(fibre)...] += scale * (R == 1 ? c[fibre[1]] : c[fibre[1], fibre[2]])
    end
  end
  return out
end


# --- base-agnostic contraction references -------------------------------------------------------
# The references above index `a[:, :, :, i]`, which assumes a three-axis base and so cannot be pointed
# at a point-value section, whose base is one axis. These take the fiber as the TRAILING axes and work
# over any base, which is what lets one sweep drive the field and point families from one definition.
_base_shape(a, R) = ntuple(d -> size(a, d), ndims(a) - R)


function ref_dot_generic(a, b)
  base = _base_shape(a, 1)
  # Promote: one operand may be a REAL constant broadcast against a complex spectral section, and
  # `eltype(a)` alone silently narrowed the result and threw on assignment.
  out = zeros(promote_type(eltype(a), eltype(b)), base)
  for I in CartesianIndices(base), i in 1:3
    out[I] += a[I, i] * b[I, i]
  end
  return out
end


function ref_cross_generic(a, b)
  base = _base_shape(a, 1)
  out = Array{promote_type(eltype(a), eltype(b))}(undef, size(a))
  for I in CartesianIndices(base)
    out[I, 1] = a[I, 2] * b[I, 3] - a[I, 3] * b[I, 2]
    out[I, 2] = a[I, 3] * b[I, 1] - a[I, 1] * b[I, 3]
    out[I, 3] = a[I, 1] * b[I, 2] - a[I, 2] * b[I, 1]
  end
  return out
end


function ref_matvec_generic(A, u)               # (Au)_i = A_ij u_j
  base = _base_shape(A, 2)
  out = zeros(promote_type(eltype(A), eltype(u)), (base..., 3))
  for I in CartesianIndices(base), i in 1:3, j in 1:3
    out[I, i] += A[I, i, j] * u[I, j]
  end
  return out
end


function ref_vecmat_generic(u, A)               # (uᵀA)_j = u_i A_ij, the right action
  base = _base_shape(A, 2)
  out = zeros(promote_type(eltype(A), eltype(u)), (base..., 3))
  for I in CartesianIndices(base), j in 1:3, i in 1:3
    out[I, j] += u[I, i] * A[I, i, j]
  end
  return out
end


function ref_matmul_generic(A, B)               # (AB)_ik = A_ij B_jk
  base = _base_shape(A, 2)
  out = zeros(promote_type(eltype(A), eltype(B)), (base..., 3, 3))
  for I in CartesianIndices(base), i in 1:3, k in 1:3, j in 1:3
    out[I, i, k] += A[I, i, j] * B[I, j, k]
  end
  return out
end


function ref_tensor_inner_generic(A, B)         # the Frobenius pairing A_ij B_ij
  base = _base_shape(A, 2)
  out = zeros(promote_type(eltype(A), eltype(B)), base)
  for I in CartesianIndices(base), i in 1:3, j in 1:3
    out[I] += A[I, i, j] * B[I, i, j]
  end
  return out
end
