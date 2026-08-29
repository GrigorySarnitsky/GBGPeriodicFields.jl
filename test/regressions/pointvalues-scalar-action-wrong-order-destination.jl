# DEFECT: the point-value scalar action accepted a DESTINATION of the wrong tensor order. It checked
# only `_check_npoints_match` — the point count — where the field twin has always called
# `check_field_compatibility`, which is the domain check AND `_same_tensor_order`. So a scalar × scalar
# product could be written into a vector destination, where it was broadcast over the fiber, and a
# VECTOR result into a tensor destination, which Julia's broadcasting expands along the trailing axis
# and returns as a wrong-shaped answer rather than an error. `Points.jl` documents these four
# signatures as "mirroring FieldAlgebra"; they did not.
#
# FOUND: the per-method ledger's dispatch sweep, 2026-08-29 — the cell existed, so a row had to reach
# it, and writing that row is what exposed the asymmetry. FIXED: the commit that promoted this file.
using Test
using GBGPeriodicFields

@testset "the point-value scalar action refuses a destination of the wrong tensor order" begin
  q  = ScalarPointValues(ones(9))
  qa = VectorPointValues(ones(9, 3))
  # A scalar times a scalar is a SCALAR; a vector destination is not a place to put it.
  @test_throws Exception multiply!(VectorPointValues(zeros(9, 3)), q, q)
  @test_throws Exception divide!(VectorPointValues(zeros(9, 3)), q, q)
  # The worse case: a VECTOR result silently broadcast across a tensor destination's last axis,
  # which returns a wrong-shaped answer rather than failing.
  @test_throws Exception multiply!(TensorPointValues{2}(zeros(9, 3, 3)), q, qa)
  # The field layer already refuses the same shape, and these two surfaces mirror each other.
  grid = Grid3D((4, 4, 4), (2π, 2π, 2π))
  s = ScalarFieldPhysical(ones(4, 4, 4), grid)
  @test_throws Exception multiply!(VectorFieldPhysical(zeros(4, 4, 4, 3), grid), s, s)
end
