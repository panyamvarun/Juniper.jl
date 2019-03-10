include("table_log.jl")
include("bb_inits_and_defaults.jl")
include("bb_strategies.jl")
include("bb_user_limits.jl")
include("bb_type_correct.jl")
include("bb_integral_or_branch.jl")
include("bb_gains.jl")

"""
    get_branching_disc_idx!(m, step_obj, opts, disc2var_idx, gains, counter::Int64=1)

Get the index of a variable to branch on.
"""
function get_branching_disc_idx!(m, step_obj, opts, disc2var_idx, gains, counter::Int64=1)
    start = time()
    node = step_obj.node
    idx = 0
    strong_restarts = 0
    branch_strat = opts.branch_strategy
    status = :Normal
    if branch_strat == :MostInfeasible
        idx = branch_mostinfeasible(m, node, disc2var_idx)
    elseif branch_strat == :PseudoCost || branch_strat == :StrongPseudoCost
        if counter == 1 && branch_strat == :PseudoCost
            idx = branch_mostinfeasible(m, node, disc2var_idx)
        elseif counter <= opts.strong_branching_nsteps && branch_strat == :StrongPseudoCost
            status, idx, strong_restarts = branch_strong!(m, opts, disc2var_idx, step_obj, counter)
        else
            idx = branch_pseudo(m, node, disc2var_idx, gains, opts.gain_mu, opts.atol)
        end
    elseif branch_strat == :Reliability
        status, idx, strong_restarts = branch_reliable!(m,opts,step_obj,disc2var_idx,gains,counter)
    end
    step_obj.state = status
    step_obj.var_idx = idx
    step_obj.nrestarts = strong_restarts
    step_obj.idx_time = time()-start
    return
end

"""
    process_node!(m, step_obj, cnode, disc2var_idx, temp)

Solve a child node `cnode` by relaxation.
Set the state and best_bound property.
Push integrals and new branch nodes to the step object
Return state
"""
function process_node!(m, step_obj, cnode, disc2var_idx, temp)
     # set bounds
    for i=1:m.num_var
        JuMP.setlowerbound(m.x[i], cnode.l_var[i])
        JuMP.setupperbound(m.x[i], cnode.u_var[i])
    end
    setvalue(m.x[1:m.num_var],step_obj.node.solution)

    if occursin("Ipopt", string(m.nl_solver))
        overwritten = false
        old_mu_init = 0.1 # default value in Ipopt
        for i=1:length(m.nl_solver.options)
            if m.nl_solver.options[i][1] == :mu_init
                old_mu_init = m.nl_solver.options[i][2]
                m.nl_solver.options[i] = (:mu_init, 1e-5)
                overwritten = true
                break
            end
        end
        if !overwritten
            push!(m.nl_solver.options, (:mu_init, 1e-5))
        end
    end
    status = JuMP.solve(m.model, suppress_warnings=true)

    # reset mu_init
    if occursin("Ipopt", string(m.nl_solver))
        for i=1:length(m.nl_solver.options)
            if m.nl_solver.options[i][1] == :mu_init
                m.nl_solver.options[i] = (:mu_init, old_mu_init)
                break
            end
        end
    end

    objval = getobjectivevalue(m.model)
    cnode.solution = getvalue(m.x)
    cnode.relaxation_state = status
    if status == :Error
        cnode.state = :Error
    elseif status == :Optimal
        cnode.best_bound = objval
        set_cnode_state!(cnode, m, step_obj, disc2var_idx)
        if !temp
            push_integral_or_branch!(step_obj, cnode)
        end
    else
        cnode.state = :Infeasible
    end
    internal_model = internalmodel(m.model)
    if hasmethod(MathProgBase.freemodel!, Tuple{typeof(internal_model)})
        MathProgBase.freemodel!(internal_model)
    end
    return cnode.state
end

