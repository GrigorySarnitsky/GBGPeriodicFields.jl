# =============================================================================
# Allocation-free in-place operators — regression guard.
#
# The in-place `!` operators must allocate NO field-sized scratch when called on preallocated buffers
# with a destination distinct from the sources. An internal temporary is invisible on the CPU (the GC
# reclaims it), but on the GPU it grows the device memory pool every step until the run wedges or
# `hipMalloc` segfaults — exactly what bit the HIST demos before the fix (see examples/README.md). These
# tests lock the property in: in particular the lazy `|k|²` (`_squared_wavenumber_broadcast`) and the
# fused `helmholtz_projection!` / `laplacian!` / `inverse_laplacian!` kernels, which previously each
# materialized an O(N³) temporary per call.
#
# Method: warm up the operator once (to exclude compilation), then measure a single in-place call with
# `@allocated`. A field-sized temporary would be hundreds of KB; the threshold is a small fraction of one
# field, so it catches any field allocation while tolerating the few hundred bytes of scalar/closure noise.
# =============================================================================

using Test
using GBGPeriodicFields              # exports `mul!` (re-exported from FieldAlgebra), so no LinearAlgebra import
using GBGPeriodicFields: field_data

@testset "allocation-free in-place operators" begin
  for T in (Float64, Float32)
    @testset "$T" begin
      N = 24
      grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
      layout = RealFourierLayout()

      spectral_vector() = VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid)
      spectral_scalar() = ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)
      spectral_tensor() = TensorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(2))), grid)
      physical_vector() = VectorFieldPhysical(zeros(T, N, N, N, 3), grid)
      physical_scalar() = ScalarFieldPhysical(zeros(T, N, N, N), grid)
      physical_tensor() = TensorFieldPhysical(zeros(T, N, N, N, 3, 3), grid)
      randomize!(f) = (field_data(f) .= rand(eltype(field_data(f)), size(field_data(f))); f)

      multipliers = FieldSpectralMultipliers(spectral_vector())
      vector_plans = FieldTransformPlans(physical_vector(), spectral_vector())
      scalar_plans = FieldTransformPlans(physical_scalar(), spectral_scalar())

      # A full field is this many bytes; allow only a small fraction (so a field-sized temp fails the test).
      field_bytes = sizeof(field_data(spectral_vector()))
      threshold = field_bytes ÷ 16

      # sources (with data) and distinct destinations
      vector_source = randomize!(spectral_vector())
      scalar_source = randomize!(spectral_scalar())
      tensor_source = randomize!(spectral_tensor())
      vector_dest, scalar_dest, tensor_dest = spectral_vector(), spectral_scalar(), spectral_tensor()
      kernel = spectral_scalar(); field_data(kernel) .= one(Complex{T})

      physical_u = randomize!(physical_vector())
      physical_v = randomize!(physical_vector())
      physical_tensor_source = randomize!(physical_tensor())
      physical_vector_dest, physical_scalar_dest, physical_tensor_dest =
        physical_vector(), physical_scalar(), physical_tensor()

      # --- spectral differential operators (lazy |k|² + fused kernels) -------
      laplacian!(vector_dest, vector_source, multipliers)
      @test (@allocated laplacian!(vector_dest, vector_source, multipliers)) < threshold
      inverse_laplacian!(vector_dest, vector_source, multipliers)
      @test (@allocated inverse_laplacian!(vector_dest, vector_source, multipliers)) < threshold
      helmholtz_projection!(vector_dest, vector_source, multipliers)
      @test (@allocated helmholtz_projection!(vector_dest, vector_source, multipliers)) < threshold
      curl!(vector_dest, vector_source, multipliers)
      @test (@allocated curl!(vector_dest, vector_source, multipliers)) < threshold
      divergence!(scalar_dest, vector_source, multipliers)
      @test (@allocated divergence!(scalar_dest, vector_source, multipliers)) < threshold
      gradient!(vector_dest, scalar_source, multipliers)
      @test (@allocated gradient!(vector_dest, scalar_source, multipliers)) < threshold
      gradient!(tensor_dest, vector_source, multipliers)
      @test (@allocated gradient!(tensor_dest, vector_source, multipliers)) < threshold

      # --- spectral convolution (coefficientwise kernel multiply) ------------
      convolve!(vector_dest, vector_source, kernel)
      @test (@allocated convolve!(vector_dest, vector_source, kernel)) < threshold
      convolve!(vector_dest, vector_source, kernel, T(0.5), T(1))
      @test (@allocated convolve!(vector_dest, vector_source, kernel, T(0.5), T(1))) < threshold

      # --- transforms (FFT plans reuse their own work buffers) ---------------
      to_physical!(physical_vector_dest, randomize!(spectral_vector()), vector_plans)
      @test (@allocated to_physical!(physical_vector_dest, vector_source, vector_plans)) < threshold
      to_spectral!(vector_dest, randomize!(physical_vector()), vector_plans)
      @test (@allocated to_spectral!(vector_dest, physical_u, vector_plans)) < threshold

      # --- fiberwise algebra, distinct destination (no alias guard) ----------
      cross!(physical_vector_dest, physical_u, physical_v)
      @test (@allocated cross!(physical_vector_dest, physical_u, physical_v)) < threshold
      mul!(physical_vector_dest, physical_tensor_source, physical_u)
      @test (@allocated mul!(physical_vector_dest, physical_tensor_source, physical_u)) < threshold
      add!(vector_dest, vector_source, vector_source)
      @test (@allocated add!(vector_dest, vector_source, vector_source)) < threshold
      subtract!(vector_dest, vector_source, vector_source)
      @test (@allocated subtract!(vector_dest, vector_source, vector_source)) < threshold
      transpose!(physical_tensor_dest, physical_tensor_source)
      @test (@allocated transpose!(physical_tensor_dest, physical_tensor_source)) < threshold
      sym!(physical_tensor_dest, physical_tensor_source)
      @test (@allocated sym!(physical_tensor_dest, physical_tensor_source)) < threshold
      skew!(physical_tensor_dest, physical_tensor_source)
      @test (@allocated skew!(physical_tensor_dest, physical_tensor_source)) < threshold

      # NOTE: a few fiber ops carry an internal scalar reduction and so materialize one field — the norm
      # `norm!`/`lpnorm` (the pointwise magnitude) and `dev!` (the trace it subtracts). These are NOT
      # allocation-free and are excluded here; the HIST demo's CFL speed uses `maximum(abs, field_data(u))`
      # rather than `lpnorm` for exactly this reason (see its comment).
    end
  end
end
