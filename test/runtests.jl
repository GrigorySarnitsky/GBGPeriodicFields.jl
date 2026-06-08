# Test suite entry point for GBGPeriodicFields.
#
# Each module's tests live in their own file. Each file is included into its own
# wrapper module so that top-level test helpers (comp, plans_for, grid, ...) and
# constants don't collide across files. Every file is also runnable on its own:
#   julia --project=. test/<module>.jl

module FieldsTests;                include("fields.jl");                end
module FieldAlgebraTests;          include("fieldalgebra.jl");          end
module DifferentialOperatorsTests; include("differentialoperators.jl"); end
module EltypeGenericityTests;      include("eltype_genericity.jl");     end
module MethodParityTests;          include("method_parity.jl");         end
module AquaTests;                  include("aqua.jl");                  end