"""
    branch!(m, opts, step_obj, counter, disc2var_idx; temp=false)

Branch a node by using x[idx] <= floor(x[idx]) and x[idx] >= ceil(x[idx])
Solve both nodes and set current node state to done.
"""
function branch!(m, opts, step_obj, counter, disc2var_idx; temp=false)
    ps = opts.log_levels
    node = step_obj.node
    vidx = step_obj.var_idx

    start = time()
    # it might be already branched on
    if !temp && node.state != :Branch
        for cnode in [step_obj.l_nd,step_obj.r_nd]
            if cnode.state == :Branch || cnode.state == :Integral
                push_integral_or_branch!(step_obj, cnode)
            end
        end
        return step_obj.l_nd,step_obj.r_nd
    end

    l_nd_u_var = copy(node.u_var)
    r_nd_l_var = copy(node.l_var)
    l_nd_u_var[vidx] = floor(node.solution[vidx])
    r_nd_l_var[vidx] = ceil(node.solution[vidx])

    if opts.debug
        path_l = copy(node.path)
        path_r = copy(node.path)
        push!(path_l,node)
        push!(path_r,node)
    else
        path_l = []
        path_r = []
    end
    l_nd = new_left_node(node, l_nd_u_var; path=path_l)
    r_nd = new_right_node(node, r_nd_l_var; path=path_r)

    # save that this node branches on this particular variable
    node.var_idx = vidx

    check_print(ps,[:All,:FuncCall]) && println("branch")

    if !temp
        step_obj.l_nd = l_nd
        step_obj.r_nd = r_nd
        node.state = :Done
    end

    start_process = time()
    l_state = process_node!(m, step_obj, l_nd, disc2var_idx, temp)
    r_state = process_node!(m, step_obj, r_nd, disc2var_idx, temp)
    node_time = time() - start_process

    if !temp
        step_obj.node_branch_time += node_time
    end

    branch_strat = opts.branch_strategy

    if check_print(ps,[:All])
        println("State of left node: ", l_state)
        println("State of right node: ", r_state)
        println("l sol: ", l_nd.solution)
        println("r sol: ", r_nd.solution)
    end

    if !temp
        step_obj.branch_time += time()-start
    end

    return l_nd,r_nd
end

"""
    update_incumbent!(tree::BnBTreeObj, node::BnBNode)

Get's called if new integral solution was found.
Check whether it's a new incumbent and update if necessary
"""
function update_incumbent!(tree::BnBTreeObj, node::BnBNode)
    ps = tree.options.log_levels
    check_print(ps,[:All,:FuncCall]) && println("update_incumbent")

    factor = tree.obj_fac
    if !isdefined(tree,:incumbent) || factor*node.best_bound > factor*tree.incumbent.objval
        objval = node.best_bound
        solution = copy(node.solution)
        status = :Optimal
        tree.incumbent = Incumbent(objval, solution, status, tree.best_bound)
        if !tree.options.all_solutions
            bound!(tree)
        end
        return true
    end

    return false
end


"""
    bound!(tree::BnBTreeObj)
"""
function bound!(tree::BnBTreeObj)
    function isbetter(n)
        return f*n.best_bound > f*incumbent_val
    end
    incumbent_val = tree.incumbent.objval
    f = tree.obj_fac
    filter!(isbetter, tree.branch_nodes)
end

"""
    add_incumbent_constr(m, incumbent)

Add a constraint >=/<= incumbent
"""
function add_incumbent_constr(m, incumbent)
    obj_expr = MathProgBase.obj_expr(m.d)
    if m.obj_sense == :Min
        obj_constr = Expr(:call, :<=, obj_expr, incumbent.objval)
    else
        obj_constr = Expr(:call, :>=, obj_expr, incumbent.objval)
    end
    Juniper.expr_dereferencing!(obj_constr, m.model)
    # TODO: Change RHS instead of adding new (doesn't work for NL constraints atm)
    JuMP.addNLconstraint(m.model, obj_constr)
end

"""
    add_obj_epsilon_constr(tree)

Add a constraint obj ≦ (1+ϵ)*LB or obj ≧ (1-ϵ)*UB
"""
function add_obj_epsilon_constr(tree)
    # add constr for objval
    if tree.options.obj_epsilon > 0
        ϵ = tree.options.obj_epsilon
        obj_expr = MathProgBase.obj_expr(tree.m.d)
        if tree.m.obj_sense == :Min
            obj_constr = Expr(:call, :<=, obj_expr, (1+ϵ)*tree.m.objval)
        else
            obj_constr = Expr(:call, :>=, obj_expr, (1-ϵ)*tree.m.objval)
        end
        Juniper.expr_dereferencing!(obj_constr, tree.m.model)
        JuMP.addNLconstraint(tree.m.model, obj_constr)
        tree.m.ncuts += 1
    end
