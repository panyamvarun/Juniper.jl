include("basic/gamsworld.jl")
include("POD_experiment/blend029.jl")

@testset "parallel tests" begin

@testset "Batch.mod reliable parallel" begin
    println("==================================")
    println("BATCH.MOD reliable")
    println("==================================")

    m = batch_problem()

    juniper = DefaultTestSolver(
        branch_strategy=:Reliability,
        strong_restart = false,
        processors = 4,
        mip_solver = Cbc.CbcSolver(),
        incumbent_constr = true
    )

    JuMP.setsolver(m, juniper)
    status = JuMP.solve(m)
    @test status == :Optimal

    juniper_val = JuMP.getobjectivevalue(m)
    juniper_bb = JuMP.getobjbound(m)

    println("Solution by Juniper")
    println("obj: ", juniper_val)
    println("bound: ", juniper_bb)


    @test isapprox(juniper_val, 285506.5082, atol=opt_atol, rtol=opt_rtol)
end

@testset "Knapsack solution limit and table print test" begin
    println("==================================")
    println("Knapsack solution limit and table print test")
    println("==================================")

    juniper_one_solution = DefaultTestSolver(
        log_levels=[:Table],
        branch_strategy=:MostInfeasible,
        solution_limit=1,
        mip_solver=Cbc.CbcSolver(),
        processors = 3
    )

    m = JuMP.Model()
    v = [10,20,12,23,42]
    w = [12,45,12,22,21]
    JuMP.@variable(m, x[1:5], Bin)

    JuMP.@objective(m, Max, dot(v,x))

    JuMP.@NLconstraint(m, sum(w[i]*x[i]^2 for i=1:5) <= 45)

    JuMP.setsolver(m, juniper_one_solution)
    status = JuMP.solve(m)
    @test status == :UserLimit

    # maybe all three found a solution at the same time
    @test Juniper.getnsolutions(JuMP.internalmodel(m)) <= 3
    @test Juniper.getnsolutions(JuMP.internalmodel(m)) >= 1
end

@testset "Knapsack Max Reliable incumbent_constr" begin
    println("==================================")
    println("KNAPSACK Reliable incumbent_constr")
    println("==================================")

    m = JuMP.Model(solver=DefaultTestSolver(;branch_strategy=:MostInfeasible,
                                        incumbent_constr=true,processors=2))

    v = [10,20,12,23,42]
    w = [12,45,12,22,21]
    JuMP.@variable(m, x[1:5], Bin)

    JuMP.@objective(m, Max, dot(v,x))

    JuMP.@NLconstraint(m, sum(w[i]*x[i]^2 for i=1:5) <= 45)

    status = JuMP.solve(m)
    println("Obj: ", JuMP.getobjectivevalue(m))

    @test status == :Optimal
    @test isapprox(JuMP.getobjectivevalue(m), 65, atol=opt_atol)
    @test isapprox(JuMP.getobjectivebound(m), 65, atol=opt_atol)
    @test isapprox(JuMP.getvalue(x), [0,0,0,1,1], atol=sol_atol)
end


@testset "Batch.mod reliable parallel > processors" begin
    println("==================================")
    println("BATCH.MOD reliable more processors than available")
    println("==================================")

    m = batch_problem()

    juniper = DefaultTestSolver(
        branch_strategy=:Reliability,
        strong_restart = false,
        processors = 10
    )

    JuMP.setsolver(m, juniper)
    status = JuMP.solve(m)
    @test status == :Optimal

    juniper_val = JuMP.getobjectivevalue(m)
    juniper_bb = JuMP.getobjbound(m)

    println("Solution by Juniper")
    println("obj: ", juniper_val)
    println("bound: ", juniper_bb)

    im = JuMP.internalmodel(m)
    # must have changed to 4 processors
    @test im.options.processors == 4
    @test isapprox(juniper_val, 285506.5082, atol=opt_atol, rtol=opt_rtol)
end

