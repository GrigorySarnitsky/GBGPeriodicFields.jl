# Claims I verified myself against the source (2026-09-16), so they are not second-hand

1. `_parseval_weight` (src/Reductions.jl:946-953): `folded_length = size(field_data(f), folded_dimension)`
   — the LOCAL storage extent — then `weight_host[1] = 1` and `weight_host[folded_length] = 1`.
   Split the folded axis and EVERY rank weights its own first and last local plane as self-conjugate:
   2(P-1) planes wrongly counted once instead of twice, a systematic bias in every spectral `inner`,
   `l2norm`, `weighted_inner` and the shell spectrum. (The `iseven` test beside it already reads the
   GLOBAL `grid_size` — the test is right, the index is not.) CONFIRMS the layout flip.

2. Transfer stride (src/Interpolation.jl:1145-1147 → kernel :974): the launch passes
   `prod(grid.grid_size)` (GLOBAL) as `points_per_fibre` and the kernel computes
   `number_of_fibres = length(field_values) ÷ points_per_fibre`. With local storage 3N^3/P against a
   global divisor N^3 this is floor(3/P) = 0 for P > 3: the fibre loop never runs and `interpolate!`
   returns its destination UNTOUCHED. Created by the "grid global, storage local" ruling itself.

3. Function-initialized constructors (src/Fields.jl:467-479; vector twin :612-627): allocate
   `field_physical_shape(grid, Val(0))` (local) but loop `1:grid.grid_size[d]` (global) and offset from
   the global origin ⇒ out-of-bounds write and wrong coordinates on every rank.

4. `run!` (IT src/SimulationRun.jl:1100-1109): `keep = callback(sim); keep || break` — an arbitrary user
   predicate gates `advance!`, which is full of collectives. Rank-divergent ⇒ hang. This, not "a collective
   inside an if", is the real deadlock surface.

5. Forcing RNG (IT src/Forcing.jl:902): `randn!(ou.rng, field_data(noise_physical))` INSIDE the hot loop,
   followed at :906 by `inner(noise_spectral, noise_spectral)`. Under SPMD every rank draws the same
   stream ⇒ each slab gets identical noise ⇒ slab-periodic forcing, and band-pass + Leray + variance
   normalisation make it look correct.

6. IT's recorded resolutions: 128^3 (x18), 256^3 (x16), 384^3 (x2) across docs/, src/ and test/.
   NOTHING above 384^3. 512^3 Float64 is ~27 GiB against one GH200's 96 GiB.
