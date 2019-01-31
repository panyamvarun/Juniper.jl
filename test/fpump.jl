import Distributed: nworkers

#include("POD_experiment/blend029.jl")
include("POD_experiment/tspn05.jl")
#include("POD_experiment/ndcc12persp.jl")
include("POD_experiment/FLay02H.jl")
include("basic/gamsworld.jl")

@testset "fp tests" begin

#=
# omit for test speed
@testset "FP: blend029" begin
    println("==================================")
    println("FP: blend029")
    println("==================================")

    m,objval = get_blend029()

    JuMP.setsolver(m, DefaultTestSolver(
            branch_strategy=:MostInfeasible,
            time_limit = 5,
            mip_solver=Cbc.CbcSolver(),
            incumbent_constr = true
    ))
    status = JuMP.solve(m)

    @test Juniper.getnsolutions(JuMP.internalmodel(m)) >= 1
end
=#

#=
# seems to be a copy of blend029
@testset "FP: cvxnonsep_nsig20r_problem" begin
    println("==================================")
    println("FP: cvxnonsep_nsig20r_problem")
    println("==================================")

    m,objval = get_blend029()

    JuMP.setsolver(m, DefaultTestSolver(
            branch_strategy=:MostInfeasible,
            feasibility_pump = true,
            time_limit = 1,
            mip_solver=Cbc.CbcSolver()
    ))
    status = JuMP.solve(m)

    @test Juniper.getnsolutions(JuMP.internalmodel(m)) >= 1
end
=#

@testset "FP: no linear" begin
    println("==================================")
    println("FP: no linear")
    println("==================================")

    m = JuMP.Model()
    JuMP.@variable(m, x[1:10], Bin)
    JuMP.@NLconstraint(m, x[1]^2+x[2]^2 == 0)
    JuMP.@objective(m, Max, sum(x))

    JuMP.setsolver(m, DefaultTestSolver(
            branch_strategy=:MostInfeasible,
            feasibility_pump = true,
            time_limit = 1,
            mip_solver=Cbc.CbcSolver()
    ))
    status = JuMP.solve(m)

    @test Juniper.getnsolutions(JuMP.internalmodel(m)) >= 1
end

@testset "FP: Integer test" begin
    println("==================================")
    println("FP: Integer Test")
    println("==================================")
    m = JuMP.Model()

    JuMP.@variable(m, 1 <= x[1:4] <= 5, Int)

    JuMP.@objective(m, Min, x[1])

    JuMP.@constraint(m, x[1] >= 0.9)
    JuMP.@constraint(m, x[1] <= 1.1)
    JuMP.@NLconstraint(m, (x[1]-x[2])^2 >= 0.1)
    JuMP.@NLconstraint(m, (x[2]-x[3])^2 >= 0.1)
    JuMP.@NLconstraint(m, (x[1]-x[3])^2 >= 0.1)
    JuMP.@NLconstraint(m, (x[1]-x[4])^2 >= 0.1)
    JuMP.@NLconstraint(m, (x[2]-x[4])^2 >= 0.1)
    JuMP.@NLconstraint(m, (x[3]-x[4])^2 >= 0.1)

    JuMP.setsolver(m, DefaultTestSolver(
        branch_strategy=:MostInfeasible,
        feasibility_pump = true,
        time_limit = 1,
        mip_solver=Cbc.CbcSolver()
    ))

    status = JuMP.solve(m)
    @test Juniper.getnsolutions(JuMP.internalmodel(m)) >= 1
end

@testset "FP: Integer test2" begin
    println("==================================")
    println("FP: Integer Test 2")
    println("==================================")
    m = JuMP.Model()

    JuMP.@variable(m, 0 <= x <= 10, Int)
    JuMP.@variable(m, y >= 0)
    JuMP.@variable(m, 0 <= u <= 10, Int)
    JuMP.@variable(m, w == 1)

    JuMP.@objective(m, Min, -3x - y)

    JuMP.@constraint(m, 3x + 10 <= 20)
    JuMP.@NLconstraint(m, y^2 <= u*w)
    JuMP.@NLconstraint(m, x^2 >= u*w)

    JuMP.setsolver(m, DefaultTestSolver(
        branch_strategy=:MostInfeasible,
        feasibility_pump = true,
        time_limit = 1,
        mip_solver=Cbc.CbcSolver()
    ))

    status = JuMP.solve(m)
    @test Juniper.getnsolutions(JuMP.internalmodel(m)) >= 1
end

@testset "FP: infeasible cos" begin
    println("==================================")
    println("FP: Infeasible cos")
    println("==================================")
    m = JuMP.Model()

    JuMP.@variable(m, 1 <= x <= 5, Int)
    JuMP.@variable(m, -2 <= y <= 2, Int)

    JuMP.@objective(m, Min, -x-y)

    JuMP.@NLconstraint(m, y==2*cos(2*x))

    JuMP.setsolver(m, DefaultTestSolver(
        branch_strategy=:MostInfeasible,
        feasibility_pump = true,
        time_limit = 1,
        mip_solver=Cbc.CbcSolver()
    ))

    status = JuMP.solve(m)
    println("Status: ", status)

    @test status == :Infeasible
    @test Juniper.getnsolutions(JuMP.internalmodel(m)) == 0
end

@testset "FP: tspn05" begin
    println("==================================")
    println("FP: tspn05")
    println("==================================")

    m = get_tspn05()

    JuMP.setsolver(m, DefaultTestSolver(
            branch_strategy=:StrongPseudoCost,
            feasibility_pump = true,
            mip_solver=Cbc.CbcSolver()
    ))
    status = JuMP.solve(m)

    @test status == :Optimal
    @test isapprox(JuMP.getobjectivevalue(m),191.2541,atol=1e0)
end


#=
# omit for test speed
@testset "FP: ndcc12persp" begin
    println("==================================")
    println("FP: ndcc12persp")
    println("==================================")

    # This probably has a "NLP couldn't be solved to optimality" warning in FPump
    m = get_ndcc12persp()

    JuMP.setsolver(m, DefaultTestSolver(
            branch_strategy=:StrongPseudoCost,
            feasibility_pump = true,
            mip_solver=Cbc.CbcSolver(),
            time_limit = 10,
    ))
    status = JuMP.solve(m)

    @test status == :Optimal || status == :UserLimit
end
=#

@testset "FP: FLay02H" begin
    println("==================================")
    println("FP: FLay02H")
    println("==================================")

    # This probably needs a restart in real nlp
    m = get_FLay02H()

    JuMP.setsolver(m, DefaultTestSolver(
            branch_strategy=:StrongPseudoCost,
            feasibility_pump = true,
            feasibility_pump_time_limit = 10,
            time_limit = 10,
            mip_solver=Cbc.CbcSolver()
    ))
    status = JuMP.solve(m)

    @test status == :Optimal || status == :UserLimit
    @test Juniper.getnsolutions(JuMP.internalmodel(m)) >= 1
end

end