@testset "Batch.mod no restart parallel" begin
    println("==================================")
    println("BATCH.MOD NO RESTART")
    println("==================================")

    m = batch_problem()

    juniper = DefaultTestSolver(
        branch_strategy=:StrongPseudoCost,
        strong_restart = false,
        processors = 4
    )

    JuMP.setsolver(m, juniper)
    status = JuMP.solve(m)
    @test status == :Optimal

    juniper_val = JuMP.getobjectivevalue(m)
    juniper_bb = JuMP.getobjbound(m)

    println("Solution by Juniper")
    println("obj: ", juniper_val)
    println("bound: ", juniper_bb)


    @test isapprox(juniper_val, 285506.5082, atol=opt_atol, rtol=opt_rtol)
end

@testset "Knapsack 100% limit" begin
    println("==================================")
    println("KNAPSACK 100%")
    println("==================================")

    m = JuMP.Model(solver=DefaultTestSolver(;processors=2,traverse_strategy=:DBFS,mip_gap=100,
              branch_strategy=:MostInfeasible))

    v = [10,20,12,23,42]
    w = [12,45,12,22,21]
    JuMP.@variable(m, x[1:5], Bin)

    JuMP.@objective(m, Max, dot(v,x))

    JuMP.@NLconstraint(m, sum(w[i]*x[i]^2 for i=1:5) <= 45)

    status = JuMP.solve(m)
    objval = JuMP.getobjectivevalue(m)
    println("Obj: ", objval)
    best_bound_val = JuMP.getobjbound(m)
    gap_val = JuMP.getobjgap(m)
    println("bb: ", JuMP.getobjbound(m))

    @test status == :UserLimit

    @test best_bound_val >= objval
    @test 0.01 <= gap_val <= 1 || Juniper.getnsolutions(JuMP.internalmodel(m)) == 1
end

#=
# remove for test stability
@testset "blend029" begin
    println("==================================")
    println("blend029")
    println("==================================")

    m,objval = get_blend029()

    JuMP.setsolver(m, DefaultTestSolver(
            branch_strategy=:StrongPseudoCost,
            strong_branching_perc = 50,
            strong_branching_nsteps = 5,
            strong_restart = true,
            processors = 4,
            debug = true,
            debug_write = true
    ))
    status = JuMP.solve(m)

    @test status == :Optimal

    juniper_val = JuMP.getobjectivevalue(m)
    best_bound_val = JuMP.getobjbound(m)
    gap_val = JuMP.getobjgap(m)

    println("Solution by Juniper")
    println("obj: ", juniper_val)
    println("best_bound_val: ", best_bound_val)
    println("gap_val: ", gap_val)

    @test isapprox(juniper_val, objval, atol=1e0)
    @test isapprox(best_bound_val, objval, atol=1e0)
    @test isapprox(gap_val, 0, atol=1e-2)
end
=#

@testset "bruteforce" begin
    println("==================================")
    println("Bruteforce")
    println("==================================")
    juniper_all_solutions = DefaultTestSolver(
        branch_strategy=:StrongPseudoCost,
        all_solutions = true,
        list_of_solutions = true,
        strong_restart = true,
        processors = 3,
        debug = true
    )

    m = JuMP.Model(solver=juniper_all_solutions)

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

    status = JuMP.solve(m)

    debugDict = JuMP.internalmodel(m).debugDict
    list_of_solutions = Juniper.getsolutions(JuMP.internalmodel(m))
    @test length(unique(list_of_solutions)) == Juniper.getnsolutions(JuMP.internalmodel(m))

    @test status == :Optimal
    @test Juniper.getnsolutions(JuMP.internalmodel(m)) == 24

    @test getnstate(debugDict,:Integral) == 24
    @test different_hashes(debugDict) == true
    counter_test(debugDict,Juniper.getnbranches(JuMP.internalmodel(m)))
end

@testset "bruteforce fake parallel vs sequential" begin
    println("==================================")
    println("Bruteforce fake parallel vs sequential")
    println("==================================")
    juniper_all_solutions = DefaultTestSolver(
        branch_strategy=:PseudoCost,
        all_solutions = true,
        list_of_solutions = true,
        strong_restart = false,
        processors = 1
    )

    juniper_all_solutions_p = DefaultTestSolver(
        branch_strategy=:PseudoCost,
        all_solutions = true,
        list_of_solutions = true,
        strong_restart = false,
        processors = 1,
        force_parallel = true # just for testing this goes into the parallel branch (using driver + 1)
    )

    m = JuMP.Model(solver=juniper_all_solutions)

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

    status = JuMP.solve(m)
    nbranches = Juniper.getnbranches(JuMP.internalmodel(m))

    JuMP.setsolver(m, juniper_all_solutions_p)

    status = JuMP.solve(m)
    @test Juniper.getnbranches(JuMP.internalmodel(m)) == nbranches
