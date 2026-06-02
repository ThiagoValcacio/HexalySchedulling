use cfw;
use math;
use gap as gap;

function solve(ls) {
    _nbLogs = 0;
    _timeToFeasible = nil;

    _schedLowerBound = nil;
    _schedUpperBound = nil;
    _schedGapAbs = nil;
    _schedGapPct = nil;

    ls.solve();

    _solveStatus = ls.solution.status;

    local nbObjs = ls.model.objectives.count();

    local obj_index = 3;

    if (ls.solution.objectiveBounds.count() > obj_index) {
        _schedLowerBound = 0 + ls.solution.objectiveBounds[obj_index];
    }

    if (_solveStatus == "FEASIBLE" || _solveStatus == "OPTIMAL") {
        _schedUpperBound = 0 + ls.model.objectives[obj_index].value;
    }

    if (_schedLowerBound != nil && _schedUpperBound != nil) {
        _schedGapAbs = _schedUpperBound - _schedLowerBound;

        local denom = (_schedUpperBound >= 0) ? _schedUpperBound : -_schedUpperBound;

        if (denom > 1e-9) {
            _schedGapPct = 100 * _schedGapAbs / denom;
        }
    }

    println(" ");
    println("========== BOUNDS DO SCHEDULING ==========");
    println("Mecanico: ", m_opt);
    println("Status: ", _solveStatus);
    println("Lower Bound: ", _schedLowerBound);
    println("Upper Bound: ", _schedUpperBound);
    println("Gap Absoluto: ", _schedGapAbs);
    println("Gap Percentual: ", _schedGapPct, "%");
    println("==========================================");
    println(" ");

    logFunction(ls, nil);
}

function run(ls, m, S_JOBS_MECHANIC, lb_input, ub_input, use_warm_start, WARM_START_SCHED) {

    ls.addCallback("TIME_TICKED", logFunction);
    ls.addCallback("TIME_TICKED", stoppingCriterion);
    ls.param.verbosity = 0;

    m_opt = m;
    S_JOBS_MECHANIC_OPT = S_JOBS_MECHANIC;
    lb_opt = lb_input;
    ub_opt = ub_input;

    model();

    println(" ");
    println("================= SEQUENCIANDO PARA O MECANICO " + m + " ==================");
    println(" ");
    println(" ");

    for[j in S_JOBS_MECHANIC_OPT] {
        if (cfw.k_task_type[j] == "Cliente") {
            b_type_task_client[j] = true;
        } else {
            b_type_task_client[j] = false;
        }
    }

    GAP_ASSIGN_SIZE_TOTAL <- sum[j in S_JOBS_MECHANIC_OPT](
        gap.t_time_processing_opt[j] * GAP_ASSIGN[j]
    );

    minimize GAP_ASSIGN_CLIENT_TOTAL;
    minimize GAP_ASSIGN_TOTAL;
    minimize GAP_ASSIGN_SIZE_TOTAL;
    
    obj <- sum[j in S_JOBS_MECHANIC_OPT][t in 0...gap.n_mechanicslots]((t + gap.t_time_processing_opt[j] - (b_type_task_client[j] ? gap.n_slots_arrival_job[j] : t)) * B_ASSIGNMENT_SCHED[j][gap.Hours[t]]);
    minimize obj;

    // Aplica lower bound, se existir
    if (lb_opt != nil) {
        local st_lb <- obj >= lb_opt;
        st_lb.name = "Lower bound informado para o scheduling";
        constraint st_lb;
    }

    // Aplica upper bound, se existir
    if (ub_opt != nil) {
        local st_ub <- obj <= ub_opt;
        st_ub.name = "Upper bound informado para o scheduling";
        constraint st_ub;
    }

    // if (use_warm_start) {
    //     local st_no_gap <- GAP_ASSIGN_TOTAL == 0;
    //     st_no_gap.name = "Forca solucao sem slack no warm start";
    //     constraint st_no_gap;
    // }

    ls.model.close();

    if (use_warm_start) {
        for[j in S_JOBS_MECHANIC_OPT][t in 0...gap.n_mechanicslots] {
            B_ASSIGNMENT_SCHED[j][gap.Hours[t]].value =
                WARM_START_SCHED[j][gap.Hours[t]];
        }

        for[j in S_JOBS_MECHANIC_OPT] {
            GAP_ASSIGN[j].value = 0;
        }
    }

    _schedLowerBound = nil;
    _schedUpperBound = nil;
    _obj_value = nil;

    solve(ls);
    postSolve();

    local obj_index = 3;

    if (ls.solution.objectiveBounds.count() > obj_index) {
        _schedLowerBound = 0 + ls.solution.objectiveBounds[obj_index];
    }

    if (_solveStatus == "FEASIBLE" || _solveStatus == "OPTIMAL") {
        _schedUpperBound = 0 + ls.model.objectives[obj_index].value;
        _obj_value = _schedUpperBound;
    }

    println("STATUS SCHED: ", _solveStatus);
    println("LOWER BOUND SCHED: ", _schedLowerBound);

    if (_schedUpperBound != nil) {
        println("UPPER BOUND SCHED: ", _schedUpperBound);
    }

    if (ls.solution.status == "INCONSISTENT") {
        iis = ls.computeInconsistency();
        println(iis);
    }
}