end

"""
    get_next_branch_node!(tree)

Get the next branch node (sorted by best bound)
Return true,step_obj if there is a branch node and
false, nothing otherwise
"""
function get_next_branch_node!(tree)
    if length(tree.branch_nodes) == 0
        return false, false, nothing
    end
    bvalue, nidx = findmax([tree.obj_fac*n.best_bound for n in tree.branch_nodes])

    trav_strat = tree.options.traverse_strategy
    if trav_strat == :BFS
        # use the one with highest depth
        _value, nidx = findmax([if isapprox(tree.obj_fac*n.best_bound, bvalue) n.level else -Inf end for n in tree.branch_nodes])
    end

    if trav_strat == :DFS || (trav_strat == :DBFS && !isdefined(tree,:incumbent))
        _value, nidx = findmax([n.level for n in tree.branch_nodes])
    end

    tree.best_bound = tree.obj_fac*bvalue
    bbreak = isbreak_mip_gap(tree)
    if bbreak
        return false, true, nothing
    end

    node = tree.branch_nodes[nidx]
    deleteat!(tree.branch_nodes, nidx)

    return true, false, new_default_step_obj(tree.m,node)
end


"""
    one_branch_step!(m1, incumbent, opts, step_obj, disc2var_idx, gains, counter)

Get a branch variable using the specified strategy and branch on the node in step_obj
using that variable. Return the new updated step_obj
"""
function one_branch_step!(m1, incumbent, opts, step_obj, disc2var_idx, gains, counter)
    if m1 == nothing
        global m
        global is_newincumbent
        if opts.incumbent_constr && incumbent != nothing && is_newincumbent
            is_newincumbent = false
            add_incumbent_constr(m, incumbent)
        end
    else
        m = m1
    end

    node = step_obj.node
    step_obj.counter = counter

# get branch variable
    node_idx_start = time()
    get_branching_disc_idx!(m, step_obj, opts, disc2var_idx, gains, counter)   
    step_obj.node_idx_time = time()-node_idx_start
    # if no variable got selected might be true that all variables are already type correct
    # node.solution can be updated if one child is infeasible and the other optimal (can result in discrete)
    if step_obj.var_idx == 0 && are_type_correct(step_obj.node.solution, m.var_type, disc2var_idx, opts.atol)
        push!(step_obj.integral, node)
    else
        if step_obj.state != :GlobalInfeasible && step_obj.state != :LocalInfeasible
            @assert step_obj.var_idx != 0
            branch!(m, opts, step_obj, counter, disc2var_idx)
        end
    end
    return step_obj
end

"""
    upd_time_obj!(time_obj, step_obj)

Add step_obj times to time_obj
"""
function upd_time_obj!(time_obj, step_obj)
    time_obj.solve_leaves_get_idx += step_obj.node_idx_time
    time_obj.solve_leaves_branch += step_obj.node_branch_time
    time_obj.branch += step_obj.branch_time
    time_obj.get_idx += step_obj.idx_time
    time_obj.upd_gains += step_obj.upd_gains_time
end

"""
    upd_tree_obj!(tree, step_obj, time_obj)

Update the tree obj like new incumbent or new branch nodes using the step_obj
Return true if it's the end of the algorithm (checking different break rules)
"""
function upd_tree_obj!(tree, step_obj, time_obj)
    node = step_obj.node
    still_running = true

    if step_obj.node.level+1 > tree.m.nlevels
        tree.m.nlevels = step_obj.node.level+1
    end

    if step_obj.state == :GlobalInfeasible
        # if there is no incumbent yet
        if !isdefined(tree,:incumbent)
            tree.incumbent = Incumbent(NaN, zeros(tree.m.num_var), :Infeasible, NaN)
        end # it will terminate and use the current solution as optimal (might want to rerun as an option)
        still_running = false
    end

    if still_running
        upd_gains_step!(tree, step_obj)
    end

    bbreak = upd_integral_branch!(tree, step_obj)
    if bbreak
        still_running = false
    end

    upd_time_obj!(time_obj, step_obj)
    return !still_running