end


@testset "bruteforce PseudoCost" begin
    println("==================================")
    println("Bruteforce PseudoCost")
    println("==================================")
    juniper_all_solutions = DefaultTestSolver(
        branch_strategy=:PseudoCost,
        all_solutions = true,
        list_of_solutions = true,
        strong_restart = true,
        processors = 3
    )

    m = JuMP.Model(solver=juniper_all_solutions)

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

    status = JuMP.solve(m)
    println("Status: ", status)
    list_of_solutions = Juniper.getsolutions(JuMP.internalmodel(m))
    @test length(unique(list_of_solutions)) == Juniper.getnsolutions(JuMP.internalmodel(m))

    @test status == :Optimal
    @test Juniper.getnsolutions(JuMP.internalmodel(m)) == 24
end


#=
# remove for cross platform stability
@testset "time limit 5s" begin
    println("==================================")
    println("time imit 5s")
    println("==================================")
    juniper_all_solutions = DefaultTestSolver(
        branch_strategy=:PseudoCost,
        strong_restart = true,
        processors = 3,
        time_limit = 5
    )

    m,objval = get_blend029()
    JuMP.setsolver(m, juniper_all_solutions)

    status = JuMP.solve(m)
    println("Status: ", status)

    @test status == :UserLimit
    @test JuMP.getsolvetime(m) <= 13 # some seconds more are allowed
end
=#

@testset "infeasible cos" begin
    println("==================================")
    println("Infeasible cos")
    println("==================================")
    m = JuMP.Model(solver=DefaultTestSolver(
        branch_strategy=:StrongPseudoCost,
        processors = 2
    ))

    JuMP.@variable(m, 1 <= x <= 5, Int)
    JuMP.@variable(m, -2 <= y <= 2, Int)

    JuMP.@objective(m, Min, -x-y)

    JuMP.@NLconstraint(m, y==2*cos(2*x))

    status = JuMP.solve(m)
    println("Status: ", status)

    @test status == :Infeasible
end

@testset "infeasible relaxation" begin
    println("==================================")
    println("Infeasible relaxation")
    println("==================================")
    m = JuMP.Model(solver=DefaultTestSolver(
        branch_strategy=:StrongPseudoCost,
        processors = 2
    ))

    JuMP.@variable(m, 0 <= x[1:10] <= 2, Int)

    JuMP.@objective(m, Min, sum(x))

    JuMP.@constraint(m, sum(x[1:5]) <= 20)
    JuMP.@NLconstraint(m, x[1]*x[2]*x[3] >= 10)

    status = JuMP.solve(m)
    println("Status: ", status)

    @test status == :Infeasible
end

@testset "infeasible integer" begin
    println("==================================")
    println("Infeasible integer")
    println("==================================")
    m = JuMP.Model(solver=DefaultTestSolver(
        branch_strategy=:StrongPseudoCost,
        processors = 2
    ))

    JuMP.@variable(m, 0 <= x[1:10] <= 2, Int)

    JuMP.@objective(m, Min, sum(x))

    JuMP.@constraint(m, sum(x[1:5]) <= 20)
    JuMP.@NLconstraint(m, x[1]*x[2]*x[3] >= 7)
    JuMP.@NLconstraint(m, x[1]*x[2]*x[3] <= 7.5)

    status = JuMP.solve(m)
    println("Status: ", status)

    @test status == :Infeasible
end

@testset "infeasible in strong" begin
    println("==================================")
    println("Infeasible in strong")
    println("==================================")
    m = JuMP.Model(solver=DefaultTestSolver(
        branch_strategy=:StrongPseudoCost,
        processors = 2
    ))

    JuMP.@variable(m, 0 <= x[1:5] <= 2, Int)

    JuMP.@objective(m, Min, sum(x))

    JuMP.@NLconstraint(m, x[3]^2 <= 2)
    JuMP.@NLconstraint(m, x[3]^2 >= 1.2)

    status = JuMP.solve(m)
    println("Status: ", status)

    @test status == :Infeasible
end

end