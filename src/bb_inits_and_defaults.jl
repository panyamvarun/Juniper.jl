function init(start_time, m::JuniperProblem; inc_sol = nothing, inc_obj = nothing)
    hash_val = string(hash(hcat(m.l_var,m.u_var)))
    node = BnBNode(1, 1, m.l_var, m.u_var, m.solution, 0, :Branch, m.status, m.objval,[],hash_val)
    obj_gain_m = zeros(m.num_disc_var)
    obj_gain_p = zeros(m.num_disc_var)
    obj_gain_mc = zeros(Int64, m.num_disc_var)
    obj_gain_pc = zeros(Int64, m.num_disc_var)
    obj_gain_inf = zeros(Int64, m.num_disc_var)
    obj_gain = GainObj(obj_gain_m, obj_gain_p, obj_gain_mc, obj_gain_pc, obj_gain_inf)
    disc2var_idx = zeros(m.num_disc_var)
    var2disc_idx = zeros(m.num_var)
    int_i = 1
    for i=1:m.num_var
        if m.var_type[i] != :Cont
            disc2var_idx[int_i] = i
            var2disc_idx[i] = int_i
            int_i += 1
        end
    end
    factor = 1
    if m.obj_sense == :Min
        factor = -1
    end
    bnbTree = BnBTreeObj()
    bnbTree.m           = m
    bnbTree.obj_gain    = obj_gain
    bnbTree.disc2var_idx = disc2var_idx
    bnbTree.var2disc_idx = var2disc_idx
    bnbTree.options     = m.options
    bnbTree.obj_fac     = factor
    bnbTree.start_time  = start_time
    bnbTree.nsolutions  = 0
    bnbTree.branch_nodes = [node]
    bnbTree.best_bound  = m.objval

    if inc_sol != nothing
        bnbTree.incumbent = Incumbent(inc_obj, inc_sol, MOI.LOCALLY_SOLVED, m.objval)
        bnbTree.nsolutions += 1
        if m.options.incumbent_constr
            add_incumbent_constr(m,bnbTree.incumbent)
            m.ncuts += 1
        end
    end

    return bnbTree
end

function new_default_node(idx, level, l_var, u_var, solution;
                            var_idx=0, state=:Solve, relaxation_state=MOI.OPTIMIZE_NOT_CALLED, best_bound=NaN, path=[])

    l_var = copy(l_var)
    u_var = copy(u_var)
    solution = copy(solution)
    hash_val = string(hash(hcat(l_var,u_var)))
    return BnBNode(idx, level, l_var, u_var, solution, var_idx, state, relaxation_state, best_bound, path, hash_val)
end

function new_left_node(node, u_var;
                       var_idx=0, state=:Solve, relaxation_state=MOI.OPTIMIZE_NOT_CALLED, best_bound=NaN, path=[])
    l_var = copy(node.l_var)
    u_var = copy(u_var)
    solution = NaN*ones(length(node.solution))
    hash_val = string(hash(hcat(l_var,u_var)))
    return BnBNode(node.idx*2, node.level+1, l_var, u_var, solution, var_idx, state, relaxation_state, best_bound, path, hash_val)
end

function new_right_node(node, l_var;
                       var_idx=0, state=:Solve, relaxation_state=MOI.OPTIMIZE_NOT_CALLED, best_bound=NaN, path=[])
    l_var = copy(l_var)
    u_var = copy(node.u_var)
    solution = NaN*ones(length(node.solution))
    hash_val = string(hash(hcat(l_var,u_var)))
    return BnBNode(node.idx*2+1, node.level+1, l_var, u_var, solution, var_idx, state, relaxation_state, best_bound, path, hash_val)
end

function init_time_obj()
    return TimeObj(0.0,0.0,0.0,0.0,0.0)
end