end

"""
    solve_sequential(tree,
        last_table_arr,
        time_bnb_solve_start,
        fields,
        field_chars,
        time_obj)

Run branch and bound on a single processor
"""
function solve_sequential(tree,
    last_table_arr,
    time_bnb_solve_start,
    fields,
    field_chars,
    time_obj)

    m = tree.m
    opts = tree.options
    disc2var_idx = tree.disc2var_idx
    counter = 0
    ps = tree.options.log_levels

    dictTree = Dict{Any,Any}()
    while true
        # the _ is only needed for parallel
        exists, _, step_obj = get_next_branch_node!(tree)
        !exists && break
        isbreak_after_step!(tree) && break
        counter += 1
        if isdefined(tree,:incumbent)
            step_obj = one_branch_step!(m, tree.incumbent, opts, step_obj, disc2var_idx, tree.obj_gain, counter)
        else
            step_obj = one_branch_step!(m, nothing, opts, step_obj, disc2var_idx, tree.obj_gain, counter)
        end
        m.nnodes += 2 # two nodes explored per branch
        node = step_obj.node


        bbreak = upd_tree_obj!(tree,step_obj,time_obj)
        tree.options.debug && (dictTree = push_step2treeDict!(dictTree,step_obj))

        if check_print(ps,[:Table])
            last_table_arr = print_table(1,tree,node,step_obj,time_bnb_solve_start,fields,field_chars;last_arr=last_table_arr)
        end

        if bbreak
            break
        end
    end

    tree.options.debug && (tree.m.debugDict[:tree] = dictTree)
    return counter
end

function sendto(p::Int; args...)
    for (nm, val) in args
        @spawnat(p, Core.eval(Juniper, Expr(:(=), nm, val)))
    end
end

function dummysolve()
    global m
    solve(m.model)
end

"""
    pmap(f, tree, last_table_arr, time_bnb_solve_start,
        fields, field_chars, time_obj)

Run the solving steps on several processors
"""
function pmap(f, tree, last_table_arr, time_bnb_solve_start,
    fields, field_chars, time_obj)
    np = nprocs()  # determine the number of processes available
    if tree.options.processors+1 < np
        np = tree.options.processors+1
    end

    # function to produce the next work item from the queue.
    # in this case it's just an index.
    ps = tree.options.log_levels
    still_running = true
    run_counter = 0
    counter = 0

    for p=2:np
        VERSION > v"0.7.0-" ? (seed = Random.seed!) : (seed = srand)
        remotecall_fetch(seed, p, 1)
        sendto(p, m=tree.m)
        sendto(p, is_newincumbent=false)
    end

    for p=3:np
        remotecall(dummysolve, p)
    end

    proc_counter = zeros(np)

    dictTree = Dict{Any,Any}()

    branch_strat = tree.options.branch_strategy
    opts = tree.options
    @sync begin
        for p=1:np
            if p != myid() || np == 1
                @async begin
                    while true
                        exists, bbreak, step_obj = get_next_branch_node!(tree)
                        if bbreak
                            still_running = false
                            break
                        end

                        while !exists && still_running
                            sleep(0.1)
                            exists, bbreak, step_obj = get_next_branch_node!(tree)
                            exists && break
                            if bbreak
                                still_running = false
                                break
                            end
                        end
                        if !still_running
                            break
                        end

                        if isbreak_after_step!(tree)
                            still_running = false
                            break
                        end

                        run_counter += 1
                        counter += 1
                        if isdefined(tree,:incumbent)
                            step_obj = remotecall_fetch(f, p, nothing, tree.incumbent, tree.options, step_obj,
                                                        tree.disc2var_idx, tree.obj_gain, counter)
                        else
                            step_obj = remotecall_fetch(f, p, nothing, nothing, tree.options, step_obj,
                            tree.disc2var_idx, tree.obj_gain, counter)
                        end
                        tree.m.nnodes += 2 # two nodes explored per branch
                        run_counter -= 1

                        !still_running && break

                        bbreak = upd_tree_obj!(tree,step_obj,time_obj)
                        tree.options.debug && (dictTree = push_step2treeDict!(dictTree,step_obj))

                        if run_counter == 0 && length(tree.branch_nodes) == 0
                            still_running = false
                        end

                        if bbreak
                            still_running = false
                        end

                        if check_print(ps,[:Table])
                            if length(tree.branch_nodes) > 0
                                bvalue, nidx = findmax([tree.obj_fac*n.best_bound for n in tree.branch_nodes])
                                tree.best_bound = tree.obj_fac*bvalue
                            end
                            last_table_arr = print_table(p,tree,step_obj.node,step_obj,time_bnb_solve_start,fields,field_chars;last_arr=last_table_arr)
                        end

                        if !still_running
                            break
                        end
                    end
                end
            end
        end
    end
    tree.options.debug && (tree.m.debugDict[:tree] = dictTree)
    return counter
