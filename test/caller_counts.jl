# Caller-controlled counts (decision 88): the operations whose NUMBER of operands the caller chooses —
# `add!`/`subtract!` over any number of sections, `map!` over any number of sources, `displace!` over any
# number of terms, `weighted_inner` over any tuple of weights. Each was written as one fused pass over
# all of its operands, which is right for the handful a solver passes and wrong above a count the
# compiler handles: `weighted_inner` with 32 weights failed to COMPILE on a device, and the others
# either allocated or fell off the specialized path. Each now works in fixed-size groups, and the
# property asserted here is that grouping is INVISIBLE — at counts well past the group size, and past
# Julia's 32-element tuple threshold, the result is bitwise the ungrouped left-to-right arithmetic.
#
# The oracle is raw-array arithmetic in the same association order, never another package call, except
# for `weighted_inner`, whose contract IS agreement with the single-weight call (decision 72).

using Test
using GBGPeriodicFields
using GBGPeriodicFields: field_data, point_values



# A map over six tensor inputs with no symmetry between its slots, so a source bound to the wrong slot
# changes the answer.
_six_tensor_map(A, B, C, D, E, F) = A * B + 2C - D * E + transpose(F)

# A zero-filled section like `section`, to write a result into: zeros rather than uninitialized, so a
# pass that silently wrote nothing cannot pass by reading back a stale value.
_zeroed(section) = (blank = _copied(section); fill!(field_data(blank), 0); blank)

# An independent copy of `section`, owning its own storage.
_copied(section::AbstractPointValues) = similar_point_values(section, copy(field_data(section)))
_copied(section) = similar_field(section, copy(field_data(section)))


@testset "caller-controlled counts beyond the group size (decision 88)" begin
  for T in (Float64, Float32)
    @testset "$T" begin
      grid = Grid3D((8, 8, 8), T.((2pi, 4pi, 6pi)))
      layout = RealFourierLayout()
      M = 97

      @testset "add!/subtract! over n sections is the left fold" begin
        for n in (9, 16, 17, 33, 64)
          physical = [VectorFieldPhysical(rand(T, 8, 8, 8, 3), grid, layout) for _ in 1:n]
          points = [VectorPointValues(rand(T, M, 3)) for _ in 1:n]
          for (bang, update!) in ((add!, (r, x) -> (r .+= x)), (subtract!, (r, x) -> (r .-= x)))
            for sections in (physical, points)
              reference = copy(field_data(sections[1]))
              foreach(s -> update!(reference, field_data(s)), sections[2:end])
              destination = _zeroed(sections[1])
              bang(destination, sections...)
              @test field_data(destination) == reference

              # The destination may be ANY operand, including one past the first group, which a
              # grouped pass would otherwise overwrite before the group that reads it.
              for position in unique((1, n ÷ 2, n))
                operands = [_copied(s) for s in sections]
                bang(operands[position], operands...)
                @test field_data(operands[position]) == reference
              end
            end
          end
          # The allocating operator folds the same way.
          sum_reference = copy(field_data(physical[1]))
          foreach(s -> sum_reference .+= field_data(s), physical[2:end])
          @test field_data(+(physical...)) == sum_reference
        end

        # Spectral representation: the same fold over complex coefficients.
        scalar_spec = ScalarFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(0))...), grid, layout)
        spectral = [similar_field(scalar_spec, Val(1)) for _ in 1:33]
        foreach(s -> field_data(s) .= rand(Complex{T}, size(field_data(s))), spectral)
        reference = copy(field_data(spectral[1]))
        foreach(s -> reference .+= field_data(s), spectral[2:end])
        destination = _zeroed(spectral[1])
        add!(destination, spectral...)
        @test field_data(destination) == reference
      end

      @testset "map! over six tensor sources" begin
        fields = [TensorFieldPhysical{2}(rand(T, 8, 8, 8, 3, 3), grid, layout) for _ in 1:6]
        values = [TensorPointValues(rand(T, M, 3, 3)) for _ in 1:6]
        for (sources, count) in ((fields, 8^3), (values, M))
          destination = _zeroed(sources[1])
          map!(_six_tensor_map, destination, sources...)
          raw = [reshape(field_data(s), count, 3, 3) for s in sources]
          result = reshape(field_data(destination), count, 3, 3)
          worst = zero(T)
          for p in 1:count
            fibers = [FiberTensor2{T}(r[p, :, :]) for r in raw]
            expected = _six_tensor_map(fibers...)
            worst = max(worst, maximum(abs, FiberTensor2{T}(result[p, :, :]) - expected))
          end
          @test worst <= 16 * eps(T)
          # The allocating form infers the same order and gives the same values.
          @test field_data(map(_six_tensor_map, sources...)) == field_data(destination)
        end
      end

      @testset "displace! over n terms, cover and torus, in place and destination/source" begin
        X0 = rand(T, M, 3) .* T(2pi)
        for n in (9, 20, 33)
          terms = Tuple((T(randn()), VectorPointValues(randn(T, M, 3))) for _ in 1:n)
          reference = copy(X0)
          for (c, v) in terms
            reference .+= c .* point_values(v)
          end
          wrapped = PointSet(copy(reference))
          wrap!(wrapped, grid)

          points = PointSet(copy(X0))
          displace!(points, terms...)
          @test point_positions(points) == reference

          destination, source = PointSet(zeros(T, M, 3)), PointSet(copy(X0))
          displace!(destination, source, terms...)
          @test point_positions(destination) == reference
          @test point_positions(source) == X0

          # On the torus the wrap is applied once, after the last group, so the result is the wrap
          # of the cover result — not a wrap per group, which would differ wherever an intermediate
          # position crossed the boundary and came back.
          points = PointSet(copy(X0))
          displace!(points, grid, terms...)
          @test point_positions(points) == point_positions(wrapped)

          destination = PointSet(zeros(T, M, 3))
          displace!(destination, source, grid, terms...)
          @test point_positions(destination) == point_positions(wrapped)
          @test point_positions(source) == X0
        end
      end

      @testset "weighted_inner over n weights agrees with each single call" begin
        physical = VectorFieldPhysical(rand(T, 8, 8, 8, 3), grid, layout)
        scalar_spec = ScalarFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(0))...), grid, layout)
        field = to_spectral(physical, FieldTransformPlans(physical, similar_field(scalar_spec, Val(1))))
        multipliers = FieldSpectralMultipliers(field)
        classes = (spectral_band(multipliers, T(1), T(2)),
                   assignment_window(multipliers),
                   materialize_kernel(spectral_cutoff(multipliers, T(3))),
                   convolve(spectral_cutoff(multipliers, T(3)), assignment_window(multipliers)))
        for n in (5, 8, 9, 33, 40)
          weights = ntuple(i -> classes[mod1(i, length(classes))], n)
          fused = weighted_inner(field, weights)
          @test fused isa NTuple{n, T}
          @test all(i -> fused[i] === weighted_inner(field, weights[i]), 1:n)
        end
        @test @inferred(weighted_inner(field, ntuple(i -> classes[mod1(i, 4)], 33))) isa NTuple{33, T}
      end
    end
  end
end
