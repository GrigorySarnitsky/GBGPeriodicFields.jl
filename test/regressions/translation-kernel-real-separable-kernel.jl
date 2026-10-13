# DEFECT: `translation_kernel!` accepted any `SeparableKernel`, including the REAL-valued windows that
# `assignment_window` and `tophat_window` build, and wrote complex phases into their real factor arrays.
# Nothing refused the call: on the host it failed by conversion, as an `InexactError` from assigning a
# complex number to a real element — after the broadcast had possibly already written part of the
# kernel — and on a CUDA device as a `KernelException` raised inside the broadcast kernel. The outcome
# was right only by accident of Julia's number conversion, which is the kind of refusal invariant 14
# says must be the package's own decision.
#
# The refusal is decided by the kernel's TYPE: a translation is a complex phase, so a kernel whose
# factors are not complex is not one `translation_kernel!` can rebuild.
#
# FOUND: the first device run of the exhaustive survey, 2026-10-13 (4 KernelException cells per CUDA
# configuration). FIXED: the commit that promoted this file.
using Test
using GBGPeriodicFields

@testset "translation_kernel! refuses a real-valued separable kernel ($T)" for T in (Float64, Float32)
  grid = Grid3D((8, 6, 4), T.((2π, 4π, 6π)))
  multipliers = FieldSpectralMultipliers(Array, grid)
  offset = (T(0.3), T(0.1), T(0.2))

  for window in (assignment_window(multipliers), tophat_window(multipliers, T(0.7)))
    before = (copy(window.factor_1), copy(window.factor_2), copy(window.factor_3))
    @test_throws ArgumentError translation_kernel!(window, multipliers, offset)
    # Refused BEFORE writing: the window is left exactly as it was.
    @test (window.factor_1, window.factor_2, window.factor_3) == before
  end

  # The complex kernel it exists for is still rebuilt, and agrees with a freshly built one.
  phase = translation_kernel(multipliers, (zero(T), zero(T), zero(T)))
  translation_kernel!(phase, multipliers, offset)
  fresh = translation_kernel(multipliers, offset)
  @test (phase.factor_1, phase.factor_2, phase.factor_3) == (fresh.factor_1, fresh.factor_2, fresh.factor_3)
end
