# Storage-family moves: `adapt` between host and device (decision 63). This is the one class whose
# cost is a BUS transfer rather than arithmetic — it is bounded by the link, not by the card, so it
# does not scale with the device's bandwidth and belongs beside the operations rather than inside any
# of them.
#
# The class is DEVICE-ONLY, and deliberately empty on a CPU lane. `adapt(Array, host_field)` is the
# identity: it returns its argument, sharing storage, so a CPU row would time a no-op and report a few
# nanoseconds as though a transfer had happened. An empty class is the honest reading — on a host lane
# there is no second family to move to.
#
# Both directions are swept because they are not symmetric on any real link, and the companions are
# swept beside the field because a moved field alone computes nothing: invariant 14 requires the
# multipliers to match, and `FieldTransformPlans` is not a transfer at all but a PLANNING pass, whose
# cost is of a different kind and is the reason it gets its own row rather than being folded in.

function add_storage!(group, AT, ::Type{T}, grid, tag) where {T}
  # No second storage family on a host lane, so nothing to measure. See the note above.
  AT === Array && return

  host_scalar = ScalarFieldPhysical(rand(T, grid.grid_size...), grid)
  host_vector = VectorFieldPhysical(rand(T, grid.grid_size..., 3), grid)
  device_scalar = adapt(AT, host_scalar)
  device_vector = adapt(AT, host_vector)

  # The transfer itself, both ways. `bench_sync` forces completion so the copy is timed rather than
  # its enqueue; a host-bound result needs no sync, the copy being synchronous on arrival.
  group["adapt to device scalar | $tag"] =
    @benchmarkable (moved = adapt($AT, $host_scalar); bench_sync(field_data(moved)))
  group["adapt to device vector | $tag"] =
    @benchmarkable (moved = adapt($AT, $host_vector); bench_sync(field_data(moved)))
  group["adapt to host scalar | $tag"]   = @benchmarkable adapt(Array, $device_scalar)
  group["adapt to host vector | $tag"]   = @benchmarkable adapt(Array, $device_vector)

  # Adapting to the family one already occupies is the identity. Swept so that the asymmetry is
  # visible in the table rather than only in prose: this row should be a handful of nanoseconds, and
  # if it ever reads like a transfer, the identity has been lost.
  group["adapt to own family (identity) | $tag"] = @benchmarkable adapt($AT, $device_scalar)
  # The in-place move (decision 69), placed beside the allocating rows above because the COMPARISON is
  # the point: finding (x) measured the return trip at a quarter of the outbound rate and attributed
  # the gap to allocating the destination, so these rows are what confirms or refutes that.
  into_device_scalar = similar_field(device_scalar, Val(0))
  into_device_vector = similar_field(device_vector, Val(1))
  into_host_scalar   = similar_field(host_scalar, Val(0))
  into_host_vector   = similar_field(host_vector, Val(1))
  group["adapt! to device scalar | $tag"] = @benchmarkable (adapt!($into_device_scalar, $host_scalar); bench_sync(field_data($into_device_scalar)))
  group["adapt! to device vector | $tag"] = @benchmarkable (adapt!($into_device_vector, $host_vector); bench_sync(field_data($into_device_vector)))
  group["adapt! to host scalar | $tag"]   = @benchmarkable adapt!($into_host_scalar, $device_scalar)
  group["adapt! to host vector | $tag"]   = @benchmarkable adapt!($into_host_vector, $device_vector)

  # The companions. Multipliers are six O(N) axis vectors, so this is a small transfer whose cost is
  # dominated by per-call latency rather than volume — the contrast with the field rows is the point.
  host_spectral = ScalarFieldSpectral(rand(Complex{T}, specshape(grid, 0)...), grid)
  host_multipliers = FieldSpectralMultipliers(host_spectral)
  group["adapt multipliers | $tag"] = @benchmarkable adapt($AT, $host_multipliers)

  # Not a transfer: a rebuild. The plans allocate their own witnesses on the target, plan against
  # them, and release them, so this row prices a planning pass on the device.
  host_plans = FieldTransformPlans(host_scalar, host_spectral)
  group["adapt plans (rebuild) | $tag"] = @benchmarkable adapt($AT, $host_plans)
end
