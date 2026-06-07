# Test suite entry point for GBGPeriodicFields.
#
# Coverage is built up module by module as the refactor progresses: each verified
# module gets its own file, included here and also runnable on its own with
#   julia --project=. test/<module>.jl
#
# As FieldAlgebra and DifferentialOperators are verified, add their files below.

include("fields.jl")
