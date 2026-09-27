# Shared benchmark builders, parameterised by the device array type `AT` (`Array` on CPU,
# `ROCArray`/`CuArray` on GPU) — exactly how `test/gpu/suite.jl` takes `to_device`. Random data
# (values are irrelevant to timing). `bench_sync` lets BenchmarkTools time GPU work to completion.
# Included by benchmarks.jl (which carries the `using`s).

const LAYOUT = RealFourierLayout()

# Default parameter grid: modest sizes for repeatable, regression-sensitive tracking. A larger
# characterisation sweep (256³/512³) is runnable by passing `sizes = (...)` to `build_suite`.
const TYPES = (Float64, Float32)
const SIZES = (64, 128)

make_grid(::Type{T}, N) where {T} = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))

scalar_phys(AT, ::Type{T}, grid) where {T} = ScalarFieldPhysical(AT(rand(T, grid.grid_size...)), grid)
vector_phys(AT, ::Type{T}, grid) where {T} = VectorFieldPhysical(AT(rand(T, grid.grid_size..., 3)), grid)
tensor_phys(AT, ::Type{T}, grid) where {T} = TensorFieldPhysical{2}(AT(rand(T, grid.grid_size..., 3, 3)), grid)

specshape(grid, R) = field_spectral_shape(grid, LAYOUT, Val(R))
scalar_spec(AT, ::Type{T}, grid) where {T} = ScalarFieldSpectral(AT(rand(Complex{T}, specshape(grid, 0)...)), grid)
vector_spec(AT, ::Type{T}, grid) where {T} = VectorFieldSpectral(AT(rand(Complex{T}, specshape(grid, 1)...)), grid)
tensor_spec(AT, ::Type{T}, grid) where {T} = TensorFieldSpectral{2}(AT(rand(Complex{T}, specshape(grid, 2)...)), grid)

# Forward + inverse plans matching a physical field's tensor order.
function plans_for(phys, AT, ::Type{T}, grid) where {T}
  R = field_tensor_order(phys)
  spec = R == 0 ? scalar_spec(AT, T, grid) : R == 1 ? vector_spec(AT, T, grid) : tensor_spec(AT, T, grid)
  return FieldTransformPlans(phys, spec)
end

# Point set at ~1 particle / 27 cells, coordinates in [0, 2π) on the device.
function point_setup(AT, ::Type{T}, grid) where {T}
  npart = prod(grid.grid_size) ÷ 27
  return PointSet(AT(T(2π) .* rand(T, npart, 3))), ScalarPointValues(AT(rand(T, npart))), npart
end

# Call `f` with the elements of `arguments` as separate arguments, written out with a literal index
# each. A splat of more than 32 values allocates at the call site, before the package is entered, so
# the operand-count rows (decision 88) would time the benchmark's own call rather than the operation.
@generated bench_call(f, arguments::Tuple) =
  Expr(:call, :f, (:(arguments[$i]) for i in 1:fieldcount(arguments))...)

# Block on the device so BenchmarkTools times to completion (no-op on the CPU backend).
bench_sync(x::AbstractArray) = synchronize(get_backend(x))