end

"""
    solvemip(tree::BnBTreeObj)

Solve the MIP part of a problem given by BnBTreeObj using branch and bound.
 - Identify the node to branch on
 - Get variable to branch on
 - Solve subproblems
"""
function solvemip(tree::BnBTreeObj)
    time_obj = init_time_obj()
    time_bnb_solve_start = time()

    ps = tree.options.log_levels

    # check if already integral
    if are_type_correct(tree.m.solution,tree.m.var_type,tree.disc2var_idx, tree.options.atol)
        tree.nsolutions = 1
        objval = getobjectivevalue(tree.m.model)
        sol = getvalue(tree.m.x)
        bbound = getobjectivebound(tree.m.model)
        tree.incumbent = Incumbent(objval,sol,:Optimal,bbound)
        return tree.incumbent
    end

    # check if incumbent and if mip gap already fulfilled (i.e found by fp)
    if isbreak_mip_gap(tree)
        return tree.incumbent
    end

    last_table_arr = []
    fields = []
    field_chars = []
    # Print table init
    if check_print(ps,[:Table])
        fields, field_chars = get_table_config(tree.options)
        print_table_header(fields,field_chars)
    end


    check_print(ps,[:All,:FuncCall]) && println("Solve Tree")

    branch_strat = tree.options.branch_strategy

    add_obj_epsilon_constr(tree)

    # use pmap if more then one processor
    if tree.options.processors > 1 || tree.options.force_parallel
        counter = pmap(Juniper.one_branch_step!,tree,
            last_table_arr,
            time_bnb_solve_start,
            fields,
            field_chars,
            time_obj)
    else
        counter = solve_sequential(tree,
            last_table_arr,
            time_bnb_solve_start,
            fields,
            field_chars,
            time_obj)
    end

    if !isdefined(tree,:incumbent)
        # infeasible
        tree.incumbent = Incumbent(NaN, zeros(tree.m.num_var), :Infeasible, tree.best_bound)
    end

    # update best bound in incumbent
    tree.incumbent.best_bound = tree.best_bound

    if tree.options.obj_epsilon != 0 && tree.incumbent.status == :Infeasible
        @warn "Maybe only infeasible because of obj_epsilon."
    end

    if !isnan(tree.options.best_obj_stop)
        inc_val = tree.incumbent.objval
        bos = tree.options.best_obj_stop
        sense = tree.m.obj_sense
        if (sense == :Min && inc_val > bos) || (sense == :Max && inc_val < bos)
            @warn "best_obj_gap couldn't be reached."
        end
    end

    if length(tree.branch_nodes) > 0
        bvalue, nidx = findmax([tree.obj_fac*n.best_bound for n in tree.branch_nodes])
        tree.incumbent.best_bound = tree.obj_fac*bvalue
    else
        if !isnan(tree.incumbent.objval)
            tree.incumbent.best_bound = tree.incumbent.objval
        end
    end

    tree.m.nbranches = counter

    time_bnb_solve = time()-time_bnb_solve_start
    check_print(ps,[:Table]) && println("")
    check_print(ps,[:All,:Info]) && println("#branches: ", counter)

    tree.options.debug && debug_set_tree_obj_gain!(tree)
    check_print(ps,[:All,:Timing]) && print_final_timing(time_bnb_solve, time_obj)

    return tree.incumbent
end