function model() {

    for[t in 0...gap.n_mechanicslots][j in cfw.Tasks] {
        B_ASSIGNMENT_SCHED[j][gap.Hours[t]] <- bool();
    }

    for[j in cfw.Tasks] {
        GAP_ASSIGN[j] <- float(0, 1);
    }

    for[j in S_JOBS_MECHANIC_OPT] {
        local st_mandatory_assign_sch <- sum[t in 0...gap.n_mechanicslots](B_ASSIGNMENT_SCHED[j][gap.Hours[t]]) == 1 - GAP_ASSIGN[j];
        st_mandatory_assign_sch.name = "Atribuicao da task " + j + " eh obrigatoria para o " + m_opt;
        constraint st_mandatory_assign_sch;
    }

    GAP_ASSIGN_CLIENT_TOTAL <- sum[j in S_JOBS_MECHANIC_OPT : cfw.k_task_type[j] == "Cliente"](
        GAP_ASSIGN[j]
    );

    GAP_ASSIGN_TOTAL <- sum[j in S_JOBS_MECHANIC_OPT](GAP_ASSIGN[j]);

    for[tau in 0...gap.n_mechanicslots] {
        local st_precedence <- sum[j in S_JOBS_MECHANIC_OPT][t in max(0, tau - gap.t_time_processing_opt[j] + 1)..min(tau, gap.n_total_slots - gap.t_time_processing_opt[j])]
            (B_ASSIGNMENT_SCHED[j][gap.Hours[t]]) <= 1;
        st_precedence.name = "Restricao de precedencia para o periodo " + tau;
        constraint st_precedence;
    }

    for[j in S_JOBS_MECHANIC_OPT][t in 0...gap.n_mechanicslots : !gap.b_can_execute[j][t]] {
        constraint B_ASSIGNMENT_SCHED[j][gap.Hours[t]] == 0;
    }

    for[j in S_JOBS_MECHANIC_OPT][t in 0...gap.n_mechanicslots] {
        B_TOTAL_ASSIGNMENT[j][gap.Hours[t]] = false;
    }

    for[j in S_JOBS_MECHANIC_OPT][tau in 0...gap.n_mechanicslots] {
        B_TOTAL_ASSIGNMENT[j][gap.Hours[tau]] <-
            sum[t in max(0, tau - gap.t_time_processing_opt[j] + 1)
                ..min(tau, gap.n_mechanicslots - gap.t_time_processing_opt[j])]
                (B_ASSIGNMENT_SCHED[j][gap.Hours[t]]);
    }

    for[tau in 0...gap.n_mechanicslots] {
        B_MECHANIC_OCCUPIED[gap.Hours[tau]] <-
            sum[j in S_JOBS_MECHANIC_OPT]
                (B_TOTAL_ASSIGNMENT[j][gap.Hours[tau]]);
    }

    constraint sum[tau in 18...gap.n_mechanicslots]
        (1 - B_MECHANIC_OCCUPIED[gap.Hours[tau]]) >= 6;

    for[j in S_JOBS_MECHANIC_OPT][t in 0...gap.n_mechanicslots : t + gap.t_time_processing_opt[j] > gap.n_mechanicslots] {
        local st_late_start <- B_ASSIGNMENT_SCHED[j][gap.Hours[t]] == 0;
        st_late_start.name = "Task " + j + " nao pode iniciar tarde demais no slot " + t;
        constraint st_late_start;
    }
}

