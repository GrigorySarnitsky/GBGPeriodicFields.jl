# DEFECT: the NUFFT window stencil was mis-centred at ODD widths. Nodes sat at `base + (i - half)`
# with `half = W ÷ 2` for every `t`, which is the W nearest nodes only when W is even; at W = 11 the
# offsets ran -4…+6, so for t < 1/2 the outermost node lay at distance (W+1)/2 - t > W/2, outside the
# window's support and contributing exactly zero, while the nearest node was never visited. An odd
# stencil therefore did the work of a `W-1` one, asymmetrically, and every `tol` selecting an odd
# width missed its target by 10²–10³× — so a TIGHTER request could return a WORSE result.
#
# FOUND: /bug-hunt, 2026-08-27. FIXED: the commit that promoted this file (`_stencil_half`, per axis).
# Promoted UNCHANGED from the witness; only this provenance header was prepended, per the README.
# Oracle: NUFFT(reference; tol) picks a window width/shape "that reach [tol]" (docstring), and the
# width-selection comment in src/Interpolation.jl states it was "Verified against DirectDFT in
# test/transfer_spectral.jl and bumped if the measured error misses ε". A basic, tol-independent
# sanity property any such accuracy-targeting scheme must have: asking for a TIGHTER tolerance
# (hence picking a WIDER stencil and larger shape parameter) must not make the achieved accuracy
# WORSE. We test this directly against the exact DirectDFT oracle on a field that is genuinely
# band-limited with NO Nyquist content on any axis (so DirectDFT's exactness is unconditional, no
# caveat needed), and points off the grid nodes.
#
# `_nufft_width(tol) = max(4, ceil(Int, -log10(tol)) + 2)` produces an EVEN width for most round
# powers of ten (1e-6 -> 8, 1e-8 -> 10, 1e-10 -> 12) but an ODD width for others (1e-7 -> 9,
# 1e-9 -> 11, 1e-11 -> 13). Every `NUFFT(...; tol=...)` call anywhere in the shipped test suite uses
# an even-width-producing tol (1e-10, 1e-8, 1e-6, or the Float32 default 1e-4) -- grepped and
# confirmed. The odd-width branch of `_es_weights`'s node placement (`half = W ÷ 2`, offsets
# `i - half` for `i = 1:W`) is therefore never numerically exercised by the suite.

using Test
using GBGPeriodicFields
using Random

Random.seed!(555)

@testset "NUFFT: tighter tol must not achieve worse accuracy (odd-width regression)" begin
  grid = Grid3D((16, 14, 12), (2π, 2π, 2π))
  layout = RealFourierLayout()
  shp = GBGPeriodicFields.spectral_field_shape(grid, layout, Val(0))
  n1, n2, n3 = shp

  # Fill only strictly-sub-Nyquist modes on every axis, so the field carries NO Nyquist content at
  # all and DirectDFT's reconstruction is exact with no caveat.
  data = zeros(ComplexF64, shp...)
  for i1 in 1:n1-1, i2 in 1:n2, i3 in 1:n3
    if i2 != n2 ÷ 2 + 1 && i3 != n3 ÷ 2 + 1
      data[i1, i2, i3] = randn() + im * randn()
    end
  end
  field = ScalarFieldSpectral(data, grid, layout)

  M = 40
  points = PointSet(2π .* rand(M, 3))
  exact = point_values(interpolate(field, points, DirectDFT()))
  scale = maximum(abs.(exact))

  achieved(tol) = maximum(abs.(point_values(interpolate(field, points, NUFFT(field; tol = tol))) .- exact)) / scale

  # tol = 1e-8 -> width 10 (even); tol = 1e-9 -> width 11 (odd), a STRICTLY tighter request.
  err_loose = achieved(1e-8)
  err_tight = achieved(1e-9)

  @test NUFFT(field; tol = 1e-8).width == 10
  @test NUFFT(field; tol = 1e-9).width == 11

  # Oracle: a tighter tolerance request (wider stencil, larger shape parameter) must not leave the
  # scheme LESS accurate than the looser request.
  @test err_tight <= err_loose
end
