# The A/B behind PERFORMANCE.md finding (am): decision 78's walk on the width-8 CPU scatter.
#
#   julia --startup-file=no --project=. -tN benchmark/study_walk_scatter.jl     # AB_N=512 default
#
# It deliberately bypasses the benchmark GROUP. The archive step that first flagged this row is not
# admissible on its own, because decision 78 added seven rows to that group — three allocating 512^3
# vector fields — so ~3 GB more sits live while the row runs, and a neighbour can move with no kernel
# changing. This builds one scalar field and one point set, times the verb directly, and is meant to
# be run byte-identical in both arms (a worktree at 7bbbc75a is the old one), interleaved A-B-A-B.
using Random
using GBGPeriodicFields
const N = parse(Int, get(ENV, "AB_N", "512"))
const T = Float64
grid = Grid3D((N,N,N), (T(2π), T(2π), T(2π)))
field = ScalarFieldPhysical(Array, grid)
copyto!(field_data(field), randn(T, N, N, N))
Random.seed!(20260901)
M = N^3 ÷ 27
points = PointSet(T(2π) .* rand(T, M, 3))
q = ScalarPointValues(rand(T, M))
scheme = LalescuSpline(3,3)
anterpolate!(field, points, q, scheme, T(1), T(0))          # warm
best = Inf
for _ in 1:3
  t = @elapsed anterpolate!(field, points, q, scheme, T(1), T(0))
  global best = min(best, t)
end
println("anterpolate! Lalescu(3,3) | Float64 $(N)^3 | threads=$(Threads.nthreads()) : $(round(best*1000, digits=1)) ms")