function postSolve() {

    for[j in S_JOBS_MECHANIC_OPT][t in 0...gap.n_mechanicslots] {
        B_ASSIGNMENT_SCHED_OPT[j][gap.Hours[t]] = (B_ASSIGNMENT_SCHED[j][gap.Hours[t]].value) ? B_ASSIGNMENT_SCHED[j][gap.Hours[t]].value : 0;
        // println (j, " para ", m_opt, " no tempo ", gap.Hours[t], " com valor = ", B_ASSIGNMENT_SCHED[j][gap.Hours[t]].value);
    }

    for[j in S_JOBS_MECHANIC_OPT][t in 0...gap.n_mechanicslots] {
        if (B_ASSIGNMENT_SCHED_OPT[j][gap.Hours[t]]) {
            println (j, " para ", m_opt, " no tempo ", gap.Hours[t], " com valor = ", B_ASSIGNMENT_SCHED[j][gap.Hours[t]].value);
        }
    }

    println();
    println("Tasks do tipo cliente:");
    for[j in S_JOBS_MECHANIC_OPT : b_type_task_client[j]] {
        println(j);
    }
    println();

    _schedRemainingSlots = nil;

    _schedUsedSlots = 0;

    for[j in S_JOBS_MECHANIC_OPT][t in 0...gap.n_mechanicslots : B_ASSIGNMENT_SCHED[j][gap.Hours[t]].value] {
        _schedUsedSlots += gap.t_time_processing_opt[j];
    }

    _schedRemainingSlots = gap.n_mechanicslots - _schedUsedSlots;

    for[j in cfw.Tasks] {
        GAP_ASSIGN_OPT[j] = GAP_ASSIGN[j].value;
        if (GAP_ASSIGN[j].value == 1) {
            println ("Job complicante: ", j);
        }
    }
}

function logFunction(ls, cbTypes) {
    local stats = ls.statistics;
    local time = stats.runningTime;
    local sol = ls.solution;
    local valid = (sol.status == "FEASIBLE" || sol.status == "OPTIMAL");

    local nbObjs = ls.model.objectives.count();
    local objs[i in 0...nbObjs] = ls.model.objectives[i].value;

    if (_nbLogs % 50 == 0) {
        print("Time    ");
        for[i in 0...nbObjs-1] {
            print("Viol-",i+1,"    [Gap %]   ");
        }
        println("Obj       [Gap %]");
    }
    local str_time = ""+time;
    while(str_time.length() < 8) str_time = str_time + " ";

    local str_objs = "";
    for[i in 0...nbObjs] {
        local obj = (valid) ? math.round(ls.model.objectives[i].value*1e4) * 1e-4 : "Inf";
        local str_obj = ""+obj;
        while( str_obj.length() < 10) str_obj = str_obj + " ";
        str_objs = str_objs + str_obj;

        local obj_gap = (valid) ?  math.round(sol.objectiveGaps[i] * 1e4)*1e-2+ "%" : "Inf";
        local str_obj_gap = "["+obj_gap+"]";
        while(str_obj_gap.length() < 10) str_obj_gap = str_obj_gap + " ";
        str_objs = str_objs + str_obj_gap;
    }

    println(str_time,str_objs);
    _nbLogs += 1;
}

function stoppingCriterion(ls, cbTypes) {
    
    local stats = ls.statistics;
    local time = stats.runningTime;
    local sol = ls.solution;
    local feasible = (sol.status == "FEASIBLE" || sol.status == "OPTIMAL");

    local nbObjs = ls.model.objectives.count();
    local gaps[i in 0...nbObjs] = math.round(ls.solution.objectiveGaps[i] * 1e4) * 1e-2;
    local objs[i in 0...nbObjs] = ls.model.objectives[i].value;

    // Looking for feasibility;
    if (!feasible && time > 1000) ls.stop();

    // Register the time that the solution became feasible
    if (feasible && _timeToFeasible == nil) _timeToFeasible = time;

    // Minimizing OF
    if (feasible && (time - _timeToFeasible) > 10000) ls.stop();

}

function isFeasible() {
    return _solveStatus == "OPTIMAL" || _solveStatus == "FEASIBLE";
}