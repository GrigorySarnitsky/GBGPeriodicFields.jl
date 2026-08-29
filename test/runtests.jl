# Test suite entry point for GBGPeriodicFields.
#
# Each module's tests live in their own file. Each file is included into its own
# wrapper module so that top-level test helpers (comp, plans_for, grid, ...) and
# constants don't collide across files. Every file is also runnable on its own:
#   julia --project=. test/<module>.jl

module FieldsTests;                include("fields.jl");                end
module FieldAlgebraTests;          include("fieldalgebra.jl");          end
module MetadataSweepTests;         include("metadata_sweep.jl");        end
module AdaptTests;                 include("adapt.jl");                 end
module GeneratedAnalyticTests;     include("generated_analytic.jl");    end
module OracleRegistryTests;        include("oracle_registry.jl");      end
module ResultsFormatTests;         include("results_format.jl");     end
module ContractTests;              include("contracts.jl");          end
module ContextMatrixTests;         include("context_matrix.jl");    end
module ContextEntryTests;          include("context_entrypoints.jl"); end
module PeerRejectionTests;         include("peer_rejections.jl");    end
module AbsenceGateTests;           include("absence_gate.jl");       end
module DifferentialOperatorsTests; include("differentialoperators.jl"); end
module ConvolutionTests;           include("convolution.jl");           end
module InterpolationTests;         include("interpolation.jl");         end
module PointValuesAlgebraTests;    include("pointvalues_algebra.jl");   end
module DisplacementTests;          include("displacement.jl");          end
module InterpolationTransferTests; include("interpolation_transfer.jl"); end
module SpectralTransferTests;      include("transfer_spectral.jl");     end
module ReductionsTests;            include("reductions.jl");            end
module RDFTests;                   include("rdf.jl");                   end
module EltypeGenericityTests;      include("eltype_genericity.jl");     end
module AdjointnessTests;           include("adjointness.jl");           end
module RandomizedTests;            include("randomized.jl");            end
module AllocationsTests;           include("allocations.jl");           end
module PassAuditTests;             include("pass_audit.jl");            end
module ThreadingTests;             include("threading.jl");             end
module MethodParityTests;          include("method_parity.jl");         end
module AquaTests;                  include("aqua.jl");                  end
module JETTests;                   include("jet.jl");                   end
module HDF5Tests;                  include("hdf5.jl");                  end

# Promoted witnesses from /bug-hunt (see test/regressions/README.md). Each began as a test written
# before its fix and observed to FAIL on the tree that had the defect, and is included here unchanged
# so the test that proves the fix is the one that proved the bug. The directory is empty until the
# first confirmed finding; the loop is deliberately written to tolerate that rather than to require a
# placeholder, because an empty regression suite is an honest state and a fake entry is not.
for regression_file in sort(filter(name -> endswith(name, ".jl"),
                                   readdir(joinpath(@__DIR__, "regressions"); join = false)))
  @eval module $(Symbol("Regression_", replace(regression_file[1:end-3], '-' => '_')))
    include(joinpath(@__DIR__, "regressions", $regression_file))
  end
end
