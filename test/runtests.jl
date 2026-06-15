# Test suite entry point for GBGPeriodicFields.
#
# Each module's tests live in their own file. Each file is included into its own
# wrapper module so that top-level test helpers (comp, plans_for, grid, ...) and
# constants don't collide across files. Every file is also runnable on its own:
#   julia --project=. test/<module>.jl

module FieldsTests;                include("fields.jl");                end
module FieldAlgebraTests;          include("fieldalgebra.jl");          end
module DifferentialOperatorsTests; include("differentialoperators.jl"); end
module ConvolutionTests;           include("convolution.jl");           end
module InterpolationTests;         include("interpolation.jl");         end
module PointValuesAlgebraTests;    include("pointvalues_algebra.jl");   end
module InterpolationTransferTests; include("interpolation_transfer.jl"); end
module SpectralTransferTests;      include("transfer_spectral.jl");     end
module ReductionsTests;            include("reductions.jl");            end
module RDFTests;                   include("rdf.jl");                   end
module EltypeGenericityTests;      include("eltype_genericity.jl");     end
module AdjointnessTests;           include("adjointness.jl");           end
module RandomizedTests;            include("randomized.jl");            end
module AllocationsTests;           include("allocations.jl");           end
module ThreadingTests;             include("threading.jl");             end
module MethodParityTests;          include("method_parity.jl");         end
module AquaTests;                  include("aqua.jl");                  end
module JETTests;                   include("jet.jl");                   end
