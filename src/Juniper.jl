module Juniper

import JuMP
using JuMP: @variable, @constraint, @objective, Model, with_optimizer
using JSON

using MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities

# functions
const SVF = MOI.SingleVariable
const SAF = MOI.ScalarAffineFunction{Float64}
const SQF = MOI.ScalarQuadraticFunction{Float64}
const VECTOR = MOI.VectorOfVariables

if VERSION < v"0.7.0-"
    import Compat: occursin
    import Compat: Nothing
    import Compat: round
    import Compat: @warn
    import Compat: pushfirst!
    import Compat: popfirst!
    import Compat: Array
    import Compat: undef
    import Compat: hasmethod
    import Compat: findall
end

if VERSION > v"0.7.0-"
    using LinearAlgebra
    using Random
    using Distributed
    using Statistics
end



include("types.jl")

function Base.show(io::IO, opts::SolverOptions)
    longest_field_name = maximum([length(string(fname)) for fname in fieldnames(SolverOptions)])+2
    for name in fieldnames(SolverOptions)
        sname = string(name)
        pname = sname*repeat(" ", longest_field_name-length(sname))
        if getfield(opts,name) == nothing
            println(io, pname, ": NA")
        else
            println(io, pname, ": ", getfield(opts,name))
        end
    end
end

include("util.jl")
include("printing.jl")
include("solver.jl")
include("model.jl")
include("BnBTree.jl")
include("MOI_wrapper/MOI_wrapper.jl")

end