function new_default_step_obj(m,node)
    gains_m = zeros(m.num_disc_var)
    gains_mc = zeros(Int64, m.num_disc_var)
    gains_p = zeros(m.num_disc_var)
    gains_pc = zeros(Int64, m.num_disc_var)
    gains_inf = zeros(Int64, m.num_disc_var)
    gains = GainObj(gains_m, gains_p, gains_mc, gains_pc, gains_inf)
    idx_time = 0.0
    node_idx_time = 0.0
    upd_gains_time = 0.0
    node_branch_time = 0.0
    branch_time = 0.0
    step_obj = StepObj()
    step_obj.node             = node
    step_obj.var_idx          = 0
    step_obj.state            = :None
    step_obj.nrestarts        = 0
    step_obj.gain_gap         = 0.0
    step_obj.obj_gain         = gains
    step_obj.idx_time         = idx_time
    step_obj.node_idx_time    = node_idx_time
    step_obj.upd_gains_time   = upd_gains_time
    step_obj.node_branch_time = node_branch_time
    step_obj.branch_time      = branch_time
    step_obj.integral         = []
    step_obj.branch           = []
    step_obj.counter          = 0
    step_obj.upd_gains        = :None
    step_obj.strong_int_vars  = Int64[]
    return step_obj
end

function init_juniper_problem!(jp::JuniperProblem, model::MOI.AbstractOptimizer)
    num_variables = length(model.variable_info)
    num_linear_le_constraints = length(model.linear_le_constraints)
    num_linear_ge_constraints = length(model.linear_ge_constraints)
    num_linear_eq_constraints = length(model.linear_eq_constraints)
    num_quadratic_le_constraints = length(model.quadratic_le_constraints)
    num_quadratic_ge_constraints = length(model.quadratic_ge_constraints)
    num_quadratic_eq_constraints = length(model.quadratic_eq_constraints)

    jp.status = MOI.OPTIMIZE_NOT_CALLED
    jp.has_nl_objective = model.nlp_data.has_objective
    jp.nlp_evaluator = model.nlp_data.evaluator
    jp.objective = model.objective

    jp.objval = NaN
    jp.best_bound = NaN
    jp.solution = Float64[]
    jp.nsolutions = 0
    jp.solutions = []
    jp.num_disc_var = 0
    jp.nintvars = 0
    jp.nbinvars = 0
    jp.nnodes = 1 # is set to one for the root node
    jp.ncuts = 0
    jp.nbranches = 0
    jp.nlevels = 1
    jp.relaxation_time = 0.0

    jp.start_time = time()

    jp.nl_solver = model.options.nl_solver
    nl_vec_opts = Vector{Tuple}()
    for arg in model.options.nl_solver.kwargs
        if isa(arg, Pair)
            push!(nl_vec_opts, (arg.first, arg.second))
        else # is a tuple in v0.6
            push!(nl_vec_opts, arg)
        end
    end

    jp.nl_solver_options = nl_vec_opts
    println("typeof: nl_solver_options ", typeof(nl_vec_opts))

    if model.options.mip_solver != nothing
        jp.mip_solver = model.options.mip_solver
    end
    jp.options = model.options    
    if model.sense == MOI.MIN_SENSE 
        jp.obj_sense = :Min
    else
        jp.obj_sense = :Max
    end
    jp.l_var = info_array_of_variables(model.variable_info, :lower_bound)
    jp.u_var = info_array_of_variables(model.variable_info, :upper_bound)
    integer_bool_arr = info_array_of_variables(model.variable_info, :is_integer)
    binary_bool_arr = info_array_of_variables(model.variable_info, :is_binary)
    jp.num_disc_var = sum(integer_bool_arr)+sum(binary_bool_arr)
    jp.num_var = length(model.variable_info)
    jp.var_type = [:Cont for i in 1:jp.num_var]
    jp.var_type[integer_bool_arr .== true] .= :Int
    jp.var_type[binary_bool_arr .== true] .= :Bin
    jp.disc2var_idx = zeros(jp.num_disc_var)
    jp.var2disc_idx = zeros(jp.num_var)
    int_i = 1
    for i=1:jp.num_var
        if jp.var_type[i] != :Cont
            jp.disc2var_idx[int_i] = i
            jp.var2disc_idx[i] = int_i
            int_i += 1
        end
    end
    jp.num_l_constr = num_linear_le_constraints+num_linear_ge_constraints+num_linear_eq_constraints
    jp.num_q_constr = num_quadratic_le_constraints+num_quadratic_ge_constraints+num_quadratic_eq_constraints
    jp.num_nl_constr = length(model.nlp_data.constraint_bounds)
    jp.num_constr = jp.num_l_constr+jp.num_q_constr+jp.num_nl_constr
end